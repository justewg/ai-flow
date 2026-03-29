#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <task-id> <issue-number>"
  exit 1
fi

task_id="$1"
issue_number="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
execution_dir="$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
guard_bin_dir="${execution_dir}/guard-bin"
violations_file="${execution_dir}/blocked_commands.jsonl"

rm -rf "$guard_bin_dir"
mkdir -p "$guard_bin_dir"
: > "$violations_file"

for cmd in cat sed awk grep rg find git ls python python3; do
  real_cmd="$(command -v "$cmd" 2>/dev/null || true)"
  [[ -n "$real_cmd" ]] || continue
  cat > "${guard_bin_dir}/${cmd}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
MICRO_PROFILE_VIOLATIONS_FILE="${violations_file}" exec /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_command_guard.sh" "${cmd}" "${real_cmd}" "\$@"
EOF
  chmod +x "${guard_bin_dir}/${cmd}"
done

echo "MICRO_GUARD_BIN_READY=1"
echo "MICRO_GUARD_BIN_DIR=${guard_bin_dir}"
echo "MICRO_GUARD_VIOLATIONS_FILE=${violations_file}"
