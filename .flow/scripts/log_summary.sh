#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
DAEMON_LOG_SRC="${RUNTIME_LOG_DIR}/daemon.log"
WATCHDOG_LOG_SRC="${RUNTIME_LOG_DIR}/watchdog.log"
GQL_STATS_LOG_SRC="${RUNTIME_LOG_DIR}/graphql_rate_stats.log"
RUNTIME_QUEUE_FILE_SRC="${CODEX_DIR}/project_status_runtime_queue.json"

TMP_BASE="${TMPDIR:-/tmp}"
SNAPSHOT_DIR="$(mktemp -d "${TMP_BASE}/codex-log-summary.XXXXXX")"
cleanup() {
  rm -rf "${SNAPSHOT_DIR}"
}
trap cleanup EXIT

snapshot_or_touch() {
  local src="$1"
  local dst="$2"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
  else
    : > "$dst"
  fi
}

DAEMON_LOG="${SNAPSHOT_DIR}/daemon.log"
WATCHDOG_LOG="${SNAPSHOT_DIR}/watchdog.log"
GQL_STATS_LOG="${SNAPSHOT_DIR}/graphql_rate_stats.log"
RUNTIME_QUEUE_FILE="${SNAPSHOT_DIR}/project_status_runtime_queue.json"

snapshot_or_touch "$DAEMON_LOG_SRC" "$DAEMON_LOG"
snapshot_or_touch "$WATCHDOG_LOG_SRC" "$WATCHDOG_LOG"
snapshot_or_touch "$GQL_STATS_LOG_SRC" "$GQL_STATS_LOG"
snapshot_or_touch "$RUNTIME_QUEUE_FILE_SRC" "$RUNTIME_QUEUE_FILE"

iso_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

iso_hours_ago_utc() {
  local hours="$1"
  if date -u -d "1970-01-01T00:00:00Z" '+%s' >/dev/null 2>&1; then
    date -u -d "${hours} hours ago" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u -v-"${hours}"H '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

iso_to_epoch() {
  local ts="$1"
  if date -u -d "$ts" '+%s' >/dev/null 2>&1; then
    date -u -d "$ts" '+%s'
  else
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s'
  fi
}

is_valid_iso_utc() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

in_range_ts() {
  local ts="$1"
  local from="$2"
  local to="$3"
  [[ "$ts" < "$from" ]] && return 1
  [[ "$ts" > "$to" ]] && return 1
  return 0
}

fmt_duration() {
  local total="$1"
  if ! [[ "$total" =~ ^[0-9]+$ ]]; then
    total=0
  fi
  local d h m s
  d=$(( total / 86400 ))
  h=$(( (total % 86400) / 3600 ))
  m=$(( (total % 3600) / 60 ))
  s=$(( total % 60 ))
  if (( d > 0 )); then
    printf '%dd %02dh %02dm %02ds' "$d" "$h" "$m" "$s"
  elif (( h > 0 )); then
    printf '%dh %02dm %02ds' "$h" "$m" "$s"
  elif (( m > 0 )); then
    printf '%dm %02ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

safe_avg() {
  local sum="$1"
  local count="$2"
  if ! [[ "$sum" =~ ^-?[0-9]+$ ]]; then
    sum=0
  fi
  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count == 0 )); then
    printf '0'
    return 0
  fi
  awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.2f", s/c }'
}

usage() {
  cat <<'EOF'
Usage:
  .flow/scripts/log_summary.sh [--hours N] [--from ISO_UTC] [--to ISO_UTC]

Examples:
  .flow/scripts/log_summary.sh
  .flow/scripts/log_summary.sh --hours 6
  .flow/scripts/log_summary.sh --from 2026-02-28T00:00:00Z --to 2026-02-28T12:00:00Z
EOF
}

hours="24"
from_ts=""
to_ts=""
hours_explicit="0"

