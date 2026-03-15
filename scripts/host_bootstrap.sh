#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

profile=""
runtime_user="${USER:-$(id -un)}"
ai_flow_root="/var/sites/.ai-flow"
workspace_repo_url=""
workspace_ref="development"
workspace_path=""
host_env_file=""
platform_env_file=""
source_flow_env=""
toolkit_repo_url=""
toolkit_ref="main"
run_questionnaire="ask"
run_audit="ask"
run_install="ask"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/host_bootstrap.sh [options]

Bootstrap Linux-hosted flow runtime on a server:
- creates host-level .ai-flow layout;
- clones or updates authoritative automation workspace;
- prepares host-local flow env outside deploy snapshots;
- optionally runs questionnaire, onboarding audit, and service install.

Options:
  --profile <name>             Project profile (example: acme).
  --runtime-user <user>        Linux user owning automation runtime. Default: current user.
  --ai-flow-root <path>        Host root for config/state/logs/workspaces. Default: /var/sites/.ai-flow
  --workspace-repo <url>       Consumer repo URL to clone into authoritative workspace.
  --workspace-ref <ref>        Git ref for workspace checkout. Default: development
  --workspace-path <path>      Workspace path. Default: <ai-flow-root>/workspaces/<profile>
  --host-env-file <path>       Host-local flow env path. Default: <ai-flow-root>/config/<profile>.flow.env
  --platform-env-file <path>   Host-level ai-flow env path. Default: <ai-flow-root>/config/ai-flow.platform.env
  --source-flow-env <path>     Optional existing flow.env to copy before Linux normalization.
  --toolkit-repo <url>         ai-flow repo URL. Default: current origin or https://github.com/justewg/ai-flow.git
  --toolkit-ref <ref>          ai-flow ref for bootstrap. Default: main
  --questionnaire <ask|yes|no> Run flow_configurator questionnaire. Default: ask
  --audit <ask|yes|no>         Run onboarding_audit after bootstrap. Default: ask
  --install <ask|yes|no>       Run profile_init install after bootstrap. Default: ask
  -h, --help                   Show help.

Examples:
  .flow/shared/scripts/host_bootstrap.sh --profile acme --workspace-repo https://github.com/example/acme.git
  bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-host-init.sh) --profile acme
EOF
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="project"
  printf '%s' "$value"
}

expand_path() {
  local value="${1:-}"
  case "$value" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${value#~/}" ;;
    *) printf '%s' "$value" ;;
  esac
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

normalize_repo_url() {
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

current_toolkit_origin() {
  git -C "$(cd "${SCRIPT_DIR}/.." && pwd)" remote get-url origin 2>/dev/null || true
}

existing_workspace_origin() {
  local workspace_dir="${1:-}"
  if [[ -d "${workspace_dir}/.git" ]]; then
    git -C "$workspace_dir" remote get-url origin 2>/dev/null || true
  fi
}

current_user() {
  id -un
}

runtime_group() {
  id -gn "$runtime_user"
}

run_as_runtime_user() {
  if [[ "$(current_user)" == "$runtime_user" ]]; then
    "$@"
  else
    sudo -u "$runtime_user" -- "$@"
  fi
}

run_env_as_runtime_user() {
  if [[ "$(current_user)" == "$runtime_user" ]]; then
    env "$@"
  else
    sudo -u "$runtime_user" -- env "$@"
  fi
}

ensure_dir_owned() {
  local dir_path="$1"
  local owner_group
  owner_group="$(runtime_group)"

  if mkdir -p "$dir_path" 2>/dev/null; then
    :
  else
    sudo mkdir -p "$dir_path"
  fi

  if chown "$runtime_user:$owner_group" "$dir_path" 2>/dev/null; then
    :
  else
    sudo chown "$runtime_user:$owner_group" "$dir_path"
  fi
}

ensure_host_layout() {
  ensure_dir_owned "$ai_flow_root"
  ensure_dir_owned "${ai_flow_root}/config"
  ensure_dir_owned "${ai_flow_root}/logs"
  ensure_dir_owned "${ai_flow_root}/state"
  ensure_dir_owned "${ai_flow_root}/systemd"
  ensure_dir_owned "${ai_flow_root}/workspaces"
}

has_tty() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

prompt_value() {
  local prompt_text="$1"
  local default_value="${2:-}"
  local allow_empty="${3:-0}"
  local answer=""

  if ! has_tty; then
    if [[ -n "$default_value" || "$allow_empty" == "1" ]]; then
      printf '%s' "$default_value"
      return 0
    fi
    echo "Interactive input required: ${prompt_text}" >&2
    exit 1
  fi

  if [[ -n "$default_value" ]]; then
    printf '%s [%s]: ' "$prompt_text" "$default_value" > /dev/tty
  else
    printf '%s: ' "$prompt_text" > /dev/tty
  fi
  IFS= read -r answer < /dev/tty || true
  if [[ -z "$answer" ]]; then
    answer="$default_value"
  fi
  if [[ -z "$answer" && "$allow_empty" != "1" ]]; then
    echo "Value is required." > /dev/tty
    prompt_value "$prompt_text" "$default_value" "$allow_empty"
    return 0
  fi
  printf '%s' "$answer"
}

prompt_choice() {
  local prompt_text="$1"
  local default_value="$2"
  local answer=""

  if ! has_tty; then
    printf '%s' "$default_value"
    return 0
  fi

  while true; do
    printf '%s [%s]: ' "$prompt_text" "$default_value" > /dev/tty
    IFS= read -r answer < /dev/tty || true
    answer="$(printf '%s' "${answer:-$default_value}" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      ask|yes|no|y|n)
        case "$answer" in
          y) printf '%s' "yes" ;;
          n) printf '%s' "no" ;;
          *) printf '%s' "$answer" ;;
        esac
        return 0
        ;;
    esac
    echo "Expected one of: ask, yes, no." > /dev/tty
  done
}

