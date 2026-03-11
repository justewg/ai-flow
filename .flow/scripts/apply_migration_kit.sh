#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"

project=""
force="0"
root_env_output="${ROOT_DIR}/.flow/config/root/.env.codex"
flow_tmp_dir="$(codex_resolve_flow_tmp_dir)"

usage() {
  cat <<'EOF'
Usage: .flow/scripts/apply_migration_kit.sh [options]

Options:
  --project <name>        Целевое имя profile после распаковки kit.
  --root-env-output <p>   Куда положить root automation template (по умолчанию ./.flow/config/root/.env.codex).
  --force                 Разрешить перезапись target env/template.
  -h, --help              Показать справку.

Examples:
  .flow/scripts/apply_migration_kit.sh
  .flow/scripts/apply_migration_kit.sh --project acme
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

detect_source_profile() {
  local manifest_project=""
  local first_profile=""
  local count="0"
  local file_name=""
  local search_glob=""

  manifest_project="$(read_manifest_key "MIGRATION_KIT_PROJECT" || true)"
  if [[ -n "$manifest_project" ]]; then
    printf '%s' "$manifest_project"
    return 0
  fi

  for search_glob in '*.sample.env' '*.env'; do
    count="0"
    first_profile=""
    if [[ -d "$(codex_resolve_flow_profile_config_dir)" ]]; then
      while IFS= read -r env_path; do
        [[ -z "$env_path" ]] && continue
        count=$((count + 1))
        if [[ "$search_glob" == "*.sample.env" ]]; then
          file_name="$(basename "$env_path" .sample.env)"
        else
          file_name="$(basename "$env_path" .env)"
        fi
        if [[ "$count" == "1" ]]; then
          first_profile="$file_name"
        fi
      done <<EOF
$(find "$(codex_resolve_flow_profile_config_dir)" -maxdepth 1 -type f -name "$search_glob" | sort)
EOF
    fi

    if [[ "$count" == "1" && -n "$first_profile" ]]; then
      printf '%s' "$first_profile"
      return 0
    fi
  done

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "Missing value for --project" >&2; exit 1; }
      project="$2"
      shift 2
      ;;
    --root-env-output)
      [[ $# -ge 2 ]] || { echo "Missing value for --root-env-output" >&2; exit 1; }
      root_env_output="$2"
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
  echo "Could not detect migration kit profile in .flow/config/profiles/." >&2
  echo "Unpack migration_kit.tgz in repo root first." >&2
  exit 1
fi

target_profile="$source_profile"
if [[ -n "$project" ]]; then
  target_profile="$(slugify "$project")"
fi

flow_profile_config_dir="$(codex_resolve_flow_profile_config_dir)"
flow_root_config_dir="$(codex_resolve_flow_root_config_dir)"
flow_codex_state_root_dir="$(codex_resolve_flow_codex_state_root_dir)"
launchd_namespace="$(codex_resolve_flow_launchd_namespace)"

source_sample_env="${flow_profile_config_dir}/${source_profile}.sample.env"
source_env_file="${flow_profile_config_dir}/${source_profile}.env"
target_env_file="${flow_profile_config_dir}/${target_profile}.env"
target_sample_env="${flow_profile_config_dir}/${target_profile}.sample.env"
source_codex_env="${flow_root_config_dir}/.env.codex"
source_actions_template_dir="${ROOT_DIR}/.flow/templates/github"
source_actions_files_manifest="${flow_root_config_dir}/github-actions.required-files.txt"
source_actions_secrets_manifest="${flow_root_config_dir}/github-actions.required-secrets.txt"
legacy_root_env_template="${flow_profile_config_dir}/${source_profile}.root.env.template"
target_state_dir="${flow_codex_state_root_dir}/${target_profile}"
target_relative_state_dir=".flow/state/codex/${target_profile}"

if [[ ! -f "$source_sample_env" && ! -f "$source_env_file" ]]; then
  echo "Profile sample/env not found for migration kit profile ${source_profile}" >&2
  exit 1
fi

if [[ "$source_env_file" != "$target_env_file" && -e "$target_env_file" && "$force" != "1" ]]; then
  echo "Target profile env already exists: ${target_env_file}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

if [[ "$source_sample_env" != "$target_sample_env" && -e "$target_sample_env" && "$force" != "1" ]]; then
  echo "Target profile sample already exists: ${target_sample_env}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

if [[ -f "$source_sample_env" && -e "$target_env_file" && "$force" != "1" ]]; then
  echo "Target profile env already exists: ${target_env_file}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

mkdir -p "$flow_profile_config_dir" "$(dirname "$root_env_output")" "$target_state_dir"

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
elif [[ "$source_env_file" != "$target_env_file" ]]; then
  cp "$source_env_file" "$target_env_file"
fi

rewrite_env_key "$target_env_file" "PROJECT_PROFILE" "$target_profile"
rewrite_env_key "$target_env_file" "CODEX_STATE_DIR" "$target_state_dir"
rewrite_env_key "$target_env_file" "FLOW_STATE_DIR" "$target_state_dir"
rewrite_env_key "$target_env_file" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"

if [[ -f "$source_codex_env" ]]; then
  if [[ "$root_env_output" == "$source_codex_env" ]]; then
    echo "CODEX_ENV_READY=${source_codex_env}"
  elif [[ -e "$root_env_output" && "$force" != "1" ]]; then
    echo "CODEX_ENV_SKIPPED=${root_env_output}"
    echo "Root automation template already exists; keep existing file or rerun with --force."
  else
    mkdir -p "$(dirname "$root_env_output")"
    cp "$source_codex_env" "$root_env_output"
    echo "CODEX_ENV_WRITTEN=${root_env_output}"
  fi
elif [[ -f "$legacy_root_env_template" ]]; then
  if [[ -e "$root_env_output" && "$force" != "1" ]]; then
    echo "CODEX_ENV_SKIPPED=${root_env_output}"
    echo "Root automation template already exists; keep existing file or rerun with --force."
  else
    mkdir -p "$(dirname "$root_env_output")"
    cp "$legacy_root_env_template" "$root_env_output"
    echo "CODEX_ENV_WRITTEN=${root_env_output}"
  fi
fi

if [[ "$source_profile" != "$target_profile" ]]; then
  rm -f "$source_sample_env"
  rm -f "$source_env_file"
  rm -f "$legacy_root_env_template"
  rmdir "${flow_codex_state_root_dir}/${source_profile}" >/dev/null 2>&1 || true
fi

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

echo "MIGRATION_KIT_APPLIED=1"
echo "MIGRATION_KIT_PROFILE=${target_profile}"
echo "MIGRATION_KIT_PROFILE_SAMPLE=${target_sample_env}"
echo "MIGRATION_KIT_ENV=${target_env_file}"
echo "MIGRATION_KIT_CODEX_ENV=${root_env_output}"
echo "MIGRATION_KIT_STATE_DIR=${target_state_dir}"
echo "MIGRATION_KIT_REPO_ACTIONS_APPLIED=${repo_actions_applied}"
if [[ -f "$source_actions_files_manifest" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_FILES=${source_actions_files_manifest}"
fi
if [[ -f "$source_actions_secrets_manifest" ]]; then
  echo "MIGRATION_KIT_REPO_ACTIONS_SECRETS=${source_actions_secrets_manifest}"
  echo "NEXT_REPO_SECRETS_STEP=Create repo Actions secrets manually in GitHub UI -> Settings -> Secrets and variables -> Actions"
fi
echo "NEXT_STEP=.flow/scripts/run.sh onboarding_audit --profile ${target_profile}"
