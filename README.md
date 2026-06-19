# envs

Portable Apptainer development environment.

Top-level structure:

- `bin/`: build, entry, and Spack bootstrap wrappers
- `defs/`: Apptainer definition files
- `images/`: local SIF images, ignored by git
- `mounts/`: local writable mount roots, ignored by git except `.gitkeep`
- `support/`: host-side profile snippets bound into containers by wrappers

## Recommended Workflow

Build the base image:

```bash
cd /home/gaccordi/envs
./bin/base-build.sh
```

Create and initialize a writable mount root:

```bash
./bin/base-bootstrap-spack.sh --mount-state "$PWD/mounts/fedora"
```

Enter the container:

```bash
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora"
```

Run one command inside the container:

```bash
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora" -- bash -lc 'spack find'
```

The wrapper prints the exact `apptainer` command before executing it.

## Raw Apptainer Command

The wrapper is preferred, but the equivalent shape is:

```bash
apptainer run \
  --home "$HOME:/home/$USER" \
  --bind "$PWD/mounts/fedora:/mnt/dev" \
  --bind "$PWD/mounts/fedora/.module:/home/$USER/.module" \
  --env APPTAINER_DEV_MOUNT=/mnt/dev \
  --env APPTAINER_DEV_STATE_DIR=/mnt/dev/spack \
  ./images/base.sif
```

`base-enter.sh` mounts the host home by default at `/home/$USER`. Additional bind and mount flags are forwarded to Apptainer unchanged. If you want a project mounted at `/workspace`, pass it explicitly:

```bash
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora" \
  --bind "$PWD/my-project:/workspace" \
  --pwd /workspace
```

## Spack Model

The base image contains Spack at `/opt/spack`. The writable mount stores everything that grows or changes:

```text
mounts/fedora/
  spack/
    store/
    modules/
    environments/
    config/
    cache/
    stage/
  venvs/
  work/
  scratch/
  opt/
  .module/
```

Inside the container this becomes:

```text
/opt/spack
/mnt/dev/spack
/mnt/dev/venvs
/mnt/dev/work
/mnt/dev/scratch
/mnt/dev/opt
```

The profile sets:

```bash
SPACK_ROOT=/opt/spack
SPACK_ENV_DIR=/mnt/dev/spack/environments/default
SPACK_MODULE_ROOT=/mnt/dev/spack/modules
SPACK_USER_CONFIG_PATH=/mnt/dev/spack/config
SPACK_USER_CACHE_PATH=/mnt/dev/spack/cache
APPTAINER_DEV_VENVS=/mnt/dev/venvs
```

`dev-bootstrap-spack-state` configures Tcl module generation automatically. After `spack install`, refresh modules manually if needed:

```bash
spack module tcl refresh -y
module avail
module save default
```

## Existing `.apptainer-spack` and Migration

Your previous state is still supported:

```bash
./bin/base-enter.sh --spack "$PWD/.apptainer-spack"
```

This legacy mode keeps the old state mounted at `/home/$USER/.apptainer-spack` and uses the `spack/` checkout inside that state if present. That avoids breaking installed packages whose prefixes were created with the old path.

### Can the old install be converted?

Not safely by just moving or renaming folders. The existing packages were installed with prefixes under the old mounted path, for example:

```text
/home/$USER/.apptainer-spack/store/...
```

The new layout uses:

```text
/mnt/dev/spack/store/...
```

Many Spack-installed packages and generated modulefiles embed absolute paths. Moving the store directly can leave binaries, RPATHs, scripts, pkg-config files, CMake files, and modulefiles pointing to the old location.

### Recommended path: migrate specs, rebuild packages

This is the clean migration. It preserves the package list and environment intent, but rebuilds/install packages into the new mount layout.

```bash
./bin/base-enter.sh --spack "$PWD/.apptainer-spack" -- bash -lc 'spack -e "$SPACK_ENV_DIR" find'
cp .apptainer-spack/environments/default/spack.yaml /tmp/old-spack.yaml
./bin/base-bootstrap-spack.sh --mount-state "$PWD/mounts/fedora"
cp /tmp/old-spack.yaml mounts/fedora/spack/environments/default/spack.yaml
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora" -- bash -lc 'spack -e "$SPACK_ENV_DIR" concretize -f && spack -e "$SPACK_ENV_DIR" install'
```

If you also have a lock file and want to try reproducing the exact concretized DAG, copy it too:

```bash
cp .apptainer-spack/environments/default/spack.lock mounts/fedora/spack/environments/default/spack.lock
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora" -- bash -lc 'spack -e "$SPACK_ENV_DIR" install'
```

If the old lock references compiler/OS details that no longer match the rebuilt image, remove the copied lock and reconcretize:

```bash
rm mounts/fedora/spack/environments/default/spack.lock
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora" -- bash -lc 'spack -e "$SPACK_ENV_DIR" concretize -f && spack -e "$SPACK_ENV_DIR" install'
```

### Safe short-term path: keep the old state

If you need the old packages immediately, keep using:

```bash
./bin/base-enter.sh --spack "$PWD/.apptainer-spack"
```

Use the new mount layout only for new environments:

