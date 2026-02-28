#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

project_id="${PROJECT_ID:-PVT_kwHOAPt_Q84BPyyr}"
project_number="${PROJECT_NUMBER:-2}"
project_owner="${PROJECT_OWNER:-@me}"
project_items_limit="${PROJECT_ITEMS_LIMIT:-200}"
repo="${GITHUB_REPO:-justewg/planka}"
repo_owner="${repo%%/*}"
repo_name="${repo#*/}"
trigger_status="${TRIGGER_STATUS:-Todo}"
target_status="${TARGET_STATUS:-In Progress}"
target_flow="${TARGET_FLOW:-In Progress}"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
dirty_gate_issue_file="${CODEX_DIR}/dirty_gate_issue_number.txt"
dirty_gate_issue_url_file="${CODEX_DIR}/dirty_gate_issue_url.txt"
dirty_gate_signature_file="${CODEX_DIR}/dirty_gate_signature.txt"
dirty_gate_comment_signature_file="${CODEX_DIR}/dirty_gate_comment_signature.txt"
dirty_gate_blocked_issue_file="${CODEX_DIR}/dirty_gate_blocked_issue_number.txt"
dirty_gate_blocked_title_file="${CODEX_DIR}/dirty_gate_blocked_issue_title.txt"
dirty_gate_override_signature_file="${CODEX_DIR}/dirty_gate_override_signature.txt"
dirty_gate_last_reply_id_file="${CODEX_DIR}/dirty_gate_last_reply_comment_id.txt"
DIRTY_GATE_ISSUE_CREATED_THIS_TICK="0"
gql_stats_log_file="${CODEX_DIR}/graphql_rate_stats.log"
gql_window_state_file="${CODEX_DIR}/graphql_rate_window_state.txt"
gql_window_start_epoch_file="${CODEX_DIR}/graphql_rate_window_start_epoch.txt"
gql_window_start_utc_file="${CODEX_DIR}/graphql_rate_window_start_utc.txt"
gql_window_requests_file="${CODEX_DIR}/graphql_rate_window_requests.txt"
gql_last_success_utc_file="${CODEX_DIR}/graphql_rate_last_success_utc.txt"
gql_last_limit_utc_file="${CODEX_DIR}/graphql_rate_last_limit_utc.txt"

emit_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

is_github_network_error() {
  local text="$1"
  printf '%s' "$text" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect'
}

run_gh_retry_capture() {
  local out=""
  local err_file
  err_file="$(mktemp "${CODEX_DIR}/gh_retry_err.XXXXXX")"
  if out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" "$@" 2>"$err_file")"; then
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  else
    local rc=$?
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s\n' "$out" >&2
    return "$rc"
  fi
}

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

project_gh_token="$(resolve_config_value "DAEMON_GH_PROJECT_TOKEN" "")"
if [[ -z "$project_gh_token" ]]; then
  project_gh_token="$(resolve_config_value "CODEX_GH_PROJECT_TOKEN" "")"
fi
project_gh_token="$(printf '%s' "$project_gh_token" | tr -d '\r\n')"

run_gh_retry_capture_project() {
  if [[ -n "$project_gh_token" ]]; then
    GH_TOKEN="$project_gh_token" run_gh_retry_capture "$@"
  else
    run_gh_retry_capture "$@"
  fi
}

read_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  if [[ -s "$file_path" ]]; then
    cat "$file_path"
  else
    printf '%s' "$default_value"
  fi
}

read_int_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  local raw
  raw="$(read_file_or_default "$file_path" "$default_value")"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "$default_value"
  fi
}

