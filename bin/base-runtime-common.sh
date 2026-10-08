#!/usr/bin/env bash

# Shared host-side runtime helpers for base-enter.sh and instance wrappers.

add_bind_if_exists() {
  local source_path="$1"
  local target_path="${2:-$1}"
  [[ -e "$source_path" ]] || return 0
  apptainer_args+=(--bind "$source_path:$target_path")
}

init_mount_state_layout() {
  local mount_dir="$1"
  mkdir -p \
    "$mount_dir/spack" \
    "$mount_dir/spack/cache/opt-spack-var-cache" \
    "$mount_dir/.module" \
    "$mount_dir/venvs" \
    "$mount_dir/work" \
    "$mount_dir/scratch" \
    "$mount_dir/opt" \
    "$mount_dir/.local/share" \
    "$mount_dir/.local/state" \
    "$mount_dir/.cache" \
    "$mount_dir/.codex" \
    "$mount_dir/.runtime"
}

state_uses_legacy_mount() {
  local state_dir="$1"
  [[ -d "$state_dir" ]] || return 1

  rg -q '/apptainer-dev-state' \
    "$state_dir/config" \
    "$state_dir/environments" >/dev/null 2>&1
}

append_ssh_agent_args() {
  [[ "${NO_SSH_AGENT:-0}" -eq 0 ]] || return 0
  [[ -n "${SSH_AUTH_SOCK:-}" ]] || return 0
  [[ -S "$SSH_AUTH_SOCK" ]] || return 0

  # Bind only the agent socket. The target is stable across normal shells and
  # instance:// exec calls, while the host runtime directory stays private.
  local target="/tmp/apptainer-dev-ssh-agent.sock"
  apptainer_args+=(--bind "$SSH_AUTH_SOCK:$target")
  apptainer_args+=(--env "SSH_AUTH_SOCK=$target")
}

append_graphics_args() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    apptainer_args+=(--env "WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
      local container_runtime_dir="${CONTAINER_XDG_RUNTIME_DIR:-/tmp}"
      apptainer_args+=(--bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$container_runtime_dir/$WAYLAND_DISPLAY")
      apptainer_args+=(--env "XDG_RUNTIME_DIR=$container_runtime_dir")
    fi
  fi

  if [[ -n "${DISPLAY:-}" ]]; then
    apptainer_args+=(--env "DISPLAY=$DISPLAY")
    add_bind_if_exists /tmp/.X11-unix
  fi

  if [[ -n "${XAUTHORITY:-}" ]]; then
    apptainer_args+=(--env "XAUTHORITY=$XAUTHORITY")
    add_bind_if_exists "$XAUTHORITY"
  fi
}

append_host_env_isolation_args() {
  local cli_name
  cli_name="$(basename "${CONTAINER_CLI:-apptainer}")"
  if [[ "$cli_name" == "singularity" ]]; then
    # Older Singularity releases do not implement Apptainer's --no-env.
    # --cleanenv is the compatible way to keep host session variables out.
    apptainer_args+=(--cleanenv)
  else
    apptainer_args+=(--no-env HYPRLAND_INSTANCE_SIGNATURE)
    apptainer_args+=(--no-env XDG_RUNTIME_DIR)
    apptainer_args+=(--no-env DBUS_SESSION_BUS_ADDRESS)
    apptainer_args+=(--no-env GNOME_KEYRING_CONTROL)
    apptainer_args+=(--no-env GNOME_KEYRING_PID)
    apptainer_args+=(--no-env SSH_AUTH_SOCK)
  fi
}

set_instance_env_isolation_args() {
  local cli_name
  cli_name="$(basename "${CONTAINER_CLI:-apptainer}")"
  INSTANCE_ENV_ISOLATION_ARGS=()
  if [[ "$cli_name" == "singularity" ]]; then
    INSTANCE_ENV_ISOLATION_ARGS+=(--cleanenv)
  else
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_RUNTIME_DIR)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env DBUS_SESSION_BUS_ADDRESS)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env GNOME_KEYRING_CONTROL)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env GNOME_KEYRING_PID)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env SSH_AUTH_SOCK)
  fi
}

