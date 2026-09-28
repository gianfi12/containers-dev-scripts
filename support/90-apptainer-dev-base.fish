set -q APPTAINER_DEV_MOUNT; or set -gx APPTAINER_DEV_MOUNT ""
set -q APPTAINER_DEV_STATE_DIR; or set -gx APPTAINER_DEV_STATE_DIR ""

if test -n "$APPTAINER_DEV_MOUNT"; and test -z "$APPTAINER_DEV_STATE_DIR"
    set -gx APPTAINER_DEV_STATE_DIR "$APPTAINER_DEV_MOUNT/spack"
end

if test -n "$APPTAINER_DEV_STATE_DIR"
    if test -f "$APPTAINER_DEV_STATE_DIR/spack/share/spack/setup-env.fish"
        set -gx APPTAINER_DEV_SPACK_ROOT "$APPTAINER_DEV_STATE_DIR/spack"
    else
        set -gx APPTAINER_DEV_SPACK_ROOT /opt/spack
    end

    set -gx SPACK_ROOT "$APPTAINER_DEV_SPACK_ROOT"
    set -gx SPACK_MODULE_ROOT "$APPTAINER_DEV_STATE_DIR/modules"
    set -gx SPACK_USER_CONFIG_PATH "$APPTAINER_DEV_STATE_DIR/config"
    set -gx SPACK_USER_CACHE_PATH "$APPTAINER_DEV_STATE_DIR/cache"

    if test -n "$APPTAINER_DEV_MOUNT"
        set -gx APPTAINER_DEV_VENVS "$APPTAINER_DEV_MOUNT/venvs"
        set -gx XDG_DATA_HOME "$APPTAINER_DEV_MOUNT/.local/share"
        set -gx XDG_STATE_HOME "$APPTAINER_DEV_MOUNT/.local/state"
        set -gx XDG_CACHE_HOME "$APPTAINER_DEV_MOUNT/.cache"
        set -q PASSWORD_STORE_DIR; or set -gx PASSWORD_STORE_DIR "$APPTAINER_DEV_MOUNT/.password-store"
        set -q GNUPGHOME; or set -gx GNUPGHOME "$APPTAINER_DEV_MOUNT/.gnupg"
        set -q CODEX_HOME; or set -gx CODEX_HOME "$APPTAINER_DEV_MOUNT/.codex"
        mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$PASSWORD_STORE_DIR" "$CODEX_HOME" 2>/dev/null
        if not test -d "$GNUPGHOME"
            mkdir -p "$GNUPGHOME" 2>/dev/null
            chmod 700 "$GNUPGHOME" 2>/dev/null
        end
        if test -d "$XDG_DATA_HOME/nvim/mason/bin"
            if not contains "$XDG_DATA_HOME/nvim/mason/bin" $PATH
                set -gx PATH "$XDG_DATA_HOME/nvim/mason/bin" $PATH
            end
        end
    end

    if test -f "$SPACK_ROOT/share/spack/setup-env.fish"
        source "$SPACK_ROOT/share/spack/setup-env.fish"
    end
end
