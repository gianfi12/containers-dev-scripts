#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${1:-}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") STATE_DIR

Creates a minimal Spack state directory layout for the container.
EOF
}

if [[ -z "$STATE_DIR" || "$STATE_DIR" == "-h" || "$STATE_DIR" == "--help" ]]; then
  usage
  exit 0
fi

echo "Initializing state directory: $STATE_DIR"

mkdir -p \
  "$STATE_DIR/spack/config" \
  "$STATE_DIR/spack/cache/source" \
  "$STATE_DIR/spack/cache/misc" \
  "$STATE_DIR/spack/cache/bootstrap" \
  "$STATE_DIR/spack/environments" \
  "$STATE_DIR/spack/modules" \
  "$STATE_DIR/spack/opt" \
  "$STATE_DIR/spack/stage" \
  "$STATE_DIR/.module" \
  "$STATE_DIR/venvs" \
  "$STATE_DIR/work" \
  "$STATE_DIR/scratch" \
  "$STATE_DIR/data"

# --- Spack config ---
cat >"$STATE_DIR/spack/config/config.yaml" <<'EOF'
config:
  install_tree:
    root: /mnt/dev/spack/opt
  build_stage:
  - /mnt/dev/spack/stage
  environments_root: /mnt/dev/spack/environments
  source_cache: /mnt/dev/spack/cache/source
  misc_cache: /mnt/dev/spack/cache/misc
EOF

# --- Module config ---
cat >"$STATE_DIR/spack/config/modules.yaml" <<'EOF'
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
EOF

echo
echo "State initialized at: $STATE_DIR"
echo
echo "Next steps:"
echo "  1. Enter container:"
echo "     base-enter.simple.sh --state-dir \"$STATE_DIR\" --image images/base.sif"
echo
echo "  2. Inside container:"
echo "     spack compiler find"
echo "     spack install cmake"
echo "     spack module tcl refresh -y"
