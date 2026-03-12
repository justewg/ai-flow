#!/usr/bin/env bash

# shellcheck shell=bash

: "${CODEX_DIR:?CODEX_DIR is required}"

STATE_TMP_DIR="${STATE_TMP_DIR:-$(codex_resolve_state_tmp_dir "$CODEX_DIR")}"
PROJECT_ISSUE_CACHE_FILE="${PROJECT_ISSUE_CACHE_FILE:-${CODEX_DIR}/project_issue_item_cache.json}"

mkdir -p "$STATE_TMP_DIR"

project_issue_cache_ensure() {
  if [[ ! -f "$PROJECT_ISSUE_CACHE_FILE" ]]; then
    printf '%s\n' '{"version":1,"items":{}}' > "$PROJECT_ISSUE_CACHE_FILE"
  fi
  if ! jq -e '.items and (.items | type == "object")' "$PROJECT_ISSUE_CACHE_FILE" >/dev/null 2>&1; then
    printf '%s\n' '{"version":1,"items":{}}' > "$PROJECT_ISSUE_CACHE_FILE"
  fi
}

project_issue_cache_get_field() {
  local task_id="$1"
  local field_name="$2"
  project_issue_cache_ensure
  jq -r --arg task "$task_id" --arg field "$field_name" '.items[$task][$field] // ""' "$PROJECT_ISSUE_CACHE_FILE" 2>/dev/null || true
}

project_issue_cache_upsert() {
  local task_id="$1"
  local item_id="${2:-}"
  local issue_number="${3:-}"
  local title="${4:-}"
  local status_name="${5:-}"
  local flow_name="${6:-}"
  local source_name="${7:-runtime}"
  local now_utc tmp_file

  [[ -n "$task_id" ]] || return 0

  project_issue_cache_ensure
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp_file="$(mktemp "${STATE_TMP_DIR}/project_issue_cache.XXXXXX")"

  jq \
    --arg task "$task_id" \
    --arg item_id "$item_id" \
    --arg issue_number "$issue_number" \
    --arg title "$title" \
    --arg status "$status_name" \
    --arg flow "$flow_name" \
    --arg source "$source_name" \
    --arg now "$now_utc" '
    .items[$task] = (
      (.items[$task] // {})
      + {
          task_id: $task,
          updated_at: $now,
          source: $source
        }
      + (if $item_id != "" then {item_id: $item_id} else {} end)
      + (if $issue_number != "" then {issue_number: $issue_number} else {} end)
      + (if $title != "" then {title: $title} else {} end)
      + (if $status != "" then {status: $status} else {} end)
      + (if $flow != "" then {flow: $flow} else {} end)
    )
  ' "$PROJECT_ISSUE_CACHE_FILE" > "$tmp_file"

  mv "$tmp_file" "$PROJECT_ISSUE_CACHE_FILE"
}

project_issue_cache_list_recent_status() {
  local status_name="$1"
  local max_age_sec="${2:-1800}"
  local now_epoch

  project_issue_cache_ensure
  now_epoch="$(date +%s)"

  jq -c \
    --arg status "$status_name" \
    --argjson now "$now_epoch" \
    --argjson max_age "$max_age_sec" '
    def ts:
      (. // "")
      | sub("\\.[0-9]+Z$"; "Z")
      | strptime("%Y-%m-%dT%H:%M:%SZ")
      | mktime;
    [
      .items
      | to_entries[]
      | .value
      | select((.status // "") == $status)
      | .age_sec = (
          try ($now - ((.updated_at | ts) // 0))
          catch ($max_age + 1)
        )
      | select(.age_sec >= 0 and .age_sec <= $max_age)
      | select((.item_id // "") != "" and (.issue_number // "") != "" and (.task_id // "") != "")
    ]
  ' "$PROJECT_ISSUE_CACHE_FILE"
}
