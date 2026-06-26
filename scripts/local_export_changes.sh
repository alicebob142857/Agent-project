#!/usr/bin/env bash
set -euo pipefail

# Package Git working-tree changes for a VM to download with wget.
# Run this script from anywhere inside the local Git repository.
#
# Usage:
#   bash scripts/local_export_changes.sh [output_dir]
#
# Example:
#   bash scripts/local_export_changes.sh
#   cd tmp && python3 -m http.server 8000

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUT_DIR="${1:-${REPO_ROOT}/tmp}"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo no-git-head)"
STAMP="$(date +%Y%m%d-%H%M%S)"
PKG_NAME="git-changes-${SHORT_SHA}-${STAMP}.tar.gz"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-changes.XXXXXX")"
STAGE_DIR="${WORK_DIR}/payload"
FILE_LIST="${WORK_DIR}/files.txt"
DELETE_LIST="${WORK_DIR}/delete-list.txt"
MANIFEST="${WORK_DIR}/manifest.txt"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${OUT_DIR}" "${STAGE_DIR}"
# Keep only one update package in the output directory. Git remains the source
# of truth for rollback; this directory is only a transient download endpoint.
find "${OUT_DIR}" -maxdepth 1 -type f -name 'git-changes-*.tar.gz' -delete
: > "${FILE_LIST}"
: > "${DELETE_LIST}"

cd "${REPO_ROOT}"

# Existing tracked changes: staged and unstaged.
git diff --name-only --diff-filter=ACMRTUXB >> "${FILE_LIST}"
git diff --cached --name-only --diff-filter=ACMRTUXB >> "${FILE_LIST}"

# Deleted tracked files: staged and unstaged.
git diff --name-only --diff-filter=D >> "${DELETE_LIST}"
git diff --cached --name-only --diff-filter=D >> "${DELETE_LIST}"

# One-time cleanup for the old sync layout on the VM. These paths are safe to
# request deletion even if they do not exist on the target.
printf '%s\n' \
  'scripts/sync/README.md' \
  'scripts/sync/local_export_changes.sh' \
  'scripts/sync/vm_pull_changes.sh' \
  'scripts/sync' >> "${DELETE_LIST}"

# Untracked files, respecting .gitignore.
git ls-files --others --exclude-standard >> "${FILE_LIST}"

# Never package transient sync artifacts. By default packages live in ./tmp,
# and callers may also pass another output directory inside the repo.
OUT_DIR_ABS="$(cd "${OUT_DIR}" && pwd)"
OUT_DIR_REL=""
case "${OUT_DIR_ABS}/" in
  "${REPO_ROOT}/"*)
    OUT_DIR_REL="${OUT_DIR_ABS#${REPO_ROOT}/}"
    ;;
esac

