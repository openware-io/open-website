#!/usr/bin/env bash
# Build and push the website image to Alibaba Cloud ACR.
set -euo pipefail

# ============ Config (can be overridden by env vars) ============
REGISTRY="${REGISTRY:-crpi-2xbf44rg544imbew.cn-hangzhou.personal.cr.aliyuncs.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-meta-cogni}"
IMAGE_NAME="${IMAGE_NAME:-meta-cogni-cms}"
PLATFORM="${PLATFORM:-linux/amd64}"
VERSION_FILE="${VERSION_FILE:-VERSION}"
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "ERROR: version file not found: ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must use semantic versioning, for example 1.0.0" >&2
  exit 1
fi

VERSION_IMAGE="${REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE="${REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:latest"

echo "==> Build images"
echo "    ${VERSION_IMAGE}"
echo "    ${LATEST_IMAGE}"

docker build --platform "${PLATFORM}" \
  -t "${VERSION_IMAGE}" \
  -t "${LATEST_IMAGE}" \
  -f Dockerfile .

echo "==> Login to ACR (optional via ACR_USERNAME / ACR_PASSWORD)"
if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
  printf '%s' "${ACR_PASSWORD}" | docker login "${REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
else
  echo "    No ACR credentials provided, using existing docker login session."
fi

echo "==> Push images"
docker push "${VERSION_IMAGE}"
docker push "${LATEST_IMAGE}"

cat <<EOF

==> Build and push completed
    Version        : ${VERSION}
    Version image  : ${VERSION_IMAGE}
    Latest image   : ${LATEST_IMAGE}

Next:
    TAG=${VERSION} ./scripts/deploy.sh
EOF
