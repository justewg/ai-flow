#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

platform_env_file=""
host_name=""
conf_file=""
upstream="${OPS_BOT_NGINX_UPSTREAM:-http://127.0.0.1:8790}"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/nginx_ops_ingress_audit.sh [options]

Audit nginx ingress for host-level ai-flow surfaces:
- reads OPS_BOT_PUBLIC_BASE_URL from ai-flow.platform.env;
- derives <host> and inspects /etc/nginx/conf.d/<host>.conf by default;
- reports which locations already exist;
- prints append-only nginx snippet for missing locations.

Options:
  --platform-env-file <path>   Explicit platform env path. Default: <AI_FLOW_ROOT_DIR>/config/ai-flow.platform.env
  --host <hostname>            Override host name instead of deriving it from OPS_BOT_PUBLIC_BASE_URL
  --conf-file <path>           Explicit nginx conf file path. Default: /etc/nginx/conf.d/<host>.conf
  --upstream <url>             Upstream for proxy_pass. Default: http://127.0.0.1:8790
  -h, --help                   Show help.
EOF
}

canonicalize_file_path() {
  local value="${1:-}"
  [[ -n "$value" ]] || return 1
  if [[ -e "$value" ]]; then
    cd "$(dirname "$value")" && printf '%s/%s' "$(pwd -P)" "$(basename "$value")"
  else
    local parent
    parent="$(dirname "$value")"
    if [[ -d "$parent" ]]; then
      cd "$parent" && printf '%s/%s' "$(pwd -P)" "$(basename "$value")"
    else
      printf '%s' "$value"
    fi
  fi
}

