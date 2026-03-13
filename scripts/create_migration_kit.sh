#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

project=""
source_profile=""
defaults_from="current"
target_repo=""
output_path=""
force="0"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/create_migration_kit.sh --project <name> [options]

Options:
  --project <name>         Целевое имя profile для migration kit (обязательно).
  --defaults-from <mode>   Откуда брать defaults для нового flow.sample.env:
                           current (из текущего flow.env) или sample (из flow.sample.env).
  --source-profile <name>  Legacy profile-источник для defaults-from=current.
  --target-repo <path>     Путь к новому repo: archive дополнительно копируется в
                           <target-repo>/.flow/migration/<project>-migration-kit.tgz.
  --output <path>          Явный путь итогового архива. По умолчанию:
                           ./.flow/migration/<project>-migration-kit.tgz
  --force                  Перезаписать существующий архив.
  -h, --help               Показать справку.

Examples:
  .flow/shared/scripts/create_migration_kit.sh --project acme
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from sample
  .flow/shared/scripts/create_migration_kit.sh --project acme --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from current --source-profile planka --output /tmp/acme_kit.tgz
EOF
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
}

resolve_source_env_file() {
  local target_profile="$1"
  local candidate=""
  local first_env=""
  local count="0"

  if [[ "$defaults_from" == "sample" ]]; then
    candidate="$(codex_resolve_flow_sample_env_file)"
    [[ -f "$candidate" ]] || {
      echo "Source sample env not found: ${candidate}" >&2
      return 1
    }
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -n "$source_profile" ]]; then
    candidate="$(codex_resolve_profile_env_file "$(slugify "$source_profile")")"
    [[ -f "$candidate" ]] || {
      echo "Source profile env not found: ${candidate}" >&2
      return 1
    }
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -n "${DAEMON_GH_ENV_FILE:-}" && -f "${DAEMON_GH_ENV_FILE}" ]]; then
    printf '%s' "${DAEMON_GH_ENV_FILE}"
    return 0
  fi

  candidate="$(codex_resolve_flow_env_file)"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  candidate="$(codex_resolve_profile_env_file "${target_profile}")"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -d "$(codex_resolve_flow_profile_config_dir)" ]]; then
    while IFS= read -r env_path; do
      [[ -z "$env_path" ]] && continue
      count=$((count + 1))
      if [[ "$count" == "1" ]]; then
        first_env="$env_path"
      fi
    done <<EOF
$(find "$(codex_resolve_flow_profile_config_dir)" -maxdepth 1 -type f -name '*.env' | sort)
EOF
  fi

  if [[ "$count" == "1" && -n "$first_env" ]]; then
    printf '%s' "$first_env"
    return 0
  fi

  candidate="$(codex_resolve_flow_sample_env_file)"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  return 1
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

clear_env_key() {
  local file_path="$1"
  local key="$2"
  rewrite_env_key "$file_path" "$key" ""
}

resolve_value() {
  local key="$1"
  local default_value="${2:-}"
  codex_resolve_config_value "$key" "$default_value"
}

write_repo_actions_manifest() {
  local files_destination="$1"
  local secrets_destination="$2"
  local workflows_dir="${ROOT_DIR}/.github/workflows"
  local pr_template="${ROOT_DIR}/.github/pull_request_template.md"
  local workflow_rel=""
  local secret_names=""

  : > "$files_destination"
  : > "$secrets_destination"

  if [[ -d "$workflows_dir" ]]; then
    while IFS= read -r workflow_rel; do
      [[ -n "$workflow_rel" ]] || continue
      printf '%s\n' "$workflow_rel" >> "$files_destination"
    done <<EOF
$(cd "$ROOT_DIR" && find .github/workflows -maxdepth 1 -type f -name '*.yml' | sort)
EOF
  fi

  if [[ -f "$pr_template" ]]; then
    printf '%s\n' ".github/pull_request_template.md" >> "$files_destination"
  fi

  if [[ -d "$workflows_dir" ]]; then
    secret_names="$(
      cd "$ROOT_DIR" &&
      rg -o '[A-Z][A-Z0-9_]+ is required' .github/workflows --no-filename 2>/dev/null \
        | sed 's/ is required$//' \
        | sort -u
    )"
    if [[ -n "$secret_names" ]]; then
      printf '%s\n' "$secret_names" > "$secrets_destination"
    fi
  fi
}