detect_earliest_ts() {
  local candidate="" line ts
  local files=("$DAEMON_LOG" "$WATCHDOG_LOG" "$GQL_STATS_LOG")
  local f
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    line="$(awk 'NF{print; exit}' "$f" 2>/dev/null || true)"
    [[ -n "$line" ]] || continue
    ts="${line:0:20}"
    if ! is_valid_iso_utc "$ts"; then
      continue
    fi
    if [[ -z "$candidate" || "$ts" < "$candidate" ]]; then
      candidate="$ts"
    fi
  done
  printf '%s' "$candidate"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)
      [[ $# -ge 2 ]] || { echo "Missing value for --hours"; exit 1; }
      hours="$2"
      hours_explicit="1"
      shift 2
      ;;
    --from)
      [[ $# -ge 2 ]] || { echo "Missing value for --from"; exit 1; }
      from_ts="$2"
      shift 2
      ;;
    --to)
      [[ $# -ge 2 ]] || { echo "Missing value for --to"; exit 1; }
      to_ts="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$to_ts" ]]; then
  to_ts="$(iso_now_utc)"
fi

if [[ -z "$from_ts" ]]; then
  if [[ "$hours_explicit" == "1" ]]; then
    if ! [[ "$hours" =~ ^[0-9]+$ ]] || (( hours < 1 )); then
      echo "--hours must be integer >= 1"
      exit 1
    fi
    from_ts="$(iso_hours_ago_utc "$hours")"
  else
    from_ts="$(detect_earliest_ts)"
    if [[ -z "$from_ts" ]]; then
      from_ts="$(iso_hours_ago_utc 24)"
    fi
  fi
fi

if ! is_valid_iso_utc "$from_ts"; then
  echo "Invalid --from format: $from_ts (expected YYYY-MM-DDTHH:MM:SSZ)"
  exit 1
fi
if ! is_valid_iso_utc "$to_ts"; then
  echo "Invalid --to format: $to_ts (expected YYYY-MM-DDTHH:MM:SSZ)"
  exit 1
fi
if [[ "$from_ts" > "$to_ts" ]]; then
  echo "--from must be <= --to"
  exit 1
fi

from_epoch="$(iso_to_epoch "$from_ts")"
to_epoch="$(iso_to_epoch "$to_ts")"

daemon_heartbeat=0
daemon_state_changes=0
daemon_wait_github_offline_entries=0
daemon_wait_github_rate_entries=0
daemon_wait_github_unavail_seconds=0
daemon_wait_dirty_entries=0
daemon_wait_dirty_blocking_entries=0
daemon_wait_dirty_nonblocking_entries=0
daemon_wait_user_reply_entries=0
daemon_wait_review_feedback_entries=0
daemon_wait_dependencies_entries=0
daemon_github_status_unreachable_entries=0
daemon_github_status_dns_entries=0
daemon_github_status_unstable_entries=0
daemon_github_status_unavail_seconds=0
daemon_prev_state=""
daemon_prev_state_epoch=0
daemon_prev_github_bad=0
daemon_prev_github_state_epoch=0
daemon_wait_api_unstable_markers=0
daemon_wait_rate_limit_markers=0
daemon_net_errors=0
daemon_wait_dirty_seconds=0
daemon_wait_user_reply_seconds=0
daemon_wait_review_feedback_seconds=0
daemon_wait_dependencies_seconds=0
daemon_idle_no_tasks_seconds=0
daemon_current_state_age_seconds=0

runtime_enqueued=0
runtime_applied=0
runtime_wait=0
runtime_queue_done=0
runtime_wait_tg=0
runtime_recovered_tg=0
runtime_wait_open_epoch=0
runtime_wait_total_seconds=0
runtime_wait_ongoing=0

if [[ -f "$DAEMON_LOG" ]]; then
  while IFS= read -r line; do
    [[ ${#line} -ge 20 ]] || continue
    ts="${line:0:20}"
    msg="${line:21}"
    in_range_ts "$ts" "$from_ts" "$to_ts" || continue

    [[ "$msg" == "heartbeat" ]] && daemon_heartbeat=$((daemon_heartbeat + 1))
    [[ "$msg" == *"WAIT_GITHUB_API_UNSTABLE=1"* ]] && daemon_wait_api_unstable_markers=$((daemon_wait_api_unstable_markers + 1))
    [[ "$msg" == *"WAIT_GITHUB_RATE_LIMIT=1"* ]] && daemon_wait_rate_limit_markers=$((daemon_wait_rate_limit_markers + 1))
    [[ "$msg" == *"error connecting to api.github.com"* ]] && daemon_net_errors=$((daemon_net_errors + 1))
    [[ "$msg" == *"RUNTIME_PROJECT_STATUS_ENQUEUED=1"* ]] && runtime_enqueued=$((runtime_enqueued + 1))
    [[ "$msg" == *"RUNTIME_PROJECT_STATUS_APPLIED=1"* ]] && runtime_applied=$((runtime_applied + 1))
    [[ "$msg" == *"RUNTIME_PROJECT_STATUS_WAIT_GITHUB=1"* ]] && runtime_wait=$((runtime_wait + 1))
    [[ "$msg" == *"RUNTIME_PROJECT_STATUS_QUEUE_DONE=1"* ]] && runtime_queue_done=$((runtime_queue_done + 1))

    if [[ "$msg" == *"TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_WAIT"* ]]; then
      runtime_wait_tg=$((runtime_wait_tg + 1))
      if (( runtime_wait_open_epoch == 0 )); then
        runtime_wait_open_epoch="$(iso_to_epoch "$ts")"
      fi
    fi
    if [[ "$msg" == *"TG_NOTIFY_RUNTIME_REASON=GITHUB_RUNTIME_RECOVERED"* ]]; then
      runtime_recovered_tg=$((runtime_recovered_tg + 1))
      if (( runtime_wait_open_epoch > 0 )); then
        rec_epoch="$(iso_to_epoch "$ts")"
        if (( rec_epoch >= runtime_wait_open_epoch )); then
          runtime_wait_total_seconds=$((runtime_wait_total_seconds + rec_epoch - runtime_wait_open_epoch))
        fi
        runtime_wait_open_epoch=0
      fi
    fi

    if [[ "$msg" =~ ^STATE=([^[:space:]]+) ]]; then
      state="${BASH_REMATCH[1]}"
      state_epoch="$(iso_to_epoch "$ts")"
      daemon_state_changes=$((daemon_state_changes + 1))
      if [[ "$state" == "WAIT_GITHUB_OFFLINE" ]]; then
        daemon_wait_github_offline_entries=$((daemon_wait_github_offline_entries + 1))
      elif [[ "$state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
        daemon_wait_github_rate_entries=$((daemon_wait_github_rate_entries + 1))
      elif [[ "$state" == "WAIT_DIRTY_WORKTREE" ]]; then
        daemon_wait_dirty_entries=$((daemon_wait_dirty_entries + 1))
        if [[ "$msg" == *"WAIT_DIRTY_WORKTREE_BLOCKING_TODO=1"* ]]; then
          daemon_wait_dirty_blocking_entries=$((daemon_wait_dirty_blocking_entries + 1))
        else
          daemon_wait_dirty_nonblocking_entries=$((daemon_wait_dirty_nonblocking_entries + 1))
        fi
      elif [[ "$state" == "WAIT_USER_REPLY" ]]; then
        daemon_wait_user_reply_entries=$((daemon_wait_user_reply_entries + 1))
      elif [[ "$state" == "WAIT_REVIEW_FEEDBACK" ]]; then
        daemon_wait_review_feedback_entries=$((daemon_wait_review_feedback_entries + 1))
      elif [[ "$state" == "WAIT_DEPENDENCIES" ]]; then
        daemon_wait_dependencies_entries=$((daemon_wait_dependencies_entries + 1))
      fi

      if [[ -n "$daemon_prev_state" && "$daemon_prev_state_epoch" =~ ^[0-9]+$ && "$state_epoch" =~ ^[0-9]+$ ]]; then
        if (( state_epoch >= daemon_prev_state_epoch )); then
          delta=$((state_epoch - daemon_prev_state_epoch))
          if [[ "$daemon_prev_state" == "WAIT_GITHUB_OFFLINE" || "$daemon_prev_state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
            daemon_wait_github_unavail_seconds=$((daemon_wait_github_unavail_seconds + delta))
          fi
          case "$daemon_prev_state" in
            WAIT_DIRTY_WORKTREE)
              daemon_wait_dirty_seconds=$((daemon_wait_dirty_seconds + delta))
              ;;
            WAIT_USER_REPLY)
              daemon_wait_user_reply_seconds=$((daemon_wait_user_reply_seconds + delta))
              ;;
            WAIT_REVIEW_FEEDBACK)
              daemon_wait_review_feedback_seconds=$((daemon_wait_review_feedback_seconds + delta))
              ;;
            WAIT_DEPENDENCIES)
              daemon_wait_dependencies_seconds=$((daemon_wait_dependencies_seconds + delta))
              ;;
            IDLE_NO_TASKS)
              daemon_idle_no_tasks_seconds=$((daemon_idle_no_tasks_seconds + delta))
              ;;
          esac
        fi
      fi
      daemon_prev_state="$state"
      daemon_prev_state_epoch="$state_epoch"

      github_status=""
      if [[ "$msg" =~ GITHUB_STATUS=([^;\|[:space:]]+) ]]; then
        github_status="${BASH_REMATCH[1]}"
      fi
      github_bad=0
      case "$github_status" in
        DNS_OFFLINE)
          daemon_github_status_dns_entries=$((daemon_github_status_dns_entries + 1))
          github_bad=1
          ;;
        UNREACHABLE)
          daemon_github_status_unreachable_entries=$((daemon_github_status_unreachable_entries + 1))
          github_bad=1
          ;;
        UNSTABLE)
          daemon_github_status_unstable_entries=$((daemon_github_status_unstable_entries + 1))
          github_bad=1
          ;;
      esac

      if (( daemon_prev_github_state_epoch > 0 && state_epoch >= daemon_prev_github_state_epoch )); then
        delta_bad=$((state_epoch - daemon_prev_github_state_epoch))
        if (( daemon_prev_github_bad == 1 )); then
          daemon_github_status_unavail_seconds=$((daemon_github_status_unavail_seconds + delta_bad))
        fi
      fi
      daemon_prev_github_bad="$github_bad"
      daemon_prev_github_state_epoch="$state_epoch"
    fi
  done < "$DAEMON_LOG"
fi

if (( runtime_wait_open_epoch > 0 )); then
  if (( to_epoch >= runtime_wait_open_epoch )); then
    runtime_wait_total_seconds=$((runtime_wait_total_seconds + to_epoch - runtime_wait_open_epoch))
  fi
  runtime_wait_ongoing=1
fi

if [[ "$daemon_prev_state" == "WAIT_GITHUB_OFFLINE" || "$daemon_prev_state" == "WAIT_GITHUB_RATE_LIMIT" ]]; then
  if (( to_epoch >= daemon_prev_state_epoch )); then
    daemon_wait_github_unavail_seconds=$((daemon_wait_github_unavail_seconds + to_epoch - daemon_prev_state_epoch))
  fi
fi
if [[ -n "$daemon_prev_state" && "$daemon_prev_state_epoch" =~ ^[0-9]+$ ]] && (( to_epoch >= daemon_prev_state_epoch )); then
  tail_delta=$((to_epoch - daemon_prev_state_epoch))
  daemon_current_state_age_seconds="$tail_delta"
  case "$daemon_prev_state" in
    WAIT_DIRTY_WORKTREE)
      daemon_wait_dirty_seconds=$((daemon_wait_dirty_seconds + tail_delta))
      ;;
    WAIT_USER_REPLY)
      daemon_wait_user_reply_seconds=$((daemon_wait_user_reply_seconds + tail_delta))
      ;;
    WAIT_REVIEW_FEEDBACK)
      daemon_wait_review_feedback_seconds=$((daemon_wait_review_feedback_seconds + tail_delta))
      ;;
    WAIT_DEPENDENCIES)
      daemon_wait_dependencies_seconds=$((daemon_wait_dependencies_seconds + tail_delta))
      ;;
    IDLE_NO_TASKS)
      daemon_idle_no_tasks_seconds=$((daemon_idle_no_tasks_seconds + tail_delta))
      ;;
  esac
