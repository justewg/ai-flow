#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
QUEUE_FILE="${CODEX_DIR}/project_status_runtime_queue.json"
QUEUE_MD_FILE="${CODEX_DIR}/project_status_runtime_queue.md"
mkdir -p "$STATE_TMP_DIR"

mkdir -p "$CODEX_DIR"

usage() {
  cat <<'EOF'
Usage:
  .flow/shared/scripts/project_status_runtime.sh enqueue <target> <status> [flow] [reason]
  .flow/shared/scripts/project_status_runtime.sh apply [max-per-run]
  .flow/shared/scripts/project_status_runtime.sh list
  .flow/shared/scripts/project_status_runtime.sh clear
EOF
}

sanitize_line() {
  local value="$1"
  printf '%s' "$value" | tr '\n' ' ' | tr '\t' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

is_retryable_github_error() {
  local text="$1"
  printf '%s' "$text" | grep -Eiq \
    'error connecting to api\.github\.com|could not resolve host: api\.github\.com|could not resolve host: github\.com|could not resolve hostname github\.com|temporary failure in name resolution|connection timed out|operation timed out|tls handshake timeout|failed to connect|api rate limit already exceeded|graphql_rate_limit|rate limit'
}

ensure_queue_file() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    printf '%s\n' '{"version":1,"items":[]}' > "$QUEUE_FILE"
  fi
  if ! jq -e '.items and (.items | type == "array")' "$QUEUE_FILE" >/dev/null 2>&1; then
    printf '%s\n' '{"version":1,"items":[]}' > "$QUEUE_FILE"
  fi
}

queue_count() {
  jq -r '(.items // []) | length' "$QUEUE_FILE" 2>/dev/null || echo 0
}

