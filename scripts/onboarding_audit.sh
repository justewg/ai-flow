#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

profile=""
env_file=""
state_dir=""
skip_network="0"

ok_count=0
warn_count=0
fail_count=0
action_count=0
ready_override=""

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/onboarding_audit.sh [options]

Options:
  --profile <name>      Проверять project-scoped flow env и state-dir для указанного профиля.
  --env-file <path>     Явный путь к flow env-файлу.
  --state-dir <path>    Явный путь к profile state-dir.
  --skip-network        Не выполнять GitHub API / Project v2 проверки.
  -h, --help            Показать справку.

Examples:
  .flow/shared/scripts/onboarding_audit.sh
  .flow/shared/scripts/onboarding_audit.sh --profile acme
  .flow/shared/scripts/onboarding_audit.sh --profile acme --skip-network
EOF
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --env-file" >&2; exit 1; }
      env_file="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-dir" >&2; exit 1; }
      state_dir="$2"
      shift 2
      ;;
    --skip-network)
      skip_network="1"
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

if [[ -n "$profile" ]]; then
  profile_slug="$(slugify "$profile")"
  flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
  [[ -n "$env_file" ]] || env_file="$(codex_resolve_flow_env_file)"
  [[ -n "$state_dir" ]] || state_dir="${flow_state_root_dir}"
fi

if [[ -n "$env_file" ]]; then
  export DAEMON_GH_ENV_FILE="$env_file"
fi

report_ok() {
  ok_count=$((ok_count + 1))
  printf '✅ CHECK_OK %s=%s\n' "$1" "$2"
}

report_warn() {
  warn_count=$((warn_count + 1))
  printf '⚠️ CHECK_WARN %s=%s\n' "$1" "$2"
}

report_fail() {
  fail_count=$((fail_count + 1))
  printf '❌ CHECK_FAIL %s=%s\n' "$1" "$2"
}

report_action() {
  action_count=$((action_count + 1))
  printf '👉 ACTION %s=%s\n' "$1" "$2"
}

section() {
  printf '\n## %s\n' "$1"
}

check_required_file() {
  local rel_path="$1"
  local label="$2"
  local hint="$3"
  local abs_path="${ROOT_DIR}/${rel_path}"
  if [[ -f "$abs_path" ]]; then
    report_ok "$label" "$rel_path"
  else
    report_fail "$label" "missing:${rel_path}"
    report_action "$label" "$hint"
  fi
}

check_required_executable() {
  local rel_path="$1"
  local label="$2"
  local hint="$3"
  local abs_path="${ROOT_DIR}/${rel_path}"
  if [[ ! -f "$abs_path" ]]; then
    report_fail "$label" "missing:${rel_path}"
    report_action "$label" "$hint"
    return 0
  fi
  if [[ -x "$abs_path" ]]; then
    report_ok "$label" "$rel_path"
  else
    report_fail "$label" "not-executable:${rel_path}"
    report_action "$label" "Сделай файл исполняемым: chmod +x ${rel_path}"
  fi
}

check_command() {
  local cmd="$1"
  local label="$2"
  local required="$3"
  local hint="$4"
  if command -v "$cmd" >/dev/null 2>&1; then
    report_ok "$label" "$(command -v "$cmd")"
  elif [[ "$required" == "1" ]]; then
    report_fail "$label" "missing-command:${cmd}"
    report_action "$label" "$hint"
  else
    report_warn "$label" "missing-command:${cmd}"
    report_action "$label" "$hint"
  fi
}

check_optional_file() {
  local rel_path="$1"
  local label="$2"
  local hint="$3"
  local abs_path="${ROOT_DIR}/${rel_path}"
  if [[ -f "$abs_path" ]]; then
    report_ok "$label" "$rel_path"
  else
    report_warn "$label" "missing:${rel_path}"
    report_action "$label" "$hint"
  fi
}

collect_self_hosted_runner_labels() {
  local workflows_dir="${ROOT_DIR}/.github/workflows"
  [[ -d "$workflows_dir" ]] || return 0

  {
    rg -o 'REQUIRED_LABEL:[[:space:]]*[A-Za-z0-9._-]+' "$workflows_dir" --no-filename 2>/dev/null \
      | sed -E 's/^REQUIRED_LABEL:[[:space:]]*//'
    rg -o 'runs-on:[[:space:]]*\[self-hosted,[[:space:]]*[A-Za-z0-9._-]+' "$workflows_dir" --no-filename 2>/dev/null \
      | sed -E 's/^runs-on:[[:space:]]*\[self-hosted,[[:space:]]*//'
  } | sed '/^$/d' | sort -u
}

is_truthy() {
  local value="${1:-}"
  [[ "$value" =~ ^(1|true|yes|on)$ ]]
}

normalize_remote_repo() {
  local raw="$1"
  raw="${raw%.git}"
  raw="${raw#git@github.com:}"
  raw="${raw#ssh://git@github.com/}"
  raw="${raw#https://github.com/}"
  raw="${raw#http://github.com/}"
  printf '%s' "$raw"
}

read_profile_key() {
  local key="$1"
  [[ -n "$env_file" && -f "$env_file" ]] || return 1
  codex_read_key_from_env_file "$env_file" "$key"
}

read_global_key() {
  local key="$1"
  codex_try_config_value "$key" || true
}

required_repo_actions_files_manifest="${ROOT_DIR}/.flow/templates/github/required-files.txt"
required_repo_actions_secrets_manifest="${ROOT_DIR}/.flow/templates/github/required-secrets.txt"
self_hosted_runner_labels="$(collect_self_hosted_runner_labels || true)"

