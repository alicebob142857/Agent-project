#!/usr/bin/env bash
set -euo pipefail

# VM side: download latest Git-change package and expand it into /data.
# It preserves local repo-relative paths:
#   src/a.py     -> /data/src/a.py
#   scripts/x.sh -> /data/scripts/x.sh
#
# Usage:
#   bash /data/vm_pull_changes.sh <trycloudflare_base_url> [target_dir=/data]
#
# Works with either of these shares:
#   root share: https://xxxx.trycloudflare.com           (package under /tmp)
#   tmp share:  https://xxxx.trycloudflare.com           (package at root)

BASE_URL="${1:-}"
TARGET_DIR="${2:-/data}"

if [[ -z "${BASE_URL}" ]]; then
  echo "Usage: bash /data/vm_pull_changes.sh <trycloudflare_base_url> [target_dir=/data]" >&2
  exit 2
fi

BASE_URL="${BASE_URL%/}"
TMP_DIR="$(mktemp -d /tmp/vm-git-changes.XXXXXX)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

mkdir -p "${TARGET_DIR}"

try_wget() {
  local url="$1"
  local out="$2"
  echo "GET ${url}"
  wget -q -O "${out}" "${url}"
}

resolve_package_base_url() {
  local latest_out="$1"

  if try_wget "${BASE_URL}/latest.txt" "${latest_out}"; then
    printf '%s\n' "${BASE_URL}"
    return 0
  fi

  if try_wget "${BASE_URL}/tmp/latest.txt" "${latest_out}"; then
    printf '%s\n' "${BASE_URL}/tmp"
    return 0
  fi

  echo "Could not fetch latest.txt from either:" >&2
  echo "  ${BASE_URL}/latest.txt" >&2
  echo "  ${BASE_URL}/tmp/latest.txt" >&2
  exit 1
}

echo "Resolving latest package..."
LATEST_FILE="${TMP_DIR}/latest.txt"
PKG_BASE_URL="$(resolve_package_base_url "${LATEST_FILE}" | tail -n 1)"
PKG_NAME="$(tr -d '[:space:]' < "${LATEST_FILE}")"

if [[ -z "${PKG_NAME}" ]]; then
  echo "latest.txt is empty." >&2
  exit 1
fi

echo "Package base URL: ${PKG_BASE_URL}"
echo "Package name: ${PKG_NAME}"

PACKAGE_PATH="${TMP_DIR}/${PKG_NAME}"
try_wget "${PKG_BASE_URL}/${PKG_NAME}" "${PACKAGE_PATH}"

if [[ ! -s "${PACKAGE_PATH}" ]]; then
  echo "Downloaded package is empty: ${PACKAGE_PATH}" >&2
  exit 1
fi

echo "Extracting package..."
mkdir -p "${TMP_DIR}/payload"
tar -xzf "${PACKAGE_PATH}" -C "${TMP_DIR}/payload"

MANIFEST="${TMP_DIR}/payload/.sync-meta/manifest.txt"
if [[ -f "${MANIFEST}" ]]; then
  echo ""
  echo "Package manifest:"
  sed -n '1,200p' "${MANIFEST}"
fi

DELETE_LIST="${TMP_DIR}/payload/.sync-meta/delete-list.txt"
SAVED_DELETE_LIST="${TMP_DIR}/delete-list.txt"
if [[ -f "${DELETE_LIST}" ]]; then
  cp "${DELETE_LIST}" "${SAVED_DELETE_LIST}"
else
  : > "${SAVED_DELETE_LIST}"
fi

echo ""
echo "Applying package into ${TARGET_DIR} ..."
rm -rf "${TMP_DIR}/payload/.sync-meta"
cp -a "${TMP_DIR}/payload/." "${TARGET_DIR}/"

echo "Copied files:"
find "${TMP_DIR}/payload" -type f | sed "s#^${TMP_DIR}/payload/#  + #" | sed -n '1,200p'

if [[ -s "${SAVED_DELETE_LIST}" ]]; then
  echo ""
  echo "Applying deletions inside ${TARGET_DIR}:"
  while IFS= read -r relpath; do
    [[ -z "${relpath}" ]] && continue
    case "${relpath}" in
      /*|*..*)
        echo "  ! skip unsafe deletion path: ${relpath}" >&2
        ;;
      *)
        if [[ -e "${TARGET_DIR}/${relpath}" || -L "${TARGET_DIR}/${relpath}" ]]; then
          echo "  - ${relpath}"
          rm -rf "${TARGET_DIR:?}/${relpath}"
        else
          echo "  - ${relpath} (already absent)"
        fi
        ;;
    esac
  done < "${SAVED_DELETE_LIST}"
fi

echo ""
echo "Done. Files are now expanded under: ${TARGET_DIR}"
