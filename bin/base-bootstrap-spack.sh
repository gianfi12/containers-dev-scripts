#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
STATE_DIR="${STATE_DIR:-$HOME/.apptainer-spack}"
CONTAINER_HOME="/home/$USER"
STATE_MOUNT="${STATE_MOUNT:-$CONTAINER_HOME/.apptainer-spack}"
SPACK_REF="${SPACK_REF:-develop}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options] [-- spec...]

Options:
  --image PATH        Use a different base SIF image.
  --spack DIR         Bind DIR to $STATE_MOUNT for the writable Spack state.
  --state DIR         Alias for --spack.
  --ref REF           Clone Spack ref REF.
  --help              Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --spack "\$PWD/.apptainer-spack"
  $(basename "$0") --spack "\$PWD/.apptainer-spack" -- hdf5
EOF
}

bootstrap_specs=()

print_command() {
  printf '+' >&2
  for arg in "$@"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
}

state_uses_legacy_mount() {
  local state_dir="$1"
  [[ -d "$state_dir" ]] || return 1

  rg -q '/apptainer-dev-state' \
    "$state_dir/config" \
    "$state_dir/environments" >/dev/null 2>&1
}

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
    --spack|--state)
      STATE_DIR="$2"
      shift 2
      ;;
    --ref)
      SPACK_REF="$2"
      shift 2
      ;;
    --)
      shift
      bootstrap_specs+=("$@")
      break
      ;;
    *)
      bootstrap_specs+=("$1")
      shift
      ;;
  esac
done

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  echo "Run bin/base-build.sh first." >&2
  exit 1
}

mkdir -p "$STATE_DIR"

if state_uses_legacy_mount "$STATE_DIR"; then
  echo "Spack state at $STATE_DIR still references the obsolete /apptainer-dev-state prefix." >&2
  echo "Delete that state directory and bootstrap it again so installs use $STATE_MOUNT." >&2
  exit 1
fi

cmd=(
  apptainer exec
  --home "$HOME:$CONTAINER_HOME"
  --bind "$STATE_DIR:$STATE_MOUNT"
  --env "APPTAINER_DEV_STATE_DIR=$STATE_MOUNT"
  "$IMAGE_PATH"
  dev-bootstrap-spack-state
  --state "$STATE_MOUNT"
  --ref "$SPACK_REF"
)

if [[ ${#bootstrap_specs[@]} -gt 0 ]]; then
  cmd+=(-- "${bootstrap_specs[@]}")
fi

print_command "${cmd[@]}"
exec "${cmd[@]}"
