#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
REPO="${GITHUB_REPO:-justewg/planka}"

commit_file="${CODEX_DIR}/commit_message.txt"
stage_file="${CODEX_DIR}/stage_paths.txt"
task_file="${CODEX_DIR}/project_task_id.txt"
active_task_file="${CODEX_DIR}/daemon_active_task.txt"
active_item_file="${CODEX_DIR}/daemon_active_item_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
title_file="${CODEX_DIR}/pr_title.txt"
body_file="${CODEX_DIR}/pr_body.txt"
pr_number_file="${CODEX_DIR}/pr_number.txt"

read_if_present() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    local value
    value="$(<"$file_path")"
    printf '%s' "$value"
    return 0
  fi
  return 1
}

require_nonempty_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing file: $file_path"
    exit 1
  fi
  local value
  value="$(<"$file_path")"
  if [[ -z "$value" ]]; then
    echo "Empty file: $file_path"
    exit 1
  fi
  printf '%s' "$value"
}

build_default_pr_title() {
  local task_id="$1"
  local commit_message="$2"
  local cleaned
  cleaned="$(printf '%s' "$commit_message" | sed -E 's/^PL-[0-9]{3}:[[:space:]]*/ /')"
  cleaned="$(printf '%s' "$cleaned" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ -z "$cleaned" ]]; then
    cleaned="Рабочая дельта по задаче ${task_id}"
  fi
  printf '%s %s' "$task_id" "$cleaned"
}

build_default_pr_body() {
  local task_id="$1"
  cat <<EOF
## Краткое описание
- Реализация по задаче ${task_id}.

## Состав изменений
- Основные изменения по ${task_id} внесены в кодовую базу.

## Критерии приёмки
- [ ] Функциональность по ${task_id} соответствует ожидаемому поведению.
- [ ] Регрессий в затронутых сценариях не обнаружено.

## Шаги QA
1) Проверить сценарии, описанные в ${task_id}.
2) Убедиться, что изменения работают в целевом окружении.

## Примечания
- Task ID: ${task_id}
EOF
}

ensure_final_review_signal() {
  local body="$1"
  if printf '%s\n' "$body" | grep -q 'CODEX_SIGNAL: FINAL_REVIEW'; then
    printf '%s' "$body"
    return
  fi
  printf '%s\n\n%s\n%s\n' "$body" "CODEX_SIGNAL: FINAL_REVIEW" "CODEX_STAGE: IN_REVIEW"
}

extract_task_id_from_message() {
  local commit_message="$1"
  local task_id
  task_id="$(printf '%s' "$commit_message" | grep -Eo 'PL-[0-9]{3}' | head -n1 || true)"
  printf '%s' "$task_id"
}

extract_pr_number_from_url() {
  local url="$1"
  printf '%s' "$url" | sed -E 's#.*/pull/([0-9]+).*#\1#'
}

mark_pr_ready_if_draft() {
  local pr_number="$1"
  local is_draft
  is_draft="$(
    gh pr view "$pr_number" \
      --repo "$REPO" \
      --json isDraft \
      --jq '.isDraft'
  )"

  if [[ "$is_draft" == "true" ]]; then
    gh pr ready "$pr_number" --repo "$REPO" >/dev/null
    echo "PR_READY_FOR_REVIEW=true"
  else
    echo "PR_READY_FOR_REVIEW=false"
  fi
}

find_issue_number_for_task() {
  local task_id="$1"
  local issue_number=""

  if [[ -s "$active_issue_file" ]]; then
    issue_number="$(<"$active_issue_file")"
  fi
  if [[ -n "$issue_number" ]]; then
    printf '%s' "$issue_number"
    return 0
  fi

  local candidates_json=""
  if ! candidates_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
      gh issue list \
      --repo "$REPO" \
      --state open \
      --limit 100 \
      --json number,title 2>/dev/null
  )"; then
    return 1
  fi

  issue_number="$(
    printf '%s' "$candidates_json" |
      jq -r --arg task "$task_id" '
        [ .[] | select((.title // "") | test($task)) ][0].number // empty
      '
  )"
  printf '%s' "$issue_number"
  return 0
}

post_in_review_issue_comment() {
  local task_id="$1"
  local pr_number="$2"
  local pr_url="$3"
  local issue_number=""

  if ! issue_number="$(find_issue_number_for_task "$task_id")"; then
    echo "FINAL_ISSUE_COMMENT_SKIPPED=GITHUB_LOOKUP_UNAVAILABLE"
    return 0
  fi
  if [[ -z "$issue_number" ]]; then
    echo "FINAL_ISSUE_COMMENT_SKIPPED=ISSUE_NOT_FOUND"
    return 0
  fi

  local comment_body
  comment_body="$(cat <<EOF
CODEX_SIGNAL: AGENT_IN_REVIEW
CODEX_TASK: ${task_id}
CODEX_PR_NUMBER: ${pr_number}
CODEX_EXPECT: USER_REVIEW

Работу по задаче завершил, PR готов к проверке.
Жду твою проверку и решение по PR: ${pr_url}
EOF
)"

  local comment_json=""
  if comment_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments" \
      -f body="$comment_body" 2>&1
  )"; then
    local comment_id comment_url
    comment_id="$(printf '%s' "$comment_json" | jq -r '.id // empty')"
    comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url // empty')"
    echo "FINAL_ISSUE_COMMENT_POSTED=1"
    echo "FINAL_ISSUE_NUMBER=$issue_number"
    echo "FINAL_ISSUE_COMMENT_ID=$comment_id"
    echo "FINAL_ISSUE_COMMENT_URL=$comment_url"
    return 0
  fi

  local rc=$?
  if [[ "$rc" -eq 75 ]]; then
    local tmp_body queue_out
    tmp_body="$(mktemp "${CODEX_DIR}/in_review_comment.XXXXXX")"
    printf '%s\n' "$comment_body" > "$tmp_body"

    if queue_out="$(
      "${ROOT_DIR}/scripts/codex/github_outbox.sh" \
        enqueue_issue_comment \
        "$REPO" \
        "$issue_number" \
        "$tmp_body" \
        "$task_id" \
        "IN_REVIEW" \
        "0" 2>&1
    )"; then
      rm -f "$tmp_body"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done <<< "$queue_out"
      echo "FINAL_ISSUE_COMMENT_QUEUED_OUTBOX=1"
      echo "FINAL_ISSUE_NUMBER=$issue_number"
      echo "WAIT_GITHUB_API_UNSTABLE=1"
      return 0
    fi

    local qrc=$?
    rm -f "$tmp_body"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "FINAL_ISSUE_COMMENT_OUTBOX_ERROR(rc=$qrc): $line"
    done <<< "$queue_out"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "FINAL_ISSUE_COMMENT_ERROR(rc=$rc): $line"
  done <<< "$comment_json"
  return 0
}

