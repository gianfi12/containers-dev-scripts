#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") STATE_DIR
  $(basename "$0") --state-dir STATE_DIR

Create a host state directory layout for the Apptainer base image.

Layout:
  STATE_DIR/
    spack/
      config/
      cache/
      environments/default/
      modules/
      stage/
    .module/
    venvs/
    work/
    scratch/
    opt/
    data/
USAGE
}

STATE_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    *)
      if [[ -z "$STATE_DIR" ]]; then
        STATE_DIR="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$STATE_DIR" ]]; then
  usage >&2
  exit 1
fi

mkdir -p \
  "$STATE_DIR/spack/config" \
  "$STATE_DIR/spack/cache" \
  "$STATE_DIR/spack/environments/default" \
  "$STATE_DIR/spack/modules" \
  "$STATE_DIR/spack/stage" \
  "$STATE_DIR/.module" \
  "$STATE_DIR/venvs" \
  "$STATE_DIR/work" \
  "$STATE_DIR/scratch" \
  "$STATE_DIR/opt" \
  "$STATE_DIR/data"

CONFIG_FILE="$STATE_DIR/spack/config/config.yaml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<'YAML'
config:
  build_stage:
  - /mnt/dev/spack/stage
YAML
fi

ENV_FILE="$STATE_DIR/spack/environments/default/spack.yaml"
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'YAML'
spack:
  specs: []
  view: false
YAML
fi

cat <<OUT
Initialized state directory:
  $STATE_DIR

Important paths:
  Spack state:      $STATE_DIR/spack
  Modulefiles:      $STATE_DIR/spack/modules
  Module collections: $STATE_DIR/.module
  Virtualenvs:      $STATE_DIR/venvs
  Workspace:        $STATE_DIR/work
  Scratch:          $STATE_DIR/scratch
  Extra software:   $STATE_DIR/opt
  User data:        $STATE_DIR/data

Notes:
  - The container profile script will use /mnt/dev/spack as APPTAINER_DEV_STATE_DIR.
  - If you place a full Spack checkout at $STATE_DIR/spack/spack, you can point the
    profile script at it explicitly with APPTAINER_DEV_SPACK_ROOT=/mnt/dev/spack/spack.
  - Otherwise the image's built-in /opt/spack will be used.
OUT