render_md() {
  local count
  count="$(queue_count)"
  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count == 0 )); then
    rm -f "$QUEUE_MD_FILE"
    return 0
  fi

  jq -r '
    "# Runtime Project-Status Queue\n"
    + "Pending actions: " + ((.items | length)|tostring) + "\n\n"
    + (.items | to_entries | map(
        "## " + ((.key + 1)|tostring) + ". " + .value.target + " -> " + .value.status + " / " + .value.flow + "\n"
        + "- reason: " + ((.value.reason // "")|tostring) + "\n"
        + "- created_at: " + ((.value.created_at // "")|tostring) + "\n"
        + "- attempts: " + ((.value.attempts // 0)|tostring) + "\n"
      ) | join("\n"))
  ' "$QUEUE_FILE" > "$QUEUE_MD_FILE" 2>/dev/null || true
}

queue_done_cleanup() {
  local count
  count="$(queue_count)"
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count == 0 )); then
    rm -f "$QUEUE_FILE" "$QUEUE_MD_FILE"
    echo "RUNTIME_PROJECT_STATUS_QUEUE_DONE=1"
  else
    render_md
    echo "RUNTIME_PROJECT_STATUS_REMAINING_COUNT=$count"
    echo "RUNTIME_PROJECT_STATUS_QUEUE_FILE=$QUEUE_FILE"
    echo "RUNTIME_PROJECT_STATUS_QUEUE_MD_FILE=$QUEUE_MD_FILE"
  fi
}

enqueue_action() {
  local target="$1"
  local status_name="$2"
  local flow_name="${3:-$status_name}"
  local reason="${4:-runtime-deferred}"
  local now_utc
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  ensure_queue_file

  tmp="$(mktemp "${STATE_TMP_DIR}/status_runtime.XXXXXX")"
  jq \
    --arg target "$target" \
    --arg status "$status_name" \
    --arg flow "$flow_name" \
    --arg reason "$reason" \
    --arg now "$now_utc" '
    .items = (
      (.items // [])
      | map(select((.target != $target) or (.status != $status) or (.flow != $flow)))
      + [{
          target: $target,
          status: $status,
          flow: $flow,
          reason: $reason,
          created_at: $now,
          updated_at: $now,
          attempts: 0,
          last_error: ""
        }]
    )
  ' "$QUEUE_FILE" > "$tmp"
  mv "$tmp" "$QUEUE_FILE"

  echo "RUNTIME_PROJECT_STATUS_ENQUEUED=1"
  echo "RUNTIME_PROJECT_STATUS_TARGET=$target"
  echo "RUNTIME_PROJECT_STATUS_STATUS=$status_name"
  echo "RUNTIME_PROJECT_STATUS_FLOW=$flow_name"
  echo "RUNTIME_PROJECT_STATUS_REASON=$(sanitize_line "$reason")"
  render_md
  echo "RUNTIME_PROJECT_STATUS_REMAINING_COUNT=$(queue_count)"
}

apply_queue() {
  local max_raw="${1:-5}"
  local max_per_run=5
  if [[ "$max_raw" =~ ^[0-9]+$ ]] && (( max_raw > 0 )); then
    max_per_run="$max_raw"
  fi

  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "RUNTIME_PROJECT_STATUS_QUEUE_ABSENT=1"
    exit 0
  fi
  ensure_queue_file

  local remaining
  remaining="$(queue_count)"
  if ! [[ "$remaining" =~ ^[0-9]+$ ]] || (( remaining == 0 )); then
    queue_done_cleanup
    exit 0
  fi

  local processed=0
  local pass_limit="$remaining"
  if (( pass_limit > max_per_run )); then
    pass_limit="$max_per_run"
  fi

  while (( processed < pass_limit )); do
    remaining="$(queue_count)"
    if ! [[ "$remaining" =~ ^[0-9]+$ ]] || (( remaining == 0 )); then
      break
    fi

    item_json="$(jq -c '.items[0]' "$QUEUE_FILE")"
    target="$(printf '%s' "$item_json" | jq -r '.target // ""')"
    status_name="$(printf '%s' "$item_json" | jq -r '.status // ""')"
    flow_name="$(printf '%s' "$item_json" | jq -r '.flow // ""')"
    reason="$(printf '%s' "$item_json" | jq -r '.reason // ""')"
    attempts="$(printf '%s' "$item_json" | jq -r '.attempts // 0')"
    [[ -z "$flow_name" ]] && flow_name="$status_name"

    if [[ -z "$target" || -z "$status_name" || -z "$flow_name" ]]; then
      tmp="$(mktemp "${STATE_TMP_DIR}/status_runtime.XXXXXX")"
      jq 'if (.items | length) > 0 then .items |= .[1:] else . end' "$QUEUE_FILE" > "$tmp"
      mv "$tmp" "$QUEUE_FILE"
      echo "RUNTIME_PROJECT_STATUS_DROPPED_INVALID=1"
      processed=$((processed + 1))
      continue
    fi

    if set_out="$("${CODEX_SHARED_SCRIPTS_DIR}/project_set_status.sh" "$target" "$status_name" "$flow_name" 2>&1)"; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done <<< "$set_out"
      tmp="$(mktemp "${STATE_TMP_DIR}/status_runtime.XXXXXX")"
      jq 'if (.items | length) > 0 then .items |= .[1:] else . end' "$QUEUE_FILE" > "$tmp"
      mv "$tmp" "$QUEUE_FILE"
      echo "RUNTIME_PROJECT_STATUS_APPLIED=1"
      echo "RUNTIME_PROJECT_STATUS_TARGET=$target"
      echo "RUNTIME_PROJECT_STATUS_STATUS=$status_name"
      echo "RUNTIME_PROJECT_STATUS_FLOW=$flow_name"
      echo "RUNTIME_PROJECT_STATUS_REASON=$(sanitize_line "$reason")"
      processed=$((processed + 1))
      continue
    fi

    rc=$?
    err_line="$(sanitize_line "$set_out")"
    if [[ "$rc" -eq 75 ]] || is_retryable_github_error "$set_out"; then
      echo "RUNTIME_PROJECT_STATUS_WAIT_GITHUB=1"
      echo "RUNTIME_PROJECT_STATUS_WAIT_TARGET=$target"
      echo "RUNTIME_PROJECT_STATUS_WAIT_STATUS=$status_name"
      echo "RUNTIME_PROJECT_STATUS_WAIT_FLOW=$flow_name"
      echo "RUNTIME_PROJECT_STATUS_WAIT_REASON=$(sanitize_line "$reason")"
      echo "RUNTIME_PROJECT_STATUS_WAIT_ERROR=$err_line"
      break
    fi

    now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if ! [[ "$attempts" =~ ^[0-9]+$ ]]; then
      attempts=0
    fi
    attempts=$((attempts + 1))

    tmp="$(mktemp "${STATE_TMP_DIR}/status_runtime.XXXXXX")"
    jq \
      --arg now "$now_utc" \
      --arg err "$err_line" \
      --argjson attempts "$attempts" '
      if (.items | length) > 0 then
        .items = ((.items[1:] + [(.items[0] + {updated_at:$now, attempts:$attempts, last_error:$err})]))
      else
        .
      end
    ' "$QUEUE_FILE" > "$tmp"
    mv "$tmp" "$QUEUE_FILE"

    echo "RUNTIME_PROJECT_STATUS_NONRETRYABLE_WARN=1"
    echo "RUNTIME_PROJECT_STATUS_WARN_TARGET=$target"
    echo "RUNTIME_PROJECT_STATUS_WARN_STATUS=$status_name"
    echo "RUNTIME_PROJECT_STATUS_WARN_FLOW=$flow_name"
    echo "RUNTIME_PROJECT_STATUS_WARN_ERROR=$err_line"
    processed=$((processed + 1))
  done

  queue_done_cleanup
}

cmd="${1:-}"
case "$cmd" in
  enqueue)
    if [[ $# -lt 3 || $# -gt 5 ]]; then
      usage
      exit 1
    fi
    enqueue_action "$2" "$3" "${4:-$3}" "${5:-runtime-deferred}"
    ;;
  apply)
    if [[ $# -gt 2 ]]; then
      usage
      exit 1
    fi
    apply_queue "${2:-5}"
    ;;
  list)
    if [[ ! -f "$QUEUE_FILE" ]]; then
      echo "RUNTIME_PROJECT_STATUS_QUEUE_ABSENT=1"
      exit 0
    fi
    cat "$QUEUE_FILE"
    ;;
  clear)
    rm -f "$QUEUE_FILE" "$QUEUE_MD_FILE"
    echo "RUNTIME_PROJECT_STATUS_QUEUE_CLEARED=1"
    ;;
  *)
    usage
    exit 1
    ;;
esac
