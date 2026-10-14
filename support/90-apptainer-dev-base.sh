export APPTAINER_DEV_MOUNT="${APPTAINER_DEV_MOUNT:-}"
export APPTAINER_DEV_STATE_DIR="${APPTAINER_DEV_STATE_DIR:-}"
export SPACK_ROOT=/opt/spack

case "${LANG:-C}" in
    C|POSIX) export LANG=C.UTF-8 ;;
esac
case "${LC_CTYPE:-${LANG}}" in
    C|POSIX) export LC_CTYPE=C.UTF-8 ;;
esac

if [ -n "$APPTAINER_DEV_MOUNT" ]; then
    export APPTAINER_DEV_STATE_DIR="$APPTAINER_DEV_MOUNT/spack"
    export APPTAINER_DEV_VENVS="$APPTAINER_DEV_MOUNT/venvs"
    export SPACK_MODULE_ROOT="$APPTAINER_DEV_STATE_DIR/modules"
    export SPACK_USER_CONFIG_PATH="$APPTAINER_DEV_STATE_DIR/config"
    export SPACK_USER_CACHE_PATH="$APPTAINER_DEV_STATE_DIR/cache"
    export XDG_DATA_HOME="$APPTAINER_DEV_MOUNT/.local/share"
    export XDG_STATE_HOME="$APPTAINER_DEV_MOUNT/.local/state"
    export XDG_CACHE_HOME="$APPTAINER_DEV_MOUNT/.cache"
    unset SPACK_DISABLE_LOCAL_CONFIG
    mkdir -p "$APPTAINER_DEV_VENVS" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" 2>/dev/null || true
    if [ -d "$XDG_DATA_HOME/nvim/mason/bin" ]; then
        export PATH="$XDG_DATA_HOME/nvim/mason/bin:$PATH"
    fi
fi

if [ -n "$APPTAINER_DEV_MOUNT" ]; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate zsh
        autoload -Uz compinit
        compinit -i
        autoload -Uz bashcompinit
        bashcompinit
    fi
    . "$SPACK_ROOT/share/spack/setup-env.sh"
    if [ -n "${BASH_VERSION:-}" ]; then
        . /usr/share/Modules/init/bash
    elif [ -n "${ZSH_VERSION:-}" ]; then
        . /usr/share/Modules/init/zsh
    else
        . /usr/share/Modules/init/sh
    fi
fi

if [ -n "$APPTAINER_DEV_MOUNT" ] && [ -d "$SPACK_MODULE_ROOT" ]; then
    module use "${SPACK_MODULE_ROOT}" >/dev/null 2>&1 || true
fi
