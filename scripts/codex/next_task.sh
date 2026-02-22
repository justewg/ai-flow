#!/usr/bin/env bash
set -euo pipefail

# Выбор следующей задачи из GitHub Project:
# - Статус: Planned
# - Приоритет: P0 → P1 → P2 → P3 → ...
# - Вторичная сортировка: по номеру PL-xxx (возрастание)

project_id="PVT_kwHOAPt_Q84BPyyr"

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

json="$(gh api graphql -f query="$query" -F projectId="$project_id" -F itemsFirst=200)"

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
    | map(.pri_w = (if .priority=="P0" then 0 else if .priority=="P1" then 1 else if .priority=="P2" then 2 else if .priority=="P3" then 3 else 9 end))
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

