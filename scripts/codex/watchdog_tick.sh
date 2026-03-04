#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

LOG_FILE="${CODEX_DIR}/watchdog.log"
STATE_FILE="${CODEX_DIR}/watchdog_state.txt"
DETAIL_FILE="${CODEX_DIR}/watchdog_state_detail.txt"
LAST_ACTION_FILE="${CODEX_DIR}/watchdog_last_action.txt"
LAST_ACTION_EPOCH_FILE="${CODEX_DIR}/watchdog_last_action_epoch.txt"
DAEMON_LOG_FILE="${CODEX_DIR}/daemon.log"
DAEMON_LOCK_DIR="${CODEX_DIR}/daemon.lock"

DAEMON_LABEL="${WATCHDOG_DAEMON_LABEL:-com.planka.codex-daemon}"
DAEMON_INTERVAL="${WATCHDOG_DAEMON_INTERVAL_SEC:-45}"
COOLDOWN_SEC="${WATCHDOG_COOLDOWN_SEC:-120}"
EXECUTOR_STALE_SEC="${WATCHDOG_EXECUTOR_STALE_SEC:-180}"
DAEMON_LOG_STALE_SEC="${WATCHDOG_DAEMON_LOG_STALE_SEC:-180}"

mkdir -p "$CODEX_DIR"

parse_uint_or_default() {
  local raw="$1"
  local default_value="$2"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "$default_value"
  fi
}

COOLDOWN_SEC="$(parse_uint_or_default "$COOLDOWN_SEC" "120")"
EXECUTOR_STALE_SEC="$(parse_uint_or_default "$EXECUTOR_STALE_SEC" "180")"
DAEMON_LOG_STALE_SEC="$(parse_uint_or_default "$DAEMON_LOG_STALE_SEC" "180")"
DAEMON_INTERVAL="$(parse_uint_or_default "$DAEMON_INTERVAL" "45")"

if (( COOLDOWN_SEC < 30 )); then COOLDOWN_SEC=30; fi
if (( EXECUTOR_STALE_SEC < 60 )); then EXECUTOR_STALE_SEC=60; fi
if (( DAEMON_LOG_STALE_SEC < 60 )); then DAEMON_LOG_STALE_SEC=60; fi
if (( DAEMON_INTERVAL < 5 )); then DAEMON_INTERVAL=45; fi

log() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s %s\n' "$ts" "$*" >> "$LOG_FILE"
}

set_state() {
  local state="$1"
  local detail="${2:-}"
  printf '%s\n' "$state" > "$STATE_FILE"
  printf '%s\n' "$detail" > "$DETAIL_FILE"
  if [[ -n "$detail" ]]; then
    log "STATE=$state DETAIL=$detail"
  else
    log "STATE=$state"
  fi
}

read_file_or_default() {
  local file_path="$1"
  local default_value="$2"
  if [[ -s "$file_path" ]]; then
    cat "$file_path"
  else
    printf '%s' "$default_value"
  fi
}

file_mtime_epoch() {
  local file_path="$1"
  if [[ ! -e "$file_path" ]]; then
    echo "0"
    return 0
  fi
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path"
    return 0
  fi
  if stat -c %Y "$file_path" >/dev/null 2>&1; then
    stat -c %Y "$file_path"
    return 0
  fi
  echo "0"
}

emit_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
    log "$line"
  done <<< "$text"
}

is_pid_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

daemon_loop_running() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi
  pgrep -f "${ROOT_DIR}/scripts/codex/daemon_loop.sh" >/dev/null 2>&1
}

html_escape() {
  local value="${1:-}"
  jq -rn --arg v "$value" '$v|@html'
}

watchdog_reason_human_text() {
  local reason="$1"
  case "$reason" in
    DAEMON_LOG_STALE_WITH_LOCK)
      echo "daemon завис: lock удерживается, но лог не обновляется"
      ;;
    EXECUTOR_PID_DEAD)
      echo "executor помечен как RUNNING, но процесс не найден"
      ;;
    EXECUTOR_HEARTBEAT_STALE)
      echo "executor завис: heartbeat не обновлялся слишком долго"
      ;;
    DAEMON_IDLE_WITH_ACTIVE_TASK)
      echo "daemon ушёл в IDLE при наличии активной задачи"
      ;;
    ACTIVE_TASK_WITHOUT_EXECUTOR_STATE)
      echo "активная задача есть, но состояние executor отсутствует"
      ;;
    *)
      echo "внутренняя причина watchdog: ${reason}"
      ;;
  esac
}

