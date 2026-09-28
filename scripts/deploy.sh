#!/usr/bin/env bash
# Deploy the website image from a schema-v2 release manifest.
set -euo pipefail

# ============ Config (can be overridden by env vars) ============
REGISTRY="${REGISTRY:-ghcr.io/openware-io}"
ACR_NAMESPACE="${ACR_NAMESPACE:-openware}"
IMAGE_NAME="${IMAGE_NAME:-open-website}"
RELEASE_MANIFEST_PATH="${RELEASE_MANIFEST_PATH:?ERROR: RELEASE_MANIFEST_PATH is required}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-openware}"
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/k8s"

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or kubeconfig is missing"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required to validate release manifests"; exit 1; }
[[ -f "${RELEASE_MANIFEST_PATH}" ]] || { echo "ERROR: release manifest not found: ${RELEASE_MANIFEST_PATH}"; exit 1; }

FULL_IMAGE="$(python3 - "${RELEASE_MANIFEST_PATH}" "${REGISTRY}" "${ACR_NAMESPACE}" "${IMAGE_NAME}" <<'PY'
import json,re,sys
p,registry,namespace,name=sys.argv[1:]
m=json.load(open(p,encoding='utf-8')); e=m.get('services',{}).get(name,{})
prefix=registry.rstrip('/') + (('/'+namespace.strip('/')) if namespace else '')
tag=e.get('tag',''); image=e.get('image',''); digest=e.get('digest','')
if m.get('schemaVersion') != 2 or m.get('releaseType') not in ('development','formal'): raise SystemExit('invalid schema-v2 manifest')
if not re.fullmatch(r'\d+\.\d+\.\d+(-SNAPSHOT)?',tag) or e.get('moduleVersion') != tag: raise SystemExit('invalid tag')
if m['releaseType']=='development' and not tag.endswith('-SNAPSHOT'): raise SystemExit('development tag must end with -SNAPSHOT')
if m['releaseType']=='formal' and tag.endswith('-SNAPSHOT'): raise SystemExit('formal tag cannot be SNAPSHOT')
if image != f'{prefix}/{name}:{tag}' or '@sha256:' in image or not re.fullmatch(r'sha256:[a-f0-9]{64}',digest): raise SystemExit('invalid release image')
print(image)
PY
)"

echo "==> Target image : ${FULL_IMAGE}"
echo "==> Namespace    : ${DEPLOY_NAMESPACE}"

echo "==> Apply Namespace"
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "==> Apply manifest-rendered deployment"
RENDERED_DEPLOYMENT="$(mktemp)"
trap 'rm -f "${RENDERED_DEPLOYMENT}"' EXIT
sed "s|__APP_IMAGE_OPEN_WEBSITE__|${FULL_IMAGE}|g" "${K8S_DIR}/deployment.yaml" > "${RENDERED_DEPLOYMENT}"
if grep -q '__APP_IMAGE_' "${RENDERED_DEPLOYMENT}"; then echo "ERROR: unresolved image placeholder" >&2; exit 1; fi
kubectl apply -f "${RENDERED_DEPLOYMENT}"
kubectl -n "${DEPLOY_NAMESPACE}" annotate deployment/xch-cms \
  kubernetes.io/change-cause="deploy ${FULL_IMAGE}" --overwrite >/dev/null

echo "==> Apply Service / Ingress"
kubectl apply -f "${K8S_DIR}/service.yaml"
kubectl apply -f "${K8S_DIR}/ingress.yaml"

echo "==> Wait for rollout"
kubectl -n "${DEPLOY_NAMESPACE}" rollout status deployment/xch-cms --timeout=300s
ACTUAL_IMAGE="$(kubectl -n "${DEPLOY_NAMESPACE}" get deployment xch-cms -o jsonpath='{.spec.template.spec.containers[0].image}')"
[[ "${ACTUAL_IMAGE}" == "${FULL_IMAGE}" ]] || { echo "ERROR: deployment image drift: ${ACTUAL_IMAGE}" >&2; exit 1; }

cat <<EOF

==> Deployment completed
    Check : kubectl -n ${DEPLOY_NAMESPACE} get deploy,svc,ingress
    Logs  : kubectl -n ${DEPLOY_NAMESPACE} logs -f deploy/xch-cms
EOF
