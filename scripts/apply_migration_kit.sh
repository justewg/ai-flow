#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

project=""
force="0"
migration_config=""
payload_archive=""

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/apply_migration_kit.sh [options]

Options:
  --project <name>          Целевое имя profile после распаковки payload.
  --migration-config <path> Локальный migration config из .flow/migration/migration.conf.
  --payload-archive <path>  Путь к payload archive проекта.
  --force                   Разрешить перезапись target env/template.
  -h, --help                Показать справку.

Examples:
  .flow/shared/scripts/apply_migration_kit.sh --project acme --migration-config .flow/migration/migration.conf --payload-archive .flow/migration/acme-migration-kit.tgz
EOF
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
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

copy_file_if_present() {
  local source_path="$1"
  local target_path="$2"
  [[ -f "$source_path" ]] || return 0
  mkdir -p "$(dirname "$target_path")"
  if [[ -e "$target_path" && "$force" != "1" ]]; then
    echo "PAYLOAD_COPY_SKIPPED=${target_path}"
    echo "Use --force to overwrite existing file."
    return 0
  fi
  cp "$source_path" "$target_path"
  echo "PAYLOAD_COPY_WRITTEN=${target_path}"
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

read_migration_config_key() {
  local key="$1"
  [[ -n "$migration_config" && -f "$migration_config" ]] || return 1
  codex_read_key_from_env_file "$migration_config" "$key"
}

emit_binding_post_apply_hint() {
  local binding_mode=""
  binding_mode="$(read_migration_config_key "MIGRATION_PROJECT_BINDING_MODE" || true)"
  if [[ "$binding_mode" == "keep" ]]; then
    echo "NEXT_BINDING_STEP=Verify GITHUB_REPO and PROJECT_* in .flow/config/flow.env still point to the intended target project."
  else
    echo "NEXT_BINDING_STEP=Run .flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${target_profile} and fill GITHUB_REPO plus PROJECT_* for this target repo."
  fi
}

resolve_repo_relative_path() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  if [[ "$value" = /* ]]; then
    printf '%s' "$value"
  else
    printf '%s/%s' "${ROOT_DIR}" "${value#./}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "Missing value for --project" >&2; exit 1; }
      project="$2"
      shift 2
      ;;
    --migration-config)
      [[ $# -ge 2 ]] || { echo "Missing value for --migration-config" >&2; exit 1; }
      migration_config="$2"
      shift 2
      ;;
    --payload-archive)
      [[ $# -ge 2 ]] || { echo "Missing value for --payload-archive" >&2; exit 1; }
      payload_archive="$2"
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

if [[ -n "$migration_config" && ! -f "$migration_config" ]]; then
  echo "Migration config not found: ${migration_config}" >&2
  exit 1
fi

if [[ -z "$project" ]]; then
  if config_project="$(read_migration_config_key "MIGRATION_PROJECT" || true)"; [[ -n "$config_project" ]]; then
    project="$config_project"
  fi
fi

if [[ -z "$project" ]]; then
  echo "Could not resolve target project. Pass --project or set MIGRATION_PROJECT in migration.conf." >&2
  exit 1
fi

if [[ -z "$payload_archive" ]]; then
  if payload_rel="$(read_migration_config_key "MIGRATION_PAYLOAD_ARCHIVE_REL" || true)"; [[ -n "$payload_rel" ]]; then
    payload_archive="$(resolve_repo_relative_path "$payload_rel")"
  fi
fi

if [[ -z "$payload_archive" || ! -f "$payload_archive" ]]; then
  echo "Payload archive not found: ${payload_archive}" >&2
  exit 1
fi

target_profile="$(slugify "$project")"
flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
flow_config_dir="$(codex_resolve_flow_config_dir)"
target_env_file="$(codex_resolve_flow_env_file)"
target_sample_env="$(codex_resolve_flow_sample_env_file)"
target_migration_conf="${flow_config_dir}/migration.conf"
launchd_namespace="$(codex_resolve_flow_launchd_namespace)"
target_state_dir="${flow_state_root_dir}"
target_relative_state_dir=".flow/state"

payload_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex_payload_unpack.XXXXXX")"
cleanup() {
  rm -rf "$payload_tmp_dir"
}
trap cleanup EXIT

tar -xzf "$payload_archive" -C "$payload_tmp_dir"

source_sample_env="${payload_tmp_dir}/.flow/config/flow.sample.env"
source_env_file="${payload_tmp_dir}/.flow/config/flow.env"
source_actions_template_dir="${payload_tmp_dir}/.flow/templates/github"
source_actions_files_manifest="${source_actions_template_dir}/required-files.txt"
source_actions_secrets_manifest="${source_actions_template_dir}/required-secrets.txt"
source_github_overlay_dir="${payload_tmp_dir}/.flow/github"

if [[ ! -f "$source_sample_env" && ! -f "$source_env_file" ]]; then
  echo "flow.sample.env / flow.env not found in payload archive." >&2
  exit 1
fi

if [[ -e "$target_env_file" && "$force" != "1" ]]; then
  echo "Target flow env already exists: ${target_env_file}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

if [[ -e "$target_sample_env" && "$force" != "1" ]]; then
  echo "Target flow sample already exists: ${target_sample_env}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

mkdir -p "$flow_config_dir" "$target_state_dir"

if [[ -n "$migration_config" ]]; then
  if [[ -e "$target_migration_conf" && "$target_migration_conf" != "$migration_config" && "$force" != "1" ]]; then
    echo "Target migration config already exists: ${target_migration_conf}" >&2
    echo "Use --force to overwrite it." >&2
    exit 1
  fi
  if [[ "$migration_config" != "$target_migration_conf" ]]; then
    cp "$migration_config" "$target_migration_conf"
  fi
fi

if [[ -f "$source_sample_env" ]]; then
  cp "$source_sample_env" "$target_sample_env"
  rewrite_env_key "$target_sample_env" "PROJECT_PROFILE" "$target_profile"
  rewrite_env_key "$target_sample_env" "CODEX_STATE_DIR" "$target_relative_state_dir"
  rewrite_env_key "$target_sample_env" "FLOW_STATE_DIR" "$target_relative_state_dir"
  rewrite_env_key "$target_sample_env" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"
fi

if [[ -f "$source_env_file" ]]; then
  cp "$source_env_file" "$target_env_file"
elif [[ -f "$target_sample_env" ]]; then
  cp "$target_sample_env" "$target_env_file"
fi

rewrite_env_key "$target_env_file" "PROJECT_PROFILE" "$target_profile"
rewrite_env_key "$target_env_file" "CODEX_STATE_DIR" "$target_relative_state_dir"
rewrite_env_key "$target_env_file" "FLOW_STATE_DIR" "$target_relative_state_dir"
rewrite_env_key "$target_env_file" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"

copy_file_if_present "$source_actions_files_manifest" "${ROOT_DIR}/.flow/templates/github/required-files.txt"
copy_file_if_present "$source_actions_secrets_manifest" "${ROOT_DIR}/.flow/templates/github/required-secrets.txt"

repo_actions_applied="0"
if [[ -d "${source_github_overlay_dir}/workflows" ]]; then
  while IFS= read -r source_workflow; do
    [[ -n "$source_workflow" ]] || continue
    workflow_name="$(basename "$source_workflow")"
    copy_repo_overlay_file "$source_workflow" "${ROOT_DIR}/.github/workflows/${workflow_name}"
    repo_actions_applied=$((repo_actions_applied + 1))
  done <<EOF
$(find "${source_github_overlay_dir}/workflows" -maxdepth 1 -type f -name '*.yml' | sort)
EOF
fi

if [[ -f "${source_github_overlay_dir}/pull_request_template.md" ]]; then
  copy_repo_overlay_file \
    "${source_github_overlay_dir}/pull_request_template.md" \
    "${ROOT_DIR}/.github/pull_request_template.md"
fi

if [[ -d "${ROOT_DIR}/.flow/shared" ]]; then
  echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=BOOTSTRAPPED_EXTERNALLY"
else
  echo "MIGRATION_KIT_TOOLKIT_SUBMODULE_STATUS=NOT_PRESENT"
fi

echo "MIGRATION_KIT_APPLIED=1"
echo "MIGRATION_KIT_PROFILE=${target_profile}"
echo "MIGRATION_KIT_PROFILE_SAMPLE=${target_sample_env}"
echo "MIGRATION_KIT_ENV=${target_env_file}"
if [[ -n "$migration_config" ]]; then
  echo "MIGRATION_KIT_FLOW_CONFIG=${target_migration_conf}"
fi
echo "MIGRATION_KIT_STATE_DIR=${target_state_dir}"
echo "MIGRATION_KIT_REPO_ACTIONS_APPLIED=${repo_actions_applied}"
if [[ -f "${ROOT_DIR}/.flow/templates/github/required-files.txt" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_FILES=${ROOT_DIR}/.flow/templates/github/required-files.txt"
fi
if [[ -f "${ROOT_DIR}/.flow/templates/github/required-secrets.txt" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_SECRETS=${ROOT_DIR}/.flow/templates/github/required-secrets.txt"
  echo "NEXT_REPO_SECRETS_STEP=Create repo Actions secrets manually in GitHub UI -> Settings -> Secrets and variables -> Actions"
fi
emit_binding_post_apply_hint
echo "NEXT_STEP=.flow/shared/scripts/run.sh onboarding_audit --profile ${target_profile}"
