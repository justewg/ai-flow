#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SITE_DIR=""
DEPLOY_ROOT=""
RELEASE_ID=""

usage() {
  cat <<'EOF'
Usage: scripts/flow_docs/deploy_flow_docs.sh --site-dir <dir> --deploy-root <dir> [--release-id <id>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-dir)
      SITE_DIR="$2"
      shift 2
      ;;
    --deploy-root)
      DEPLOY_ROOT="$2"
      shift 2
      ;;
    --release-id)
      RELEASE_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${SITE_DIR}" || -z "${DEPLOY_ROOT}" ]]; then
  usage
  exit 1
fi

if [[ ! -f "${SITE_DIR}/redocly.yaml" ]]; then
  echo "Missing redocly.yaml in ${SITE_DIR}" >&2
  exit 1
fi

if [[ -z "${RELEASE_ID}" ]]; then
  RELEASE_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
fi

DEPLOY_ROOT="${DEPLOY_ROOT%/}"
RELEASES_DIR="${DEPLOY_ROOT}/releases"
RELEASE_DIR="${RELEASES_DIR}/${RELEASE_ID}"
CURRENT_LINK="${DEPLOY_ROOT}/current"
BIN_DIR="${DEPLOY_ROOT}/bin"

mkdir -p "${RELEASE_DIR}" "${BIN_DIR}"
rsync -az --delete "${SITE_DIR}/" "${RELEASE_DIR}/"
install -m 755 "${SCRIPT_DIR}/serve_flow_docs.sh" "${BIN_DIR}/serve_flow_docs.sh"
ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"

echo "FLOW_DOCS_DEPLOY_ROOT=${DEPLOY_ROOT}"
echo "FLOW_DOCS_RELEASE_ID=${RELEASE_ID}"
echo "FLOW_DOCS_RELEASE_DIR=${RELEASE_DIR}"
echo "FLOW_DOCS_CURRENT_LINK=${CURRENT_LINK}"
echo "FLOW_DOCS_SERVE_SCRIPT=${BIN_DIR}/serve_flow_docs.sh"
