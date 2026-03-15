#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

agent_user="aiflow"
profile_name="$(codex_resolve_project_profile_name)"
ai_flow_root="$(codex_resolve_ai_flow_root_dir)"
workspace_path="$ROOT_DIR"
source_project_env_file="$(codex_resolve_flow_env_file)"
source_platform_env_file="${AI_FLOW_PLATFORM_ENV_FILE:-${ai_flow_root}/config/ai-flow.platform.env}"
publisher_interval_sec="15"
password_mode="locked"
authorized_key_file=""
source_openai_env_file=""

readonly gateway_install_path="/usr/local/sbin/ai-flow-remote-agent-v2-gateway"
readonly helper_install_path="/usr/local/libexec/ai-flow/remote-agent-v2-helper"
readonly publisher_install_path="/usr/local/libexec/ai-flow/ai-flow-diagnostics-publish"
readonly sshd_fragment_path="/etc/ssh/sshd_config.d/ai-flow-remote-agent-v2.conf"
readonly sudoers_path="/etc/sudoers.d/ai-flow-remote-agent-v2"
readonly systemd_service_path="/etc/systemd/system/ai-flow-diagnostics-publish@.service"
readonly systemd_timer_path="/etc/systemd/system/ai-flow-diagnostics-publish@.timer"
readonly platform_public_env="/etc/ai-flow/public/platform.env"
readonly public_projects_root="/etc/ai-flow/public/projects"
readonly secrets_platform_root="/etc/ai-flow/secrets/platform"
readonly secrets_projects_root="/etc/ai-flow/secrets/projects"
readonly diagnostics_root="/var/lib/ai-flow/diagnostics"
readonly audit_log_path="/var/log/ai-flow/remote-agent-v2.log"

platform_secret_keys=(
  OPS_BOT_DEBUG_BEARER_TOKEN
)

project_secret_keys=(
  DAEMON_GH_PROJECT_TOKEN
  GH_APP_INTERNAL_SECRET
  GH_APP_PRIVATE_KEY_PATH
  DAEMON_TG_BOT_TOKEN
  OPS_BOT_TG_BOT_TOKEN
  OPS_BOT_WEBHOOK_SECRET
  OPS_BOT_TG_SECRET_TOKEN
  OPS_REMOTE_STATUS_PUSH_SECRET
  OPS_REMOTE_SUMMARY_PUSH_SECRET
)

usage() {
  cat <<'EOF'
Usage: sudo .flow/shared/scripts/remote_agent_v2_bootstrap.sh [options]

Install Remote Agent v2:
- immutable gateway/helper/publisher under /usr/local;
- sshd Match User + ForceCommand fragment;
- sudoers allowlist only for immutable helper;
- server-side public/secrets layout under /etc/ai-flow;
- deterministic diagnostics publisher timer;
- optional operator public key for the aiflow user.

Options:
  --profile <name>                 Project profile. Default: resolved current profile.
  --agent-user <user>              Diagnostic SSH user. Default: aiflow
  --ai-flow-root <path>            AI flow host root. Default: resolved AI_FLOW_ROOT_DIR
  --workspace-path <path>          Authoritative workspace path. Default: current ROOT_DIR
  --source-project-env-file <path> Source project env for migration/bootstrap.
  --source-platform-env-file <path>
                                   Source platform env for migration/bootstrap.
  --source-openai-env-file <path>  Optional source OpenAI env file to copy into /etc/ai-flow/secrets/platform/openai.env
  --publisher-interval-sec <sec>   Diagnostics publish interval. Default: 15
  --authorized-key-file <path>     Public key to append into ~agent/.ssh/authorized_keys
  --password-mode <locked|interactive>
                                   locked: disable password login (default)
                                   interactive: set password after setup
  -h, --help                       Show help.
EOF
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must run as root." >&2
    exit 1
  fi
}

expand_path() {
  local value="${1:-}"
  case "$value" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${value#~/}" ;;
    *) printf '%s' "$value" ;;
  esac
}

