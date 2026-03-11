#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_LOG_FILE="${ROOT_DIR}/.flow/tmp/net_probe_host.log"

usage() {
  cat <<'EOF'
Usage:
  scripts/net_probe_host.sh run [duration-sec] [interval-sec] [output-log]
  scripts/net_probe_host.sh monitor [interval-sec] [output-log]
  scripts/net_probe_host.sh summary [output-log]

Defaults:
  duration-sec: 900   (15 minutes)
  interval-sec: 20
  output-log:   .flow/tmp/net_probe_host.log
EOF
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

resolve_dns_ips() {
  local host="$1"
  local ips=""

  if command -v dscacheutil >/dev/null 2>&1; then
    ips="$(
      dscacheutil -q host -a name "$host" 2>/dev/null |
        awk '/ip_address/{print $2}' |
        paste -sd, -
    )"
  elif command -v getent >/dev/null 2>&1; then
    ips="$(
      getent hosts "$host" 2>/dev/null |
        awk '{print $1}' |
        paste -sd, -
    )"
  elif command -v dig >/dev/null 2>&1; then
    ips="$(
      dig +short "$host" 2>/dev/null |
        awk 'NF' |
        paste -sd, -
    )"
  fi

  if [[ -z "$ips" ]]; then
    printf 'none'
  else
    printf '%s' "$ips"
  fi
}

print_summary() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    echo "Log file not found: $log_file"
    exit 1
  fi

  awk '
  BEGIN {
    total=0; curl_ok=0; curl_fail=0; gh_ok=0; gh_fail=0; dns_none=0;
  }
  {
    total++;
    dns_val="";
    curl_val="";
    gh_val="";
    for (i=1; i<=NF; i++) {
      if ($i ~ /^dns=/)     { split($i,a,"="); dns_val=a[2]; dns_seen[dns_val]=1; }
      if ($i ~ /^curl_rc=/) { split($i,a,"="); curl_val=a[2]; }
      if ($i ~ /^gh_rc=/)   { split($i,a,"="); gh_val=a[2]; }
    }

    if (dns_val=="none") { dns_none++; }
    if (curl_val=="0") { curl_ok++; } else { curl_fail++; }
    if (gh_val=="0") { gh_ok++; } else { gh_fail++; }
  }
  END {
    dns_unique=0;
    for (k in dns_seen) { dns_unique++; }
    printf("SUMMARY total=%d curl_ok=%d curl_fail=%d gh_ok=%d gh_fail=%d dns_none=%d dns_unique=%d\n",
           total, curl_ok, curl_fail, gh_ok, gh_fail, dns_none, dns_unique);
  }' "$log_file"
}

collect_sample() {
  local log_file="$1"
  local ts dns_ips curl_rc gh_rc gh_rate

  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  dns_ips="$(resolve_dns_ips "api.github.com")"

  if curl -sS -o /dev/null --max-time 6 https://api.github.com; then
    curl_rc=0
  else
    curl_rc=$?
  fi

  gh_rc=0
  gh_rate="na"
  if command -v gh >/dev/null 2>&1; then
    if gh_rate="$(gh api rate_limit --jq '.rate.remaining' 2>/dev/null)"; then
      gh_rc=0
    else
      gh_rc=$?
      gh_rate="na"
    fi
  else
    gh_rc=127
  fi

  printf '%s dns=%s curl_rc=%s gh_rc=%s gh_rate=%s\n' \
    "$ts" "$dns_ips" "$curl_rc" "$gh_rc" "$gh_rate" | tee -a "$log_file"
}

run_probe() {
  local duration_sec="${1:-900}"
  local interval_sec="${2:-20}"
  local log_file="${3:-$DEFAULT_LOG_FILE}"

  if ! is_uint "$duration_sec" || (( duration_sec < 5 )); then
    echo "Invalid duration-sec: $duration_sec (expected integer >= 5)"
    exit 1
  fi
  if ! is_uint "$interval_sec" || (( interval_sec < 1 )); then
    echo "Invalid interval-sec: $interval_sec (expected integer >= 1)"
    exit 1
  fi

  mkdir -p "$(dirname "$log_file")"

  local iterations=$(( duration_sec / interval_sec ))
  if (( duration_sec % interval_sec != 0 )); then
    iterations=$(( iterations + 1 ))
  fi

  local i
  for (( i=1; i<=iterations; i++ )); do
    collect_sample "$log_file"

    if (( i < iterations )); then
      sleep "$interval_sec"
    fi
  done

  echo "LOG_FILE=$log_file"
  print_summary "$log_file"
}

monitor_probe() {
  local interval_sec="${1:-20}"
  local log_file="${2:-$DEFAULT_LOG_FILE}"

  if ! is_uint "$interval_sec" || (( interval_sec < 1 )); then
    echo "Invalid interval-sec: $interval_sec (expected integer >= 1)"
    exit 1
  fi

  mkdir -p "$(dirname "$log_file")"
  echo "MONITOR_START interval_sec=$interval_sec log_file=$log_file"
  echo "Stop with Ctrl+C"

  while true; do
    collect_sample "$log_file"
    sleep "$interval_sec"
  done
}

main() {
  local cmd="${1:-run}"
  case "$cmd" in
    run)
      run_probe "${2:-900}" "${3:-20}" "${4:-$DEFAULT_LOG_FILE}"
      ;;
    monitor)
      monitor_probe "${2:-20}" "${3:-$DEFAULT_LOG_FILE}"
      ;;
    summary)
      print_summary "${2:-$DEFAULT_LOG_FILE}"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
