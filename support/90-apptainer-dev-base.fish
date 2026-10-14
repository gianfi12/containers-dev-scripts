set -q APPTAINER_DEV_MOUNT; or set -gx APPTAINER_DEV_MOUNT ""
set -q APPTAINER_DEV_STATE_DIR; or set -gx APPTAINER_DEV_STATE_DIR ""

# Minimal/clean Singularity environments may leave the locale at plain C,
# which makes tmux and shell prompts treat UTF-8 symbols as non-printable.
if not set -q LANG; or test "$LANG" = C; or test "$LANG" = POSIX
    set -gx LANG C.UTF-8
end
if not set -q LC_CTYPE; or test "$LC_CTYPE" = C; or test "$LC_CTYPE" = POSIX
    set -gx LC_CTYPE C.UTF-8
end

if command -q fzf
    fzf --fish | source
    set -gx FZF_TMUX 1
end

if test -n "$APPTAINER_DEV_MOUNT"
    set -gx APPTAINER_DEV_STATE_DIR "$APPTAINER_DEV_MOUNT/spack"
    set -gx SPACK_ROOT /opt/spack
    set -gx SPACK_MODULE_ROOT "$APPTAINER_DEV_STATE_DIR/modules"
    set -gx SPACK_USER_CONFIG_PATH "$APPTAINER_DEV_STATE_DIR/config"
    set -gx SPACK_USER_CACHE_PATH "$APPTAINER_DEV_STATE_DIR/cache"

    set -gx APPTAINER_DEV_VENVS "$APPTAINER_DEV_MOUNT/venvs"
    set -gx XDG_DATA_HOME "$APPTAINER_DEV_MOUNT/.local/share"
    set -gx XDG_STATE_HOME "$APPTAINER_DEV_MOUNT/.local/state"
    set -gx XDG_CACHE_HOME "$APPTAINER_DEV_MOUNT/.cache"
    mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" 2>/dev/null
    if test -d "$XDG_DATA_HOME/nvim/mason/bin"
        if not contains "$XDG_DATA_HOME/nvim/mason/bin" $PATH
            set -gx PATH "$XDG_DATA_HOME/nvim/mason/bin" $PATH
        end
    end
    source /usr/share/Modules/init/fish
    source "$SPACK_ROOT/share/spack/setup-env.fish"
end