missing_profile_action() {
  local key="$1"
  local hint="$2"
  local project_owner_value=""
  local project_number_value=""
  local github_repo_value=""
  local project_list_cmd=""
  local project_id_cmd=""

  project_owner_value="$(read_profile_key "PROJECT_OWNER" || true)"
  project_number_value="$(read_profile_key "PROJECT_NUMBER" || true)"
  github_repo_value="$(read_profile_key "GITHUB_REPO" || true)"
  if [[ -n "$project_owner_value" ]]; then
    project_list_cmd="gh project list --owner ${project_owner_value} --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'"
  elif [[ -n "$github_repo_value" ]]; then
    project_list_cmd="gh project list --owner ${github_repo_value%%/*} --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'"
  else
    project_list_cmd="gh project list --owner <PROJECT_OWNER> --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'"
  fi
  if [[ -n "$project_owner_value" && -n "$project_number_value" ]]; then
    project_id_cmd="gh project view ${project_number_value} --owner ${project_owner_value} --format json --jq '.id'"
  else
    project_id_cmd="gh project view <PROJECT_NUMBER> --owner <PROJECT_OWNER> --format json --jq '.id'"
  fi
  case "$key" in
    PROJECT_NUMBER)
      printf '%s' "Заполни PROJECT_NUMBER в ${env_file} (${hint}). GitHub UI: открой нужный Project v2, возьми число из URL вида github.com/users/<owner>/projects/<number> или github.com/orgs/<owner>/projects/<number>."
      ;;
    PROJECT_OWNER)
      printf '%s' "Заполни PROJECT_OWNER в ${env_file} (${hint}). GitHub UI: открой нужный Project v2 и возьми owner из URL. Для user-owned project это login после /users/, для org-owned после /orgs/. Если project принадлежит owner текущего repo, можно посмотреть список так: ${project_list_cmd}"
      ;;
    PROJECT_ID)
      printf '%s' "Заполни PROJECT_ID в ${env_file} (${hint}). В обычном GitHub UI node id Project v2 не показывается. Сначала можно вывести owner/title/number/id так: ${project_list_cmd} Затем для точного значения PROJECT_ID запусти: ${project_id_cmd}"
      ;;
    DAEMON_GH_PROJECT_TOKEN)
      printf '%s' "Заполни DAEMON_GH_PROJECT_TOKEN в ${env_file} (${hint}). GitHub UI: avatar -> Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token. Базовые scopes: repo, read:project, project. Рекомендуемые дополнительные scopes для совместимости: read:org, read:discussions."
      ;;
    GITHUB_REPO)
      printf '%s' "Заполни GITHUB_REPO в ${env_file} (${hint}). GitHub UI: открой repo и возьми owner/repo из URL или блока About."
      ;;
    *)
      printf '%s' "Заполни ${key} в ${env_file} (${hint})."
      ;;
  esac
}

mask_secret() {
  local value="$1"
  local length="${#value}"
  if (( length <= 8 )); then
    printf '***'
    return 0
  fi
  printf '%s...%s' "${value:0:4}" "${value: -4}"
}

display_profile_value() {
  local key="$1"
  local value="$2"
  case "$key" in
    DAEMON_GH_PROJECT_TOKEN|DAEMON_GH_TOKEN|GH_APP_INTERNAL_SECRET)
      mask_secret "$value"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

check_profile_value() {
  local key="$1"
  local hint="$2"
  local value
  value="$(read_profile_key "$key" || true)"
  if [[ -n "$value" ]]; then
    report_ok "ENV_${key}" "$(display_profile_value "$key" "$value")"
  else
    report_fail "ENV_${key}" "missing"
    report_action "ENV_${key}" "$(missing_profile_action "$key" "$hint")"
  fi
}

project_gh() {
  local project_token="$1"
  shift
  if [[ -n "$project_token" ]]; then
    GH_TOKEN="$project_token" gh "$@"
  else
    gh "$@"
  fi
}

gh_auth_ok="0"

section "Toolkit Files"
check_required_executable ".flow/shared/scripts/run.sh" "TOOLKIT_RUN_SH" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/profile_init.sh" "TOOLKIT_PROFILE_INIT" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/onboarding_audit.sh" "TOOLKIT_ONBOARDING_AUDIT" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/create_migration_kit.sh" "TOOLKIT_CREATE_MIGRATION_KIT" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/apply_migration_kit.sh" "TOOLKIT_APPLY_MIGRATION_KIT" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/daemon_install.sh" "TOOLKIT_DAEMON_INSTALL" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/watchdog_install.sh" "TOOLKIT_WATCHDOG_INSTALL" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/gh_app_auth_token.sh" "TOOLKIT_AUTH_TOKEN" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/telegram_local_notify.sh" "TOOLKIT_TG_NOTIFY" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/ops_bot_webhook_register.sh" "TOOLKIT_OPS_WEBHOOK" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/ops_remote_status_push.sh" "TOOLKIT_OPS_REMOTE_STATUS_PUSH" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_executable ".flow/shared/scripts/ops_remote_summary_push.sh" "TOOLKIT_OPS_REMOTE_SUMMARY_PUSH" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/env/resolve_config.sh" "TOOLKIT_RESOLVE_CONFIG" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/gh_app_auth_service.js" "TOOLKIT_AUTH_SERVICE" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/gh_app_auth_pm2_ecosystem.config.cjs" "TOOLKIT_AUTH_PM2_CONFIG" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/status_snapshot.sh" "TOOLKIT_STATUS_SNAPSHOT" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/log_summary.sh" "TOOLKIT_LOG_SUMMARY" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/ops_bot_service.js" "TOOLKIT_OPS_BOT_SERVICE" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file ".flow/shared/scripts/ops_bot_pm2_ecosystem.config.cjs" "TOOLKIT_OPS_BOT_PM2_CONFIG" "Подключи shared toolkit в .flow/shared/ (submodule, локальный link или onboarding bootstrap)."
check_required_file "COMMAND_TEMPLATES.md" "COMMAND_TEMPLATES" "Перенеси COMMAND_TEMPLATES.md в корень consumer-project."
check_required_file ".flow/shared/docs/flow-onboarding-checklist.md" "DOC_ONBOARDING_CHECKLIST" "Подключи shared toolkit docs в .flow/shared/docs/."
check_required_file ".flow/shared/docs/flow-onboarding-quickstart.md" "DOC_ONBOARDING_QUICKSTART" "Подключи shared toolkit docs в .flow/shared/docs/."
check_required_file ".flow/shared/docs/flow-portability-runbook.md" "DOC_FLOW_PORTABILITY" "Подключи shared toolkit docs в .flow/shared/docs/."
check_required_file ".flow/shared/docs/gh-app-daemon-integration-plan.md" "DOC_GH_APP_PLAN" "Подключи shared toolkit docs в .flow/shared/docs/."
check_required_file ".flow/shared/docs/ops-bot-dashboard.md" "DOC_OPS_BOT_DASHBOARD" "Подключи shared toolkit docs в .flow/shared/docs/."
check_optional_file ".flow/templates/github/required-files.txt" "REPO_ACTIONS_FILES_MANIFEST" "Если переносишь repo-level workflows через migration kit, manifest должен лежать в .flow/templates/github/required-files.txt."
check_optional_file ".flow/templates/github/required-secrets.txt" "REPO_ACTIONS_SECRETS_MANIFEST" "Если переносишь repo-level workflows через migration kit, manifest обязательных Actions secrets должен лежать в .flow/templates/github/required-secrets.txt."

