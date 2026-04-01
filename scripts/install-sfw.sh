#!/bin/bash
set -euo pipefail

# =============================================================================
# install-sfw.sh — Install Socket Firewall Free (sfw)
#
# sfw is a command-line tool that spins up an ephemeral HTTP proxy to scan
# packages against Socket.dev's malware database before installation.
#
# Tries npm first, falls back to downloading the binary from GitHub releases.
# After installing sfw, run setup-shim.sh to wrap your package managers.
# =============================================================================

# --- Load nvm so we can find npm ---
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

# --- Colors & Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_done()  { echo -e "${GREEN}[DONE]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# =============================================================================
# Install methods
# =============================================================================

install_via_npm() {
    if ! command -v npm &>/dev/null; then
        log_warn "npm not found — skipping npm install method."
        return 1
    fi

    log_info "Installing sfw globally via npm..."
    if npm i -g sfw --min-release-age=0 2>&1; then
        if command -v sfw &>/dev/null; then
            return 0
        fi
    fi

    log_warn "npm install failed — trying binary download instead."
    return 1
}

install_via_binary() {
    log_info "Downloading sfw binary from GitHub releases..."

    local arch
    arch="$(uname -m)"
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    local binary_name=""
    case "${os}-${arch}" in
        darwin-arm64)  binary_name="sfw-darwin-arm64" ;;
        darwin-x86_64) binary_name="sfw-darwin-x86_64" ;;
        linux-x86_64)  binary_name="sfw-linux-x86_64" ;;
        linux-aarch64) binary_name="sfw-linux-arm64" ;;
        *)
            log_error "Unsupported platform: ${os}-${arch}"
            return 1
            ;;
    esac

    local download_url="https://github.com/SocketDev/sfw-free/releases/latest/download/${binary_name}"
    local install_dir="/usr/local/bin"

    if [[ ! -w "$install_dir" ]]; then
        log_warn "/usr/local/bin is not writable — will use sudo."
    fi

    local tmpfile
    tmpfile="$(mktemp)"
    if curl -fsSL "$download_url" -o "$tmpfile"; then
        chmod +x "$tmpfile"
        if [[ -w "$install_dir" ]]; then
            mv "$tmpfile" "$install_dir/sfw"
        else
            sudo mv "$tmpfile" "$install_dir/sfw"
        fi

        if command -v sfw &>/dev/null; then
            return 0
        fi
    fi

    rm -f "$tmpfile"
    log_error "Binary download failed."
    return 1
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Install sfw (Socket Firewall Free)                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if command -v sfw &>/dev/null; then
    log_done "sfw is already installed: $(command -v sfw)"
    echo ""
    echo "To update:  npm update -g sfw"
    echo ""
    exit 0
fi

if install_via_npm || install_via_binary; then
    log_done "sfw installed successfully: $(command -v sfw)"
    echo ""
    echo "Next steps:"
    echo "  bash $SCRIPT_DIR/setup-shim.sh    # wrap npm, yarn, pnpm, uv with sfw"
    echo "  bash $SCRIPT_DIR/setup-pip.sh     # wrap pip with age-gating + sfw"
    echo ""
else
    log_error "Could not install sfw via npm or binary download."
    log_error "Install manually from: https://github.com/SocketDev/sfw-free/releases"
    exit 1
fi
