#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
REPO="${GITHUB_REPO:-justewg/planka}"

issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
question_id_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"

is_review_feedback_kind() {
  local value="$1"
  [[ "$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')" == "REVIEW_FEEDBACK" ]]
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

clear_waiting_state() {
  : > "$issue_file"
  : > "$task_file"
  : > "$question_id_file"
  : > "$kind_file"
  : > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
  : > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  : > "$pending_post_file"
}

if [[ ! -s "$issue_file" || ! -s "$question_id_file" ]]; then
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

comments_json=""

if [[ "$pending_post" == "1" ]]; then
  outbox_count="0"
  if outbox_out="$("${ROOT_DIR}/scripts/codex/github_outbox.sh" count 2>/dev/null)"; then
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
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
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

  if is_review_feedback_kind "$kind_label"; then
    recovered_qid="$(
      printf '%s' "$comments_json" |
        jq -r '
          [ .[]
            | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_IN_REVIEW$")))
            | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REVIEW$")))
          ][-1].id // empty
        '
    )"
  else
    recovered_qid="$(
      printf '%s' "$comments_json" |
        jq -r '
          [ .[]
            | select(((.body // "") | test("(?m)^CODEX_SIGNAL: (AGENT_QUESTION|AGENT_BLOCKER)$")))
            | select(((.body // "") | test("(?m)^CODEX_EXPECT: USER_REPLY$")))
          ][-1].id // empty
        '
    )"
  fi

  if [[ -n "$recovered_qid" ]]; then
    question_comment_id="$recovered_qid"
    printf '%s\n' "$question_comment_id" > "$question_id_file"
    echo "RECOVERED_QUESTION_COMMENT_ID=$question_comment_id"
  else
    emit_wait_state "$task_id" "$issue_number" "$question_comment_id" "$kind_label"
    echo "WAITING_FOR_VALID_QUESTION_ID=1"
    exit 0
  fi
fi

if [[ -z "$comments_json" ]]; then
  if ! comments_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
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

if is_review_feedback_kind "$kind_label"; then
  if ! issue_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
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

printf '%s\n' "$reply_body" > "${CODEX_DIR}/daemon_user_reply.txt"
printf '%s\n' "$reply_id" > "${CODEX_DIR}/daemon_user_reply_comment_id.txt"
printf '%s\n' "$reply_url" > "${CODEX_DIR}/daemon_user_reply_comment_url.txt"
printf '%s\n' "$reply_user" > "${CODEX_DIR}/daemon_user_reply_author.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_user_reply_task_id.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_user_reply_issue_number.txt"
printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_user_reply_at_utc.txt"

clear_waiting_state

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

if ! ack_out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" gh api "repos/${REPO}/issues/${issue_number}/comments" -f body="$ack_body" 2>&1)"; then
  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    tmp_ack="$(mktemp "${CODEX_DIR}/ack_body.XXXXXX")"
    trap 'rm -f "$tmp_ack"' EXIT
    printf '%s\n' "$ack_body" > "$tmp_ack"
    if queue_out="$("${ROOT_DIR}/scripts/codex/github_outbox.sh" enqueue_issue_comment "$REPO" "$issue_number" "$tmp_ack" "$task_id" "ACK" "0" 2>&1)"; then
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
echo "REPLY_COMMENT_ID=$reply_id"
echo "REPLY_AUTHOR=$reply_user"
echo "REPLY_URL=$reply_url"
echo "REPLY_PREVIEW=$reply_preview"
