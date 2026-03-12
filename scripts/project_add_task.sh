#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_project_config

if [[ $# -lt 4 || $# -gt 6 ]]; then
  echo "Usage: $0 <task-id> <title-file> <scope> <priority> [status] [flow]"
  echo "Example: $0 PL-014 .flow/state/codex/default/project_new_title.txt V1+ P2 Backlog Backlog"
  exit 1
fi

task_id="$1"
title_file="$2"
scope="$3"
priority="$4"
status_name="${5:-Backlog}"
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

strip_quotes() {
  codex_strip_quotes "$1"
}

read_key_from_env_file() {
  codex_read_key_from_env_file "$1" "$2"
}

resolve_config_value() {
  codex_resolve_config_value "$1" "${2:-}"
}

owner="$PROJECT_OWNER"
project_number="$PROJECT_NUMBER"
project_id="$PROJECT_ID"

project_token="$(resolve_config_value "DAEMON_GH_PROJECT_TOKEN" "")"
if [[ -z "$project_token" ]]; then
  project_token="$(resolve_config_value "CODEX_GH_PROJECT_TOKEN" "")"
fi
project_token="$(printf '%s' "$project_token" | tr -d '\r\n')"

run_gh_retry_capture() {
  local out=""
  local err_file
  err_file="$(mktemp)"
  if [[ -n "$project_token" ]]; then
    if out="$(GH_TOKEN="$project_token" "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" "$@" 2>"$err_file")"; then
      if [[ -s "$err_file" ]]; then
        cat "$err_file" >&2
      fi
      rm -f "$err_file"
      printf '%s' "$out"
      return 0
    fi
  elif out="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" "$@" 2>"$err_file")"; then
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  fi
  local rc=$?
  if [[ -s "$err_file" ]]; then
    cat "$err_file" >&2
  fi
  rm -f "$err_file"
  printf '%s\n' "$out" >&2
  return "$rc"
}

set_single_select() {
  local item_id="$1"
  local field_id="$2"
  local option_id="$3"
  run_gh_retry_capture gh project item-edit \
    --id "$item_id" \
    --project-id "$project_id" \
    --field-id "$field_id" \
    --single-select-option-id "$option_id" >/dev/null
}

verify_status_flow() {
  local item_id="$1"
  local expected_status="$2"
  local expected_flow="$3"
  local item_json actual_status actual_flow

  item_json="$(
    run_gh_retry_capture \
      gh api graphql \
      -f query='
query($itemId: ID!) {
  node(id: $itemId) {
    ... on ProjectV2Item {
      id
      status: fieldValueByName(name: "Status") {
        __typename
        ... on ProjectV2ItemFieldSingleSelectValue { name }
      }
      flow: fieldValueByName(name: "Flow") {
        __typename
        ... on ProjectV2ItemFieldSingleSelectValue { name }
      }
    }
  }
}
' \
      -f itemId="$item_id"
  )"
  actual_status="$(printf '%s' "$item_json" | jq -r '.data.node.status.name // ""')"
  actual_flow="$(printf '%s' "$item_json" | jq -r '.data.node.flow.name // ""')"

  [[ "$actual_status" == "$expected_status" && "$actual_flow" == "$expected_flow" ]]
}

full_title="${task_id} ${title_text}"
body="$(printf 'Scope: %s\nPriority: %s\nSource: TODO.md' "$scope" "$priority")"

item_json="$(
  run_gh_retry_capture \
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

fields_json="$(run_gh_retry_capture gh project field-list "$project_number" --owner "$owner" --format json)"

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

run_gh_retry_capture gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$task_field_id" \
  --text "$task_id" >/dev/null

set_single_select "$item_id" "$scope_field_id" "$scope_option_id"
set_single_select "$item_id" "$priority_field_id" "$priority_option_id"
set_single_select "$item_id" "$status_field_id" "$status_option_id"
set_single_select "$item_id" "$flow_field_id" "$flow_option_id"

if verify_status_flow "$item_id" "$status_name" "$flow_name"; then
  echo "Created project task: $task_id ($full_title)"
  echo "VERIFIED_STATUS=$status_name"
  echo "VERIFIED_FLOW=$flow_name"
  exit 0
fi

for _ in 1 2 3; do
  sleep 1
  set_single_select "$item_id" "$status_field_id" "$status_option_id"
  set_single_select "$item_id" "$flow_field_id" "$flow_option_id"
  if verify_status_flow "$item_id" "$status_name" "$flow_name"; then
    echo "Created project task: $task_id ($full_title)"
    echo "VERIFIED_STATUS=$status_name"
    echo "VERIFIED_FLOW=$flow_name"
    exit 0
  fi
done

echo "Created project task but failed to verify final status/flow."
echo "ITEM_ID=$item_id"
echo "EXPECTED_STATUS=$status_name"
echo "EXPECTED_FLOW=$flow_name"
echo "VERIFY_FAILED=1"
exit 2
