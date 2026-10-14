#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/bin/base-runtime-common.sh"
STATE_USER="$(id -un)"
QUIET=0

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") STATE_DIR

Create a host state directory layout for the Apptainer base image.

Layout:
  STATE_DIR/
    spack/
      config/
      cache/
      environments/default/
      modules/
      stage/
    .module/
    venvs/
    work/
    scratch/
    opt/
    data/
    home/USER/              Persistent container home (separate from host home)
      .oh-my-bash/
      .oh-my-zsh/
      .local/share/omf/
      .local/bin/starship
      .tmux/
USAGE
}

STATE_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    *)
      if [[ -z "$STATE_DIR" ]]; then
        STATE_DIR="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$STATE_DIR" ]]; then
  usage >&2
  exit 1
fi

init_mount_state_layout "$STATE_DIR" "$STATE_USER"

CONTAINER_HOME="$STATE_DIR/home/$STATE_USER"

install_repo() {
  local url="$1"
  local destination="$2"
  local temporary="${destination}.install.$$"

  if [[ -d "$destination/.git" ]]; then
    return 0
  fi
  if [[ -e "$destination" ]]; then
    echo "Cannot install $url: $destination exists but is not a Git checkout." >&2
    return 1
  fi

  mkdir -p "$(dirname "$destination")"
  if ! git clone --depth 1 --single-branch "$url" "$temporary"; then
    rm -rf -- "$temporary"
    echo "Failed to install $url. Check network access and rerun this initializer." >&2
    return 1
  fi
  mv "$temporary" "$destination"
}

install_repo https://github.com/ohmybash/oh-my-bash.git "$CONTAINER_HOME/.oh-my-bash"
install_repo https://github.com/ohmyzsh/ohmyzsh.git "$CONTAINER_HOME/.oh-my-zsh"
install_repo https://github.com/oh-my-fish/oh-my-fish.git "$CONTAINER_HOME/.local/share/omf"
install_repo https://github.com/gpakosz/.tmux.git "$CONTAINER_HOME/.tmux"

mkdir -p "$CONTAINER_HOME/.local/bin"
if [[ ! -x "$CONTAINER_HOME/.local/bin/starship" ]]; then
  if ! curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$CONTAINER_HOME/.local/bin"; then
    echo "Failed to install Starship. Check network access and rerun this initializer." >&2
    exit 1
  fi
fi

if [[ ! -e "$CONTAINER_HOME/.bashrc" ]]; then
  cat > "$CONTAINER_HOME/.bashrc" <<'BASHRC'
export PATH="$HOME/.local/bin:$PATH"
export OSH="$HOME/.oh-my-bash"
OSH_THEME="font"
plugins=(git)
[[ -r "$OSH/oh-my-bash.sh" ]] && source "$OSH/oh-my-bash.sh"
eval "$(starship init bash)"

# fzf bindings: Ctrl-R history, Ctrl-T files, Alt-C directories.
export FZF_TMUX=1
[[ -r /usr/share/fzf/shell/key-bindings.bash ]] && source /usr/share/fzf/shell/key-bindings.bash
[[ -r /usr/share/bash-completion/completions/fzf ]] && source /usr/share/bash-completion/completions/fzf
BASHRC
fi

if [[ ! -e "$CONTAINER_HOME/.bash_profile" ]]; then
  cat > "$CONTAINER_HOME/.bash_profile" <<'BASHPROFILE'
