#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

target_repo="$(pwd -P)"
profile=""
shared_repo_url=""
shared_ref=""
force="0"

usage() {
  cat <<'EOF'
Usage: bootstrap_repo.sh --profile <name> [options]

Options:
  --profile <name>             Имя project profile. Обязательно.
  --target-repo <path>         Repo, куда materialize-ить initializer layout.
                               По умолчанию: текущая директория.
  --shared-repo-url <url>      Источник toolkit для .flow/shared.
                               По умолчанию: origin текущего ai-flow checkout.
  --shared-ref <ref>           Git ref/revision toolkit. По умолчанию: HEAD
                               текущего ai-flow checkout.
  --force                      Разрешить перезапись стартовых root-template.
  -h, --help                   Показать справку.

Examples:
  .flow/shared/scripts/bootstrap_repo.sh --profile acme
  .flow/shared/scripts/bootstrap_repo.sh --profile acme --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/bootstrap_repo.sh --profile acme --shared-repo-url ssh://git@github.com/justewg/ai-flow.git --shared-ref main
EOF
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="project"
  printf '%s' "$value"
}

ensure_dir() {
  local path="$1"
  mkdir -p "$path"
}

current_toolkit_origin() {
  git -C "$TOOLKIT_ROOT" remote get-url origin 2>/dev/null || true
}

current_toolkit_revision() {
  git -C "$TOOLKIT_ROOT" rev-parse HEAD 2>/dev/null || echo "main"
}

git_in_target_repo() {
  git -C "$target_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

git_with_local_transport() {
  if [[ "$shared_repo_url" == /* || "$shared_repo_url" == file://* || "$shared_repo_url" == ./* || "$shared_repo_url" == ../* ]]; then
    git -c protocol.file.allow=always "$@"
  else
    git "$@"
  fi
}

ensure_target_layout() {
  ensure_dir "${target_repo}/.flow"
  ensure_dir "${target_repo}/.flow/config"
  ensure_dir "${target_repo}/.flow/config/profiles"
  ensure_dir "${target_repo}/.flow/tmp/wizard"
  ensure_dir "${target_repo}/.flow/templates/github"
}

copy_file_if_missing() {
  local source_path="$1"
  local target_path="$2"
  if [[ ! -f "$source_path" ]]; then
    echo "BOOTSTRAP_TEMPLATE_MISSING=${source_path}"
    return 0
  fi

  ensure_dir "$(dirname "$target_path")"
  if [[ -e "$target_path" && "$force" != "1" ]]; then
    echo "BOOTSTRAP_TEMPLATE_REUSED=${target_path}"
    return 0
  fi

  cp "$source_path" "$target_path"
  echo "BOOTSTRAP_TEMPLATE_WRITTEN=${target_path}"
}

checkout_toolkit_ref() {
  local toolkit_dir="$1"
  if [[ -n "$shared_ref" ]]; then
    git_with_local_transport -C "$toolkit_dir" fetch --depth 1 origin "$shared_ref" >/dev/null 2>&1 || true
    git -C "$toolkit_dir" checkout "$shared_ref" >/dev/null 2>&1
  fi
}

bootstrap_shared_checkout() {
  local target_shared_dir="${target_repo}/.flow/shared"
  local action="reused"

  if git_in_target_repo; then
    if git -C "$target_repo" config -f .gitmodules --get "submodule..flow/shared.url" >/dev/null 2>&1; then
      git -C "$target_repo" config -f .gitmodules submodule..flow/shared.url "$shared_repo_url"
      git -C "$target_repo" config -f .gitmodules submodule..flow/shared.branch "main" || true
      git_with_local_transport -C "$target_repo" submodule sync -- ".flow/shared" >/dev/null 2>&1 || true
      git_with_local_transport -C "$target_repo" submodule update --init --checkout ".flow/shared" >/dev/null 2>&1
    elif [[ ! -e "$target_shared_dir" ]]; then
      git_with_local_transport -C "$target_repo" submodule add "$shared_repo_url" ".flow/shared" >/dev/null 2>&1
      action="added"
    elif [[ -d "$target_shared_dir/.git" || -f "$target_shared_dir/.git" ]]; then
      echo "BOOTSTRAP_BLOCKED_SHARED_PATH=${target_shared_dir}" >&2
      echo "Existing .flow/shared is a standalone git checkout, but canonical git-repo mode requires a submodule. Remove it or convert it before retrying." >&2
      exit 1
    else
      echo "BOOTSTRAP_BLOCKED_SHARED_PATH=${target_shared_dir}" >&2
      echo "Existing .flow/shared is not a git checkout/submodule. Move it away or convert it manually." >&2
      exit 1
    fi

    checkout_toolkit_ref "$target_shared_dir"
  else
    if [[ ! -e "$target_shared_dir" ]]; then
      git_with_local_transport clone "$shared_repo_url" "$target_shared_dir" >/dev/null 2>&1
      action="clone-fallback"
    elif [[ -d "$target_shared_dir/.git" || -f "$target_shared_dir/.git" ]]; then
      action="reused-clone-fallback"
    else
      echo "BOOTSTRAP_BLOCKED_SHARED_PATH=${target_shared_dir}" >&2
      echo "Existing .flow/shared is not a git checkout. Initialize git repo or remove the path and retry." >&2
      exit 1
    fi

    checkout_toolkit_ref "$target_shared_dir"
  fi

  echo "SHARED_SUBMODULE_ACTION=${action}"
  echo "SHARED_TOOLKIT_PATH=${target_shared_dir}"
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
    --shared-repo-url)
      [[ $# -ge 2 ]] || { echo "Missing value for --shared-repo-url" >&2; exit 1; }
      shared_repo_url="$2"
      shift 2
      ;;
    --shared-ref)
      [[ $# -ge 2 ]] || { echo "Missing value for --shared-ref" >&2; exit 1; }
      shared_ref="$2"
      shift 2
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

if [[ -z "$profile" ]]; then
  echo "Option --profile is required" >&2
  usage
  exit 1
fi

target_repo="$(cd "$target_repo" && pwd -P)"
profile="$(slugify "$profile")"

if [[ -z "$shared_repo_url" ]]; then
  shared_repo_url="$(current_toolkit_origin)"
fi
if [[ -z "$shared_repo_url" ]]; then
  shared_repo_url="ssh://git@github.com/justewg/ai-flow.git"
fi
if [[ -z "$shared_ref" ]]; then
  shared_ref="$(current_toolkit_revision)"
fi

ensure_target_layout
bootstrap_shared_checkout

copy_file_if_missing \
  "${TOOLKIT_ROOT}/templates/root/COMMAND_TEMPLATES.md" \
  "${target_repo}/COMMAND_TEMPLATES.md"

echo "BOOTSTRAP_REPO=${target_repo}"
echo "BOOTSTRAP_PROFILE=${profile}"
echo "BOOTSTRAP_SHARED_REPO_URL=${shared_repo_url}"
echo "BOOTSTRAP_SHARED_REF=${shared_ref}"

ROOT_DIR="$target_repo" "${target_repo}/.flow/shared/scripts/profile_init.sh" init --profile "$profile"

echo "NEXT_STEP=.flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${profile}"
echo "NEXT_AUDIT_STEP=.flow/shared/scripts/run.sh onboarding_audit --profile ${profile}"
echo "NEXT_ORCHESTRATE_STEP=.flow/shared/scripts/run.sh profile_init orchestrate --profile ${profile}"
