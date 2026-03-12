#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
CODEX_DIR="$(codex_export_state_dir)"
RUNNER_INPUT_DIR="${CODEX_RUNNER_INPUT_DIR:-$(codex_resolve_flow_tmp_dir)/run}"

mkdir -p "${CODEX_DIR}"
mkdir -p "${RUNNER_INPUT_DIR}"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/run.sh <command>

Commands:
  help
  clear
  write
  append
  copy
  dispatch
  issue_create
  issue_view
  issue_close
  sync_branches
  pr_list
  pr_list_open
  pr_view
  pr_create
  pr_edit
  pr_merge
  commit_push
  git_ls_remote_heads
  git_delete_branch
  project_add_task
  project_add_issue
  project_set_status
  project_status_runtime
  log_summary
  log_tail_executor
  log_tail_daemon_executor
  log_tail_all
  status_snapshot
  next_task
  app_deps_mermaid
  backlog_seed_apply
  onboarding_audit
  create_migration_kit
  apply_migration_kit
  profile_init
  daemon_tick
  daemon_loop
  daemon_install
  daemon_uninstall
  daemon_status
  watchdog_tick
  watchdog_loop
  watchdog_install
  watchdog_uninstall
  watchdog_status
  executor_reset
  runtime_clear_active
  runtime_clear_waiting
  runtime_clear_review
  executor_start
  executor_tick
  executor_build_prompt
  task_ask
  daemon_check_replies
  task_finalize
  gh_retry
  github_health_check
  github_outbox
  gh_app_auth_start
  gh_app_auth_health
  gh_app_auth_probe
  gh_app_auth_token
  gh_app_auth_pm2_start
  gh_app_auth_pm2_stop
  gh_app_auth_pm2_restart
  gh_app_auth_pm2_status
  gh_app_auth_pm2_health
  gh_app_auth_pm2_crash_test
  ops_bot_start
  ops_bot_health
  ops_bot_post_smoke_check
  ops_bot_pm2_start
  ops_bot_pm2_stop
  ops_bot_pm2_restart
  ops_bot_pm2_status
  ops_bot_pm2_health
  ops_bot_webhook_register
  ops_bot_webhook_refresh
  ops_remote_status_push
  ops_remote_summary_push
  issue_285_reframe_apply

Fixed input files in state dir
(`CODEX_STATE_DIR` or `FLOW_STATE_DIR`, default `.flow/state/codex/default`):
  pr_number.txt
  pr_title.txt
  pr_body.txt
  commit_message.txt
  stage_paths.txt
  issue_number.txt
  issue_title.txt
  issue_body.txt
  issue_view_json.txt
  issue_view_jq.txt
  issue_close_reason.txt
  issue_close_comment.txt
  pr_state.txt
  pr_base.txt
  pr_head.txt
  pr_list_json.txt
  pr_list_jq.txt
  pr_merge_method.txt
  pr_delete_branch.txt
  git_remote.txt
  git_refs.txt
  branch_name.txt
  project_task_id.txt
  project_status.txt
  project_flow.txt (optional; defaults to project_status.txt)
  project_new_task_id.txt
  project_new_title.txt
  project_new_scope.txt
  project_new_priority.txt
  project_new_status.txt (optional; defaults to Backlog)
  project_new_flow.txt (optional; defaults to Backlog)

Repo-local dispatch input files
(`CODEX_RUNNER_INPUT_DIR`, default `.flow/tmp/run`):
  dispatch_command.txt
  dispatch_args.txt (optional; one argument per line)
EOF
}

read_required_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing file: $file_path"
    exit 1
  fi
  local content
  content="$(<"$file_path")"
  if [[ -z "$content" ]]; then
    echo "Empty file: $file_path"
    exit 1
  fi
  printf '%s' "$content"
}

read_optional_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    cat "$file_path"
  fi
}

