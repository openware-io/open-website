#!/usr/bin/env bash
# Fast-forward a clean worktree, then build a manifest-governed release image.
set -euo pipefail

REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -n "$(git status --porcelain=v1)" ]]; then
  echo "ERROR: release source worktree must be clean; refusing to stash or build from mixed changes." >&2
  exit 1
fi

echo "==> Fetch latest code"
git fetch "${REMOTE}"

echo "==> Fast-forward ${BRANCH}"
git pull --ff-only "${REMOTE}" "${BRANCH}"

echo "==> Build and push manifest-governed release image"
"${SCRIPT_DIR}/build-and-push.sh"
