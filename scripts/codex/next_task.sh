#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Выбор следующей задачи из GitHub Project:
# - Статус: Planned
# - Приоритет: P0 → P1 → P2 → P3 → ...
# - Вторичная сортировка: по номеру PL-xxx (возрастание)

project_id="PVT_kwHOAPt_Q84BPyyr"

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

read_key_from_env_file() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 1
  local raw
  raw="$(grep -E "^${key}=" "$file_path" | tail -n1 | cut -d'=' -f2- || true)"
  [[ -n "$raw" ]] || return 1
  strip_quotes "$raw"
}

resolve_config_value() {
  local key="$1"
  local default_value="${2:-}"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi

  local env_candidates=()
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" ]]; then
    env_candidates+=("${DAEMON_GH_ENV_FILE}")
  fi
  env_candidates+=("${ROOT_DIR}/.env")
  env_candidates+=("${ROOT_DIR}/.env.deploy")

  local env_file value
  for env_file in "${env_candidates[@]}"; do
    value="$(read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

  printf '%s' "$default_value"
}

project_token="$(resolve_config_value "DAEMON_GH_PROJECT_TOKEN" "")"
if [[ -z "$project_token" ]]; then
  project_token="$(resolve_config_value "CODEX_GH_PROJECT_TOKEN" "")"
fi
project_token="$(printf '%s' "$project_token" | tr -d '\r\n')"

query='
query($projectId: ID!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: $itemsFirst) {
        nodes {
          id
          content {
            __typename
            ... on DraftIssue { title }
            ... on Issue { title number }
            ... on PullRequest { title number }
          }
          taskId: fieldValueByName(name: "Task ID") {
            __typename
            ... on ProjectV2ItemFieldTextValue { text }
          }
          status: fieldValueByName(name: "Status") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
          priority: fieldValueByName(name: "Priority") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
          flow: fieldValueByName(name: "Flow") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
        }
      }
    }
  }
}
'

if [[ -n "$project_token" ]]; then
  json="$(GH_TOKEN="$project_token" gh api graphql -f query="$query" -F projectId="$project_id" -F itemsFirst=100)"
else
  json="$(gh api graphql -f query="$query" -F projectId="$project_id" -F itemsFirst=100)"
fi

# jq: фильтруем Planned и сортируем
candidate="$(
  printf '%s' "$json" | jq -r '
    .data.node.items.nodes
    | map({
        id,
        title: (.content.title // ""),
        task: (.taskId.text // ""),
        status: (.status.name // ""),
        priority: (.priority.name // ""),
        flow: (.flow.name // "")
      })
    | map(select(.status == "Planned"))
    | map(.pri_w = (
        if .priority=="P0" then 0
        elif .priority=="P1" then 1
        elif .priority=="P2" then 2
        elif .priority=="P3" then 3
        else 9
        end
      ))
    | map(.num = ((.task | capture("PL-(?<n>[0-9]+)").n // "999") | tonumber))
    | sort_by(.pri_w, .num)
    | .[0]'
  )"

if [[ -z "$candidate" || "$candidate" == "null" ]]; then
  echo "No Planned tasks found"
  exit 2
fi

task_id="$(printf '%s' "$candidate" | jq -r '.task')"
title="$(printf '%s' "$candidate" | jq -r '.title')"

echo "NEXT_TASK_ID=$task_id"
echo "NEXT_TITLE=$title"