append_state_args() {
  if [[ "${USE_STATE:-0}" -eq 0 ]]; then
    apptainer_args+=(--env APPTAINER_DEV_STATE_DIR=/tmp/.apptainer-spack)
    return 0
  fi

  if [[ "${STATE_MODE:-mount}" == "mount" ]]; then
    [[ -n "${STATE_DIR:-}" ]] || STATE_DIR="$ROOT_DIR/mounts/fedora"
    init_mount_state_layout "$STATE_DIR"

    if state_uses_legacy_mount "$STATE_DIR/spack"; then
      echo "Spack state at $STATE_DIR/spack still references the obsolete /apptainer-dev-state prefix." >&2
      echo "Delete that state directory and bootstrap it again." >&2
      exit 1
    fi

    if [[ ! -f "$STATE_DIR/spack/environments/default/spack.yaml" ]]; then
      echo "Warning: Spack state at $STATE_DIR/spack is not initialized yet." >&2
      echo "Initialize it with: $ROOT_DIR/bin/base-bootstrap-spack.sh --mount-state \"$STATE_DIR\"" >&2
    fi

    apptainer_args+=(--bind "$STATE_DIR:$DEV_MOUNT_TARGET")
    apptainer_args+=(--env "APPTAINER_DEV_MOUNT=$DEV_MOUNT_TARGET")
    apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$DEV_MOUNT_TARGET/spack")
    apptainer_args+=(--env "XDG_DATA_HOME=$DEV_MOUNT_TARGET/.local/share")
    apptainer_args+=(--env "XDG_STATE_HOME=$DEV_MOUNT_TARGET/.local/state")
    apptainer_args+=(--env "XDG_CACHE_HOME=$DEV_MOUNT_TARGET/.cache")
    apptainer_args+=(--env "APPTAINER_DEV_RUNTIME_ROOT=$DEV_MOUNT_TARGET/.runtime")
    if [[ "${AUTO_HOME:-1}" -eq 1 && -d "$HOME" ]]; then
      apptainer_args+=(--bind "$STATE_DIR/.module:$HOME/.module")
    fi
    apptainer_args+=(--bind "$STATE_DIR/spack/cache/opt-spack-var-cache:/opt/spack/var/spack/cache")
  else
    [[ -n "${STATE_DIR:-}" ]] || STATE_DIR="$ROOT_DIR/.apptainer-spack"
    mkdir -p "$STATE_DIR" "$STATE_DIR/.module"
    apptainer_args+=(--bind "$STATE_DIR:$HOME/.apptainer-spack")
    apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$HOME/.apptainer-spack")
    if [[ "${AUTO_HOME:-1}" -eq 1 && -d "$HOME" ]]; then
      apptainer_args+=(--bind "$STATE_DIR/.module:$HOME/.module")
    fi
  fi
}

append_common_runtime_args() {
  # Keep these small runtime helpers in sync with the repository even when
  # the SIF predates the latest shell/session fix. Package changes still
  # require an image rebuild, but wrapper changes do not.
  apptainer_args+=(--bind "$ROOT_DIR/support/dev-shell:/usr/local/bin/dev-shell")
  apptainer_args+=(--bind "$ROOT_DIR/support/dev-private-session:/usr/local/bin/dev-private-session")
  apptainer_args+=(--bind "$ROOT_DIR/support/dev-instance-start:/usr/local/bin/dev-instance-start")
  apptainer_args+=(--bind "$ROOT_DIR/support/dev-keyring-unlock:/usr/local/bin/keyring-unlock")
  apptainer_args+=(--bind "$ROOT_DIR/support/90-apptainer-dev-base.fish:/etc/fish/conf.d/90-apptainer-dev-base.fish")
  apptainer_args+=(--bind "$PROFILE_BIND_SOURCE:$PROFILE_BIND_TARGET")
  append_host_env_isolation_args
  append_ssh_agent_args
  append_graphics_args
  append_state_args

  if [[ "${AUTO_HOME:-1}" -eq 1 && -d "$HOME" ]]; then
    apptainer_args=(--home "$HOME" "${apptainer_args[@]}")
  fi
}
