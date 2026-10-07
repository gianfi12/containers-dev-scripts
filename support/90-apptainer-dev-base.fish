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
        set -q CODEX_HOME; or set -gx CODEX_HOME "$APPTAINER_DEV_MOUNT/.codex"
        mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$CODEX_HOME" 2>/dev/null
        if test -d "$XDG_DATA_HOME/nvim/mason/bin"
            if not contains "$XDG_DATA_HOME/nvim/mason/bin" $PATH
                set -gx PATH "$XDG_DATA_HOME/nvim/mason/bin" $PATH
            end
        end
    end

    # Keep Codex credentials in the private GNOME Keyring.  Unlocking remains
    # manual through keyring-unlock when credentials are actually needed.
    mkdir -p "$CODEX_HOME" 2>/dev/null
    set codex_config "$CODEX_HOME/config.toml"
    if test -f "$codex_config"; and grep -qE '^[[:space:]]*cli_auth_credentials_store[[:space:]]*=' "$codex_config"
        sed -i 's/^[[:space:]]*cli_auth_credentials_store[[:space:]]*=.*/cli_auth_credentials_store = "keyring"/' "$codex_config" 2>/dev/null
    else
        printf '\ncli_auth_credentials_store = "keyring"\n' >> "$codex_config" 2>/dev/null
    end
    set -e codex_config

    if test -f "$SPACK_ROOT/share/spack/setup-env.fish"
        source "$SPACK_ROOT/share/spack/setup-env.fish"
    end
end

# Some host Fish configurations erase the universal fish_key_bindings value
# during migration. Restore Fish's normal bindings inside the container.
if not set -q fish_key_bindings
    set -g fish_key_bindings fish_default_key_bindings
end

# Prefer fzf's interactive history/file completion when available. Otherwise
# Fish keeps its standard history-search behavior.
if command -q fzf
    fzf --fish | source
end