read_env_key() {
  local env_file="$1"
  local key="$2"
  codex_read_key_from_env_file "$env_file" "$key" || true
}

write_env_kv() {
  local target_file="$1"
  local key="$2"
  local value="$3"
  printf '%s=%s\n' "$key" "$value" >> "$target_file"
}

invoking_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s' "$SUDO_USER"
  else
    printf '%s' "${USER:-$(id -un)}"
  fi
}

home_dir_for_user() {
  getent passwd "$1" | cut -d: -f6
}

default_authorized_key_file() {
  local operator_user operator_home candidate
  operator_user="$(invoking_user)"
  operator_home="$(home_dir_for_user "$operator_user" || true)"
  [[ -n "$operator_home" ]] || return 0
  candidate="${operator_home}/.ssh/aiflow_remote_agent.pub"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
  fi
}

ensure_user() {
  if id "$agent_user" >/dev/null 2>&1; then
    return 0
  fi
  useradd --create-home --shell /bin/bash "$agent_user"
}

ensure_agent_not_in_docker_group() {
  if getent group docker >/dev/null 2>&1; then
    gpasswd -d "$agent_user" docker >/dev/null 2>&1 || true
  fi
}

install_immutable_binaries() {
  install -d -o root -g root -m 0755 /usr/local/libexec/ai-flow /usr/local/sbin
  install -o root -g root -m 0755 "${SCRIPT_DIR}/remote_agent_v2_gateway.sh" "$gateway_install_path"
  install -o root -g root -m 0755 "${SCRIPT_DIR}/remote_agent_v2_helper.sh" "$helper_install_path"
  install -o root -g root -m 0755 "${SCRIPT_DIR}/remote_agent_v2_publisher.sh" "$publisher_install_path"
}

install_public_and_secret_layout() {
  install -d -o root -g root -m 0755 /etc/ai-flow
  install -d -o root -g root -m 0755 /etc/ai-flow/public "$public_projects_root"
  install -d -o root -g root -m 0700 /etc/ai-flow/secrets "$secrets_platform_root" "${secrets_projects_root}/${profile_name}"
  install -d -o root -g root -m 0750 "${diagnostics_root}/${profile_name}"
  install -d -o root -g root -m 0750 /var/log/ai-flow
  touch "$audit_log_path"
  chown root:root "$audit_log_path"
  chmod 0640 "$audit_log_path"
}