mkdir -p "$CODEX_DIR"

commit_message="$(require_nonempty_file "$commit_file")"

stage_paths=()
if [[ ! -f "$stage_file" ]]; then
  echo "Missing file: $stage_file"
  exit 1
fi
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  stage_paths+=("$line")
done < "$stage_file"
if [[ ${#stage_paths[@]} -eq 0 ]]; then
  echo "Missing or empty file: $stage_file"
  exit 1
fi

task_id="$(read_if_present "$task_file" || true)"
if [[ -z "$task_id" ]]; then
  task_id="$(read_if_present "$active_task_file" || true)"
fi
if [[ -z "$task_id" ]]; then
  task_id="$(extract_task_id_from_message "$commit_message")"
fi
if [[ -z "$task_id" ]]; then
  echo "Cannot detect task id. Set ${task_file} or include PL-xxx in commit message."
  exit 1
fi

pr_title="$(read_if_present "$title_file" || true)"
if [[ -z "$pr_title" ]]; then
  pr_title="$(build_default_pr_title "$task_id" "$commit_message")"
fi

pr_body="$(read_if_present "$body_file" || true)"
if [[ -z "$pr_body" ]]; then
  pr_body="$(build_default_pr_body "$task_id")"
fi
pr_body="$(ensure_final_review_signal "$pr_body")"

tmp_title="$(mktemp)"
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_title" "$tmp_body"' EXIT
printf '%s\n' "$pr_title" > "$tmp_title"
printf '%s\n' "$pr_body" > "$tmp_body"

"${ROOT_DIR}/scripts/codex/dev_commit_push.sh" "$commit_message" "${stage_paths[@]}"

open_prs_json="$(
  gh pr list \
    --repo "$REPO" \
    --state open \
    --base main \
    --head development \
    --json number,title,url \
    --jq '.'
)"
open_pr_count="$(printf '%s' "$open_prs_json" | jq 'length')"

if (( open_pr_count == 0 )); then
  create_out="$("${ROOT_DIR}/scripts/codex/pr_create.sh" "$tmp_title" "$tmp_body")"
  pr_url="$(printf '%s' "$create_out" | tail -n1)"
  pr_number="$(extract_pr_number_from_url "$pr_url")"
  if [[ -z "$pr_number" || "$pr_number" == "$pr_url" ]]; then
    echo "Failed to parse PR number from create output: $create_out"
    exit 1
  fi
  echo "PR_ACTION=CREATED"
  echo "PR_NUMBER=$pr_number"
  echo "PR_URL=$pr_url"
elif (( open_pr_count == 1 )); then
  pr_number="$(printf '%s' "$open_prs_json" | jq -r '.[0].number')"
  pr_url="$(printf '%s' "$open_prs_json" | jq -r '.[0].url')"
  "${ROOT_DIR}/scripts/codex/pr_edit.sh" "$pr_number" "$tmp_title" "$tmp_body" >/dev/null
  echo "PR_ACTION=UPDATED"
  echo "PR_NUMBER=$pr_number"
  echo "PR_URL=$pr_url"
else
  echo "More than one open PR development->main. Manual resolve required."
  printf '%s\n' "$open_prs_json"
  exit 1
fi

mark_pr_ready_if_draft "$pr_number"

post_in_review_issue_comment "$task_id" "$pr_number" "$pr_url"

printf '%s\n' "$pr_number" > "$pr_number_file"
"${ROOT_DIR}/scripts/codex/project_set_status.sh" "$task_id" "In Progress" "In Review"

: > "$commit_file"
: > "$stage_file"
: > "$title_file"
: > "$body_file"
: > "$active_task_file"
: > "$active_item_file"
: > "$active_issue_file"
: > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
: > "${CODEX_DIR}/daemon_waiting_task_id.txt"
: > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
: > "${CODEX_DIR}/daemon_waiting_kind.txt"
: > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
: > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
: > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
"${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null

echo "FINALIZED_TASK_ID=$task_id"
echo "FINALIZED_STATUS=In Progress"
echo "FINALIZED_FLOW=In Review"
