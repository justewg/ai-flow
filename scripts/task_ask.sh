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
executor_pid_file="${CODEX_DIR}/executor_pid.txt"
executor_heartbeat_pid_file="${CODEX_DIR}/executor_heartbeat_pid.txt"
executor_detach_file="${CODEX_DIR}/executor_detach_requested.txt"
executor_state_file="${CODEX_DIR}/executor_state.txt"
executor_review_handoff_reason_file="${CODEX_DIR}/executor_review_handoff_reason.txt"

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

trim_line() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

extract_structured_field() {
  local field_name="$1"
  local text="$2"
  printf '%s\n' "$text" \
    | sed 's/\r$//' \
    | awk -F= -v key="$field_name" '$1 == key { sub(/^[^=]*=/, "", $0); print; exit }'
}

contains_user_prompt_keywords() {
  local text
  text="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$text" \
    | grep -Eiq '\b(продолжай|продолжить|финализируй|финализировать|подтверди|выбери|как действовать|нужен ответ|ответь|какой|какая|какое|какие|что|нужно ли|можно ли|should|what|which|how|need your answer)\b'
}

is_malformed_question_candidate() {
  local value
  value="$(trim_line "$1")"

  [[ -z "$value" ]] && return 0

  if printf '%s' "$value" | grep -Eiq '^(null[[:space:]]*->[[:space:]]*".*\?"|\?\?[[:space:]]+.+|[0-9]{4}-[0-9]{2}-[0-9]{2}t[0-9:.+-]+.*\|.*event=|diff --git|index [0-9a-f]+\.\.[0-9a-f]+|@@|[+-]{3}[[:space:]]|override fun |versionname[[:space:]]*=|/bin/(ba|z)sh|[A-Za-z0-9_./-]+[[:space:]]*->[[:space:]]*".*")$'; then
    return 0
  fi

  return 1
}

