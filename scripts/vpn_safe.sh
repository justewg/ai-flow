#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="${OPENVPN_SERVICE_NAME:-openvpn-vanyavpn-safe.service}"
STATE_DIR="${AI_FLOW_VPN_STATE_DIR:-/tmp/ai-flow-vpn-safe}"
IP_CHECK_URL="${AI_FLOW_VPN_IP_CHECK_URL:-https://ifconfig.me}"
STATE_SLUG="$(printf '%s' "$SERVICE_NAME" | tr -c 'A-Za-z0-9._-' '_')"
STATE_FILE="${STATE_DIR}/${STATE_SLUG}.env"

usage() {
  cat <<EOF
Usage: vpn_safe.sh <command>

Commands:
  start
  stop
  restart
  enable
  disable
  status
  ip
  route-info

Environment:
  OPENVPN_SERVICE_NAME  Override systemd service name.
                        Default: ${SERVICE_NAME}
  AI_FLOW_VPN_CLIENT_IP Explicit SSH client IP to preserve via eth0.
                        Default: first field from SSH_CONNECTION.
  AI_FLOW_VPN_STATE_DIR Override state dir for preserved route metadata.
                        Default: ${STATE_DIR}
  AI_FLOW_VPN_IP_CHECK_URL
                        Override external IPv4 check endpoint.
                        Default: ${IP_CHECK_URL}
EOF
}

run_systemctl() {
  local action="$1"
  shift || true
  sudo systemctl "${action}" "${SERVICE_NAME}" "$@"
}

current_client_ip() {
  if [[ -n "${AI_FLOW_VPN_CLIENT_IP:-}" ]]; then
    printf '%s\n' "${AI_FLOW_VPN_CLIENT_IP}"
    return
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    printf '%s\n' "${SSH_CONNECTION%% *}"
  fi
}

current_default_route() {
  ip route show default 2>/dev/null | head -n 1
}

current_default_gateway() {
  current_default_route | awk '{for (i=1; i<=NF; i++) if ($i == "via") {print $(i+1); exit}}'
}

current_default_iface() {
  current_default_route | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}'
}

save_state() {
  local client_ip="$1"
  local default_gateway="$2"
  local default_iface="$3"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_FILE" <<EOF
client_ip=${client_ip}
default_gateway=${default_gateway}
default_iface=${default_iface}
EOF
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

clear_preserved_route() {
  local client_ip default_gateway default_iface
  client_ip=""
  default_gateway=""
  default_iface=""
  load_state
  if [[ -n "$client_ip" ]]; then
    sudo ip route del "${client_ip}/32" via "${default_gateway}" dev "${default_iface}" 2>/dev/null \
      || sudo ip route del "${client_ip}/32" 2>/dev/null \
      || true
  fi
  rm -f "$STATE_FILE"
}

ensure_preserved_route() {
  local client_ip default_gateway default_iface
  client_ip="$(current_client_ip || true)"
  default_gateway="$(current_default_gateway || true)"
  default_iface="$(current_default_iface || true)"

  if [[ -z "$client_ip" ]]; then
    echo "WARN: SSH client IP is unknown; no bypass route will be preserved." >&2
    return 0
  fi
  if [[ -z "$default_gateway" || -z "$default_iface" ]]; then
    echo "Cannot determine default route before VPN start." >&2
    exit 1
  fi

  sudo ip route replace "${client_ip}/32" via "${default_gateway}" dev "${default_iface}"
  save_state "$client_ip" "$default_gateway" "$default_iface"
  echo "PRESERVED_SSH_ROUTE=${client_ip}/32 via ${default_gateway} dev ${default_iface}"
}

show_route_info() {
  local client_ip default_gateway default_iface
  client_ip="$(current_client_ip || true)"
  default_gateway="$(current_default_gateway || true)"
  default_iface="$(current_default_iface || true)"
  echo "SERVICE_NAME=${SERVICE_NAME}"
  echo "SSH_CLIENT_IP=${client_ip:-unknown}"
  echo "DEFAULT_GATEWAY=${default_gateway:-unknown}"
  echo "DEFAULT_IFACE=${default_iface:-unknown}"
  if [[ -n "$client_ip" ]]; then
    ip route get "$client_ip" 2>/dev/null || true
  fi
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    start)
      ensure_preserved_route
      run_systemctl start
      ;;
    stop)
      run_systemctl stop
      clear_preserved_route
      ;;
    restart)
      ensure_preserved_route
      run_systemctl restart
      ;;
    enable)
      run_systemctl enable
      ;;
    disable)
      run_systemctl disable
      ;;
    status)
      run_systemctl status --no-pager
      ;;
    ip)
      curl -4 -fsS "$IP_CHECK_URL"
      echo
      ;;
    route-info)
      show_route_info
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Unknown command: $1" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
