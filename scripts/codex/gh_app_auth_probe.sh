#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file_path"
    set +a
  fi
}

load_env_file "${ROOT_DIR}/.env"
load_env_file "${ROOT_DIR}/.env.deploy"

bind="${GH_APP_BIND:-127.0.0.1}"
port="${GH_APP_PORT:-8787}"
secret="${GH_APP_INTERNAL_SECRET:-}"

if ! command -v node >/dev/null 2>&1; then
  echo "node command is required to run gh_app_auth_probe" >&2
  exit 1
fi

if [[ -z "$secret" ]]; then
  echo "GH_APP_INTERNAL_SECRET is required for token probe" >&2
  exit 1
fi

health_url="http://${bind}:${port}/health"
token_url="http://${bind}:${port}/token"

health_response="$(curl -fsS "$health_url")"
printf '%s\n' "$health_response" | node -e '
let data = "";
process.stdin.on("data", (chunk) => { data += chunk; });
process.stdin.on("end", () => {
  const payload = JSON.parse(data);
  if (payload.status !== "ok") {
    process.stderr.write("Health status is not ok\n");
    process.exit(1);
  }
  process.stdout.write("HEALTH_OK\n");
});
'

token_response="$(curl -fsS -H "X-Internal-Secret: ${secret}" "$token_url")"
printf '%s\n' "$token_response" | node -e '
let data = "";
process.stdin.on("data", (chunk) => { data += chunk; });
process.stdin.on("end", () => {
  const payload = JSON.parse(data);
  if (typeof payload.token !== "string" || payload.token.length === 0) {
    process.stderr.write("Token payload is missing token\n");
    process.exit(1);
  }
  if (typeof payload.expires_at !== "string" || payload.expires_at.length === 0) {
    process.stderr.write("Token payload is missing expires_at\n");
    process.exit(1);
  }
  const source = typeof payload.source === "string" ? payload.source : "unknown";
  process.stdout.write(`TOKEN_OK source=${source} expires_at=${payload.expires_at}\n`);
});
'