section "Repo Automation Overlay"
if [[ -f "$required_repo_actions_files_manifest" ]]; then
  repo_actions_required_count="0"
  repo_actions_missing_count="0"
  while IFS= read -r repo_action_rel_path; do
    [[ -n "$repo_action_rel_path" && "$repo_action_rel_path" != \#* ]] || continue
    repo_actions_required_count=$((repo_actions_required_count + 1))
    if [[ -f "${ROOT_DIR}/${repo_action_rel_path}" ]]; then
      report_ok "REPO_ACTION_FILE" "$repo_action_rel_path"
    else
      repo_actions_missing_count=$((repo_actions_missing_count + 1))
      report_warn "REPO_ACTION_FILE" "missing:${repo_action_rel_path}"
      report_action "REPO_ACTION_FILE" "Разверни repo automation overlay через .flow/shared/scripts/run.sh apply_migration_kit --project <name> или вручную восстанови ${repo_action_rel_path}."
    fi
  done < "$required_repo_actions_files_manifest"
  if [[ "$repo_actions_required_count" == "0" ]]; then
    report_warn "REPO_ACTIONS_FILES_MANIFEST" "empty"
    report_action "REPO_ACTIONS_FILES_MANIFEST" "Обнови migration kit: manifest repo workflows пуст."
  fi
  if [[ "$repo_actions_missing_count" == "0" && "$repo_actions_required_count" -gt 0 ]]; then
    report_ok "REPO_ACTIONS_OVERLAY" "all-required-files-present:${repo_actions_required_count}"
  fi
else
  if [[ -d "${ROOT_DIR}/.github/workflows" ]]; then
    repo_actions_detected_count="$(find "${ROOT_DIR}/.github/workflows" -maxdepth 1 -type f -name '*.yml' | wc -l | tr -d ' ')"
    report_ok "REPO_ACTIONS_OVERLAY" "detected-without-manifest:${repo_actions_detected_count}"
    report_action "REPO_ACTIONS_OVERLAY" "Для переносимого onboarding лучше хранить manifest обязательных workflows/secrets: пересобери migration kit свежим create_migration_kit."
  else
    report_ok "REPO_ACTIONS_OVERLAY" "not-configured(optional)"
  fi
fi

section "Local Commands"
check_command bash "CMD_BASH" "1" "Установи bash."
check_command git "CMD_GIT" "1" "Установи git."
check_command gh "CMD_GH" "1" "Установи GitHub CLI: https://cli.github.com/"
check_command jq "CMD_JQ" "1" "Установи jq."
check_command node "CMD_NODE" "1" "Установи Node.js LTS (рекомендуется >= 18)."
check_command curl "CMD_CURL" "1" "Установи curl."
service_manager="$(codex_resolve_flow_service_manager)"
report_ok "FLOW_SERVICE_MANAGER" "$service_manager"
case "$service_manager" in
  launchd)
    check_command launchctl "CMD_LAUNCHCTL" "0" "Если нужен штатный daemon/watchdog через launchd, запускай на macOS с launchctl."
    ;;
  systemd)
    check_command systemctl "CMD_SYSTEMCTL" "1" "Для Linux-hosted daemon/watchdog нужен systemctl (обычно systemd user services)."
    ;;
  *)
    report_warn "FLOW_SERVICE_MANAGER" "unsupported:${service_manager}"
    report_action "FLOW_SERVICE_MANAGER" "Укажи поддерживаемый backend: FLOW_SERVICE_MANAGER=launchd|systemd."
    ;;
esac
check_command pm2 "CMD_PM2" "0" "Если auth-service будет жить под PM2, установи pm2: npm install -g pm2"

section "Git Repository"
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  report_ok "GIT_REPO" "$ROOT_DIR"
else
  report_fail "GIT_REPO" "not-a-git-repository"
  report_action "GIT_REPO" "Инициализируй repo или клонируй consumer-project в текущую папку."
fi

