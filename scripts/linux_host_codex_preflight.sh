#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_load_flow_env

report_ok() {
  printf 'CHECK_OK %s=%s\n' "$1" "$2"
}

report_warn() {
  printf 'CHECK_WARN %s=%s\n' "$1" "$2"
}

report_fail() {
  printf 'CHECK_FAIL %s=%s\n' "$1" "$2" >&2
}

has_env_key() {
  local file_path="$1"
  local key="$2"
  [[ -r "$file_path" ]] || return 1
  local value
  value="$(codex_read_key_from_env_file "$file_path" "$key" || true)"
  [[ -n "$value" ]]
}

resolve_openai_env_file() {
  local openai_env_file
  openai_env_file="$(codex_resolve_config_value "OPENAI_ENV_FILE" "")"
  if [[ -z "$openai_env_file" && -f "/etc/ai-flow/secrets/platform/openai.env" ]]; then
    openai_env_file="/etc/ai-flow/secrets/platform/openai.env"
  fi
  if [[ -z "$openai_env_file" && -f "${HOME}/.config/ai-flow/openai.env" ]]; then
    openai_env_file="${HOME}/.config/ai-flow/openai.env"
  fi
  printf '%s' "$openai_env_file"
}

resolve_claude_env_file() {
  local claude_env_file
  claude_env_file="$(codex_resolve_config_value "CLAUDE_PROVIDER_ENV_FILE" "")"
  if [[ -z "$claude_env_file" && -f "/etc/ai-flow/secrets/platform/claude.env" ]]; then
    claude_env_file="/etc/ai-flow/secrets/platform/claude.env"
  fi
  if [[ -z "$claude_env_file" && -f "${HOME}/.config/ai-flow/claude.env" ]]; then
    claude_env_file="${HOME}/.config/ai-flow/claude.env"
  fi
  printf '%s' "$claude_env_file"
}

provider_api_preflight() {
  local openai_env_file claude_env_file provider_ok="0"

  openai_env_file="$(resolve_openai_env_file)"
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    report_ok "OPENAI_API_KEY" "present:env"
    provider_ok="1"
  elif [[ -n "$openai_env_file" && -r "$openai_env_file" ]] && has_env_key "$openai_env_file" "OPENAI_API_KEY"; then
    report_ok "OPENAI_API_KEY" "present:${openai_env_file}"
    provider_ok="1"
  elif [[ -n "$openai_env_file" ]]; then
    report_warn "OPENAI_API_KEY" "missing_or_unreadable:${openai_env_file}"
  else
    report_warn "OPENAI_API_KEY" "env_file_unresolved"
  fi

  claude_env_file="$(resolve_claude_env_file)"
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    report_ok "ANTHROPIC_API_KEY" "present:env"
    provider_ok="1"
  elif [[ -n "$claude_env_file" && -r "$claude_env_file" ]] && has_env_key "$claude_env_file" "ANTHROPIC_API_KEY"; then
    report_ok "ANTHROPIC_API_KEY" "present:${claude_env_file}"
    provider_ok="1"
  elif [[ -n "$claude_env_file" ]]; then
    report_warn "ANTHROPIC_API_KEY" "missing_or_unreadable:${claude_env_file}"
  else
    report_warn "ANTHROPIC_API_KEY" "env_file_unresolved"
  fi

  if [[ "$provider_ok" != "1" ]]; then
    report_fail "PROVIDER_API_CREDENTIALS" "missing:OPENAI_API_KEY|ANTHROPIC_API_KEY"
    return 1
  fi

  report_ok "PROVIDER_API_CREDENTIALS" "present"
}

runtime_mode="$(codex_resolve_config_value "FLOW_HOST_RUNTIME_MODE" "")"
preflight_profile="$(codex_resolve_config_value "FLOW_PREFLIGHT_PROFILE" "")"
preflight_profile="$(printf '%s' "$preflight_profile" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n')"
case "$runtime_mode" in
  linux-hosted|linux-docker-hosted)
    report_ok "FLOW_HOST_RUNTIME_MODE" "$runtime_mode"
    ;;
  *)
    report_warn "FLOW_HOST_RUNTIME_MODE" "${runtime_mode:-unset}"
    exit 0
    ;;