install_project_public_env() {
  local target_file="${public_projects_root}/${profile_name}.env"
  local diagnostics_dir="${diagnostics_root}/${profile_name}"
  local ops_bind ops_port runtime_log_dir flow_logs_dir compose_root compose_env_file compose_file public_base_url host_name nginx_conf_file ttl
  ops_bind="$(read_env_key "$source_project_env_file" "OPS_BOT_BIND")"
  ops_port="$(read_env_key "$source_project_env_file" "OPS_BOT_PORT")"
  runtime_log_dir="$(read_env_key "$source_project_env_file" "FLOW_RUNTIME_LOG_DIR")"
  flow_logs_dir="$(read_env_key "$source_project_env_file" "FLOW_LOGS_DIR")"
  compose_root="${ai_flow_root}/docker/${profile_name}"
  compose_env_file="${compose_root}/.env"
  compose_file="${compose_root}/docker-compose.yml"
  public_base_url="$(read_env_key "$source_platform_env_file" "OPS_BOT_PUBLIC_BASE_URL")"
  host_name="$(printf '%s' "$public_base_url" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
  nginx_conf_file="/etc/nginx/conf.d/${host_name}.conf"
  ttl="$(( publisher_interval_sec * 2 ))"
  [[ -n "$ops_bind" ]] || ops_bind="127.0.0.1"
  [[ -n "$ops_port" ]] || ops_port="8790"

  : > "$target_file"
  chmod 0644 "$target_file"
  write_env_kv "$target_file" "PROJECT_PROFILE" "$profile_name"
  write_env_kv "$target_file" "AI_FLOW_ROOT_DIR" "$ai_flow_root"
  write_env_kv "$target_file" "WORKSPACE_PATH" "$workspace_path"
  write_env_kv "$target_file" "FLOW_HOST_RUNTIME_MODE" "$(read_env_key "$source_project_env_file" "FLOW_HOST_RUNTIME_MODE")"
  write_env_kv "$target_file" "OPS_BOT_BIND" "$ops_bind"
  write_env_kv "$target_file" "OPS_BOT_PORT" "$ops_port"
  write_env_kv "$target_file" "OPS_BOT_WEBHOOK_PATH" "$(read_env_key "$source_project_env_file" "OPS_BOT_WEBHOOK_PATH")"
  write_env_kv "$target_file" "FLOW_LOGS_DIR" "$flow_logs_dir"
  write_env_kv "$target_file" "FLOW_RUNTIME_LOG_DIR" "$runtime_log_dir"
  write_env_kv "$target_file" "COMPOSE_ROOT" "$compose_root"
  write_env_kv "$target_file" "COMPOSE_ENV_FILE" "$compose_env_file"
  write_env_kv "$target_file" "COMPOSE_FILE" "$compose_file"
  write_env_kv "$target_file" "NGINX_CONF_FILE" "$nginx_conf_file"
  write_env_kv "$target_file" "AI_FLOW_DIAGNOSTICS_DIR" "$diagnostics_dir"
  write_env_kv "$target_file" "AI_FLOW_DIAGNOSTICS_PUBLISH_INTERVAL_SEC" "$publisher_interval_sec"
  write_env_kv "$target_file" "AI_FLOW_DIAGNOSTICS_SNAPSHOT_TTL_SEC" "$ttl"
}

install_platform_public_env() {
  : > "$platform_public_env"
  chmod 0644 "$platform_public_env"
  write_env_kv "$platform_public_env" "AI_FLOW_ROOT_DIR" "$ai_flow_root"
  write_env_kv "$platform_public_env" "FLOW_HOST_RUNTIME_MODE" "$(read_env_key "$source_platform_env_file" "FLOW_HOST_RUNTIME_MODE")"
  write_env_kv "$platform_public_env" "OPS_BOT_PUBLIC_BASE_URL" "$(read_env_key "$source_platform_env_file" "OPS_BOT_PUBLIC_BASE_URL")"
  write_env_kv "$platform_public_env" "AI_FLOW_REMOTE_AGENT_GATEWAY_PATH" "$gateway_install_path"
  write_env_kv "$platform_public_env" "AI_FLOW_REMOTE_AGENT_HELPER_PATH" "$helper_install_path"
  write_env_kv "$platform_public_env" "AI_FLOW_DIAGNOSTICS_ROOT" "$diagnostics_root"
  write_env_kv "$platform_public_env" "AI_FLOW_REMOTE_AGENT_AUDIT_LOG" "$audit_log_path"
}

copy_selected_secret_keys() {
  local source_env="$1"
  local target_env="$2"
  shift 2 || true
  local key value
  : > "$target_env"
  chmod 0600 "$target_env"
  for key in "$@"; do
    value="$(read_env_key "$source_env" "$key")"
    if [[ -n "$value" ]]; then
      write_env_kv "$target_env" "$key" "$value"
    fi
  done
}

copy_secret_material() {
  local platform_secret_env="${secrets_platform_root}/runtime.env"
  local project_secret_env="${secrets_projects_root}/${profile_name}/runtime.env"
  copy_selected_secret_keys "$source_platform_env_file" "$platform_secret_env" "${platform_secret_keys[@]}"
  copy_selected_secret_keys "$source_project_env_file" "$project_secret_env" "${project_secret_keys[@]}"
  if [[ -n "$source_openai_env_file" && -f "$source_openai_env_file" ]]; then
    install -o root -g root -m 0600 "$source_openai_env_file" "${secrets_platform_root}/openai.env"
  fi
}