read_lines_file_into_array() {
  local file_path="$1"
  local array_name="$2"
  local line escaped_line
  eval "$array_name=()"
  if [[ ! -f "$file_path" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    escaped_line="${line//\\/\\\\}"
    escaped_line="${escaped_line//\"/\\\"}"
    eval "$array_name+=(\"$escaped_line\")"
  done < "$file_path"
}

is_truthy() {
  local raw_value="${1:-}"
  local value
  value="$(printf '%s' "$raw_value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_flow_repo() {
  codex_resolve_flow_config
  if [[ -z "${FLOW_GITHUB_REPO:-}" ]]; then
    echo "FLOW_GITHUB_REPO is not configured"
    exit 1
  fi
  printf '%s' "$FLOW_GITHUB_REPO"
}

write_temp_body_file() {
  local source_file="$1"
  local tmp_file
  tmp_file="$(mktemp "${RUNNER_INPUT_DIR}/body.XXXXXX.md")"
  cp "$source_file" "$tmp_file"
  printf '%s' "$tmp_file"
}

tail_runtime_log() {
  local log_name="$1"
  local lines="$2"
  local log_dir log_file
  log_dir="$(codex_resolve_flow_runtime_log_dir)"
  log_file="${log_dir}/${log_name}"
  if [[ ! -f "$log_file" ]]; then
    echo "Log file not found: $log_file"
    exit 1
  fi
  tail -n "$lines" "$log_file"
}

clear_runtime_state_file() {
  local file_name="$1"
  : > "${CODEX_DIR}/${file_name}"
}

key_to_file() {
  local key="$1"
  case "$key" in
    pr_number) echo "${CODEX_DIR}/pr_number.txt" ;;
    pr_title) echo "${CODEX_DIR}/pr_title.txt" ;;
    pr_body) echo "${CODEX_DIR}/pr_body.txt" ;;
    commit_message) echo "${CODEX_DIR}/commit_message.txt" ;;
    stage_paths) echo "${CODEX_DIR}/stage_paths.txt" ;;
    issue_number) echo "${CODEX_DIR}/issue_number.txt" ;;
    issue_title) echo "${CODEX_DIR}/issue_title.txt" ;;
    issue_body) echo "${CODEX_DIR}/issue_body.txt" ;;
    issue_view_json) echo "${CODEX_DIR}/issue_view_json.txt" ;;
    issue_view_jq) echo "${CODEX_DIR}/issue_view_jq.txt" ;;
    issue_close_reason) echo "${CODEX_DIR}/issue_close_reason.txt" ;;
    issue_close_comment) echo "${CODEX_DIR}/issue_close_comment.txt" ;;
    pr_state) echo "${CODEX_DIR}/pr_state.txt" ;;
    pr_base) echo "${CODEX_DIR}/pr_base.txt" ;;
    pr_head) echo "${CODEX_DIR}/pr_head.txt" ;;
    pr_list_json) echo "${CODEX_DIR}/pr_list_json.txt" ;;
    pr_list_jq) echo "${CODEX_DIR}/pr_list_jq.txt" ;;
    pr_merge_method) echo "${CODEX_DIR}/pr_merge_method.txt" ;;
    pr_delete_branch) echo "${CODEX_DIR}/pr_delete_branch.txt" ;;
    git_remote) echo "${CODEX_DIR}/git_remote.txt" ;;
    git_refs) echo "${CODEX_DIR}/git_refs.txt" ;;
    branch_name) echo "${CODEX_DIR}/branch_name.txt" ;;
    project_task_id) echo "${CODEX_DIR}/project_task_id.txt" ;;
    project_status) echo "${CODEX_DIR}/project_status.txt" ;;
    project_flow) echo "${CODEX_DIR}/project_flow.txt" ;;
    project_new_task_id) echo "${CODEX_DIR}/project_new_task_id.txt" ;;
    project_new_title) echo "${CODEX_DIR}/project_new_title.txt" ;;
    project_new_scope) echo "${CODEX_DIR}/project_new_scope.txt" ;;
    project_new_priority) echo "${CODEX_DIR}/project_new_priority.txt" ;;
    project_new_status) echo "${CODEX_DIR}/project_new_status.txt" ;;
    project_new_flow) echo "${CODEX_DIR}/project_new_flow.txt" ;;
    dispatch_command) echo "${RUNNER_INPUT_DIR}/dispatch_command.txt" ;;
    dispatch_args) echo "${RUNNER_INPUT_DIR}/dispatch_args.txt" ;;
    *)
      echo "Unknown key: $key"
      exit 1
      ;;
  esac
}

cmd="${1:-help}"

