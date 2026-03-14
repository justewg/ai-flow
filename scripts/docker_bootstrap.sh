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
source_flow_env=""
toolkit_repo_url=""
toolkit_ref="main"
compose_root=""
runtime_home=""
codex_home=""
openai_env_file=""
compose_project_name=""
compose_image_name=""
daemon_interval="${FLOW_DAEMON_INTERVAL:-45}"
watchdog_interval="${FLOW_WATCHDOG_INTERVAL:-45}"
run_compose_config="yes"
run_compose_up="ask"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/docker_bootstrap.sh [options]

Bootstrap docker-based ai-flow runtime on a Linux host:
- creates host-level .ai-flow layout;
- clones or updates authoritative automation workspace;
- prepares host-local flow env outside deploy snapshots;
- generates Dockerfile, docker-compose.yml and helper scripts;
- optionally runs `docker compose config` and `docker compose up -d --build`.

Options:
  --profile <name>             First managed project profile (example: planka).
  --runtime-user <user>        Linux user owning automation runtime. Default: current user.
  --ai-flow-root <path>        Host root for config/state/logs/workspaces. Default: /var/sites/.ai-flow
  --workspace-repo <url>       Consumer repo URL or path for authoritative workspace.
  --workspace-ref <ref>        Git ref for workspace checkout. Default: development
  --workspace-path <path>      Workspace path. Default: <ai-flow-root>/workspaces/<profile>
  --host-env-file <path>       Host-local flow env path. Default: <ai-flow-root>/config/<profile>.flow.env
  --source-flow-env <path>     Optional existing flow.env to copy before Linux normalization.
  --toolkit-repo <url>         ai-flow repo URL/path. Default: current origin or https://github.com/justewg/ai-flow.git
  --toolkit-ref <ref>          ai-flow ref for bootstrap. Default: main
  --compose-root <path>        Docker compose root. Default: <ai-flow-root>/docker/<profile>
  --runtime-home <path>        Runtime HOME mounted into containers. Default: /home/<runtime-user>
  --codex-home <path>          CODEX_HOME inside runtime. Default: <runtime-home>/.codex-server-api
  --openai-env-file <path>     Host-local env file with OPENAI_API_KEY. Default: <runtime-home>/.config/planka-automation/openai.env
  --daemon-interval <seconds>  Daemon loop interval. Default: 45
  --watchdog-interval <sec>    Watchdog loop interval. Default: 45
  --config <ask|yes|no>        Run `docker compose config`. Default: yes
  --up <ask|yes|no>            Run `docker compose up -d --build`. Default: ask
  -h, --help                   Show help.
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

  if GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new' \
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

current_user() {
  id -un
}

runtime_group() {
  id -gn "$runtime_user"
}

runtime_uid() {
  id -u "$runtime_user"
}

runtime_gid() {
  id -g "$runtime_user"
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
  ensure_dir_owned "${ai_flow_root}/docker"
  ensure_dir_owned "$compose_root"
}

has_tty() {
  [[ -t 0 && -t 1 ]]
}

