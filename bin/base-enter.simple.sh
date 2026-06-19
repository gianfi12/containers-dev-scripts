#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
CONTAINER_HOME="/home/$USER"
STATE_BIND_TARGET="${STATE_BIND_TARGET:-/mnt/dev}"
MODULE_COLLECTIONS_TARGET="${MODULE_COLLECTIONS_TARGET:-$CONTAINER_HOME/.module}"
STATE_DIR=""
AUTO_HOME=1
apptainer_args=()
container_cmd=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --state-dir DIR [apptainer-flags...] [-- command...]

Required:
  --state-dir DIR   Host directory containing the persistent state layout

Optional:
  --image PATH      Use a different image
  --no-home         Do not mount your home directory
  --help            Show this help

Behavior:
  - Binds DIR to $STATE_BIND_TARGET
  - Exports APPTAINER_DEV_MOUNT=$STATE_BIND_TARGET
  - Exports APPTAINER_DEV_STATE_DIR=$STATE_BIND_TARGET/spack
  - Binds DIR/.module to $MODULE_COLLECTIONS_TARGET
  - Uses the profile script already present in the container image
USAGE
}
add_bind_if_exists() {
  local source_path="$1"
  local target_path="${2:-$1}"
  [[ -e "$source_path" ]] || return 0
  apptainer_args+=(--bind "$source_path:$target_path")
}

print_command() {
  printf '+' >&2
  for arg in "$@"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --image)
    IMAGE_PATH="$2"
    shift 2
    ;;
  --state-dir)
    STATE_DIR="$2"
    shift 2
    ;;
  --no-home)
    AUTO_HOME=0
    apptainer_args+=(--no-home)
    shift
    ;;
  --)
    shift
    container_cmd=("$@")
    break
    ;;
  *)
    apptainer_args+=("$1")
    shift
    ;;
  esac
done

if [[ -z "$STATE_DIR" ]]; then
  echo "Missing required --state-dir DIR" >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$STATE_DIR/spack" ]]; then
  echo "State directory does not look initialized: $STATE_DIR" >&2
  exit 1
fi

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  exit 1
}

if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
  apptainer_args+=(--env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}")
  add_bind_if_exists "${XDG_RUNTIME_DIR}"
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  apptainer_args+=(--env "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
fi

if [[ -n "${DISPLAY:-}" ]]; then
  apptainer_args+=(--env "DISPLAY=${DISPLAY}")
  add_bind_if_exists /tmp/.X11-unix
fi

if [[ -n "${XAUTHORITY:-}" ]]; then
  apptainer_args+=(--env "XAUTHORITY=${XAUTHORITY}")
  add_bind_if_exists "${XAUTHORITY}"
fi

mkdir -p "$STATE_DIR/.module"

apptainer_args+=(--bind "$STATE_DIR:$STATE_BIND_TARGET")
apptainer_args+=(--bind "$STATE_DIR/.module:$MODULE_COLLECTIONS_TARGET")
apptainer_args+=(--env "APPTAINER_DEV_MOUNT=$STATE_BIND_TARGET")
apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$STATE_BIND_TARGET/spack")

if [[ "$AUTO_HOME" -eq 1 && -d "$HOME" ]]; then
  apptainer_args=(--home "$HOME:$CONTAINER_HOME" "${apptainer_args[@]}")
fi

if [[ ${#container_cmd[@]} -gt 0 ]]; then
  print_command apptainer exec "${apptainer_args[@]}" "$IMAGE_PATH" /usr/local/bin/dev-shell "${container_cmd[@]}"
  exec apptainer exec "${apptainer_args[@]}" "$IMAGE_PATH" /usr/local/bin/dev-shell "${container_cmd[@]}"
fi

print_command apptainer run "${apptainer_args[@]}" "$IMAGE_PATH"
exec apptainer run "${apptainer_args[@]}" "$IMAGE_PATH"