[[ -r "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
BASHPROFILE
fi

if [[ ! -e "$CONTAINER_HOME/.zshrc" ]]; then
  cat > "$CONTAINER_HOME/.zshrc" <<'ZSHRC'
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"
eval "$(starship init zsh)"

# fzf bindings: Ctrl-R history, Ctrl-T files, Alt-C directories.
export FZF_TMUX=1
[[ -r /usr/share/fzf/shell/key-bindings.zsh ]] && source /usr/share/fzf/shell/key-bindings.zsh
ZSHRC
fi

FISH_CONFIG="$CONTAINER_HOME/.config/fish/config.fish"
if [[ ! -e "$FISH_CONFIG" ]]; then
  cat > "$FISH_CONFIG" <<'FISHCONFIG'
fish_add_path "$HOME/.local/bin"
set -gx OMF_PATH "$HOME/.local/share/omf"
if test -f "$OMF_PATH/init.fish"
    source "$OMF_PATH/init.fish"
end
starship init fish | source

FISHCONFIG
fi

if [[ ! -e "$CONTAINER_HOME/.tmux.conf" ]]; then
  ln -s .tmux/.tmux.conf "$CONTAINER_HOME/.tmux.conf"
fi
if [[ ! -e "$CONTAINER_HOME/.tmux.conf.local" ]]; then
  cp "$CONTAINER_HOME/.tmux/.tmux.conf.local" "$CONTAINER_HOME/.tmux.conf.local"
  cat >> "$CONTAINER_HOME/.tmux.conf.local" <<'TMUX'
tmux_conf_copy_to_os_clipboard=true
set -g default-terminal "tmux-256color"
set -g set-clipboard on
set -g mouse on
set -g status-keys vi
set -g mode-keys vi
TMUX
fi

NVIM_CONFIG_DIR="$CONTAINER_HOME/.config/nvim"
NVIM_STARTER_TEMP="$CONTAINER_HOME/.config/nvim.starter.$$"
if [[ ! -e "$NVIM_CONFIG_DIR" ]]; then
  rm -rf -- "$NVIM_STARTER_TEMP"
  if ! git clone --depth 1 --single-branch https://github.com/LazyVim/starter.git "$NVIM_STARTER_TEMP"; then
    rm -rf -- "$NVIM_STARTER_TEMP"
    echo "Failed to install LazyVim starter. Check network access and rerun this initializer." >&2
    exit 1
  fi
  rm -rf -- "$NVIM_STARTER_TEMP/.git"
  mv "$NVIM_STARTER_TEMP" "$NVIM_CONFIG_DIR"
fi

CONFIG_FILE="$STATE_DIR/spack/config/config.yaml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<'YAML'
config:
  install_tree:
    root: /mnt/dev/spack/store
  build_stage:
  - /mnt/dev/spack/stage
  environments_root: /mnt/dev/spack/environments
  source_cache: /mnt/dev/spack/cache/source
  misc_cache: /mnt/dev/spack/cache/misc
YAML
fi

MODULES_FILE="$STATE_DIR/spack/config/modules.yaml"
if [[ ! -f "$MODULES_FILE" ]]; then
  cat > "$MODULES_FILE" <<'YAML'
modules:
  default:
    enable:
      - tcl
    roots:
      tcl: /mnt/dev/spack/modules
    arch_folder: false
    tcl:
      hide_implicits: true
YAML
fi

if [[ "$QUIET" -eq 0 ]]; then
cat <<OUT
Initialized state directory:
  $STATE_DIR

Important paths:
  Spack state:      $STATE_DIR/spack
  Modulefiles:      $STATE_DIR/spack/modules
  Module collections: $STATE_DIR/.module
  Virtualenvs:      $STATE_DIR/venvs
  Workspace:        $STATE_DIR/work
  Scratch:          $STATE_DIR/scratch
  Extra software:   $STATE_DIR/opt
  User data:        $STATE_DIR/data
  Container home:   $CONTAINER_HOME
  Shell frameworks: Oh My Bash, Oh My Zsh, Oh My Fish, Oh My Tmux
  Shared prompt:    Starship (Bash, Zsh and Fish)
  Fuzzy bindings:   fzf enabled for Bash, Zsh and Fish

Notes:
  - The container profile script will use /mnt/dev/spack as APPTAINER_DEV_STATE_DIR.
  - Spack runs from the image at /opt/spack.
OUT
fi
