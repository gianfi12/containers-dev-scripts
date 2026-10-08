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
USE_STATE=0
STATE_MODE=""
STATE_DIR=""
AUTO_HOME=1
NO_SSH_AGENT=0
INSTANCE_NAME=""

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
  --no-ssh-agent       Do not forward the host SSH_AUTH_SOCK.
  --instance NAME      Execute in an existing Apptainer instance.
  --nv, --nvidia       Enable NVIDIA support (must be set when starting an instance).
  --rocm, --amd        Enable AMD ROCm support (must be set when starting an instance).
  --bind, -B SRC[:DST] Bind mount host directories inside the container.
  --shell SHELL        Launch a specific shell (e.g. bash, fish, zsh).
  --help               Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --mount-state "\$PWD/mounts/fedora"
  $(basename "$0") --spack "\$PWD/.apptainer-spack"
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" --bind "\$PWD/project:/workspace" --pwd /workspace
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" -B /hs/work0:/hs/work0
  $(basename "$0") --mount-state "\$PWD/mounts/fedora" -- bash -lc 'spack find'
  $(basename "$0") --instance hpc-dev

Notes:
  Unknown flags and --bind/-B options are forwarded directly to the container runtime.
  The host home is mounted by default at \$HOME.
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
  --no-ssh-agent)
    NO_SSH_AGENT=1
    shift
    ;;
  --instance)
    INSTANCE_NAME="$2"
    shift 2
    ;;
  --nvidia)
    apptainer_args+=(--nv)
    shift
    ;;
  --amd)
    apptainer_args+=(--rocm)
    shift
    ;;
  --shell)
    container_cmd=("$2")
    shift 2
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

# Never use the host /run/user tree or /tmp as the container runtime directory.
# Apptainer creates this scratch directory writable by the container user.
CONTAINER_XDG_RUNTIME_DIR="/tmp/apptainer-dev-runtime"
apptainer_args+=(--scratch "$CONTAINER_XDG_RUNTIME_DIR")
apptainer_args+=(--env "APPTAINER_DEV_RUNTIME_DIR=$CONTAINER_XDG_RUNTIME_DIR")

if [[ -n "$INSTANCE_NAME" ]]; then
  for arg in "${apptainer_args[@]}"; do
    if [[ "$arg" == "--nv" || "$arg" == "--rocm" ]]; then
      echo "GPU flags must be passed to base-instance-start.sh, not base-enter.sh --instance." >&2
      exit 2
    fi
  done
  [[ "$USE_STATE" -eq 0 || "$STATE_MODE" == "mount" ]] || {
    echo "--instance supports --mount-state, not legacy --spack/--state." >&2
    exit 2
  }
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
    --env "APPTAINER_DEV_INSTANCE=$INSTANCE_NAME"
    --env "APPTAINER_DEV_MOUNT=$DEV_MOUNT_TARGET"
    --env "APPTAINER_DEV_STATE_DIR=$DEV_MOUNT_TARGET/spack"
    --env "XDG_RUNTIME_DIR=$instance_runtime"
    --env "DBUS_SESSION_BUS_ADDRESS=unix:path=$instance_runtime/bus"
    --env "APPTAINER_DEV_RUNTIME_DIR=$instance_runtime"
    --env SSH_AUTH_SOCK=/tmp/apptainer-dev-ssh-agent.sock
  )
  if [[ ${#container_cmd[@]} -gt 0 ]]; then
    print_command "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" \
      /usr/local/bin/dev-shell "${container_cmd[@]}"
    exec "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" \
      /usr/local/bin/dev-shell "${container_cmd[@]}"
  fi
  print_command "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" /usr/local/bin/dev-shell
  exec "$CONTAINER_CLI" exec "${instance_args[@]}" "instance://$INSTANCE_NAME" /usr/local/bin/dev-shell
fi

append_common_runtime_args

if [[ ${#container_cmd[@]} -gt 0 ]]; then
  print_command "$CONTAINER_CLI" exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
  exec "$CONTAINER_CLI" exec "${apptainer_args[@]}" "$IMAGE_PATH" \
    /usr/local/bin/dev-shell "${container_cmd[@]}"
fi

print_command "$CONTAINER_CLI" run "${apptainer_args[@]}" "$IMAGE_PATH"
exec "$CONTAINER_CLI" run "${apptainer_args[@]}" "$IMAGE_PATH"
