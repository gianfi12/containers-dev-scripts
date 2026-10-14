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
  local state_user="${2:-$(id -un)}"
  mkdir -p \
    "$mount_dir/spack" \
    "$mount_dir/spack/config" \
    "$mount_dir/spack/cache/opt-spack-var-cache" \
    "$mount_dir/spack/cache/source" \
    "$mount_dir/spack/cache/misc" \
    "$mount_dir/spack/environments/default" \
    "$mount_dir/spack/modules" \
    "$mount_dir/spack/stage" \
    "$mount_dir/.module" \
    "$mount_dir/venvs" \
    "$mount_dir/work" \
    "$mount_dir/scratch" \
    "$mount_dir/opt" \
    "$mount_dir/.local/share" \
    "$mount_dir/.local/state" \
    "$mount_dir/.cache" \
    "$mount_dir/home/$state_user/.config/fish" \
    "$mount_dir/home/$state_user/.local/share"
}

container_home_path() {
  local mount_dir="$1"
  local state_user="${2:-$(id -un)}"
  printf '%s/home/%s\n' "$mount_dir" "$state_user"
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
  local graphics_session_type=""

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    local wayland_socket="$WAYLAND_DISPLAY"
    if [[ "$WAYLAND_DISPLAY" != /* && -n "${XDG_RUNTIME_DIR:-}" ]]; then
      wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    fi
    if [[ -S "$wayland_socket" ]]; then
      local container_runtime_dir="${CONTAINER_XDG_RUNTIME_DIR:-/tmp}"
      local wayland_name
      wayland_name="$(basename "$wayland_socket")"
      apptainer_args+=(--bind "$wayland_socket:$container_runtime_dir/$wayland_name")
      apptainer_args+=(--env "WAYLAND_DISPLAY=$wayland_name")
      apptainer_args+=(--env "XDG_RUNTIME_DIR=$container_runtime_dir")
      graphics_session_type="wayland"
    else
      echo "Warning: WAYLAND_DISPLAY is set but its socket is unavailable; skipping Wayland forwarding." >&2
    fi
  fi

  if [[ -n "${DISPLAY:-}" ]]; then
    apptainer_args+=(--env "DISPLAY=$DISPLAY")
    add_bind_if_exists /tmp/.X11-unix
    [[ -n "$graphics_session_type" ]] || graphics_session_type="x11"
  fi

  if [[ -n "${XAUTHORITY:-}" && -r "$XAUTHORITY" ]]; then
    apptainer_args+=(--env "XAUTHORITY=$XAUTHORITY")
    add_bind_if_exists "$XAUTHORITY"
  fi

  if [[ -n "$graphics_session_type" ]]; then
    apptainer_args+=(--env "XDG_SESSION_TYPE=$graphics_session_type")
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
    apptainer_args+=(--no-env XDG_CONFIG_HOME)
    apptainer_args+=(--no-env XDG_SESSION_TYPE)
    apptainer_args+=(--no-env DBUS_SESSION_BUS_ADDRESS)
    apptainer_args+=(--no-env GNOME_KEYRING_CONTROL)
    apptainer_args+=(--no-env GNOME_KEYRING_PID)
    apptainer_args+=(--no-env SSH_AUTH_SOCK)
    apptainer_args+=(--no-env WAYLAND_DISPLAY)
    apptainer_args+=(--no-env DISPLAY)
    apptainer_args+=(--no-env XAUTHORITY)
  fi
}

set_instance_env_isolation_args() {
  local cli_name
  cli_name="$(basename "${CONTAINER_CLI:-apptainer}")"
  INSTANCE_ENV_ISOLATION_ARGS=()
  if [[ "$cli_name" == "singularity" ]]; then
    INSTANCE_ENV_ISOLATION_ARGS+=(--cleanenv)
  else
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env HYPRLAND_INSTANCE_SIGNATURE)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_RUNTIME_DIR)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_CONFIG_HOME)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_DATA_HOME)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_STATE_HOME)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_CACHE_HOME)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XDG_SESSION_TYPE)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env DBUS_SESSION_BUS_ADDRESS)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env GNOME_KEYRING_CONTROL)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env GNOME_KEYRING_PID)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env SSH_AUTH_SOCK)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env WAYLAND_DISPLAY)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env DISPLAY)
    INSTANCE_ENV_ISOLATION_ARGS+=(--no-env XAUTHORITY)
  fi
}

append_state_args() {
  [[ -n "${STATE_DIR:-}" ]] || { echo "Missing required --mount-state DIR" >&2; exit 2; }
  init_mount_state_layout "$STATE_DIR"
  local container_home
  container_home="$(container_home_path "$STATE_DIR")"
  if [[ ! -f "$container_home/.config/nvim/init.lua" ]]; then
    bash "$ROOT_DIR/bin/base-state-init.sh" "$STATE_DIR" --quiet
  fi
  apptainer_args+=(--bind "$STATE_DIR:$DEV_MOUNT_TARGET")
  apptainer_args+=(--env "APPTAINER_DEV_MOUNT=$DEV_MOUNT_TARGET")
  apptainer_args+=(--env "APPTAINER_DEV_STATE_DIR=$DEV_MOUNT_TARGET/spack")
  apptainer_args+=(--env "XDG_DATA_HOME=$DEV_MOUNT_TARGET/.local/share")
  apptainer_args+=(--env "XDG_STATE_HOME=$DEV_MOUNT_TARGET/.local/state")
  apptainer_args+=(--env "XDG_CACHE_HOME=$DEV_MOUNT_TARGET/.cache")
  mkdir -p "$container_home"
  apptainer_args+=(--home "$container_home:/home/$(id -un)")
  apptainer_args+=(--env "XDG_CONFIG_HOME=/home/$(id -un)/.config")
  apptainer_args+=(--bind "$STATE_DIR/.module:/home/$(id -un)/.module")
  apptainer_args+=(--bind "$STATE_DIR/spack/cache/opt-spack-var-cache:/opt/spack/var/spack/cache")
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
  apptainer_args+=(--env "SHELL=${SHELL:-/bin/bash}")
  apptainer_args+=(--env "TERM=${TERM:-xterm-256color}")
  if [[ -n "${COLORTERM:-}" ]]; then
    apptainer_args+=(--env "COLORTERM=$COLORTERM")
  fi
  append_ssh_agent_args
  append_graphics_args
  append_state_args

}
