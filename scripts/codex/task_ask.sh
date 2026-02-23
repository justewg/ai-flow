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
  candidates_json="$(
    gh issue list \
      --repo "$REPO" \
      --state open \
      --limit 100 \
      --json number,title
  )"
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

comment_body="$(cat <<EOF
CODEX_SIGNAL: ${signal}
CODEX_TASK: ${task_id}
CODEX_KIND: ${kind_label}
CODEX_EXPECT: USER_REPLY

Нужен твой ответ для продолжения работы по задаче.

${message_text}

Ответь комментарием в этот Issue обычным текстом.
EOF
)"

comment_json="$(
  gh api "repos/${REPO}/issues/${issue_number}/comments" \
    -f body="$comment_body"
)"

question_comment_id="$(printf '%s' "$comment_json" | jq -r '.id')"
question_comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url')"

printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
printf '%s\n' "$question_comment_id" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
printf '%s\n' "$kind_label" > "${CODEX_DIR}/daemon_waiting_kind.txt"
printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
printf '%s\n' "$question_comment_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"

echo "QUESTION_POSTED=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "QUESTION_KIND=$kind_label"
echo "QUESTION_COMMENT_ID=$question_comment_id"
echo "QUESTION_COMMENT_URL=$question_comment_url"
echo "WAITING_FOR_USER_REPLY=1"
