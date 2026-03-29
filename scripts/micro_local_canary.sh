#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> [label]"
  exit 1
fi

task_id="$1"
issue_number="$2"
label="${3:-micro-local-canary}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
# shellcheck source=./micro_profile_lib.sh
source "${SCRIPT_DIR}/micro_profile_lib.sh"
codex_load_flow_env

CODEX_DIR="$(codex_export_state_dir)"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
task_root="$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
execution_dir="$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
context_cache_file="$(task_worktree_context_cache_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
budget_file="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
llm_calls_file="$(task_worktree_llm_calls_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
check_results_file="$(task_worktree_check_results_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
diff_file="$(task_worktree_canonical_diff_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
summary_file="${execution_dir}/micro_local_canary_summary.json"
mock_bin_dir="${execution_dir}/mock-bin"
task_id_slug="$(printf '%s' "$task_id" | tr '[:upper:]' '[:lower:]')"
target_rel="docs/${task_id_slug}_micro_smoke.txt"
target_file="${task_repo}/${target_rel}"
mock_call_counter_file="${execution_dir}/mock-codex-call-count.txt"

rm -rf "$task_root"
mkdir -p "$task_repo" "$execution_dir" "$mock_bin_dir"

git -C "$ROOT_DIR" archive HEAD | tar -x -C "$task_repo"
mkdir -p "${task_repo}/.flow"
rm -rf "${task_repo}/.flow/shared"
mkdir -p "${task_repo}/.flow/shared"
cp -R "${ROOT_DIR}/.flow/shared/." "${task_repo}/.flow/shared/"
git -C "$task_repo" init >/dev/null 2>&1
git -C "$task_repo" add . >/dev/null 2>&1
git -C "$task_repo" commit -m "bootstrap ${label}" >/dev/null 2>&1 || true
git -C "$task_repo" checkout -b "task/${task_id_slug}-issue-${issue_number}-${label}" >/dev/null 2>&1 || git -C "$task_repo" checkout "task/${task_id_slug}-issue-${issue_number}-${label}" >/dev/null 2>&1
task_worktree_ensure_toolkit_materialized "$task_repo" >/dev/null 2>&1 || true

mkdir -p "$(dirname "$target_file")"
cat > "$target_file" <<EOF
Micro canary fixture for ${task_id}
EOF

cat > "${mock_bin_dir}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "issue" && "\${2:-}" == "view" ]]; then
  cat <<'JSON'
{"title":"[${task_id}] Обновить \`${target_rel}\` для local micro canary","body":"Контекст:\\nНужно проверить micro-profile на локальном synthetic run.\\n\\nЧто сделать:\\n- Обновить \`${target_rel}\`, добавив строку \`micro canary applied\`.\\n- Не трогать другие файлы.\\n\\nПроверки:\\n- rg -n \"micro canary applied\" ${target_rel}\\n- git diff --name-only -- ${target_rel}\\n\\nВне scope:\\n- любые другие изменения\\n","number":${issue_number}}
JSON
  exit 0
fi
echo "mock gh: unsupported command" >&2
exit 1
EOF
chmod +x "${mock_bin_dir}/gh"

cat > "${mock_bin_dir}/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
repo=""
response_file=""
call_counter_file="${mock_call_counter_file}"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -C)
      repo="\$2"
      shift 2
      ;;
    --output-last-message)
      response_file="\$2"
      shift 2
      ;;
    --dangerously-bypass-approvals-and-sandbox|--full-auto)
      shift 1
      ;;
    exec)
      shift 1
      ;;
    -)
      shift 1
      ;;
    *)
      shift 1
      ;;
  esac
done
while IFS= read -r _line; do
  :
done
call_count=0
if [[ -f "\$call_counter_file" ]]; then
  IFS= read -r call_count < "\$call_counter_file" || true
fi
call_count=\$((call_count + 1))
printf '%s\n' "\$call_count" > "\$call_counter_file"
if [[ -n "\$repo" ]]; then
  if [[ "${label}" == *repair* && "\$call_count" -eq 1 ]]; then
    printf 'micro canary staged\n' >> "\$repo/${target_rel}"
  else
    printf 'micro canary applied\n' >> "\$repo/${target_rel}"
  fi
fi
if [[ -n "\$response_file" ]]; then
  if [[ "${label}" == *repair* && "\$call_count" -eq 1 ]]; then
    printf '%s\n' 'Локальный repair-canary: внесена неполная правка для проверки второго вызова.' > "\$response_file"
  else
    printf '%s\n' 'Локальный micro canary выполнен. Изменён только целевой fixture-файл.' > "\$response_file"
  fi
fi
printf '%s\n' "tokens used"
if [[ "${label}" == *repair* && "\$call_count" -eq 1 ]]; then
  printf '%s\n' "2890"
else
  printf '%s\n' "3456"
fi
EOF
chmod +x "${mock_bin_dir}/codex"

ROOT_DIR="$task_repo" PATH="${mock_bin_dir}:${PATH}" /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/micro_task_classifier.sh" "$task_id" "$issue_number" "$profile_file" >/dev/null
micro_profile_budget_init_json "$task_id" "$issue_number" "${EXECUTOR_MICRO_MAX_TOTAL_TOKENS:-15000}" "0" > "$budget_file"

printf '%s\n' "$task_id" > "${CODEX_DIR}/project_task_id.txt"
printf '%s\n' "$task_id" > "${CODEX_DIR}/daemon_active_task.txt"
printf '%s\n' "$issue_number" > "${CODEX_DIR}/daemon_active_issue_number.txt"

ROOT_DIR="$ROOT_DIR" CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" PATH="${mock_bin_dir}:${PATH}" EXECUTOR_MICRO_SKIP_FINALIZE=1 EXECUTOR_CODEX_BYPASS_SANDBOX=1 \
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/executor_run.sh" "$task_id" "$issue_number"

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg taskRepo "$task_repo" \
  --arg targetFile "$target_rel" \
  --arg profileFile "$profile_file" \
  --arg contextCacheFile "$context_cache_file" \
  --arg budgetFile "$budget_file" \
  --arg llmCallsFile "$llm_calls_file" \
  --arg checkResultsFile "$check_results_file" \
  --arg canonicalDiffFile "$diff_file" \
  '{
    taskId:$taskId,
    issueNumber:$issueNumber,
    taskRepo:$taskRepo,
    targetFile:$targetFile,
    profileFile:$profileFile,
    contextCacheFile:$contextCacheFile,
    budgetFile:$budgetFile,
    llmCallsFile:$llmCallsFile,
    checkResultsFile:$checkResultsFile,
    canonicalDiffFile:$canonicalDiffFile
  }' > "$summary_file"

echo "MICRO_LOCAL_CANARY_READY=1"
echo "MICRO_LOCAL_CANARY_SUMMARY=${summary_file}"
