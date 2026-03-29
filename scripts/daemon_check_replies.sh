#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"
codex_resolve_flow_config
REPO="${GITHUB_REPO:-justewg/planka}"
BASE_BRANCH="${FLOW_BASE_BRANCH}"
HEAD_BRANCH="${FLOW_HEAD_BRANCH}"

issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
question_id_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"

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
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_EVENT: $line"
    done <<< "$event_out"
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
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_RECONCILE: $line"
    done <<< "$reconcile_out"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "RUNTIME_V2_RECONCILE_ERROR(rc=$rc): $line"
    done <<< "$reconcile_out"
  fi
}

build_wait_payload() {
  local wait_comment_id="$1"
  local wait_reason="$2"
  local wait_kind="$3"
  local comment_url="$4"
  local pending_post="$5"
  local waiting_since="$6"

  jq -nc \
    --arg waitCommentId "$wait_comment_id" \
    --arg reason "$wait_reason" \
    --arg kind "$wait_kind" \
    --arg commentUrl "$comment_url" \
    --arg waitingSince "$waiting_since" \
    --argjson pendingPost "$pending_post" \
    '{
      waitCommentId:$waitCommentId,
      reason:$reason,
      kind:$kind,
      commentUrl:$commentUrl,
      waitingSince:$waitingSince,
      pendingPost:$pendingPost
    }'
}

build_review_feedback_payload() {
  local wait_comment_id="$1"
  local comment_url="$2"
  local pending_post="$3"
  local waiting_since="$4"
  local wait_reason="$5"

  jq -nc \
    --arg waitCommentId "$wait_comment_id" \
    --arg commentUrl "$comment_url" \
    --arg waitingSince "$waiting_since" \
    --arg reason "$wait_reason" \
    --argjson pendingPost "$pending_post" \
    '{
      waitCommentId:$waitCommentId,
      commentUrl:$commentUrl,
      waitingSince:$waitingSince,
      reason:$reason,
      pendingPost:$pendingPost
    }'
}
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
review_branch_file="${CODEX_DIR}/daemon_review_branch_name.txt"

is_review_feedback_kind() {
  local value="$1"
  [[ "$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')" == "REVIEW_FEEDBACK" ]]
}

is_blocker_kind() {
  local value="$1"
  [[ "$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')" == "BLOCKER" ]]
}

has_resume_intent() {
  local body="$1"
  printf '%s' "$body" | grep -Eiq \
    '(^|[[:space:][:punct:]])(go|lgtm|approve|approved)($|[[:space:][:punct:]])|продолж|возобнов|выполняй|делай[[:space:]]+дальше|можно[[:space:]]+продолж|разрешаю|ок[, ]*продолж'
}

