#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.deploy"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_USER:?DEPLOY_USER is required}"
: "${DEPLOY_PATH:?DEPLOY_PATH is required}"

DEPLOY_PORT="${DEPLOY_PORT:-22}"
DEPLOY_SOURCE="${DEPLOY_SOURCE:-${ROOT_DIR}}"
DEPLOY_POST_COMMAND="${DEPLOY_POST_COMMAND:-}"

SOURCE_PATH="${DEPLOY_SOURCE%/}/"
TARGET="${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"
SSH_CMD=(ssh -p "${DEPLOY_PORT}" -o StrictHostKeyChecking=accept-new)

echo "[deploy] source: ${SOURCE_PATH}"
echo "[deploy] target: ${TARGET}"

"${SSH_CMD[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH}'"

rsync -az --delete \
  --exclude ".git/" \
  --exclude ".github/" \
  --exclude ".tmp/" \
  --exclude "node_modules/" \
  --exclude ".env" \
  --exclude ".env.*" \
  -e "ssh -p ${DEPLOY_PORT} -o StrictHostKeyChecking=accept-new" \
  "${SOURCE_PATH}" "${TARGET}"

if [[ -n "${DEPLOY_POST_COMMAND}" ]]; then
  echo "[deploy] running post command"
  "${SSH_CMD[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" "cd '${DEPLOY_PATH}' && ${DEPLOY_POST_COMMAND}"
fi

echo "[deploy] done"