fi
if (( daemon_prev_github_state_epoch > 0 && to_epoch >= daemon_prev_github_state_epoch )); then
  if (( daemon_prev_github_bad == 1 )); then
    daemon_github_status_unavail_seconds=$((daemon_github_status_unavail_seconds + to_epoch - daemon_prev_github_state_epoch))
  fi
fi

watchdog_heartbeat=0
watchdog_recovery_actions=0
if [[ -f "$WATCHDOG_LOG" ]]; then
  while IFS= read -r line; do
    [[ ${#line} -ge 20 ]] || continue
    ts="${line:0:20}"
    msg="${line:21}"
    in_range_ts "$ts" "$from_ts" "$to_ts" || continue
    [[ "$msg" == "watchdog_heartbeat" ]] && watchdog_heartbeat=$((watchdog_heartbeat + 1))
    if [[ "$msg" == WATCHDOG_ACTION=* ]] && [[ "$msg" != "WATCHDOG_ACTION=NONE" ]]; then
      watchdog_recovery_actions=$((watchdog_recovery_actions + 1))
    fi
  done < "$WATCHDOG_LOG"
fi

gql_events=0
gql_sum_requests=0
gql_sum_duration=0
gql_max_duration=0
gql_min_duration=-1
if [[ -f "$GQL_STATS_LOG" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    ts="${line%%$'\t'*}"
    in_range_ts "$ts" "$from_ts" "$to_ts" || continue
    [[ "$line" == *$'\tEVENT=RATE_LIMIT\t'* ]] || continue

    req=0
    dur=0
    IFS=$'\t' read -r -a gql_fields <<< "$line"
    for f in "${gql_fields[@]}"; do
      case "$f" in
        requests=*)
          req="${f#requests=}"
          ;;
        duration_sec=*)
          dur="${f#duration_sec=}"
          ;;
      esac
    done
    [[ "$req" =~ ^[0-9]+$ ]] || req=0
    [[ "$dur" =~ ^[0-9]+$ ]] || dur=0

    gql_events=$((gql_events + 1))
    gql_sum_requests=$((gql_sum_requests + req))
    gql_sum_duration=$((gql_sum_duration + dur))

    if (( dur > gql_max_duration )); then
      gql_max_duration=$dur
    fi
    if (( gql_min_duration < 0 || dur < gql_min_duration )); then
      gql_min_duration=$dur
    fi
  done < "$GQL_STATS_LOG"
fi

runtime_queue_pending=0
if [[ -f "$RUNTIME_QUEUE_FILE" ]]; then
  runtime_queue_pending="$(jq -r '(.items // []) | length' "$RUNTIME_QUEUE_FILE" 2>/dev/null || echo 0)"
  if ! [[ "$runtime_queue_pending" =~ ^[0-9]+$ ]]; then
    runtime_queue_pending=0
  fi
fi

daemon_state_now="$(cat "${CODEX_DIR}/daemon_state.txt" 2>/dev/null || echo "UNKNOWN")"
daemon_detail_now="$(cat "${CODEX_DIR}/daemon_state_detail.txt" 2>/dev/null || echo "")"
watchdog_state_now="$(cat "${CODEX_DIR}/watchdog_state.txt" 2>/dev/null || echo "UNKNOWN")"

echo "PLANKA Automation Log Summary"
echo "Period: ${from_ts} -> ${to_ts} ($(fmt_duration $((to_epoch - from_epoch))))"
echo
echo "Daemon"
echo "- Heartbeats: ${daemon_heartbeat}"
echo "- State changes: ${daemon_state_changes}"
echo "- WAIT_GITHUB_OFFLINE entries: ${daemon_wait_github_offline_entries}"
echo "- WAIT_GITHUB_RATE_LIMIT entries: ${daemon_wait_github_rate_entries}"
echo "- Estimated GitHub-unavailable time (state-based): $(fmt_duration "${daemon_wait_github_unavail_seconds}")"
echo "- GITHUB_STATUS DNS_OFFLINE entries: ${daemon_github_status_dns_entries}"
echo "- GITHUB_STATUS UNREACHABLE entries: ${daemon_github_status_unreachable_entries}"
echo "- GITHUB_STATUS UNSTABLE entries: ${daemon_github_status_unstable_entries}"
echo "- Estimated GitHub-unavailable time (detail-based): $(fmt_duration "${daemon_github_status_unavail_seconds}")"
echo "- WAIT_GITHUB_API_UNSTABLE markers: ${daemon_wait_api_unstable_markers}"
echo "- WAIT_GITHUB_RATE_LIMIT markers: ${daemon_wait_rate_limit_markers}"
echo "- Network error lines (api.github.com): ${daemon_net_errors}"
echo "- WAIT_DIRTY_WORKTREE entries: ${daemon_wait_dirty_entries} (blocking_todo=${daemon_wait_dirty_blocking_entries}, nonblocking=${daemon_wait_dirty_nonblocking_entries})"
echo "- Estimated WAIT_DIRTY_WORKTREE time: $(fmt_duration "${daemon_wait_dirty_seconds}")"
echo "- WAIT_USER_REPLY entries: ${daemon_wait_user_reply_entries}"
echo "- Estimated WAIT_USER_REPLY time: $(fmt_duration "${daemon_wait_user_reply_seconds}")"
echo "- WAIT_REVIEW_FEEDBACK entries: ${daemon_wait_review_feedback_entries}"
echo "- Estimated WAIT_REVIEW_FEEDBACK time: $(fmt_duration "${daemon_wait_review_feedback_seconds}")"
echo "- WAIT_DEPENDENCIES entries: ${daemon_wait_dependencies_entries}"
echo "- Estimated WAIT_DEPENDENCIES time: $(fmt_duration "${daemon_wait_dependencies_seconds}")"
echo "- Estimated IDLE_NO_TASKS time: $(fmt_duration "${daemon_idle_no_tasks_seconds}")"
echo
echo "Runtime Queue"
echo "- Enqueued actions: ${runtime_enqueued}"
echo "- Applied actions: ${runtime_applied}"
echo "- Wait-GitHub events: ${runtime_wait}"
echo "- Queue-done events: ${runtime_queue_done}"
echo "- Pending now: ${runtime_queue_pending}"
echo "- TG runtime wait signals: ${runtime_wait_tg}"
echo "- TG runtime recovered signals: ${runtime_recovered_tg}"
echo "- Estimated runtime wait time (TG-based): $(fmt_duration "${runtime_wait_total_seconds}")"
if (( runtime_wait_ongoing == 1 )); then
  echo "- Runtime wait: ongoing"
fi
echo
echo "GraphQL Rate Limit"
echo "- Events: ${gql_events}"
echo "- Avg requests/window: $(safe_avg "$gql_sum_requests" "$gql_events")"
echo "- Avg duration sec/window: $(safe_avg "$gql_sum_duration" "$gql_events")"
if (( gql_events > 0 )); then
  echo "- Min duration/window: ${gql_min_duration}s"
  echo "- Max duration/window: ${gql_max_duration}s"
fi
echo
echo "Watchdog"
echo "- Heartbeats: ${watchdog_heartbeat}"
echo "- Recovery action markers: ${watchdog_recovery_actions}"
echo
echo "Current State"
echo "- daemon_state: ${daemon_state_now}"
echo "- daemon_state_age: $(fmt_duration "${daemon_current_state_age_seconds}")"
echo "- daemon_state_detail: ${daemon_detail_now}"
echo "- watchdog_state: ${watchdog_state_now}"