install_sshd_fragment() {
  cat > "$sshd_fragment_path" <<EOF
Match User ${agent_user}
    AuthenticationMethods publickey
    PasswordAuthentication no
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    PermitUserRC no
    PermitTunnel no
    ForceCommand ${gateway_install_path}
Match all
EOF
  chmod 0644 "$sshd_fragment_path"
  sshd -t
}

reload_ssh_service() {
  if systemctl reload ssh >/dev/null 2>&1; then
    return 0
  fi
  if systemctl reload sshd >/dev/null 2>&1; then
    return 0
  fi
  if service ssh reload >/dev/null 2>&1; then
    return 0
  fi
  if service sshd reload >/dev/null 2>&1; then
    return 0
  fi
  echo "Unable to reload SSH service after installing ${sshd_fragment_path}" >&2
  exit 1
}

verify_sshd_policy() {
  local sshd_dump
  sshd_dump="$(sshd -T -C "user=${agent_user},host=127.0.0.1,addr=127.0.0.1" 2>/dev/null || true)"
  [[ -n "$sshd_dump" ]] || {
    echo "WARN: Unable to verify effective SSH policy for ${agent_user}" >&2
    return 1
  }
  grep -Eq '^forcecommand /usr/local/sbin/ai-flow-remote-agent-v2-gateway$' <<< "$sshd_dump" || {
    echo "WARN: Effective SSH policy missing expected ForceCommand for ${agent_user}" >&2
    return 1
  }
  grep -Eq '^permittty no$' <<< "$sshd_dump" || {
    echo "WARN: Effective SSH policy missing PermitTTY no for ${agent_user}" >&2
    return 1
  }
  grep -Eq '^allowtcpforwarding no$' <<< "$sshd_dump" || {
    echo "WARN: Effective SSH policy missing AllowTcpForwarding no for ${agent_user}" >&2
    return 1
  }
  return 0
}

install_sudoers() {
  cat > "$sudoers_path" <<EOF
Defaults:${agent_user} !requiretty
${agent_user} ALL=(root) NOPASSWD: ${helper_install_path} --dispatch *
EOF
  chmod 0440 "$sudoers_path"
  visudo -cf "$sudoers_path" >/dev/null
}

install_systemd_units() {
  install -o root -g root -m 0644 "${SCRIPT_DIR}/remote_agent_v2_publisher.service" "$systemd_service_path"
  sed "s/@PUBLISH_INTERVAL_SEC@/${publisher_interval_sec}s/g" "${SCRIPT_DIR}/remote_agent_v2_publisher.timer" > "$systemd_timer_path"
  chmod 0644 "$systemd_timer_path"
  systemctl daemon-reload
  systemctl enable --now "ai-flow-diagnostics-publish@${profile_name}.timer"
}

