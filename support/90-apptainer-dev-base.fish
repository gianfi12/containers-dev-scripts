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

function module_chain
    if test (count $argv) -ne 1; or not test -d "$argv[1]"
        echo 'Usage: module_chain MODULEFILE_DIRECTORY' >&2
        return 2
    end
    if not type -q module
        echo 'Environment Modules is not initialized in this shell.' >&2
        return 1
    end
    module use "$argv[1]"
end

function spack_chain
    if test (count $argv) -ne 1
        echo 'Usage: spack_chain SPACK_INSTALL_TREE' >&2
        return 2
    end
    if set -q APPTAINER_DEV_SPACK_CHAIN_CONFIG
        echo "A Spack upstream is already active: $APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE" >&2
        echo 'Run spack_unchain before selecting another.' >&2
        return 1
    end

    set -l install_tree (string replace -r '/+$' '' -- "$argv[1]")
    if not test -d "$install_tree/.spack-db"
        echo "Spack install tree or database not found: $install_tree/.spack-db" >&2
        return 1
    end

    set -l base_config "$SPACK_USER_CONFIG_PATH"
    set -l temp_parent /tmp
    if set -q APPTAINER_DEV_RUNTIME_DIR
        set temp_parent "$APPTAINER_DEV_RUNTIME_DIR"
    else if set -q TMPDIR
        set temp_parent "$TMPDIR"
    end
    if not test -d "$temp_parent"; or not test -w "$temp_parent"
        set temp_parent /tmp
    end
    set -g APPTAINER_DEV_SPACK_CHAIN_CONFIG (mktemp -d "$temp_parent/spack-chain.XXXXXX")
    or return 1
    set -g APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG "$base_config"
    mkdir -p "$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
    if test -d "$base_config"
        cp -a "$base_config/." "$APPTAINER_DEV_SPACK_CHAIN_CONFIG/"
        or return 1
    end

    set -l yaml_install_tree (string replace -a "'" "''" -- "$install_tree")
    printf "upstreams:\n  hpc:\n    install_tree: '%s'\n" "$yaml_install_tree" >"$APPTAINER_DEV_SPACK_CHAIN_CONFIG/upstreams.yaml"
    or return 1

    set -gx SPACK_USER_CONFIG_PATH "$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
    spack config get upstreams >/dev/null
    or begin
        echo "Spack rejected the upstream configuration for $install_tree" >&2
        spack_unchain
        return 1
    end
    set -g APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE "$install_tree"
    echo "Spack upstream enabled for this shell: $install_tree"
end

function spack_unchain
    if not set -q APPTAINER_DEV_SPACK_CHAIN_CONFIG
        echo 'No temporary Spack upstream is active.' >&2
        return 1
    end
    set -gx SPACK_USER_CONFIG_PATH "$APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG"
    switch "$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
        case '*/spack-chain.*'
            rm -rf -- "$APPTAINER_DEV_SPACK_CHAIN_CONFIG"
        case '*'
            echo "Refusing to remove unexpected config path: $APPTAINER_DEV_SPACK_CHAIN_CONFIG" >&2
            return 1
    end
    set -e APPTAINER_DEV_SPACK_CHAIN_CONFIG APPTAINER_DEV_SPACK_CHAIN_BASE_CONFIG APPTAINER_DEV_SPACK_CHAIN_INSTALL_TREE
    echo 'Container Spack configuration restored for this shell.'
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
