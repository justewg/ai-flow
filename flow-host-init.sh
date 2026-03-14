#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

toolkit_repo_url=""
toolkit_ref="main"
forwarded_args=()

usage() {
  cat <<'EOF'
Usage: flow-host-init.sh [options]

Linux-hosted flow runtime bootstrap entrypoint.
Designed for:

  bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-host-init.sh)

This launcher fetches ai-flow if needed and then runs:
  scripts/host_bootstrap.sh

Options:
  --toolkit-repo <url>         ai-flow repo URL. Default: current origin or https://github.com/justewg/ai-flow.git
  --toolkit-ref <ref>          ai-flow git ref. Default: main
  -h, --help                   Show help.

All other options are forwarded to host_bootstrap.sh.
EOF
}

local_toolkit_checkout() {
  if [[ -x "${SCRIPT_DIR}/scripts/host_bootstrap.sh" ]]; then
    printf '%s' "$SCRIPT_DIR"
    return 0
  fi
  return 1
}

resolve_local_origin() {
  local checkout_dir="$1"
  git -C "$checkout_dir" remote get-url origin 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --toolkit-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --toolkit-repo" >&2; exit 1; }
      toolkit_repo_url="$2"
      shift 2
      ;;
    --toolkit-ref)
      [[ $# -ge 2 ]] || { echo "Missing value for --toolkit-ref" >&2; exit 1; }
      toolkit_ref="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      forwarded_args+=("$1")
      shift
      ;;
  esac
done

bootstrap_checkout=""
cleanup_dir=""

if bootstrap_checkout="$(local_toolkit_checkout)"; then
  :
else
  if [[ -z "$toolkit_repo_url" ]]; then
    toolkit_repo_url="https://github.com/justewg/ai-flow.git"
  fi
  cleanup_dir="$(mktemp -d "${TMPDIR:-/tmp}/ai-flow-host-init.XXXXXX")"
  trap '[[ -n "${cleanup_dir:-}" ]] && rm -rf "${cleanup_dir}"' EXIT
  git clone --depth 1 --branch "$toolkit_ref" "$toolkit_repo_url" "$cleanup_dir" >/dev/null 2>&1
  bootstrap_checkout="$cleanup_dir"
fi

if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="$(resolve_local_origin "$bootstrap_checkout")"
fi
if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="https://github.com/justewg/ai-flow.git"
fi

"${bootstrap_checkout}/scripts/host_bootstrap.sh" \
  --toolkit-repo "$toolkit_repo_url" \
  --toolkit-ref "$toolkit_ref" \
  "${forwarded_args[@]}"
