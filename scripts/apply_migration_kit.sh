#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

project=""
force="0"
flow_tmp_dir="$(codex_resolve_flow_tmp_dir)"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/apply_migration_kit.sh [options]

Options:
  --project <name>        Целевое имя profile после распаковки kit.
  --force                 Разрешить перезапись target env/template.
  -h, --help              Показать справку.

Examples:
  .flow/shared/scripts/apply_migration_kit.sh
  .flow/shared/scripts/apply_migration_kit.sh --project acme
EOF
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
}

read_manifest_key() {
  local key="$1"
  local manifest_path="${flow_tmp_dir}/migration_kit_manifest.env"
  local legacy_manifest_path="${ROOT_DIR}/.flow/migration_kit_manifest.env"
  if [[ -f "$manifest_path" ]]; then
    codex_read_key_from_env_file "$manifest_path" "$key"
    return 0
  fi
  [[ -f "$legacy_manifest_path" ]] || return 1
  codex_read_key_from_env_file "$legacy_manifest_path" "$key"
}

rewrite_env_key() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local temp_file
  temp_file="$(mktemp "${TMPDIR:-/tmp}/codex_env_rewrite.XXXXXX")"

  awk -v target_key="$key" -v target_value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ ("^" target_key "=") {
      print target_key "=" target_value
      replaced = 1
      next
    }
    { print }
    END {
      if (replaced == 0) {
        print target_key "=" target_value
      }
    }
  ' "$file_path" > "$temp_file"

  mv "$temp_file" "$file_path"
}

copy_repo_overlay_file() {
  local source_path="$1"
  local target_path="$2"

  mkdir -p "$(dirname "$target_path")"
  if [[ -e "$target_path" && "$force" != "1" ]]; then
    echo "GITHUB_OVERLAY_SKIPPED=${target_path}"
    echo "Use --force to overwrite existing repo automation file."
    return 0
  fi
  cp "$source_path" "$target_path"
  echo "GITHUB_OVERLAY_WRITTEN=${target_path}"
}

materialize_shared_submodule() {
  local submodule_url submodule_revision current_url backup_dir timestamp backup_path
  local add_out sync_out fetch_out checkout_out

  submodule_url="$(read_manifest_key "MIGRATION_KIT_TOOLKIT_SUBMODULE_URL" || true)"
  submodule_revision="$(read_manifest_key "MIGRATION_KIT_TOOLKIT_SUBMODULE_REVISION" || true)"
  if [[ -z "$submodule_url" || -z "$submodule_revision" ]]; then
    echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=SKIPPED_NO_MANIFEST"
    return 0
  fi

  if ! git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=SKIPPED_NOT_GIT_REPO"
    return 0
  fi

  if git -C "${ROOT_DIR}" config -f .gitmodules --get submodule..flow/shared.url >/dev/null 2>&1; then
    current_url="$(git -C "${ROOT_DIR}" config -f .gitmodules --get submodule..flow/shared.url || true)"
    if [[ "$current_url" != "$submodule_url" ]]; then
      git -C "${ROOT_DIR}" config -f .gitmodules submodule..flow/shared.url "$submodule_url"
    fi
    if sync_out="$(git -C "${ROOT_DIR}" submodule sync -- .flow/shared 2>&1)"; then
      [[ -n "$sync_out" ]] && echo "$sync_out"
    else
      [[ -n "$sync_out" ]] && echo "$sync_out"
      echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=FAILED_SYNC"
      return 0
    fi
  else
    if [[ -e "${ROOT_DIR}/.flow/shared" ]]; then
      timestamp="$(date -u '+%Y%m%d-%H%M%S')"
      backup_dir="${ROOT_DIR}/.flow/tmp/bootstrap/backups"
      backup_path="${backup_dir}/shared-pre-submodule-${timestamp}"
      mkdir -p "$backup_dir"
      mv "${ROOT_DIR}/.flow/shared" "$backup_path"
      echo "MIGRATION_KIT_TOOLKIT_SNAPSHOT_BACKUP=${backup_path}"
    fi

    if add_out="$(git -C "${ROOT_DIR}" submodule add "$submodule_url" .flow/shared 2>&1)"; then
      [[ -n "$add_out" ]] && echo "$add_out"
    else
      [[ -n "$add_out" ]] && echo "$add_out"
      rm -rf "${ROOT_DIR}/.flow/shared"
      if [[ -n "${backup_path:-}" && -e "$backup_path" ]]; then
        mv "$backup_path" "${ROOT_DIR}/.flow/shared"
      fi
      echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=FAILED_ADD"
      return 0
    fi
  fi

  if fetch_out="$(git -C "${ROOT_DIR}/.flow/shared" fetch origin "$submodule_revision" 2>&1)"; then
    [[ -n "$fetch_out" ]] && echo "$fetch_out"
  else
    [[ -n "$fetch_out" ]] && echo "$fetch_out"
    echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=FAILED_FETCH"
    return 0
  fi

  if checkout_out="$(git -C "${ROOT_DIR}/.flow/shared" checkout "$submodule_revision" 2>&1)"; then
    [[ -n "$checkout_out" ]] && echo "$checkout_out"
    echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=OK"
  else
    [[ -n "$checkout_out" ]] && echo "$checkout_out"
    echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=FAILED_CHECKOUT"
  fi
}

