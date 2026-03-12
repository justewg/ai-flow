#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_project_config

# Выбор следующей задачи из GitHub Project:
# - Статус: Planned
# - Приоритет: P0 → P1 → P2 → P3 → ...
# - Вторичная сортировка: по номеру PL-xxx (возрастание)

strip_quotes() {
  codex_strip_quotes "$1"
}

read_key_from_env_file() {
  codex_read_key_from_env_file "$1" "$2"
}

resolve_config_value() {
  codex_resolve_config_value "$1" "${2:-}"
}

project_id="$PROJECT_ID"

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