executor_is_live() {
  local exec_pid=""
  [[ -s "${CODEX_DIR}/executor_pid.txt" ]] || return 1
  exec_pid="$(<"${CODEX_DIR}/executor_pid.txt")"
  [[ "$exec_pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$exec_pid" 2>/dev/null
}

detect_reply_mode() {
  local kind="$1"
  local body="$2"
  local explicit_mode=""
  local first_line=""
  explicit_mode="$(
    printf '%s\n' "$body" |
      sed -n 's/^CODEX_MODE:[[:space:]]*//p' |
      head -n1 |
      tr '[:lower:]' '[:upper:]'
  )"
  if [[ "$explicit_mode" == "QUESTION" || "$explicit_mode" == "REWORK" ]]; then
    printf '%s' "$explicit_mode"
    return 0
  fi
  if [[ "$explicit_mode" == "FINALIZE" || "$explicit_mode" == "CONTINUE" || "$explicit_mode" == "RESUME" ]]; then
    printf 'REWORK'
    return 0
  fi

  if is_blocker_kind "$kind"; then
    first_line="$(printf '%s\n' "$body" | head -n1 | tr -d '\r')"

    # Short option replies like "1", "1.", "п.1", "2)" should resume blocker flow
    # even if locale-sensitive word matching misses Cyrillic imperatives.
    if printf '%s\n' "$first_line" | grep -Eq '^[[:space:]]*([PpПп]\.?[[:space:]]*)?1([.)][[:space:]]*.*)?$'; then
      printf 'REWORK'
      return 0
    fi
    if printf '%s\n' "$first_line" | grep -Eq '^[[:space:]]*([PpПп]\.?[[:space:]]*)?2([.)][[:space:]]*.*)?$'; then
      printf 'REWORK'
      return 0
    fi
    if printf '%s\n' "$first_line" | grep -Eq '^[[:space:]]*([PpПп]\.?[[:space:]]*)?3([.)][[:space:]]*.*)?$'; then
      printf 'QUESTION'
      return 0
    fi

    # Explicit dirty-gate commands should resume blocker flow, not stay in QUESTION.
    if printf '%s' "$body" | grep -Eiq '(^|[[:space:]])(COMMIT|STASH|REVERT|IGNORE|IGNOR|ИГНОР|ПРОПУСТИ|ПРОДОЛЖАЙ С DIRTY)($|[[:space:]])'; then
      printf 'REWORK'
      return 0
    fi

    if printf '%s' "$body" | grep -q '?' ||
      printf '%s' "$body" | grep -Eiq '(^|[[:space:]])(что|как|почему|зачем|когда|где|какой|какая|какие|можно ли|все ли|опиши|поясни|уточни|расскажи|объясни)\b'; then
      printf 'QUESTION'
      return 0
    fi

    # If executor is still alive, non-question replies should not keep the task
    # stuck in blocker clarification mode.
    if executor_is_live; then
      printf 'REWORK'
      return 0
    fi

    if has_resume_intent "$body"; then
      printf 'REWORK'
      return 0
    fi

    if printf '%s' "$body" | grep -Eiq '(сделай|добавь|исправ|поправ|измени|доработ|реализ|перепиши|убери|удали|перенеси|нужно|надо|требуется|поменяй|обнови)'; then
      printf 'REWORK'
      return 0
    fi

    printf 'QUESTION'
    return 0
  fi

  if printf '%s' "$body" | grep -Eiq '(сделай|добавь|исправ|поправ|измени|доработ|реализ|перепиши|убери|удали|перенеси|нужно|надо|требуется|поменяй|обнови)'; then
    printf 'REWORK'
    return 0
  fi

  if printf '%s' "$body" | grep -q '?' ||
    printf '%s' "$body" | grep -Eiq '^[[:space:]]*(что|как|почему|зачем|когда|где|какой|какая|какие|можно ли|все ли)\b'; then
    printf 'QUESTION'
    return 0
  fi

  printf 'REWORK'
}

build_answer_comment() {
  local kind_label="$1"
  local task_id="$2"
  local issue_number="$3"
  local reply_id="$4"

  local status_hint="Review"
  local flow_hint="In Review"
  local active_task=""
  local exec_state=""
  local exec_pid=""
  local pr_number=""
  local pr_state="UNKNOWN"
  local pr_url=""
  local question_comment_url=""
  local question_comment_id=""
  local last_note=""

  [[ -s "${CODEX_DIR}/daemon_active_task.txt" ]] && active_task="$(<"${CODEX_DIR}/daemon_active_task.txt")"
  [[ -s "${CODEX_DIR}/executor_state.txt" ]] && exec_state="$(<"${CODEX_DIR}/executor_state.txt")"
  [[ -s "${CODEX_DIR}/executor_pid.txt" ]] && exec_pid="$(<"${CODEX_DIR}/executor_pid.txt")"
  [[ -s "${CODEX_DIR}/daemon_review_pr_number.txt" ]] && pr_number="$(<"${CODEX_DIR}/daemon_review_pr_number.txt")"
  [[ -s "${CODEX_DIR}/daemon_waiting_comment_url.txt" ]] && question_comment_url="$(<"${CODEX_DIR}/daemon_waiting_comment_url.txt")"
  [[ -s "${CODEX_DIR}/daemon_waiting_question_comment_id.txt" ]] && question_comment_id="$(<"${CODEX_DIR}/daemon_waiting_question_comment_id.txt")"
  if [[ -s "${CODEX_DIR}/executor_last_message.txt" ]]; then
    last_note="$(tr '\n' ' ' < "${CODEX_DIR}/executor_last_message.txt" | sed 's/[[:space:]]\+/ /g' | cut -c1-260)"
  fi

  if is_blocker_kind "$kind_label"; then
    status_hint="In Progress"
    flow_hint="In Progress"
  fi

  if [[ "$active_task" == "$task_id" ]]; then
    status_hint="In Progress"
    flow_hint="In Progress"
  fi

  if [[ -n "$pr_number" ]]; then
    if pr_json="$(
      "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
        gh api "repos/${REPO}/pulls/${pr_number}" \
          --jq '{state: (.state // "UNKNOWN"), url: (.html_url // "")}'
    )"; then
      pr_state="$(printf '%s' "$pr_json" | jq -r '.state // "UNKNOWN"')"
      pr_url="$(printf '%s' "$pr_json" | jq -r '.url // ""')"
    fi
  fi

  [[ -z "$exec_state" ]] && exec_state="unknown"
  if [[ -n "$exec_pid" ]]; then
    exec_state="${exec_state} (pid ${exec_pid})"
  fi

  local executor_live="0"
  if executor_is_live; then
    executor_live="1"
  fi

  local pr_line=""
  if [[ -n "$pr_number" && -n "$pr_url" ]]; then
    pr_line="- PR #${pr_number}: ${pr_state} (${pr_url})"
  elif [[ -n "$pr_number" ]]; then
    pr_line="- PR #${pr_number}: ${pr_state}"
  else
    pr_line="- PR: не найден в review-контексте"
  fi

  local blocker_line=""
  if [[ -n "$question_comment_url" ]]; then
    blocker_line="- Исходный блокер: ${question_comment_url}"
  elif [[ -n "$question_comment_id" ]]; then
    blocker_line="- Исходный блокер: comment id ${question_comment_id}"
  else
    blocker_line="- Исходный блокер: см. предыдущий комментарий CODEX_SIGNAL: AGENT_BLOCKER"
  fi

  local last_note_line=""
  if [[ -n "$last_note" ]]; then
    last_note_line="- Последняя ремарка executor: ${last_note}"
  fi

  if is_blocker_kind "$kind_label"; then
    if [[ "$executor_live" == "1" ]]; then
      cat <<EOF
CODEX_SIGNAL: AGENT_ANSWER
CODEX_TASK: ${task_id}
CODEX_SOURCE_REPLY_COMMENT_ID: ${reply_id}
CODEX_MODE: QUESTION

Короткий ответ: executor уже продолжает работу, новый blocker не требуется.

Текущий контекст:
- Задача #${issue_number}: ${status_hint} / ${flow_hint}
${blocker_line}
${last_note_line}
- Executor: ${exec_state}

Дополнительный комментарий не нужен, если не появился новый содержательный вопрос.
EOF
      return 0
    fi

    cat <<EOF
CODEX_SIGNAL: AGENT_ANSWER
CODEX_TASK: ${task_id}
CODEX_SOURCE_REPLY_COMMENT_ID: ${reply_id}
CODEX_MODE: QUESTION

Короткий ответ: вижу запрос на уточнение блокера. Блокер активен, работу не возобновлял.

Текущий контекст:
- Задача #${issue_number}: ${status_hint} / ${flow_hint}
${blocker_line}
${last_note_line}
- Executor: ${exec_state}

Чтобы продолжить работу, напиши отдельный комментарий:
CODEX_MODE: REWORK
<что делать дальше>
EOF
    return 0
  fi

  cat <<EOF
CODEX_SIGNAL: AGENT_ANSWER
CODEX_TASK: ${task_id}
CODEX_SOURCE_REPLY_COMMENT_ID: ${reply_id}
CODEX_MODE: QUESTION

Короткий ответ: задача в работе, review-feedback получен и обработан.

Текущий контекст:
- Задача #${issue_number}: ${status_hint} / ${flow_hint}
${pr_line}
- Executor: ${exec_state}

Если нужна доработка, напиши отдельный комментарий:
CODEX_MODE: REWORK
<что именно изменить>
EOF
}