sanitize_for_log() {
  local value="$1"
  printf '%s' "$value" | tr '\n' ' ' | tr '\t' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

graphql_payload_has_rate_limit() {
  local payload="$1"
  printf '%s' "$payload" | jq -e '
    (.errors // [])
    | any(
        (.type // "" | ascii_downcase) == "rate_limit"
        or (.extensions.code // "" | ascii_downcase) == "graphql_rate_limit"
        or ((.message // "" | ascii_downcase) | test("rate limit"))
      )
  ' >/dev/null 2>&1
}

graphql_payload_first_rate_limit_message() {
  local payload="$1"
  local message
  message="$(
    printf '%s' "$payload" | jq -r '
      (
        (.errors // [])
        | map(
            select(
              (.type // "" | ascii_downcase) == "rate_limit"
              or (.extensions.code // "" | ascii_downcase) == "graphql_rate_limit"
              or ((.message // "" | ascii_downcase) | test("rate limit"))
            )
            | .message
          )
        | .[0]
      ) // ""
    ' 2>/dev/null || true
  )"
  if [[ -z "$message" ]]; then
    message="GraphQL rate limit reached"
  fi
  sanitize_for_log "$message"
}

gql_stats_on_success() {
  local now_epoch now_utc state requests
  now_epoch="$(date +%s)"
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  state="$(read_file_or_default "$gql_window_state_file" "WAIT_SUCCESS")"
  if [[ "$state" != "RUNNING" ]]; then
    printf '%s\n' "RUNNING" > "$gql_window_state_file"
    printf '%s\n' "$now_epoch" > "$gql_window_start_epoch_file"
    printf '%s\n' "$now_utc" > "$gql_window_start_utc_file"
    printf '%s\n' "1" > "$gql_window_requests_file"
  else
    requests="$(read_int_file_or_default "$gql_window_requests_file" "0")"
    requests=$(( requests + 1 ))
    printf '%s\n' "$requests" > "$gql_window_requests_file"
  fi

  printf '%s\n' "$now_utc" > "$gql_last_success_utc_file"
}

gql_stats_on_limit() {
  local stage="$1"
  local message="$2"
  local now_epoch now_utc state start_epoch start_utc requests duration
  now_epoch="$(date +%s)"
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  state="$(read_file_or_default "$gql_window_state_file" "WAIT_SUCCESS")"
  start_epoch="$(read_int_file_or_default "$gql_window_start_epoch_file" "0")"
  start_utc="$(read_file_or_default "$gql_window_start_utc_file" "")"
  requests="$(read_int_file_or_default "$gql_window_requests_file" "0")"
  duration="0"

  if [[ "$state" == "RUNNING" && "$start_epoch" -gt 0 && "$requests" -gt 0 ]]; then
    if (( now_epoch > start_epoch )); then
      duration=$(( now_epoch - start_epoch ))
    fi
  fi

  mkdir -p "$CODEX_DIR"
  printf '%s\tEVENT=RATE_LIMIT\tstage=%s\trequests=%s\tduration_sec=%s\tstart_utc=%s\tend_utc=%s\tmessage=%s\n' \
    "$now_utc" \
    "$(sanitize_for_log "$stage")" \
    "$requests" \
    "$duration" \
    "$(sanitize_for_log "$start_utc")" \
    "$now_utc" \
    "$(sanitize_for_log "$message")" \
    >> "$gql_stats_log_file"

  printf '%s\n' "$now_utc" > "$gql_last_limit_utc_file"
  printf '%s\n' "WAIT_SUCCESS" > "$gql_window_state_file"
  : > "$gql_window_start_epoch_file"
  : > "$gql_window_start_utc_file"
  printf '%s\n' "0" > "$gql_window_requests_file"

  printf '%s|%s|%s|%s' "$requests" "$duration" "$start_utc" "$now_utc"
}

trim() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

parse_flow_meta_line() {
  local body="$1"
  local key="$2"
  local value
  value="$(
    printf '%s\n' "$body" |
      awk -v k="$key" '
        BEGIN { IGNORECASE = 1 }
        {
          line=$0
          gsub("\r","",line)
          if (tolower(line) ~ "^" tolower(k) "[[:space:]]*:") {
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
          }
        }
      '
  )"
  trim "$value"
}

build_dependency_block_comment() {
  local task_id="$1"
  local blockers="$2"
  cat <<EOF
CODEX_SIGNAL: AGENT_DEPENDENCY_BLOCKED
CODEX_TASK: ${task_id}
CODEX_BLOCKED_BY: ${blockers}
CODEX_EXPECT: WAIT_DEPENDENCIES

Задача не может быть взята в работу: не выполнены зависимости из Flow Meta.
Блокеры: ${blockers}

Закрой блокеры (или обнови Depends-On), затем снова переведи задачу в Todo.
EOF
}

notify_dependency_blocked_once() {
  local task_id="$1"
  local issue_number="$2"
  local blockers="$3"

  local signature_file="${CODEX_DIR}/daemon_dependency_blocked_signature.txt"
  local signature="${task_id}|${blockers}"
  local previous=""
  if [[ -s "$signature_file" ]]; then
    previous="$(<"$signature_file")"
  fi
  if [[ "$previous" == "$signature" ]]; then
    echo "DEPENDENCY_BLOCK_NOTIFY_SKIPPED=ALREADY_SENT"
    echo "DEPENDENCY_BLOCK_SIGNATURE=$signature"
    return 0
  fi

  local comment_body comment_json err_file
  comment_body="$(build_dependency_block_comment "$task_id" "$blockers")"
  err_file="$(mktemp "${CODEX_DIR}/dependency_block_gh_err.XXXXXX")"

  if comment_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
      gh api "repos/${repo}/issues/${issue_number}/comments" \
      -f body="$comment_body" 2>"$err_file"
  )"; then
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s\n' "$signature" > "$signature_file"
    echo "DEPENDENCY_BLOCK_COMMENT_POSTED=1"
    echo "DEPENDENCY_BLOCK_ISSUE_NUMBER=$issue_number"
    echo "DEPENDENCY_BLOCK_SIGNATURE=$signature"
    return 0
  fi

  local rc=$?
  if [[ -s "$err_file" ]]; then
    cat "$err_file" >&2
  fi
  rm -f "$err_file"

  if [[ "$rc" -eq 75 ]]; then
    local tmp_body queue_out
    tmp_body="$(mktemp "${CODEX_DIR}/dependency_block_body.XXXXXX")"
    printf '%s\n' "$comment_body" > "$tmp_body"

    if queue_out="$(
      "${ROOT_DIR}/scripts/codex/github_outbox.sh" \
        enqueue_issue_comment \
        "$repo" \
        "$issue_number" \
        "$tmp_body" \
        "$task_id" \
        "DEPENDENCY_BLOCKED" \
        "0" 2>&1
    )"; then
      rm -f "$tmp_body"
      emit_lines "$queue_out"
      printf '%s\n' "$signature" > "$signature_file"
      echo "DEPENDENCY_BLOCK_COMMENT_QUEUED_OUTBOX=1"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      return 0
    fi

    local qrc=$?
    rm -f "$tmp_body"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "DEPENDENCY_BLOCK_OUTBOX_ERROR(rc=$qrc): $line"
    done <<<"$queue_out"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "DEPENDENCY_BLOCK_COMMENT_ERROR(rc=$rc): $line"
  done <<<"$comment_json"
  return 0
}

is_review_feedback_kind() {
  local kind="$1"
  [[ "$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')" == "REVIEW_FEEDBACK" ]]
}

extract_kv() {
  local text="$1"
  local key="$2"
  printf '%s\n' "$text" | sed -n "s/^${key}=//p" | head -n1
}

is_truthy_flag() {
  local raw="$1"
  local value
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

find_first_todo_issue_json() {
  local project_json
  if ! project_json="$(
    run_gh_retry_capture_project \
      gh api graphql \
      -f query='
query($projectId: ID!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: $itemsFirst) {
        nodes {
          id
          content {
            __typename
            ... on Issue { number title }
            ... on DraftIssue { title }
          }
          status: fieldValueByName(name: "Status") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
          priority: fieldValueByName(name: "Priority") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
      }
    }
  }
}
' \
      -f projectId="$project_id" \
      -F itemsFirst=100
  )"; then
    return "$?"
  fi

  printf '%s' "$project_json" | jq -c --arg trigger "$trigger_status" '
    def norm: gsub("^\\s+|\\s+$";"") | ascii_downcase;
    [
      .data.node.items.nodes[]
      | select(((.content.__typename // "") == "Issue") or ((.content.__typename // "") == "DraftIssue"))
      | select((((.content.title // "") | test("^DIRTY-GATE:")) | not))
      | select((.status.name // "" | norm) == ($trigger | norm))
      | {
          item_id: (.id // ""),
          content_type: (.content.__typename // ""),
          issue_number: (.content.number // ""),
          title: (.content.title // ""),
          priority: (.priority.name // "")
        }
      | .pri_w = (
          if .priority == "P0" then 0
          elif .priority == "P1" then 1
          elif .priority == "P2" then 2
          elif .priority == "P3" then 3
          else 9
          end
        )
      | .num = ((try (.issue_number | tonumber) catch 999999))
    ]
    | sort_by(.pri_w, .num)
    | .[0] // empty
  '
}

clear_dirty_gate_local_state() {
  : > "$dirty_gate_issue_file"
  : > "$dirty_gate_issue_url_file"
  : > "$dirty_gate_signature_file"
  : > "$dirty_gate_comment_signature_file"
  : > "$dirty_gate_blocked_issue_file"
  : > "$dirty_gate_blocked_title_file"
  : > "$dirty_gate_override_signature_file"
  : > "$dirty_gate_last_reply_id_file"
}

clear_dirty_gate_waiting_state_if_any() {
  local waiting_task=""
  [[ -s "${CODEX_DIR}/daemon_waiting_task_id.txt" ]] && waiting_task="$(<"${CODEX_DIR}/daemon_waiting_task_id.txt")"
  if [[ "$waiting_task" == DIRTY-GATE-ISSUE-* ]]; then
    : > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
    : > "${CODEX_DIR}/daemon_waiting_task_id.txt"
    : > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
    : > "${CODEX_DIR}/daemon_waiting_kind.txt"
    : > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
    : > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
    : > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
    echo "WAIT_DIRTY_WORKTREE_STALE_WAITING_CLEARED=1"
  fi
}

find_project_issue_item_id() {
  local issue_number="$1"
  local project_json

  if ! project_json="$(
    run_gh_retry_capture_project \
      gh api graphql \
      -f query='
query($projectId: ID!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: $itemsFirst) {
        nodes {
          id
          content {
            __typename
            ... on Issue { number }
          }
        }
      }
    }
  }
}
' \
      -f projectId="$project_id" \
      -F itemsFirst=100
  )"; then
    return "$?"
  fi

  printf '%s' "$project_json" | jq -r --arg num "$issue_number" '
    .data.node.items.nodes[]
    | select((.content.__typename // "") == "Issue")
    | select(((.content.number // "") | tostring) == $num)
    | .id
  ' | head -n1
}

find_project_item_status_by_id() {
  local item_id="$1"
  local project_json

  if ! project_json="$(
    run_gh_retry_capture_project \
      gh api graphql \
      -f query='
query($projectId: ID!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: $itemsFirst) {
        nodes {
          id
          status: fieldValueByName(name: "Status") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
      }
    }
  }
}
' \
      -f projectId="$project_id" \
      -F itemsFirst=100
  )"; then
    return "$?"
  fi

  printf '%s' "$project_json" | jq -r --arg id "$item_id" '
    .data.node.items.nodes[]
    | select((.id // "") == $id)
    | (.status.name // "")
  ' | head -n1
}

normalize_status_name() {
  local value="$1"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

is_resolved_project_status() {
  local value="$1"
  local normalized
  normalized="$(normalize_status_name "$value")"
  [[ "$normalized" == "done" || "$normalized" == "closed" ]]
}

dependency_issue_resolved() {
  local dep_issue_number="$1"
  local dep_state dep_item_id dep_status rc

  if dep_state="$(
    run_gh_retry_capture \
      gh issue view "$dep_issue_number" \
      --repo "$repo" \
      --json state \
      --jq '.state'
  )"; then
    :
  else
    rc=$?
    [[ "$rc" -eq 75 ]] && return 75
    return "$rc"
  fi

  if [[ "$dep_state" == "CLOSED" ]]; then
    return 0
  fi

  if dep_item_id="$(find_project_issue_item_id "$dep_issue_number")"; then
    :
  else
    rc=$?
    [[ "$rc" -eq 75 ]] && return 75
    return "$rc"
  fi

  [[ -n "$dep_item_id" ]] || return 1

  if dep_status="$(find_project_item_status_by_id "$dep_item_id")"; then
    :
  else
    rc=$?
    [[ "$rc" -eq 75 ]] && return 75
    return "$rc"
  fi

  if is_resolved_project_status "$dep_status"; then
    return 0
  fi

  return 1
}

maybe_release_active_task_on_status_mismatch() {
  local active_task_file="${CODEX_DIR}/daemon_active_task.txt"
  local active_item_file="${CODEX_DIR}/daemon_active_item_id.txt"
  local active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
  local active_task active_item status_name status_norm target_norm rc

  [[ -s "$active_task_file" ]] || return 0
  active_task="$(<"$active_task_file")"
  [[ -n "$active_task" ]] || return 0

  active_item=""
  [[ -s "$active_item_file" ]] && active_item="$(<"$active_item_file")"
  [[ -n "$active_item" ]] || return 0

  if ! status_name="$(find_project_item_status_by_id "$active_item")"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=ACTIVE_TASK_STATUS_CHECK"
      return 75
    fi
    return 0
  fi
  [[ -n "$status_name" ]] || return 0

  status_norm="$(normalize_status_name "$status_name")"
  target_norm="$(normalize_status_name "$target_status")"
  if [[ "$status_norm" == "$target_norm" ]]; then
    return 0
  fi

  echo "ACTIVE_TASK_RELEASED_STATUS_MISMATCH=1"
  echo "ACTIVE_TASK_RELEASED_TASK_ID=${active_task}"
  echo "ACTIVE_TASK_RELEASED_STATUS=${status_name}"
  echo "ACTIVE_TASK_EXPECTED_STATUS=${target_status}"
  "${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null || true
  : > "$active_task_file"
  : > "$active_item_file"
  : > "$active_issue_file"
  : > "${CODEX_DIR}/project_task_id.txt"
  return 0
}

detect_dirty_gate_action() {
  local reply_body="$1"
  local reply_mode="$2"
  if printf '%s' "$reply_body" | grep -Eiq '(^|[[:space:]])(IGNORE|IGNOR|ИГНОР|ПРОПУСТИ|ПРОДОЛЖАЙ С DIRTY)($|[[:space:]])'; then
    printf 'IGNORE'
    return 0
  fi
  if printf '%s' "$reply_body" | grep -Eiq '(^|[[:space:]])(COMMIT|ЗАКОММИТ|ЗАКОММИТЬ|КОММИТ)($|[[:space:]])'; then
    printf 'COMMIT'
    return 0
  fi
  if printf '%s' "$reply_body" | grep -Eiq '(^|[[:space:]])(STASH|СТЕШ|СТАШ)($|[[:space:]])'; then
    printf 'STASH'
    return 0
  fi
  if printf '%s' "$reply_body" | grep -Eiq '(^|[[:space:]])(REVERT|ОТКАТ|ОТКАТИТЬ|ОТМЕНИ)($|[[:space:]])'; then
    printf 'REVERT'
    return 0
  fi

  if [[ "$(printf '%s' "$reply_mode" | tr '[:lower:]' '[:upper:]')" == "REWORK" ]]; then
    printf 'REWORK'
  else
    printf 'QUESTION'
  fi
}

set_dirty_gate_project_status() {
  local issue_number="$1"
  local status_name="$2"
  local flow_name="$3"
  local stage_name="$4"
  local preferred_item_id="${5:-}"
  local item_id status_target status_out rc

  if [[ "$preferred_item_id" == PVTI_* ]]; then
    item_id="$preferred_item_id"
  else
    item_id="$(find_project_issue_item_id "$issue_number" || true)"
  fi
  if [[ -n "$item_id" ]]; then
    echo "WAIT_DIRTY_WORKTREE_GATE_PROJECT_ITEM_ID=${item_id}"
    status_target="$item_id"
  else
    status_target="ISSUE-${issue_number}"
  fi

  if status_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "$status_target" "$status_name" "$flow_name" 2>&1)"; then
    emit_lines "$status_out"
    return 0
  fi

  rc=$?
  if [[ "$rc" -eq 75 ]] || is_github_network_error "$status_out"; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=${stage_name}"
    return 75
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "DIRTY_GATE_PROJECT_STATUS_WARN: $line"
  done <<< "$status_out"
  return "$rc"
}

set_dirty_gate_waiting_at_reply() {
  local gate_issue_number="$1"
  local reply_comment_id="$2"
  local reply_url="$3"
  local waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
  local waiting_task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
  local waiting_question_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  local waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
  local waiting_pending_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
  local waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
  local waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"
  local task_id

  [[ -n "$reply_comment_id" ]] || return 0
  task_id="DIRTY-GATE-ISSUE-${gate_issue_number}"

  printf '%s\n' "$gate_issue_number" > "$waiting_issue_file"
  printf '%s\n' "$task_id" > "$waiting_task_file"
  printf '%s\n' "$reply_comment_id" > "$waiting_question_file"
  printf '%s\n' "BLOCKER" > "$waiting_kind_file"
  printf '%s\n' "0" > "$waiting_pending_file"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$waiting_since_file"
  if [[ -n "$reply_url" ]]; then
    printf '%s\n' "$reply_url" > "$waiting_comment_url_file"
  else
    : > "$waiting_comment_url_file"
  fi
  echo "WAIT_DIRTY_WORKTREE_WAITING_AT_REPLY_ID=${reply_comment_id}"
}

auto_commit_dirty_worktree() {
  local gate_issue_number="$1"
  local reply_comment_id="$2"
  local current_branch blocked_issue commit_message commit_out rc retry_out retry_rc
  local -a stage_paths=()

  current_branch="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$current_branch" != "development" ]]; then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_BLOCKED_BRANCH=${current_branch:-unknown}"
    return 1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    stage_paths+=("$line")
  done < <(
    {
      git -C "${ROOT_DIR}" diff --name-only --ignore-submodules -- || true
      git -C "${ROOT_DIR}" diff --cached --name-only --ignore-submodules -- || true
    } | awk 'NF' | sort -u
  )

  if (( ${#stage_paths[@]} == 0 )); then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_SKIPPED=NO_TRACKED_CHANGES"
    return 0
  fi

  blocked_issue=""
  [[ -s "$dirty_gate_blocked_issue_file" ]] && blocked_issue="$(<"$dirty_gate_blocked_issue_file")"
  if [[ -n "$blocked_issue" ]]; then
    commit_message="chore: dirty-gate auto-commit for ISSUE-${blocked_issue}"
  else
    commit_message="chore: dirty-gate auto-commit tracked changes"
  fi

  if commit_out="$("${ROOT_DIR}/scripts/codex/dev_commit_push.sh" "$commit_message" "${stage_paths[@]}" 2>&1)"; then
    emit_lines "$commit_out"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_APPLIED=1"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PATHS_COUNT=${#stage_paths[@]}"
    [[ -n "$reply_comment_id" ]] && echo "WAIT_DIRTY_WORKTREE_COMMIT_REPLY_ID=${reply_comment_id}"
    return 0
  fi

  rc=$?
  if printf '%s' "$commit_out" | grep -Eq 'non-fast-forward|failed to push some refs'; then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PUSH_RETRY=1"
    if retry_out="$(
      {
        git -C "${ROOT_DIR}" pull --rebase origin development
        git -C "${ROOT_DIR}" push origin development
      } 2>&1
    )"; then
      emit_lines "$retry_out"
      echo "WAIT_DIRTY_WORKTREE_COMMIT_APPLIED=1"
      echo "WAIT_DIRTY_WORKTREE_COMMIT_PATHS_COUNT=${#stage_paths[@]}"
      [[ -n "$reply_comment_id" ]] && echo "WAIT_DIRTY_WORKTREE_COMMIT_REPLY_ID=${reply_comment_id}"
      return 0
    fi
    retry_rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "DIRTY_GATE_COMMIT_RETRY_ERROR(rc=$retry_rc): $line"
    done <<< "$retry_out"
  fi
  if printf '%s' "$commit_out" | grep -Eiq 'nothing to commit|no changes added to commit'; then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_SKIPPED=NOTHING_TO_COMMIT"
    return 0
  fi
  if is_github_network_error "$commit_out"; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=DIRTY_GATE_AUTO_COMMIT_PUSH"
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "DIRTY_GATE_COMMIT_ERROR(rc=$rc): $line"
  done <<< "$commit_out"
  echo "WAIT_DIRTY_WORKTREE_COMMIT_FAILED=1"
  return 1
}

ensure_dirty_gate_commit_pr() {
  local gate_issue_number="$1"
  local pr_list_json pr_number pr_url create_out create_url rc

  DIRTY_GATE_COMMIT_PR_NUMBER=""
  DIRTY_GATE_COMMIT_PR_URL=""

  if pr_list_json="$(
    run_gh_retry_capture \
      gh pr list \
        --repo "$repo" \
        --state open \
        --base main \
        --head development \
        --json number,url \
        --jq '.'
  )"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_COMMIT_PR_LIST"
      return 75
    fi
    return "$rc"
  fi

  pr_number="$(printf '%s' "$pr_list_json" | jq -r '.[0].number // ""')"
  pr_url="$(printf '%s' "$pr_list_json" | jq -r '.[0].url // ""')"

  if [[ -z "$pr_number" ]]; then
    if create_out="$(
      run_gh_retry_capture \
        gh pr create \
          --repo "$repo" \
          --base main \
          --head development \
          --title "chore: dirty-gate auto-commit" \
          --body "CODEX_SIGNAL: DIRTY_GATE_AUTO_COMMIT_PR

Source: DIRTY-GATE-ISSUE-${gate_issue_number}
This PR was created automatically after COMMIT reply in dirty-gate flow."
    )"; then
      :
    else
      rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_COMMIT_PR_CREATE"
        return 75
      fi
      return "$rc"
    fi

    create_url="$(printf '%s\n' "$create_out" | tail -n1 | tr -d '[:space:]')"
    if [[ "$create_url" =~ /pull/([0-9]+)$ ]]; then
      pr_number="${BASH_REMATCH[1]}"
      pr_url="$create_url"
    fi
    emit_lines "$create_out"
  fi

  if [[ -z "$pr_number" ]]; then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_MISSING=1"
    return 1
  fi

  DIRTY_GATE_COMMIT_PR_NUMBER="$pr_number"
  DIRTY_GATE_COMMIT_PR_URL="$pr_url"
  echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_NUMBER=${pr_number}"
  [[ -n "$pr_url" ]] && echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_URL=${pr_url}"
  return 0
}

merge_dirty_gate_commit_pr() {
  local pr_number="$1"
  local merge_out pr_view_json pr_state pr_merged_at rc

  if merge_out="$(
    run_gh_retry_capture \
      gh pr merge "$pr_number" \
        --repo "$repo" \
        --merge
  )"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_COMMIT_PR_MERGE"
      return 75
    fi
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "DIRTY_GATE_PR_MERGE_WARN(rc=$rc): $line"
    done <<< "$merge_out"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_NOT_MERGED=1"
    return 1
  fi
  emit_lines "$merge_out"

  if pr_view_json="$(
    run_gh_retry_capture \
      gh pr view "$pr_number" \
        --repo "$repo" \
        --json state,mergedAt \
        --jq '.'
  )"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_COMMIT_PR_VIEW"
      return 75
    fi
    return "$rc"
  fi

  pr_state="$(printf '%s' "$pr_view_json" | jq -r '.state // ""')"
  pr_merged_at="$(printf '%s' "$pr_view_json" | jq -r '.mergedAt // ""')"
  if [[ "$pr_state" == "MERGED" || -n "$pr_merged_at" ]]; then
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_MERGED=1"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_MERGED_AT=${pr_merged_at}"
    return 0
  fi

  echo "WAIT_DIRTY_WORKTREE_COMMIT_PR_NOT_MERGED=1"
  return 1
}

finalize_dirty_gate_after_commit_merge() {
  local gate_issue_number="$1"
  local close_out rc current_waiting_issue

  if set_dirty_gate_project_status "$gate_issue_number" "Done" "Done" "DIRTY_GATE_CLOSE_STATUS"; then
    :
  else
    rc=$?
    [[ "$rc" -eq 75 ]] && return 75
  fi

  if close_out="$(
    run_gh_retry_capture \
      gh issue close "$gate_issue_number" \
        --repo "$repo" \
        --comment "CODEX_SIGNAL: DIRTY_GATE_RESOLVED
CODEX_TASK: DIRTY-GATE-ISSUE-${gate_issue_number}

Dirty worktree resolved by COMMIT flow (commit + PR + merge)."
  )"; then
    emit_lines "$close_out"
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_CLOSE_ISSUE"
      return 75
    fi
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "DIRTY_GATE_CLOSE_WARN: $line"
    done <<< "$close_out"
  fi

  : > "$dirty_gate_issue_file"
  : > "$dirty_gate_issue_url_file"
  : > "$dirty_gate_signature_file"
  : > "$dirty_gate_comment_signature_file"
  : > "$dirty_gate_blocked_issue_file"
  : > "$dirty_gate_blocked_title_file"
  : > "$dirty_gate_override_signature_file"
  : > "$dirty_gate_last_reply_id_file"

  current_waiting_issue=""
  [[ -s "${CODEX_DIR}/daemon_waiting_issue_number.txt" ]] && current_waiting_issue="$(<"${CODEX_DIR}/daemon_waiting_issue_number.txt")"
  if [[ "$current_waiting_issue" == "$gate_issue_number" ]]; then
    : > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
    : > "${CODEX_DIR}/daemon_waiting_task_id.txt"
    : > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
    : > "${CODEX_DIR}/daemon_waiting_kind.txt"
    : > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
    : > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
    : > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  fi

  echo "WAIT_DIRTY_WORKTREE_GATE_RESOLVED=1"
  return 0
}

restore_dirty_gate_waiting_state() {
  local gate_issue_number="$1"
  local comments_json issue_json question_id question_url task_id last_reply_id
  local waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
  local waiting_task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
  local waiting_question_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  local waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
  local waiting_pending_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
  local waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
  local waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"

  if comments_json="$(
    run_gh_retry_capture \
      gh api "repos/${repo}/issues/${gate_issue_number}/comments?per_page=100"
  )"; then
    :
  else
    local rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_WAITING_RECOVER"
      return 75
    fi
    return "$rc"
  fi

  task_id="DIRTY-GATE-ISSUE-${gate_issue_number}"
  question_id="$(
    printf '%s' "$comments_json" | jq -r --arg task "$task_id" '
      [
        .[]
        | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_BLOCKER$")))
        | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REPLY$")))
        | select(((.body // "") | test("(?m)^CODEX_TASK: " + $task + "$")))
      ][-1].id // empty
    '
  )"
  question_url="$(
    printf '%s' "$comments_json" | jq -r --arg task "$task_id" '
      [
        .[]
        | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_BLOCKER$")))
        | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REPLY$")))
        | select(((.body // "") | test("(?m)^CODEX_TASK: " + $task + "$")))
      ][-1].html_url // empty
    '
  )"

  if [[ -z "$question_id" ]]; then
    if ! issue_json="$(
      run_gh_retry_capture \
        gh issue view "$gate_issue_number" \
          --repo "$repo" \
          --json body,url,state \
          --jq '.'
    )"; then
      local rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_WAITING_RESTORE_ISSUE"
        return 75
      fi
      return "$rc"
    fi
    if [[ "$(printf '%s' "$issue_json" | jq -r '.state // ""')" == "OPEN" ]] &&
      printf '%s' "$issue_json" | jq -r '.body // ""' | grep -q '^CODEX_SIGNAL: DIRTY_GATE_OPEN$'; then
      question_id="0"
      question_url="$(printf '%s' "$issue_json" | jq -r '.url // empty')"
    fi
  fi

  [[ -n "$question_id" ]] || return 1

  # If we already processed a reply, set waiting anchor to that reply id.
  # This prevents daemon_check_replies from re-reading the same comment
  # and re-posting AGENT_RESUMED on every tick.
  last_reply_id=""
  [[ -s "$dirty_gate_last_reply_id_file" ]] && last_reply_id="$(<"$dirty_gate_last_reply_id_file")"
  if [[ "$last_reply_id" =~ ^[0-9]+$ ]]; then
    if [[ ! "$question_id" =~ ^[0-9]+$ || "$last_reply_id" -gt "$question_id" ]]; then
      question_id="$last_reply_id"
      question_url="$(
        printf '%s' "$comments_json" | jq -r --argjson qid "$question_id" '
          [ .[] | select((.id|tonumber) == $qid) ][0].html_url // empty
        '
      )"
    fi
  fi

  printf '%s\n' "$gate_issue_number" > "$waiting_issue_file"
  printf '%s\n' "$task_id" > "$waiting_task_file"
  printf '%s\n' "$question_id" > "$waiting_question_file"
  printf '%s\n' "BLOCKER" > "$waiting_kind_file"
  printf '%s\n' "0" > "$waiting_pending_file"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$waiting_since_file"
  if [[ -n "$question_url" ]]; then
    printf '%s\n' "$question_url" > "$waiting_comment_url_file"
  else
    : > "$waiting_comment_url_file"
  fi

  echo "WAIT_DIRTY_WORKTREE_WAITING_RECOVERED=1"
  echo "WAIT_DIRTY_WORKTREE_GATE_COMMENT_ID=${question_id}"
  return 0
}

ensure_dirty_gate_issue_in_project() {
  local issue_number="$1"
  local item_id issue_id issue_json add_json rc

  item_id="$(find_project_issue_item_id "$issue_number" || true)"
  if [[ -n "$item_id" ]]; then
    echo "WAIT_DIRTY_WORKTREE_GATE_PROJECT_ITEM_ID=${item_id}"
  else
    if ! issue_json="$(
      run_gh_retry_capture \
        gh api graphql \
        -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) { id }
  }
}
' \
        -f owner="$repo_owner" \
        -f repo="$repo_name" \
        -F number="$issue_number"
    )"; then
      rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_ISSUE_ID"
        return 75
      fi
      return "$rc"
    fi

    issue_id="$(printf '%s' "$issue_json" | jq -r '.data.repository.issue.id // ""')"
    if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
      echo "DIRTY_GATE_PROJECT_LINK_SKIP=ISSUE_ID_MISSING"
      return 1
    fi

    if ! add_json="$(
      run_gh_retry_capture_project \
        gh api graphql \
        -f query='
mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
    item { id }
  }
}
' \
        -f projectId="$project_id" \
        -f contentId="$issue_id"
    )"; then
      rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_PROJECT_ADD"
        return 75
      fi
      return "$rc"
    fi

    item_id="$(printf '%s' "$add_json" | jq -r '.data.addProjectV2ItemById.item.id // ""')"
    [[ -n "$item_id" ]] && echo "WAIT_DIRTY_WORKTREE_GATE_PROJECT_ITEM_ID=${item_id}"
  fi

  if ! set_dirty_gate_project_status "$issue_number" "$target_status" "$target_flow" "DIRTY_GATE_PROJECT_STATUS" "$item_id"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      return 75
    fi
  else
    echo "WAIT_DIRTY_WORKTREE_GATE_STATUS=${target_status}"
    echo "WAIT_DIRTY_WORKTREE_GATE_FLOW=${target_flow}"
  fi

  return 0
}

ensure_dirty_gate_issue() {
  local blocked_ref="$1"
  local blocked_title="$2"
  local tracked_count="$3"
  local tracked_preview="$4"
  local signature="${5:-}"

  DIRTY_GATE_ISSUE_NUMBER=""
  DIRTY_GATE_ISSUE_URL=""
  DIRTY_GATE_ISSUE_CREATED_THIS_TICK="0"

  if [[ -s "$dirty_gate_issue_file" ]]; then
    local existing_number existing_json existing_state existing_url
    existing_number="$(<"$dirty_gate_issue_file")"
    if existing_json="$(
      run_gh_retry_capture \
        gh issue view "$existing_number" \
          --repo "$repo" \
          --json number,state,url \
          --jq '.'
    )"; then
      existing_state="$(printf '%s' "$existing_json" | jq -r '.state // ""')"
      if [[ "$existing_state" == "OPEN" ]]; then
        DIRTY_GATE_ISSUE_NUMBER="$(printf '%s' "$existing_json" | jq -r '.number // ""')"
        existing_url="$(printf '%s' "$existing_json" | jq -r '.url // ""')"
        DIRTY_GATE_ISSUE_URL="$existing_url"
      fi
    else
      local rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_VIEW"
      fi
    fi
  fi

  if [[ -z "$DIRTY_GATE_ISSUE_NUMBER" ]]; then
    local issue_title issue_body create_out create_url
    issue_title="DIRTY-GATE: resolve tracked worktree changes"
    issue_body="$(cat <<EOF
CODEX_SIGNAL: DIRTY_GATE_OPEN
CODEX_EXPECT: USER_REPLY

Daemon paused due to tracked local changes.

Blocked Todo task:
- ${blocked_ref}: ${blocked_title}

Current tracked changes:
- count: ${tracked_count}
- files: ${tracked_preview}

Reply in this issue with one of intents:
- COMMIT: разрешить daemon сделать commit через flow
- STASH: сначала убрать изменения в stash
- REVERT: откатить текущие tracked-изменения
- IGNORE: временно разрешить взять Todo при текущем dirty-state
EOF
)"
    if create_out="$(
      run_gh_retry_capture \
        gh issue create \
          --repo "$repo" \
          --title "$issue_title" \
          --body "$issue_body"
    )"; then
      create_url="$(printf '%s\n' "$create_out" | tail -n1 | tr -d '[:space:]')"
      if [[ "$create_url" =~ /issues/([0-9]+)$ ]]; then
        DIRTY_GATE_ISSUE_NUMBER="${BASH_REMATCH[1]}"
        DIRTY_GATE_ISSUE_URL="$create_url"
        printf '%s\n' "$DIRTY_GATE_ISSUE_NUMBER" > "$dirty_gate_issue_file"
        printf '%s\n' "$DIRTY_GATE_ISSUE_URL" > "$dirty_gate_issue_url_file"
        if [[ -n "$signature" ]]; then
          printf '%s\n' "$signature" > "$dirty_gate_comment_signature_file"
        fi
        printf '%s\n' "$DIRTY_GATE_ISSUE_NUMBER" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
        printf '%s\n' "DIRTY-GATE-ISSUE-${DIRTY_GATE_ISSUE_NUMBER}" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
        printf '%s\n' "0" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
        printf '%s\n' "BLOCKER" > "${CODEX_DIR}/daemon_waiting_kind.txt"
        printf '%s\n' "0" > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
        date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
        if [[ -n "$DIRTY_GATE_ISSUE_URL" ]]; then
          printf '%s\n' "$DIRTY_GATE_ISSUE_URL" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
        fi
        DIRTY_GATE_ISSUE_CREATED_THIS_TICK="1"
        echo "DIRTY_GATE_ISSUE_CREATED=1"
        echo "WAIT_DIRTY_WORKTREE_GATE_COMMENT_ID=0"
      fi
    else
      local rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DIRTY_GATE_CREATE"
        return 75
      fi
      return "$rc"
    fi
  else
    [[ -n "$DIRTY_GATE_ISSUE_URL" ]] && printf '%s\n' "$DIRTY_GATE_ISSUE_URL" > "$dirty_gate_issue_url_file"
  fi

  if [[ -n "$DIRTY_GATE_ISSUE_NUMBER" ]]; then
    if ! ensure_dirty_gate_issue_in_project "$DIRTY_GATE_ISSUE_NUMBER"; then
      local rc=$?
      if [[ "$rc" -eq 75 ]]; then
        return 75
      fi
    fi
    echo "WAIT_DIRTY_WORKTREE_GATE_ISSUE_NUMBER=${DIRTY_GATE_ISSUE_NUMBER}"
    [[ -n "$DIRTY_GATE_ISSUE_URL" ]] && echo "WAIT_DIRTY_WORKTREE_GATE_ISSUE_URL=${DIRTY_GATE_ISSUE_URL}"
    return 0
  fi

  return 1
}

maybe_post_dirty_gate_blocker() {
  local gate_issue_number="$1"
  local blocked_ref="$2"
  local blocked_title="$3"
  local tracked_count="$4"
  local tracked_preview="$5"
  local signature="$6"
  local comment_json comment_id comment_url

  if [[ -s "$dirty_gate_comment_signature_file" && "$(cat "$dirty_gate_comment_signature_file")" == "$signature" ]]; then
    return 0
  fi

  local comment_body
  comment_body="$(cat <<EOF
CODEX_SIGNAL: AGENT_BLOCKER
CODEX_TASK: DIRTY-GATE-ISSUE-${gate_issue_number}
CODEX_EXPECT: USER_REPLY

Сейчас daemon не берет задачи из Todo: в рабочем дереве есть tracked-изменения.

Блокируемая задача:
- ${blocked_ref}: ${blocked_title}

Tracked changes:
- count: ${tracked_count}
- files: ${tracked_preview}

Ответь одним сообщением, что делать:
- COMMIT
- STASH
- REVERT
- IGNORE
EOF
)"

  if ! comment_json="$(
    run_gh_retry_capture \
      gh api "repos/${repo}/issues/${gate_issue_number}/comments" \
      -f body="$comment_body"
  )"; then
    local rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_BLOCKER_COMMENT"
      return 0
    fi
    return "$rc"
  fi

  comment_id="$(printf '%s' "$comment_json" | jq -r '.id // ""')"
  comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url // ""')"
  printf '%s\n' "$signature" > "$dirty_gate_comment_signature_file"

  if [[ -n "$comment_id" ]]; then
    printf '%s\n' "$gate_issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
    printf '%s\n' "DIRTY-GATE-ISSUE-${gate_issue_number}" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
    printf '%s\n' "$comment_id" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
    printf '%s\n' "BLOCKER" > "${CODEX_DIR}/daemon_waiting_kind.txt"
    printf '%s\n' "0" > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
    [[ -n "$comment_url" ]] && printf '%s\n' "$comment_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
    echo "WAIT_DIRTY_WORKTREE_GATE_COMMENT_ID=${comment_id}"
  fi
}

maybe_process_dirty_gate_reply() {
  local signature="$1"
  local waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
  local waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
  local gate_issue_number waiting_issue waiting_kind reply_probe_out reply_body reply_mode dirty_action rc
  local blocked_json
  local reply_comment_id reply_url task_id
  local commit_ok="0" set_override="0"
  local commit_flow_resolved="0"

  [[ -s "$dirty_gate_issue_file" ]] || return 0
  gate_issue_number="$(<"$dirty_gate_issue_file")"
  task_id="DIRTY-GATE-ISSUE-${gate_issue_number}"

  waiting_issue=""
  [[ -s "$waiting_issue_file" ]] && waiting_issue="$(<"$waiting_issue_file")"
  waiting_kind=""
  [[ -s "$waiting_kind_file" ]] && waiting_kind="$(<"$waiting_kind_file")"

  # In idle (no Todo candidates), do not keep or restore DIRTY-GATE waiting context.
  if ! blocked_json="$(find_first_todo_issue_json)"; then
    rc=$?
    [[ "$rc" -eq 75 ]] && return 0
    return 0
  fi
  if [[ -z "$blocked_json" ]]; then
    clear_dirty_gate_waiting_state_if_any
    return 0
  fi

  if [[ "$waiting_issue" != "$gate_issue_number" || "$(printf '%s' "$waiting_kind" | tr '[:lower:]' '[:upper:]')" != "BLOCKER" ]]; then
    if ! restore_dirty_gate_waiting_state "$gate_issue_number"; then
      rc=$?
      [[ "$rc" -eq 75 ]] && return 0
      return 0
    fi
  fi

  if ! reply_probe_out="$("${ROOT_DIR}/scripts/codex/daemon_check_replies.sh" 2>&1)"; then
    local rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_REPLY_CHECK"
      return 0
    fi
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "NO_WAITING_USER_REPLY=1" ]] && continue
    echo "$line"
  done <<< "$reply_probe_out"

  if ! printf '%s' "$reply_probe_out" | grep -q '^USER_REPLY_RECEIVED=1'; then
    return 0
  fi

  reply_body=""
  [[ -s "${CODEX_DIR}/daemon_user_reply.txt" ]] && reply_body="$(<"${CODEX_DIR}/daemon_user_reply.txt")"
  reply_mode="$(extract_kv "$reply_probe_out" "REPLY_MODE")"
  reply_comment_id="$(extract_kv "$reply_probe_out" "REPLY_COMMENT_ID")"
  reply_url="$(extract_kv "$reply_probe_out" "REPLY_URL")"

  if [[ -n "$reply_comment_id" && -s "$dirty_gate_last_reply_id_file" && "$(<"$dirty_gate_last_reply_id_file")" == "$reply_comment_id" ]]; then
    echo "WAIT_DIRTY_WORKTREE_REPLY_ALREADY_PROCESSED=${reply_comment_id}"
    return 0
  fi

  dirty_action="$(detect_dirty_gate_action "$reply_body" "$reply_mode")"
  echo "WAIT_DIRTY_WORKTREE_GATE_ACTION=${dirty_action}"

  if [[ "$dirty_action" == "IGNORE" ]]; then
    set_override="1"
  elif [[ "$dirty_action" == "COMMIT" ]]; then
    if auto_commit_dirty_worktree "$gate_issue_number" "$reply_comment_id"; then
      commit_ok="1"
      if ensure_dirty_gate_commit_pr "$gate_issue_number" && merge_dirty_gate_commit_pr "$DIRTY_GATE_COMMIT_PR_NUMBER" && finalize_dirty_gate_after_commit_merge "$gate_issue_number"; then
        commit_flow_resolved="1"
      else
        rc=$?
        [[ "$rc" -eq 75 ]] && return 0
        set_dirty_gate_waiting_at_reply "$gate_issue_number" "$reply_comment_id" "$reply_url"
      fi
    else
      commit_ok="0"
      set_override="0"
      set_dirty_gate_waiting_at_reply "$gate_issue_number" "$reply_comment_id" "$reply_url"
    fi
  fi

  if [[ "$set_override" == "1" ]]; then
    printf '%s\n' "$signature" > "$dirty_gate_override_signature_file"
    echo "WAIT_DIRTY_WORKTREE_OVERRIDE_SET=1"
    echo "WAIT_DIRTY_WORKTREE_OVERRIDE_MODE=${dirty_action}"
    [[ "$dirty_action" == "COMMIT" ]] && echo "WAIT_DIRTY_WORKTREE_COMMIT_OK=${commit_ok}"
  elif [[ "$dirty_action" == "COMMIT" && "$commit_flow_resolved" == "1" ]]; then
    : > "$dirty_gate_override_signature_file"
    echo "WAIT_DIRTY_WORKTREE_OVERRIDE_SET=0"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_OK=${commit_ok}"
    echo "WAIT_DIRTY_WORKTREE_COMMIT_FLOW_DONE=1"
  else
    : > "$dirty_gate_override_signature_file"
    echo "WAIT_DIRTY_WORKTREE_OVERRIDE_SET=0"
    set_dirty_gate_waiting_at_reply "$gate_issue_number" "$reply_comment_id" "$reply_url"
  fi

  [[ -n "$reply_comment_id" ]] && printf '%s\n' "$reply_comment_id" > "$dirty_gate_last_reply_id_file"

  if [[ "$commit_flow_resolved" != "1" && "$(printf '%s' "$reply_mode" | tr '[:lower:]' '[:upper:]')" == "REWORK" ]]; then
    if ! set_dirty_gate_project_status "$gate_issue_number" "$target_status" "$target_flow" "DIRTY_GATE_REPLY_STATUS"; then
      rc=$?
      [[ "$rc" -eq 75 ]] && return 0
    else
      echo "WAIT_DIRTY_WORKTREE_GATE_STATUS_MOVED=1"
      echo "WAIT_DIRTY_WORKTREE_GATE_STATUS=${target_status}"
      echo "WAIT_DIRTY_WORKTREE_GATE_FLOW=${target_flow}"
    fi
  fi
}

dirty_worktree_override_active() {
  local signature="$1"
  [[ -s "$dirty_gate_override_signature_file" ]] || return 1
  [[ "$(<"$dirty_gate_override_signature_file")" == "$signature" ]]
}

maybe_handle_dirty_worktree_gate() {
  local tracked_count="$1"
  local tracked_preview="$2"
  local gate_enabled_raw blocked_json blocked_issue blocked_title blocked_item_id blocked_type blocked_ref signature
  local rc

  gate_enabled_raw="$(resolve_config_value "DIRTY_WORKTREE_GATE_ENABLED" "1")"
  if ! is_truthy_flag "$gate_enabled_raw"; then
    return 0
  fi

  if ! blocked_json="$(find_first_todo_issue_json)"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=DIRTY_GATE_TODO_SCAN"
      return 0
    fi
    return 0
  fi

  [[ -z "$blocked_json" ]] && return 0

  blocked_issue="$(printf '%s' "$blocked_json" | jq -r '.issue_number // ""')"
  blocked_item_id="$(printf '%s' "$blocked_json" | jq -r '.item_id // ""')"
  blocked_type="$(printf '%s' "$blocked_json" | jq -r '.content_type // ""')"
  blocked_title="$(printf '%s' "$blocked_json" | jq -r '.title // ""')"
  if [[ "$blocked_type" == "Issue" && -n "$blocked_issue" && "$blocked_issue" != "0" ]]; then
    blocked_ref="Issue #${blocked_issue}"
  elif [[ "$blocked_type" == "DraftIssue" && -n "$blocked_item_id" ]]; then
    blocked_ref="DraftItem ${blocked_item_id}"
  else
    return 0
  fi

  if [[ "$blocked_type" == "Issue" ]]; then
    printf '%s\n' "$blocked_issue" > "$dirty_gate_blocked_issue_file"
  else
    : > "$dirty_gate_blocked_issue_file"
  fi
  printf '%s\n' "$blocked_title" > "$dirty_gate_blocked_title_file"
  echo "WAIT_DIRTY_WORKTREE_BLOCKED_REF=${blocked_ref}"
  [[ "$blocked_type" == "Issue" ]] && echo "WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_NUMBER=${blocked_issue}"
  [[ -n "$blocked_title" ]] && echo "WAIT_DIRTY_WORKTREE_BLOCKED_ISSUE_TITLE=${blocked_title}"

  signature="$(printf '%s|%s|%s|%s|%s' "$blocked_type" "$blocked_ref" "$blocked_title" "$tracked_count" "$tracked_preview" | shasum -a 1 | awk '{print $1}')"
  printf '%s\n' "$signature" > "$dirty_gate_signature_file"

  if ! ensure_dirty_gate_issue "$blocked_ref" "$blocked_title" "$tracked_count" "$tracked_preview" "$signature"; then
    rc=$?
    [[ "$rc" -eq 75 ]] && return 0
    return 0
  fi

  if [[ -n "$DIRTY_GATE_ISSUE_NUMBER" ]]; then
    if [[ "$DIRTY_GATE_ISSUE_CREATED_THIS_TICK" == "1" ]]; then
      return 0
    fi
    maybe_post_dirty_gate_blocker "$DIRTY_GATE_ISSUE_NUMBER" "$blocked_ref" "$blocked_title" "$tracked_count" "$tracked_preview" "$signature" || true
  fi
}

mkdir -p "$CODEX_DIR"

# Runtime backlog-seed apply:
# if .tmp/codex/backlog_seed_plan.json exists, try to create/link one task per tick.
if backlog_seed_out="$("${ROOT_DIR}/scripts/codex/backlog_seed_apply.sh" 2>&1)"; then
  emit_lines "$backlog_seed_out"
else
  rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "BACKLOG_SEED_APPLY_ERROR(rc=$rc): $line"
  done <<< "$backlog_seed_out"
fi

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  tracked_lines=""
  tracked_count=""
  tracked_preview=""
  dirty_signature=""
  tracked_lines="$(
    git -C "${ROOT_DIR}" status --short --untracked-files=no 2>/dev/null || true
  )"
  tracked_count="$(
    printf '%s\n' "$tracked_lines" | awk 'NF {count++} END {print count+0}'
  )"
  tracked_preview="$(
    printf '%s\n' "$tracked_lines" |
      awk 'NF {sub(/^[[:space:]]*[MADRCU?!][MADRCU?!]?[[:space:]]*/, "", $0); print}' |
      head -n 8 |
      paste -sd ',' -
  )"
  tracked_preview="$(printf '%s' "$tracked_preview" | tr -s ' ')"
  dirty_signature="$(printf '%s|%s' "$tracked_count" "$tracked_preview" | shasum -a 1 | awk '{print $1}')"
  if ! dirty_worktree_override_active "$dirty_signature"; then
    maybe_process_dirty_gate_reply "$dirty_signature" || true
  fi

  # Dirty-gate reply may have committed/merged in the same tick.
  # Re-read tracked state to avoid creating a new gate from stale snapshot.
  if git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- &&
    git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
    echo "WAIT_DIRTY_WORKTREE_RESOLVED_POST_ACTION=1"
    clear_dirty_gate_waiting_state_if_any
    clear_dirty_gate_local_state
  else
    tracked_lines="$(
      git -C "${ROOT_DIR}" status --short --untracked-files=no 2>/dev/null || true
    )"
    tracked_count="$(
      printf '%s\n' "$tracked_lines" | awk 'NF {count++} END {print count+0}'
    )"
    tracked_preview="$(
      printf '%s\n' "$tracked_lines" |
        awk 'NF {sub(/^[[:space:]]*[MADRCU?!][MADRCU?!]?[[:space:]]*/, "", $0); print}' |
        head -n 8 |
        paste -sd ',' -
    )"
    tracked_preview="$(printf '%s' "$tracked_preview" | tr -s ' ')"
    dirty_signature="$(printf '%s|%s' "$tracked_count" "$tracked_preview" | shasum -a 1 | awk '{print $1}')"

    if dirty_worktree_override_active "$dirty_signature"; then
      echo "WAIT_DIRTY_WORKTREE_OVERRIDE_ACTIVE=1"
      echo "WAIT_DIRTY_WORKTREE_OVERRIDE_SIGNATURE=${dirty_signature}"
      echo "WAIT_DIRTY_WORKTREE_TRACKED_COUNT=${tracked_count}"
      if [[ -n "$tracked_preview" ]]; then
        echo "WAIT_DIRTY_WORKTREE_TRACKED_FILES=${tracked_preview}"
      fi
      # Explicit override from dirty-gate issue: continue regular daemon flow on current signature.
    else
      echo "WAIT_DIRTY_WORKTREE_TRACKED=1"
      echo "WAIT_DIRTY_WORKTREE_TRACKED_COUNT=${tracked_count}"
      if [[ -n "$tracked_preview" ]]; then
        echo "WAIT_DIRTY_WORKTREE_TRACKED_FILES=${tracked_preview}"
      fi
      maybe_handle_dirty_worktree_gate "$tracked_count" "$tracked_preview" || true
      exit 0
    fi
  fi
