#!/bin/bash


set -euo pipefail
trap 'cleanup' EXIT

# ----------------------------------------------------------------------
# Global variables
METHOD=""                     # user‑requested method (snap|flatpak|aur)
VERSION="latest"              # version to install (default latest)
DRY_RUN=false
TEMP_DIR=""
SCRIPT_NAME="$(basename "$0")"

# ----------------------------------------------------------------------
# Helper functions
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  --method snap|flatpak|aur|tarball   Force a specific installation method
  --version VERSION                    Specify version (e.g., 4.3)
  --dry-run                             Show actions without executing
  --help                                Show this help message
EOF
    exit 0
}

error() {
    echo "Error: $*" >&2
    exit 1
}

confirm() {
    # Prompt user for yes/no, default yes
    local prompt="$1"
    local response
    read -r -p "$prompt [Y/n] " response
    case "$response" in
        [nN][oO]|[nN]) return 1 ;;
        *) return 0 ;;
    esac
}

run() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# ----------------------------------------------------------------------
# Installation method functions

install_snap() {
    echo "Installing Processing via Snap..."
    if confirm "This will run 'sudo snap install processing --classic'. Continue?"; then
        run sudo snap install processing --classic
        echo "Snap installation complete."
    else
        echo "Aborted."
    fi
}

install_flatpak() {
    echo "Installing Processing via Flatpak..."
    if confirm "This will run 'flatpak install flathub org.processing.processingide'. Continue?"; then
        run flatpak install flathub org.processing.processingide
        echo "Flatpak installation complete."
    else
        echo "Aborted."
    fi
}

install_aur() {
    echo "Installing Processing from AUR..."

    local helper=""
    if command_exists "yay"; then
        helper="yay"
    elif command_exists "paru"; then
        helper="paru"
    fi

    if [ -n "$helper" ]; then
        if confirm "This will run '$helper -S processing'. Continue?"; then
            run "$helper" -S processing
            echo "AUR installation complete."
        else
            echo "Aborted."
        fi
    else
        # This case should not be reached because we only call install_aur after detection
        echo "No AUR helper found. Install manually from AUR:"
        echo "  git clone https://aur.archlinux.org/processing.git"
        echo "  cd processing && makepkg -si"
    fi
}

install_tarball() {
    echo "Installing Processing via direct download..."
    # STUB – for now just inform user.
    echo "This feature is coming soon! For now, you can manually download from:"
    echo "  https://processing.org/download/"
}

# ----------------------------------------------------------------------
# Distribution detection helpers

is_arch_based() {
    # Check for typical Arch indicators
    [ -f /etc/arch-release ] && return 0
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            arch|manjaro|endeavouros) return 0 ;;
        esac
    fi
    return 1
}

has_flathub() {
    # Check if flatpak is installed and flathub remote is present
    command_exists flatpak || return 1
    flatpak remote-list 2>/dev/null | grep -q flathub
}

# ----------------------------------------------------------------------
# Main

# Create temporary directory
TEMP_DIR="$(mktemp -d)"

# Parse command‑line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --method)
            if [ -z "$2" ]; then
                error "--method requires an argument"
            fi
            METHOD="$2"
            shift 2
            ;;
        --version)
            if [ -z "$2" ]; then
                error "--version requires an argument"
            fi
            VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# If override method is provided, use it directly
if [ -n "$METHOD" ]; then
    case "$METHOD" in
        snap)     install_snap ;;
        flatpak)  install_flatpak ;;
        aur)      install_aur ;;
        tarball)  install_tarball ;;
        *)        error "Invalid method: $METHOD. Use snap, flatpak, aur, or tarball." ;;
    esac
    exit 0
fi

# Auto‑detection
echo "Detecting best installation method for your system..."


if command_exists snap; then
    echo "Snap is available (official package)."
    if confirm "Install Processing via Snap?"; then
        install_snap
        exit 0
    fi
fi


if has_flathub; then
    echo "Flatpak (Flathub) is available."
    if confirm "Install Processing via Flatpak?"; then
        install_flatpak
        exit 0
    fi
fi


if is_arch_based; then
    echo "Arch‑based distribution detected."
    if command_exists yay || command_exists paru; then
        if confirm "Install Processing from AUR?"; then
            install_aur
            exit 0
        fi
    else
        echo "No AUR helper found. You can install manually from AUR:"
        echo "  git clone https://aur.archlinux.org/processing.git"
        echo "  cd processing && makepkg -si"
        exit 0
    fi
fi

# Fallback: tarball
echo "No suitable package manager found. Falling back to direct download."
install_tarball
exit 0