write_profile_sample_env() {
  local destination="$1"
  local source_env_path="$2"
  local defaults_mode="$3"
  local target_profile="$4"
  local watchdog_interval="$5"
  local launchd_namespace="$6"
  local line=""
  local key=""
  local value=""
  local source_label=""

  if [[ "$defaults_mode" == "sample" ]]; then
    source_label="flow.sample.env"
  else
    source_label="flow.env"
  fi

  {
    cat <<EOF
# Generated by .flow/shared/scripts/create_migration_kit.sh for profile ${target_profile}
# Defaults source: ${source_label}
# This file intentionally contains no live secrets from the source project.
# After unpacking in a new repo, run:
#   .flow/shared/scripts/run.sh apply_migration_kit --project ${target_profile}

EOF

    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]]; then
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
          PROJECT_PROFILE)
            value="${target_profile}"
            ;;
          GITHUB_REPO|PROJECT_ID|PROJECT_NUMBER|PROJECT_OWNER)
            value=""
            ;;
          DAEMON_GH_PROJECT_TOKEN|CODEX_GH_PROJECT_TOKEN|GH_APP_INTERNAL_SECRET|DAEMON_GH_TOKEN|CODEX_GH_TOKEN)
            value=""
            ;;
          DAEMON_TG_BOT_TOKEN|OPS_BOT_TG_BOT_TOKEN|OPS_BOT_WEBHOOK_SECRET|OPS_BOT_TG_SECRET_TOKEN)
            value=""
            ;;
          OPS_REMOTE_STATUS_PUSH_SECRET|OPS_REMOTE_SUMMARY_PUSH_SECRET)
            value=""
            ;;
          GH_APP_PRIVATE_KEY_PATH)
            value=""
            ;;
          CODEX_STATE_DIR|FLOW_STATE_DIR)
            value=".flow/state"
            ;;
          WATCHDOG_DAEMON_LABEL)
            value="${launchd_namespace}.codex-daemon.${target_profile}"
            ;;
          WATCHDOG_DAEMON_INTERVAL_SEC)
            value="${watchdog_interval}"
            ;;
          GH_APP_PM2_APP_NAME)
            value="${target_profile}-gh-app-auth"
            ;;
          OPS_BOT_PM2_APP_NAME)
            value="${target_profile}-ops-bot"
            ;;
          OPS_REMOTE_STATUS_PUSH_SOURCE|OPS_REMOTE_SUMMARY_PUSH_SOURCE)
            value="${target_profile}"
            ;;
        esac
        printf '%s=%s\n' "$key" "$value"
        continue
      fi
      printf '%s\n' "$line"
    done < "$source_env_path"
  } > "$destination"

  rewrite_env_key "$destination" "PROJECT_PROFILE" "$target_profile"
  rewrite_env_key "$destination" "GITHUB_REPO" ""
  rewrite_env_key "$destination" "PROJECT_ID" ""
  rewrite_env_key "$destination" "PROJECT_NUMBER" ""
  rewrite_env_key "$destination" "PROJECT_OWNER" ""
  rewrite_env_key "$destination" "CODEX_STATE_DIR" ".flow/state"
  rewrite_env_key "$destination" "FLOW_STATE_DIR" ".flow/state"
  rewrite_env_key "$destination" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"
  rewrite_env_key "$destination" "WATCHDOG_DAEMON_INTERVAL_SEC" "${watchdog_interval}"
  rewrite_env_key "$destination" "GH_APP_PM2_APP_NAME" "${target_profile}-gh-app-auth"
  rewrite_env_key "$destination" "OPS_BOT_PM2_APP_NAME" "${target_profile}-ops-bot"
  rewrite_env_key "$destination" "OPS_REMOTE_STATUS_PUSH_SOURCE" "${target_profile}"
  rewrite_env_key "$destination" "OPS_REMOTE_SUMMARY_PUSH_SOURCE" "${target_profile}"
  clear_env_key "$destination" "DAEMON_GH_PROJECT_TOKEN"
  clear_env_key "$destination" "CODEX_GH_PROJECT_TOKEN"
  clear_env_key "$destination" "GH_APP_INTERNAL_SECRET"
  clear_env_key "$destination" "DAEMON_GH_TOKEN"
  clear_env_key "$destination" "CODEX_GH_TOKEN"
  clear_env_key "$destination" "DAEMON_TG_BOT_TOKEN"
  clear_env_key "$destination" "OPS_BOT_TG_BOT_TOKEN"
  clear_env_key "$destination" "OPS_BOT_WEBHOOK_SECRET"
  clear_env_key "$destination" "OPS_BOT_TG_SECRET_TOKEN"
  clear_env_key "$destination" "OPS_REMOTE_STATUS_PUSH_SECRET"
  clear_env_key "$destination" "OPS_REMOTE_SUMMARY_PUSH_SECRET"
  clear_env_key "$destination" "GH_APP_PRIVATE_KEY_PATH"

  if ! rg -q '^# Prefer interactive wizard for first setup or safe rerun:' "$destination"; then
    cat >> "$destination" <<EOF

