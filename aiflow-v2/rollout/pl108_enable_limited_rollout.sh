#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pl108_enable_limited_rollout.sh --env-file <path> --allow-task <TASK_ID> [--allow-task <TASK_ID> ...]

Updates the flow env file for limited rollout and writes a .bak backup next to it.
EOF
}

env_file=""
declare -a allow_tasks=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      env_file="${2:-}"
      shift 2
      ;;
    --allow-task)
      allow_tasks+=("${2:-}")
      shift 2
      ;;
    -h|--help)
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

if [[ -z "$env_file" || ${#allow_tasks[@]} -eq 0 ]]; then
  usage
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Env file not found: $env_file" >&2
  exit 1
fi

backup_file="${env_file}.bak.$(date -u '+%Y%m%dT%H%M%SZ')"
cp "$env_file" "$backup_file"

allowed_csv="$(printf '%s\n' "${allow_tasks[@]}" | awk 'NF {print}' | paste -sd ',' -)"
tmp_file="$(mktemp "${env_file}.tmp.XXXXXX")"

upsert_key() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$file_path"; then
    awk -v key="$key" -v value="$value" '
      BEGIN { replaced = 0 }
      $0 ~ ("^" key "=") {
        print key "=" value
        replaced = 1
        next
      }
      { print }
      END {
        if (replaced == 0) {
          print key "=" value
        }
      }
    ' "$file_path" > "${file_path}.next"
    mv "${file_path}.next" "$file_path"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file_path"
  fi
}

cp "$env_file" "$tmp_file"
upsert_key "$tmp_file" "FLOW_V2_ROLLOUT_MODE" "limited"
upsert_key "$tmp_file" "FLOW_V2_ALLOWED_TASK_IDS" "$allowed_csv"
upsert_key "$tmp_file" "FLOW_V2_EMERGENCY_ON_BREACH" "1"
upsert_key "$tmp_file" "FLOW_V2_MAX_EXECUTIONS_PER_TASK" "3"
upsert_key "$tmp_file" "FLOW_V2_MAX_TOKEN_USAGE_PER_TASK" "60000"
upsert_key "$tmp_file" "FLOW_V2_MAX_ESTIMATED_COST_PER_TASK" "25"
mv "$tmp_file" "$env_file"

printf 'PL108_ENV_UPDATED=%s\n' "$env_file"
printf 'PL108_ENV_BACKUP=%s\n' "$backup_file"
printf 'PL108_ALLOWED_TASK_IDS=%s\n' "$allowed_csv"
