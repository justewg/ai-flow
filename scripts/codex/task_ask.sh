#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <question|blocker> <message-file>"
  exit 1
fi

kind_raw="$1"
message_file="$2"

if [[ ! -f "$message_file" ]]; then
  echo "Message file not found: $message_file"
  exit 1
fi

message_text="$(<"$message_file")"
if [[ -z "$message_text" ]]; then
  echo "Message file is empty: $message_file"
  exit 1
fi

kind="$(printf '%s' "$kind_raw" | tr '[:upper:]' '[:lower:]')"
signal="AGENT_QUESTION"
kind_label="QUESTION"
if [[ "$kind" == "blocker" ]]; then
  signal="AGENT_BLOCKER"
  kind_label="BLOCKER"
elif [[ "$kind" != "question" ]]; then
  echo "Unknown kind: $kind_raw (expected question|blocker)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
REPO="${GITHUB_REPO:-justewg/planka}"

mkdir -p "$CODEX_DIR"

active_task_file="${CODEX_DIR}/daemon_active_task.txt"
project_task_file="${CODEX_DIR}/project_task_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"

post_issue_comment() {
  local issue_number="$1"
  local body="$2"
  local out=""
  if out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" gh api "repos/${REPO}/issues/${issue_number}/comments" -f body="$body" 2>&1)"; then
    printf '%s' "$out"
    return 0
  fi
  local rc=$?
  printf '%s\n' "$out" >&2
  return "$rc"
}

task_id=""
if [[ -s "$active_task_file" ]]; then
  task_id="$(<"$active_task_file")"
elif [[ -s "$project_task_file" ]]; then
  task_id="$(<"$project_task_file")"
fi

if [[ -z "$task_id" ]]; then
  echo "Cannot detect active task id (daemon_active_task/project_task_id is empty)"
  exit 1
fi

issue_number=""
if [[ -s "$active_issue_file" ]]; then
  issue_number="$(<"$active_issue_file")"
fi

if [[ -z "$issue_number" ]]; then
  if ! candidates_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
      gh issue list \
      --repo "$REPO" \
      --state open \
      --limit 100 \
      --json number,title
  )"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      exit 75
    fi
    exit "$rc"
  fi

  issue_number="$(
    printf '%s' "$candidates_json" |
      jq -r --arg task "$task_id" '
        [ .[] | select((.title // "") | test($task)) ][0].number // empty
      '
  )"
fi

if [[ -z "$issue_number" ]]; then
  echo "Cannot detect issue number for task: $task_id"
  exit 1
fi

now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

comment_body="$(cat <<EOF_COMMENT
CODEX_SIGNAL: ${signal}
CODEX_TASK: ${task_id}
CODEX_KIND: ${kind_label}
CODEX_EXPECT: USER_REPLY

Нужен твой ответ для продолжения работы по задаче.

${message_text}

Ответь комментарием в этот Issue обычным текстом.
EOF_COMMENT
)"

if comment_json="$(post_issue_comment "$issue_number" "$comment_body")"; then
  question_comment_id="$(printf '%s' "$comment_json" | jq -r '.id')"
  question_comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url')"

  printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
  printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
  printf '%s\n' "$question_comment_id" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  printf '%s\n' "$kind_label" > "${CODEX_DIR}/daemon_waiting_kind.txt"
  printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
  printf '%s\n' "$question_comment_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  : > "$pending_post_file"

  echo "QUESTION_POSTED=1"
  echo "TASK_ID=$task_id"
  echo "ISSUE_NUMBER=$issue_number"
  echo "QUESTION_KIND=$kind_label"
  echo "QUESTION_COMMENT_ID=$question_comment_id"
  echo "QUESTION_COMMENT_URL=$question_comment_url"
  echo "WAITING_FOR_USER_REPLY=1"
  exit 0
fi

rc=$?
if [[ "$rc" -ne 75 ]]; then
  exit "$rc"
fi

tmp_body="$(mktemp "${CODEX_DIR}/question_body.XXXXXX")"
trap 'rm -f "$tmp_body"' EXIT
printf '%s\n' "$comment_body" > "$tmp_body"

if ! enqueue_out="$(
  "${ROOT_DIR}/scripts/codex/github_outbox.sh" \
    enqueue_issue_comment \
    "$REPO" \
    "$issue_number" \
    "$tmp_body" \
    "$task_id" \
    "$kind_label" \
    "1" 2>&1
)"; then
  qrc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "QUESTION_OUTBOX_ERROR(rc=$qrc): $line"
  done <<< "$enqueue_out"
  exit "$qrc"
fi
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<< "$enqueue_out"

printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
printf '%s\n' "-1" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
printf '%s\n' "$kind_label" > "${CODEX_DIR}/daemon_waiting_kind.txt"
printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
: > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
printf '%s\n' "1" > "$pending_post_file"

echo "QUESTION_QUEUED_OUTBOX=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "QUESTION_KIND=$kind_label"
echo "WAIT_GITHUB_API_UNSTABLE=1"
echo "WAITING_FOR_USER_REPLY_PENDING_POST=1"
