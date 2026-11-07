#!/usr/bin/env bash
# Shared by the package's install.sh (sourced, not run): messages, system
# packages through the distro's package manager, fonts, and putting the
# config in ~/.config/<name> and its command on PATH (~/.local/bin, or
# /usr/local/bin when ~/.local/bin isn't on PATH).
#
# install.sh sets, before calling these:
#   ASSUME_YES     1 to skip the prompts
#   PACMAN_PKGS    Arch packages
# (SYSTEM_BIN overrides /usr/local/bin; INSTALL_PM exists only so a test can
# pin the package manager.)

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
    ((ASSUME_YES)) && return 0
    local reply
    read -rp "$1 [S/n] " reply
    [[ -z $reply || $reply =~ ^[SsYy] ]]
}

# pacman, or nothing: this package requires Omarchy, which is Arch (INSTALL_PM
# exists so a test can pin it).
package_manager() {
    if [[ -n ${INSTALL_PM-} ]]; then
        echo "$INSTALL_PM"
        return
    fi
    command -v pacman >/dev/null && echo pacman
}

# Installs the system packages this package needs, with whichever of
# pacman, apt or dnf is there. Quickshell is left alone when some build of
# it is already installed (quickshell and quickshell-git conflict on Arch).
install_system_packages() {
    local pm pkgs=("${PACMAN_PKGS[@]}") p flags=(-S --needed)

    pm=$(package_manager)
    if [[ $pm != pacman ]]; then
        die "este instalador solo admite Arch con pacman (Omarchy); instala esto tú mismo: ${pkgs[*]}"
    fi

    # Quickshell is left alone when some build of it is already installed
    # (quickshell and quickshell-git conflict on Arch).
    if command -v qs >/dev/null || command -v quickshell >/dev/null; then
        for p in "${!pkgs[@]}"; do
            [[ ${pkgs[p]} == quickshell ]] && unset 'pkgs[p]'
        done
        pkgs=("${pkgs[@]}")
    fi

    ((${#pkgs[@]})) || return
    info "Instalando paquetes con pacman: ${pkgs[*]}"
    ((ASSUME_YES)) && flags+=(--noconfirm)
    sudo pacman "${flags[@]}" "${pkgs[@]}" || warn "no instalados: ${pkgs[*]}"
}

fonts_dir() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"; }

has_font() { fc-list : family 2>/dev/null | grep -qi -- "$1"; }

# A font file from a URL into the user's fonts, unless a font of that
# family is installed already.
install_font() {  # family url file
    local family=$1 url=$2 file=$3 dir
    has_font "$family" && return
    dir=$(fonts_dir)
    info "Descargando la fuente $family"
    mkdir -p "$dir"
    if curl -fsSL "$url" -o "$dir/$file.part"; then
        mv "$dir/$file.part" "$dir/$file"
        fc-cache -f "$dir" >/dev/null 2>&1 || true
    else
        rm -f "$dir/$file.part"
        warn "no se pudo descargar $family; los iconos se verán como cuadros hasta que la instales"
    fi
}

# Nerd Fonts' symbols-only font (icon glyphs), unless some Nerd Font is there.
# Pinned to one release and checked before extracting: this runs as the user
# and unpacks a tarball, so "latest" is not good enough (audit 2026-11-06,
# finding 11).
NERD_FONT_VERSION="3.5.1"
NERD_FONT_SHA256="01172f37db8543edb102e5cb5c64101c9f4686630804d49b419aa07b23a69996"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONT_VERSION}/NerdFontsSymbolsOnly.tar.xz"

install_nerd_symbols() {
    local dir tmp sum
    has_font "Nerd Font" && return
    dir=$(fonts_dir)
    tmp=$(mktemp -d)
    info "Descargando la fuente Symbols Nerd Font ${NERD_FONT_VERSION}"
    if ! curl -fsSL "$NERD_FONT_URL" -o "$tmp/f.tar.xz"; then
        rm -rf "$tmp"
        warn "no se pudo descargar la fuente Symbols Nerd Font; los iconos se verán como cuadros hasta que instales una Nerd Font"
        return
    fi
    sum=$(sha256sum "$tmp/f.tar.xz" | cut -d' ' -f1)
    if [[ $sum != "$NERD_FONT_SHA256" ]]; then
        rm -rf "$tmp"
        warn "la fuente Symbols Nerd Font no coincide con su sha256; no la instalo"
        return
    fi
    if tar -xJf "$tmp/f.tar.xz" -C "$tmp"; then
        mkdir -p "$dir"
        cp "$tmp"/*.ttf "$dir/"
        fc-cache -f "$dir" >/dev/null 2>&1 || true
    else
        warn "no se pudo descomprimir la fuente Symbols Nerd Font"
    fi
    rm -rf "$tmp"
}

# This folder as ~/.config/$1, which `qs -p` runs: a symlink to it, or a
# copy with MODE=copy (an earlier copy is updated, keeping its settings and
# colours).
# Anything else already there is left alone, and the install stops.
install_config() {  # name
    local target="${XDG_CONFIG_HOME:-$HOME/.config}/$1"
    # Cloned right there, or linked by an earlier install.
    [[ $SRC_DIR -ef $target ]] && return
    if [[ -L $target ]]; then
        [[ ! -e $target || -e $target/.package-export ]] \
            || die "$target es un enlace a otra cosa; muévelo aparte y vuelve a ejecutar esto"
        rm "$target"
    elif [[ -e $target ]]; then
        [[ -e $target/.package-export ]] \
            || die "$target ya existe y no es $1; muévelo aparte y vuelve a ejecutar esto"
        [[ $MODE == copy ]] \
            || die "$target es una copia anterior de $1; bórrala, o vuelve a ejecutar con --copy para actualizarla"
        # Keep the copy's own state (settings and the palette file an install
        # from before the Omarchy adoption still carries), delete what no
        # longer exists, and never carry development folders into the config
        # (audit 2026-11-06, finding 24).
        rsync -a --delete \
            --exclude=.git --exclude=odd --exclude=tests \
            --exclude=settings.json --exclude=colors/Colors.json \
            "$SRC_DIR/" "$target/"
        info "Copia actualizada en $target"
        return
    fi
    mkdir -p "$(dirname "$target")"
    if [[ $MODE == copy ]]; then
        mkdir -p "$target"
        rsync -a --delete \
            --exclude=.git --exclude=odd --exclude=tests \
            "$SRC_DIR/" "$target/"
        info "Copiada a $target"
    else
        ln -s "$SRC_DIR" "$target"
        info "Enlazada $target -> $SRC_DIR"
    fi
}

on_path() { [[ ":$PATH:" == *":$1:"* ]]; }

# Links the command into a folder: as is, or with "sudo" as $3. A different
# file of that name is left alone (ours name themselves in their header,
# "Instalado por el install.sh de <name>"; installs made before the Spanish
# messages still say "Installed by <name>'s install.sh").
link_command() {  # source dest [sudo]
    local src=$1 dest=$2 name=${1##*/}
    # The command's header names itself in Spanish; an older install still
    # says it in English, so accept both before overwriting.
    if [[ -e $dest || -L $dest ]] && ! grep -qE "Installed by $name's install.sh|Instalado por el install.sh de $name" "$dest" 2>/dev/null; then
        warn "$dest existe y no es de este paquete; no lo toco (usa $src en su lugar)"
        return 1
    fi
    ${3-} mkdir -p "$(dirname "$dest")" && ${3-} ln -sfn "$src" "$dest" || return 1
    info "Comando $name instalado en $(dirname "$dest")"
}

# The line that puts ~/.local/bin on PATH for the user's shell.
path_hint() {
    case ${SHELL##*/} in
        fish) echo "fish_add_path ~/.local/bin" ;;
        zsh)  echo "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
        *)    echo "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc" ;;
    esac
}

# The package's command (bin/$1), linked into the config so it stays
# current: in ~/.local/bin when that's on PATH. Otherwise in /usr/local/bin
# (with sudo, after asking), which every shell and compositor has on PATH,
# so it works at once, in keybinds too. Declined, it goes in ~/.local/bin
# with the line that puts that on PATH.
install_command() {  # name
    local name=$1
    local src="${XDG_CONFIG_HOME:-$HOME/.config}/$name/bin/$name"
    local bin="$HOME/.local/bin"
    if on_path "$bin"; then
        link_command "$src" "$bin/$name" || true
        return
    fi
    local sys=${SYSTEM_BIN:-/usr/local/bin}
    if on_path "$sys" \
        && confirm "$bin no está en tu PATH. ¿Pongo el comando $name en $sys (necesita sudo)?" \
        && link_command "$src" "$sys/$name" sudo; then
        return
    fi
    link_command "$src" "$bin/$name" || return 0
    warn "$bin no está en tu PATH, así que '$name' no se encontrará. Añádelo con"
    printf '     %s\n' "$(path_hint)" >&2
    warn "luego abre una terminal nueva (y usa $bin/$name en los atajos del compositor, o vuelve a iniciar sesión)."
}