else
  clear_dirty_gate_waiting_state_if_any
fi

# Сначала пытаемся доставить отложенные действия в GitHub (outbox).
outbox_out="$("${ROOT_DIR}/scripts/codex/github_outbox.sh" flush 2>&1 || true)"
if [[ -n "$outbox_out" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "OUTBOX_EMPTY=1" ]] && continue
    echo "$line"
  done <<< "$outbox_out"
fi

pending_actions="$(
  "${ROOT_DIR}/scripts/codex/github_outbox.sh" count 2>/dev/null |
    awk -F= '/^OUTBOX_PENDING_COUNT=/{print $2}' |
    tail -n1
)"
if [[ -n "$pending_actions" && "$pending_actions" != "0" ]]; then
  echo "WAIT_GITHUB_PENDING_ACTIONS=$pending_actions"
fi

reply_probe_out="$("${ROOT_DIR}/scripts/codex/daemon_check_replies.sh" 2>&1)"
while IFS= read -r line; do
  [[ -z "$line" || "$line" == "NO_WAITING_USER_REPLY=1" ]] && continue
  echo "$line"
done <<< "$reply_probe_out"
if printf '%s' "$reply_probe_out" | grep -q '^WAIT_USER_REPLY=1'; then
  exit 0
fi
if printf '%s' "$reply_probe_out" | grep -q '^USER_REPLY_RECEIVED=1'; then
  reply_kind="$(extract_kv "$reply_probe_out" "REPLY_KIND")"
  if is_review_feedback_kind "$reply_kind"; then
    review_task_id="$(extract_kv "$reply_probe_out" "TASK_ID")"
    review_issue_number="$(extract_kv "$reply_probe_out" "ISSUE_NUMBER")"
    review_item_id=""
    review_task_file_value=""
    if [[ -s "$review_task_file" ]]; then
      review_task_file_value="$(<"$review_task_file")"
    fi
    if [[ -s "$review_item_file" ]]; then
      review_item_id="$(<"$review_item_file")"
    fi
    if [[ -n "$review_task_file_value" && "$review_task_file_value" != "$review_task_id" ]]; then
      review_item_id=""
    fi

    if [[ -z "$review_task_id" || -z "$review_issue_number" ]]; then
      echo "BLOCKED_REVIEW_FEEDBACK_CONTEXT=1"
      echo "REVIEW_FEEDBACK_TASK_ID=${review_task_id}"
      echo "REVIEW_FEEDBACK_ISSUE_NUMBER=${review_issue_number}"
      exit 0
    fi

    status_target="$review_task_id"
    if [[ -n "$review_item_id" ]]; then
      status_target="$review_item_id"
    fi

    if status_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "$status_target" "$target_status" "$target_flow" 2>&1)"; then
      :
    else
      rc=$?
      emit_lines "$status_out"
      if is_github_network_error "$status_out" || [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=REVIEW_RESUME_STATUS_UPDATE"
        exit 0
      fi
      exit "$rc"
    fi
    emit_lines "$status_out"

    printf '%s\n' "$review_task_id" > "${CODEX_DIR}/daemon_active_task.txt"
    if [[ -n "$review_item_id" ]]; then
      printf '%s\n' "$review_item_id" > "${CODEX_DIR}/daemon_active_item_id.txt"
    else
      : > "${CODEX_DIR}/daemon_active_item_id.txt"
    fi
    printf '%s\n' "$review_issue_number" > "${CODEX_DIR}/daemon_active_issue_number.txt"
    printf '%s\n' "$review_task_id" > "${CODEX_DIR}/project_task_id.txt"
    "${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null

    : > "$review_task_file"
    : > "$review_item_file"
    : > "$review_issue_file"
    : > "$review_pr_file"

    echo "REVIEW_FEEDBACK_RESUMED=1"
    echo "REVIEW_FEEDBACK_TASK_ID=$review_task_id"
    echo "REVIEW_FEEDBACK_ISSUE_NUMBER=$review_issue_number"

    exec_out="$("${ROOT_DIR}/scripts/codex/executor_tick.sh" "$review_task_id" "$review_issue_number" 2>&1)"
    emit_lines "$exec_out"
    exit 0
  fi
fi

if ! maybe_release_active_task_on_status_mismatch; then
  rc=$?
  [[ "$rc" -eq 75 ]] && exit 0
fi

if [[ -s "${CODEX_DIR}/daemon_active_task.txt" ]]; then
  active_task_id="$(<"${CODEX_DIR}/daemon_active_task.txt")"
  echo "WAIT_ACTIVE_TASK_ID=$active_task_id"
  active_issue_number=""
  if [[ -s "${CODEX_DIR}/daemon_active_issue_number.txt" ]]; then
    active_issue_number="$(<"${CODEX_DIR}/daemon_active_issue_number.txt")"
    echo "WAIT_ACTIVE_ISSUE_NUMBER=$active_issue_number"
  fi

  if [[ -n "$active_issue_number" ]]; then
    exec_out="$("${ROOT_DIR}/scripts/codex/executor_tick.sh" "$active_task_id" "$active_issue_number" 2>&1)"
    emit_lines "$exec_out"
  else
    echo "BLOCKED_ACTIVE_TASK_WITHOUT_ISSUE=1"
  fi
  exit 0
fi

if health_out="$("${ROOT_DIR}/scripts/codex/github_health_check.sh" 2>&1)"; then
  :
else
  rc=$?
  emit_lines "$health_out"
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PRE_CLAIM"
    exit 0
  fi
  exit "$rc"
fi

open_prs_json=""
if open_prs_json="$(
  run_gh_retry_capture \
    gh pr list \
    --repo "$repo" \
    --state open \
    --base main \
    --head development \
    --json number,title,url \
    --jq '.'
)"; then
  :