# Prefer interactive wizard for first setup or safe rerun:
#   .flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${target_profile}
EOF
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "Missing value for --project" >&2; exit 1; }
      project="$2"
      shift 2
      ;;
    --source-profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-profile" >&2; exit 1; }
      source_profile="$2"
      shift 2
      ;;
    --defaults-from)
      [[ $# -ge 2 ]] || { echo "Missing value for --defaults-from" >&2; exit 1; }
      defaults_from="$2"
      shift 2
      ;;
    --target-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --target-repo" >&2; exit 1; }
      target_repo="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 1; }
      output_path="$2"
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

if [[ -z "$project" ]]; then
  echo "Option --project is required" >&2
  usage
  exit 1
fi

project_slug="$(slugify "$project")"
if [[ -z "$output_path" ]]; then
  output_path="${ROOT_DIR}/.flow/migration/${project_slug}-migration-kit.tgz"
fi

case "$defaults_from" in
  current|sample)
    ;;
  *)
    echo "Unknown value for --defaults-from: ${defaults_from}" >&2
    echo "Expected one of: current, sample" >&2
    exit 1
    ;;
esac

if [[ -e "$output_path" && "$force" != "1" ]]; then
  echo "Output archive already exists: ${output_path}" >&2
  echo "Use --force to overwrite it." >&2
  exit 1
fi

source_defaults_file="$(resolve_source_env_file "$project_slug" || true)"
if [[ "$defaults_from" == "current" && -n "$source_defaults_file" ]]; then
  export DAEMON_GH_ENV_FILE="$source_defaults_file"
fi

launchd_namespace="$(resolve_value "FLOW_LAUNCHD_NAMESPACE" "com.flow")"

watchdog_interval="45"
if [[ -n "$source_defaults_file" && -f "$source_defaults_file" ]]; then
  watchdog_interval="$(codex_read_key_from_env_file "$source_defaults_file" "WATCHDOG_DAEMON_INTERVAL_SEC" || true)"
fi
[[ -n "$watchdog_interval" ]] || watchdog_interval="45"
if [[ -z "$source_defaults_file" || ! -f "$source_defaults_file" ]]; then
  echo "Could not resolve source env for defaults-from=${defaults_from}." >&2
  exit 1
fi

toolkit_remote_url="$(git -C "${ROOT_DIR}/.flow/shared" remote get-url origin 2>/dev/null || true)"
toolkit_revision="$(git -C "${ROOT_DIR}/.flow/shared" rev-parse HEAD 2>/dev/null || true)"

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex_migration_kit.XXXXXX")"
cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT

mkdir -p \
  "${build_dir}/.flow/config" \
  "${build_dir}/.flow/state" \
  "${build_dir}/.flow/tmp" \
  "${build_dir}/.flow/templates/github"

