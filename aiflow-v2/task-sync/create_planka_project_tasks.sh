#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_FILE="${SCRIPT_DIR}/planka_project_tasks.json"

if [[ ! -f "$PAYLOAD_FILE" ]]; then
  echo "Payload file not found: $PAYLOAD_FILE"
  exit 1
fi

PROJECT_NUMBER=2
PROJECT_OWNER='@me'
PROJECT_ID='PVT_kwHOAPt_Q84BPyyr'
TASK_ID_FIELD='PVTF_lAHOAPt_Q84BPyyrzg-Gaa4'
SCOPE_FIELD='PVTSSF_lAHOAPt_Q84BPyyrzg-Gaas'
FLOW_FIELD='PVTSSF_lAHOAPt_Q84BPyyrzg-Gaaw'
PRIORITY_FIELD='PVTSSF_lAHOAPt_Q84BPyyrzg-Gaa0'
STATUS_FIELD='PVTSSF_lAHOAPt_Q84BPyyrzg-GaSs'
SCOPE_V1PLUS='ba94c054'
PRIORITY_P1='0911d620'
STATUS_BACKLOG='69dc1846'
STATUS_DONE='98236657'
FLOW_BACKLOG='27f2ef16'
FLOW_DONE='697fc56c'

existing_json="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 300)"

jq -c '.[]' "$PAYLOAD_FILE" | while IFS= read -r row; do
  task_id="$(printf '%s' "$row" | jq -r '.task_id')"
  title_suffix="$(printf '%s' "$row" | jq -r '.title')"
  full_title="${task_id} ${title_suffix}"
  body="$(printf '%s' "$row" | jq -r '.body')"
  status_name="$(printf '%s' "$row" | jq -r '.status')"

  existing_item_id="$(printf '%s' "$existing_json" | jq -r --arg task "$task_id" '.items[] | select(."task ID" == $task) | .id' | head -n1)"
  if [[ -z "$existing_item_id" ]]; then
    create_json="$(gh project item-create "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --title "$full_title" --body "$body" --format json)"
    item_id="$(printf '%s' "$create_json" | jq -r '.id')"
    echo "CREATED $task_id $item_id"
  else
    item_id="$existing_item_id"
    echo "EXISTS $task_id $item_id"
  fi

  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$TASK_ID_FIELD" --text "$task_id" >/dev/null
  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$SCOPE_FIELD" --single-select-option-id "$SCOPE_V1PLUS" >/dev/null
  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$PRIORITY_FIELD" --single-select-option-id "$PRIORITY_P1" >/dev/null

  if [[ "$status_name" == "Done" ]]; then
    gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$STATUS_FIELD" --single-select-option-id "$STATUS_DONE" >/dev/null
    gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$FLOW_FIELD" --single-select-option-id "$FLOW_DONE" >/dev/null
  else
    gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$STATUS_FIELD" --single-select-option-id "$STATUS_BACKLOG" >/dev/null
    gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$FLOW_FIELD" --single-select-option-id "$FLOW_BACKLOG" >/dev/null
  fi

  echo "READY $task_id status=$status_name"
done
