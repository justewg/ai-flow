#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

project_id="${PROJECT_ID:-PVT_kwHOAPt_Q84BPyyr}"
project_number="${PROJECT_NUMBER:-2}"
project_owner="${PROJECT_OWNER:-@me}"
project_items_limit="${PROJECT_ITEMS_LIMIT:-200}"
repo="${GITHUB_REPO:-justewg/planka}"
trigger_status="${TRIGGER_STATUS:-Todo}"
target_status="${TARGET_STATUS:-In Progress}"
target_flow="${TARGET_FLOW:-In Progress}"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"

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

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  echo "WAIT_DIRTY_WORKTREE_TRACKED=1"
  exit 0
fi

mkdir -p "$CODEX_DIR"

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
  run_gh_retry_capture \
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
  :
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
    run_gh_retry_capture \
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
      | [.[] | select(.content_type == "Issue")]
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

    dep_issue_number=""
    if [[ "$dep_token" =~ ^#([0-9]+)$ ]]; then
      dep_issue_number="${BASH_REMATCH[1]}"
    elif [[ "$dep_token" =~ ^ISSUE-([0-9]+)$ ]]; then
      dep_issue_number="${BASH_REMATCH[1]}"
    elif [[ "$dep_token" =~ ^([0-9]+)$ ]]; then
      dep_issue_number="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$dep_issue_number" ]]; then
      blocked_dependencies+=("$dep_token")
      continue
    fi

    dep_state=""
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
      if [[ "$rc" -eq 75 ]]; then
        echo "WAIT_GITHUB_API_UNSTABLE=1"
        echo "WAIT_GITHUB_STAGE=DEPENDENCY_CHECK"
        exit 0
      fi
      exit "$rc"
    fi

    if [[ "$dep_state" != "CLOSED" ]]; then
      blocked_dependencies+=("#${dep_issue_number}")
    fi
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
