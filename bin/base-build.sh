#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
DEF_PATH="${DEF_PATH:-$ROOT_DIR/defs/base.def}"

CONTAINER_CLI="${CONTAINER_CLI:-}"
if [[ -z "$CONTAINER_CLI" ]]; then
  if command -v apptainer >/dev/null 2>&1; then
    CONTAINER_CLI="apptainer"
  elif command -v singularity >/dev/null 2>&1; then
    CONTAINER_CLI="singularity"
  else
    echo "Error: neither 'apptainer' nor 'singularity' found in PATH." >&2
    exit 1
  fi
fi

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options] [apptainer-build-flags...]

Options:
  --image PATH   Output SIF path. Default: $IMAGE_PATH
  --def PATH     Definition file. Default: $DEF_PATH
  --help         Show this help.

Notes:
  Unknown flags are forwarded to \`apptainer build\`.
EOF
}

apptainer_args=(--fakeroot --notest --force)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --image)
      IMAGE_PATH="$2"
      shift 2
      ;;
    --def)
      DEF_PATH="$2"
      shift 2
      ;;
    *)
      apptainer_args+=("$1")
      shift
      ;;
  esac
done

exec "$CONTAINER_CLI" build "${apptainer_args[@]}" "$IMAGE_PATH" "$DEF_PATH"
