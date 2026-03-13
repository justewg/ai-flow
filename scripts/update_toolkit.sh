#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/update_toolkit.sh [--ref <name>]

Options:
  --ref <name>  Update .flow/shared to origin/<name> (default: main)
  --help        Show this help
EOF
}

target_ref="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --ref"
        exit 1
      fi
      target_ref="$2"
      shift 2
      ;;
    --help|-h)
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

toolkit_dir="$(codex_resolve_repo_flow_shared_dir)"
if [[ ! -d "${toolkit_dir}/.git" ]]; then
  echo "Toolkit submodule is not initialized: ${toolkit_dir}"
  exit 1
fi

before_head="$(git -C "$toolkit_dir" rev-parse HEAD)"
before_branch="$(git -C "$toolkit_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

git -C "$toolkit_dir" fetch origin

if git -C "$toolkit_dir" show-ref --verify --quiet "refs/remotes/origin/${target_ref}"; then
  if git -C "$toolkit_dir" show-ref --verify --quiet "refs/heads/${target_ref}"; then
    git -C "$toolkit_dir" checkout "$target_ref"
    git -C "$toolkit_dir" pull --ff-only origin "$target_ref"
  else
    git -C "$toolkit_dir" checkout -B "$target_ref" "origin/${target_ref}"
  fi
else
  git -C "$toolkit_dir" checkout "$target_ref"
fi

after_head="$(git -C "$toolkit_dir" rev-parse HEAD)"
after_branch="$(git -C "$toolkit_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

echo "TOOLKIT_DIR=$toolkit_dir"
echo "TOOLKIT_REF_REQUESTED=$target_ref"
echo "TOOLKIT_BEFORE_HEAD=$before_head"
echo "TOOLKIT_AFTER_HEAD=$after_head"
echo "TOOLKIT_BEFORE_BRANCH=${before_branch:-DETACHED}"
echo "TOOLKIT_AFTER_BRANCH=${after_branch:-DETACHED}"

if [[ "$before_head" == "$after_head" ]]; then
  echo "TOOLKIT_UPDATED=0"
else
  echo "TOOLKIT_UPDATED=1"
fi

if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$ROOT_DIR" diff --quiet -- .flow/shared; then
    echo "TOOLKIT_GITLINK_CHANGED=0"
  else
    echo "TOOLKIT_GITLINK_CHANGED=1"
    echo 'NEXT_STEP=git add .flow/shared && git commit -m "flow: bump ai-flow toolkit"'
  fi
fi