else
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=OPEN_PR_CHECK"
    exit 0
  fi
  exit "$rc"
fi

open_pr_count="$(printf '%s' "$open_prs_json" | jq 'length')"
if (( open_pr_count > 0 )); then
  echo "WAIT_OPEN_PR_COUNT=$open_pr_count"
  printf '%s' "$open_prs_json" | jq -r '.[] | "OPEN_PR=#\(.number) \(.title) \(.url)"'
  exit 0
fi

project_json=""
if project_json="$(
  run_gh_retry_capture_project \
    gh api graphql \
    -f query='
query($projectId: ID!, $fieldsFirst: Int!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      fields(first: $fieldsFirst) {
        nodes {
          __typename
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
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
          flow: fieldValueByName(name: "Flow") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
          priority: fieldValueByName(name: "Priority") {
            __typename
            ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
          }
        }
      }
    }
  }
}
' \
    -f projectId="$project_id" \
    -F fieldsFirst=100 \
    -F itemsFirst=100
)"; then
  if graphql_payload_has_rate_limit "$project_json"; then
    rate_msg="$(graphql_payload_first_rate_limit_message "$project_json")"
    stats_payload="$(gql_stats_on_limit "PROJECT_QUERY" "$rate_msg")"
    IFS='|' read -r stats_requests stats_duration stats_start_utc stats_end_utc <<< "$stats_payload"
    echo "WAIT_GITHUB_RATE_LIMIT=1"
    echo "WAIT_GITHUB_RATE_LIMIT_STAGE=PROJECT_QUERY"
    echo "WAIT_GITHUB_RATE_LIMIT_MSG=$rate_msg"
    echo "GQL_STATS_WINDOW_REQUESTS=$stats_requests"
    echo "GQL_STATS_WINDOW_DURATION_SEC=$stats_duration"
    [[ -n "$stats_start_utc" ]] && echo "GQL_STATS_WINDOW_START_UTC=$stats_start_utc"
    [[ -n "$stats_end_utc" ]] && echo "GQL_STATS_WINDOW_END_UTC=$stats_end_utc"
    exit 0
  fi
  gql_stats_on_success
