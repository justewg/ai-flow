#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

toolkit_repo_url=""
toolkit_ref="main"
forwarded_args=()

usage() {
  cat <<'EOF'
Usage: flow-docker-init.sh [options]

Docker-hosted flow runtime bootstrap entrypoint.
Designed for:

  bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-docker-init.sh)

This launcher fetches ai-flow if needed and then runs:
  scripts/docker_bootstrap.sh

Options:
  --toolkit-repo <url>         ai-flow repo URL. Default: current origin or https://github.com/justewg/ai-flow.git
  --toolkit-ref <ref>          ai-flow git ref. Default: main
  -h, --help                   Show help.

All other options are forwarded to docker_bootstrap.sh.
EOF
}

local_toolkit_checkout() {
  if [[ -x "${SCRIPT_DIR}/scripts/docker_bootstrap.sh" ]]; then
    printf '%s' "$SCRIPT_DIR"
    return 0
  fi
  return 1
}

preferred_github_git_protocol() {
  if [[ -n "${AI_FLOW_GIT_PROTOCOL:-}" ]]; then
    printf '%s' "${AI_FLOW_GIT_PROTOCOL}"
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    gh config get git_protocol -h github.com 2>/dev/null || true
    return
  fi

  if GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new' \
    git ls-remote git@github.com:justewg/ai-flow.git HEAD >/dev/null 2>&1; then
    printf 'ssh'
    return
  fi

  printf 'https'
}

normalize_toolkit_repo_url() {
  local value="${1:-}"
  local protocol owner_repo
  protocol="$(preferred_github_git_protocol)"
  case "$value" in
    https://github.com/*)
      if [[ "$protocol" == "ssh" ]]; then
        owner_repo="${value#https://github.com/}"
        owner_repo="${owner_repo%.git}"
        printf 'git@github.com:%s.git' "$owner_repo"
      else
        printf '%s' "$value"
      fi
      ;;
    http://github.com/*)
      if [[ "$protocol" == "ssh" ]]; then
        owner_repo="${value#http://github.com/}"
        owner_repo="${owner_repo%.git}"
        printf 'git@github.com:%s.git' "$owner_repo"
      else
        printf '%s' "$value"
      fi
      ;;
    ssh://*|git@*|/*|./*|../*)
      printf '%s' "$value"
      ;;
    */*)
      if [[ "$protocol" == "ssh" ]]; then
        printf 'git@github.com:%s.git' "$value"
      else
        printf 'https://github.com/%s.git' "$value"
      fi
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
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
  toolkit_repo_url="$(normalize_toolkit_repo_url "$toolkit_repo_url")"
  cleanup_dir="$(mktemp -d "${TMPDIR:-/tmp}/ai-flow-docker-init.XXXXXX")"
  trap '[[ -n "${cleanup_dir:-}" ]] && rm -rf "${cleanup_dir}"' EXIT
  echo "Fetching ai-flow toolkit from ${toolkit_repo_url}..." >&2
  git clone --depth 1 --branch "$toolkit_ref" "$toolkit_repo_url" "$cleanup_dir"
  bootstrap_checkout="$cleanup_dir"
fi

if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="$(resolve_local_origin "$bootstrap_checkout")"
fi
if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="https://github.com/justewg/ai-flow.git"
fi

echo "Launching docker bootstrap wizard..." >&2

bootstrap_cmd=(
  env
)

case "$toolkit_repo_url" in
  git@github.com:*|ssh://git@github.com/*)
    bootstrap_cmd+=(AI_FLOW_GIT_PROTOCOL=ssh)
    ;;
  https://github.com/*|http://github.com/*)
    bootstrap_cmd+=(AI_FLOW_GIT_PROTOCOL=https)
    ;;
esac

bootstrap_cmd+=(
  "${bootstrap_checkout}/scripts/docker_bootstrap.sh"
  --toolkit-repo "$toolkit_repo_url"
  --toolkit-ref "$toolkit_ref"
)

if [[ ${#forwarded_args[@]} -gt 0 ]]; then
  bootstrap_cmd+=("${forwarded_args[@]}")
fi

"${bootstrap_cmd[@]}"
