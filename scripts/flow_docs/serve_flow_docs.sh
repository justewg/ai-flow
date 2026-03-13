#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_DIR="${FLOW_DOCS_PROJECT_DIR:-${ROOT_DIR}/.tmp/flow-docs/site}"
HOST="${FLOW_DOCS_PREVIEW_HOST:-127.0.0.1}"
PORT="${FLOW_DOCS_PREVIEW_PORT:-4410}"
PRODUCT="${FLOW_DOCS_PREVIEW_PRODUCT:-realm}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --product)
      PRODUCT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${PROJECT_DIR}/redocly.yaml" ]]; then
  echo "Missing redocly.yaml in ${PROJECT_DIR}" >&2
  exit 1
fi

if command -v redocly >/dev/null 2>&1; then
  exec redocly preview \
    --product="${PRODUCT}" \
    --project-dir="${PROJECT_DIR}" \
    --host="${HOST}" \
    --port="${PORT}"
fi

exec npx -y @redocly/cli preview \
  --product="${PRODUCT}" \
  --project-dir="${PROJECT_DIR}" \
  --host="${HOST}" \
  --port="${PORT}"