step() {
  echo "[docker-bootstrap] $*" >&2
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
    printf '%s [%s]:\n' "$prompt_text" "$default_value" >&2
  else
    printf '%s:\n' "$prompt_text" >&2
  fi
  IFS= read -r answer || true
  if [[ -z "$answer" ]]; then
    answer="$default_value"
  fi
  if [[ -z "$answer" && "$allow_empty" != "1" ]]; then
    echo "Value is required." >&2
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
    printf '%s [%s]:\n' "$prompt_text" "$default_value" >&2
    IFS= read -r answer || true
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
    echo "Expected one of: ask, yes, no." >&2
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
  if [[ "$toolkit_repo_url" == /* || "$toolkit_repo_url" == ./* || "$toolkit_repo_url" == ../* ]]; then
    run_as_runtime_user git -C "$workspace_path" -c protocol.file.allow=always submodule update --init --recursive
  else
    run_as_runtime_user git -C "$workspace_path" submodule update --init --recursive
  fi
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
      "${workspace_path}/.flow/shared/scripts/profile_init.sh" init \
      --profile "$profile" \
      --env-file "$host_env_file" \
      --state-dir "$state_dir"
  fi

  upsert_env_key "$host_env_file" "PROJECT_PROFILE" "$profile"
  upsert_env_key "$host_env_file" "AI_FLOW_ROOT_DIR" "$ai_flow_root"
  upsert_env_key "$host_env_file" "CODEX_STATE_DIR" "$state_dir"
  upsert_env_key "$host_env_file" "FLOW_STATE_DIR" "$state_dir"
  upsert_env_key "$host_env_file" "FLOW_LOGS_DIR" "$logs_dir"
  upsert_env_key "$host_env_file" "FLOW_RUNTIME_LOG_DIR" "$runtime_logs_dir"
  upsert_env_key "$host_env_file" "FLOW_PM2_LOG_DIR" "$pm2_logs_dir"
  upsert_env_key "$host_env_file" "FLOW_HOST_RUNTIME_MODE" "linux-docker-hosted"

  remove_env_key "$host_env_file" "FLOW_LAUNCHAGENTS_DIR"
  remove_env_key "$host_env_file" "FLOW_LAUNCHD_DIR"
  chown "$runtime_user:$(runtime_group)" "$host_env_file" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "$host_env_file"
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

ensure_runtime_home_paths() {
  ensure_dir_owned "$runtime_home"
  ensure_dir_owned "$codex_home"
  ensure_dir_owned "$(dirname "$openai_env_file")"
}

render_compose_env() {
  cat > "${compose_root}/.env" <<EOF
PROFILE=${profile}
AI_FLOW_ROOT=${ai_flow_root}
WORKSPACE_PATH=${workspace_path}
RUNTIME_HOME=${runtime_home}
CODEX_HOME=${codex_home}
HOST_ENV_FILE=${host_env_file}
OPENAI_ENV_FILE=${openai_env_file}
RUNTIME_UID=$(runtime_uid)
RUNTIME_GID=$(runtime_gid)
IMAGE_NAME=${compose_image_name}
COMPOSE_PROJECT_NAME=${compose_project_name}
DAEMON_INTERVAL=${daemon_interval}
WATCHDOG_INTERVAL=${watchdog_interval}
EOF
  chown "$runtime_user:$(runtime_group)" "${compose_root}/.env" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "${compose_root}/.env"
}

render_container_env() {
  cat > "${compose_root}/container.env" <<EOF
PROJECT_PROFILE=${profile}
ROOT_DIR=${workspace_path}
FLOW_WORKSPACE_PATH=${workspace_path}
AI_FLOW_ROOT_DIR=${ai_flow_root}
DAEMON_GH_ENV_FILE=${host_env_file}
FLOW_HOST_RUNTIME_MODE=linux-docker-hosted
FLOW_DOCKER_COMPOSE_ROOT=${compose_root}
HOME=${runtime_home}
CODEX_HOME=${codex_home}
TERM=xterm-256color
GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new
EOF
  chown "$runtime_user:$(runtime_group)" "${compose_root}/container.env" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "${compose_root}/container.env"
}

render_dockerfile() {
  cat > "${compose_root}/Dockerfile" <<'EOF'
FROM node:20-bookworm-slim

SHELL ["/bin/bash", "-lc"]

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    openssh-client \
    ripgrep \
    tmux \
    wget \
  && mkdir -p /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg > /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && npm install -g @openai/codex \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
EOF
  chown "$runtime_user:$(runtime_group)" "${compose_root}/Dockerfile" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "${compose_root}/Dockerfile"
}

render_compose_file() {
  cat > "${compose_root}/docker-compose.yml" <<'EOF'
services:
  runtime: &ai_flow_base
    build:
      context: .
      dockerfile: Dockerfile
    image: ${IMAGE_NAME}
    container_name: ai-flow-${PROFILE}-runtime
    init: true
    network_mode: host
    restart: unless-stopped
    user: "${RUNTIME_UID}:${RUNTIME_GID}"
    working_dir: ${WORKSPACE_PATH}
    env_file:
      - ./container.env
      - ${HOST_ENV_FILE}
      - ${OPENAI_ENV_FILE}
    environment:
      HOME: ${RUNTIME_HOME}
      CODEX_HOME: ${CODEX_HOME}
    volumes:
      - ${AI_FLOW_ROOT}:${AI_FLOW_ROOT}
      - ${WORKSPACE_PATH}:${WORKSPACE_PATH}
      - ${RUNTIME_HOME}:${RUNTIME_HOME}
    command:
      - bash
      - -lc
      - |
        mkdir -p "${RUNTIME_HOME}" "${CODEX_HOME}"
        exec sleep infinity
    stdin_open: true
    tty: true

  daemon:
    <<: *ai_flow_base
    container_name: ai-flow-${PROFILE}-daemon
    stdin_open: false
    tty: false
    command:
      - bash
      - -lc
      - |
        mkdir -p "${RUNTIME_HOME}" "${CODEX_HOME}"
        cd "${WORKSPACE_PATH}"
        exec ./.flow/shared/scripts/daemon_loop.sh ${DAEMON_INTERVAL}

  watchdog:
    <<: *ai_flow_base
    container_name: ai-flow-${PROFILE}-watchdog
    stdin_open: false
    tty: false
    command:
      - bash
      - -lc
      - |
        mkdir -p "${RUNTIME_HOME}" "${CODEX_HOME}"
        cd "${WORKSPACE_PATH}"
        exec ./.flow/shared/scripts/watchdog_loop.sh ${WATCHDOG_INTERVAL}
EOF
  chown "$runtime_user:$(runtime_group)" "${compose_root}/docker-compose.yml" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "${compose_root}/docker-compose.yml"
}

render_helper_scripts() {
  cat > "${compose_root}/up.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${SCRIPT_DIR}/docker-compose.yml" up -d --build
EOF
  cat > "${compose_root}/down.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${SCRIPT_DIR}/docker-compose.yml" down
EOF
  cat > "${compose_root}/logs.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
service_name="${1:-daemon}"
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${SCRIPT_DIR}/docker-compose.yml" logs -f "${service_name}"
EOF
  cat > "${compose_root}/exec-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${SCRIPT_DIR}/docker-compose.yml" exec runtime bash
EOF
  chmod +x "${compose_root}/up.sh" "${compose_root}/down.sh" "${compose_root}/logs.sh" "${compose_root}/exec-runtime.sh"
  chown "$runtime_user:$(runtime_group)" "${compose_root}/up.sh" "${compose_root}/down.sh" "${compose_root}/logs.sh" "${compose_root}/exec-runtime.sh" 2>/dev/null || sudo chown "$runtime_user:$(runtime_group)" "${compose_root}/up.sh" "${compose_root}/down.sh" "${compose_root}/logs.sh" "${compose_root}/exec-runtime.sh"
}

compose_cmd() {
  docker compose --env-file "${compose_root}/.env" -f "${compose_root}/docker-compose.yml" "$@"
}

run_compose_config_if_requested() {
  should_run_step "$run_compose_config" "Проверить docker compose config сейчас?" || return 0
  compose_cmd config >/dev/null
  echo "DOCKER_COMPOSE_CONFIG=ok"
}

run_compose_up_if_requested() {
  should_run_step "$run_compose_up" "Запустить docker compose up -d --build сейчас?" || return 0
  compose_cmd up -d --build
  compose_cmd ps
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
    --compose-root)
      [[ $# -ge 2 ]] || { echo "Missing value for --compose-root" >&2; exit 1; }
      compose_root="$2"
      shift 2
      ;;
    --runtime-home)
      [[ $# -ge 2 ]] || { echo "Missing value for --runtime-home" >&2; exit 1; }
      runtime_home="$2"
      shift 2
      ;;
    --codex-home)
      [[ $# -ge 2 ]] || { echo "Missing value for --codex-home" >&2; exit 1; }
      codex_home="$2"
      shift 2
      ;;
    --openai-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --openai-env-file" >&2; exit 1; }
      openai_env_file="$2"
      shift 2
      ;;
    --daemon-interval)
      [[ $# -ge 2 ]] || { echo "Missing value for --daemon-interval" >&2; exit 1; }
      daemon_interval="$2"
      shift 2
      ;;
    --watchdog-interval)
      [[ $# -ge 2 ]] || { echo "Missing value for --watchdog-interval" >&2; exit 1; }
      watchdog_interval="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "Missing value for --config" >&2; exit 1; }
      run_compose_config="$2"
      shift 2
      ;;
    --up)
      [[ $# -ge 2 ]] || { echo "Missing value for --up" >&2; exit 1; }
      run_compose_up="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

profile="$(slugify "$(prompt_value "First managed project profile" "${profile:-planka}")")"
step "Interactive input detected: $(if has_tty; then echo yes; else echo no; fi)"
runtime_user="$(prompt_value "Runtime user" "$runtime_user")"
ai_flow_root="$(expand_path "$(prompt_value "AI flow root" "$ai_flow_root")")"
workspace_repo_url="$(normalize_repo_url "$(prompt_value "Workspace repo URL" "${workspace_repo_url:-justewg/planka}")")"
workspace_ref="$(prompt_value "Workspace git ref" "$workspace_ref")"
workspace_path="$(expand_path "$(prompt_value "Workspace path" "${workspace_path:-${ai_flow_root}/workspaces/${profile}}")")"
host_env_file="$(expand_path "$(prompt_value "Host flow env path" "${host_env_file:-${ai_flow_root}/config/${profile}.flow.env}")")"
source_flow_env="$(expand_path "$(prompt_value "Existing flow.env to copy (optional)" "${source_flow_env:-}" 1)")"
toolkit_repo_url="$(normalize_repo_url "$(prompt_value "Toolkit repo URL" "${toolkit_repo_url:-$(current_toolkit_origin)}")")"
toolkit_ref="$(prompt_value "Toolkit git ref" "$toolkit_ref")"
compose_root="$(expand_path "$(prompt_value "Docker compose root" "${compose_root:-${ai_flow_root}/docker/${profile}}")")"
runtime_home="$(expand_path "$(prompt_value "Runtime HOME path" "${runtime_home:-/home/${runtime_user}}")")"
codex_home="$(expand_path "$(prompt_value "CODEX_HOME path" "${codex_home:-${runtime_home}/.codex-server-api}")")"
openai_env_file="$(expand_path "$(prompt_value "OpenAI env file" "${openai_env_file:-${runtime_home}/.config/planka-automation/openai.env}")")"
daemon_interval="$(prompt_value "Daemon interval (seconds)" "$daemon_interval")"
watchdog_interval="$(prompt_value "Watchdog interval (seconds)" "$watchdog_interval")"
run_compose_config="$(prompt_choice "Run docker compose config" "$run_compose_config")"
run_compose_up="$(prompt_choice "Run docker compose up -d --build" "$run_compose_up")"

if [[ -n "$source_flow_env" && ! -f "$source_flow_env" ]]; then
  echo "Source flow env not found: $source_flow_env" >&2
  exit 1
fi

compose_project_name="ai-flow-${profile}"
compose_image_name="ai-flow-${profile}:latest"

step "Preparing host layout under ${ai_flow_root}"
ensure_host_layout
step "Preparing runtime home paths under ${runtime_home}"
ensure_runtime_home_paths
step "Cloning or updating workspace at ${workspace_path}"
clone_or_update_workspace
step "Normalizing host env at ${host_env_file}"
normalize_host_env
step "Linking workspace flow.env"
ensure_workspace_env_symlink
step "Rendering Docker bootstrap files into ${compose_root}"
render_compose_env
render_container_env
render_dockerfile
render_compose_file
render_helper_scripts
step "Validating generated docker compose"
run_compose_config_if_requested
step "Optional container start phase"
run_compose_up_if_requested

cat <<EOF
DOCKER_BOOTSTRAP_OK=1
PROFILE=${profile}
WORKSPACE_PATH=${workspace_path}
HOST_ENV_FILE=${host_env_file}
COMPOSE_ROOT=${compose_root}
COMPOSE_PROJECT_NAME=${compose_project_name}
NEXT_UP=${compose_root}/up.sh
NEXT_EXEC=${compose_root}/exec-runtime.sh
NEXT_LOGS=${compose_root}/logs.sh
EOF
