#!/usr/bin/env bash

task_worktree_slug_from_title() {
  local title="${1:-}"
  local slug=""

  slug="$(printf '%s' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\[[^]]+\]//g; s/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"

  if [[ -z "$slug" ]]; then
    slug="task"
  fi

  printf '%s' "$slug"
}

task_worktree_key() {
  local task_id="$1"
  local issue_number="$2"
  local profile="${3:-${PROJECT_PROFILE:-default}}"
  printf '%s-%s-issue-%s' "$profile" "$task_id" "$issue_number"
}

task_worktree_root_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  [[ -n "$state_dir" ]] || state_dir="$(codex_resolve_state_dir)"
  printf '%s/task-worktrees/%s' "$state_dir" "$(task_worktree_key "$task_id" "$issue_number" "$profile")"
}

task_worktree_repo_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/repo' "$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_meta_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/meta' "$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_logs_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/logs' "$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_env_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/task.env' "$(task_worktree_meta_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_json_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/task.json' "$(task_worktree_meta_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_execution_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/execution' "$(task_worktree_meta_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_execution_profile_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/execution_profile.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_source_definition_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/source_definition.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_standardized_spec_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/standardized_task_spec.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_intake_profile_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/intake_profile.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_context_cache_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/context_cache.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_micro_prompt_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/micro_prompt_input.txt' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_canonical_diff_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/canonical_diff.patch' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_changed_files_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/changed_files.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_diff_summary_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/diff_summary.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_llm_calls_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/llm_calls.jsonl' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_execution_budget_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/execution_budget.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_noop_probe_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/noop_probe.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_check_results_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/check_results.json' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_failed_checks_file() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  printf '%s/failed_checks.txt' "$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile")"
}

task_worktree_branch_name() {
  local task_id="$1"
  local issue_number="$2"
  local title="${3:-}"
  local slug=""

  slug="$(task_worktree_slug_from_title "$title")"
  printf 'task/%s-issue-%s-%s' "$(printf '%s' "$task_id" | tr '[:upper:]' '[:lower:]')" "$issue_number" "$slug"
}

task_worktree_read_env_value() {
  local env_file="$1"
  local key="$2"
  [[ -f "$env_file" ]] || return 1
  grep -E "^${key}=" "$env_file" | tail -n1 | cut -d'=' -f2- || true
}

task_worktree_resolve_branch() {
  local task_id="$1"
  local issue_number="$2"
  local title="${3:-}"
  local state_dir="${4:-}"
  local profile="${5:-${PROJECT_PROFILE:-default}}"
  local env_file branch=""

  env_file="$(task_worktree_env_file "$task_id" "$issue_number" "$state_dir" "$profile")"
  branch="$(task_worktree_read_env_value "$env_file" "TASK_BRANCH" || true)"
  if [[ -n "$branch" ]]; then
    printf '%s' "$branch"
    return 0
  fi

  task_worktree_branch_name "$task_id" "$issue_number" "$title"
}

task_worktree_repo_present() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 1
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

task_worktree_head_commit() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 1
  task_worktree_repo_present "$repo_path" || return 1
  git -C "$repo_path" rev-parse HEAD 2>/dev/null
}

task_worktree_declares_toolkit_submodule() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 1
  [[ -f "$repo_path/.gitmodules" ]] || return 1

  git -C "$repo_path" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{print $2}' \
    | grep -Fxq '.flow/shared'
}

task_worktree_toolkit_ready() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 1
  [[ -f "$repo_path/.flow/shared/scripts/run.sh" ]]
}

task_worktree_reset_toolkit_submodule() {
  local repo_path="${1:-}"
  local git_dir=""
  local common_dir=""
  [[ -n "$repo_path" ]] || return 1
  task_worktree_repo_present "$repo_path" || return 1

  git_dir="$(git -C "$repo_path" rev-parse --git-dir 2>/dev/null || true)"
  common_dir="$(git -C "$repo_path" rev-parse --git-common-dir 2>/dev/null || true)"
  git -C "$repo_path" submodule deinit -f -- ".flow/shared" >/dev/null 2>&1 || true
  rm -rf "$repo_path/.flow/shared"
  if [[ -n "$git_dir" ]]; then
    rm -rf "${git_dir}/modules/.flow/shared"
  fi
  if [[ -n "$common_dir" ]]; then
    rm -rf "${common_dir}/modules/.flow/shared"
  fi
}

task_worktree_run_toolkit_update() {
  local repo_path="${1:-}"
  local err_file=""
  local rc=0
  [[ -n "$repo_path" ]] || return 1

  err_file="$(mktemp "${TMPDIR:-/tmp}/task_worktree_toolkit_update.XXXXXX")"
  git -C "$repo_path" submodule sync --recursive -- ".flow/shared" >/dev/null 2>&1 || true
  if git -C "$repo_path" submodule update --init --recursive -- ".flow/shared" >/dev/null 2>"$err_file"; then
    rm -f "$err_file"
    return 0
  fi

  rc=$?
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "TASK_WORKTREE_TOOLKIT_UPDATE_ERROR: $line" >&2
  done <"$err_file"
  rm -f "$err_file"
  return "$rc"
}

task_worktree_ensure_toolkit_materialized() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 1
  task_worktree_repo_present "$repo_path" || return 1

  if ! task_worktree_declares_toolkit_submodule "$repo_path"; then
    return 0
  fi

  if task_worktree_toolkit_ready "$repo_path"; then
    return 0
  fi

  if task_worktree_run_toolkit_update "$repo_path" && task_worktree_toolkit_ready "$repo_path"; then
    return 0
  fi

  echo "TASK_WORKTREE_TOOLKIT_REINIT=1" >&2
  task_worktree_reset_toolkit_submodule "$repo_path" || true

  task_worktree_run_toolkit_update "$repo_path" || return 1
  if task_worktree_toolkit_ready "$repo_path"; then
    return 0
  fi

  echo "TASK_WORKTREE_TOOLKIT_READY_MISSING=1" >&2
  return 1
}
