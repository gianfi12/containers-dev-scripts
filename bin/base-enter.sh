#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
. "$ROOT_DIR/bin/base-runtime-common.sh"

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

DEV_MOUNT_TARGET="${DEV_MOUNT_TARGET:-/mnt/dev}"
PROFILE_BIND_SOURCE="${PROFILE_BIND_SOURCE:-$ROOT_DIR/support/90-apptainer-dev-base.sh}"
PROFILE_BIND_TARGET="/etc/profile.d/90-apptainer-dev-base.sh"
STATE_DIR=""
NO_SSH_AGENT=0
INSTANCE_NAME=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--mount-state DIR] [options] [apptainer-flags...] [-- command...]

Options:
  --image PATH          Use a different base SIF image.
  --mount-state DIR    Persistent home and Spack state root (required for a new session).
  --no-ssh-agent       Do not forward the host SSH_AUTH_SOCK.
  --instance NAME      Execute in an existing Apptainer instance.
  --bind, -B SRC[:DST] Bind mount host directories inside the container.
  --help               Show this help.

Examples:
  $(basename "$0") --mount-state "\$PWD/mounts/fedora"
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" --bind "\$PWD/project:/workspace" --pwd /workspace
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" -B /hs/work0:/hs/work0
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" -- bash -lc 'spack find'
  $(basename "$0") --instance hpc-dev

Notes:
  Unknown flags and --bind/-B options are forwarded directly to the container runtime.
  With --mount-state, the container home persists under DIR/home/USER.
  Host directories are mounted only when explicitly requested with --bind/-B.
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
  --mount-state)
    STATE_DIR="$2"
    shift 2
    ;;
  --no-ssh-agent)
    NO_SSH_AGENT=1
    shift
    ;;
  --instance)
    INSTANCE_NAME="$2"
    shift 2
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

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  echo "Run bin/base-build.sh first." >&2
  exit 1
}

if [[ -n "$INSTANCE_NAME" ]]; then
  if [[ ${#apptainer_args[@]} -gt 0 ]]; then
    echo "Runtime flags such as --bind must be passed to base-instance-start.sh; mounts cannot be added to an existing instance." >&2
    exit 2
  fi
  if ! "$CONTAINER_CLI" instance list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$INSTANCE_NAME"; then
    echo "Apptainer instance not found: $INSTANCE_NAME" >&2
    exit 1
  fi
  # The instance already owns its mounts. Only pass the private runtime
  # environment and the command; host runtime sockets are not rebound here.
  instance_runtime="/run/user/$(id -u)"
  set_instance_env_isolation_args
  instance_args=(
    "${INSTANCE_ENV_ISOLATION_ARGS[@]}"
    --env "APPTAINER_DEV_MOUNT=$DEV_MOUNT_TARGET"
    --env "APPTAINER_DEV_STATE_DIR=$DEV_MOUNT_TARGET/spack"
    --env "XDG_CONFIG_HOME=/home/$(id -un)/.config"
    --env "XDG_DATA_HOME=$DEV_MOUNT_TARGET/.local/share"
    --env "XDG_STATE_HOME=$DEV_MOUNT_TARGET/.local/state"
    --env "XDG_CACHE_HOME=$DEV_MOUNT_TARGET/.cache"
    --env "XDG_RUNTIME_DIR=$instance_runtime"
    --env "DBUS_SESSION_BUS_ADDRESS=unix:path=$instance_runtime/bus"
    --env "SHELL=${SHELL:-/bin/bash}"
    --env "TERM=${TERM:-xterm-256color}"
  )
  if [[ -n "${COLORTERM:-}" ]]; then
    instance_args+=(--env "COLORTERM=$COLORTERM")
  fi
  if [[ "$NO_SSH_AGENT" -eq 0 && -S "${SSH_AUTH_SOCK:-}" ]]; then
    instance_args+=(--env SSH_AUTH_SOCK=/tmp/apptainer-dev-ssh-agent.sock)
  fi
  instance_graphics_session_type=""
  if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    instance_wayland_socket="$WAYLAND_DISPLAY"
    if [[ "$WAYLAND_DISPLAY" != /* ]]; then
      instance_wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    fi
    if [[ -S "$instance_wayland_socket" ]]; then
      instance_args+=(--env "WAYLAND_DISPLAY=$(basename "$instance_wayland_socket")")
      instance_graphics_session_type="wayland"
    fi
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    instance_args+=(--env "DISPLAY=$DISPLAY")
    [[ -n "$instance_graphics_session_type" ]] || instance_graphics_session_type="x11"
  fi
  if [[ -n "${XAUTHORITY:-}" && -r "$XAUTHORITY" ]]; then
    instance_args+=(--env "XAUTHORITY=$XAUTHORITY")
  fi
  if [[ -n "$instance_graphics_session_type" ]]; then
    instance_args+=(--env "XDG_SESSION_TYPE=$instance_graphics_session_type")
  fi
  if [[ ${#container_cmd[@]} -gt 0 ]]; then
    print_command "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" \
      /usr/local/bin/dev-shell "${container_cmd[@]}"
    exec "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" \
      /usr/local/bin/dev-shell "${container_cmd[@]}"
  fi
  print_command "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" /usr/local/bin/dev-shell
  exec "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" /usr/local/bin/dev-shell
fi

[[ -n "$STATE_DIR" ]] || { echo "Missing required --mount-state DIR" >&2; usage >&2; exit 2; }

# Apptainer creates this private scratch directory for the container runtime.
CONTAINER_XDG_RUNTIME_DIR="/tmp/apptainer-dev-runtime"
apptainer_args+=(--scratch "$CONTAINER_XDG_RUNTIME_DIR")
apptainer_args+=(--env "APPTAINER_DEV_RUNTIME_DIR=$CONTAINER_XDG_RUNTIME_DIR")

append_common_runtime_args

if [[ ${#container_cmd[@]} -gt 0 ]]; then
  print_command "$CONTAINER_CLI" exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
  exec "$CONTAINER_CLI" exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
fi

print_command "$CONTAINER_CLI" run "${apptainer_args[@]}" "$IMAGE_PATH"
exec "$CONTAINER_CLI" run "${apptainer_args[@]}" "$IMAGE_PATH"
