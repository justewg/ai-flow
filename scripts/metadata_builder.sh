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
# shellcheck source=./micro_profile_lib.sh
source "${SCRIPT_DIR}/micro_profile_lib.sh"

CODEX_DIR="$(codex_export_state_dir)"
REPO="${GITHUB_REPO:-justewg/planka}"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
changed_files_file="$(task_worktree_changed_files_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
diff_summary_file="$(task_worktree_diff_summary_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
check_results_file="$(task_worktree_check_results_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

issue_json="$(micro_profile_issue_json "$issue_number" "$REPO" 2>/dev/null || jq -nc --arg n "$issue_number" '{title:"", body:"", number:$n}')"
issue_title="$(micro_profile_title_without_task_id "$(micro_profile_issue_title "$issue_json")")"
issue_title="$(micro_profile_trim "$issue_title")"
if [[ -z "$issue_title" ]]; then
  issue_title="Рабочая дельта"
fi

commit_message="${task_id}: ${issue_title}"
printf '%s\n' "$commit_message" > "${CODEX_DIR}/commit_message.txt"

if [[ -f "$changed_files_file" ]]; then
  jq -r '.[]' "$changed_files_file" > "${CODEX_DIR}/stage_paths.txt"
else
  : > "${CODEX_DIR}/stage_paths.txt"
fi

pr_title="${task_id} ${issue_title}"
printf '%s\n' "$pr_title" > "${CODEX_DIR}/pr_title.txt"

changed_paths_md="- (нет изменённых путей)"
if [[ -f "$changed_files_file" ]] && [[ "$(jq 'length' "$changed_files_file")" -gt 0 ]]; then
  changed_paths_md="$(jq -r '.[] | "- `" + . + "`"' "$changed_files_file")"
fi

check_results_md="- deterministic checks не запускались"
if [[ -f "$check_results_file" ]]; then
  check_results_md="$(jq -r '.results[]? | "- `" + .command + "` -> " + .status' "$check_results_file" 2>/dev/null || true)"
  [[ -n "$check_results_md" ]] || check_results_md="- deterministic checks не запускались"
fi

diff_stat=""
if [[ -f "$diff_summary_file" ]]; then
  diff_stat="$(jq -r '.diffStat // ""' "$diff_summary_file")"
fi

cat > "${CODEX_DIR}/pr_body.txt" <<EOF
## Что сделано
- Выполнена micro-task дельта по задаче ${task_id}.
- Изменения собраны deterministic micro-finalize path без LLM-generated finalize metadata.

## Изменённые файлы
${changed_paths_md}

## Проверки
${check_results_md}

## Diff summary
\`\`\`
${diff_stat}
\`\`\`

## Вне scope
- Дополнительные runtime/rollout/finalize изменения не вносились.
EOF

echo "METADATA_BUILDER_READY=1"
echo "COMMIT_MESSAGE_FILE=${CODEX_DIR}/commit_message.txt"
echo "STAGE_PATHS_FILE=${CODEX_DIR}/stage_paths.txt"
echo "PR_TITLE_FILE=${CODEX_DIR}/pr_title.txt"
echo "PR_BODY_FILE=${CODEX_DIR}/pr_body.txt"