else
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PROJECT_QUERY"
    exit 0
  fi
  exit "$rc"
fi

matched_json="$(
  printf '%s' "$project_json" | jq -c --arg trigger "$trigger_status" '
    def norm: gsub("^\\s+|\\s+$";"") | ascii_downcase;
    .data.node as $project
    | (($project.fields.nodes[] | select(.name=="Status") | .options[] | select((.name | norm) == ($trigger | norm)) | .id) // null) as $trigger_option_id
    | [
      $project.items.nodes[]
      | {
          item_id: .id,
          content_type: (.content.__typename // ""),
          issue_number: (.content.number // ""),
          title: (.content.title // ""),
          task_id: (
            . as $item
            | (($item.taskId.text // "") | gsub("^\\s+|\\s+$";"")) as $task_field
            | if $task_field != "" then $task_field
              else (
                ([ (($item.content.title // "") | capture("(?<id>PL-[0-9]{3})").id) ] | first // "") as $pl_from_title
                | if $pl_from_title != "" then $pl_from_title
                  else (
                    if ($item.content.__typename // "") == "Issue" and ($item.content.number != null)
                    then ("ISSUE-" + (($item.content.number | tostring)))
                    else ""
                    end
                  )
                  end
              )
              end
          ),
          status_name: (.status.name // ""),
          status_option_id: (.status.optionId // ""),
          flow: (.flow.name // ""),
          priority: (.priority.name // "")
        }
      | select(
          if $trigger_option_id == null
          then ((.status_name | norm) == ($trigger | norm))
          else (.status_option_id == $trigger_option_id)
          end
        )
      | select((((.title // "") | test("^DIRTY-GATE:")) | not))
      | .pri_w = (
          if .priority == "P0" then 0
          elif .priority == "P1" then 1
          elif .priority == "P2" then 2
          elif .priority == "P3" then 3
          else 9
          end
        )
      | .num = ((try (.issue_number | tonumber) catch 999999))
    ]
    | sort_by(.pri_w, .num)
  '
)"

matched_count="$(printf '%s' "$matched_json" | jq 'length')"
queue_json="$(printf '%s' "$matched_json" | jq -c '[.[] | select(.content_type == "Issue")]')"
queue_count="$(printf '%s' "$queue_json" | jq 'length')"

if (( matched_count > 0 && queue_count == 0 )); then
  echo "NO_ISSUE_TASKS_IN_TRIGGER_STATUS=$trigger_status"
  printf '%s' "$matched_json" | jq -r '.[] | "IGNORED_NON_ISSUE=\(.content_type)\t\(.title)"'
  exit 0
fi

if (( queue_count == 0 )); then
  fallback_items_json=""
  if fallback_items_json="$(
    run_gh_retry_capture_project \
      gh project item-list "$project_number" \
      --owner "$project_owner" \
      --limit "$project_items_limit" \
      --format json \
      --jq '.'
  )"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=PROJECT_ITEM_LIST_FALLBACK"
      exit 0
    fi
    exit "$rc"
  fi

  fallback_queue_json="$(
    printf '%s' "$fallback_items_json" | jq -c --arg trigger "$trigger_status" '
      def norm: gsub("^\\s+|\\s+$";"") | ascii_downcase;
      [
        .items[]
        | {
            item_id: .id,
            content_type: (.content.type // ""),
            issue_number: (.content.number // ""),
            title: (.title // .content.title // ""),
            task_id: (
              . as $item
              | (($item."task ID" // "") | gsub("^\\s+|\\s+$";"")) as $task_field
              | if $task_field != "" then $task_field
                else (
                  ([ (($item.title // $item.content.title // "") | capture("(?<id>PL-[0-9]{3})").id) ] | first // "") as $pl_from_title
                  | if $pl_from_title != "" then $pl_from_title
                    else (
                      if ($item.content.type // "") == "Issue" and ($item.content.number != null)
                      then ("ISSUE-" + (($item.content.number | tostring)))
                      else ""
                      end
                    )
                    end
                )
                end
            ),
            status_name: (.status // ""),
            flow: (.flow // ""),
            priority: (.priority // "")
          }
        | select((.status_name | norm) == ($trigger | norm))
        | .pri_w = (
            if .priority == "P0" then 0
            elif .priority == "P1" then 1
            elif .priority == "P2" then 2
            elif .priority == "P3" then 3
            else 9
            end
          )
        | .num = ((try (.issue_number | tonumber) catch 999999))
      ]
      | sort_by(.pri_w, .num)
      | [.[] | select(.content_type == "Issue" and (((.title // "") | test("^DIRTY-GATE:")) | not))]
    '
  )"

  fallback_queue_count="$(printf '%s' "$fallback_queue_json" | jq 'length')"
  if (( fallback_queue_count == 0 )); then
    echo "NO_TASKS_IN_TRIGGER_STATUS=$trigger_status"
    exit 0
  fi

  echo "FALLBACK_PROJECT_ITEM_LIST_USED=1"
  queue_json="$fallback_queue_json"
  queue_count="$fallback_queue_count"
fi

valid_queue_json="$(printf '%s' "$queue_json" | jq -c '[.[] | select(.task_id != "")]')"
valid_queue_count="$(printf '%s' "$valid_queue_json" | jq 'length')"

if (( valid_queue_count == 0 )); then
  echo "BLOCKED_TRIGGER_TASKS_WITHOUT_TASK_ID=$queue_count"
  printf '%s' "$queue_json" | jq -r '.[] | "QUEUE_ITEM_MISSING_TASK_ID=\(.priority)\t\(.title)"'
  exit 0
fi

if (( valid_queue_count > 1 )); then
  echo "BLOCKED_MULTIPLE_TRIGGER_TASKS=$valid_queue_count"
  printf '%s' "$valid_queue_json" | jq -r '.[] | "QUEUE_TASK=\(.task_id)\t\(.priority)\t\(.title)"'
  exit 0
fi

item_id="$(printf '%s' "$valid_queue_json" | jq -r '.[0].item_id')"
issue_number="$(printf '%s' "$valid_queue_json" | jq -r '.[0].issue_number')"
task_id="$(printf '%s' "$valid_queue_json" | jq -r '.[0].task_id')"
title="$(printf '%s' "$valid_queue_json" | jq -r '.[0].title')"

if [[ -z "$task_id" || "$task_id" == "null" ]]; then
  echo "Task in trigger status has no resolvable task id"
  exit 1
fi

if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Task in trigger status has no project item id"
  exit 1
fi

if [[ -z "$issue_number" || "$issue_number" == "null" ]]; then
  echo "Task in trigger status has no issue number"
  exit 1
fi

issue_body=""
if issue_body="$(
  run_gh_retry_capture \
    gh issue view "$issue_number" \
    --repo "$repo" \
    --json body \
    --jq '.body // ""'
)"; then
  :
else
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=DEPENDENCY_BODY"
    exit 0
  fi
  exit "$rc"
fi

depends_line="$(parse_flow_meta_line "$issue_body" "Depends-On")"
execution_mode="$(parse_flow_meta_line "$issue_body" "Execution-Mode")"
auto_queue="$(parse_flow_meta_line "$issue_body" "Auto-Queue-When-Unblocked")"

[[ -z "$depends_line" ]] && depends_line="none"
[[ -z "$execution_mode" ]] && execution_mode="daemon"
[[ -z "$auto_queue" ]] && auto_queue="false"

echo "FLOW_META_DEPENDS_ON=$depends_line"
echo "FLOW_META_EXECUTION_MODE=$execution_mode"
echo "FLOW_META_AUTO_QUEUE=$auto_queue"

blocked_dependencies=()

execution_mode_norm="$(printf '%s' "$execution_mode" | tr '[:upper:]' '[:lower:]')"
if [[ "$execution_mode_norm" == "manual" ]]; then
  blocked_dependencies+=("Execution-Mode=manual")
fi

if [[ "$depends_line" != "none" ]]; then
  IFS=',' read -r -a dep_tokens <<< "$depends_line"
  for raw_dep in "${dep_tokens[@]}"; do
    dep_token="$(trim "$raw_dep")"
    [[ -z "$dep_token" ]] && continue

    dep_norm="$(printf '%s' "$dep_token" | tr '[:upper:]' '[:lower:]')"
    if [[ "$dep_norm" == "none" ]]; then
      continue
    fi

    dep_issue_numbers=()
    if [[ "$dep_token" =~ ^#([0-9]+)$ ]]; then
      dep_issue_numbers+=("${BASH_REMATCH[1]}")
    elif [[ "$dep_token" =~ ^ISSUE-([0-9]+)$ ]]; then
      dep_issue_numbers+=("${BASH_REMATCH[1]}")
    elif [[ "$dep_token" =~ ^([0-9]+)$ ]]; then
      dep_issue_numbers+=("${BASH_REMATCH[1]}")
    elif [[ "$dep_token" =~ ^(#[0-9]+)+$ ]]; then
      while IFS= read -r dep_num; do
        [[ -z "$dep_num" ]] && continue
        dep_issue_numbers+=("$dep_num")
      done < <(printf '%s' "$dep_token" | grep -oE '[0-9]+')
    fi

    if (( ${#dep_issue_numbers[@]} == 0 )); then
      blocked_dependencies+=("$dep_token")
      continue
    fi

    for dep_issue_number in "${dep_issue_numbers[@]}"; do
      dep_resolved_rc=0
      if dependency_issue_resolved "$dep_issue_number"; then
        :
      else
        dep_resolved_rc=$?
        if [[ "$dep_resolved_rc" -eq 75 ]]; then
          echo "WAIT_GITHUB_API_UNSTABLE=1"
          echo "WAIT_GITHUB_STAGE=DEPENDENCY_CHECK"
          exit 0
        fi
        if [[ "$dep_resolved_rc" -ne 1 ]]; then
          exit "$dep_resolved_rc"
        fi
        blocked_dependencies+=("#${dep_issue_number}")
      fi
    done
  done
fi

if (( ${#blocked_dependencies[@]} > 0 )); then
  blocked_csv="$(IFS=', '; printf '%s' "${blocked_dependencies[*]}")"
  echo "WAIT_DEPENDENCIES=1"
  echo "WAIT_DEPENDENCIES_TASK_ID=$task_id"
  echo "WAIT_DEPENDENCIES_ISSUE_NUMBER=$issue_number"
  echo "WAIT_DEPENDENCIES_BLOCKERS=$blocked_csv"
  notify_dependency_blocked_once "$task_id" "$issue_number" "$blocked_csv"
  exit 0
fi

skip_sync_branches=0
if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  tracked_lines_sync="$(
    git -C "${ROOT_DIR}" status --short --untracked-files=no 2>/dev/null || true
  )"
  tracked_count_sync="$(
    printf '%s\n' "$tracked_lines_sync" | awk 'NF {count++} END {print count+0}'
  )"
  tracked_preview_sync="$(
    printf '%s\n' "$tracked_lines_sync" |
      awk 'NF {sub(/^[[:space:]]*[MADRCU?!][MADRCU?!]?[[:space:]]*/, "", $0); print}' |
      head -n 8 |
      paste -sd ',' -
  )"
  tracked_preview_sync="$(printf '%s' "$tracked_preview_sync" | tr -s ' ')"
  dirty_signature_sync="$(printf '%s|%s' "$tracked_count_sync" "$tracked_preview_sync" | shasum -a 1 | awk '{print $1}')"
  if dirty_worktree_override_active "$dirty_signature_sync"; then
    skip_sync_branches=1
    echo "WAIT_BRANCH_SYNC_SKIPPED_DIRTY_OVERRIDE=1"
    echo "WAIT_DIRTY_WORKTREE_OVERRIDE_SIGNATURE=${dirty_signature_sync}"
  fi
fi

if (( skip_sync_branches == 0 )); then
  if sync_out="$("${ROOT_DIR}/scripts/codex/sync_branches.sh" 2>&1)"; then
    :
  else
    rc=$?
    emit_lines "$sync_out"
    if is_github_network_error "$sync_out"; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAIT_GITHUB_STAGE=SYNC_BRANCHES"
      exit 0
    fi
    if [[ "$rc" -eq 78 ]] ||
      printf '%s' "$sync_out" | grep -Eq 'BRANCH_SYNC_CONFLICT=1|Not possible to fast-forward, aborting.|Automatic merge failed'; then
      echo "WAIT_BRANCH_SYNC_REQUIRED=1"
      echo "WAIT_BRANCH_STAGE=SYNC_BRANCHES"
      exit 0
    fi
    exit "$rc"
  fi
  emit_lines "$sync_out"
fi

if status_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "$item_id" "$target_status" "$target_flow" 2>&1)"; then
  :
else
  rc=$?
  emit_lines "$status_out"
  if is_github_network_error "$status_out"; then
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAIT_GITHUB_STAGE=PROJECT_STATUS_UPDATE"
    exit 0
  fi
  exit "$rc"
fi
emit_lines "$status_out"

rm -f "${CODEX_DIR}/daemon_dependency_blocked_signature.txt"
: > "$review_task_file"
: > "$review_item_file"
: > "$review_issue_file"
: > "$review_pr_file"

printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_active_task.txt"
printf '%s\n' "$item_id" > "${CODEX_DIR}/daemon_active_item_id.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_active_issue_number.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/project_task_id.txt"
"${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_last_claim_utc.txt"

echo "CLAIMED_TASK_ID=$task_id"
echo "CLAIMED_ITEM_ID=$item_id"
echo "CLAIMED_ISSUE_NUMBER=$issue_number"
echo "CLAIMED_TITLE=$title"
echo "CLAIMED_FROM_STATUS=$trigger_status"
echo "CLAIMED_TO_STATUS=$target_status"