notify_action() {
  local action="$1"
  local reason="$2"
  local detail="$3"
  local msg_file
  msg_file="$(mktemp "${CODEX_DIR}/watchdog_notify.XXXXXX")"
  local now_utc check_icon title aux_text aux_escaped reason_human
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  reason_human="$(watchdog_reason_human_text "$reason")"
  if [[ "$action" == "NONE" ]]; then
    check_icon="💤"
  else
    check_icon="🚨"
  fi
  title="<b>${check_icon} 🛟 WATCHDOG: $(html_escape "$action")</b>"
  aux_text=$'ACTION='"${action}"$'\n'
  aux_text+=$'REASON='"${reason}"$'\n'
  aux_text+=$'DETAIL='"${detail}"$'\n'
  aux_text+=$'TIME_UTC='"${now_utc}"
  aux_escaped="$(html_escape "$aux_text")"
  cat > "$msg_file" <<EOF
${title}
<b>⚙️ Reason:</b> <code>$(html_escape "$reason_human")</code>
<blockquote><code>${aux_escaped}</code></blockquote>
EOF
  local out rc
  if out="$("${ROOT_DIR}/scripts/codex/telegram_local_notify.sh" "$msg_file" 2>&1)"; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "TG_NOTIFY: $line"
    done <<< "$out"
  else
    rc=$?
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log "TG_NOTIFY_ERROR(rc=$rc): $line"
    done <<< "$out"
  fi
  rm -f "$msg_file"
}

run_soft_tick() {
  local out rc
  if out="$("${ROOT_DIR}/scripts/codex/daemon_tick.sh" 2>&1)"; then
    emit_lines "$out"
    return 0
  fi
  rc=$?
  emit_lines "$out"
  return "$rc"
}

run_medium_recovery() {
  local rc=0
  local out

  if out="$("${ROOT_DIR}/scripts/codex/executor_reset.sh" 2>&1)"; then
    emit_lines "$out"
  else
    rc=$?
    emit_lines "$out"
  fi

  if out="$("${ROOT_DIR}/scripts/codex/daemon_tick.sh" 2>&1)"; then
    emit_lines "$out"
  else
    local tick_rc=$?
    emit_lines "$out"
    if [[ "$rc" -eq 0 ]]; then
      rc="$tick_rc"
    fi
  fi

  return "$rc"
}

run_hard_recovery() {
  local rc=0
  local out

  if [[ -d "$DAEMON_LOCK_DIR" ]] && ! daemon_loop_running; then
    rm -rf "$DAEMON_LOCK_DIR"
    log "STALE_DAEMON_LOCK_REMOVED=1"
    echo "STALE_DAEMON_LOCK_REMOVED=1"
  fi

  if out="$("${ROOT_DIR}/scripts/codex/daemon_uninstall.sh" "$DAEMON_LABEL" 2>&1)"; then
    emit_lines "$out"
  else
    rc=$?
    emit_lines "$out"
  fi

  if out="$("${ROOT_DIR}/scripts/codex/daemon_install.sh" "$DAEMON_LABEL" "$DAEMON_INTERVAL" 2>&1)"; then
    emit_lines "$out"
  else
    local install_rc=$?
    emit_lines "$out"
    if [[ "$rc" -eq 0 ]]; then
      rc="$install_rc"
    fi
  fi

  if out="$("${ROOT_DIR}/scripts/codex/daemon_status.sh" "$DAEMON_LABEL" 2>&1)"; then
    emit_lines "$out"
  else
    local status_rc=$?
    emit_lines "$out"
    if [[ "$rc" -eq 0 ]]; then
      rc="$status_rc"
    fi
  fi

  return "$rc"
}

now_epoch="$(date +%s)"

if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
  detail="WATCHDOG_PAUSED_DIRTY_WORKTREE=1"
  set_state "PAUSED_DIRTY_WORKTREE" "$detail"
  echo "$detail"
  echo "WATCHDOG_ACTION=NONE"
  echo "WATCHDOG_REASON=DIRTY_WORKTREE_TRACKED"
  echo "WATCHDOG_OK=1"
  exit 0
fi

active_task="$(read_file_or_default "${CODEX_DIR}/daemon_active_task.txt" "")"
active_issue="$(read_file_or_default "${CODEX_DIR}/daemon_active_issue_number.txt" "")"
daemon_state="$(read_file_or_default "${CODEX_DIR}/daemon_state.txt" "UNKNOWN")"
daemon_detail="$(read_file_or_default "${CODEX_DIR}/daemon_state_detail.txt" "")"
executor_state="$(read_file_or_default "${CODEX_DIR}/executor_state.txt" "")"
executor_pid="$(read_file_or_default "${CODEX_DIR}/executor_pid.txt" "")"
executor_hb_epoch="$(read_file_or_default "${CODEX_DIR}/executor_heartbeat_epoch.txt" "0")"
executor_hb_epoch="$(parse_uint_or_default "$executor_hb_epoch" "0")"
daemon_log_mtime="$(file_mtime_epoch "$DAEMON_LOG_FILE")"
daemon_log_mtime="$(parse_uint_or_default "$daemon_log_mtime" "0")"

