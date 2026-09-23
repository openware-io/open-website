#!/usr/bin/env bash
# Deploy the website image to ACK.
set -euo pipefail

# ============ Config (can be overridden by env vars) ============
REGISTRY="${REGISTRY:-registry.example.com}"
ACR_NAMESPACE="${ACR_NAMESPACE:-openware}"
IMAGE_NAME="${IMAGE_NAME:-open-website}"
VERSION_FILE="${VERSION_FILE:-VERSION}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-openware}"
# ==============================================================

DEFAULT_TAG="latest"
if [[ -f "${VERSION_FILE}" ]]; then
  FILE_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
  if [[ "${FILE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DEFAULT_TAG="${FILE_VERSION}"
  fi
fi
TAG="${TAG:-${DEFAULT_TAG}}"

FULL_IMAGE="${REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:${TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/k8s"

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or kubeconfig is missing"; exit 1; }

echo "==> Target image : ${FULL_IMAGE}"
echo "==> Namespace    : ${DEPLOY_NAMESPACE}"

echo "==> Apply Namespace"
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "==> Apply Deployment and update image"
kubectl apply -f "${K8S_DIR}/deployment.yaml"
kubectl -n "${DEPLOY_NAMESPACE}" set image deployment/xch-cms \
  "xch-cms=${FULL_IMAGE}"
kubectl -n "${DEPLOY_NAMESPACE}" annotate deployment/xch-cms \
  kubernetes.io/change-cause="deploy ${FULL_IMAGE}" --overwrite >/dev/null

echo "==> Apply Service / Ingress"
kubectl apply -f "${K8S_DIR}/service.yaml"
kubectl apply -f "${K8S_DIR}/ingress.yaml"

echo "==> Wait for rollout"
kubectl -n "${DEPLOY_NAMESPACE}" rollout status deployment/xch-cms --timeout=300s

cat <<EOF

==> Deployment completed
    Check : kubectl -n ${DEPLOY_NAMESPACE} get deploy,svc,ingress
    Logs  : kubectl -n ${DEPLOY_NAMESPACE} logs -f deploy/xch-cms
EOF
