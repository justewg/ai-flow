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
include_secrets="0"
keep_project_binding="0"
force="0"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/create_migration_kit.sh --project <name> [options]

Options:
  --project <name>         Целевое имя profile для migration kit (обязательно).
  --defaults-from <mode>   Откуда брать defaults для payload flow.sample.env:
                           current (из текущего flow.env) или sample (из flow.sample.env).
  --source-profile <name>  Legacy profile-источник для defaults-from=current.
  --target-repo <path>     Путь к новому repo (обязательно): в
                           <target-repo>/.flow/migration/ будут записаны
                           migration.conf, README.md, do_migration.sh и payload archive.
  --output <path>          Явный путь итогового payload archive. По умолчанию:
                           ./.flow/migration/<project>-migration-kit.tgz
  --include-secrets        Для payload flow.env переносить секреты из current source env.
  --keep-project-binding   Сохранить source values для GITHUB_REPO и PROJECT_*.
                           По умолчанию migration kit очищает project binding,
                           чтобы target repo был донастроен отдельно.
  --force                  Перезаписать существующий archive и migration artifacts.
  -h, --help               Показать справку.

Examples:
  .flow/shared/scripts/create_migration_kit.sh --project acme --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from sample --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from current --include-secrets --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from current --keep-project-binding --target-repo <HOME>/sites/acme-app
  .flow/shared/scripts/create_migration_kit.sh --project acme --defaults-from current --source-profile planka --target-repo <HOME>/sites/acme-app --output /tmp/acme_kit.tgz
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

write_profile_env_from_source() {
  local destination="$1"
  local source_env_path="$2"
  local defaults_mode="$3"
  local target_profile="$4"
  local watchdog_interval="$5"
  local launchd_namespace="$6"
  local preserve_secrets="$7"
  local comment_mode="$8"
  local clear_project_binding="${9:-0}"
  local line=""
  local key=""
  local value=""
  local source_label=""
  local secret_notice=""
  local ai_flow_logs_root_dir=""
  local -a sensitive_keys=(
    DAEMON_GH_PROJECT_TOKEN
    CODEX_GH_PROJECT_TOKEN
    GH_APP_INTERNAL_SECRET
    DAEMON_GH_TOKEN
    CODEX_GH_TOKEN
    DAEMON_TG_BOT_TOKEN
    OPS_BOT_TG_BOT_TOKEN
    OPS_BOT_WEBHOOK_SECRET
    OPS_BOT_TG_SECRET_TOKEN
    OPS_REMOTE_STATUS_PUSH_SECRET
    OPS_REMOTE_SUMMARY_PUSH_SECRET
  )

  if [[ "$defaults_mode" == "sample" ]]; then
    source_label="flow.sample.env"
  else
    source_label="flow.env"
  fi
  if [[ "$preserve_secrets" == "1" ]]; then
    secret_notice="# This file may contain live secrets from the source project."
  else
    secret_notice="# This file intentionally contains no live secrets from the source project."
  fi
  ai_flow_logs_root_dir="$(codex_resolve_ai_flow_logs_root_dir)"

  {
    cat <<EOF
# Generated by .flow/shared/scripts/create_migration_kit.sh for profile ${target_profile}
# Defaults source: ${source_label}
# Mode: ${comment_mode}
${secret_notice}

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
            if [[ "$clear_project_binding" == "1" ]]; then
              value=""
            fi
            ;;
          CODEX_STATE_DIR|FLOW_STATE_DIR)
            value=".flow/state"
            ;;
          FLOW_LOGS_DIR)
            value="${ai_flow_logs_root_dir}/${target_profile}"
            ;;
          FLOW_RUNTIME_LOG_DIR)
            value="${ai_flow_logs_root_dir}/${target_profile}/runtime"
            ;;
          FLOW_PM2_LOG_DIR)
            value="${ai_flow_logs_root_dir}/${target_profile}/pm2"
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

        if [[ "$preserve_secrets" != "1" ]]; then
          for sensitive_key in "${sensitive_keys[@]}"; do
            if [[ "$key" == "$sensitive_key" ]]; then
              value=""
              break
            fi
          done
        fi

        printf '%s=%s\n' "$key" "$value"
        continue
      fi
      printf '%s\n' "$line"
    done < "$source_env_path"
  } > "$destination"

  rewrite_env_key "$destination" "PROJECT_PROFILE" "$target_profile"
  rewrite_env_key "$destination" "CODEX_STATE_DIR" ".flow/state"
  rewrite_env_key "$destination" "FLOW_STATE_DIR" ".flow/state"
  rewrite_env_key "$destination" "FLOW_LOGS_DIR" "${ai_flow_logs_root_dir}/${target_profile}"
  rewrite_env_key "$destination" "FLOW_RUNTIME_LOG_DIR" "${ai_flow_logs_root_dir}/${target_profile}/runtime"
  rewrite_env_key "$destination" "FLOW_PM2_LOG_DIR" "${ai_flow_logs_root_dir}/${target_profile}/pm2"
  rewrite_env_key "$destination" "WATCHDOG_DAEMON_LABEL" "${launchd_namespace}.codex-daemon.${target_profile}"
  rewrite_env_key "$destination" "WATCHDOG_DAEMON_INTERVAL_SEC" "${watchdog_interval}"
  rewrite_env_key "$destination" "GH_APP_PM2_APP_NAME" "${target_profile}-gh-app-auth"
  rewrite_env_key "$destination" "OPS_BOT_PM2_APP_NAME" "${target_profile}-ops-bot"
  rewrite_env_key "$destination" "OPS_REMOTE_STATUS_PUSH_SOURCE" "${target_profile}"
  rewrite_env_key "$destination" "OPS_REMOTE_SUMMARY_PUSH_SOURCE" "${target_profile}"
  if [[ "$clear_project_binding" == "1" ]]; then
    clear_env_key "$destination" "GITHUB_REPO"
    clear_env_key "$destination" "PROJECT_ID"
    clear_env_key "$destination" "PROJECT_NUMBER"
    clear_env_key "$destination" "PROJECT_OWNER"
  fi
  if [[ "$preserve_secrets" != "1" ]]; then
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
  fi
}