should_run_step() {
  local mode="$1"
  local prompt_text="$2"
  case "$mode" in
    yes) return 0 ;;
    no) return 1 ;;
    ask)
      if ! has_tty; then
        return 1
      fi
      [[ "$(prompt_choice "$prompt_text" "yes")" == "yes" ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

clone_or_update_workspace() {
  ensure_dir_owned "$(dirname "$workspace_path")"

  if [[ -d "${workspace_path}/.git" ]]; then
    run_as_runtime_user git -C "$workspace_path" fetch origin
    run_as_runtime_user git -C "$workspace_path" checkout "$workspace_ref"
    run_as_runtime_user git -C "$workspace_path" pull --ff-only origin "$workspace_ref"
  else
    run_as_runtime_user git clone --branch "$workspace_ref" "$workspace_repo_url" "$workspace_path"
  fi

  if [[ -n "$toolkit_repo_url" ]] && run_as_runtime_user git -C "$workspace_path" config -f .gitmodules --get "submodule..flow/shared.url" >/dev/null 2>&1; then
    run_as_runtime_user git -C "$workspace_path" config -f .gitmodules submodule..flow/shared.url "$toolkit_repo_url"
  fi

  run_as_runtime_user git -C "$workspace_path" submodule sync --recursive
  run_as_runtime_user git -C "$workspace_path" submodule update --init --recursive
}

upsert_env_key() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  if [[ -f "$file_path" ]]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { updated = 0 }
      $0 ~ "^" key "=" {
        print key "=" value
        updated = 1
        next
      }
      { print }
      END {
        if (updated == 0) {
          print key "=" value
        }
      }
    ' "$file_path" > "$tmp_file"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp_file"
  fi

  mv "$tmp_file" "$file_path"
}

remove_env_key() {
  local file_path="$1"
  local key="$2"
  local tmp_file
  [[ -f "$file_path" ]] || return 0
  tmp_file="$(mktemp)"
  awk -v key="$key" '$0 !~ "^" key "=" { print }' "$file_path" > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

normalize_host_env() {
  local state_dir logs_dir runtime_logs_dir pm2_logs_dir
  state_dir="${ai_flow_root}/state/${profile}"
  logs_dir="${ai_flow_root}/logs/${profile}"
  runtime_logs_dir="${logs_dir}/runtime"
  pm2_logs_dir="${logs_dir}/pm2"

  ensure_dir_owned "$(dirname "$host_env_file")"

  if [[ -n "$source_flow_env" ]]; then
    cp "$source_flow_env" "$host_env_file"
  elif [[ ! -f "$host_env_file" ]]; then
    run_env_as_runtime_user \
      ROOT_DIR="$workspace_path" \
      AI_FLOW_ROOT_DIR="$ai_flow_root" \
      FLOW_SERVICE_MANAGER=systemd \
      FLOW_SYSTEMD_SCOPE=user \
      "${workspace_path}/.flow/shared/scripts/profile_init.sh" init \
      --profile "$profile" \
      --env-file "$host_env_file" \
      --state-dir "$state_dir"
  fi

  upsert_env_key "$host_env_file" "PROJECT_PROFILE" "$profile"
  upsert_env_key "$host_env_file" "AI_FLOW_ROOT_DIR" "$ai_flow_root"
  upsert_env_key "$host_env_file" "FLOW_SERVICE_MANAGER" "systemd"
  upsert_env_key "$host_env_file" "FLOW_SYSTEMD_SCOPE" "user"
  upsert_env_key "$host_env_file" "CODEX_STATE_DIR" "$state_dir"
  upsert_env_key "$host_env_file" "FLOW_STATE_DIR" "$state_dir"
  upsert_env_key "$host_env_file" "FLOW_LOGS_DIR" "$logs_dir"
  upsert_env_key "$host_env_file" "FLOW_RUNTIME_LOG_DIR" "$runtime_logs_dir"
  upsert_env_key "$host_env_file" "FLOW_PM2_LOG_DIR" "$pm2_logs_dir"

  remove_env_key "$host_env_file" "FLOW_LAUNCHAGENTS_DIR"
  remove_env_key "$host_env_file" "FLOW_LAUNCHD_DIR"
  chown "$runtime_user:$(runtime_group)" "$host_env_file" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "$host_env_file"
}

ensure_platform_env() {
  ensure_dir_owned "$(dirname "$platform_env_file")"
  if [[ ! -f "$platform_env_file" ]]; then
    : > "$platform_env_file"
  fi
  upsert_env_key "$platform_env_file" "AI_FLOW_ROOT_DIR" "$ai_flow_root"
  upsert_env_key "$platform_env_file" "GH_APP_PM2_APP_NAME" "ai-flow-gh-app-auth"
  upsert_env_key "$platform_env_file" "OPS_BOT_PM2_APP_NAME" "ai-flow-ops-bot"
  chown "$runtime_user:$(runtime_group)" "$platform_env_file" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "$platform_env_file"
}

ensure_workspace_env_symlink() {
  local workspace_env_link="${workspace_path}/.flow/config/flow.env"
  run_as_runtime_user mkdir -p "${workspace_path}/.flow/config"
  if [[ -e "$workspace_env_link" && ! -L "$workspace_env_link" ]]; then
    run_as_runtime_user cp "$workspace_env_link" "${workspace_env_link}.bak.$(date +%s)"
    run_as_runtime_user rm -f "$workspace_env_link"
  fi
  run_as_runtime_user ln -sfn "$host_env_file" "$workspace_env_link"
}

run_questionnaire_if_requested() {
  should_run_step "$run_questionnaire" "Запустить flow_configurator questionnaire сейчас?" || return 0
  run_env_as_runtime_user \
    ROOT_DIR="$workspace_path" \
    AI_FLOW_ROOT_DIR="$ai_flow_root" \
    DAEMON_GH_ENV_FILE="$host_env_file" \
    FLOW_SERVICE_MANAGER=systemd \
    FLOW_SYSTEMD_SCOPE=user \
    "${workspace_path}/.flow/shared/scripts/run.sh" flow_configurator questionnaire --profile "$profile" < /dev/tty > /dev/tty 2>&1
}

run_audit_if_requested() {
  should_run_step "$run_audit" "Запустить onboarding_audit сейчас?" || return 0
  run_env_as_runtime_user \
    ROOT_DIR="$workspace_path" \
    AI_FLOW_ROOT_DIR="$ai_flow_root" \
    DAEMON_GH_ENV_FILE="$host_env_file" \
    FLOW_SERVICE_MANAGER=systemd \
    FLOW_SYSTEMD_SCOPE=user \
    "${workspace_path}/.flow/shared/scripts/run.sh" onboarding_audit --profile "$profile" < /dev/tty > /dev/tty 2>&1
}

run_install_if_requested() {
  should_run_step "$run_install" "Установить daemon/watchdog сейчас?" || return 0
  run_env_as_runtime_user \
    ROOT_DIR="$workspace_path" \
    AI_FLOW_ROOT_DIR="$ai_flow_root" \
    DAEMON_GH_ENV_FILE="$host_env_file" \
    FLOW_SERVICE_MANAGER=systemd \
    FLOW_SYSTEMD_SCOPE=user \
    "${workspace_path}/.flow/shared/scripts/run.sh" profile_init install --profile "$profile" < /dev/tty > /dev/tty 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --runtime-user)
      [[ $# -ge 2 ]] || { echo "Missing value for --runtime-user" >&2; exit 1; }
      runtime_user="$2"
      shift 2
      ;;
    --ai-flow-root)
      [[ $# -ge 2 ]] || { echo "Missing value for --ai-flow-root" >&2; exit 1; }
      ai_flow_root="$2"
      shift 2
      ;;
    --workspace-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --workspace-repo" >&2; exit 1; }
      workspace_repo_url="$2"
      shift 2
      ;;
    --workspace-ref)
      [[ $# -ge 2 ]] || { echo "Missing value for --workspace-ref" >&2; exit 1; }
      workspace_ref="$2"
      shift 2
      ;;
    --workspace-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --workspace-path" >&2; exit 1; }
      workspace_path="$2"
      shift 2
      ;;
    --host-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --host-env-file" >&2; exit 1; }
      host_env_file="$2"
      shift 2
      ;;
    --platform-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform-env-file" >&2; exit 1; }
      platform_env_file="$2"
      shift 2
      ;;
    --source-flow-env)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-flow-env" >&2; exit 1; }
      source_flow_env="$2"
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
    --questionnaire)
      [[ $# -ge 2 ]] || { echo "Missing value for --questionnaire" >&2; exit 1; }
      run_questionnaire="$2"
      shift 2
      ;;
    --audit)
      [[ $# -ge 2 ]] || { echo "Missing value for --audit" >&2; exit 1; }
      run_audit="$2"
      shift 2
      ;;
    --install)
      [[ $# -ge 2 ]] || { echo "Missing value for --install" >&2; exit 1; }
      run_install="$2"
      shift 2
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

if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="$(current_toolkit_origin)"
fi
if [[ -z "$toolkit_repo_url" ]]; then
  toolkit_repo_url="https://github.com/justewg/ai-flow.git"
fi

if [[ -z "$profile" ]]; then
  profile="$(prompt_value "Project profile" "acme" "0")"
fi
profile="$(slugify "$profile")"

runtime_user="$(prompt_value "Runtime user" "$runtime_user" "0")"
ai_flow_root="$(expand_path "$(prompt_value "AI flow root" "$ai_flow_root" "0")")"
workspace_ref="$(prompt_value "Workspace git ref" "$workspace_ref" "0")"
if [[ -z "$workspace_path" ]]; then
  workspace_path="${ai_flow_root}/workspaces/${profile}"
fi
workspace_path="$(expand_path "$(prompt_value "Workspace path" "$workspace_path" "0")")"
workspace_repo_url="$(normalize_repo_url "$(prompt_value "Workspace repo URL" "${workspace_repo_url:-$(existing_workspace_origin "$workspace_path")}" "0")")"
if [[ -z "$host_env_file" ]]; then
  host_env_file="${ai_flow_root}/config/${profile}.flow.env"
fi
if [[ -z "$platform_env_file" ]]; then
  platform_env_file="${ai_flow_root}/config/ai-flow.platform.env"
fi
host_env_file="$(expand_path "$(prompt_value "Host flow env path" "$host_env_file" "0")")"
platform_env_file="$(expand_path "$(prompt_value "AI flow platform env path" "$platform_env_file" "0")")"
source_flow_env="$(expand_path "$(prompt_value "Existing flow.env to copy (optional)" "$source_flow_env" "1")")"
run_questionnaire="$(prompt_choice "Questionnaire mode (ask/yes/no)" "$run_questionnaire")"
run_audit="$(prompt_choice "Audit mode (ask/yes/no)" "$run_audit")"
run_install="$(prompt_choice "Install mode (ask/yes/no)" "$run_install")"

if [[ -n "$source_flow_env" && ! -f "$source_flow_env" ]]; then
  echo "Source flow env not found: $source_flow_env" >&2
  exit 1
fi

ensure_host_layout
clone_or_update_workspace
normalize_host_env
ensure_platform_env
ensure_workspace_env_symlink
run_questionnaire_if_requested
run_audit_if_requested
run_install_if_requested

cat <<EOF
HOST_BOOTSTRAP_RESULT=ok
RUNTIME_USER=${runtime_user}
AI_FLOW_ROOT=${ai_flow_root}
PROFILE=${profile}
WORKSPACE_REPO=${workspace_repo_url}
WORKSPACE_REF=${workspace_ref}
WORKSPACE_PATH=${workspace_path}
TOOLKIT_REPO=${toolkit_repo_url}
TOOLKIT_REF=${toolkit_ref}
HOST_ENV_FILE=${host_env_file}
PLATFORM_ENV_FILE=${platform_env_file}
HOST_STATE_DIR=${ai_flow_root}/state/${profile}
HOST_LOG_DIR=${ai_flow_root}/logs/${profile}
NEXT_QUESTIONNAIRE=ROOT_DIR=${workspace_path} AI_FLOW_ROOT_DIR=${ai_flow_root} DAEMON_GH_ENV_FILE=${host_env_file} FLOW_SERVICE_MANAGER=systemd FLOW_SYSTEMD_SCOPE=user ./.flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${profile}
NEXT_AUDIT=ROOT_DIR=${workspace_path} AI_FLOW_ROOT_DIR=${ai_flow_root} DAEMON_GH_ENV_FILE=${host_env_file} FLOW_SERVICE_MANAGER=systemd FLOW_SYSTEMD_SCOPE=user ./.flow/shared/scripts/run.sh onboarding_audit --profile ${profile}
NEXT_INSTALL=ROOT_DIR=${workspace_path} AI_FLOW_ROOT_DIR=${ai_flow_root} DAEMON_GH_ENV_FILE=${host_env_file} FLOW_SERVICE_MANAGER=systemd FLOW_SYSTEMD_SCOPE=user ./.flow/shared/scripts/run.sh profile_init install --profile ${profile}
EOF
