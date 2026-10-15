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

module_chain() {
    if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
        printf 'Usage: module_chain MODULEFILE_DIRECTORY\n' >&2
        return 2
    fi
    if ! type module >/dev/null 2>&1; then
        printf 'Environment Modules is not initialized in this shell.\n' >&2
        return 1
    fi
    module use "$1"
}

spack_chain() {
    if [ "$#" -ne 1 ]; then
        printf 'Usage: spack_chain SPACK_INSTALL_TREE\n' >&2
        return 2
    fi
    if [ -n "${APPTAINER_DEV_SPACK_CHAIN_CONFIG:-}" ]; then
        printf 'A Spack upstream is already active: %s\nRun spack_unchain before selecting another.\n' \
            "$APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE" >&2
        return 1
    fi

    local install_tree="${1%/}"
    if [ ! -d "$install_tree/.spack-db" ]; then
        printf 'Spack install tree or database not found: %s/.spack-db\n' "$install_tree" >&2
        return 1
    fi

    local base_config="${SPACK_USER_CONFIG_PATH:-$HOME/.spack}"
    local temp_parent="${APPTAINER_DEV_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    [ -d "$temp_parent" ] && [ -w "$temp_parent" ] || temp_parent=/tmp
    APPTAINER_DEV_SPACK_CHAIN_CONFIG="$(mktemp -d "$temp_parent/spack-chain.XXXXXX")" || return 1
    APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG="$base_config"
    mkdir -p "$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
    if [ -d "$base_config" ]; then
        cp -a "$base_config/." "$APPTAINER_DEV_SPACK_CHAIN_CONFIG/" || return 1
    fi

    local yaml_install_tree="${install_tree//\'/\'\'}"
    cat >"$APPTAINER_DEV_SPACK_CHAIN_CONFIG/upstreams.yaml" <<YAML
upstreams:
  hpc:
    install_tree: '$yaml_install_tree'
YAML

    export SPACK_USER_CONFIG_PATH="$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
    if ! spack config get upstreams >/dev/null; then
        printf 'Spack rejected the upstream configuration for %s\n' "$install_tree" >&2
        spack_unchain
        return 1
    fi
    APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE="$install_tree"
    printf 'Spack upstream enabled for this shell: %s\n' "$install_tree"
}

spack_unchain() {
    if [ -z "${APPTAINER_DEV_SPACK_CHAIN_CONFIG:-}" ]; then
        printf 'No temporary Spack upstream is active.\n' >&2
        return 1
    fi
    export SPACK_USER_CONFIG_PATH="$APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG"
    case "$APPTAINER_DEV_SPACK_CHAIN_CONFIG" in
        */spack-chain.*) rm -rf -- "$APPTAINER_DEV_SPACK_CHAIN_CONFIG" ;;
        *) printf 'Refusing to remove unexpected config path: %s\n' "$APPTAINER_DEV_SPACK_CHAIN_CONFIG" >&2; return 1 ;;
    esac
    unset APPTAINER_DEV_SPACK_CHAIN_CONFIG APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE
    printf 'Container Spack configuration restored for this shell.\n'
}

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
