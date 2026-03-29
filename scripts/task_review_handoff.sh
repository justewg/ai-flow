#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> [reason]"
  exit 1
fi

task_id="$1"
issue_number="$2"
handoff_reason="${3:-automation_stopped}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"

CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"
codex_resolve_flow_config

REPO="$FLOW_GITHUB_REPO"
STATE_DIR="$(codex_resolve_state_dir)"
PROFILE_NAME="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
BUDGET_FILE="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$STATE_DIR" "$PROFILE_NAME")"
NOOP_PROBE_FILE="$(task_worktree_noop_probe_file "$task_id" "$issue_number" "$STATE_DIR" "$PROFILE_NAME")"

active_task_file="${CODEX_DIR}/daemon_active_task.txt"
active_item_file="${CODEX_DIR}/daemon_active_item_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
review_branch_file="${CODEX_DIR}/daemon_review_branch_name.txt"
waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
waiting_task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
waiting_question_id_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
waiting_pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"
project_task_file="${CODEX_DIR}/project_task_id.txt"
claim_epoch_file="${CODEX_DIR}/daemon_last_claim_epoch.txt"

emit_nonempty_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

is_github_network_error() {
  local text="$1"
  printf '%s' "$text" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect|api rate limit already exceeded|graphql_rate_limit|rate limit'
}

emit_runtime_v2_event() {
  local event_type="$1"
  local event_id="$2"
  local dedup_key="$3"
  local payload_json="${4:-{}}"
  local event_out rc

  if event_out="$(
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_apply_event.sh" \
      "$task_id" "$issue_number" "$event_type" "$event_id" "$dedup_key" "$payload_json" 2>&1
  )"; then
    emit_nonempty_lines "$event_out"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_EVENT_ERROR(rc=$rc): $line"
    done <<< "$event_out"
  fi
}

reconcile_runtime_v2_primary_context() {
  local reconcile_out rc
  if reconcile_out="$(
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_reconcile_primary_context.sh" 2>&1
  )"; then
    emit_nonempty_lines "$reconcile_out"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_RECONCILE_ERROR(rc=$rc): $line"
    done <<< "$reconcile_out"
  fi
}

human_reason_label() {
  case "$1" in
    profile_breach)
      printf '%s' "automation_profile_breach"
      ;;
    provider_quota_exceeded)
      printf '%s' "provider_quota_exceeded"
      ;;
    intake_human_needed)
      printf '%s' "intake_human_needed"
      ;;
    intake_blocked)
      printf '%s' "intake_blocked"
      ;;
    already_satisfied)
      printf '%s' "already_satisfied"
      ;;
    *)
      printf '%s' "automation_stopped"
      ;;
  esac
}

reason_explanation() {
  case "$1" in
    profile_breach)
      printf '%s' "Автоматика остановила выполнение до создания PR, потому что задача вышла за текущий budget execution profile."
      ;;
    provider_quota_exceeded)
      printf '%s' "Автоматика остановила выполнение до создания PR, потому что провайдер вернул quota exceeded."
      ;;
    intake_human_needed)
      printf '%s' "Автоматика не начала выполнение, потому что intake layer не смогла надёжно нормализовать задачу и перевела её в human-needed review."
      ;;
    intake_blocked)
      printf '%s' "Автоматика не начала выполнение, потому что intake layer пометила задачу как blocked."
      ;;
    already_satisfied)
      printf '%s' "Автоматика не создавала PR, потому что требуемая правка уже присутствует в репозитории."
      ;;
    *)
      printf '%s' "Автоматика остановила выполнение до создания PR и передаёт задачу в review без PR."
      ;;
  esac
}