case "$cmd" in
  help)
    usage
    ;;

  clear)
    if [[ $# -ne 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh clear <key>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    : > "$file_path"
    ;;

  write)
    if [[ $# -lt 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh write <key> <value...>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    shift 2
    # Interpret escaped sequences (for example: \n -> newline) for PR bodies.
    printf '%b\n' "$*" > "$file_path"
    ;;

  append)
    if [[ $# -lt 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh append <key> <value...>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    shift 2
    # Interpret escaped sequences (for example: \n -> newline) for multiline payloads.
    printf '%b\n' "$*" >> "$file_path"
    ;;

  copy)
    if [[ $# -ne 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh copy <key> <source-file>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    source_file="$3"
    if [[ ! -f "$source_file" ]]; then
      echo "Source file not found: $source_file"
      exit 1
    fi
    cp "$source_file" "$file_path"
    ;;

  dispatch)
    dispatch_cmd="${2:-}"
    if [[ -z "$dispatch_cmd" ]]; then
      dispatch_cmd="$(read_required_file "$(key_to_file "dispatch_command")")"
    fi
    if [[ "$dispatch_cmd" == "dispatch" ]]; then
      echo "Refusing recursive dispatch"
      exit 1
    fi
    dispatch_args=()
    read_lines_file_into_array "$(key_to_file "dispatch_args")" dispatch_args
    exec "$0" "$dispatch_cmd" "${dispatch_args[@]}"
    ;;

  issue_create)
    repo="$(require_flow_repo)"
    issue_title="$(read_required_file "${CODEX_DIR}/issue_title.txt")"
    issue_body_file="$(key_to_file "issue_body")"
    if [[ ! -f "$issue_body_file" ]]; then
      echo "Missing file: $issue_body_file"
      exit 1
    fi
    tmp_body_file="$(write_temp_body_file "$issue_body_file")"
    trap 'rm -f "$tmp_body_file"' EXIT
    gh issue create --repo "$repo" --title "$issue_title" --body-file "$tmp_body_file"
    ;;

  issue_view)
    repo="$(require_flow_repo)"
    issue_number="$(read_required_file "${CODEX_DIR}/issue_number.txt")"
    issue_view_json="$(read_optional_file "$(key_to_file "issue_view_json")")"
    issue_view_jq="$(read_optional_file "$(key_to_file "issue_view_jq")")"
    if [[ -n "$issue_view_json" ]]; then
      if [[ -n "$issue_view_jq" ]]; then
        gh issue view "$issue_number" --repo "$repo" --json "$issue_view_json" --jq "$issue_view_jq"
      else
        gh issue view "$issue_number" --repo "$repo" --json "$issue_view_json"
      fi
    else
      gh issue view "$issue_number" --repo "$repo"
    fi
    ;;

  issue_close)
    repo="$(require_flow_repo)"
    issue_number="$(read_required_file "${CODEX_DIR}/issue_number.txt")"
    issue_close_reason="$(read_optional_file "$(key_to_file "issue_close_reason")")"
    issue_close_comment="$(read_optional_file "$(key_to_file "issue_close_comment")")"
    issue_cmd=(gh issue close "$issue_number" --repo "$repo")
    [[ -n "$issue_close_reason" ]] && issue_cmd+=(--reason "$issue_close_reason")
    if [[ -n "$issue_close_comment" ]]; then
      issue_cmd+=(--comment "$issue_close_comment")
    fi
    "${issue_cmd[@]}"
    ;;

  sync_branches)
    "${CODEX_SHARED_SCRIPTS_DIR}/sync_branches.sh"
    ;;

  pr_list)
    repo="$(require_flow_repo)"
    pr_state="$(read_optional_file "$(key_to_file "pr_state")")"
    pr_base="$(read_optional_file "$(key_to_file "pr_base")")"
    pr_head="$(read_optional_file "$(key_to_file "pr_head")")"
    pr_list_json="$(read_optional_file "$(key_to_file "pr_list_json")")"
    pr_list_jq="$(read_optional_file "$(key_to_file "pr_list_jq")")"
    pr_cmd=(gh pr list --repo "$repo")
    [[ -n "$pr_state" ]] && pr_cmd+=(--state "$pr_state")
    [[ -n "$pr_base" ]] && pr_cmd+=(--base "$pr_base")
    [[ -n "$pr_head" ]] && pr_cmd+=(--head "$pr_head")
    [[ -n "$pr_list_json" ]] && pr_cmd+=(--json "$pr_list_json")
    [[ -n "$pr_list_jq" ]] && pr_cmd+=(--jq "$pr_list_jq")
    "${pr_cmd[@]}"
    ;;

  pr_list_open)
    "${CODEX_SHARED_SCRIPTS_DIR}/pr_list_open.sh"
    ;;

  pr_view)
    pr_number="$(read_required_file "${CODEX_DIR}/pr_number.txt")"
    "${CODEX_SHARED_SCRIPTS_DIR}/pr_view.sh" "$pr_number"
    ;;

  pr_create)
    "${CODEX_SHARED_SCRIPTS_DIR}/pr_create.sh" \
      "${CODEX_DIR}/pr_title.txt" \
      "${CODEX_DIR}/pr_body.txt"
    ;;

  pr_edit)
    pr_number="$(read_required_file "${CODEX_DIR}/pr_number.txt")"
    "${CODEX_SHARED_SCRIPTS_DIR}/pr_edit.sh" \
      "$pr_number" \
      "${CODEX_DIR}/pr_title.txt" \
      "${CODEX_DIR}/pr_body.txt"
    ;;

  pr_merge)
    repo="$(require_flow_repo)"
    pr_number="$(read_required_file "${CODEX_DIR}/pr_number.txt")"
    pr_merge_method="$(read_optional_file "$(key_to_file "pr_merge_method")")"
    pr_delete_branch_raw="$(read_optional_file "$(key_to_file "pr_delete_branch")")"
    pr_merge_cmd=(gh pr merge "$pr_number" --repo "$repo")
    case "${pr_merge_method:-merge}" in
      ""|merge)
        pr_merge_cmd+=(--merge)
        ;;
      squash)
        pr_merge_cmd+=(--squash)
        ;;
      rebase)
        pr_merge_cmd+=(--rebase)
        ;;
      *)
        echo "Unsupported pr_merge_method: ${pr_merge_method}"
        exit 1
        ;;
    esac
    if is_truthy "${pr_delete_branch_raw:-0}"; then
      pr_merge_cmd+=(--delete-branch)
    fi
    "${pr_merge_cmd[@]}"
    ;;

  commit_push)
    commit_message="$(read_required_file "${CODEX_DIR}/commit_message.txt")"
    stage_paths=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      stage_paths+=("$line")
    done < "${CODEX_DIR}/stage_paths.txt"
    if [[ ${#stage_paths[@]} -eq 0 ]]; then
      echo "Missing or empty file: ${CODEX_DIR}/stage_paths.txt"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/dev_commit_push.sh" "$commit_message" "${stage_paths[@]}"
    ;;

  git_ls_remote_heads)
    git_remote="$(read_optional_file "$(key_to_file "git_remote")")"
    [[ -z "$git_remote" ]] && git_remote="origin"
    git_refs=()
    read_lines_file_into_array "$(key_to_file "git_refs")" git_refs
    git ls-remote --heads "$git_remote" "${git_refs[@]}"
    ;;

  git_delete_branch)
    branch_name="$(read_required_file "$(key_to_file "branch_name")")"
    git branch -D "$branch_name"
    ;;

  project_add_task)
    new_task_id="$(read_required_file "${CODEX_DIR}/project_new_task_id.txt")"
    new_scope="$(read_required_file "${CODEX_DIR}/project_new_scope.txt")"
    new_priority="$(read_required_file "${CODEX_DIR}/project_new_priority.txt")"
    new_status="Backlog"
    new_flow="Backlog"
    [[ -f "${CODEX_DIR}/project_new_status.txt" ]] && new_status="$(read_required_file "${CODEX_DIR}/project_new_status.txt")"
    [[ -f "${CODEX_DIR}/project_new_flow.txt" ]] && new_flow="$(read_required_file "${CODEX_DIR}/project_new_flow.txt")"
    "${CODEX_SHARED_SCRIPTS_DIR}/project_add_task.sh" \
      "$new_task_id" \
      "${CODEX_DIR}/project_new_title.txt" \
      "$new_scope" \
      "$new_priority" \
      "$new_status" \
      "$new_flow"
    ;;

  project_add_issue)
    repo="$(require_flow_repo)"
    codex_resolve_project_config
    issue_number="$(read_required_file "${CODEX_DIR}/issue_number.txt")"
    issue_url="https://github.com/${repo}/issues/${issue_number}"
    gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$issue_url"
    ;;

  project_set_status)
    task_id="$(read_required_file "${CODEX_DIR}/project_task_id.txt")"
    status_name="$(read_required_file "${CODEX_DIR}/project_status.txt")"
    flow_file="${CODEX_DIR}/project_flow.txt"
    if [[ -f "$flow_file" ]]; then
      flow_name="$(read_required_file "$flow_file")"
      "${CODEX_SHARED_SCRIPTS_DIR}/project_set_status.sh" "$task_id" "$status_name" "$flow_name"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/project_set_status.sh" "$task_id" "$status_name"
    fi
    ;;

  project_status_runtime)
    if [[ $# -lt 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh project_status_runtime <enqueue|apply|list|clear> [args...]"
      exit 1
    fi
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/project_status_runtime.sh" "$@"
    ;;

  log_summary)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/log_summary.sh" "$@"
    ;;

  log_tail_executor)
    tail_runtime_log "executor.log" "140"
    ;;

  log_tail_daemon_executor)
    printf '=== daemon tail ===\n'
    tail_runtime_log "daemon.log" "80"
    printf '\n=== executor tail ===\n'
    tail_runtime_log "executor.log" "120"
    ;;

  log_tail_all)
    printf '=== daemon tail ===\n'
    tail_runtime_log "daemon.log" "80"
    printf '\n=== watchdog tail ===\n'
    tail_runtime_log "watchdog.log" "80"
    printf '\n=== executor tail ===\n'
    tail_runtime_log "executor.log" "120"
    ;;

  status_snapshot)
    "${CODEX_SHARED_SCRIPTS_DIR}/status_snapshot.sh"
    ;;

  next_task)
    "${CODEX_SHARED_SCRIPTS_DIR}/next_task.sh"
    ;;

  app_deps_mermaid)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/generate_app_dependencies_mermaid.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/generate_app_dependencies_mermaid.sh"
    fi
    ;;

  backlog_seed_apply)
    "${CODEX_SHARED_SCRIPTS_DIR}/backlog_seed_apply.sh"
    ;;

  onboarding_audit)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/onboarding_audit.sh" "$@"
    ;;

  create_migration_kit)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/create_migration_kit.sh" "$@"
    ;;

  apply_migration_kit)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/apply_migration_kit.sh" "$@"
    ;;

  profile_init)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/profile_init.sh" "$@"
    ;;

  daemon_tick)
    "${CODEX_SHARED_SCRIPTS_DIR}/daemon_tick.sh"
    ;;

  daemon_loop)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_loop.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_loop.sh"
    fi
    ;;

  daemon_install)
    if [[ $# -ge 3 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_install.sh" "$2" "$3"
    elif [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_install.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_install.sh"
    fi
    ;;

  daemon_uninstall)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_uninstall.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_uninstall.sh"
    fi
    ;;

  daemon_status)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_status.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/daemon_status.sh"
    fi
    ;;

  watchdog_tick)
    "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_tick.sh"
    ;;

  watchdog_loop)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_loop.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_loop.sh"
    fi
    ;;

  watchdog_install)
    if [[ $# -ge 3 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_install.sh" "$2" "$3"
    elif [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_install.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_install.sh"
    fi
    ;;

  watchdog_uninstall)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_uninstall.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_uninstall.sh"
    fi
    ;;

  watchdog_status)
    if [[ $# -ge 2 ]]; then
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_status.sh" "$2"
    else
      "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_status.sh"
    fi
    ;;

  executor_reset)
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_reset.sh"
    ;;

  runtime_clear_active)
    clear_runtime_state_file "daemon_active_task.txt"
    clear_runtime_state_file "daemon_active_item_id.txt"
    clear_runtime_state_file "daemon_active_issue_number.txt"
    ;;

  runtime_clear_waiting)
    clear_runtime_state_file "daemon_waiting_task_id.txt"
    clear_runtime_state_file "daemon_waiting_issue_number.txt"
    clear_runtime_state_file "daemon_waiting_kind.txt"
    clear_runtime_state_file "daemon_waiting_since_utc.txt"
    clear_runtime_state_file "daemon_waiting_comment_url.txt"
    clear_runtime_state_file "daemon_waiting_pending_post.txt"
    clear_runtime_state_file "daemon_waiting_question_comment_id.txt"
    ;;

  runtime_clear_review)
    clear_runtime_state_file "daemon_review_task_id.txt"
    clear_runtime_state_file "daemon_review_item_id.txt"
    clear_runtime_state_file "daemon_review_issue_number.txt"
    clear_runtime_state_file "daemon_review_pr_number.txt"
    clear_runtime_state_file "daemon_review_branch_name.txt"
    ;;

  executor_start)
    if [[ $# -ne 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh executor_start <task-id> <issue-number>"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_start.sh" "$2" "$3"
    ;;

  executor_tick)
    if [[ $# -ne 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh executor_tick <task-id> <issue-number>"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_tick.sh" "$2" "$3"
    ;;

  executor_build_prompt)
    if [[ $# -ne 4 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh executor_build_prompt <task-id> <issue-number> <output-file>"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/executor_build_prompt.sh" "$2" "$3" "$4"
    ;;

  task_ask)
    if [[ $# -ne 3 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh task_ask <question|blocker> <message-file>"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/task_ask.sh" "$2" "$3"
    ;;

  daemon_check_replies)
    "${CODEX_SHARED_SCRIPTS_DIR}/daemon_check_replies.sh"
    ;;

  task_finalize)
    "${CODEX_SHARED_SCRIPTS_DIR}/task_finalize.sh"
    ;;

  gh_retry)
    if [[ $# -lt 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh gh_retry <command> [args...]"
      exit 1
    fi
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" "$@"
    ;;

  github_health_check)
    "${CODEX_SHARED_SCRIPTS_DIR}/github_health_check.sh"
    ;;

  github_outbox)
    if [[ $# -lt 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh github_outbox <enqueue_issue_comment|flush|count|list> [args...]"
      exit 1
    fi
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" "$@"
    ;;

  gh_app_auth_start)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_start.sh"
    ;;

  gh_app_auth_health)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_health.sh"
    ;;

  gh_app_auth_probe)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_probe.sh"
    ;;

  gh_app_auth_token)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_token.sh"
    ;;

  gh_app_auth_pm2_start)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_start.sh"
    ;;

  gh_app_auth_pm2_stop)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_stop.sh"
    ;;

  gh_app_auth_pm2_restart)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_restart.sh"
    ;;

  gh_app_auth_pm2_status)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_status.sh"
    ;;

  gh_app_auth_pm2_health)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_health.sh"
    ;;

  gh_app_auth_pm2_crash_test)
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_app_auth_pm2_crash_test.sh"
    ;;

  ops_bot_start)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_start.sh"
    ;;

  ops_bot_health)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_health.sh"
    ;;

  ops_bot_post_smoke_check)
    shift 1
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_post_smoke_check.sh" "$@"
    ;;

  ops_bot_pm2_start)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_start.sh"
    ;;

  ops_bot_pm2_stop)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_stop.sh"
    ;;

  ops_bot_pm2_restart)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_restart.sh"
    ;;

  ops_bot_pm2_status)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_status.sh"
    ;;

  ops_bot_pm2_health)
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_pm2_health.sh"
    ;;

  ops_bot_webhook_register)
    if [[ $# -gt 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh ops_bot_webhook_register [register|refresh|delete|info]"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_webhook_register.sh" "${2:-register}"
    ;;

  ops_bot_webhook_refresh)
    if [[ $# -ne 1 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh ops_bot_webhook_refresh"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_webhook_refresh.sh"
    ;;

  ops_remote_status_push)
    if [[ $# -ne 1 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh ops_remote_status_push"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_remote_status_push.sh"
    ;;

  ops_remote_summary_push)
    if [[ $# -ne 1 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh ops_remote_summary_push"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/ops_remote_summary_push.sh"
    ;;

  issue_285_reframe_apply)
    if [[ $# -gt 2 ]]; then
      echo "Usage: .flow/shared/scripts/run.sh issue_285_reframe_apply [manual-issue-number]"
      exit 1
    fi
    "${CODEX_SHARED_SCRIPTS_DIR}/issue_285_reframe_apply.sh" "${2:-285}"
    ;;

  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
