#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

runtime_user="${USER:-$(id -un)}"
agent_user="aiflow"
ai_flow_root=""
workspace_path=""
authorized_key_file=""
password_mode="locked"
gateway_install_path=""
audit_log_path=""
sudoers_path="/etc/sudoers.d/ai-flow-remote-agent"

usage() {
  cat <<'EOF'
Usage: sudo .flow/shared/scripts/remote_agent_access_bootstrap.sh [options]

Provision optional remote-agent access for read-only external diagnostics:
- creates dedicated SSH user (default: aiflow);
- installs forced-command gateway;
- installs sudoers allowlist only for probe execution;
- optionally appends one SSH public key with forced-command restrictions;
- writes audit log path for every accepted/denied command.

Options:
  --runtime-user <user>         Existing runtime owner (example: ewg). Default: current user.
  --agent-user <user>           Dedicated remote agent SSH user. Default: aiflow
  --ai-flow-root <path>         AI flow host root. Default: resolved AI_FLOW_ROOT_DIR
  --workspace-path <path>       Authoritative workspace. Default: current ROOT_DIR
  --authorized-key-file <path>  Public key file to append into ~agent/.ssh/authorized_keys
  --password-mode <locked|interactive>
                                locked: keep password login disabled (default)
                                interactive: run passwd for break-glass password after setup
  --sudoers-path <path>         Override sudoers snippet path. Default: /etc/sudoers.d/ai-flow-remote-agent
  -h, --help                    Show help.
EOF
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root." >&2
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

agent_home_dir() {
  getent passwd "$agent_user" | cut -d: -f6
}

ensure_user() {
  if id "$agent_user" >/dev/null 2>&1; then
    return 0
  fi
  useradd --create-home --shell /bin/bash "$agent_user"
}

install_gateway() {
  mkdir -p "$(dirname "$gateway_install_path")"
  install -o root -g root -m 0755 "${SCRIPT_DIR}/remote_agent_gateway.sh" "$gateway_install_path"
}

install_audit_log() {
  mkdir -p "$(dirname "$audit_log_path")"
  touch "$audit_log_path"
  chown "$agent_user:$agent_user" "$(dirname "$audit_log_path")" "$audit_log_path"
  chmod 750 "$(dirname "$audit_log_path")"
  chmod 640 "$audit_log_path"
}

install_sudoers() {
  cat > "$sudoers_path" <<EOF
Defaults:${agent_user} !requiretty
${agent_user} ALL=(root) NOPASSWD: ${gateway_install_path} --sudo-probe *
EOF
  chmod 440 "$sudoers_path"
  visudo -cf "$sudoers_path" >/dev/null
}

append_authorized_key() {
  local key_file="$1"
  local home_dir ssh_dir authorized_keys key_line managed_prefix
  home_dir="$(agent_home_dir)"
  ssh_dir="${home_dir}/.ssh"
  authorized_keys="${ssh_dir}/authorized_keys"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  touch "$authorized_keys"
  chmod 600 "$authorized_keys"
  chown -R "$agent_user:$agent_user" "$ssh_dir"

  while IFS= read -r key_line || [[ -n "$key_line" ]]; do
    [[ -n "${key_line//[[:space:]]/}" ]] || continue
    [[ "$key_line" =~ ^# ]] && continue
    managed_prefix="command=\"${gateway_install_path} --forced-command --runtime-user ${runtime_user} --workspace-path ${workspace_path} --audit-log ${audit_log_path}\",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding "
    if grep -Fqx "${managed_prefix}${key_line}" "$authorized_keys"; then
      continue
    fi
    printf '%s%s\n' "$managed_prefix" "$key_line" >> "$authorized_keys"
  done < "$key_file"

  chown "$agent_user:$agent_user" "$authorized_keys"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-user)
      [[ $# -ge 2 ]] || { echo "Missing value for --runtime-user" >&2; exit 1; }
      runtime_user="$2"
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
    --sudoers-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --sudoers-path" >&2; exit 1; }
      sudoers_path="$2"
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

[[ -n "$ai_flow_root" ]] || ai_flow_root="$(codex_resolve_ai_flow_root_dir)"
[[ -n "$workspace_path" ]] || workspace_path="$ROOT_DIR"
ai_flow_root="$(expand_path "$ai_flow_root")"
workspace_path="$(expand_path "$workspace_path")"
gateway_install_path="${ai_flow_root}/bin/ai-flow-remote-agent-gateway"
audit_log_path="${ai_flow_root}/logs/remote-agent/access.log"

id "$runtime_user" >/dev/null 2>&1 || {
  echo "Runtime user not found: ${runtime_user}" >&2
  exit 1
}
[[ -d "$workspace_path" ]] || {
  echo "Workspace path not found: ${workspace_path}" >&2
  exit 1
}

ensure_user
passwd -l "$agent_user" >/dev/null 2>&1 || true
install_gateway
install_audit_log
install_sudoers

if [[ -n "$authorized_key_file" ]]; then
  [[ -f "$authorized_key_file" ]] || {
    echo "Public key file not found: ${authorized_key_file}" >&2
    exit 1
  }
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
    echo "Unsupported --password-mode: ${password_mode}" >&2
    exit 1
    ;;
esac

cat <<EOF
REMOTE_AGENT_ACCESS_BOOTSTRAP=ok
AGENT_USER=${agent_user}
RUNTIME_USER=${runtime_user}
WORKSPACE_PATH=${workspace_path}
AI_FLOW_ROOT_DIR=${ai_flow_root}
GATEWAY_PATH=${gateway_install_path}
AUDIT_LOG_PATH=${audit_log_path}
SUDOERS_PATH=${sudoers_path}
AUTHORIZED_KEY_FILE=${authorized_key_file:-}
PASSWORD_MODE=${password_mode}
NEXT_PROBE_EXAMPLE=ssh ${agent_user}@<host> semantically_overqualified_runtime_snapshot_env_audit_bundle_v1
NEXT_DISABLE=passwd -l ${agent_user} && rm -f ${sudoers_path}
EOF
