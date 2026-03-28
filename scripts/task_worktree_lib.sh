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

  git -C "$repo_path" submodule update --init --recursive -- ".flow/shared" >/dev/null 2>&1 || return 1
  task_worktree_toolkit_ready "$repo_path"
}
