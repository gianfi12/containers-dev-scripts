#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${IMAGE_PATH:-$ROOT_DIR/images/base.sif}"
CONTAINER_HOME="/home/$USER"
STATE_BIND_TARGET="${STATE_BIND_TARGET:-/mnt/dev}"
MODULE_COLLECTIONS_TARGET="${MODULE_COLLECTIONS_TARGET:-$CONTAINER_HOME/.module}"
STATE_DIR=""
bootstrap_specs=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --state-dir DIR [-- spec...]

Required:
  --state-dir DIR   Host directory containing the persistent state layout

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
    "$root/.module" \
    "$root/venvs" \
    "$root/work" \
    "$root/scratch" \
    "$root/opt" \
    "$root/spack/cache/opt-spack-var-cache" \
    "$root/data"
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
  --state-dir)
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
  echo "Missing required --state-dir DIR" >&2
  usage >&2
  exit 1
fi

[[ -f "$IMAGE_PATH" ]] || {
  echo "Portable base image not found: $IMAGE_PATH" >&2
  exit 1
}

init_state_layout "$STATE_DIR"
write_spack_config "$STATE_DIR"

apptainer_args=(
  --home "$HOME:$CONTAINER_HOME"
  --bind "$STATE_DIR:$STATE_BIND_TARGET"
  --bind "$STATE_DIR/.module:$MODULE_COLLECTIONS_TARGET"
  --bind "$STATE_DIR/spack/cache/opt-spack-var-cache:/opt/spack/var/spack/cache"
  --env "APPTAINER_DEV_MOUNT=$STATE_BIND_TARGET"
  --env "APPTAINER_DEV_STATE_DIR=$STATE_BIND_TARGET/spack"
)

cmd=(
  apptainer exec
  "${apptainer_args[@]}"
  "$IMAGE_PATH"
  /usr/local/bin/dev-bootstrap-spack-state
  --state "$STATE_BIND_TARGET/spack"
)

if [[ ${#bootstrap_specs[@]} -gt 0 ]]; then
  cmd+=(-- "${bootstrap_specs[@]}")
fi

print_command "${cmd[@]}"
"${cmd[@]}"

refresh_cmd=(
  apptainer exec
  "${apptainer_args[@]}"
  "$IMAGE_PATH"
  bash -lc 'spack module tcl refresh -y >/dev/null 2>&1 || true'
)

print_command "${refresh_cmd[@]}"
exec "${refresh_cmd[@]}"
