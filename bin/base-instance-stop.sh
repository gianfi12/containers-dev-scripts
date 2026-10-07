#!/usr/bin/env bash
set -euo pipefail

CONTAINER_CLI="${CONTAINER_CLI:-}"
if [[ -z "$CONTAINER_CLI" ]]; then
  if command -v apptainer >/dev/null 2>&1; then CONTAINER_CLI=apptainer
  elif command -v singularity >/dev/null 2>&1; then CONTAINER_CLI=singularity
  else echo "Error: neither 'apptainer' nor 'singularity' found in PATH." >&2; exit 1
  fi
fi

force=()
instance_name=""
usage() { echo "Usage: $(basename "$0") --instance NAME [--force]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --instance) instance_name="$2"; shift 2 ;;
    --force) force=(--force); shift ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$instance_name" ]] || { echo "Missing --instance NAME" >&2; usage >&2; exit 2; }
exec "$CONTAINER_CLI" instance stop "${force[@]}" "$instance_name"
