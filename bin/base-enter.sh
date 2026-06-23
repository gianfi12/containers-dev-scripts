#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
CONTAINER_HOME="/home/$USER"
STATE_MOUNT="${STATE_MOUNT:-$CONTAINER_HOME/.apptainer-spack}"
DEV_MOUNT_TARGET="${DEV_MOUNT_TARGET:-/mnt/dev}"
MODULE_COLLECTIONS_MOUNT="${MODULE_COLLECTIONS_MOUNT:-$CONTAINER_HOME/.module}"
PROFILE_BIND_SOURCE="${PROFILE_BIND_SOURCE:-$ROOT_DIR/support/90-apptainer-dev-base.sh}"
PROFILE_BIND_TARGET="/etc/profile.d/90-apptainer-dev-base.sh"
# ZSH_USER_BIND_SOURCE="${ZSH_USER_BIND_SOURCE:-$ROOT_DIR/support/container-zsh-user.zsh}"
ZSH_USER_BIND_TARGET="/home/$USER/.user.zsh"
USE_STATE=0
STATE_MODE=""
STATE_DIR=""
AUTO_HOME=1

add_bind_if_exists() {
  local source_path="$1"
  local target_path="${2:-$1}"
  [[ -e "$source_path" ]] || return 0
  apptainer_args+=(--bind "$source_path:$target_path")
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options] [apptainer-flags...] [-- command...]

Options:
  --image PATH          Use a different base SIF image.
  --mount-state DIR    Mount DIR at $DEV_MOUNT_TARGET.
                        Spack state is stored in DIR/spack.
  --spack DIR          Legacy mode: mount DIR as the Spack state root.
  --state DIR          Alias for --spack.
  --no-spack           Do not mount persistent Spack state.
  --help               Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --mount-state "\$PWD/mounts/fedora"
  $(basename "$0") --spack "\$PWD/.apptainer-spack"
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" -- bash -lc 'spack find'
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" --bind "\$PWD/project:/workspace" --pwd /workspace

Notes:
  Unknown flags are forwarded to Apptainer.
  The host home is mounted by default at /home/$USER.
  Use \`--no-home\` if you explicitly want to disable that.
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

init_mount_state_layout() {
  local mount_dir="$1"
  mkdir -p \
    "$mount_dir/spack" \
    "$mount_dir/.module" \
    "$mount_dir/venvs" \
    "$mount_dir/work" \
    "$mount_dir/scratch" \
    "$mount_dir/opt"
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
  --mount-state | --mnt)
    STATE_DIR="$2"
    STATE_MODE="mount"
    USE_STATE=1
    shift 2
    ;;
  --spack | --state)
    STATE_DIR="$2"
    STATE_MODE="legacy"
    USE_STATE=1
    shift 2
    ;;
  --no-spack | --no-state)
    USE_STATE=0
    STATE_DIR=""
    STATE_MODE=""
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

apptainer_args+=(--bind "$PROFILE_BIND_SOURCE:$PROFILE_BIND_TARGET")
# add_bind_if_exists "$ZSH_USER_BIND_SOURCE" "$ZSH_USER_BIND_TARGET"

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

if [[ "$USE_STATE" -eq 1 ]]; then
  if [[ "$STATE_MODE" == "mount" ]]; then
    [[ -n "$STATE_DIR" ]] || STATE_DIR="$ROOT_DIR/mounts/fedora"
    init_mount_state_layout "$STATE_DIR"

    if state_uses_legacy_mount "$STATE_DIR/spack"; then
      echo "Spack state at $STATE_DIR/spack still references the obsolete /apptainer-dev-state prefix." >&2
      echo "Delete that state directory and bootstrap it again so installs use $DEV_MOUNT_TARGET/spack." >&2
      exit 1
    fi

    if [[ ! -f "$STATE_DIR/spack/environments/default/spack.yaml" ]]; then
      echo "Spack state at $STATE_DIR/spack is not initialized yet." >&2
      echo "Initialize it with:" >&2
      echo "  $ROOT_DIR/bin/base-bootstrap-spack.sh --mount-state \"$STATE_DIR\"" >&2
    fi

    apptainer_args+=(--bind "$STATE_DIR:$DEV_MOUNT_TARGET")
    apptainer_args+=(--env "APPTAINER_DEV_MOUNT=$DEV_MOUNT_TARGET")
    apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$DEV_MOUNT_TARGET/spack")
    apptainer_args+=(--bind "$STATE_DIR/.module:$MODULE_COLLECTIONS_MOUNT")
    apptainer_args+=(--bind "$STATE_DIR/spack/cache/opt-spack-var-cache:/opt/spack/var/spack/cache")
  else
    [[ -n "$STATE_DIR" ]] || STATE_DIR="$ROOT_DIR/.apptainer-spack"
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
  fi
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
