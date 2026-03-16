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

runtime_mode="$(codex_resolve_config_value "FLOW_HOST_RUNTIME_MODE" "")"
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

openai_env_file="$(codex_resolve_config_value "OPENAI_ENV_FILE" "")"
if [[ -z "$openai_env_file" && -f "/etc/ai-flow/secrets/platform/openai.env" ]]; then
  openai_env_file="/etc/ai-flow/secrets/platform/openai.env"
fi
if [[ -z "$openai_env_file" && -f "${HOME}/.config/ai-flow/openai.env" ]]; then
  openai_env_file="${HOME}/.config/ai-flow/openai.env"
fi

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
