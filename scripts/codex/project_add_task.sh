#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 6 ]]; then
  echo "Usage: $0 <task-id> <title-file> <scope> <priority> [status] [flow]"
  echo "Example: $0 PL-014 .tmp/codex/project_new_title.txt V1+ P2 Todo Backlog"
  exit 1
fi

task_id="$1"
title_file="$2"
scope="$3"
priority="$4"
status_name="${5:-Todo}"
flow_name="${6:-Backlog}"

if [[ ! -f "$title_file" ]]; then
  echo "Title file not found: $title_file"
  exit 1
fi

title_text="$(<"$title_file")"
if [[ -z "$title_text" ]]; then
  echo "Title file is empty: $title_file"
  exit 1
fi

owner="justewg"
project_number="2"
project_id="PVT_kwHOAPt_Q84BPyyr"

full_title="${task_id} ${title_text}"
body="$(printf 'Scope: %s\nPriority: %s\nSource: TODO.md' "$scope" "$priority")"

item_json="$(
  gh project item-create "$project_number" \
    --owner "$owner" \
    --title "$full_title" \
    --body "$body" \
    --format json
)"
item_id="$(printf '%s' "$item_json" | jq -r '.id')"
if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Unable to create project item."
  exit 1
fi

fields_json="$(gh project field-list "$project_number" --owner "$owner" --format json)"

task_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Task ID") | .id')"
scope_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Scope") | .id')"
priority_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Priority") | .id')"
status_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Status") | .id')"
flow_field_id="$(printf '%s' "$fields_json" | jq -r '.fields[] | select(.name=="Flow") | .id')"

scope_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$scope" '.fields[] | select(.name=="Scope") | .options[] | select(.name==$name) | .id'
)"
priority_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$priority" '.fields[] | select(.name=="Priority") | .options[] | select(.name==$name) | .id'
)"
status_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$status_name" '.fields[] | select(.name=="Status") | .options[] | select(.name==$name) | .id'
)"
flow_option_id="$(
  printf '%s' "$fields_json" |
    jq -r --arg name "$flow_name" '.fields[] | select(.name=="Flow") | .options[] | select(.name==$name) | .id'
)"

for name in task_field_id scope_field_id priority_field_id status_field_id flow_field_id \
  scope_option_id priority_option_id status_option_id flow_option_id; do
  value="${!name}"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Missing field/option value: $name"
    exit 1
  fi
done

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$task_field_id" \
  --text "$task_id" >/dev/null

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$scope_field_id" \
  --single-select-option-id "$scope_option_id" >/dev/null

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$priority_field_id" \
  --single-select-option-id "$priority_option_id" >/dev/null

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

echo "Created project task: $task_id ($full_title)"

