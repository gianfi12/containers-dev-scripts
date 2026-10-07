#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
PROFILE_BIND_SOURCE="${PROFILE_BIND_SOURCE:-$ROOT_DIR/support/90-apptainer-dev-base.sh}"
PROFILE_BIND_TARGET="/etc/profile.d/90-apptainer-dev-base.sh"
DEV_MOUNT_TARGET="${DEV_MOUNT_TARGET:-/mnt/dev}"
USE_STATE=1
STATE_MODE=mount
STATE_DIR=""
AUTO_HOME=1
NO_SSH_AGENT=0
INSTANCE_NAME=""
apptainer_args=()
. "$ROOT_DIR/bin/base-runtime-common.sh"

CONTAINER_CLI="${CONTAINER_CLI:-}"
if [[ -z "$CONTAINER_CLI" ]]; then
  if command -v apptainer >/dev/null 2>&1; then
    CONTAINER_CLI=apptainer
  elif command -v singularity >/dev/null 2>&1; then
    CONTAINER_CLI=singularity
  else
    echo "Error: neither 'apptainer' nor 'singularity' found in PATH." >&2
    exit 1
  fi
fi

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --instance NAME --mount-state DIR [options] [apptainer-flags...]

Options:
  --instance NAME      Name of the persistent instance.
  --mount-state DIR    Persistent state root mounted at $DEV_MOUNT_TARGET.
  --image PATH         Base SIF image.
  --no-ssh-agent       Do not forward the host SSH_AUTH_SOCK.
  --nv, --nvidia       Enable NVIDIA support.
  --rocm, --amd        Enable AMD ROCm support.
  --no-home            Do not mount the host home directory.
  --help               Show this help.
EOF
}

print_command() {
  printf '+' >&2
  for arg in "$@"; do printf ' %q' "$arg" >&2; done
  printf '\n' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --instance) INSTANCE_NAME="$2"; shift 2 ;;
    --mount-state|--mnt) STATE_DIR="$2"; shift 2 ;;
    --image) IMAGE_PATH="$2"; shift 2 ;;
    --no-ssh-agent) NO_SSH_AGENT=1; shift ;;
    --nvidia) apptainer_args+=(--nv); shift ;;
    --amd) apptainer_args+=(--rocm); shift ;;
    --no-home) AUTO_HOME=0; apptainer_args+=(--no-home); shift ;;
    *) apptainer_args+=("$1"); shift ;;
  esac
done

[[ -n "$INSTANCE_NAME" ]] || { echo "Missing --instance NAME" >&2; usage >&2; exit 2; }
[[ -n "$STATE_DIR" ]] || { echo "Missing --mount-state DIR" >&2; usage >&2; exit 2; }
[[ -f "$IMAGE_PATH" ]] || { echo "Portable base image not found: $IMAGE_PATH" >&2; exit 1; }

runtime_dir="/run/user/$(id -u)"
CONTAINER_XDG_RUNTIME_DIR="$runtime_dir"

if "$CONTAINER_CLI" instance list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$INSTANCE_NAME"; then
  echo "Apptainer instance already exists: $INSTANCE_NAME" >&2
  exit 1
fi

append_common_runtime_args

apptainer_args+=(--scratch "$runtime_dir")
apptainer_args+=(--env "XDG_RUNTIME_DIR=$runtime_dir")
apptainer_args+=(--env "DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime_dir/bus")
apptainer_args+=(--env "APPTAINER_DEV_RUNTIME_DIR=$runtime_dir")
apptainer_args+=(--env "APPTAINER_DEV_INSTANCE=$INSTANCE_NAME")

cmd=("$CONTAINER_CLI" instance start "${apptainer_args[@]}" "$IMAGE_PATH" "$INSTANCE_NAME")
print_command "${cmd[@]}"
exec "${cmd[@]}"