filter_sync_artifacts() {
  local src="$1"
  local dst="${src}.filtered"
  : > "${dst}"
  while IFS= read -r relpath; do
    [[ -z "${relpath}" ]] && continue
    case "${relpath}" in
      tmp|tmp/*|./tmp|./tmp/*)
        continue
        ;;
    esac
    if [[ -n "${OUT_DIR_REL}" ]]; then
      case "${relpath}" in
        "${OUT_DIR_REL}"|"${OUT_DIR_REL}"/*)
          continue
          ;;
      esac
    fi
    printf '%s\n' "${relpath}" >> "${dst}"
  done < "${src}"
  mv "${dst}" "${src}"
}

filter_sync_artifacts "${FILE_LIST}"
filter_sync_artifacts "${DELETE_LIST}"

sort -u "${FILE_LIST}" -o "${FILE_LIST}"
sort -u "${DELETE_LIST}" -o "${DELETE_LIST}"

if [[ ! -s "${FILE_LIST}" && ! -s "${DELETE_LIST}" ]]; then
  echo "No Git changes found. Nothing to package."
  exit 0
fi

FILE_COUNT="$(grep -c . "${FILE_LIST}" || true)"
DELETE_COUNT="$(grep -c . "${DELETE_LIST}" || true)"

echo "Files to package (${FILE_COUNT}):"
if [[ -s "${FILE_LIST}" ]]; then
  sed 's/^/  + /' "${FILE_LIST}"
else
  echo "  (none)"
fi

echo
echo "Files to delete on VM (${DELETE_COUNT}):"
if [[ -s "${DELETE_LIST}" ]]; then
  sed 's/^/  - /' "${DELETE_LIST}"
else
  echo "  (none)"
fi
echo

while IFS= read -r relpath; do
  [[ -z "${relpath}" ]] && continue
  if [[ -f "${relpath}" ]]; then
    mkdir -p "${STAGE_DIR}/$(dirname "${relpath}")"
    cp -p "${relpath}" "${STAGE_DIR}/${relpath}"
  elif [[ -d "${relpath}" ]]; then
    mkdir -p "${STAGE_DIR}/${relpath}"
  fi
done < "${FILE_LIST}"

mkdir -p "${STAGE_DIR}/.sync-meta"
cp "${FILE_LIST}" "${STAGE_DIR}/.sync-meta/files.txt"
cp "${DELETE_LIST}" "${STAGE_DIR}/.sync-meta/delete-list.txt"

{
  echo "repo_root=${REPO_ROOT}"
  echo "git_head=${SHORT_SHA}"
  echo "created_at=${STAMP}"
  echo
  echo "[files]"
  cat "${FILE_LIST}"
  echo
  echo "[deletions]"
  cat "${DELETE_LIST}"
} > "${MANIFEST}"
cp "${MANIFEST}" "${STAGE_DIR}/.sync-meta/manifest.txt"

tar -C "${STAGE_DIR}" -czf "${OUT_DIR}/${PKG_NAME}" .
cp "${MANIFEST}" "${OUT_DIR}/latest-manifest.txt"
printf '%s\n' "${PKG_NAME}" > "${OUT_DIR}/latest.txt"
cp "${REPO_ROOT}/scripts/vm_pull_changes.sh" "${OUT_DIR}/vm_pull_changes.sh"
# Also publish the VM script at the repository root for the original
# start_share.sh workflow, where the HTTP server shares the current directory.
cp "${REPO_ROOT}/scripts/vm_pull_changes.sh" "${REPO_ROOT}/vm_pull_changes.sh"

# Automatically persist local code changes to GitHub after packaging.
# Disable with: AUTO_GIT_PUSH=0 bash scripts/local_export_changes.sh
AUTO_GIT_PUSH="${AUTO_GIT_PUSH:-1}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-sync: update ${STAMP}}"

if [[ "${AUTO_GIT_PUSH}" == "1" ]]; then
  echo
  echo "Running git add/commit/push..."
  git add -A

  if git diff --cached --quiet; then
    echo "No staged Git changes to commit."
  else
    git commit -m "${COMMIT_MESSAGE}"
  fi

  CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
  if [[ -z "${CURRENT_BRANCH}" ]]; then
    echo "Git push skipped: detached HEAD or no current branch." >&2
  elif git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git push
  elif git remote get-url origin >/dev/null 2>&1; then
    git push -u origin "${CURRENT_BRANCH}"
  else
    echo "Git push skipped: no upstream branch and no origin remote." >&2
  fi
else
  echo
  echo "Git add/commit/push skipped because AUTO_GIT_PUSH=${AUTO_GIT_PUSH}."
fi

cat <<EOF
Created package:
  ${OUT_DIR}/${PKG_NAME}

Latest marker:
  ${OUT_DIR}/latest.txt

Share the repository root with your trycloudflare helper:
  bash start_share.sh

After cloudflared prints a URL like https://xxxx.trycloudflare.com, run this on the VM:
  wget -O /data/vm_pull_changes.sh https://xxxx.trycloudflare.com/vm_pull_changes.sh
  bash /data/vm_pull_changes.sh https://xxxx.trycloudflare.com

The VM script will automatically find the package under /tmp/latest.txt and expand it into /data.
EOF