origin_url=""
if origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"; then
  if [[ -n "$origin_url" ]]; then
    report_ok "GIT_REMOTE_ORIGIN" "$origin_url"
  else
    report_fail "GIT_REMOTE_ORIGIN" "missing"
    report_action "GIT_REMOTE_ORIGIN" "Добавь GitHub remote origin для нового repo."
  fi
else
  report_fail "GIT_REMOTE_ORIGIN" "missing"
  report_action "GIT_REMOTE_ORIGIN" "Добавь GitHub remote origin для нового repo."
fi

for branch_name in main development; do
  branch_label="$(printf '%s' "$branch_name" | tr '[:lower:]' '[:upper:]')"
  if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/${branch_name}" ||
    git -C "$ROOT_DIR" show-ref --verify --quiet "refs/remotes/origin/${branch_name}"; then
    report_ok "GIT_BRANCH_${branch_label}" "present"
  else
    report_fail "GIT_BRANCH_${branch_label}" "missing"
    report_action "GIT_BRANCH_${branch_label}" "Создай ветку ${branch_name} в repo и/или подтяни её локально."
  fi
done

section "GitHub CLI Auth"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    gh_auth_ok="1"
    report_ok "GH_AUTH" "authenticated"
  else
    report_fail "GH_AUTH" "not-authenticated"
    report_action "GH_AUTH" "Выполни gh auth login под аккаунтом, который видит repo и Project v2."
  fi
fi

section "Profile"
if [[ -z "$profile" && -z "$env_file" ]]; then
  ready_override="0"
  report_warn "PROFILE" "not-specified"
  report_action "PROFILE" "Для полной проверки profile/env запусти: .flow/shared/scripts/run.sh onboarding_audit --profile <name>"
elif [[ -z "$env_file" || ! -f "$env_file" ]]; then
  report_fail "PROFILE_ENV_FILE" "missing:${env_file}"
  if [[ -n "$profile" ]]; then
      report_action "PROFILE_ENV_FILE" "Создай flow env через: .flow/shared/scripts/run.sh profile_init init --profile ${profile}"
  else
    report_action "PROFILE_ENV_FILE" "Передай существующий flow env через --env-file <path> или создай его через profile_init init."
  fi
  if [[ -n "$state_dir" ]]; then
    if [[ -d "$state_dir" ]]; then
      report_ok "PROFILE_STATE_DIR" "$state_dir"
    else
      report_warn "PROFILE_STATE_DIR" "missing:${state_dir}"
      report_action "PROFILE_STATE_DIR" "Команда profile_init init создаст state-dir автоматически."
    fi
  fi
