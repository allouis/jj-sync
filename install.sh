#!/usr/bin/env bash
# install.sh - Install refsync
set -euo pipefail

# Default installation prefix
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBDIR="${LIBDIR:-$PREFIX/share/refsync}"
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

Install refsync to your system.

Options:
    --prefix=PATH       Installation prefix (default: ~/.local)
    --bindir=PATH       Binary directory (default: PREFIX/bin)
    --uninstall         Remove refsync
    --help              Show this help

Environment variables:
    PREFIX              Installation prefix
    BINDIR              Binary directory
    COMPLETIONS_DIR_BASH  Bash completions directory
    COMPLETIONS_DIR_ZSH   Zsh completions directory

Examples:
    $0                          # Install to ~/.local
    $0 --prefix=/usr/local      # Install system-wide (requires sudo)
    $0 --uninstall              # Remove refsync

EOF
}

install_refsync() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    info "Installing refsync..."

    # Create directories
    mkdir -p "$BINDIR"
    mkdir -p "$COMPLETIONS_DIR_BASH"
    mkdir -p "$COMPLETIONS_DIR_ZSH"
    mkdir -p "$COMPLETIONS_DIR_FISH"

    # Install the self-contained script
    info "Installing refsync to $BINDIR"
    cp "$script_dir/refsync" "$BINDIR/refsync"
    chmod +x "$BINDIR/refsync"
    success "refsync installed"

    # Install completions
    if [[ -d "$script_dir/completions" ]]; then
        info "Installing shell completions"

        if [[ -f "$script_dir/completions/refsync.bash" ]]; then
            cp "$script_dir/completions/refsync.bash" "$COMPLETIONS_DIR_BASH/refsync"
            success "Bash completions installed to $COMPLETIONS_DIR_BASH"
        fi

        if [[ -f "$script_dir/completions/_refsync" ]]; then
            cp "$script_dir/completions/_refsync" "$COMPLETIONS_DIR_ZSH/_refsync"
            success "Zsh completions installed to $COMPLETIONS_DIR_ZSH"
        fi

        if [[ -f "$script_dir/completions/refsync.fish" ]]; then
            cp "$script_dir/completions/refsync.fish" "$COMPLETIONS_DIR_FISH/refsync.fish"
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
    echo "    source $COMPLETIONS_DIR_BASH/refsync"
    echo ""
    echo "  Zsh: Add $COMPLETIONS_DIR_ZSH to your fpath before compinit"
    echo ""
    echo "  Fish: Completions auto-loaded from $COMPLETIONS_DIR_FISH"
    echo ""
}

uninstall_refsync() {
    info "Uninstalling refsync..."

    if [[ -f "$BINDIR/refsync" ]]; then
        rm -f "$BINDIR/refsync"
        success "Removed $BINDIR/refsync"
    fi

    if [[ -d "$LIBDIR" ]]; then
        rm -rf "$LIBDIR"
        success "Removed $LIBDIR"
    fi

    if [[ -f "$COMPLETIONS_DIR_BASH/refsync" ]]; then
        rm -f "$COMPLETIONS_DIR_BASH/refsync"
        success "Removed bash completions"
    fi

    if [[ -f "$COMPLETIONS_DIR_ZSH/_refsync" ]]; then
        rm -f "$COMPLETIONS_DIR_ZSH/_refsync"
        success "Removed zsh completions"
    fi

    if [[ -f "$COMPLETIONS_DIR_FISH/refsync.fish" ]]; then
        rm -f "$COMPLETIONS_DIR_FISH/refsync.fish"
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
            LIBDIR="$PREFIX/share/refsync"
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
    uninstall_refsync
else
    install_refsync
fi