is_actionable_user_prompt_candidate() {
  local value
  value="$(trim_line "$1")"

  if [[ -z "$value" ]] || is_malformed_question_candidate "$value"; then
    return 1
  fi

  if contains_user_prompt_keywords "$value"; then
    return 0
  fi

  if [[ "$value" == *"?"* ]] && printf '%s' "$value" | grep -Eq '[[:alpha:]]'; then
    return 0
  fi

  return 1
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
    if [[ -n "$candidate" ]] && ! is_actionable_user_prompt_candidate "$candidate"; then
      candidate=""
    fi
    if [[ -z "$candidate" ]]; then
      candidate="$(extract_decision_line "$src_text")"
      if [[ -n "$candidate" ]] && ! is_actionable_user_prompt_candidate "$candidate"; then
        candidate=""
      fi
    fi
  fi

  if [[ -z "$candidate" && -f "${RUNTIME_LOG_DIR}/executor.log" ]]; then
    src_text="$(tail -n 400 "${RUNTIME_LOG_DIR}/executor.log" 2>/dev/null || true)"
    candidate="$(extract_question_line "$src_text")"
    if [[ -n "$candidate" ]] && ! is_actionable_user_prompt_candidate "$candidate"; then
      candidate=""
    fi
    if [[ -z "$candidate" ]]; then
      candidate="$(extract_decision_line "$src_text")"
      if [[ -n "$candidate" ]] && ! is_actionable_user_prompt_candidate "$candidate"; then
        candidate=""
      fi
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

render_question_message() {
  local text="$1"
  local kind="$2"
  local structured_q=""
  local explicit_q=""
  local explicit_decision=""
  local inferred_q=""
  local fallback_q=""
  local selected_q=""
  local context_line=""
  local executor_remark=""
  local smart_options=""
  local recommended_option=""

  structured_q="$(extract_structured_field "ASK_QUESTION" "$text")"
  if [[ -n "$structured_q" ]] && ! is_actionable_user_prompt_candidate "$structured_q"; then
    structured_q=""
  fi

  explicit_q="$(extract_question_line "$text")"
  if [[ -n "$explicit_q" ]] && ! is_actionable_user_prompt_candidate "$explicit_q"; then
    explicit_q=""
  fi

  explicit_decision="$(extract_decision_line "$text")"
  if [[ -n "$explicit_decision" ]] && ! is_actionable_user_prompt_candidate "$explicit_decision"; then
    explicit_decision=""
  fi

  if [[ -n "$structured_q" ]]; then
    selected_q="$structured_q"
  elif [[ -n "$explicit_q" ]]; then
    selected_q="$explicit_q"
  elif [[ -n "$explicit_decision" ]]; then
    selected_q="$explicit_decision"
  fi

  if [[ -z "$selected_q" && "$kind" != "BLOCKER" ]]; then
    inferred_q="$(infer_executor_question)"
    if [[ -n "$inferred_q" ]]; then
      selected_q="$inferred_q"
    fi
  fi

  if [[ -z "$selected_q" && "$kind" == "BLOCKER" ]]; then
    printf '%s' "__TASK_ASK_REJECTED_MALFORMED_BLOCKER__"
    return 0
  fi

  if [[ -z "$selected_q" ]]; then
    fallback_q="$(extract_context_line "$text")"
    if [[ -z "$fallback_q" ]]; then
      fallback_q="$(printf '%s\n' "$text" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sed '/^$/d' | head -n1)"
    fi
    selected_q="$fallback_q"
  fi

  selected_q="$(normalize_executor_question "$selected_q")"
  if is_generic_executor_question "$selected_q"; then
    selected_q="Выбери следующий шаг для executor."
  fi
  context_line="$(extract_context_line "$text")"
  executor_remark="$(infer_executor_remark)"
  smart_options="$(build_smart_options "$text" "$selected_q" "$executor_remark" "$kind")"
  recommended_option="$(detect_recommended_option "$text" "$selected_q" "$executor_remark")"

  if [[ -n "$selected_q" ]]; then
    if [[ -n "$executor_remark" && "$executor_remark" != "$selected_q" && "$executor_remark" != "$context_line" ]]; then
      cat <<EOF_RENDER
Последние ремарки executor:
${executor_remark}

EOF_RENDER
    fi

    if [[ -n "$context_line" && "$context_line" != "$selected_q" ]]; then
      cat <<EOF_RENDER
Контекст:
${context_line}

Вопрос executor:
${selected_q}

Варианты ответа:
${smart_options}
Рекомендовано: ${recommended_option}
EOF_RENDER
    else
      cat <<EOF_RENDER
Вопрос executor:
${selected_q}

Варианты ответа:
${smart_options}
Рекомендовано: ${recommended_option}
EOF_RENDER
    fi
    return 0
  fi

  printf '%s' "$text"
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

kill_pid_gracefully() {
  local pid="$1"
  [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
}

request_executor_stop() {
  local pid=""
  local heartbeat_pid=""
  pid="$(cat "$executor_pid_file" 2>/dev/null || true)"
  heartbeat_pid="$(cat "$executor_heartbeat_pid_file" 2>/dev/null || true)"

  # Drop RUNNING immediately so watchdog does not freeze on a deliberate wait handoff.
  printf '%s\n' "REVIEW_NEEDED" > "$executor_state_file"
  printf '%s\n' "waiting_user_reply" > "$executor_review_handoff_reason_file"
  printf '%s\n' "stop-requested" > "$executor_detach_file"
  kill_pid_gracefully "$heartbeat_pid"
  kill_pid_gracefully "$pid"

  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "EXECUTOR_STOP_REQUESTED=1"
    echo "EXECUTOR_STOP_PID=$pid"
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
if [[ "$kind_label" == "QUESTION" || "$kind_label" == "BLOCKER" ]]; then
  comment_message_text="$(render_question_message "$message_text" "$kind_label")"
  if [[ "$comment_message_text" == "__TASK_ASK_REJECTED_MALFORMED_BLOCKER__" ]]; then
    echo "TASK_ASK_REJECTED_MALFORMED_BLOCKER=1"
    echo "TASK_ASK_REJECTED_KIND=${kind_label}"
    exit 42
  fi
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
  : > "$pending_post_file"
  request_executor_stop

  wait_reason="waiting human reply"
  if [[ "$kind_label" == "BLOCKER" ]]; then
    wait_reason="waiting human unblock"
  fi
  wait_payload="$(build_wait_payload "$question_comment_id" "$wait_reason" "$kind_label" "$question_comment_url" false "$now_utc")"
  emit_runtime_v2_event \
    "human.wait_requested" \
    "legacy-v2-wait-${task_id}-${question_comment_id}" \
    "legacy.human.wait_requested:${task_id}:${question_comment_id}" \
    "$wait_payload"
  reconcile_runtime_v2_primary_context

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

printf '%s\n' "1" > "$pending_post_file"
request_executor_stop

wait_reason="waiting human reply"
if [[ "$kind_label" == "BLOCKER" ]]; then
  wait_reason="waiting human unblock"
fi
wait_payload="$(build_wait_payload "-1" "$wait_reason" "$kind_label" "" true "$now_utc")"
emit_runtime_v2_event \
  "human.wait_requested" \
  "legacy-v2-wait-${task_id}-pending-${now_utc}" \
  "legacy.human.wait_requested:${task_id}:pending" \
  "$wait_payload"
reconcile_runtime_v2_primary_context

echo "QUESTION_QUEUED_OUTBOX=1"
echo "TASK_ID=$task_id"
echo "ISSUE_NUMBER=$issue_number"
echo "QUESTION_KIND=$kind_label"
echo "WAIT_GITHUB_API_UNSTABLE=1"
echo "WAITING_FOR_USER_REPLY_PENDING_POST=1"