daemon_log_age=999999
if (( daemon_log_mtime > 0 )); then
  daemon_log_age=$(( now_epoch - daemon_log_mtime ))
fi

last_action_epoch="$(read_file_or_default "$LAST_ACTION_EPOCH_FILE" "0")"
last_action_epoch="$(parse_uint_or_default "$last_action_epoch" "0")"
last_action_name="$(read_file_or_default "$LAST_ACTION_FILE" "NONE")"

executor_pid_alive="0"
if is_pid_alive "$executor_pid"; then
  executor_pid_alive="1"
fi

action="NONE"
reason=""

if [[ -d "$DAEMON_LOCK_DIR" && $daemon_log_age -gt $DAEMON_LOG_STALE_SEC ]]; then
  action="HARD_RESTART_DAEMON"
  reason="DAEMON_LOG_STALE_WITH_LOCK"
elif [[ -n "$active_task" ]]; then
  if [[ "$executor_state" == "RUNNING" && "$executor_pid_alive" != "1" ]]; then
    action="MEDIUM_RESET_EXECUTOR"
    reason="EXECUTOR_PID_DEAD"
  elif [[ "$executor_state" == "RUNNING" && "$executor_hb_epoch" -gt 0 && $(( now_epoch - executor_hb_epoch )) -gt $EXECUTOR_STALE_SEC ]]; then
    action="MEDIUM_RESET_EXECUTOR"
    reason="EXECUTOR_HEARTBEAT_STALE"
  elif [[ "$daemon_state" == "IDLE_NO_TASKS" ]]; then
    action="SOFT_DAEMON_TICK"
    reason="DAEMON_IDLE_WITH_ACTIVE_TASK"
  elif [[ -z "$executor_state" ]]; then
    action="SOFT_DAEMON_TICK"
    reason="ACTIVE_TASK_WITHOUT_EXECUTOR_STATE"
  fi
fi

summary="active_task=${active_task:-none};active_issue=${active_issue:-none};daemon_state=${daemon_state};executor_state=${executor_state:-none};executor_pid=${executor_pid:-none};executor_pid_alive=${executor_pid_alive};daemon_log_age=${daemon_log_age}s"
echo "WATCHDOG_SUMMARY=${summary}"
log "WATCHDOG_SUMMARY=${summary}"

if [[ "$action" == "NONE" ]]; then
  set_state "HEALTHY" "$summary"
  echo "WATCHDOG_ACTION=NONE"
  echo "WATCHDOG_REASON=NO_RECOVERY_NEEDED"
  echo "WATCHDOG_OK=1"
  exit 0
fi

since_last=$(( now_epoch - last_action_epoch ))
if (( since_last < COOLDOWN_SEC )); then
  detail="action=${action};reason=${reason};cooldown_left=$((COOLDOWN_SEC - since_last));last_action=${last_action_name}"
  set_state "COOLDOWN" "$detail"
  echo "WATCHDOG_ACTION=DEFERRED_COOLDOWN"
  echo "WATCHDOG_REASON=${reason}"
  echo "WATCHDOG_COOLDOWN_LEFT_SEC=$((COOLDOWN_SEC - since_last))"
  echo "WATCHDOG_LAST_ACTION=${last_action_name}"
  exit 0
fi

detail="action=${action};reason=${reason};${summary}"
set_state "RECOVERY_ACTION_PENDING" "$detail"
echo "WATCHDOG_ACTION=${action}"
echo "WATCHDOG_REASON=${reason}"
notify_action "$action" "$reason" "$summary"

action_rc=0
if [[ "$action" == "SOFT_DAEMON_TICK" ]]; then
  if ! run_soft_tick; then
    action_rc=$?
  fi
elif [[ "$action" == "MEDIUM_RESET_EXECUTOR" ]]; then
  if ! run_medium_recovery; then
    action_rc=$?
  fi
elif [[ "$action" == "HARD_RESTART_DAEMON" ]]; then
  if ! run_hard_recovery; then
    action_rc=$?
  fi
fi

printf '%s\n' "$action" > "$LAST_ACTION_FILE"
printf '%s\n' "$now_epoch" > "$LAST_ACTION_EPOCH_FILE"

if [[ "$action_rc" -eq 0 ]]; then
  set_state "RECOVERY_ACTION_APPLIED" "action=${action};reason=${reason}"
  echo "WATCHDOG_ACTION_RESULT=OK"
  exit 0
fi

set_state "RECOVERY_ACTION_FAILED" "action=${action};reason=${reason};rc=${action_rc}"
echo "WATCHDOG_ACTION_RESULT=FAILED"
echo "WATCHDOG_ACTION_RC=${action_rc}"
exit 0
