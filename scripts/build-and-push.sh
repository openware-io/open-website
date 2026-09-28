#!/usr/bin/env bash
# Build a schema-v2 release image for the standalone website.
set -euo pipefail

# ============ Config (can be overridden by env vars) ============
REGISTRY="${REGISTRY:-ghcr.io/openware-io}"
ACR_NAMESPACE="${ACR_NAMESPACE:-openware}"
IMAGE_NAME="${IMAGE_NAME:-open-website}"
PLATFORM="${PLATFORM:-linux/amd64}"
VERSION_FILE="${VERSION_FILE:-VERSION}"
FORMAL_RELEASE="${FORMAL_RELEASE:-0}"
RELEASE_MANIFEST_PATH="${RELEASE_MANIFEST_PATH:-}"
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "ERROR: version file not found: ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must use semantic versioning, for example 1.0.0" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: release worktree must be clean" >&2
  exit 1
fi

REVISION="$(git rev-parse --short HEAD)"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

REPOSITORY="${REGISTRY%/}"
if [[ -n "${ACR_NAMESPACE}" ]]; then REPOSITORY="${REPOSITORY}/${ACR_NAMESPACE#/}"; fi
if [[ "${FORMAL_RELEASE}" == "1" ]]; then
  TAG="${VERSION}"
  RELEASE_TYPE="formal"
  ALLOW_TAG_OVERWRITE=false
  if docker buildx imagetools inspect "${REPOSITORY}/${IMAGE_NAME}:${TAG}" >/dev/null 2>&1; then
    echo "ERROR: formal image tag already exists and cannot be overwritten: ${REPOSITORY}/${IMAGE_NAME}:${TAG}" >&2
    exit 1
  fi
else
  TAG="${VERSION}-SNAPSHOT"
  RELEASE_TYPE="development"
  ALLOW_TAG_OVERWRITE=true
fi
VERSION_IMAGE="${REPOSITORY}/${IMAGE_NAME}:${TAG}"

echo "==> Build release image"
echo "    ${VERSION_IMAGE}"

docker build --platform "${PLATFORM}" \
  --pull=false \
  --build-arg "IMAGE_NAME=${IMAGE_NAME}" \
  --build-arg "IMAGE_VERSION=${TAG}" \
  --build-arg "IMAGE_REVISION=${REVISION}" \
  --build-arg "IMAGE_CREATED=${CREATED_AT}" \
  --build-arg "IMAGE_SOURCE=https://github.com/openware-io/open-website" \
  -t "${VERSION_IMAGE}" \
  -f Dockerfile .

echo "==> Login to ACR (optional via ACR_USERNAME / ACR_PASSWORD)"
if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
  printf '%s' "${ACR_PASSWORD}" | docker login "${REGISTRY}" -u "${ACR_USERNAME}" --password-stdin
else
  echo "    No ACR credentials provided, using existing docker login session."
fi

echo "==> Push images"
docker push "${VERSION_IMAGE}"

DIGEST="$(docker buildx imagetools inspect "${VERSION_IMAGE}" --format '{{json .Manifest}}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])')"
if ! [[ "${DIGEST}" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "ERROR: cannot verify registry digest for ${VERSION_IMAGE}" >&2
  exit 1
fi
if [[ -z "${RELEASE_MANIFEST_PATH}" ]]; then
  RELEASE_MANIFEST_PATH=".outputs/releases/open-website-${TIMESTAMP}-${REVISION}.json"
fi
mkdir -p "$(dirname "${RELEASE_MANIFEST_PATH}")"
printf '{"schemaVersion":2,"createdAt":"%s","buildIdentity":"%s.%s.%s","releaseType":"%s","allowTagOverwrite":%s,"sourceRevision":"%s","registry":"%s","deploymentTargets":["%s"],"services":{"%s":{"moduleVersion":"%s","tag":"%s","sourceRevision":"%s","registry":"%s","image":"%s","digest":"%s"}}}\n' \
  "${CREATED_AT}" "${RELEASE_TYPE}" "${TIMESTAMP}" "${REVISION}" "${RELEASE_TYPE}" "${ALLOW_TAG_OVERWRITE}" "${REVISION}" "${REPOSITORY}" "${IMAGE_NAME}" "${IMAGE_NAME}" "${TAG}" "${TAG}" "${REVISION}" "${REPOSITORY}" "${VERSION_IMAGE}" "${DIGEST}" > "${RELEASE_MANIFEST_PATH}"

printf '\n==> Build and push completed\n    Version        : %s\n    Version image  : %s\n    Manifest       : %s\n\nNext:\n    RELEASE_MANIFEST_PATH=%s ./scripts/deploy.sh\n' \
  "${TAG}" "${VERSION_IMAGE}" "${RELEASE_MANIFEST_PATH}" "${RELEASE_MANIFEST_PATH}"