append_authorized_key() {
  local key_file="$1"
  local home_dir ssh_dir authorized_keys key_line managed_prefix
  home_dir="$(home_dir_for_user "$agent_user")"
  ssh_dir="${home_dir}/.ssh"
  authorized_keys="${ssh_dir}/authorized_keys"
  install -d -o "$agent_user" -g "$agent_user" -m 0700 "$ssh_dir"
  touch "$authorized_keys"
  chown "$agent_user:$agent_user" "$authorized_keys"
  chmod 0600 "$authorized_keys"

  while IFS= read -r key_line || [[ -n "$key_line" ]]; do
    [[ -n "${key_line//[[:space:]]/}" ]] || continue
    [[ "$key_line" =~ ^# ]] && continue
    managed_prefix="command=\"${gateway_install_path}\",restrict "
    if grep -Fqx "${managed_prefix}${key_line}" "$authorized_keys"; then
      continue
    fi
    printf '%s%s\n' "$managed_prefix" "$key_line" >> "$authorized_keys"
  done < "$key_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile_name="$2"
      shift 2
      ;;
    --agent-user)
      [[ $# -ge 2 ]] || { echo "Missing value for --agent-user" >&2; exit 1; }
      agent_user="$2"
      shift 2
      ;;
    --ai-flow-root)
      [[ $# -ge 2 ]] || { echo "Missing value for --ai-flow-root" >&2; exit 1; }
      ai_flow_root="$2"
      shift 2
      ;;
    --workspace-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --workspace-path" >&2; exit 1; }
      workspace_path="$2"
      shift 2
      ;;
    --source-project-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-project-env-file" >&2; exit 1; }
      source_project_env_file="$2"
      shift 2
      ;;
    --source-platform-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-platform-env-file" >&2; exit 1; }
      source_platform_env_file="$2"
      shift 2
      ;;
    --source-openai-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-openai-env-file" >&2; exit 1; }
      source_openai_env_file="$2"
      shift 2
      ;;
    --publisher-interval-sec)
      [[ $# -ge 2 ]] || { echo "Missing value for --publisher-interval-sec" >&2; exit 1; }
      publisher_interval_sec="$2"
      shift 2
      ;;
    --authorized-key-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --authorized-key-file" >&2; exit 1; }
      authorized_key_file="$2"
      shift 2
      ;;
    --password-mode)
      [[ $# -ge 2 ]] || { echo "Missing value for --password-mode" >&2; exit 1; }
      password_mode="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_root

ai_flow_root="$(expand_path "$ai_flow_root")"
workspace_path="$(expand_path "$workspace_path")"
source_project_env_file="$(expand_path "$source_project_env_file")"
source_platform_env_file="$(expand_path "$source_platform_env_file")"
if [[ -z "$authorized_key_file" ]]; then
  authorized_key_file="$(default_authorized_key_file)"
fi
if [[ -n "$source_openai_env_file" ]]; then
  source_openai_env_file="$(expand_path "$source_openai_env_file")"
fi

[[ "$publisher_interval_sec" =~ ^[0-9]+$ ]] || { echo "Invalid publisher interval" >&2; exit 1; }
[[ -d "$workspace_path" ]] || { echo "Workspace path not found: ${workspace_path}" >&2; exit 1; }
[[ -f "$source_project_env_file" ]] || { echo "Project env not found: ${source_project_env_file}" >&2; exit 1; }
[[ -f "$source_platform_env_file" ]] || { echo "Platform env not found: ${source_platform_env_file}" >&2; exit 1; }

ensure_user
ensure_agent_not_in_docker_group
passwd -l "$agent_user" >/dev/null 2>&1 || true
install_immutable_binaries
install_public_and_secret_layout
install_platform_public_env
install_project_public_env
copy_secret_material
install_sshd_fragment
reload_ssh_service
sshd_policy_effective="0"
if verify_sshd_policy; then
  sshd_policy_effective="1"
fi
install_sudoers
install_systemd_units

if [[ -n "$authorized_key_file" ]]; then
  [[ -f "$authorized_key_file" ]] || { echo "Public key file not found: ${authorized_key_file}" >&2; exit 1; }
  append_authorized_key "$authorized_key_file"
fi

case "$password_mode" in
  locked)
    passwd -l "$agent_user" >/dev/null 2>&1 || true
    ;;
  interactive)
    passwd "$agent_user"
    ;;
  *)
    echo "Unknown password mode: ${password_mode}" >&2
    exit 1
    ;;
esac

echo "REMOTE_AGENT_V2_BOOTSTRAP_OK=1"
echo "PROFILE=${profile_name}"
echo "AGENT_USER=${agent_user}"
echo "GATEWAY_PATH=${gateway_install_path}"
echo "HELPER_PATH=${helper_install_path}"
echo "PUBLISHER_PATH=${publisher_install_path}"
echo "PLATFORM_PUBLIC_ENV=${platform_public_env}"
echo "PROJECT_PUBLIC_ENV=${public_projects_root}/${profile_name}.env"
echo "PROJECT_SECRETS_ENV=${secrets_projects_root}/${profile_name}/runtime.env"
echo "PLATFORM_SECRETS_ENV=${secrets_platform_root}/runtime.env"
echo "AUDIT_LOG=${audit_log_path}"
echo "SSHD_POLICY_EFFECTIVE=${sshd_policy_effective}"
