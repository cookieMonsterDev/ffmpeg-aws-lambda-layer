#!/usr/bin/env bash
#
# Downloads the latest FFmpeg static release from johnvansickle.com and
# stages it under ./build/layer/bin so that `aws cloudformation package`
# can upload it as a Lambda Layer.
#
# Why johnvansickle?
#   - Statically-linked single-binary tarballs, refreshed for every
#     upstream FFmpeg release.
#   - Built against glibc 2.17 so the binary runs unmodified on every
#     Lambda runtime including Amazon Linux 2023 (glibc 2.34).
#   - Always pulled via the unversioned "release" URL, so this script
#     automatically picks up new versions (7.0.2 -> 7.1.x -> 8.x ...).
#   - The alternative source, BtbN/FFmpeg-Builds, ships an 8.1 binary
#     but at ~200 MB per executable (~387 MB unzipped for ffmpeg +
#     ffprobe), which overflows Lambda's 250 MB function-plus-layers
#     unzipped quota.
#
# Environment variables:
#   ARCH     amd64 (default) | arm64
#   OUT_DIR  output directory (default: ./build/layer)
#
set -euo pipefail

ARCH="${ARCH:-amd64}"
OUT_DIR="${OUT_DIR:-build/layer}"

case "${ARCH}" in
  amd64|arm64) ;;
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Unsupported ARCH='${ARCH}'. Use amd64 or arm64." >&2
    exit 1
    ;;
esac

BASE_URL="https://johnvansickle.com/ffmpeg/releases"
TARBALL="ffmpeg-release-${ARCH}-static.tar.xz"
CHECKSUM="${TARBALL}.md5"

echo ">> Cleaning ${OUT_DIR}"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/bin"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo ">> Downloading ${BASE_URL}/${TARBALL}"
curl -fsSL "${BASE_URL}/${TARBALL}"  -o "${TMP}/${TARBALL}"
curl -fsSL "${BASE_URL}/${CHECKSUM}" -o "${TMP}/${CHECKSUM}"

echo ">> Verifying MD5 checksum"
(
  cd "${TMP}"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum -c "${CHECKSUM}"
  else
    expected="$(awk '{print $1}' "${CHECKSUM}")"
    actual="$(md5 -q "${TARBALL}")"
    [ "${expected}" = "${actual}" ] || {
      echo "Checksum mismatch: expected=${expected} actual=${actual}" >&2
      exit 1
    }
  fi
)

echo ">> Extracting"
tar -xJf "${TMP}/${TARBALL}" -C "${TMP}"

EXTRACT_DIR="$(find "${TMP}" -maxdepth 1 -type d -name 'ffmpeg-*-static' | head -n 1)"
if [ -z "${EXTRACT_DIR}" ]; then
  echo "Could not locate extracted ffmpeg directory" >&2
  exit 1
fi

cp "${EXTRACT_DIR}/ffmpeg"  "${OUT_DIR}/bin/ffmpeg"
cp "${EXTRACT_DIR}/ffprobe" "${OUT_DIR}/bin/ffprobe"
chmod +x "${OUT_DIR}/bin/ffmpeg" "${OUT_DIR}/bin/ffprobe"

[ -f "${EXTRACT_DIR}/readme.txt" ] && cp "${EXTRACT_DIR}/readme.txt" "${OUT_DIR}/UPSTREAM-README.txt"
[ -f "${EXTRACT_DIR}/GPLv3.txt"  ] && cp "${EXTRACT_DIR}/GPLv3.txt"  "${OUT_DIR}/UPSTREAM-GPLv3.txt"

echo ">> Layer contents:"
ls -lh "${OUT_DIR}/bin"

echo ">> Binary info:"
file "${OUT_DIR}/bin/ffmpeg" || true

echo ">> Done. Layer staged in '${OUT_DIR}/' (ARCH=${ARCH})."
