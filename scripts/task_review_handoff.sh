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
    materialize_failed)
      printf '%s' "materialize_failed"
      ;;
    runtime_gate_max_executions_per_task)
      printf '%s' "runtime_gate_max_executions_per_task"
      ;;
    runtime_gate_max_token_usage_per_task)
      printf '%s' "runtime_gate_max_token_usage_per_task"
      ;;
    runtime_gate_max_estimated_cost_per_task)
      printf '%s' "runtime_gate_max_estimated_cost_per_task"
      ;;
    runtime_gate_blocked)
      printf '%s' "runtime_gate_blocked"
      ;;
    github_api_unavailable)
      printf '%s' "github_api_unavailable"
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
    materialize_failed)
      printf '%s' "Автоматика не смогла подготовить task worktree и toolkit до старта executor, поэтому задача передана в review без PR."
      ;;
    runtime_gate_max_executions_per_task)
      printf '%s' "Автоматика остановила дальнейшую обработку задачи, потому что исчерпан лимит числа запусков для этого taskflow."
      ;;
    runtime_gate_max_token_usage_per_task)
      printf '%s' "Автоматика остановила дальнейшую обработку задачи, потому что исчерпан лимит суммарного token budget для этого taskflow."
      ;;
    runtime_gate_max_estimated_cost_per_task)
      printf '%s' "Автоматика остановила дальнейшую обработку задачи, потому что исчерпан лимит допустимой стоимости для этого taskflow."
      ;;
    runtime_gate_blocked)
      printf '%s' "Автоматика остановила дальнейшую обработку задачи, потому что runtime v2 gate заблокировала продолжение по внутренним ограничениям taskflow."
      ;;
    github_api_unavailable)
      printf '%s' "Автоматика остановила дальнейшую обработку задачи, потому что GitHub API сейчас недоступен, а без него нельзя надёжно продолжить taskflow."
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
  local execution_profile_file=""
  local decision_reason=""
  local interpreted_intent=""
  local target_count=""
  local target_preview=""
  local detail_lines="0"

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
      execution_profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$STATE_DIR" "$PROFILE_NAME")"
      if [[ -f "$execution_profile_file" ]]; then
        confidence="$(jq -r '.confidence.label // empty' "$execution_profile_file" 2>/dev/null || true)"
        decision_reason="$(jq -r '.reason // empty' "$execution_profile_file" 2>/dev/null || true)"
        interpreted_intent="$(jq -r '.interpretedIntent // empty' "$execution_profile_file" 2>/dev/null || true)"
        target_count="$(jq -r '(.candidateTargetFiles // []) | length' "$execution_profile_file" 2>/dev/null || true)"
        target_preview="$(
          jq -r '.candidateTargetFiles // [] | .[:3][]?' "$execution_profile_file" 2>/dev/null || true
        )"
      fi
      detail="Детали:"
      [[ -n "$decision_reason" ]] && detail="${detail}
- decision reason: ${decision_reason}"
      [[ -n "$decision_reason" ]] && detail_lines="1"
      [[ -n "$confidence" ]] && detail="${detail}
- confidence интерпретации: ${confidence}"
      [[ -n "$confidence" ]] && detail_lines="1"
      [[ -n "$interpreted_intent" ]] && detail="${detail}
- понятое намерение: ${interpreted_intent}"
      [[ -n "$interpreted_intent" ]] && detail_lines="1"
      if [[ -n "$target_count" ]]; then
        if [[ "$target_count" == "0" ]]; then
          detail="${detail}
- candidate target files: none (0)
- не удалось надёжно привязать задачу к конкретному файлу или компоненту"
          detail_lines="1"
        else
          detail="${detail}
- candidate target files: ${target_count}"
          detail_lines="1"
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            detail="${detail}
  - ${line}"
          done <<< "$target_preview"
        fi
      fi
      [[ "$detail_lines" == "1" ]] || detail=""
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
    runtime_gate_max_executions_per_task)
      detail="Детали: runtime v2 gate вернула reason \`max_executions_per_task\`."
      ;;
    runtime_gate_max_token_usage_per_task)
      detail="Детали: runtime v2 gate вернула reason \`max_token_usage_per_task\`."
      ;;
    runtime_gate_max_estimated_cost_per_task)
      detail="Детали: runtime v2 gate вернула reason \`max_estimated_cost_per_task\`."
      ;;
    runtime_gate_blocked)
      detail="Детали: продолжение было остановлено на этапе runtime v2 gate."
      ;;
    github_api_unavailable)
      detail="Детали: продолжение требовало обращения к GitHub API, но запросы в текущий момент не проходили."
      ;;
  esac

  printf '%s' "$detail"
}

existing_review_pr_number() {
  local current_review_task current_review_pr
  current_review_task="$(cat "$review_task_file" 2>/dev/null || true)"
  current_review_pr="$(cat "$review_pr_file" 2>/dev/null || true)"
  if [[ "$current_review_task" == "$task_id" && -n "$current_review_pr" ]]; then
    printf '%s' "$current_review_pr"
  fi
}

existing_review_branch_name() {
  local current_review_task current_review_branch
  current_review_task="$(cat "$review_task_file" 2>/dev/null || true)"
  current_review_branch="$(cat "$review_branch_file" 2>/dev/null || true)"
  if [[ "$current_review_task" == "$task_id" && -n "$current_review_branch" ]]; then
    printf '%s' "$current_review_branch"
  fi
}

build_comment_body() {
  local reason="$1"
  local explanation detail existing_pr review_note
  explanation="$(reason_explanation "$reason")"
  detail="$(reason_detail_block "$reason")"
  existing_pr="$(existing_review_pr_number)"
  if [[ -n "$existing_pr" ]]; then
    review_note="Новый PR не создавался; дальнейшая автоматическая доработка по уже открытому PR #${existing_pr} не продолжена."
  else
    review_note="PR не создавался."
  fi

  cat <<EOF
CODEX_SIGNAL: AGENT_IN_REVIEW
CODEX_TASK: ${task_id}
CODEX_EXPECT: USER_REVIEW
CODEX_REVIEW_KIND: AUTOMATION_STOP
CODEX_AUTOMATION_STOP_REASON: ${reason}

${explanation}
${detail}
${review_note}

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
existing_pr_number="$(existing_review_pr_number)"
existing_branch_name="$(existing_review_branch_name)"
if [[ -n "$existing_pr_number" ]]; then
  printf '%s\n' "$existing_pr_number" > "$review_pr_file"
else
  : > "$review_pr_file"
fi
if [[ -n "$existing_branch_name" ]]; then
  printf '%s\n' "$existing_branch_name" > "$review_branch_file"
else
  : > "$review_branch_file"
fi

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
