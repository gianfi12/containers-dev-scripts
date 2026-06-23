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
    end

    if test -f "$SPACK_ROOT/share/spack/setup-env.fish"
        source "$SPACK_ROOT/share/spack/setup-env.fish"
    end
end