reason_detail_block() {
  local reason="$1"
  local total_tokens=""
  local threshold_tokens=""
  local confidence=""
  local detail=""
  local target_file=""
  local matched_literal=""

  case "$reason" in
    profile_breach)
      if [[ -f "$BUDGET_FILE" ]]; then
        total_tokens="$(jq -r '.totalTokens // empty' "$BUDGET_FILE" 2>/dev/null || true)"
        threshold_tokens="$(jq -r '.thresholdTokens // empty' "$BUDGET_FILE" 2>/dev/null || true)"
      fi
      if [[ -n "$total_tokens" && -n "$threshold_tokens" ]]; then
        detail="Детали: израсходовано ${total_tokens} токенов при лимите ${threshold_tokens}."
      fi
      ;;
    intake_human_needed|intake_blocked)
      if [[ -f "$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$STATE_DIR" "$PROFILE_NAME")" ]]; then
        confidence="$(jq -r '.confidence.label // empty' "$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$STATE_DIR" "$PROFILE_NAME")" 2>/dev/null || true)"
      fi
      if [[ -n "$confidence" ]]; then
        detail="Детали: confidence интерпретации = ${confidence}."
      fi
      ;;
    already_satisfied)
      if [[ -f "$NOOP_PROBE_FILE" ]]; then
        target_file="$(jq -r '.targetFile // empty' "$NOOP_PROBE_FILE" 2>/dev/null || true)"
        matched_literal="$(jq -r '.matchedLiteral // empty' "$NOOP_PROBE_FILE" 2>/dev/null || true)"
      fi
      if [[ -n "$target_file" && -n "$matched_literal" ]]; then
        detail="Детали: в ${target_file} уже найдено `${matched_literal}`."
      elif [[ -n "$target_file" ]]; then
        detail="Детали: целевая правка уже присутствует в ${target_file}."
      fi
      ;;
  esac

  printf '%s' "$detail"
}

build_comment_body() {
  local reason="$1"
  local explanation detail
  explanation="$(reason_explanation "$reason")"
  detail="$(reason_detail_block "$reason")"

  cat <<EOF
CODEX_SIGNAL: AGENT_IN_REVIEW
CODEX_TASK: ${task_id}
CODEX_EXPECT: USER_REVIEW
CODEX_REVIEW_KIND: AUTOMATION_STOP
CODEX_AUTOMATION_STOP_REASON: ${reason}

${explanation}
${detail}
PR не создавался.

Ответь комментарием ниже, как действовать дальше: можно уточнить задачу, подтвердить, что текущего состояния достаточно, или явно дать новую команду на продолжение.
EOF
}