emit_wait_state() {
  local task_id="$1"
  local issue_number="$2"
  local question_comment_id="$3"
  local kind_label="$4"
  echo "WAIT_USER_REPLY=1"
  echo "TASK_ID=$task_id"
  echo "ISSUE_NUMBER=$issue_number"
  echo "QUESTION_COMMENT_ID=$question_comment_id"
  echo "QUESTION_KIND=$kind_label"
  if is_review_feedback_kind "$kind_label"; then
    echo "WAIT_REVIEW_FEEDBACK=1"
  fi
}

has_waiting_context_artifacts() {
  [[ -s "$issue_file" ]] ||
    [[ -s "$task_file" ]] ||
    [[ -s "$question_id_file" ]] ||
    [[ -s "$kind_file" ]] ||
    [[ -s "$pending_post_file" ]] ||
    [[ -s "$waiting_since_file" ]] ||
    [[ -s "$waiting_comment_url_file" ]]
}

has_review_context_artifacts() {
  [[ -s "$review_task_file" ]] ||
    [[ -s "$review_item_file" ]] ||
    [[ -s "$review_issue_file" ]] ||
    [[ -s "$review_pr_file" ]] ||
    [[ -s "$review_branch_file" ]]
}

clear_waiting_state() {
  : > "$issue_file"
  : > "$task_file"
  : > "$question_id_file"
  : > "$kind_file"
  : > "$waiting_since_file"
  : > "$waiting_comment_url_file"
  : > "$pending_post_file"
}

clear_review_context() {
  : > "$review_task_file"
  : > "$review_item_file"
  : > "$review_issue_file"
  : > "$review_pr_file"
  : > "$review_branch_file"
}

emit_nonempty_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

cleanup_review_task_branch_if_merged() {
  local task_branch="$1"

  [[ -n "$task_branch" ]] || return 0

  if [[ "$task_branch" == "$HEAD_BRANCH" || "$task_branch" == "$BASE_BRANCH" ]]; then
    echo "REVIEW_TASK_BRANCH_DELETE_SKIPPED=PROTECTED_BRANCH"
    echo "REVIEW_TASK_BRANCH_NAME=${task_branch}"
    return 0
  fi
  echo "REVIEW_TASK_BRANCH_CLEANUP_DEFERRED=1"
  echo "REVIEW_TASK_BRANCH_NAME=${task_branch}"
}