else
  report_ok "PROFILE_ENV_FILE" "$env_file"
  if [[ -n "$state_dir" ]]; then
    if [[ -d "$state_dir" ]]; then
      report_ok "PROFILE_STATE_DIR" "$state_dir"
    else
      report_warn "PROFILE_STATE_DIR" "missing:${state_dir}"
      report_action "PROFILE_STATE_DIR" "Создай state-dir через: .flow/shared/scripts/run.sh profile_init init --profile ${profile}"
    fi
  fi

  check_profile_value "GITHUB_REPO" "GitHub repo в формате owner/repo"
  check_profile_value "FLOW_BASE_BRANCH" "базовая ветка flow"
  check_profile_value "FLOW_HEAD_BRANCH" "рабочая ветка flow"
  check_profile_value "PROJECT_PROFILE" "имя profile"
  check_profile_value "PROJECT_ID" "node id Project v2"
  check_profile_value "PROJECT_NUMBER" "номер Project v2"
  check_profile_value "PROJECT_OWNER" "owner Project v2 (@me или org)"
  check_profile_value "DAEMON_GH_PROJECT_TOKEN" "PAT для Project v2 операций"
  check_profile_value "CODEX_STATE_DIR" "путь к state-dir профиля"
  check_profile_value "FLOW_STATE_DIR" "путь к state-dir профиля"
  check_profile_value "WATCHDOG_DAEMON_LABEL" "label daemon для watchdog"
  check_profile_value "WATCHDOG_DAEMON_INTERVAL_SEC" "интервал daemon для watchdog"

  auth_secret="$(read_profile_key "GH_APP_INTERNAL_SECRET" || true)"
  fallback_enabled="$(read_profile_key "DAEMON_GH_TOKEN_FALLBACK_ENABLED" || true)"
  fallback_token="$(read_profile_key "DAEMON_GH_TOKEN" || true)"

  if [[ -n "$auth_secret" ]]; then
    report_ok "ENV_GH_APP_INTERNAL_SECRET" "present"
  else
    report_warn "ENV_GH_APP_INTERNAL_SECRET" "missing"
    report_action "ENV_GH_APP_INTERNAL_SECRET" "Для штатного App auth укажи GH_APP_INTERNAL_SECRET в ${env_file}."
  fi

  if [[ "$fallback_enabled" =~ ^(1|true|yes|on)$ ]]; then
    if [[ -n "$fallback_token" ]]; then
      report_ok "ENV_DAEMON_GH_TOKEN_FALLBACK" "enabled"
      report_ok "ENV_DAEMON_GH_TOKEN" "present"
    else
      report_fail "ENV_DAEMON_GH_TOKEN" "fallback-enabled-but-token-missing"
      report_action "ENV_DAEMON_GH_TOKEN" "Если включаешь fallback, заполни DAEMON_GH_TOKEN в ${env_file}."
    fi
  else
    report_ok "ENV_DAEMON_GH_TOKEN_FALLBACK" "disabled"
  fi

  gh_app_id="$(read_global_key "GH_APP_ID")"
  gh_app_installation_id="$(read_global_key "GH_APP_INSTALLATION_ID")"
  gh_app_private_key_path="$(read_global_key "GH_APP_PRIVATE_KEY_PATH")"

  if [[ -n "$auth_secret" ]]; then
    if [[ -n "$gh_app_id" ]]; then
      report_ok "ENV_GH_APP_ID" "$gh_app_id"
    else
      report_fail "ENV_GH_APP_ID" "missing"
      report_action "ENV_GH_APP_ID" "Заполни GH_APP_ID в .env или .env.deploy consumer-project."
    fi

    if [[ -n "$gh_app_installation_id" ]]; then
      report_ok "ENV_GH_APP_INSTALLATION_ID" "$gh_app_installation_id"
    else
      report_fail "ENV_GH_APP_INSTALLATION_ID" "missing"
      report_action "ENV_GH_APP_INSTALLATION_ID" "Заполни GH_APP_INSTALLATION_ID в .env или .env.deploy consumer-project."
    fi

    if [[ -n "$gh_app_private_key_path" ]]; then
      report_ok "ENV_GH_APP_PRIVATE_KEY_PATH" "$gh_app_private_key_path"
      if [[ -f "$gh_app_private_key_path" ]]; then
        report_ok "GH_APP_PRIVATE_KEY_FILE" "$gh_app_private_key_path"
      else
        report_fail "GH_APP_PRIVATE_KEY_FILE" "missing:${gh_app_private_key_path}"
        report_action "GH_APP_PRIVATE_KEY_FILE" "Проверь путь GH_APP_PRIVATE_KEY_PATH и положи .pem вне репозитория, рекомендуемо в <HOME>/.secrets/gh-apps/codex-flow.private-key.pem."
      fi
    else
      report_fail "ENV_GH_APP_PRIVATE_KEY_PATH" "missing"
      report_action "ENV_GH_APP_PRIVATE_KEY_PATH" "Заполни GH_APP_PRIVATE_KEY_PATH в .env или .env.deploy consumer-project, рекомендуемо как <HOME>/.secrets/gh-apps/codex-flow.private-key.pem."
    fi
  fi

  gh_app_pm2_name="$(read_global_key "GH_APP_PM2_APP_NAME")"
  gh_app_pm2_use_default="$(read_global_key "GH_APP_PM2_USE_DEFAULT")"
  gh_app_bind="$(read_global_key "GH_APP_BIND")"
  gh_app_port="$(read_global_key "GH_APP_PORT")"
  daemon_gh_auth_token_url="$(read_global_key "DAEMON_GH_AUTH_TOKEN_URL")"
  auth_service_coordinates=""
  if [[ -n "$daemon_gh_auth_token_url" ]]; then
    auth_service_coordinates="$daemon_gh_auth_token_url"
  elif [[ -n "$gh_app_bind" || -n "$gh_app_port" ]]; then
    auth_service_coordinates="${gh_app_bind:-127.0.0.1}:${gh_app_port:-8787}"
  fi
  if [[ -n "$auth_secret" ]]; then
    if [[ -n "$gh_app_pm2_name" ]]; then
      report_ok "ENV_GH_APP_PM2_APP_NAME" "$gh_app_pm2_name"
    elif is_truthy "$gh_app_pm2_use_default"; then
      if [[ -n "$auth_service_coordinates" ]]; then
        report_ok "ENV_GH_APP_PM2_APP_NAME" "using-default:planka-gh-app-auth"
        report_ok "ENV_GH_APP_PM2_USE_DEFAULT" "1"
        report_ok "ENV_GH_APP_SERVICE_COORDINATES" "$auth_service_coordinates"
      else
        report_warn "ENV_GH_APP_PM2_USE_DEFAULT" "requested-but-auth-service-coordinates-missing"
        report_action "ENV_GH_APP_PM2_USE_DEFAULT" "Если используешь shared/default auth-service, укажи координаты через DAEMON_GH_AUTH_TOKEN_URL или GH_APP_BIND/GH_APP_PORT. Иначе убери GH_APP_PM2_USE_DEFAULT=1 и задай отдельный GH_APP_PM2_APP_NAME."
      fi
    elif [[ "${profile:-default}" != "default" ]]; then
      report_warn "ENV_GH_APP_PM2_APP_NAME" "using-default:planka-gh-app-auth"
      report_action "ENV_GH_APP_PM2_APP_NAME" "Если auth-service будет отдельным для этого consumer-project, задай уникальное GH_APP_PM2_APP_NAME в .env или .env.deploy. Если auth-service общий на хосте, можно оставить shared имя."
    fi
  fi

  daemon_tg_bot_token="$(read_global_key "DAEMON_TG_BOT_TOKEN")"
  [[ -n "$daemon_tg_bot_token" ]] || daemon_tg_bot_token="$(read_global_key "TG_BOT_TOKEN")"
  daemon_tg_chat_id="$(read_global_key "DAEMON_TG_CHAT_ID")"
  [[ -n "$daemon_tg_chat_id" ]] || daemon_tg_chat_id="$(read_global_key "TG_CHAT_ID")"
  if [[ -n "$daemon_tg_bot_token" && -n "$daemon_tg_chat_id" ]]; then
    report_ok "ENV_DAEMON_TG_ALERTS" "configured"
  elif [[ -n "$daemon_tg_bot_token" || -n "$daemon_tg_chat_id" ]]; then
    report_warn "ENV_DAEMON_TG_ALERTS" "partial"
    report_action "ENV_DAEMON_TG_ALERTS" "Для локальных Telegram alerts задай и token, и chat id: DAEMON_TG_BOT_TOKEN/DAEMON_TG_CHAT_ID или TG_BOT_TOKEN/TG_CHAT_ID."
  else
    report_ok "ENV_DAEMON_TG_ALERTS" "not-configured(optional)"
  fi

  ops_bot_token="$(read_global_key "OPS_BOT_TG_BOT_TOKEN")"
  [[ -n "$ops_bot_token" ]] || ops_bot_token="$daemon_tg_bot_token"
  ops_bot_public_base_url="$(read_global_key "OPS_BOT_PUBLIC_BASE_URL")"
  ops_bot_allowed_chat_ids="$(read_global_key "OPS_BOT_ALLOWED_CHAT_IDS")"
  ops_bot_pm2_name="$(read_global_key "OPS_BOT_PM2_APP_NAME")"
  ops_bot_use_default="$(read_global_key "OPS_BOT_USE_DEFAULT")"
  ops_bot_port="$(read_global_key "OPS_BOT_PORT")"
  ops_bot_bind="$(read_global_key "OPS_BOT_BIND")"
  ops_bot_webhook_secret="$(read_global_key "OPS_BOT_WEBHOOK_SECRET")"
  ops_bot_tg_secret_token="$(read_global_key "OPS_BOT_TG_SECRET_TOKEN")"
  ops_bot_local_coordinates="${ops_bot_bind:-127.0.0.1}:${ops_bot_port:-8790}"
  ops_remote_push_enabled="$(read_global_key "OPS_REMOTE_STATUS_PUSH_ENABLED")"
  ops_bot_remote_expected="0"
  if [[ -n "$ops_bot_public_base_url" || -n "$ops_bot_webhook_secret" || -n "$ops_bot_tg_secret_token" ]]; then
    ops_bot_remote_expected="1"
  fi
  if is_truthy "$ops_remote_push_enabled"; then
    ops_bot_remote_expected="1"
  fi
  if [[ -n "$ops_bot_token" || -n "$ops_bot_public_base_url" || -n "$ops_bot_allowed_chat_ids" || -n "$ops_bot_webhook_secret" || -n "$ops_bot_tg_secret_token" || -n "$ops_bot_pm2_name" || -n "$ops_bot_port" ]]; then
    report_ok "ENV_OPS_BOT" "configured-partially-or-fully"
    if [[ -n "$ops_bot_token" ]]; then
      report_ok "ENV_OPS_BOT_TG_BOT_TOKEN" "present(via fallback chain)"
    else
      report_warn "ENV_OPS_BOT_TG_BOT_TOKEN" "missing"
      report_action "ENV_OPS_BOT_TG_BOT_TOKEN" "Для ops-bot укажи OPS_BOT_TG_BOT_TOKEN или используй fallback DAEMON_TG_BOT_TOKEN/TG_BOT_TOKEN."
    fi
    if [[ -n "$ops_bot_allowed_chat_ids" ]]; then
      report_ok "ENV_OPS_BOT_ALLOWED_CHAT_IDS" "$ops_bot_allowed_chat_ids"
    else
      report_warn "ENV_OPS_BOT_ALLOWED_CHAT_IDS" "missing"
      report_action "ENV_OPS_BOT_ALLOWED_CHAT_IDS" "Для ops-bot ограничь чаты через OPS_BOT_ALLOWED_CHAT_IDS."
    fi
    if is_truthy "$ops_bot_use_default"; then
      report_ok "ENV_OPS_BOT_USE_DEFAULT" "1"
      report_ok "ENV_OPS_BOT_LOCAL_CONTOUR" "using-default-shared-service"
      report_ok "ENV_OPS_BOT_LOCAL_COORDINATES" "$ops_bot_local_coordinates"
    elif [[ -n "$ops_bot_pm2_name" || -n "$ops_bot_port" || -n "$ops_bot_bind" ]]; then
      report_ok "ENV_OPS_BOT_LOCAL_CONTOUR" "explicit-local-runtime"
      report_ok "ENV_OPS_BOT_LOCAL_COORDINATES" "$ops_bot_local_coordinates"
    fi
    if [[ -n "$ops_bot_public_base_url" ]]; then
      report_ok "ENV_OPS_BOT_PUBLIC_BASE_URL" "$ops_bot_public_base_url"
      report_ok "ENV_OPS_BOT_REMOTE_CONTOUR" "public-url-configured"
    elif [[ "$ops_bot_remote_expected" == "1" ]]; then
      report_warn "ENV_OPS_BOT_REMOTE_CONTOUR" "expected-but-public-base-url-missing"
      report_action "ENV_OPS_BOT_REMOTE_CONTOUR" "Если используешь внешний status/webhook server для ops-bot (status-page, Telegram webhook, remote ingest), укажи его URL в OPS_BOT_PUBLIC_BASE_URL."
    else
      report_ok "ENV_OPS_BOT_REMOTE_CONTOUR" "not-configured(optional-local-only)"
    fi
    if [[ -n "$ops_bot_pm2_name" ]]; then
      report_ok "ENV_OPS_BOT_PM2_APP_NAME" "$ops_bot_pm2_name"
    elif is_truthy "$ops_bot_use_default"; then
      report_ok "ENV_OPS_BOT_PM2_APP_NAME" "using-default:planka-ops-bot"
    elif [[ "${profile:-default}" != "default" ]]; then
      report_warn "ENV_OPS_BOT_PM2_APP_NAME" "using-default:planka-ops-bot"
      report_action "ENV_OPS_BOT_PM2_APP_NAME" "Если ops-bot будет отдельным для consumer-project, задай уникальное OPS_BOT_PM2_APP_NAME в .env или .env.deploy."
    fi
    if [[ -n "$ops_bot_port" ]]; then
      report_ok "ENV_OPS_BOT_PORT" "$ops_bot_port"
    elif is_truthy "$ops_bot_use_default"; then
      report_ok "ENV_OPS_BOT_PORT" "using-default:8790"
    elif [[ "${profile:-default}" != "default" ]]; then
      report_warn "ENV_OPS_BOT_PORT" "using-default:8790"
      report_action "ENV_OPS_BOT_PORT" "Если на хосте будут несколько ops-bot, задай уникальный OPS_BOT_PORT в .env или .env.deploy."
    fi
  else
    report_ok "ENV_OPS_BOT" "not-configured(optional)"
  fi

  if [[ "$ops_remote_push_enabled" =~ ^(1|true|yes|on)$ ]]; then
    ops_remote_push_url="$(read_global_key "OPS_REMOTE_STATUS_PUSH_URL")"
    ops_remote_push_secret="$(read_global_key "OPS_REMOTE_STATUS_PUSH_SECRET")"
    if [[ -n "$ops_remote_push_url" && -n "$ops_remote_push_secret" ]]; then
      report_ok "ENV_OPS_REMOTE_STATUS_PUSH" "configured"
    else
      report_warn "ENV_OPS_REMOTE_STATUS_PUSH" "partial"
      report_action "ENV_OPS_REMOTE_STATUS_PUSH" "Если включен OPS_REMOTE_STATUS_PUSH_ENABLED, заполни OPS_REMOTE_STATUS_PUSH_URL и OPS_REMOTE_STATUS_PUSH_SECRET."
    fi
  else
    report_ok "ENV_OPS_REMOTE_STATUS_PUSH" "not-configured(optional)"
  fi

  github_repo="$(read_profile_key "GITHUB_REPO" || true)"
  flow_base_branch="$(read_profile_key "FLOW_BASE_BRANCH" || true)"
  flow_head_branch="$(read_profile_key "FLOW_HEAD_BRANCH" || true)"
  project_id="$(read_profile_key "PROJECT_ID" || true)"
  project_number="$(read_profile_key "PROJECT_NUMBER" || true)"
  project_owner="$(read_profile_key "PROJECT_OWNER" || true)"
  project_token="$(read_profile_key "DAEMON_GH_PROJECT_TOKEN" || true)"

  if [[ -n "$origin_url" && -n "$github_repo" ]]; then
    normalized_origin="$(normalize_remote_repo "$origin_url")"
    if [[ "$normalized_origin" == "$github_repo" ]]; then
      report_ok "GIT_REMOTE_MATCHES_ENV" "$github_repo"
    else
      report_fail "GIT_REMOTE_MATCHES_ENV" "origin=${normalized_origin}; env=${github_repo}"
      report_action "GIT_REMOTE_MATCHES_ENV" "Сверь remote origin и GITHUB_REPO в ${env_file}."
    fi
  fi

  if [[ -n "$flow_base_branch" ]]; then
    if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/${flow_base_branch}" ||
      git -C "$ROOT_DIR" show-ref --verify --quiet "refs/remotes/origin/${flow_base_branch}"; then
      report_ok "ENV_FLOW_BASE_BRANCH_EXISTS" "$flow_base_branch"
    else
      report_fail "ENV_FLOW_BASE_BRANCH_EXISTS" "missing:${flow_base_branch}"
      report_action "ENV_FLOW_BASE_BRANCH_EXISTS" "Создай/подтяни ветку ${flow_base_branch} или поправь FLOW_BASE_BRANCH в ${env_file}."
    fi
  fi

  if [[ -n "$flow_head_branch" ]]; then
    if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/${flow_head_branch}" ||
      git -C "$ROOT_DIR" show-ref --verify --quiet "refs/remotes/origin/${flow_head_branch}"; then
      report_ok "ENV_FLOW_HEAD_BRANCH_EXISTS" "$flow_head_branch"
    else
      report_fail "ENV_FLOW_HEAD_BRANCH_EXISTS" "missing:${flow_head_branch}"
      report_action "ENV_FLOW_HEAD_BRANCH_EXISTS" "Создай/подтяни ветку ${flow_head_branch} или поправь FLOW_HEAD_BRANCH в ${env_file}."
    fi
  fi

  section "GitHub Network"
  if [[ "$skip_network" == "1" ]]; then
    report_warn "NETWORK_CHECKS" "skipped-by-flag"
  elif [[ "$gh_auth_ok" != "1" ]]; then
    report_warn "NETWORK_CHECKS" "skipped-gh-auth-missing"
  else
    if [[ -n "$github_repo" ]]; then
      repo_view_out=""
      if repo_view_out="$(gh repo view "$github_repo" --json nameWithOwner,defaultBranchRef --jq '.nameWithOwner + "\t" + (.defaultBranchRef.name // "")' 2>&1)"; then
        repo_name="${repo_view_out%%$'\t'*}"
        repo_default_branch="${repo_view_out#*$'\t'}"
        report_ok "GH_REPO_VIEW" "$repo_name"
        if [[ -n "$repo_default_branch" ]]; then
          report_ok "GH_REPO_DEFAULT_BRANCH" "$repo_default_branch"
        fi
      else
        report_fail "GH_REPO_VIEW" "$(printf '%s' "$repo_view_out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        report_action "GH_REPO_VIEW" "Проверь, что repo ${github_repo} существует и доступен через gh auth."
      fi
    fi

    if [[ -n "$project_number" && -n "$project_owner" ]]; then
      project_view_out=""
      if project_view_out="$(project_gh "$project_token" project view "$project_number" --owner "$project_owner" --format json 2>&1)"; then
        report_ok "GH_PROJECT_VIEW" "owner=${project_owner}; number=${project_number}"
        project_view_id="$(printf '%s' "$project_view_out" | jq -r '.id // empty' 2>/dev/null || true)"
        if [[ -n "$project_view_id" && -n "$project_id" ]]; then
          if [[ "$project_view_id" == "$project_id" ]]; then
            report_ok "GH_PROJECT_ID_MATCH" "$project_id"
          else
            report_fail "GH_PROJECT_ID_MATCH" "view=${project_view_id}; env=${project_id}"
            report_action "GH_PROJECT_ID_MATCH" "Сверь PROJECT_ID / PROJECT_NUMBER / PROJECT_OWNER в ${env_file}."
          fi
        fi
      else
        report_fail "GH_PROJECT_VIEW" "$(printf '%s' "$project_view_out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        report_action "GH_PROJECT_VIEW" "Проверь Project v2 binding, scopes токена и доступ owner=${project_owner}, number=${project_number}."
      fi
    fi

    if [[ -n "$github_repo" && -f "$required_repo_actions_secrets_manifest" ]]; then
      required_repo_secret_count="0"
      while IFS= read -r required_repo_secret; do
        [[ -n "$required_repo_secret" && "$required_repo_secret" != \#* ]] || continue
        required_repo_secret_count=$((required_repo_secret_count + 1))
      done < "$required_repo_actions_secrets_manifest"

      if [[ "$required_repo_secret_count" == "0" ]]; then
        report_warn "GH_REPO_ACTIONS_SECRETS_MANIFEST" "empty"
        report_action "GH_REPO_ACTIONS_SECRETS_MANIFEST" "Manifest обязательных repo Actions secrets пуст: пересобери migration kit или обнови .github/workflows."
      else
        repo_actions_secrets_out=""
        if repo_actions_secrets_out="$(gh api "repos/${github_repo}/actions/secrets?per_page=100" --jq '.secrets[].name' 2>&1)"; then
          report_ok "GH_REPO_ACTIONS_SECRETS_API" "repo=${github_repo}"
          missing_repo_secrets=""
          while IFS= read -r required_repo_secret; do
            [[ -n "$required_repo_secret" && "$required_repo_secret" != \#* ]] || continue
            if {
              if command -v rg >/dev/null 2>&1; then
                printf '%s\n' "$repo_actions_secrets_out" | rg -x --quiet "$required_repo_secret"
              else
                printf '%s\n' "$repo_actions_secrets_out" | grep -F -x -q "$required_repo_secret"
              fi
            }; then
              report_ok "GH_REPO_ACTION_SECRET" "$required_repo_secret"
            else
              missing_repo_secrets+="${required_repo_secret},"
            fi
          done < "$required_repo_actions_secrets_manifest"
          if [[ -n "$missing_repo_secrets" ]]; then
            missing_repo_secrets="${missing_repo_secrets%,}"
            report_warn "GH_REPO_ACTIONS_SECRETS" "missing:${missing_repo_secrets}"
            report_action "GH_REPO_ACTIONS_SECRETS" "Создай недостающие repo Actions secrets в GitHub UI -> Settings -> Secrets and variables -> Actions. Список expected лежит в ${required_repo_actions_secrets_manifest}. Что именно вписывать в каждый secret см. в .flow/shared/docs/github-actions-repo-secrets.md."
          else
            report_ok "GH_REPO_ACTIONS_SECRETS" "all-required-secrets-present:${required_repo_secret_count}"
          fi
        else
          report_warn "GH_REPO_ACTIONS_SECRETS_API" "$(printf '%s' "$repo_actions_secrets_out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
          report_action "GH_REPO_ACTIONS_SECRETS_API" "Проверь, что gh auth видит repo secrets API для ${github_repo}, или проверь secrets вручную в GitHub UI -> Settings -> Secrets and variables -> Actions. Что именно вписывать в каждый secret см. в .flow/shared/docs/github-actions-repo-secrets.md."
        fi
      fi
    fi

    if [[ -n "$github_repo" && -n "$self_hosted_runner_labels" ]]; then
      repo_runners_out=""
      if repo_runners_out="$(gh api "repos/${github_repo}/actions/runners?per_page=100" 2>&1)"; then
        report_ok "GH_REPO_RUNNERS_API" "repo=${github_repo}"
        while IFS= read -r expected_runner_label; do
          [[ -n "$expected_runner_label" ]] || continue
          online_runner_count="$(
            printf '%s' "$repo_runners_out" \
              | jq --arg label "$expected_runner_label" '
                  [
                    .runners[]
                    | select(.status == "online")
                    | select(any((.labels // [])[]; .name == $label))
                  ] | length
                ' 2>/dev/null || printf '0'
          )"
          if [[ "${online_runner_count}" =~ ^[0-9]+$ ]] && (( online_runner_count > 0 )); then
            report_ok "GH_REPO_SELF_HOSTED_RUNNER" "label=${expected_runner_label}; online=${online_runner_count}"
          else
            report_warn "GH_REPO_SELF_HOSTED_RUNNER" "missing-online-runner-for-label:${expected_runner_label}"
            report_action "GH_REPO_SELF_HOSTED_RUNNER" "В repo ${github_repo} зарегистрируй online self-hosted runner с label ${expected_runner_label}: GitHub UI -> Settings -> Actions -> Runners -> New self-hosted runner. Runner из другого repo сам сюда не появится; нужен отдельный repo-level runner или общий org-level runner."
          fi
        done <<EOF
${self_hosted_runner_labels}
EOF
      else
        report_warn "GH_REPO_RUNNERS_API" "$(printf '%s' "$repo_runners_out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        report_action "GH_REPO_RUNNERS_API" "Проверь self-hosted runners вручную в GitHub UI -> Settings -> Actions -> Runners. Если deploy workflow ждёт label из .github/workflows, runner должен быть зарегистрирован именно для этого repo или на уровне org."
      fi
    fi
  fi
fi

printf '\nSUMMARY ok=%d warn=%d fail=%d action=%d\n' "$ok_count" "$warn_count" "$fail_count" "$action_count"
if (( fail_count > 0 )) || [[ "$ready_override" == "0" ]]; then
  echo "READY_FOR_AUTOMATION=0"
  exit 1
fi

echo "READY_FOR_AUTOMATION=1"
