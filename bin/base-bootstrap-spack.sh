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

CONTAINER_HOME="${CONTAINER_HOME:-/home/$(id -un)}"
STATE_BIND_TARGET="${STATE_BIND_TARGET:-/mnt/dev}"
MODULE_COLLECTIONS_TARGET="${MODULE_COLLECTIONS_TARGET:-$CONTAINER_HOME/.module}"
STATE_DIR=""
bootstrap_specs=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --mount-state DIR [-- spec...]

Required:
  --mount-state DIR   Host directory containing the persistent state layout

Optional:
  --image PATH      Use a different image
  --help            Show this help
USAGE
}

print_command() {
  printf '+' >&2
  for arg in "$@"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
}

init_state_layout() {
  local root="$1"
  init_mount_state_layout "$root"
  mkdir -p \
    "$root/spack/config" \
    "$root/spack/cache/source" \
    "$root/spack/cache/misc" \
    "$root/spack/cache/bootstrap" \
    "$root/spack/cache/package_repos" \
    "$root/spack/environments/default" \
    "$root/spack/modules" \
    "$root/spack/opt" \
    "$root/spack/stage" \
    "$root/spack/cache/opt-spack-var-cache"
}

write_spack_config() {
  local cfg_dir="$1/spack/config"

  cat >"$cfg_dir/config.yaml" <<'YAML'
config:
  install_tree:
    root: /mnt/dev/spack/opt
  build_stage:
  - /mnt/dev/spack/stage
  environments_root: /mnt/dev/spack/environments
  source_cache: /mnt/dev/spack/cache/source
  misc_cache: /mnt/dev/spack/cache/misc
YAML

  cat >"$cfg_dir/modules.yaml" <<'YAML'
modules:
  default:
    enable:
      - tcl
    roots:
      tcl: /mnt/dev/spack/modules
    tcl:
      hash_length: 0
      projections:
        all: "{name}/{version}"
YAML
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
  --mount-state)
    STATE_DIR="$2"
    shift 2
    ;;
  --)
    shift
    bootstrap_specs=("$@")
    break
    ;;
  *)
    bootstrap_specs+=("$1")
    shift
    ;;
  esac
done

if [[ -z "$STATE_DIR" ]]; then
  echo "Missing required --mount-state DIR" >&2
  usage >&2
  exit 1
fi

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  exit 1
}

init_state_layout "$STATE_DIR"
if [[ ! -f "$STATE_DIR/home/$(id -un)/.config/nvim/init.lua" ]]; then
  bash "$ROOT_DIR/bin/base-state-init.sh" "$STATE_DIR" --quiet
fi
write_spack_config "$STATE_DIR"

apptainer_args=(
  --home "$STATE_DIR/home/$(id -un):$CONTAINER_HOME"
  --bind "$STATE_DIR:$STATE_BIND_TARGET"
  --bind "$STATE_DIR/.module:$MODULE_COLLECTIONS_TARGET"
  --bind "$STATE_DIR/spack/cache/opt-spack-var-cache:/opt/spack/var/spack/cache"
  --env "APPTAINER_DEV_MOUNT=$STATE_BIND_TARGET"
  --env "APPTAINER_DEV_STATE_DIR=$STATE_BIND_TARGET/spack"
  --env "XDG_CONFIG_HOME=$CONTAINER_HOME/.config"
  --env "XDG_DATA_HOME=$STATE_BIND_TARGET/.local/share"
  --env "XDG_STATE_HOME=$STATE_BIND_TARGET/.local/state"
  --env "XDG_CACHE_HOME=$STATE_BIND_TARGET/.cache"
)

cmd=(
  "$CONTAINER_CLI" exec
  "${apptainer_args[@]}"
  "$IMAGE_PATH"
  /usr/local/bin/dev-bootstrap-spack-state
)

if [[ ${#bootstrap_specs[@]} -gt 0 ]]; then
  cmd+=(-- "${bootstrap_specs[@]}")
fi

print_command "${cmd[@]}"
"${cmd[@]}"

refresh_cmd=(
  "$CONTAINER_CLI" exec
  "${apptainer_args[@]}"
  "$IMAGE_PATH"
  bash -lc 'spack module tcl refresh -y >/dev/null 2>&1 || true'
)

print_command "${refresh_cmd[@]}"
exec "${refresh_cmd[@]}"
