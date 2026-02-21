#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <status-name> [flow-name]"
  echo "Example: $0 PL-003 \"In Progress\" \"In Progress\""
  exit 1
fi

task_id="$1"
status_name="$2"
flow_name="${3:-$2}"

owner="justewg"
project_number="2"
project_id="PVT_kwHOAPt_Q84BPyyr"

fields_json="$(gh project field-list "$project_number" --owner "$owner" --format json)"
items_json="$(gh project item-list "$project_number" --owner "$owner" --limit 100 --format json)"

item_id="$(printf '%s' "$items_json" | jq -r --arg task "$task_id" '.items[] | select(."task ID" == $task) | .id')"
if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Task not found in project: $task_id"
  exit 1
fi

status_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Status") | .id')"
flow_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Flow") | .id')"

status_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$status_name" '.fields[] | select(.name=="Status") | .options[] | select(.name==$name) | .id'
)"
flow_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$flow_name" '.fields[] | select(.name=="Flow") | .options[] | select(.name==$name) | .id'
)"

if [[ -z "$status_option_id" || "$status_option_id" == "null" ]]; then
  echo "Status option not found: $status_name"
  exit 1
fi

if [[ -z "$flow_option_id" || "$flow_option_id" == "null" ]]; then
  echo "Flow option not found: $flow_name"
  exit 1
fi

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$status_field_id" \
  --single-select-option-id "$status_option_id" >/dev/null

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$flow_field_id" \
  --single-select-option-id "$flow_option_id" >/dev/null

echo "Updated $task_id: Status=$status_name, Flow=$flow_name"