clear_waiting_for_terminal_review_pr() {
  local issue_number="$1"
  local kind_label="$2"
  local review_branch_name="$3"
  local review_pr_number="$4"
  local review_pr_state="$5"
  local review_pr_merged_at="$6"
  local review_pr_closed_at="$7"
  local task_id=""

  [[ -s "$review_task_file" ]] && task_id="$(<"$review_task_file")"

  if [[ "$review_pr_state" == "MERGED" || -n "$review_pr_merged_at" ]]; then
    cleanup_review_task_branch_if_merged "$review_branch_name"
    if [[ -n "$task_id" && "$issue_number" =~ ^[0-9]+$ ]]; then
      cleanup_out="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_worktree_cleanup.sh" "$task_id" "$issue_number" "review-pr-merged" 2>&1 || true)"
      emit_nonempty_lines "$cleanup_out"
    fi
    clear_waiting_state
    clear_review_context
    echo "STALE_WAITING_CONTEXT_CLEARED=REVIEW_PR_MERGED"
    echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
    echo "STALE_WAITING_PR_NUMBER=$review_pr_number"
    echo "STALE_WAITING_KIND=$kind_label"
    echo "NO_WAITING_USER_REPLY=1"
    exit 0
  fi

  if [[ "$review_pr_state" == "CLOSED" || -n "$review_pr_closed_at" ]]; then
    if [[ -n "$task_id" && "$issue_number" =~ ^[0-9]+$ ]]; then
      cleanup_out="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_worktree_cleanup.sh" "$task_id" "$issue_number" "review-pr-closed" 2>&1 || true)"
      emit_nonempty_lines "$cleanup_out"
    fi
    clear_waiting_state
    clear_review_context
    echo "STALE_WAITING_CONTEXT_CLEARED=REVIEW_PR_CLOSED"
    echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
    echo "STALE_WAITING_PR_NUMBER=$review_pr_number"
    echo "STALE_WAITING_KIND=$kind_label"
    echo "NO_WAITING_USER_REPLY=1"
    exit 0
  fi
}

