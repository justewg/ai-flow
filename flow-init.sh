#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

target_repo="$(pwd -P)"
profile=""
toolkit_repo_url=""
toolkit_ref="main"
skip_questionnaire="0"
force="0"

usage() {
  cat <<'EOF'
Usage: flow-init.sh [options]

Options:
  --profile <name>             Project profile. По умолчанию: slug имени target repo.
  --target-repo <path>         Repo, куда подключается flow. По умолчанию: текущая директория.
  --toolkit-repo <url>         Git URL ai-flow toolkit. По умолчанию: origin текущего checkout
                               или ssh://git@github.com/justewg/ai-flow.git.
  --toolkit-ref <ref>          Git ref toolkit для bootstrap. По умолчанию: main.
  --skip-questionnaire         Только bootstrap toolkit/layout; configurator не запускать.
  --force                      Разрешить перезапись стартовых root-template.
  -h, --help                   Показать справку.

Examples:
  bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile acme
  bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --target-repo <HOME>/sites/acme-app
  .flow/shared/flow-init.sh --profile acme
EOF
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="project"
  printf '%s' "$value"
}

local_toolkit_checkout() {
  if [[ -x "${SCRIPT_DIR}/scripts/bootstrap_repo.sh" ]]; then
    printf '%s' "$SCRIPT_DIR"
    return 0
  fi
  return 1
}

resolve_local_origin() {
  local checkout_dir="$1"
  git -C "$checkout_dir" remote get-url origin 2>/dev/null || true
}

run_questionnaire() {
  local run_script="$1"
  local profile_name="$2"

  if [[ "$skip_questionnaire" == "1" ]]; then
    echo "FLOW_INIT_NEXT_STEP=${run_script} flow_configurator questionnaire --profile ${profile_name}"
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    echo "FLOW_INIT_STEP=flow_configurator questionnaire"
    "${run_script}" flow_configurator questionnaire --profile "$profile_name" < /dev/tty > /dev/tty 2>&1
    echo "FLOW_INIT_NEXT_AUDIT=${run_script} onboarding_audit --profile ${profile_name}"
    echo "FLOW_INIT_NEXT_ORCHESTRATE=${run_script} profile_init orchestrate --profile ${profile_name}"
    return 0
  fi

  echo "FLOW_INIT_NEXT_STEP=${run_script} flow_configurator questionnaire --profile ${profile_name}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --target-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --target-repo" >&2; exit 1; }
      target_repo="$2"
      shift 2
      ;;
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
    --skip-questionnaire)
      skip_questionnaire="1"
      shift
      ;;
    --force)
      force="1"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

target_repo="$(cd "$target_repo" && pwd -P)"
if [[ -z "$profile" ]]; then
  profile="$(slugify "$(basename "$target_repo")")"
else
  profile="$(slugify "$profile")"
fi

bootstrap_checkout=""
cleanup_dir=""
bootstrap_args=()

if bootstrap_checkout="$(local_toolkit_checkout)"; then
  :
else
  if [[ -z "$toolkit_repo_url" ]]; then
    toolkit_repo_url="ssh://git@github.com/justewg/ai-flow.git"
  fi
  cleanup_dir="$(mktemp -d "${TMPDIR:-/tmp}/ai-flow-init.XXXXXX")"
  trap '[[ -n "${cleanup_dir:-}" ]] && rm -rf "${cleanup_dir}"' EXIT
  git clone --depth 1 --branch "$toolkit_ref" "$toolkit_repo_url" "$cleanup_dir" >/dev/null 2>&1
  bootstrap_checkout="$cleanup_dir"
fi

if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="$(resolve_local_origin "$bootstrap_checkout")"
fi
if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="ssh://git@github.com/justewg/ai-flow.git"
fi

bootstrap_args=(
  --profile "$profile"
  --target-repo "$target_repo"
  --shared-repo-url "$toolkit_repo_url"
  --shared-ref "$toolkit_ref"
)
if [[ "$force" == "1" ]]; then
  bootstrap_args+=(--force)
fi

"${bootstrap_checkout}/scripts/bootstrap_repo.sh" "${bootstrap_args[@]}"

run_questionnaire "${target_repo}/.flow/shared/scripts/run.sh" "$profile"
