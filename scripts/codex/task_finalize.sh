#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
REPO="${GITHUB_REPO:-justewg/planka}"
FINAL_STATUS="${FINAL_STATUS:-Review}"
FINAL_FLOW="${FINAL_FLOW:-In Review}"

commit_file="${CODEX_DIR}/commit_message.txt"
stage_file="${CODEX_DIR}/stage_paths.txt"
task_file="${CODEX_DIR}/project_task_id.txt"
active_task_file="${CODEX_DIR}/daemon_active_task.txt"
active_item_file="${CODEX_DIR}/daemon_active_item_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
title_file="${CODEX_DIR}/pr_title.txt"
body_file="${CODEX_DIR}/pr_body.txt"
pr_number_file="${CODEX_DIR}/pr_number.txt"
executor_prompt_file="${CODEX_DIR}/executor_prompt.txt"

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
  shift || true
  local -a changed_paths=("$@")
  local changed_paths_md="- (не указано; см. commit diff)"
  local path normalized

  if (( ${#changed_paths[@]} > 0 )); then
    changed_paths_md=""
    for path in "${changed_paths[@]}"; do
      normalized="$(normalize_repo_path "$path")"
      [[ -z "$normalized" ]] && continue
      changed_paths_md+=$'\n'"- \`${normalized}\`"
    done
    [[ -n "$changed_paths_md" ]] || changed_paths_md="- (не указано; см. commit diff)"
  fi

  cat <<EOF
## Что сделано
- Реализованы изменения по задаче ${task_id} в соответствии с требованиями Issue.
- Ниже перечислены фактические изменения, чтобы PR можно было ревьюить без переключения в Issue.

## Состав изменений (файлы)
${changed_paths_md}

## Проверка
1) Проверены сценарии, затронутые изменениями по ${task_id}.
2) Выполнена базовая проверка на отсутствие побочных регрессий в смежных частях.

## Критерии приёмки
- [ ] Изменения соответствуют требованиям ${task_id}.
- [ ] Проверки из раздела «Проверка» воспроизводимы.

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
  local err_file
  err_file="$(mktemp "${CODEX_DIR}/final_comment_gh_err.XXXXXX")"
  if comment_json="$(
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments" \
      -f body="$comment_body" 2>"$err_file"
  )"; then
    if [[ -s "$err_file" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done < "$err_file"
    fi
    rm -f "$err_file"
    local comment_id comment_url
    comment_id="$(printf '%s' "$comment_json" | jq -r '.id // empty')"
    comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url // empty')"
    echo "FINAL_ISSUE_COMMENT_POSTED=1"
    echo "FINAL_ISSUE_NUMBER=$issue_number"
    echo "FINAL_ISSUE_COMMENT_ID=$comment_id"
    echo "FINAL_ISSUE_COMMENT_URL=$comment_url"
    return 0
  else
    local rc=$?
    local comment_err
    comment_err="$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file"
    if [[ -n "$comment_err" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done <<< "$comment_err"
    fi
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
  fi
}

emit_nonempty_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

normalize_repo_path() {
  local path="$1"
  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done
  printf '%s' "$path"
}

is_path_within_narrative() {
  local path
  path="$(normalize_repo_path "$1")"
  [[ "$path" == "narrative" || "$path" == "narrative/" || "$path" == narrative/* ]]
}

collect_tracked_diff_paths() {
  {
    git -C "${ROOT_DIR}" diff --name-only --ignore-submodules -- || true
    git -C "${ROOT_DIR}" diff --cached --name-only --ignore-submodules -- || true
  } | awk 'NF' | sort -u
}

extract_issue_number_from_task_id() {
  local task_id="$1"
  if [[ "$task_id" =~ ^ISSUE-([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

extract_pres_narr_index_from_text() {
  local text="$1"
  local marker index_raw

  marker="$(printf '%s\n' "$text" | grep -Eo 'PRES[-_]NARR[-_][0-9]{2}' | head -n1 || true)"
  [[ -n "$marker" ]] || return 1

  index_raw="$(printf '%s' "$marker" | sed -E 's/.*[-_]([0-9]{2})$/\1/')"
  [[ "$index_raw" =~ ^[0-9]{2}$ ]] || return 1
  printf '%d' "$((10#$index_raw))"
  return 0
}

resolve_pres_narr_index() {
  local task_id="$1"
  local commit_message="$2"
  local pr_title="$3"
  local issue_title="$4"
  local prompt_content="$5"
  local index=""

  index="$(extract_pres_narr_index_from_text "$task_id" || true)"
  [[ -n "$index" ]] && {
    printf '%s' "$index"
    return 0
  }

  index="$(extract_pres_narr_index_from_text "$pr_title" || true)"
  [[ -n "$index" ]] && {
    printf '%s' "$index"
    return 0
  }

  index="$(extract_pres_narr_index_from_text "$commit_message" || true)"
  [[ -n "$index" ]] && {
    printf '%s' "$index"
    return 0
  }

  index="$(extract_pres_narr_index_from_text "$issue_title" || true)"
  [[ -n "$index" ]] && {
    printf '%s' "$index"
    return 0
  }

  index="$(extract_pres_narr_index_from_text "$prompt_content" || true)"
  [[ -n "$index" ]] && {
    printf '%s' "$index"
    return 0
  }

  return 1
}

enforce_narrative_scope_lock_if_needed() {
  local task_id="$1"
  local commit_message="$2"
  local pr_title="$3"
  local active_issue_number="$4"
  shift 4
  local -a staged_paths=("$@")
  local issue_number issue_title prompt_content pres_narr_index
  local stage_outside diff_outside normalized

  issue_number="$active_issue_number"
  if [[ -z "$issue_number" ]]; then
    issue_number="$(extract_issue_number_from_task_id "$task_id" || true)"
  fi

  issue_title=""
  if [[ -n "$issue_number" ]]; then
    issue_title="$(gh issue view "$issue_number" --repo "$REPO" --json title --jq '.title' 2>/dev/null || true)"
  fi

  prompt_content="$(read_if_present "$executor_prompt_file" || true)"
  pres_narr_index="$(resolve_pres_narr_index "$task_id" "$commit_message" "$pr_title" "$issue_title" "$prompt_content" || true)"

  if [[ -z "$pres_narr_index" ]]; then
    echo "NARRATIVE_SCOPE_LOCK_ENFORCED=0"
    echo "NARRATIVE_SCOPE_LOCK_REASON=NOT_A_PRES_NARR_TASK"
    return 0
  fi

  echo "NARRATIVE_SCOPE_LOCK_TASK_INDEX=$pres_narr_index"
  if (( pres_narr_index == 0 )); then
    echo "NARRATIVE_SCOPE_LOCK_ENFORCED=0"
    echo "NARRATIVE_SCOPE_LOCK_REASON=PRES_NARR_00_SETUP_TASK"
    return 0
  fi

  stage_outside="$(
    for path in "${staged_paths[@]}"; do
      normalized="$(normalize_repo_path "$path")"
      [[ -z "$normalized" ]] && continue
      if ! is_path_within_narrative "$normalized"; then
        printf '%s\n' "$normalized"
      fi
    done | awk 'NF' | sort -u
  )"

  diff_outside="$(
    while IFS= read -r path; do
      normalized="$(normalize_repo_path "$path")"
      [[ -z "$normalized" ]] && continue
      if ! is_path_within_narrative "$normalized"; then
        printf '%s\n' "$normalized"
      fi
    done < <(collect_tracked_diff_paths)
  )"
  diff_outside="$(printf '%s\n' "$diff_outside" | awk 'NF' | sort -u)"

  if [[ -n "$stage_outside" || -n "$diff_outside" ]]; then
    echo "NARRATIVE_SCOPE_LOCK_ENFORCED=1"
    echo "NARRATIVE_SCOPE_LOCK_FAILED=1"
    if [[ -n "$stage_outside" ]]; then
      while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        echo "NARRATIVE_SCOPE_LOCK_STAGE_PATH_OUTSIDE=$path"
      done <<< "$stage_outside"
    fi
    if [[ -n "$diff_outside" ]]; then
      while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        echo "NARRATIVE_SCOPE_LOCK_DIFF_PATH_OUTSIDE=$path"
      done <<< "$diff_outside"
    fi
    echo "NARRATIVE_SCOPE_LOCK_HINT=Разрешены только изменения внутри narrative/."
    exit 1
  fi

  echo "NARRATIVE_SCOPE_LOCK_ENFORCED=1"
  echo "NARRATIVE_SCOPE_LOCK_FAILED=0"
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
active_item_id="$(read_if_present "$active_item_file" || true)"
active_issue_number="$(read_if_present "$active_issue_file" || true)"
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

enforce_narrative_scope_lock_if_needed \
  "$task_id" \
  "$commit_message" \
  "$pr_title" \
  "$active_issue_number" \
  "${stage_paths[@]}"

pr_body="$(read_if_present "$body_file" || true)"
if [[ -z "$pr_body" ]]; then
  pr_body="$(build_default_pr_body "$task_id" "${stage_paths[@]}")"
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

in_review_comment_out="$(
  post_in_review_issue_comment "$task_id" "$pr_number" "$pr_url"
)"
emit_nonempty_lines "$in_review_comment_out"

review_issue_number="$(printf '%s\n' "$in_review_comment_out" | sed -n 's/^FINAL_ISSUE_NUMBER=//p' | tail -n1)"
review_comment_id="$(printf '%s\n' "$in_review_comment_out" | sed -n 's/^FINAL_ISSUE_COMMENT_ID=//p' | tail -n1)"
review_comment_url="$(printf '%s\n' "$in_review_comment_out" | sed -n 's/^FINAL_ISSUE_COMMENT_URL=//p' | tail -n1)"
review_pending_post="0"
if printf '%s\n' "$in_review_comment_out" | grep -q '^FINAL_ISSUE_COMMENT_QUEUED_OUTBOX=1$'; then
  review_pending_post="1"
fi

# Safety net: если review-контекст уже включаем, но якорный комментарий не получен
# и outbox не активирован, ставим recovery-комментарий в outbox.
if [[ -n "$review_issue_number" && -z "$review_comment_id" && "$review_pending_post" != "1" ]]; then
  echo "REVIEW_FEEDBACK_ANCHOR_RECOVER=1"
  recover_body_file="$(mktemp "${CODEX_DIR}/review_anchor_recover.XXXXXX")"
  cat > "$recover_body_file" <<EOF
CODEX_SIGNAL: AGENT_IN_REVIEW
CODEX_TASK: ${task_id}
CODEX_PR_NUMBER: ${pr_number}
CODEX_EXPECT: USER_REVIEW

Работу по задаче завершил, PR готов к проверке.
Жду твою проверку и решение по PR: ${pr_url}
EOF
  recover_queue_out=""
  if recover_queue_out="$(
    "${ROOT_DIR}/scripts/codex/github_outbox.sh" \
      enqueue_issue_comment \
      "$REPO" \
      "$review_issue_number" \
      "$recover_body_file" \
      "$task_id" \
      "REVIEW_FEEDBACK" \
      "1" 2>&1
  )"; then
    emit_nonempty_lines "$recover_queue_out"
    review_pending_post="1"
    echo "REVIEW_FEEDBACK_ANCHOR_RECOVER_QUEUED=1"
  else
    recover_qrc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "REVIEW_FEEDBACK_ANCHOR_RECOVER_ERROR(rc=$recover_qrc): $line"
    done <<< "$recover_queue_out"
  fi
  rm -f "$recover_body_file"
fi

printf '%s\n' "$pr_number" > "$pr_number_file"
status_target="$task_id"
if [[ -n "$active_item_id" ]]; then
  status_target="$active_item_id"
fi

if final_status_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "$status_target" "$FINAL_STATUS" "$FINAL_FLOW" 2>&1)"; then
  emit_nonempty_lines "$final_status_out"
else
  final_status_rc=$?
  emit_nonempty_lines "$final_status_out"
  if [[ "$final_status_rc" -eq 75 ]] || printf '%s' "$final_status_out" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect|api rate limit already exceeded|graphql_rate_limit|rate limit'; then
    echo "FINAL_STATUS_DEFERRED=1"
    runtime_out="$("${ROOT_DIR}/scripts/codex/project_status_runtime.sh" enqueue "$status_target" "$FINAL_STATUS" "$FINAL_FLOW" "task-finalize:${task_id}" 2>&1 || true)"
    emit_nonempty_lines "$runtime_out"
  else
    exit "$final_status_rc"
  fi
fi

# После перевода в Review включаем канал review-feedback через комментарии Issue.
if [[ -n "$review_issue_number" ]]; then
  printf '%s\n' "$task_id" > "$review_task_file"
  printf '%s\n' "$review_issue_number" > "$review_issue_file"
  printf '%s\n' "$pr_number" > "$review_pr_file"
  if [[ -n "$active_item_id" ]]; then
    printf '%s\n' "$active_item_id" > "$review_item_file"
  else
    : > "$review_item_file"
  fi

  printf '%s\n' "$review_issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
  printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
  printf '%s\n' "REVIEW_FEEDBACK" > "${CODEX_DIR}/daemon_waiting_kind.txt"
  if [[ -n "$review_comment_id" ]]; then
    printf '%s\n' "$review_comment_id" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  else
    printf '0\n' > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  fi
  if [[ -n "$review_comment_url" ]]; then
    printf '%s\n' "$review_comment_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  else
    : > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  fi
  printf '%s\n' "$review_pending_post" > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
  if [[ -n "$review_comment_id" ]]; then
    echo "REVIEW_FEEDBACK_WAIT_ENABLED=1"
    echo "REVIEW_FEEDBACK_ANCHOR_COMMENT_ID=$review_comment_id"
  else
    echo "REVIEW_FEEDBACK_WAIT_ENABLED=1"
    echo "REVIEW_FEEDBACK_ANCHOR_COMMENT_ID=missing"
  fi
  if [[ "$review_pending_post" == "1" ]]; then
    echo "REVIEW_FEEDBACK_ANCHOR_PENDING_OUTBOX=1"
  fi
else
  : > "$review_task_file"
  : > "$review_item_file"
  : > "$review_issue_file"
  : > "$review_pr_file"
  : > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
  : > "${CODEX_DIR}/daemon_waiting_task_id.txt"
  : > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
  : > "${CODEX_DIR}/daemon_waiting_kind.txt"
  : > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
  : > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
  : > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
fi

: > "$commit_file"
: > "$stage_file"
: > "$title_file"
: > "$body_file"
: > "$active_task_file"
: > "$active_item_file"
: > "$active_issue_file"
"${ROOT_DIR}/scripts/codex/executor_reset.sh" >/dev/null

echo "FINALIZED_TASK_ID=$task_id"
echo "FINALIZED_STATUS=$FINAL_STATUS"
echo "FINALIZED_FLOW=$FINAL_FLOW"
