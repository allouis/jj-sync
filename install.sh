#!/usr/bin/env bash
# install.sh - Install jj-sync
set -euo pipefail

# Default installation prefix
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBDIR="${LIBDIR:-$PREFIX/share/jj-sync}"
COMPLETIONS_DIR_BASH="${COMPLETIONS_DIR_BASH:-$PREFIX/share/bash-completion/completions}"
COMPLETIONS_DIR_ZSH="${COMPLETIONS_DIR_ZSH:-$PREFIX/share/zsh/site-functions}"
COMPLETIONS_DIR_FISH="${COMPLETIONS_DIR_FISH:-$HOME/.config/fish/completions}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install jj-sync to your system.

Options:
    --prefix=PATH       Installation prefix (default: ~/.local)
    --bindir=PATH       Binary directory (default: PREFIX/bin)
    --uninstall         Remove jj-sync
    --help              Show this help

Environment variables:
    PREFIX              Installation prefix
    BINDIR              Binary directory
    COMPLETIONS_DIR_BASH  Bash completions directory
    COMPLETIONS_DIR_ZSH   Zsh completions directory

Examples:
    $0                          # Install to ~/.local
    $0 --prefix=/usr/local      # Install system-wide (requires sudo)
    $0 --uninstall              # Remove jj-sync

EOF
}

install_jj_sync() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    info "Installing jj-sync..."

    # Create directories
    mkdir -p "$BINDIR"
    mkdir -p "$LIBDIR"
    mkdir -p "$COMPLETIONS_DIR_BASH"
    mkdir -p "$COMPLETIONS_DIR_ZSH"
    mkdir -p "$COMPLETIONS_DIR_FISH"

    # Copy library files
    info "Installing library files to $LIBDIR"
    cp -r "$script_dir/lib/"*.sh "$LIBDIR/"
    success "Library files installed"

    # Create the main script with correct LIBDIR
    info "Installing jj-sync to $BINDIR"
    sed "s|^SCRIPT_DIR=.*|LIBDIR=\"$LIBDIR\"|" "$script_dir/jj-sync" > "$BINDIR/jj-sync"
    chmod +x "$BINDIR/jj-sync"

    # Fix the source paths in the installed script
    sed -i "s|source \"\$SCRIPT_DIR/lib/|source \"\$LIBDIR/|g" "$BINDIR/jj-sync"
    success "jj-sync installed"

    # Install completions
    if [[ -d "$script_dir/completions" ]]; then
        info "Installing shell completions"

        if [[ -f "$script_dir/completions/jj-sync.bash" ]]; then
            cp "$script_dir/completions/jj-sync.bash" "$COMPLETIONS_DIR_BASH/jj-sync"
            success "Bash completions installed to $COMPLETIONS_DIR_BASH"
        fi

        if [[ -f "$script_dir/completions/_jj-sync" ]]; then
            cp "$script_dir/completions/_jj-sync" "$COMPLETIONS_DIR_ZSH/_jj-sync"
            success "Zsh completions installed to $COMPLETIONS_DIR_ZSH"
        fi

        if [[ -f "$script_dir/completions/jj-sync.fish" ]]; then
            cp "$script_dir/completions/jj-sync.fish" "$COMPLETIONS_DIR_FISH/jj-sync.fish"
            success "Fish completions installed to $COMPLETIONS_DIR_FISH"
        fi
    fi

    echo ""
    success "Installation complete!"
    echo ""

    # Check if bindir is in PATH
    if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
        warn "Note: $BINDIR is not in your PATH"
        echo ""
        echo "Add this to your shell profile (.bashrc, .zshrc, etc.):"
        echo ""
        echo "    export PATH=\"$BINDIR:\$PATH\""
        echo ""
    fi

    # Show completion setup instructions
    echo "To enable shell completions:"
    echo ""
    echo "  Bash: Add to ~/.bashrc:"
    echo "    source $COMPLETIONS_DIR_BASH/jj-sync"
    echo ""
    echo "  Zsh: Add $COMPLETIONS_DIR_ZSH to your fpath before compinit"
    echo ""
    echo "  Fish: Completions auto-loaded from $COMPLETIONS_DIR_FISH"
    echo ""
}

uninstall_jj_sync() {
    info "Uninstalling jj-sync..."

    if [[ -f "$BINDIR/jj-sync" ]]; then
        rm -f "$BINDIR/jj-sync"
        success "Removed $BINDIR/jj-sync"
    fi

    if [[ -d "$LIBDIR" ]]; then
        rm -rf "$LIBDIR"
        success "Removed $LIBDIR"
    fi

    if [[ -f "$COMPLETIONS_DIR_BASH/jj-sync" ]]; then
        rm -f "$COMPLETIONS_DIR_BASH/jj-sync"
        success "Removed bash completions"
    fi

    if [[ -f "$COMPLETIONS_DIR_ZSH/_jj-sync" ]]; then
        rm -f "$COMPLETIONS_DIR_ZSH/_jj-sync"
        success "Removed zsh completions"
    fi

    if [[ -f "$COMPLETIONS_DIR_FISH/jj-sync.fish" ]]; then
        rm -f "$COMPLETIONS_DIR_FISH/jj-sync.fish"
        success "Removed fish completions"
    fi

    echo ""
    success "Uninstallation complete!"
}

# Parse arguments
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix=*)
            PREFIX="${1#*=}"
            BINDIR="$PREFIX/bin"
            LIBDIR="$PREFIX/share/jj-sync"
            COMPLETIONS_DIR_BASH="$PREFIX/share/bash-completion/completions"
            COMPLETIONS_DIR_ZSH="$PREFIX/share/zsh/site-functions"
            shift
            ;;
        --bindir=*)
            BINDIR="${1#*=}"
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run installation or uninstallation
if [[ "$UNINSTALL" == "true" ]]; then
    uninstall_jj_sync
else
    install_jj_sync
fi
