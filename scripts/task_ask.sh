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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
REPO="${GITHUB_REPO:-justewg/planka}"

mkdir -p "$CODEX_DIR"

active_task_file="${CODEX_DIR}/daemon_active_task.txt"
project_task_file="${CODEX_DIR}/project_task_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"

extract_structured_field() {
  local key="$1"
  local text="$2"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, "", $0); print; exit }'
}

strip_structured_fields() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | grep -Ev '^ASK_[A-Z_]+=' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed '/^$/d'
}

is_valid_blocker_reason() {
  local reason="$1"
  case "$reason" in
    needs_user_fact|needs_user_decision|needs_scope_decision)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_structured_options() {
  local reason="$1"
  case "$reason" in
    needs_user_fact)
      cat <<'EOF'
Ответь одним комментарием с недостающим фактом или значением, которое нужно для продолжения.
EOF
      ;;
    needs_user_decision)
      cat <<'EOF'
Ответь одним комментарием с выбранным вариантом или коротким решением, которое нужно для продолжения.
EOF
      ;;
    needs_scope_decision)
      cat <<'EOF'
Ответь одним комментарием, что остаётся в scope текущей задачи, а что нужно вынести отдельно.
EOF
      ;;
  esac
}

render_structured_message() {
  local kind_label="$1"
  local reason="$2"
  local question="$3"
  local context="$4"

  if [[ -n "$context" ]]; then
    cat <<EOF
Контекст:
${context}

Вопрос executor:
${question}

Как ответить:
$(build_structured_options "$reason")
EOF
    return 0
  fi

  cat <<EOF
Вопрос executor:
${question}

Как ответить:
$(build_structured_options "$reason")
EOF
}

extract_question_line() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed '/^$/d' \
    | grep -E '.+\?' \
    | tail -n1 \
    | sed -E 's/^[*-][[:space:]]*//'
}

extract_decision_line() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed '/^$/d' \
    | grep -Ei '\b(продолжай|продолжить|финализируй|финализировать|подтверди|выбери|как действовать|нужен ответ|ответь)\b' \
    | tail -n1 \
    | sed -E 's/^[*-][[:space:]]*//'
}

sanitize_executor_remark_text() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed '/^$/d' \
    | grep -Eiv '^(thinking|exec|codex|viewed image|reconnecting|error:|warning:|tokens used|=== EXECUTOR_|/bin/zsh|```|USE THESE RULES|IMPORTANT:|Open the referenced issue|Plan:|^-\s+Progress updates|^-\s+Use only approved commands|^-\s+Act as a coding agent)'
}

format_recent_executor_paragraphs() {
  local text="$1"
  printf '%s\n' "$text" | awk '
    function normalize(p) {
      gsub(/\r/, "", p)
      gsub(/\n+/, " ", p)
      gsub(/[[:space:]]+/, " ", p)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
      return p
    }
    function store(p) {
      p = normalize(p)
      if (p == "") return
      idx = (count % 3) + 1
      arr[idx] = p
      count++
    }
    {
      if ($0 ~ /^[[:space:]]*$/) {
        store(buf)
        buf = ""
        next
      }
      if (buf == "") buf = $0
      else buf = buf "\n" $0
    }
    END {
      store(buf)
      if (count == 0) exit
      start = (count > 3 ? count - 2 : 1)
      rank = 1
      for (i = start; i <= count; i++) {
        idx = ((i - 1) % 3) + 1
        printf "%d) %s", rank, arr[idx]
        if (i < count) printf "\n"
        rank++
      }
    }
  '
}

