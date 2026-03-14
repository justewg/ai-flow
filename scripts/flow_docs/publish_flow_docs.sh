#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/.tmp/flow-docs/site"
STATIC_OUTPUT_DIR="${ROOT_DIR}/.tmp/flow-docs/static"
SCALAR_OUTPUT_DIR="${ROOT_DIR}/.tmp/flow-docs/scalar"
BUNDLE_FILE="${ROOT_DIR}/.tmp/flow-docs/flow-web-docs-bundle.tgz"
SKIP_BUILD=0
SKIP_VALIDATION=0
PUBLISH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --bundle-file)
      BUNDLE_FILE="$2"
      shift 2
      ;;
    --static-output-dir)
      STATIC_OUTPUT_DIR="$2"
      shift 2
      ;;
    --scalar-output-dir)
      SCALAR_OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-validation)
      SKIP_VALIDATION=1
      shift
      ;;
    --publish)
      PUBLISH=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if (( SKIP_BUILD == 0 )); then
  python3 "${ROOT_DIR}/scripts/flow_docs/build_flow_docs.py" \
    --output-dir "${OUTPUT_DIR}" \
    --static-output-dir "${STATIC_OUTPUT_DIR}" \
    --scalar-output-dir "${SCALAR_OUTPUT_DIR}"
fi

if [[ ! -f "${OUTPUT_DIR}/redocly.yaml" ]]; then
  echo "Missing generated redocly.yaml in ${OUTPUT_DIR}" >&2
  exit 1
fi

if [[ ! -f "${STATIC_OUTPUT_DIR}/index.html" ]]; then
  echo "Missing generated static index.html in ${STATIC_OUTPUT_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SCALAR_OUTPUT_DIR}/index.html" ]]; then
  echo "Missing generated Scalar index.html in ${SCALAR_OUTPUT_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SCALAR_OUTPUT_DIR}/openapi.json" ]]; then
  echo "Missing generated Scalar openapi.json in ${SCALAR_OUTPUT_DIR}" >&2
  exit 1
fi

if (( SKIP_VALIDATION == 0 )); then
  if command -v npx >/dev/null 2>&1; then
    npx -y @redocly/cli check-config --config "${OUTPUT_DIR}/redocly.yaml"
  else
    echo "Skip Readocly validation: npx is not available" >&2
  fi
fi

mkdir -p "$(dirname "${BUNDLE_FILE}")"
tar -czf "${BUNDLE_FILE}" -C "${OUTPUT_DIR}" .
echo "Flow docs bundle archived to ${BUNDLE_FILE}"

if (( PUBLISH == 0 )); then
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required for publish mode" >&2
  exit 1
fi

: "${REDOCLY_AUTHORIZATION:?REDOCLY_AUTHORIZATION is required}"
: "${REDOCLY_ORGANIZATION:?REDOCLY_ORGANIZATION is required}"
: "${REDOCLY_PROJECT:?REDOCLY_PROJECT is required}"

readonly MOUNT_PATH="${REDOCLY_MOUNT_PATH:-/flow}"
readonly BRANCH_NAME="${GITHUB_REF_NAME:-main}"
readonly AUTHOR_LOGIN="${GITHUB_ACTOR:-flow-docs-bot}"
readonly AUTHOR_EMAIL="${AUTHOR_LOGIN}@users.noreply.github.com"
readonly SHORT_SHA="${GITHUB_SHA:-local}"
readonly MESSAGE="ISSUE-387: publish flow docs ${SHORT_SHA:0:8}"

pushd "${OUTPUT_DIR}" >/dev/null
shopt -s dotglob nullglob
FILES=(./*)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Nothing to publish from ${OUTPUT_DIR}" >&2
  exit 1
fi

npx -y @redocly/cli push \
  "${FILES[@]}" \
  --organization "${REDOCLY_ORGANIZATION}" \
  --project "${REDOCLY_PROJECT}" \
  --mount-path "${MOUNT_PATH}" \
  --branch "${BRANCH_NAME}" \
  --message "${MESSAGE}" \
  --author "${AUTHOR_LOGIN} <${AUTHOR_EMAIL}>" \
  --wait-for-deployment
popd >/dev/null
