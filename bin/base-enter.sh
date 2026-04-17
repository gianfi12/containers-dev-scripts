#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
STATE_DIR="${STATE_DIR:-}"
CONTAINER_HOME="/home/$USER"
STATE_MOUNT="${STATE_MOUNT:-$CONTAINER_HOME/.apptainer-spack}"
MODULE_COLLECTIONS_MOUNT="${MODULE_COLLECTIONS_MOUNT:-$CONTAINER_HOME/.module}"
USE_SPACK=0
AUTO_HOME=1

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options] [apptainer-flags...] [-- command...]

Options:
  --image PATH        Use a different base SIF image.
  --spack DIR         Mount DIR as the writable Spack state root.
  --no-spack          Do not mount a Spack state.
  --help              Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --spack "\$PWD/.apptainer-spack"
  $(basename "$0") --image "$ROOT_DIR/images/base.sif" --spack "\$PWD/.apptainer-spack"
  $(basename "$0") --spack "\$PWD/.apptainer-spack" -- bash -lc 'spack find'

Notes:
  Unknown flags are forwarded to Apptainer.
  Use \`--\` before a container command.
EOF
}

apptainer_args=()
container_cmd=()

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
      USE_SPACK=1
      shift 2
      ;;
    --no-spack|--no-state)
      USE_SPACK=0
      STATE_DIR=""
      shift
      ;;
    --)
      shift
      container_cmd=("$@")
      break
      ;;
    *)
      if [[ "$1" == "--home" || "$1" == "--home="* || "$1" == "--no-home" ]]; then
        AUTO_HOME=0
      fi
      apptainer_args+=("$1")
      shift
      ;;
  esac
done

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  echo "Run bin/base-build.sh first." >&2
  exit 1
}

if [[ "$USE_SPACK" -eq 1 ]]; then
  [[ -n "$STATE_DIR" ]] || STATE_DIR="$PWD/.apptainer-spack"
  mkdir -p "$STATE_DIR"

  if state_uses_legacy_mount "$STATE_DIR"; then
    echo "Spack state at $STATE_DIR still references the obsolete /apptainer-dev-state prefix." >&2
    echo "Delete that state directory and bootstrap it again so installs use $STATE_MOUNT." >&2
    exit 1
  fi

  if [[ ! -d "$STATE_DIR/spack/.git" || ! -f "$STATE_DIR/environments/default/spack.yaml" ]]; then
    echo "Spack state at $STATE_DIR is not initialized yet." >&2
    echo "Initialize it with:" >&2
    echo "  $ROOT_DIR/bin/base-bootstrap-spack.sh --spack \"$STATE_DIR\"" >&2
  fi

  apptainer_args+=(--bind "$STATE_DIR:$STATE_MOUNT")
  apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$STATE_MOUNT")
  mkdir -p "$STATE_DIR/.module"
  apptainer_args+=(--bind "$STATE_DIR/.module:$MODULE_COLLECTIONS_MOUNT")
else
  apptainer_args+=(--env APPTAINER_DEV_STATE_DIR=/tmp/.apptainer-spack)
fi

if [[ "$AUTO_HOME" -eq 1 && -d "$HOME" ]]; then
  apptainer_args=(--home "$HOME:$CONTAINER_HOME" "${apptainer_args[@]}")
fi

if [[ ${#container_cmd[@]} -gt 0 ]]; then
  print_command apptainer exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
  exec apptainer exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
fi

print_command apptainer run "${apptainer_args[@]}" "$IMAGE_PATH"
exec apptainer run "${apptainer_args[@]}" "$IMAGE_PATH"
