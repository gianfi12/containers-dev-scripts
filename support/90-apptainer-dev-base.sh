export APPTAINER_DEV_MOUNT="${APPTAINER_DEV_MOUNT:-}"
export APPTAINER_DEV_STATE_DIR="${APPTAINER_DEV_STATE_DIR:-}"

if [ -n "${APPTAINER_DEV_MOUNT}" ] && [ -z "${APPTAINER_DEV_STATE_DIR}" ]; then
    export APPTAINER_DEV_STATE_DIR="${APPTAINER_DEV_MOUNT}/spack"
fi

if [ -n "${APPTAINER_DEV_STATE_DIR}" ]; then
    if [ -f "${APPTAINER_DEV_STATE_DIR}/spack/share/spack/setup-env.sh" ]; then
        export APPTAINER_DEV_SPACK_ROOT="${APPTAINER_DEV_SPACK_ROOT:-${APPTAINER_DEV_STATE_DIR}/spack}"
    else
        export APPTAINER_DEV_SPACK_ROOT="${APPTAINER_DEV_SPACK_ROOT:-/opt/spack}"
    fi

    export SPACK_ROOT="${SPACK_ROOT:-${APPTAINER_DEV_SPACK_ROOT}}"
    export SPACK_MODULE_ROOT="${SPACK_MODULE_ROOT:-${APPTAINER_DEV_STATE_DIR}/modules}"
    export SPACK_USER_CONFIG_PATH="${SPACK_USER_CONFIG_PATH:-${APPTAINER_DEV_STATE_DIR}/config}"
    export SPACK_USER_CACHE_PATH="${SPACK_USER_CACHE_PATH:-${APPTAINER_DEV_STATE_DIR}/cache}"

    if [ -n "${APPTAINER_DEV_MOUNT}" ]; then
        export APPTAINER_DEV_VENVS="${APPTAINER_DEV_VENVS:-${APPTAINER_DEV_MOUNT}/venvs}"
    fi

    unset SPACK_DISABLE_LOCAL_CONFIG
fi

_apptainer_dev_source_first() {
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            . "$candidate"
            return 0
        fi
    done
    return 1
}

_apptainer_dev_module_is_ready() {
    command -v module >/dev/null 2>&1 || typeset -f module >/dev/null 2>&1
}

_apptainer_dev_module_shell_name() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        printf '%s\n' zsh
    elif [ -n "${BASH_VERSION:-}" ]; then
        printf '%s\n' bash
    else
        printf '%s\n' sh
    fi
}

_apptainer_dev_source_module_init() {
    prefix="$1"
    shell_name="$(_apptainer_dev_module_shell_name)"
    _apptainer_dev_source_first \
        "${prefix}/init/${shell_name}" \
        "${prefix}/share/Modules/init/${shell_name}" \
        "${prefix}/init/sh" \
        "${prefix}/share/Modules/init/sh" \
        "${prefix}/init/profile.sh" \
        "${prefix}/share/Modules/init/profile.sh"
}

_apptainer_dev_prepare_zsh_bash_completion() {
    if [ -n "${ZSH_VERSION:-}" ] && ! typeset -f complete >/dev/null 2>&1; then
        autoload -Uz compinit bashcompinit 2>/dev/null || return 0
        compinit -C 2>/dev/null || true
        bashcompinit 2>/dev/null || true
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        if ! typeset -f compdef >/dev/null 2>&1; then
            compdef() { return 0; }
        fi
        if ! typeset -f complete >/dev/null 2>&1; then
            complete() { return 0; }
        fi
    fi
}

if [ -n "${APPTAINER_DEV_STATE_DIR:-}" ] && mkdir -p \
    "${APPTAINER_DEV_STATE_DIR}" \
    "${SPACK_USER_CONFIG_PATH}" \
    "${SPACK_USER_CACHE_PATH}" \
    "${SPACK_MODULE_ROOT}" 2>/dev/null; then
    :
fi

if [ -n "${APPTAINER_DEV_MOUNT:-}" ] && mkdir -p "${APPTAINER_DEV_VENVS}" 2>/dev/null; then
    :
fi

if [ -n "${APPTAINER_DEV_STATE_DIR:-}" ] && [ -f "${SPACK_ROOT}/share/spack/setup-env.sh" ]; then
    _apptainer_dev_prepare_zsh_bash_completion
    . "${SPACK_ROOT}/share/spack/setup-env.sh"

    module_prefix="$(spack location -i environment-modules 2>/dev/null || true)"
    if [ -n "${module_prefix}" ] && ! _apptainer_dev_module_is_ready; then
        _apptainer_dev_source_module_init "${module_prefix}" || true
    fi
fi

if ! _apptainer_dev_module_is_ready; then
    _apptainer_dev_source_module_init /usr/share/Modules || true
fi

if [ -n "${APPTAINER_DEV_STATE_DIR:-}" ] && _apptainer_dev_module_is_ready && [ -d "${SPACK_MODULE_ROOT}" ]; then
    module use "${SPACK_MODULE_ROOT}" >/dev/null 2>&1 || true
    case ":${MODULEPATH:-}:" in
        *:"${SPACK_MODULE_ROOT}":*) ;;
        *) export MODULEPATH="${SPACK_MODULE_ROOT}${MODULEPATH:+:${MODULEPATH}}" ;;
    esac
fi

unset module_prefix prefix shell_name
