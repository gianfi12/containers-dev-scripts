#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
DEF_PATH="${DEF_PATH:-$ROOT_DIR/defs/base.def}"

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

exec apptainer build "${apptainer_args[@]}" "$IMAGE_PATH" "$DEF_PATH"