probe_terminal_review_pr_from_review_context() {
  local review_pr_number=""
  local review_issue_number=""
  local review_branch_name=""
  local review_pr_json=""
  local review_pr_state=""
  local review_pr_merged_at=""
  local review_pr_closed_at=""
  local rc=0

  [[ -s "$review_pr_file" ]] && review_pr_number="$(<"$review_pr_file")"
  [[ -s "$review_issue_file" ]] && review_issue_number="$(<"$review_issue_file")"
  [[ -s "$review_branch_file" ]] && review_branch_name="$(<"$review_branch_file")"

  if ! [[ "$review_pr_number" =~ ^[0-9]+$ && "$review_issue_number" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if ! review_pr_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/pulls/${review_pr_number}" \
        --jq '{state: (.state // ""), mergedAt: (.merged_at // ""), closedAt: (.closed_at // "")}'
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAITING_FOR_REVIEW_CONTEXT_ONLY=1"
      echo "WAITING_REVIEW_PR_NUMBER=$review_pr_number"
      return 0
    fi
    clear_review_context
    echo "STALE_WAITING_CONTEXT_CLEARED=REVIEW_PR_LOOKUP_FAILED"
    echo "STALE_WAITING_ISSUE_NUMBER=$review_issue_number"
    echo "STALE_WAITING_PR_NUMBER=$review_pr_number"
    echo "NO_WAITING_USER_REPLY=1"
    exit 0
  fi

  review_pr_state="$(printf '%s' "$review_pr_json" | jq -r '.state // ""' | tr '[:lower:]' '[:upper:]')"
  review_pr_merged_at="$(printf '%s' "$review_pr_json" | jq -r '.mergedAt // ""')"
  review_pr_closed_at="$(printf '%s' "$review_pr_json" | jq -r '.closedAt // ""')"

  clear_waiting_for_terminal_review_pr \
    "$review_issue_number" \
    "REVIEW_FEEDBACK" \
    "$review_branch_name" \
    "$review_pr_number" \
    "$review_pr_state" \
    "$review_pr_merged_at" \
    "$review_pr_closed_at"

  echo "WAITING_FOR_REVIEW_CONTEXT_ONLY=1"
  echo "WAITING_REVIEW_PR_NUMBER=$review_pr_number"
  return 0
}

clear_stale_waiting_context() {
  local reason="$1"
  local issue_number="${2:-}"
  local task_id="${3:-}"
  local kind_label="${4:-}"
  local review_task=""
  local review_issue=""

  [[ -s "$review_task_file" ]] && review_task="$(<"$review_task_file")"
  [[ -s "$review_issue_file" ]] && review_issue="$(<"$review_issue_file")"

  clear_waiting_state
  if is_review_feedback_kind "$kind_label" ||
    [[ -n "$task_id" && "$review_task" == "$task_id" ]] ||
    [[ -n "$issue_number" && "$review_issue" == "$issue_number" ]]; then
    clear_review_context
  fi

  echo "STALE_WAITING_CONTEXT_CLEARED=${reason}"
  [[ -n "$issue_number" ]] && echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
  [[ -n "$task_id" ]] && echo "STALE_WAITING_TASK_ID=$task_id"
}

recover_anchor_comment_id() {
  local kind_label="$1"
  local task_id="$2"
  local comments_json="$3"

  if is_review_feedback_kind "$kind_label"; then
    printf '%s' "$comments_json" |
      jq -r --arg task "$task_id" '
        [
          .[]
          | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_IN_REVIEW$")))
          | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REVIEW$")))
          | select(((.body // "") | test("(?m)^CODEX_TASK: " + $task + "$")))
        ][-1].id // empty
      '
  else
    printf '%s' "$comments_json" |
      jq -r --arg task "$task_id" '
        [
          .[]
          | select(((.body // "") | test("(?m)^CODEX_SIGNAL: (AGENT_QUESTION|AGENT_BLOCKER)$")))
          | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REPLY$")))
          | select(((.body // "") | test("(?m)^CODEX_TASK: " + $task + "$")))
        ][-1].id // empty
      '
  fi
}

if [[ ! -s "$issue_file" || ! -s "$question_id_file" ]]; then
  if has_review_context_artifacts; then
    probe_terminal_review_pr_from_review_context
  fi
  if has_waiting_context_artifacts; then
    clear_waiting_state
    echo "STALE_WAITING_CONTEXT_CLEARED=MISSING_WAITING_MARKERS"
  fi
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi

issue_number="$(<"$issue_file")"
task_id=""
question_comment_id="$(<"$question_id_file")"
kind_label=""
pending_post="0"
issue_author=""
[[ -s "$task_file" ]] && task_id="$(<"$task_file")"
[[ -s "$kind_file" ]] && kind_label="$(<"$kind_file")"
[[ -s "$pending_post_file" ]] && pending_post="$(<"$pending_post_file")"

if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
  clear_stale_waiting_context "INVALID_ISSUE_NUMBER" "$issue_number" "$task_id" "$kind_label"
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi

if [[ -z "$task_id" || -z "$kind_label" ]]; then
  clear_stale_waiting_context "MISSING_TASK_OR_KIND" "$issue_number" "$task_id" "$kind_label"
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi

comments_json=""

# Если issue уже закрыта, удалена или вручную выведена из автоматики, waiting/review
# контекст становится невалидным.
issue_state_json=""
if ! issue_state_json="$(
  "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
    gh api "repos/${REPO}/issues/${issue_number}" \
    --jq '{state: (.state // ""), auto_ignore: ((.labels // []) | any(.name == "auto:ignore"))}'
)"; then
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
    echo "WAIT_GITHUB_API_UNSTABLE=1"
    echo "WAITING_FOR_ISSUE_STATE=1"
    exit 0
  fi
  clear_waiting_state
  clear_review_context
  echo "STALE_WAITING_CONTEXT_CLEARED=ISSUE_LOOKUP_FAILED"
  echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi
issue_state="$(printf '%s' "$issue_state_json" | jq -r '.state // ""' | tr '[:lower:]' '[:upper:]')"
issue_auto_ignore="$(printf '%s' "$issue_state_json" | jq -r 'if .auto_ignore then "1" else "0" end')"

review_branch_name=""
[[ -s "$review_branch_file" ]] && review_branch_name="$(<"$review_branch_file")"

if [[ "$issue_state" == "CLOSED" ]]; then
  if is_review_feedback_kind "$kind_label"; then
    cleanup_review_task_branch_if_merged "$review_branch_name"
  fi
  clear_waiting_state
  clear_review_context
  echo "STALE_WAITING_CONTEXT_CLEARED=ISSUE_CLOSED"
  echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi

if [[ "$issue_auto_ignore" == "1" ]]; then
  if is_review_feedback_kind "$kind_label"; then
    cleanup_review_task_branch_if_merged "$review_branch_name"
  fi
  clear_waiting_state
  clear_review_context
  echo "STALE_WAITING_CONTEXT_CLEARED=ISSUE_AUTO_IGNORE"
  echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
  echo "NO_WAITING_USER_REPLY=1"
  exit 0
fi

# Fallback against post-merge auto-close failures:
# once linked review PR is already merged/closed, stale waiting context should
# not block daemon indefinitely, even if the last waiting-kind was BLOCKER.
review_pr_number=""
review_issue_number=""
[[ -s "$review_pr_file" ]] && review_pr_number="$(<"$review_pr_file")"
[[ -s "$review_issue_file" ]] && review_issue_number="$(<"$review_issue_file")"

if is_review_feedback_kind "$kind_label" &&
  [[ -n "$review_issue_number" && "$review_issue_number" != "$issue_number" ]]; then
  emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
  echo "WAITING_FOR_REVIEW_CONTEXT_MATCH=1"
  echo "WAITING_CONTEXT_ISSUE_NUMBER=$issue_number"
  echo "WAITING_REVIEW_ISSUE_NUMBER=$review_issue_number"
  exit 0
fi

if [[ "$review_pr_number" =~ ^[0-9]+$ ]] &&
  [[ -z "$review_issue_number" || "$review_issue_number" == "$issue_number" ]]; then
  review_pr_json=""
  if ! review_pr_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/pulls/${review_pr_number}" \
        --jq '{state: (.state // ""), mergedAt: (.merged_at // ""), closedAt: (.closed_at // "")}'
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAITING_FOR_REVIEW_PR_STATE=1"
      echo "WAITING_REVIEW_PR_NUMBER=$review_pr_number"
      exit 0
    fi
    # Non-retryable PR lookup failure should not deadlock queue.
    clear_waiting_state
    clear_review_context
    echo "STALE_WAITING_CONTEXT_CLEARED=REVIEW_PR_LOOKUP_FAILED"
    echo "STALE_WAITING_ISSUE_NUMBER=$issue_number"
    echo "STALE_WAITING_PR_NUMBER=$review_pr_number"
    echo "NO_WAITING_USER_REPLY=1"
    exit 0
  fi

  review_pr_state="$(printf '%s' "$review_pr_json" | jq -r '.state // ""' | tr '[:lower:]' '[:upper:]')"
  review_pr_merged_at="$(printf '%s' "$review_pr_json" | jq -r '.mergedAt // ""')"
  review_pr_closed_at="$(printf '%s' "$review_pr_json" | jq -r '.closedAt // ""')"

  clear_waiting_for_terminal_review_pr \
    "$issue_number" \
    "$kind_label" \
    "$review_branch_name" \
    "$review_pr_number" \
    "$review_pr_state" \
    "$review_pr_merged_at" \
    "$review_pr_closed_at"
fi

if [[ "$pending_post" == "1" ]]; then
  outbox_count="0"
  if outbox_out="$("${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" count 2>/dev/null)"; then
    outbox_count="$(printf '%s\n' "$outbox_out" | awk -F= '/^OUTBOX_PENDING_COUNT=/{print $2}' | tail -n1)"
    [[ -z "$outbox_count" ]] && outbox_count="0"
  fi

  emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
  echo "WAIT_GITHUB_API_UNSTABLE=1"
  echo "WAITING_FOR_QUESTION_POST=1"
  echo "OUTBOX_PENDING_COUNT=$outbox_count"
  exit 0
fi

# Мягкое восстановление: если id вопроса потерян/пустой, не падаем.
# Пытаемся найти последний AGENT_QUESTION/AGENT_BLOCKER в Issue и взять его id.
if ! [[ "$question_comment_id" =~ ^[0-9]+$ ]]; then
  if ! comments_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments?per_page=100"
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAITING_FOR_VALID_QUESTION_ID=1"
      exit 0
    fi
    exit "$rc"
  fi

  recovered_qid="$(recover_anchor_comment_id "$kind_label" "$task_id" "$comments_json")"

  if [[ -n "$recovered_qid" ]]; then
    question_comment_id="$recovered_qid"
    printf '%s\n' "$question_comment_id" > "$question_id_file"
    echo "RECOVERED_QUESTION_COMMENT_ID=$question_comment_id"
  else
    if [[ "$pending_post" == "1" ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAITING_FOR_VALID_QUESTION_ID=1"
    else
      clear_stale_waiting_context "MISSING_ANCHOR_REQUEST" "$issue_number" "$task_id" "$kind_label"
      echo "NO_WAITING_USER_REPLY=1"
    fi
    exit 0
  fi
fi

if [[ -z "$comments_json" ]]; then
  if ! comments_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments?per_page=100"
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      exit 0
    fi
    exit "$rc"
  fi
fi

if [[ "$question_comment_id" == "0" ]]; then
  if is_review_feedback_kind "$kind_label"; then
    if [[ "$pending_post" != "1" ]]; then
      clear_stale_waiting_context "REVIEW_WAIT_WITHOUT_ANCHOR" "$issue_number" "$task_id" "$kind_label"
      echo "NO_WAITING_USER_REPLY=1"
      exit 0
    fi
  elif [[ "$task_id" != DIRTY-GATE-ISSUE-* && "$pending_post" != "1" ]]; then
    clear_stale_waiting_context "WAIT_WITHOUT_ANCHOR" "$issue_number" "$task_id" "$kind_label"
    echo "NO_WAITING_USER_REPLY=1"
    exit 0
  fi
elif [[ "$question_comment_id" =~ ^[0-9]+$ ]]; then
  anchor_exists="$(
    printf '%s' "$comments_json" | jq -r --argjson qid "$question_comment_id" '
      any(.[]; (.id | tonumber) == $qid)
    '
  )"
  if [[ "$anchor_exists" != "true" ]]; then
    recovered_qid="$(recover_anchor_comment_id "$kind_label" "$task_id" "$comments_json")"
    if [[ -n "$recovered_qid" ]]; then
      question_comment_id="$recovered_qid"
      printf '%s\n' "$question_comment_id" > "$question_id_file"
      echo "RECOVERED_QUESTION_COMMENT_ID=$question_comment_id"
    elif [[ "$pending_post" == "1" ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAITING_FOR_QUESTION_POST=1"
      exit 0
    else
      clear_stale_waiting_context "ANCHOR_COMMENT_MISSING" "$issue_number" "$task_id" "$kind_label"
      echo "NO_WAITING_USER_REPLY=1"
      exit 0
    fi
  fi
fi

if is_review_feedback_kind "$kind_label"; then
  if ! issue_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}"
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      echo "WAITING_FOR_ISSUE_AUTHOR=1"
      exit 0
    fi
    exit "$rc"
  fi

  issue_author="$(printf '%s' "$issue_json" | jq -r '.user.login // empty')"
  if [[ -z "$issue_author" || "$issue_author" == "null" ]]; then
    emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
    echo "WAITING_FOR_ISSUE_AUTHOR=1"
    exit 0
  fi

  reply_json="$(
    printf '%s' "$comments_json" |
      jq -c --argjson qid "$question_comment_id" --arg issue_author "$issue_author" '
        [
          .[]
          | select((.id | tonumber) > $qid)
          | select(((.body // "") | test("(?m)^CODEX_SIGNAL:")) | not)
          | select((((.user.login // "") | ascii_downcase) == ($issue_author | ascii_downcase)))
        ][0] // empty
      '
  )"
else
  reply_json="$(
    printf '%s' "$comments_json" |
      jq -c --argjson qid "$question_comment_id" '
        [
          .[]
          | select((.id | tonumber) > $qid)
          | select(((.body // "") | test("(?m)^CODEX_SIGNAL:")) | not)
        ][0] // empty
      '
  )"
fi

if [[ -z "$reply_json" ]]; then
  emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
  exit 0
fi

reply_id="$(printf '%s' "$reply_json" | jq -r '.id')"
reply_url="$(printf '%s' "$reply_json" | jq -r '.html_url')"
reply_user="$(printf '%s' "$reply_json" | jq -r '.user.login')"
reply_body="$(printf '%s' "$reply_json" | jq -r '.body // ""')"
reply_preview="$(printf '%s' "$reply_body" | tr '\n' ' ' | cut -c1-180)"
now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

reply_mode="$(detect_reply_mode "$kind_label" "$reply_body")"

if [[ "$reply_mode" == "QUESTION" ]]; then
  printf '%s\n' "$reply_id" > "$question_id_file"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
  printf '%s\n' "$reply_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"

  answer_body="$(build_answer_comment "$kind_label" "$task_id" "$issue_number" "$reply_id")"
  if ! answer_out="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" gh api "repos/${REPO}/issues/${issue_number}/comments" -f body="$answer_body" 2>&1)"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      tmp_answer="$(mktemp "${STATE_TMP_DIR}/answer_body.XXXXXX")"
      trap 'rm -f "$tmp_answer"' EXIT
      printf '%s\n' "$answer_body" > "$tmp_answer"
      if queue_out="$("${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" enqueue_issue_comment "$REPO" "$issue_number" "$tmp_answer" "$task_id" "ANSWER" "0" 2>&1)"; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line"
        done <<< "$queue_out"
        echo "ANSWER_QUEUED_OUTBOX=1"
        echo "WAIT_GITHUB_API_UNSTABLE=1"
      else
        qrc=$?
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "ANSWER_OUTBOX_ERROR(rc=$qrc): $line"
        done <<< "$queue_out"
      fi
    else
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "ANSWER_POST_ERROR(rc=$rc): $line"
      done <<< "$answer_out"
    fi
  else
    echo "ANSWER_POSTED=1"
  fi

  if is_review_feedback_kind "$kind_label"; then
    review_wait_payload="$(build_review_feedback_payload "$reply_id" "$reply_url" false "$now_utc" "awaiting review feedback clarification")"
    emit_runtime_v2_event \
      "review.feedback_wait_requested" \
      "legacy-v2-review-wait-${task_id}-${reply_id}" \
      "legacy.review.feedback_wait_requested:${task_id}:${reply_id}" \
      "$review_wait_payload"
  else
    wait_reason="waiting human reply"
    if is_blocker_kind "$kind_label"; then
      wait_reason="waiting human unblock"
    fi
    wait_payload="$(build_wait_payload "$reply_id" "$wait_reason" "$kind_label" "$reply_url" false "$now_utc")"
    emit_runtime_v2_event \
      "human.wait_requested" \
      "legacy-v2-wait-${task_id}-${reply_id}" \
      "legacy.human.wait_requested:${task_id}:${reply_id}" \
      "$wait_payload"
  fi
  reconcile_runtime_v2_primary_context

  emit_wait_state "$task_id" "$issue_number" "$reply_id" "$kind_label"
  if is_review_feedback_kind "$kind_label"; then
    echo "REVIEW_FEEDBACK_RECEIVED=1"
    echo "REVIEW_FEEDBACK_ISSUE_AUTHOR=$issue_author"
  else
    echo "BLOCKER_CLARIFICATION_RECEIVED=1"
  fi
  echo "USER_REPLY_RECEIVED=1"
  echo "TASK_ID=$task_id"
  echo "ISSUE_NUMBER=$issue_number"
  echo "REPLY_KIND=$kind_label"
  echo "REPLY_MODE=$reply_mode"
  echo "REPLY_COMMENT_ID=$reply_id"
  echo "REPLY_AUTHOR=$reply_user"
  echo "REPLY_URL=$reply_url"
  echo "REPLY_PREVIEW=$reply_preview"
  exit 0
fi

printf '%s\n' "$reply_body" > "${CODEX_DIR}/daemon_user_reply.txt"
printf '%s\n' "$reply_id" > "${CODEX_DIR}/daemon_user_reply_comment_id.txt"
printf '%s\n' "$reply_url" > "${CODEX_DIR}/daemon_user_reply_comment_url.txt"
printf '%s\n' "$reply_user" > "${CODEX_DIR}/daemon_user_reply_author.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_user_reply_task_id.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_user_reply_issue_number.txt"
printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_user_reply_at_utc.txt"

reply_payload="$(
  jq -nc \
    --arg responseType "$kind_label" \
    --arg replyCommentId "$reply_id" \
    --arg replyMode "$reply_mode" \
    '{responseType:$responseType, replyCommentId:$replyCommentId, replyMode:$replyMode}'
)"
emit_runtime_v2_event \
  "human.response_received" \
  "legacy-v2-reply-${task_id}-${reply_id}" \
  "legacy.human.response_received:${task_id}:${reply_id}" \
  "$reply_payload"
reconcile_runtime_v2_primary_context

ack_signal="AGENT_RESUMED"
ack_message="Ответ получен, продолжаю работу по задаче."
if is_review_feedback_kind "$kind_label"; then
  ack_signal="AGENT_RESUMED_REVIEW"
  ack_message="Фидбэк в Review получен, возвращаюсь к доработке."
fi

ack_body="$(cat <<EOF_ACK
CODEX_SIGNAL: ${ack_signal}
CODEX_TASK: ${task_id}
CODEX_SOURCE_REPLY_COMMENT_ID: ${reply_id}

${ack_message}
EOF_ACK
)"

if ! ack_out="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" gh api "repos/${REPO}/issues/${issue_number}/comments" -f body="$ack_body" 2>&1)"; then
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    tmp_ack="$(mktemp "${STATE_TMP_DIR}/ack_body.XXXXXX")"
    trap 'rm -f "$tmp_ack"' EXIT
    printf '%s\n' "$ack_body" > "$tmp_ack"
    if queue_out="$("${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" enqueue_issue_comment "$REPO" "$issue_number" "$tmp_ack" "$task_id" "ACK" "0" 2>&1)"; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done <<< "$queue_out"
      echo "ACK_QUEUED_OUTBOX=1"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
    else
      qrc=$?
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "ACK_OUTBOX_ERROR(rc=$qrc): $line"
      done <<< "$queue_out"
    fi
  else
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "ACK_POST_ERROR(rc=$rc): $line"
    done <<< "$ack_out"
  fi
fi

if is_review_feedback_kind "$kind_label"; then
  echo "REVIEW_FEEDBACK_RECEIVED=1"
  echo "REVIEW_FEEDBACK_ISSUE_AUTHOR=$issue_author"
fi

echo "USER_REPLY_RECEIVED=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "REPLY_KIND=$kind_label"
echo "REPLY_MODE=$reply_mode"
echo "REPLY_COMMENT_ID=$reply_id"
echo "REPLY_AUTHOR=$reply_user"
echo "REPLY_URL=$reply_url"
echo "REPLY_PREVIEW=$reply_preview"
