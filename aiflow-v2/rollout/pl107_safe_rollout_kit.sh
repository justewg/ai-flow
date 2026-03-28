#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pl107_safe_rollout_kit.sh [--skip-git-sync]

Applies the AI Flow v2 SAFE rollout kit in the current repo checkout and writes
validation artifacts into aiflow-v2/rollout-reports/<timestamp>/.
EOF
}

skip_git_sync="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-git-sync)
      skip_git_sync="1"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
report_dir="${ROOT_DIR}/aiflow-v2/rollout-reports/${timestamp}"
mkdir -p "$report_dir"

run_and_capture() {
  local label="$1"
  shift 1
  {
    echo "# ${label}"
    echo "$ $*"
    "$@"
  } | tee "${report_dir}/${label}.log"
}

if [[ "$skip_git_sync" != "1" ]]; then
  run_and_capture git_fetch git fetch origin
  run_and_capture git_checkout git checkout development
  run_and_capture git_pull git pull --ff-only
  run_and_capture git_submodule_sync git submodule sync --recursive
  run_and_capture git_submodule_update git submodule update --init --recursive
fi

run_and_capture control_mode_set_safe \
  ./.flow/shared/scripts/run.sh control_mode set SAFE "aiflow-v2 PL-107 safe rollout validation"

run_and_capture runtime_v2_shadow_sync \
  ./.flow/shared/scripts/run.sh runtime_v2_shadow_sync

run_and_capture runtime_v2_inspect \
  ./.flow/shared/scripts/run.sh runtime_v2_inspect --compact

run_and_capture runtime_v2_validate_rollout \
  ./.flow/shared/scripts/run.sh runtime_v2_validate_rollout PL-104-TARGET 104 --compact

run_and_capture runtime_v2_single_task_loop \
  ./.flow/shared/scripts/run.sh runtime_v2_single_task_loop PL-105-TARGET 105 1055 --compact

run_and_capture status_snapshot \
  ./.flow/shared/scripts/run.sh status_snapshot

cat > "${report_dir}/SUMMARY.txt" <<EOF
SAFE rollout kit completed at ${timestamp}
Repo: ${ROOT_DIR}
Reports:
- control_mode_set_safe.log
- runtime_v2_shadow_sync.log
- runtime_v2_inspect.log
- runtime_v2_validate_rollout.log
- runtime_v2_single_task_loop.log
- status_snapshot.log
EOF

printf 'PL107_SAFE_ROLLOUT_REPORT_DIR=%s\n' "$report_dir"