esac

if [[ "$(uname -s)" != "Linux" ]]; then
  report_fail "HOST_OS" "expected:Linux"
  exit 1
fi
report_ok "HOST_OS" "Linux"

case "$preflight_profile" in
  provider-only|claude-shadow|compare-only)
    report_ok "FLOW_PREFLIGHT_PROFILE" "$preflight_profile"
    if command -v codex >/dev/null 2>&1; then
      report_ok "CODEX_CLI" "$(command -v codex)"
    else
      report_warn "CODEX_CLI" "skipped:${preflight_profile}"
    fi
    provider_api_preflight
    cat <<EOF
SMOKE_STEP provider_api_openai_env=${OPENAI_ENV_FILE:-/etc/ai-flow/secrets/platform/openai.env}
SMOKE_STEP provider_api_claude_probe=.flow/shared/scripts/claude_provider_probe.sh
EOF
    exit 0
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  report_fail "CODEX_CLI" "missing"
  exit 1
fi
report_ok "CODEX_CLI" "$(command -v codex)"

codex_home="$(codex_resolve_config_value "CODEX_HOME" "${HOME}/.codex-server-api")"
if [[ ! -d "$codex_home" ]]; then
  report_fail "CODEX_HOME_DIR" "missing:${codex_home}"
  exit 1
fi
report_ok "CODEX_HOME_DIR" "$codex_home"

login_status_output=""
if login_status_output="$(CODEX_HOME="$codex_home" codex login status 2>&1)"; then
  login_status_output="$(printf '%s' "$login_status_output" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  if printf '%s' "$login_status_output" | grep -q "Logged in using an API key"; then
    report_ok "CODEX_LOGIN_STATUS" "api_key"
  else
    report_warn "CODEX_LOGIN_STATUS" "$login_status_output"
  fi
else
  login_status_output="$(printf '%s' "$login_status_output" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  report_fail "CODEX_LOGIN_STATUS" "${login_status_output:-failed}"
  exit 1
fi

openai_env_file="$(resolve_openai_env_file)"

if [[ -z "$openai_env_file" ]]; then
  report_fail "OPENAI_ENV_FILE" "unresolved"
  exit 1
fi
if [[ ! -r "$openai_env_file" ]]; then
  report_fail "OPENAI_ENV_FILE" "unreadable:${openai_env_file}"
  exit 1
fi
report_ok "OPENAI_ENV_FILE" "$openai_env_file"

vpn_wrapper="${HOME}/vpn.sh"
if [[ ! -x "$vpn_wrapper" ]]; then
  report_fail "VPN_WRAPPER" "missing_or_not_executable:${vpn_wrapper}"
  exit 1
fi
report_ok "VPN_WRAPPER" "$vpn_wrapper"

if route_info="$("$vpn_wrapper" route-info 2>&1)"; then
  route_info="$(printf '%s' "$route_info" | tr '\n' ';' | sed 's/;*$//')"
  report_ok "VPN_ROUTE_INFO" "$route_info"
else
  route_info="$(printf '%s' "$route_info" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  report_fail "VPN_ROUTE_INFO" "${route_info:-failed}"
  exit 1
fi

vpn_ip=""
if vpn_ip="$("$vpn_wrapper" ip 2>/dev/null | tail -n1 | tr -d '\r[:space:]')"; then
  if [[ "$vpn_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    report_ok "VPN_IP_CHECK" "$vpn_ip"
  else
    report_warn "VPN_IP_CHECK" "${vpn_ip:-empty}"
  fi
else
  report_warn "VPN_IP_CHECK" "failed"
fi

cat <<EOF
SMOKE_STEP linux_host_vpn_start=${vpn_wrapper} start
SMOKE_STEP linux_host_vpn_ip=${vpn_wrapper} ip
SMOKE_STEP linux_host_codex_login=CODEX_HOME=${codex_home} codex login status
SMOKE_STEP linux_host_codex_exec=CODEX_HOME=${codex_home} codex exec "Ответь ровно строкой OK"
EOF
