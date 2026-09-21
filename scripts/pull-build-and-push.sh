#!/usr/bin/env bash
# Fast-forward pull latest code, then build and push versioned/latest images.
set -euo pipefail

REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

STASHED=0
cleanup() {
  if [[ "${STASHED}" == "1" ]]; then
    git stash pop || {
      echo "WARNING: stash pop failed, please resolve manually." >&2
      exit 1
    }
  fi
}
trap cleanup EXIT

if [[ -n "$(git status --porcelain=v1)" ]]; then
  echo "==> Detected local changes, auto-stashing before pull"
  git stash push -u -m "auto-stash-before-pull-build-and-push"
  STASHED=1
fi

echo "==> Fetch latest code"
git fetch "${REMOTE}"

echo "==> Fast-forward ${BRANCH}"
git pull --ff-only "${REMOTE}" "${BRANCH}"

echo "==> Build and push images"
"${SCRIPT_DIR}/build-and-push.sh"