```bash
./bin/base-bootstrap-spack.sh --mount-state "$PWD/mounts/fedora"
./bin/base-enter.sh --mount-state "$PWD/mounts/fedora"
```

### Advanced path: Spack buildcache

Spack can create binary caches and reinstall from them elsewhere, but this is not the same as moving the store. It requires signing or trusting buildcache metadata, and relocation only works for packages that Spack can relocate correctly.

Use this only if rebuild time is the main problem and you are willing to debug package-specific relocation issues. For this setup, the default recommendation remains: migrate `spack.yaml`, optionally try `spack.lock`, and reinstall into `/mnt/dev/spack`.

## Python Venvs

Use `/mnt/dev/venvs` for persistent virtualenvs:

```bash
python3 -m venv /mnt/dev/venvs/project-a
source /mnt/dev/venvs/project-a/bin/activate
python -m pip install -U pip
```

If you want the venv tied to a Spack-managed Python stack:

```bash
spack add python
spack install
spack load python
python -m venv /mnt/dev/venvs/project-a-spack-python
```

Best practice is one venv per project and per major Python stack. If the Spack Python/compiler stack changes significantly, recreate the venv instead of trying to repair it in place.

## Mount Folder Best Practices

The wrappers create this structure automatically when you pass `--mount-state DIR` to either `base-enter.sh` or `base-bootstrap-spack.sh`:

```text
DIR/
  spack/
  venvs/
  work/
  scratch/
  opt/
  .module/
```

Use the folders like this:

- `spack/`: Spack store, config, environments, modulefiles, cache, and build stage. Do not put project source trees here.
- `venvs/`: Python virtual environments. Keep them outside project folders so they are easy to remove and recreate.
- `work/`: Git repositories, project source trees, notebooks, and active development folders.
- `scratch/`: temporary build outputs, downloaded datasets, and disposable large files.
- `opt/`: manually installed tools that are not managed by Spack or the base image.
- `.module/`: saved environment-module collections, used by `module save`.

Example project layout:

```text
/mnt/dev/work/rdkit-notebooks/
/mnt/dev/venvs/rdkit-notebooks-py312/
/mnt/dev/scratch/rdkit-notebooks/
```

Create the project and venv:

```bash
mkdir -p /mnt/dev/work/rdkit-notebooks
cd /mnt/dev/work/rdkit-notebooks
python3 -m venv /mnt/dev/venvs/rdkit-notebooks-py312
source /mnt/dev/venvs/rdkit-notebooks-py312/bin/activate
```

If you use Spack Python, name the venv so the interpreter relationship is obvious:

```bash
spack install python@3.12
spack load python@3.12
python -m venv /mnt/dev/venvs/rdkit-notebooks-spack-py312
```

A Python venv is tied to the interpreter that created it. A venv created from the container system Python is tied to that container image. A venv created from Spack Python is tied to the Spack Python prefix under `/mnt/dev/spack/store`.

For sharing venvs across different containers, prefer Spack Python and keep the mount path stable:

```text
host:      /home/gaccordi/envs/mounts/fedora
container: /mnt/dev
venv:      /mnt/dev/venvs/project-spack-py312
python:    /mnt/dev/spack/store/.../python-3.12...
```

Different containers can reuse that venv only if they mount the same state at the same container path and are ABI-compatible with the packages inside the venv. If in doubt, keep `requirements.txt`, `pyproject.toml`, or `uv.lock`/`requirements.lock` in the project and recreate the venv.

## Neovim, tmux, and Clipboard

The base image includes Neovim and tmux. It also includes `wl-copy`, `xclip`, and `xsel` for local graphical clipboard integration when the required host sockets are available.

For tmux copy/paste that works through SSH and across machines, prefer OSC52 in your tmux config. OSC52 sends clipboard data through the terminal escape stream, so it can work even when Wayland/X11 sockets are not available inside the container.

Recommended portable tmux config settings:

```tmux
set -g set-clipboard on
set -as terminal-features ',xterm-256color:clipboard'
set -as terminal-features ',screen-256color:clipboard'
set -as terminal-features ',tmux-256color:clipboard'
```

Then make sure your outer terminal allows OSC52 clipboard writes. Kitty supports this, but it may need to be enabled depending on your local config. Over SSH, OSC52 must be allowed by every terminal/tmux layer between the remote shell and your local terminal.

For portable editor/session config, keep your dotfiles repo separate from the Spack store. A practical layout is:

```text
mounts/fedora/
  config/
    nvim/
    tmux/
  spack/
  venvs/
  work/
```

If you later bake only these configs into the image, place them under a neutral path such as `/opt/dev-config/nvim` and `/opt/dev-config/tmux`, then symlink or point tools to them at shell startup. Do not bake machine-specific home config or secrets into the image.

## New Images

Generate a new image from the definition:

```bash
./bin/base-build.sh
```

Use a different output path:

```bash
./bin/base-build.sh --image "$PWD/images/base-next.sif"
./bin/base-enter.sh --image "$PWD/images/base-next.sif" --mount-state "$PWD/mounts/fedora"
```

You can rebuild or swap the SIF without deleting `mounts/fedora`. The image owns `/opt/spack`; the mount owns installed packages, environments, modulefiles, cache, venvs, and user data.