read_env_key() {
  local env_file="$1"
  local key="$2"
  [[ -f "$env_file" ]] || return 0
  awk -F= -v wanted="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    {
      raw_key=$1
      sub(/^[[:space:]]*export[[:space:]]+/, "", raw_key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw_key)
      if (raw_key != wanted) next
      sub(/^[^=]*=/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/^"/, "", $0)
      gsub(/"$/, "", $0)
      print $0
      exit
    }
  ' "$env_file"
}

derive_host_from_public_base_url() {
  local public_base_url="$1"
  local stripped
  stripped="${public_base_url#http://}"
  stripped="${stripped#https://}"
  stripped="${stripped%%/*}"
  stripped="${stripped%%\?*}"
  stripped="${stripped%%#*}"
  printf '%s' "$stripped"
}

report_ok() { printf '✅ CHECK_OK %s=%s\n' "$1" "$2"; }
report_warn() { printf '⚠️ CHECK_WARN %s=%s\n' "$1" "$2"; }
report_fail() { printf '❌ CHECK_FAIL %s=%s\n' "$1" "$2"; }
report_action() { printf '👉 ACTION %s=%s\n' "$1" "$2"; }

has_pattern() {
  local file_path="$1"
  local pattern="$2"
  grep -Eq "$pattern" "$file_path"
}

print_missing_snippet() {
  local include_health="$1"
  local include_ops="$2"
  local include_debug="$3"
  local include_webhook="$4"
  local any="0"

  printf '\n## Suggested Nginx Snippet\n'
  printf '# Append only the missing blocks below into %s\n' "$conf_file"

  if [[ "$include_health" == "1" ]]; then
    any="1"
    cat <<EOF
location = /health {
    proxy_pass ${upstream}/health;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}

EOF
  fi

  if [[ "$include_ops" == "1" ]]; then
    any="1"
    cat <<EOF
location /ops/ {
    proxy_pass ${upstream};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}

EOF
  fi

  if [[ "$include_debug" == "1" ]]; then
    any="1"
    cat <<EOF
location /ops/debug/ {
    proxy_pass ${upstream};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}

EOF
  fi

  if [[ "$include_webhook" == "1" ]]; then
    any="1"
    cat <<EOF
location /telegram/webhook/ {
    proxy_pass ${upstream};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}

EOF
  fi

  if [[ "$any" == "0" ]]; then
    printf '# Nothing to append: all required locations are already present.\n'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform-env-file" >&2; exit 1; }
      platform_env_file="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || { echo "Missing value for --host" >&2; exit 1; }
      host_name="$2"
      shift 2
      ;;
    --conf-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --conf-file" >&2; exit 1; }
      conf_file="$2"
      shift 2
      ;;
    --upstream)
      [[ $# -ge 2 ]] || { echo "Missing value for --upstream" >&2; exit 1; }
      upstream="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$platform_env_file" ]]; then
  platform_env_file="$(codex_resolve_ai_flow_root_dir)/config/ai-flow.platform.env"
fi
platform_env_file="$(canonicalize_file_path "$platform_env_file")"

printf '## Nginx Ops Ingress Audit\n'

if [[ ! -f "$platform_env_file" ]]; then
  report_fail "PLATFORM_ENV_FILE" "missing:${platform_env_file}"
  report_action "PLATFORM_ENV_FILE" "Создай platform env и задай OPS_BOT_PUBLIC_BASE_URL=https://aiflow.ewg40.ru"
  exit 1
fi
report_ok "PLATFORM_ENV_FILE" "$platform_env_file"

public_base_url="$(read_env_key "$platform_env_file" "OPS_BOT_PUBLIC_BASE_URL")"
if [[ -z "$host_name" ]]; then
  host_name="$(derive_host_from_public_base_url "$public_base_url")"
fi

if [[ -z "$public_base_url" ]]; then
  report_warn "OPS_BOT_PUBLIC_BASE_URL" "missing"
  report_action "OPS_BOT_PUBLIC_BASE_URL" "Выстави внешний host-level URL, например https://aiflow.ewg40.ru"
else
  report_ok "OPS_BOT_PUBLIC_BASE_URL" "$public_base_url"
fi

if [[ -z "$host_name" ]]; then
  report_fail "NGINX_HOST_NAME" "missing"
  report_action "NGINX_HOST_NAME" "Передай --host <hostname> или заполни OPS_BOT_PUBLIC_BASE_URL в ai-flow.platform.env"
  exit 1
fi
report_ok "NGINX_HOST_NAME" "$host_name"

if [[ -z "$conf_file" ]]; then
  conf_file="/etc/nginx/conf.d/${host_name}.conf"
fi
report_ok "NGINX_CONF_FILE" "$conf_file"
report_ok "NGINX_UPSTREAM" "$upstream"

if [[ ! -e "$conf_file" ]]; then
  report_warn "NGINX_CONF_FILE" "missing:${conf_file}"
  report_action "NGINX_CONF_FILE" "Создай server block для ${host_name} и добавь locations ниже"
  print_missing_snippet "1" "1" "1" "1"
  exit 0
fi

if [[ ! -r "$conf_file" ]]; then
  report_fail "NGINX_CONF_READ" "permission-denied:${conf_file}"
  report_action "NGINX_CONF_READ" "Запусти аудит пользователем с правом чтения ${conf_file}"
  exit 1
fi

location_health_missing="0"
location_ops_missing="0"
location_debug_missing="0"
location_webhook_missing="0"

if has_pattern "$conf_file" 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/health([[:space:]]|\{)'; then
  report_ok "NGINX_LOCATION_HEALTH" "present"
else
  report_warn "NGINX_LOCATION_HEALTH" "missing"
  location_health_missing="1"
fi

if has_pattern "$conf_file" 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/([[:space:]]|\{)'; then
  report_ok "NGINX_LOCATION_OPS" "present"
else
  report_warn "NGINX_LOCATION_OPS" "missing"
  location_ops_missing="1"
fi

if has_pattern "$conf_file" 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/debug/([[:space:]]|\{)'; then
  report_ok "NGINX_LOCATION_OPS_DEBUG" "present"
else
  report_warn "NGINX_LOCATION_OPS_DEBUG" "missing"
  location_debug_missing="1"
fi

if has_pattern "$conf_file" 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/telegram/webhook/?([[:space:]]|\{)'; then
  report_ok "NGINX_LOCATION_TELEGRAM_WEBHOOK" "present"
else
  report_warn "NGINX_LOCATION_TELEGRAM_WEBHOOK" "missing"
  location_webhook_missing="1"
fi

if has_pattern "$conf_file" 'proxy_pass[[:space:]]+http://127\.0\.0\.1:8790(/health)?;'; then
  report_ok "NGINX_PROXY_PASS_8790" "present"
else
  report_warn "NGINX_PROXY_PASS_8790" "not-detected"
  report_action "NGINX_PROXY_PASS_8790" "Сверь upstream для ops-bot: ожидается ${upstream}"
fi

print_missing_snippet "$location_health_missing" "$location_ops_missing" "$location_debug_missing" "$location_webhook_missing"