extract_recent_codex_blocks_from_log() {
  if [[ ! -f "${RUNTIME_LOG_DIR}/executor.log" ]]; then
    return 0
  fi

  local start_line=""
  local log_slice_file=""
  start_line="$(grep -n '^=== EXECUTOR_RUN_START ' "${RUNTIME_LOG_DIR}/executor.log" | tail -n1 | cut -d: -f1 || true)"
  log_slice_file="$(mktemp "${STATE_TMP_DIR}/executor_log_slice.XXXXXX")"
  if [[ -n "$start_line" ]]; then
    sed -n "${start_line},\$p" "${RUNTIME_LOG_DIR}/executor.log" > "$log_slice_file"
  else
    tail -n 1200 "${RUNTIME_LOG_DIR}/executor.log" > "$log_slice_file"
  fi

  awk '
    function normalize(p) {
      gsub(/\r/, "", p)
      gsub(/\n+/, " ", p)
      gsub(/[[:space:]]+/, " ", p)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
      return p
    }
    function store_block(p) {
      p = normalize(p)
      if (p == "") return
      idx = (count % 3) + 1
      arr[idx] = p
      count++
    }
    function flush_buffer() {
      if (buffer != "") {
        store_block(buffer)
        buffer = ""
      }
    }
    BEGIN { capture = 0; buffer = ""; count = 0 }
    {
      line = $0
      if (line == "codex") {
        flush_buffer()
        capture = 1
        next
      }
      if (capture == 1) {
        if (line ~ /^(thinking|exec|viewed image|Reconnecting|ERROR:|Warning:|tokens used|=== EXECUTOR_|\/bin\/zsh|$)/) {
          flush_buffer()
          capture = 0
          next
        }
        if (buffer == "") buffer = line
        else buffer = buffer "\n" line
      }
    }
    END {
      flush_buffer()
      if (count == 0) exit
      start = (count > 3 ? count - 2 : 1)
      rank = 1
      for (i = start; i <= count; i++) {
        idx = ((i - 1) % 3) + 1
        printf "%d) %s", rank, arr[idx]
        if (i < count) printf "\n"
        rank++
      }
    }
  ' "$log_slice_file" 2>/dev/null || true

  rm -f "$log_slice_file"
}

strip_technical_lines() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed '/^$/d' \
    | grep -Eiv '(^Task:|^Issue:|^Exit code:|executor\.log|^Проверь лог|^Проверь логи)'
}

extract_context_line() {
  local text="$1"
  strip_technical_lines "$text" | head -n1
}

normalize_executor_question() {
  local line="$1"
  local normalized=""
  normalized="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  normalized="$(printf '%s' "$normalized" | sed -E 's#[^[:space:]]*/executor\.log#лог задачи#g; s#executor\.log#лог задачи#g')"

  if printf '%s' "$normalized" | grep -Eiq 'дай команду как действовать дальше|как действовать дальше'; then
    printf 'Как действовать дальше?'
    return 0
  fi

  normalized="$(printf '%s' "$normalized" | sed -E 's/^Проверь логи[^.]*\.[[:space:]]*//I')"
  normalized="$(printf '%s' "$normalized" | sed -E 's/^Проверь лог[^.]*\.[[:space:]]*//I')"
  normalized="$(printf '%s' "$normalized" | sed -E 's/[[:space:]]+/ /g')"
  normalized="$(printf '%s' "$normalized" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

  if [[ -z "$normalized" ]]; then
    printf 'Какой следующий шаг?'
    return 0
  fi

  printf '%s' "$normalized"
}

is_generic_executor_question() {
  local line="$1"
  local value
  value="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "как действовать дальше?" || "$value" == "какой следующий шаг?" || "$value" == "что дальше?" ]]
}

build_smart_options() {
  local raw_text="$1"
  local question_text="$2"
  local remark_text="$3"
  local kind="$4"
  local merged
  merged="$(printf '%s\n%s\n%s\n' "$raw_text" "$question_text" "$remark_text" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$merged" | grep -Eiq '(завершил текущий прогон без финализации|ждет твоего решения|финализируй|finalize|готов к ревью)'; then
    cat <<'EOF'
1) продолжай — запусти следующий рабочий прогон.
2) финализируй — заверши задачу и подготовь PR к ревью.
3) уточни: <что проверить перед финализацией>.
EOF
    return 0
  fi

  if printf '%s' "$merged" | grep -Eiq '(не смог продолжить|failed|exit code|ошибка|reconnecting|stream disconnected|api\.github|dns|network|таймаут|timeout|unreachable)'; then
    cat <<'EOF'
1) продолжай — перезапусти прогон и продолжи с последнего шага.
2) продолжай без сети — делай локальные правки/коммиты, GitHub-операции отложи.
3) опиши блокер — коротко: причина, что уже проверено, что нужно от меня.
EOF
    return 0
  fi

  if [[ "$kind" == "BLOCKER" ]]; then
    cat <<'EOF'
1) продолжай — выбери лучший следующий шаг и выполняй.
2) уточни — задай один конкретный вопрос, если данных недостаточно.
3) финализируй — останови реализацию и подготовь PR к ревью.
EOF
    return 0
  fi

  cat <<'EOF'
1) продолжай — выполняй следующий шаг по задаче.
2) финализируй — завершай задачу и готовь PR к ревью.
3) уточни — задай один конкретный вопрос перед продолжением.
EOF
}

