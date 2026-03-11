#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
CODEX_DIR="$(codex_export_state_dir)"
OUTBOX_DIR="${CODEX_DIR}/outbox"
PAYLOAD_DIR="${CODEX_DIR}/outbox_payloads"
FAILED_DIR="${CODEX_DIR}/outbox_failed"

mkdir -p "$OUTBOX_DIR" "$PAYLOAD_DIR" "$FAILED_DIR"

usage() {
  cat <<'USAGE'
Usage:
  .flow/scripts/github_outbox.sh enqueue_issue_comment <repo> <issue-number> <body-file> [task-id] [kind] [set-waiting]
  .flow/scripts/github_outbox.sh flush
  .flow/scripts/github_outbox.sh count
  .flow/scripts/github_outbox.sh list
USAGE
}

pending_count() {
  find "$OUTBOX_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

cmd="${1:-}"
case "$cmd" in
  enqueue_issue_comment)
    if [[ $# -lt 5 || $# -gt 8 ]]; then
      usage
      exit 1
    fi

    repo="$2"
    issue_number="$3"
    body_file="$4"
    task_id="${5:-}"
    kind_label="${6:-QUESTION}"
    set_waiting="${7:-0}"

    if [[ ! -f "$body_file" ]]; then
      echo "Body file not found: $body_file"
      exit 1
    fi

    if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
      echo "Invalid issue number: $issue_number"
      exit 1
    fi

    if [[ "$set_waiting" != "0" && "$set_waiting" != "1" ]]; then
      echo "set-waiting must be 0 or 1"
      exit 1
    fi

    ts="$(date -u '+%Y%m%dT%H%M%SZ')"
    rand="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
    [[ -z "$rand" ]] && rand="$(date +%s)"

    item_id="${ts}_${issue_number}_${rand}"
    payload_copy="${PAYLOAD_DIR}/${item_id}.body"
    item_file="${OUTBOX_DIR}/${item_id}.json"

    cp "$body_file" "$payload_copy"

    jq -n \
      --arg action "issue_comment" \
      --arg repo "$repo" \
      --arg issue_number "$issue_number" \
      --arg payload_file "$payload_copy" \
      --arg task_id "$task_id" \
      --arg kind_label "$kind_label" \
      --arg set_waiting "$set_waiting" \
      --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{
        action: $action,
        repo: $repo,
        issue_number: ($issue_number | tonumber),
        payload_file: $payload_file,
        task_id: $task_id,
        kind_label: $kind_label,
        set_waiting: ($set_waiting == "1"),
        created_at: $created_at,
        attempts: 0
      }' > "$item_file"

    echo "OUTBOX_ENQUEUED=1"
    echo "GITHUB_ACTION_DEFERRED=issue_comment"
    echo "GITHUB_ACTION_TARGET=issue#${issue_number}"
    echo "OUTBOX_ITEM=$item_file"
    echo "OUTBOX_PENDING_COUNT=$(pending_count)"
    ;;

  flush)
    sent=0
    kept=0
    dropped=0

    shopt -s nullglob
    items=("$OUTBOX_DIR"/*.json)
    shopt -u nullglob

    if (( ${#items[@]} == 0 )); then
      echo "OUTBOX_EMPTY=1"
      echo "OUTBOX_PENDING_COUNT=0"
      exit 0
    fi

    for item_file in $(printf '%s\n' "${items[@]}" | sort); do
      [[ -f "$item_file" ]] || continue

      action="$(jq -r '.action // ""' "$item_file")"
      repo="$(jq -r '.repo // ""' "$item_file")"
      issue_number="$(jq -r '.issue_number // empty' "$item_file")"
      payload_file="$(jq -r '.payload_file // ""' "$item_file")"
      task_id="$(jq -r '.task_id // ""' "$item_file")"
      kind_label="$(jq -r '.kind_label // "QUESTION"' "$item_file")"
      set_waiting="$(jq -r '.set_waiting // false' "$item_file")"

      if [[ "$action" != "issue_comment" || -z "$repo" || -z "$issue_number" || -z "$payload_file" || ! -f "$payload_file" ]]; then
        echo "OUTBOX_DROPPED_INVALID_ITEM=$item_file"
        mv "$item_file" "${FAILED_DIR}/$(basename "$item_file")" 2>/dev/null || rm -f "$item_file"
        ((dropped++))
        continue
      fi

      body_text="$(<"$payload_file")"
      if [[ -z "$body_text" ]]; then
        echo "OUTBOX_DROPPED_EMPTY_BODY=$item_file"
        mv "$item_file" "${FAILED_DIR}/$(basename "$item_file")" 2>/dev/null || rm -f "$item_file"
        rm -f "$payload_file"
        ((dropped++))
        continue
      fi

      api_out=""
      err_file="$(mktemp "${CODEX_DIR}/outbox_gh_err.XXXXXX")"
      if api_out="$("${ROOT_DIR}/.flow/scripts/gh_retry.sh" gh api "repos/${repo}/issues/${issue_number}/comments" -f body="$body_text" 2>"$err_file")"; then
        if [[ -s "$err_file" ]]; then
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "$line"
          done < "$err_file"
        fi
        rm -f "$err_file"
        comment_id="$(printf '%s' "$api_out" | jq -r '.id // empty')"
        comment_url="$(printf '%s' "$api_out" | jq -r '.html_url // empty')"
        now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

        if [[ "$set_waiting" == "true" ]]; then
          printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_waiting_issue_number.txt"
          printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_waiting_task_id.txt"
          printf '%s\n' "$comment_id" > "${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
          printf '%s\n' "$kind_label" > "${CODEX_DIR}/daemon_waiting_kind.txt"
          printf '%s\n' "$now_utc" > "${CODEX_DIR}/daemon_waiting_since_utc.txt"
          printf '%s\n' "$comment_url" > "${CODEX_DIR}/daemon_waiting_comment_url.txt"
          : > "${CODEX_DIR}/daemon_waiting_pending_post.txt"
          echo "OUTBOX_WAITING_STATE_SET=1"
          echo "OUTBOX_WAITING_TASK_ID=$task_id"
          echo "OUTBOX_WAITING_ISSUE_NUMBER=$issue_number"
          echo "OUTBOX_WAITING_COMMENT_ID=$comment_id"
        fi

        rm -f "$item_file" "$payload_file"
        ((sent++))
        echo "GITHUB_ACTION_SENT=issue_comment"
        echo "GITHUB_ACTION_TARGET=issue#${issue_number}"
        echo "OUTBOX_SENT_ITEM=$issue_number"
      else
        rc=$?
        api_err="$(cat "$err_file" 2>/dev/null || true)"
        rm -f "$err_file"
        if [[ -n "$api_err" ]]; then
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "$line"
          done <<<"$api_err"
        fi
        if [[ "$rc" -eq 75 ]]; then
          attempts="$(jq -r '.attempts // 0' "$item_file")"
          if ! [[ "$attempts" =~ ^[0-9]+$ ]]; then
            attempts=0
          fi
          attempts=$((attempts + 1))
          tmp_item="$(mktemp "${CODEX_DIR}/outbox_item.XXXXXX")"
          jq --argjson attempts "$attempts" '.attempts = $attempts | .last_attempt_at = now | .last_error = "GITHUB_API_UNSTABLE"' "$item_file" > "$tmp_item"
          mv "$tmp_item" "$item_file"
          ((kept++))
          echo "GITHUB_ACTION_SEND_FAILED=issue_comment"
          echo "GITHUB_ACTION_FAIL_TARGET=issue#${issue_number}"
          echo "GITHUB_ACTION_FAIL_REASON=GITHUB_API_UNSTABLE"
          echo "OUTBOX_WAIT_GITHUB_API_UNSTABLE=1"
          echo "OUTBOX_PENDING_COUNT=$(pending_count)"
          echo "WAIT_GITHUB_PENDING_ACTIONS=$(pending_count)"
          echo "OUTBOX_LAST_ITEM=$item_file"
          break
        fi

        echo "OUTBOX_DROPPED_NONRETRYABLE=$item_file"
        echo "GITHUB_ACTION_SEND_FAILED=issue_comment"
        echo "GITHUB_ACTION_FAIL_TARGET=issue#${issue_number}"
        echo "GITHUB_ACTION_FAIL_REASON=NONRETRYABLE"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "OUTBOX_ERROR(rc=$rc): $line"
        done <<<"$api_out"
        mv "$item_file" "${FAILED_DIR}/$(basename "$item_file")" 2>/dev/null || rm -f "$item_file"
        mv "$payload_file" "${FAILED_DIR}/$(basename "$payload_file")" 2>/dev/null || rm -f "$payload_file"
        ((dropped++))
      fi
    done

    echo "OUTBOX_FLUSH_SENT=$sent"
    echo "OUTBOX_FLUSH_KEPT=$kept"
    echo "OUTBOX_FLUSH_DROPPED=$dropped"
    echo "OUTBOX_PENDING_COUNT=$(pending_count)"
    ;;

  count)
    echo "OUTBOX_PENDING_COUNT=$(pending_count)"
    ;;

  list)
    find "$OUTBOX_DIR" -maxdepth 1 -type f -name '*.json' -print | sort
    ;;

  *)
    usage
    exit 1
    ;;
esac