write_migration_config() {
  local destination="$1"
  local project_slug="$2"
  local archive_rel="$3"
  local toolkit_url="$4"
  local toolkit_ref="$5"
  local defaults_mode="$6"
  local include_secrets_mode="$7"
  local project_binding_mode="$8"

  cat > "$destination" <<EOF
# Generated by .flow/shared/scripts/create_migration_kit.sh
MIGRATION_PROJECT=${project_slug}
MIGRATION_PAYLOAD_ARCHIVE_REL=${archive_rel}
MIGRATION_TOOLKIT_REPO_URL=${toolkit_url}
MIGRATION_TOOLKIT_REF=${toolkit_ref}
MIGRATION_TOOLKIT_PATH=.flow/shared
MIGRATION_DEFAULTS_SOURCE=${defaults_mode}
MIGRATION_INCLUDE_SECRETS=${include_secrets_mode}
MIGRATION_PROJECT_BINDING_MODE=${project_binding_mode}
EOF
}

write_migration_readme() {
  local destination="$1"
  local project_slug="$2"
  local archive_filename="$3"
  local project_binding_mode="$4"
  local binding_note=""
  local binding_steps=""

  if [[ "$project_binding_mode" == "keep" ]]; then
    binding_note="- source binding для \`GITHUB_REPO\` и \`PROJECT_*\` сохранён как explicit override"
    binding_steps=$(cat <<EOF
1. Сразу проверь, что \`GITHUB_REPO\` и \`PROJECT_*\` действительно должны остаться от source-проекта.
2. При необходимости перезапусти wizard:
   \`.flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${project_slug}\`
3. Затем запусти orchestration:
   \`.flow/shared/scripts/run.sh profile_init orchestrate --profile ${project_slug}\`
EOF
)
  else
    binding_note="- source binding для \`GITHUB_REPO\` и \`PROJECT_*\` очищен intentionally"
    binding_steps=$(cat <<EOF
1. Обязательно перенастрой \`GITHUB_REPO\` и \`PROJECT_*\` через wizard:
   \`.flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${project_slug}\`
2. Затем запусти orchestration:
   \`.flow/shared/scripts/run.sh profile_init orchestrate --profile ${project_slug}\`
EOF
)
  fi

  cat > "$destination" <<EOF
# Migration Kit

Для проекта \`${project_slug}\` уже подготовлен migration payload.

Что лежит рядом:
- \`${archive_filename}\` — payload archive проекта без toolkit
- \`migration.conf\` — конфигурация bootstrap-а
- \`do_migration.sh\` — launcher миграции
- project binding mode: \`${project_binding_mode}\`
${binding_note}

Что делать в новом проекте:
1. Перейти в \`.flow/migration/\`
2. Запустить:
   \`./do_migration.sh\`

Что сделает launcher:
1. Поднимет toolkit \`/.flow/shared\` из \`ai-flow\` по repo/ref из \`migration.conf\`
2. Запустит \`apply_migration_kit\` из toolkit
3. Передаст payload archive проекта
4. Сохранит \`migration.conf\` в \`.flow/config/migration.conf\`
5. Материализует \`.flow/config/flow.env\`, \`.flow/config/flow.sample.env\`, \`.flow/templates/github/*\` и repo overlay

После завершения:
${binding_steps}
EOF
}

write_migration_launcher() {
  local destination="$1"
  cat > "$destination" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/migration.conf"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[migration] migration.conf not found: ${CONFIG_PATH}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_PATH"
set +a

PAYLOAD_ARCHIVE_REL="${MIGRATION_PAYLOAD_ARCHIVE_REL:-.flow/migration/migration-kit.tgz}"
PAYLOAD_ARCHIVE_PATH="${REPO_ROOT}/${PAYLOAD_ARCHIVE_REL#./}"
TOOLKIT_PATH_REL="${MIGRATION_TOOLKIT_PATH:-.flow/shared}"
TOOLKIT_PATH="${REPO_ROOT}/${TOOLKIT_PATH_REL#./}"
TOOLKIT_URL="${MIGRATION_TOOLKIT_REPO_URL:-}"
TOOLKIT_REF="${MIGRATION_TOOLKIT_REF:-main}"
APPLY_SCRIPT="${TOOLKIT_PATH}/scripts/apply_migration_kit.sh"

if [[ -z "$TOOLKIT_URL" ]]; then
  echo "[migration] MIGRATION_TOOLKIT_REPO_URL is empty" >&2
  exit 1
fi
if [[ ! -f "$PAYLOAD_ARCHIVE_PATH" ]]; then
  echo "[migration] payload archive not found: ${PAYLOAD_ARCHIVE_PATH}" >&2
  exit 1
fi

bootstrap_toolkit() {
  local toolkit_parent
  toolkit_parent="$(dirname "$TOOLKIT_PATH")"
  mkdir -p "$toolkit_parent"

  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -d "$TOOLKIT_PATH/.git" || -f "$TOOLKIT_PATH/.git" ]]; then
      :
    elif git -C "$REPO_ROOT" config -f .gitmodules --get "submodule.${TOOLKIT_PATH_REL}.url" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" submodule sync -- "$TOOLKIT_PATH_REL" || true
      git -C "$REPO_ROOT" submodule update --init -- "$TOOLKIT_PATH_REL"
    else
      git -C "$REPO_ROOT" submodule add "$TOOLKIT_URL" "$TOOLKIT_PATH_REL" >/dev/null 2>&1 || git clone "$TOOLKIT_URL" "$TOOLKIT_PATH"
    fi
  elif [[ ! -d "$TOOLKIT_PATH/.git" && ! -f "$TOOLKIT_PATH/.git" ]]; then
    git clone "$TOOLKIT_URL" "$TOOLKIT_PATH"
  fi

  if [[ ! -d "$TOOLKIT_PATH" ]]; then
    echo "[migration] toolkit path not found after bootstrap: ${TOOLKIT_PATH}" >&2
    exit 1
  fi

  git -C "$TOOLKIT_PATH" fetch origin "$TOOLKIT_REF" >/dev/null 2>&1 || true
  git -C "$TOOLKIT_PATH" checkout "$TOOLKIT_REF" >/dev/null 2>&1
}

echo "[migration] step 1/3 bootstrapping toolkit ${TOOLKIT_URL} @ ${TOOLKIT_REF}"
bootstrap_toolkit

if [[ ! -x "$APPLY_SCRIPT" ]]; then
  echo "[migration] apply script not found: ${APPLY_SCRIPT}" >&2
  exit 1
fi

echo "[migration] step 2/3 applying payload archive ${PAYLOAD_ARCHIVE_REL}"
echo "[migration] step 3/3 apply script will materialize flow config and repo overlay"
exec "$APPLY_SCRIPT" --project "${MIGRATION_PROJECT:-}" --migration-config "$CONFIG_PATH" --payload-archive "$PAYLOAD_ARCHIVE_PATH" "$@"
EOF
  chmod +x "$destination"
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
    --include-secrets)
      include_secrets="1"
      shift
      ;;
    --keep-project-binding)
      keep_project_binding="1"
      shift
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
if [[ -z "$target_repo" ]]; then
  echo "Option --target-repo is required" >&2
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

project_binding_mode="clear"
flow_env_clear_project_binding="1"
if [[ "$keep_project_binding" == "1" ]]; then
  project_binding_mode="keep"
  flow_env_clear_project_binding="0"
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
if [[ -z "$toolkit_remote_url" || -z "$toolkit_revision" ]]; then
  echo "Could not resolve toolkit repo/ref from .flow/shared" >&2
  exit 1
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex_migration_payload.XXXXXX")"
cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT

mkdir -p \
  "${build_dir}/.flow/config" \
  "${build_dir}/.flow/templates/github" \
  "${build_dir}/.flow/github"

write_profile_env_from_source \
  "${build_dir}/.flow/config/flow.sample.env" \
  "${source_defaults_file}" \
  "${defaults_from}" \
  "$project_slug" \
  "$watchdog_interval" \
  "$launchd_namespace" \
  "0" \
  "payload-flow-sample" \
  "1"

write_profile_env_from_source \
  "${build_dir}/.flow/config/flow.env" \
  "${source_defaults_file}" \
  "${defaults_from}" \
  "$project_slug" \
  "$watchdog_interval" \
  "$launchd_namespace" \
  "$include_secrets" \
  "payload-flow-env" \
  "$flow_env_clear_project_binding"

write_repo_actions_manifest \
  "${build_dir}/.flow/templates/github/required-files.txt" \
  "${build_dir}/.flow/templates/github/required-secrets.txt"

if [[ -d "${ROOT_DIR}/.github/workflows" ]]; then
  mkdir -p "${build_dir}/.flow/github/workflows"
  cp -R "${ROOT_DIR}/.github/workflows/." "${build_dir}/.flow/github/workflows/"
fi
if [[ -f "${ROOT_DIR}/.github/pull_request_template.md" ]]; then
  cp "${ROOT_DIR}/.github/pull_request_template.md" "${build_dir}/.flow/github/pull_request_template.md"
fi

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
tar -czf "$output_path" -C "$build_dir" .

target_migration_dir="${target_repo}/.flow/migration"
target_archive_path="${target_migration_dir}/${project_slug}-migration-kit.tgz"
target_config_path="${target_migration_dir}/migration.conf"
target_readme_path="${target_migration_dir}/README.md"
target_launcher_path="${target_migration_dir}/do_migration.sh"
target_archive_rel=".flow/migration/${project_slug}-migration-kit.tgz"

for target_path in "$target_archive_path" "$target_config_path" "$target_readme_path" "$target_launcher_path"; do
  if [[ -e "$target_path" && "$force" != "1" ]]; then
    echo "Target migration artifact already exists: ${target_path}" >&2
    echo "Use --force to overwrite it." >&2
    exit 1
  fi
done

mkdir -p "$target_migration_dir"
cp "$output_path" "$target_archive_path"
write_migration_config \
  "$target_config_path" \
  "$project_slug" \
  "$target_archive_rel" \
  "$toolkit_remote_url" \
  "$toolkit_revision" \
  "$defaults_from" \
  "$include_secrets" \
  "$project_binding_mode"
write_migration_readme \
  "$target_readme_path" \
  "$project_slug" \
  "$(basename "$target_archive_path")" \
  "$project_binding_mode"
write_migration_launcher "$target_launcher_path"

echo "MIGRATION_KIT_CREATED=${output_path}"
echo "MIGRATION_KIT_PROJECT=${project_slug}"
echo "MIGRATION_KIT_DEFAULTS_SOURCE=${defaults_from}"
echo "MIGRATION_KIT_INCLUDE_SECRETS=${include_secrets}"
echo "MIGRATION_KIT_PROJECT_BINDING_MODE=${project_binding_mode}"
echo "MIGRATION_KIT_TARGET_REPO=${target_repo}"
echo "MIGRATION_KIT_TARGET_ARCHIVE=${target_archive_path}"
echo "MIGRATION_KIT_TARGET_CONFIG=${target_config_path}"
echo "MIGRATION_KIT_TARGET_README=${target_readme_path}"
echo "MIGRATION_KIT_TARGET_LAUNCHER=${target_launcher_path}"
if [[ -n "$source_defaults_file" ]]; then
  echo "MIGRATION_KIT_SOURCE_ENV=${source_defaults_file}"
fi
if [[ "$project_binding_mode" == "clear" ]]; then
  echo "NEXT_BINDING_STEP=Target flow.env will have empty GITHUB_REPO and PROJECT_*; reconfigure them in the new repo."
else
  echo "NEXT_BINDING_STEP=Source GITHUB_REPO and PROJECT_* were preserved; verify they still point to the intended target."
fi
echo "NEXT_STEP=cd ${target_migration_dir} && ./do_migration.sh"