detect_recommended_option() {
  local raw_text="$1"
  local question_text="$2"
  local remark_text="$3"
  local merged
  merged="$(printf '%s\n%s\n%s\n' "$raw_text" "$question_text" "$remark_text" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$merged" | grep -Eiq '(завершил текущий прогон без финализации|ждет твоего решения|готов к ревью)'; then
    printf '2'
    return 0
  fi

  printf '1'
}

infer_executor_question() {
  local candidate=""
  local src_text=""

  if [[ -s "${CODEX_DIR}/executor_last_message.txt" ]]; then
    src_text="$(<"${CODEX_DIR}/executor_last_message.txt")"
    candidate="$(extract_question_line "$src_text")"
    if [[ -z "$candidate" ]]; then
      candidate="$(extract_decision_line "$src_text")"
    fi
  fi

  if [[ -z "$candidate" && -f "${RUNTIME_LOG_DIR}/executor.log" ]]; then
    src_text="$(tail -n 400 "${RUNTIME_LOG_DIR}/executor.log" 2>/dev/null || true)"
    candidate="$(extract_question_line "$src_text")"
    if [[ -z "$candidate" ]]; then
      candidate="$(extract_decision_line "$src_text")"
    fi
  fi

  printf '%s' "$candidate"
}

infer_executor_remark() {
  local remark=""
  local src_text=""
  local cleaned=""
  local formatted=""

  if [[ -s "${CODEX_DIR}/executor_last_message.txt" ]]; then
    src_text="$(<"${CODEX_DIR}/executor_last_message.txt")"
    cleaned="$(sanitize_executor_remark_text "$src_text")"
    formatted="$(format_recent_executor_paragraphs "$cleaned")"
    if [[ -n "$formatted" ]]; then
      remark="$formatted"
    fi
  fi

  if [[ -z "$remark" ]]; then
    remark="$(extract_recent_codex_blocks_from_log)"
  fi

  printf '%s' "$remark"
}

post_issue_comment() {
  local issue_number="$1"
  local body="$2"
  local out=""
  local err_file
  err_file="$(mktemp "${STATE_TMP_DIR}/task_ask_gh_err.XXXXXX")"
  if out="$("${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" gh api "repos/${REPO}/issues/${issue_number}/comments" -f body="$body" 2>"$err_file")"; then
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
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
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

comment_message_text="$message_text"
structured_reason="$(extract_structured_field "ASK_REASON" "$message_text")"
structured_question="$(extract_structured_field "ASK_QUESTION" "$message_text")"
structured_context="$(extract_structured_field "ASK_CONTEXT" "$message_text")"
structured_extra="$(strip_structured_fields "$message_text")"

if [[ -n "$structured_context" && -n "$structured_extra" ]]; then
  structured_context="${structured_context}"$'\n\n'"${structured_extra}"
elif [[ -z "$structured_context" ]]; then
  structured_context="$structured_extra"
fi

if [[ "$kind_label" == "BLOCKER" ]]; then
  if [[ -z "$structured_reason" || -z "$structured_question" ]]; then
    echo "TASK_ASK_REJECTED=1"
    echo "TASK_ASK_REJECT_REASON=MALFORMED_BLOCKER"
    echo "TASK_ASK_ACTION=CONTINUE_WITHOUT_USER_REPLY"
    exit 0
  fi
  if ! is_valid_blocker_reason "$structured_reason"; then
    echo "TASK_ASK_REJECTED=1"
    echo "TASK_ASK_REJECT_REASON=UNSUPPORTED_BLOCKER_REASON"
    echo "TASK_ASK_ACTION=CONTINUE_WITHOUT_USER_REPLY"
    exit 0
  fi
  comment_message_text="$(render_structured_message "$kind_label" "$structured_reason" "$structured_question" "$structured_context")"
elif [[ -n "$structured_question" ]]; then
  comment_message_text="$(render_structured_message "$kind_label" "${structured_reason:-needs_user_decision}" "$structured_question" "$structured_context")"
fi

comment_body="$(cat <<EOF_COMMENT
CODEX_SIGNAL: ${signal}
CODEX_TASK: ${task_id}
CODEX_KIND: ${kind_label}
CODEX_EXPECT: USER_REPLY

Нужен твой ответ для продолжения работы по задаче.

${comment_message_text}

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

tmp_body="$(mktemp "${STATE_TMP_DIR}/question_body.XXXXXX")"
trap 'rm -f "$tmp_body"' EXIT
printf '%s\n' "$comment_body" > "$tmp_body"

if ! enqueue_out="$(
  "${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" \
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