cp -R "${ROOT_DIR}/.flow/shared" "${build_dir}/.flow/"
rm -rf "${build_dir}/.flow/shared/.git"
if [[ -f "${ROOT_DIR}/COMMAND_TEMPLATES.md" ]]; then
  cp "${ROOT_DIR}/COMMAND_TEMPLATES.md" "${build_dir}/COMMAND_TEMPLATES.md"
fi
if [[ -d "${ROOT_DIR}/.github/workflows" ]]; then
  mkdir -p "${build_dir}/.flow/templates/github/workflows"
  cp -R "${ROOT_DIR}/.github/workflows/." "${build_dir}/.flow/templates/github/workflows/"
fi
if [[ -f "${ROOT_DIR}/.github/pull_request_template.md" ]]; then
  cp "${ROOT_DIR}/.github/pull_request_template.md" "${build_dir}/.flow/templates/github/pull_request_template.md"
fi

touch "${build_dir}/.flow/state/.keep"
write_profile_sample_env \
  "${build_dir}/.flow/config/flow.sample.env" \
  "${source_defaults_file}" \
  "${defaults_from}" \
  "$project_slug" \
  "$watchdog_interval" \
  "$launchd_namespace"
write_repo_actions_manifest \
  "${build_dir}/.flow/templates/github/required-files.txt" \
  "${build_dir}/.flow/templates/github/required-secrets.txt"

cat > "${build_dir}/.flow/tmp/migration_kit_manifest.env" <<EOF
MIGRATION_KIT_PROJECT=${project_slug}
MIGRATION_KIT_CREATED_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
MIGRATION_KIT_DEFAULTS_SOURCE=${defaults_from}
MIGRATION_KIT_SOURCE_ENV_FILE=$(basename "${source_defaults_file:-}")
MIGRATION_KIT_PROFILE_SAMPLE_ENV=.flow/config/flow.sample.env
MIGRATION_KIT_PROFILE_ENV_TARGET=.flow/config/flow.env
MIGRATION_KIT_STATE_DIR=.flow/state
MIGRATION_KIT_TOOLKIT_DIR=.flow/shared
MIGRATION_KIT_DOC_DIR=.flow/shared/docs
MIGRATION_KIT_COMMAND_TEMPLATES=COMMAND_TEMPLATES.md
MIGRATION_KIT_TOOLKIT_MODE=submodule_snapshot
MIGRATION_KIT_TOOLKIT_SUBMODULE_URL=${toolkit_remote_url}
MIGRATION_KIT_TOOLKIT_SUBMODULE_REVISION=${toolkit_revision}
MIGRATION_KIT_REPO_ACTIONS_TEMPLATE=.flow/templates/github
MIGRATION_KIT_REPO_ACTIONS_FILES=.flow/templates/github/required-files.txt
MIGRATION_KIT_REPO_ACTIONS_SECRETS=.flow/templates/github/required-secrets.txt
EOF

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
tar -czf "$output_path" -C "$build_dir" .

target_output_path=""
if [[ -n "$target_repo" ]]; then
  target_output_path="${target_repo}/.flow/migration/${project_slug}-migration-kit.tgz"
  if [[ -e "$target_output_path" && "$force" != "1" ]]; then
    echo "Target repo archive already exists: ${target_output_path}" >&2
    echo "Use --force to overwrite it." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$target_output_path")"
  cp "$output_path" "$target_output_path"
fi

echo "MIGRATION_KIT_CREATED=${output_path}"
echo "MIGRATION_KIT_PROJECT=${project_slug}"
echo "MIGRATION_KIT_DEFAULTS_SOURCE=${defaults_from}"
if [[ -n "$source_defaults_file" ]]; then
  echo "MIGRATION_KIT_SOURCE_ENV=${source_defaults_file}"
fi
echo "MIGRATION_KIT_PROFILE_SAMPLE=.flow/config/flow.sample.env"
echo "MIGRATION_KIT_FLOW_ENV=.flow/config/flow.env"
echo "MIGRATION_KIT_REPO_ACTIONS=.flow/templates/github"
echo "MIGRATION_KIT_REPO_ACTIONS_SECRETS=.flow/templates/github/required-secrets.txt"
if [[ -n "$target_output_path" ]]; then
  echo "MIGRATION_KIT_COPIED_TO=${target_output_path}"
fi
