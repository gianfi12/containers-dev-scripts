# envs

Portable Apptainer layout.

Top-level structure:

- `bin/`: entry, Spack bootstrap, and build wrappers
- `defs/`: Apptainer definition files
- `images/`: built SIF images

Recommended base-image workflow:

```bash
cd /home/gaccordi/envs
./bin/base-build.sh
./bin/base-enter.sh
./bin/base-bootstrap-spack.sh --spack "$PWD/.apptainer-spack"
./bin/base-enter.sh --spack "$PWD/.apptainer-spack"
```

Direct raw entry:

```bash
apptainer run \
  --home "$HOME:/home/$USER" \
  ./images/base.sif
```

Direct raw entry with a Spack state:

```bash
apptainer run \
  --home "$HOME:/home/$USER" \
  --bind "$PWD/.apptainer-spack:/home/$USER/.apptainer-spack" \
  --bind "$PWD/.apptainer-spack/.module:/home/$USER/.module" \
  --env APPTAINER_DEV_STATE_DIR=/home/$USER/.apptainer-spack \
  ./images/base.sif
```

Active files:

- image: [`images/base.sif`](/home/gaccordi/envs/images/base.sif)
- definition: [`defs/base.def`](/home/gaccordi/envs/defs/base.def)
- enter wrapper: [`bin/base-enter.sh`](/home/gaccordi/envs/bin/base-enter.sh)
- bootstrap wrapper: [`bin/base-bootstrap-spack.sh`](/home/gaccordi/envs/bin/base-bootstrap-spack.sh)
- build wrapper: [`bin/base-build.sh`](/home/gaccordi/envs/bin/base-build.sh)

Current behavior:

- `./bin/base-enter.sh` works without Spack
- `./bin/base-enter.sh --spack DIR` mounts an already-initialized Spack state
- `./bin/base-bootstrap-spack.sh --spack DIR` initializes a Spack state from inside the container
- module saved collections are isolated per state in `DIR/.module`

Notes:

- the base image does not bake in HyDE, starship, or any other machine-specific host prompt stack
- your mounted zsh config may therefore fall back to a plain prompt on systems where those prompt dependencies are not present
- the definition includes OS/editor/build dependencies only; Spack itself stays external in the selected state directory
- future image builds also include `ImageMagick`, so `identify` is available inside the container