detect_source_profile() {
  read_manifest_key "MIGRATION_KIT_PROJECT" || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "Missing value for --project" >&2; exit 1; }
      project="$2"
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

source_profile="$(detect_source_profile || true)"
if [[ -z "$source_profile" ]]; then
  echo "Could not detect migration kit project in .flow/tmp/migration_kit_manifest.env." >&2
  echo "Unpack migration_kit.tgz in repo root first." >&2
  exit 1
fi

target_profile="$source_profile"
if [[ -n "$project" ]]; then
  target_profile="$(slugify "$project")"
fi

flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
flow_config_dir="$(codex_resolve_flow_config_dir)"
target_env_file="$(codex_resolve_flow_env_file)"
target_sample_env="$(codex_resolve_flow_sample_env_file)"
launchd_namespace="$(codex_resolve_flow_launchd_namespace)"

source_sample_env="${flow_config_dir}/flow.sample.env"
source_env_file="${flow_config_dir}/flow.env"
source_actions_template_dir="${ROOT_DIR}/.flow/templates/github"
source_actions_files_manifest="${source_actions_template_dir}/required-files.txt"
source_actions_secrets_manifest="${source_actions_template_dir}/required-secrets.txt"
target_state_dir="${flow_state_root_dir}"
target_relative_state_dir=".flow/state"

if [[ ! -f "$source_sample_env" && ! -f "$source_env_file" ]]; then
  echo "flow.sample.env / flow.env not found in unpacked migration kit." >&2
  exit 1
fi

if [[ -e "$target_env_file" && "$target_env_file" != "$source_env_file" && "$force" != "1" ]]; then
  echo "Target flow env already exists: ${target_env_file}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

if [[ -e "$target_sample_env" && "$target_sample_env" != "$source_sample_env" && "$force" != "1" ]]; then
  echo "Target profile sample already exists: ${target_sample_env}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

mkdir -p "$flow_config_dir" "$target_state_dir"

if [[ -f "$source_sample_env" ]]; then
  if [[ "$source_sample_env" != "$target_sample_env" ]]; then
    cp "$source_sample_env" "$target_sample_env"
  fi
  rewrite_env_key "$target_sample_env" "PROJECT_PROFILE" "$target_profile"
  rewrite_env_key "$target_sample_env" "CODEX_STATE_DIR" "$target_relative_state_dir"
  rewrite_env_key "$target_sample_env" "FLOW_STATE_DIR" "$target_relative_state_dir"
  rewrite_env_key "$target_sample_env" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"
fi

if [[ -f "$target_sample_env" ]]; then
  cp "$target_sample_env" "$target_env_file"
elif [[ -f "$source_env_file" ]]; then
  cp "$source_env_file" "$target_env_file"
fi

rewrite_env_key "$target_env_file" "PROJECT_PROFILE" "$target_profile"
rewrite_env_key "$target_env_file" "CODEX_STATE_DIR" "$target_state_dir"
rewrite_env_key "$target_env_file" "FLOW_STATE_DIR" "$target_state_dir"
rewrite_env_key "$target_env_file" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"

repo_actions_applied="0"
if [[ -d "${source_actions_template_dir}/workflows" ]]; then
  while IFS= read -r source_workflow; do
    [[ -n "$source_workflow" ]] || continue
    workflow_name="$(basename "$source_workflow")"
    copy_repo_overlay_file "$source_workflow" "${ROOT_DIR}/.github/workflows/${workflow_name}"
    repo_actions_applied=$((repo_actions_applied + 1))
  done <<EOF
$(find "${source_actions_template_dir}/workflows" -maxdepth 1 -type f -name '*.yml' | sort)
EOF
fi

if [[ -f "${source_actions_template_dir}/pull_request_template.md" ]]; then
  copy_repo_overlay_file \
    "${source_actions_template_dir}/pull_request_template.md" \
    "${ROOT_DIR}/.github/pull_request_template.md"
fi

materialize_shared_submodule

echo "MIGRATION_KIT_APPLIED=1"
echo "MIGRATION_KIT_PROFILE=${target_profile}"
echo "MIGRATION_KIT_PROFILE_SAMPLE=${target_sample_env}"
echo "MIGRATION_KIT_ENV=${target_env_file}"
echo "MIGRATION_KIT_STATE_DIR=${target_state_dir}"
echo "MIGRATION_KIT_REPO_ACTIONS_APPLIED=${repo_actions_applied}"
if toolkit_submodule_url="$(read_manifest_key "MIGRATION_KIT_TOOLKIT_SUBMODULE_URL" || true)"; [[ -n "${toolkit_submodule_url}" ]]; then
  echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_URL=${toolkit_submodule_url}"
fi
if toolkit_submodule_revision="$(read_manifest_key "MIGRATION_KIT_TOOLKIT_SUBMODULE_REVISION" || true)"; [[ -n "${toolkit_submodule_revision}" ]]; then
  echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_REVISION=${toolkit_submodule_revision}"
fi
if [[ -f "$source_actions_files_manifest" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_FILES=${source_actions_files_manifest}"
fi
if [[ -f "$source_actions_secrets_manifest" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_SECRETS=${source_actions_secrets_manifest}"
  echo "NEXT_REPO_SECRETS_STEP=Create repo Actions secrets manually in GitHub UI -> Settings -> Secrets and variables -> Actions"
fi
echo "NEXT_STEP=.flow/shared/scripts/run.sh onboarding_audit --profile ${target_profile}"
