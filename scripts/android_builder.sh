#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

SERVICE_DIR="$(cd "${SCRIPT_DIR}/../services/android-builder" && pwd -P)"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose.yml"
CODEX_DIR="$(codex_export_state_dir)"
AI_FLOW_ROOT_DIR="$(codex_resolve_ai_flow_root_dir)"

mkdir -p "$CODEX_DIR"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/android_builder.sh <config|up|down|shell|run|exec> [command...]

Commands:
  config              Validate rendered docker compose config.
  up                  Build and start the android-builder service.
  down                Stop and remove the android-builder service.
  shell               Open an interactive shell inside the running service.
  run <cmd...>        Run an ephemeral command in a one-shot container.
  exec <cmd...>       Execute a command in the running service container.

Environment overrides:
  ANDROID_CMDLINE_TOOLS_VERSION
  ANDROID_COMPILE_SDK
  ANDROID_BUILD_TOOLS
  ANDROID_BUILDER_IMAGE_NAME
EOF
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="project"
  printf '%s' "$value"
}

project_slug() {
  local repo_name
  repo_name="$(basename "$ROOT_DIR")"
  slugify "$repo_name"
}

compose_project_name() {
  printf 'ai-flow-android-builder-%s' "$(project_slug)"
}

cache_root() {
  printf '%s/services/android-builder/%s' "$AI_FLOW_ROOT_DIR" "$(project_slug)"
}

ensure_cache_layout() {
  mkdir -p "$(cache_root)/home"
}

compose_env_file() {
  local env_file
  env_file="$(mktemp "$(cache_root)/compose.XXXXXX.env")"
  cat > "$env_file" <<EOF
ANDROID_BUILDER_WORKSPACE_PATH=${ROOT_DIR}
ANDROID_BUILDER_CACHE_PATH=$(cache_root)/home
ANDROID_BUILDER_UID=$(id -u)
ANDROID_BUILDER_GID=$(id -g)
ANDROID_BUILDER_IMAGE_NAME=${ANDROID_BUILDER_IMAGE_NAME:-$(compose_project_name):latest}
ANDROID_CMDLINE_TOOLS_VERSION=${ANDROID_CMDLINE_TOOLS_VERSION:-11076708}
ANDROID_COMPILE_SDK=${ANDROID_COMPILE_SDK:-35}
ANDROID_BUILD_TOOLS=${ANDROID_BUILD_TOOLS:-35.0.0}
EOF
  printf '%s' "$env_file"
}

run_compose() {
  local env_file="$1"
  shift
  docker compose \
    --project-name "$(compose_project_name)" \
    --env-file "$env_file" \
    -f "$COMPOSE_FILE" \
    "$@"
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift || true

ensure_cache_layout
env_file="$(compose_env_file)"
trap 'rm -f "$env_file"' EXIT

case "$cmd" in
  config)
    run_compose "$env_file" config
    ;;
  up)
    run_compose "$env_file" up -d --build
    run_compose "$env_file" ps
    ;;
  down)
    run_compose "$env_file" down
    ;;
  shell)
    run_compose "$env_file" exec android-builder bash
    ;;
  run)
    if [[ $# -eq 0 ]]; then
      echo "Usage: .flow/shared/scripts/android_builder.sh run <cmd...>"
      exit 1
    fi
    run_compose "$env_file" run --rm android-builder "$@"
    ;;
  exec)
    if [[ $# -eq 0 ]]; then
      echo "Usage: .flow/shared/scripts/android_builder.sh exec <cmd...>"
      exit 1
    fi
    run_compose "$env_file" exec android-builder "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