find_existing_comment() {
  local comments_json="$1"
  printf '%s' "$comments_json" |
    jq -r --arg task "$task_id" --arg reason "$handoff_reason" '
      [
        .[]
        | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_IN_REVIEW$")))
        | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REVIEW$")))
        | select(((.body // "") | test("(?m)^CODEX_TASK: " + $task + "$")))
        | select(((.body // "") | test("(?m)^CODEX_REVIEW_KIND: AUTOMATION_STOP$")))
        | select(((.body // "") | test("(?m)^CODEX_AUTOMATION_STOP_REASON: " + $reason + "$")))
      ] | last | [.id // "", .html_url // ""] | @tsv
    '
}

status_target="$task_id"
if [[ -s "$active_item_file" ]]; then
  status_target="$(<"$active_item_file")"
elif [[ -s "$review_item_file" ]]; then
  status_target="$(<"$review_item_file")"
fi

comments_json=""
if comments_json="$(
  "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
    gh api "repos/${REPO}/issues/${issue_number}/comments?per_page=100" 2>/dev/null
)"; then
  :
else
  comments_json="[]"
fi

existing_comment_tsv="$(find_existing_comment "$comments_json" || true)"
comment_id="$(printf '%s' "$existing_comment_tsv" | cut -f1)"
comment_url="$(printf '%s' "$existing_comment_tsv" | cut -f2)"
pending_post="0"

if [[ -n "$comment_id" ]]; then
  echo "REVIEW_HANDOFF_COMMENT_REUSED=1"
else
  comment_body="$(build_comment_body "$handoff_reason")"
  err_file="$(mktemp "${STATE_TMP_DIR}/review_handoff_gh_err.XXXXXX")"
  if comment_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments" \
      -f body="$comment_body" 2>"$err_file"
  )"; then
    emit_nonempty_lines "$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file"
    comment_id="$(printf '%s' "$comment_json" | jq -r '.id // empty')"
    comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url // empty')"
    echo "REVIEW_HANDOFF_COMMENT_POSTED=1"
  else
    rc=$?
    comment_err="$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file"
    emit_nonempty_lines "$comment_err"
    if [[ "$rc" -eq 75 ]] || is_github_network_error "$comment_err"; then
      tmp_body="$(mktemp "${STATE_TMP_DIR}/review_handoff_body.XXXXXX")"
      printf '%s\n' "$comment_body" > "$tmp_body"
      if queue_out="$(
        "${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" \
          enqueue_issue_comment \
          "$REPO" \
          "$issue_number" \
          "$tmp_body" \
          "$task_id" \
          "REVIEW_FEEDBACK" \
          "1" 2>&1
      )"; then
        rm -f "$tmp_body"
        emit_nonempty_lines "$queue_out"
        pending_post="1"
        echo "REVIEW_HANDOFF_COMMENT_QUEUED_OUTBOX=1"
      else
        qrc=$?
        rm -f "$tmp_body"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "REVIEW_HANDOFF_OUTBOX_ERROR(rc=$qrc): $line"
        done <<< "$queue_out"
        exit "$qrc"
      fi
    else
      exit "$rc"
    fi
  fi
fi

if status_out="$("${CODEX_SHARED_SCRIPTS_DIR}/project_set_status.sh" "$status_target" "Review" "In Review" 2>&1)"; then
  emit_nonempty_lines "$status_out"
else
  status_rc=$?
  emit_nonempty_lines "$status_out"
  if [[ "$status_rc" -eq 75 ]] || is_github_network_error "$status_out"; then
    runtime_out="$("${CODEX_SHARED_SCRIPTS_DIR}/project_status_runtime.sh" enqueue "$status_target" "Review" "In Review" "review-handoff:${handoff_reason}" 2>&1 || true)"
    emit_nonempty_lines "$runtime_out"
    echo "REVIEW_HANDOFF_STATUS_DEFERRED=1"
  else
    echo "REVIEW_HANDOFF_STATUS_ERROR=1"
    echo "REVIEW_HANDOFF_STATUS_RC=${status_rc}"
  fi
fi

printf '%s\n' "$task_id" > "$review_task_file"
if [[ -s "$active_item_file" ]]; then
  cp "$active_item_file" "$review_item_file"
else
  : > "$review_item_file"
fi
printf '%s\n' "$issue_number" > "$review_issue_file"
: > "$review_pr_file"
: > "$review_branch_file"

printf '%s\n' "$issue_number" > "$waiting_issue_file"
printf '%s\n' "$task_id" > "$waiting_task_file"
if [[ -n "$comment_id" ]]; then
  printf '%s\n' "$comment_id" > "$waiting_question_id_file"
else
  printf '0\n' > "$waiting_question_id_file"
fi
printf '%s\n' "REVIEW_FEEDBACK" > "$waiting_kind_file"
printf '%s\n' "$pending_post" > "$waiting_pending_post_file"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$waiting_since_file"
if [[ -n "$comment_url" ]]; then
  printf '%s\n' "$comment_url" > "$waiting_comment_url_file"
else
  : > "$waiting_comment_url_file"
fi

: > "$active_task_file"
: > "$active_item_file"
: > "$active_issue_file"
: > "$project_task_file"
: > "$claim_epoch_file"

if [[ -n "$comment_id" ]]; then
  wait_payload="$(
    jq -nc \
      --arg waitCommentId "$comment_id" \
      --arg reason "$(human_reason_label "$handoff_reason")" \
      --arg kind "REVIEW_FEEDBACK" \
      --arg commentUrl "${comment_url:-}" \
      --arg waitingSince "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{waitCommentId:$waitCommentId, reason:$reason, kind:$kind, commentUrl:$commentUrl, waitingSince:$waitingSince, pendingPost:false}'
  )"
  emit_runtime_v2_event \
    "human.wait_requested" \
    "legacy-v2-review-handoff-${task_id}-${comment_id}" \
    "legacy.review_handoff.wait:${task_id}:${comment_id}" \
    "$wait_payload"
fi
reconcile_runtime_v2_primary_context

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh" >/dev/null

echo "REVIEW_HANDOFF_ENABLED=1"
echo "REVIEW_HANDOFF_TASK_ID=${task_id}"
echo "REVIEW_HANDOFF_ISSUE_NUMBER=${issue_number}"
echo "REVIEW_HANDOFF_REASON=${handoff_reason}"
[[ -n "$comment_id" ]] && echo "REVIEW_HANDOFF_COMMENT_ID=${comment_id}"
[[ -n "$comment_url" ]] && echo "REVIEW_HANDOFF_COMMENT_URL=${comment_url}"
echo "WAIT_REVIEW_FEEDBACK=1"
