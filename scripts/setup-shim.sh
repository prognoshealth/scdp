#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-shim.sh — Add shell wrappers to route package managers through sfw
# Requires: sfw installed (run install-sfw.sh first)
# Target: macOS (zsh/bash)
# =============================================================================

# --- Load version managers so we see the same tools the user does ---
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

if command -v pyenv &>/dev/null; then
    eval "$(pyenv init --path 2>/dev/null)" || true
    eval "$(pyenv init - 2>/dev/null)" || true
fi

SHIM_START="# >>> sca-shim >>>"
SHIM_END="# <<< sca-shim <<<"

# --- Detect all shell RC files that exist ---
detect_shell_rcs() {
    local rcs=()
    [[ -f "$HOME/.zshrc" ]]        && rcs+=("$HOME/.zshrc")
    [[ -f "$HOME/.bashrc" ]]       && rcs+=("$HOME/.bashrc")
    [[ -f "$HOME/.bash_profile" ]] && rcs+=("$HOME/.bash_profile")

    if [[ ${#rcs[@]} -eq 0 ]]; then
        local user_shell
        user_shell="$(basename "${SHELL:-/bin/zsh}")"
        case "$user_shell" in
            zsh)  rcs+=("$HOME/.zshrc") ;;
            bash) rcs+=("$HOME/.bashrc") ;;
            *)    rcs+=("$HOME/.profile") ;;
        esac
    fi

    echo "${rcs[@]}"
}

read -ra SHELL_RCS <<< "$(detect_shell_rcs)"

# --- Colors & Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_done()  { echo -e "${GREEN}[DONE]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Helpers ---

remove_sentinel_block() {
    local file="$1" start="$2" end="$3"
    if [[ -f "$file" ]] && grep -q "$start" "$file"; then
        sed -i '' "/$start/,/$end/d" "$file"
    fi
}

# =============================================================================
# Check sfw is installed
# =============================================================================

check_sfw() {
    echo ""
    if command -v sfw &>/dev/null; then
        log_done "sfw found: $(command -v sfw)"
    else
        log_error "sfw is not installed. Run install-sfw.sh first."
        exit 1
    fi
}

# =============================================================================
# Generate and install shim functions
# =============================================================================

generate_shim_block() {
    local install_date
    install_date="$(date +%Y-%m-%d)"

    local block=""
    block+="\n"
    block+="${SHIM_START}\n"
    block+="# Supply Chain Protection — sfw malware scanning aliases\n"
    block+="#\n"
    block+="# These aliases route package manager commands through Socket Firewall (sfw),\n"
    block+="# which scans packages against Socket.dev's malware database before installation.\n"
    block+="# sfw acts as an ephemeral HTTP proxy — no packages touch disk until cleared.\n"
    block+="#\n"
    block+="# Installed by: setup-shim.sh\n"
    block+="# Date: ${install_date}\n"
    block+="# To remove: delete this block or run the revert instructions in README.md\n"
    block+="#\n"

    if command -v npm &>/dev/null; then
        block+='alias npm="sfw npm"\n'
    fi
    if command -v npx &>/dev/null; then
        block+='alias npx="sfw npx"\n'
    fi
    if command -v yarn &>/dev/null; then
        block+='alias yarn="sfw yarn"\n'
    fi
    if command -v pnpm &>/dev/null; then
        block+='alias pnpm="sfw pnpm"\n'
    fi
    if command -v uv &>/dev/null; then
        block+='alias uv="sfw uv"\n'
    fi

    # pip/pip3 — handled by setup-pip.sh (auto-detects sfw on PATH)

    block+="${SHIM_END}"
    echo -e "$block"
}

install_shim() {
    echo ""
    log_info "Installing shell function shims into: ${SHELL_RCS[*]}"

    # Generate the block once (same for all shells)
    local shim_block
    shim_block="$(generate_shim_block)"

    for rc in "${SHELL_RCS[@]}"; do
        [[ -f "$rc" ]] || touch "$rc"

        if [[ -L "$rc" ]]; then
            log_warn "$rc is a symlink — cannot modify automatically."
            log_warn "Add the following to $(readlink "$rc") manually:"
            echo ""
            echo "$shim_block"
            echo ""
            continue
        fi

        cp "$rc" "${rc}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up $rc"

        # Remove old shim block if present
        remove_sentinel_block "$rc" "$SHIM_START" "$SHIM_END"

        echo "" >> "$rc"
        echo "$shim_block" >> "$rc"

        log_done "Shims installed in $rc"
    done
}

# =============================================================================
# Advisories for unsupported ecosystems
# =============================================================================

print_advisories() {
    echo ""

    if command -v go &>/dev/null; then
        log_warn "${BOLD}Go${NC}: sfw free tier does not cover Go modules."
        log_warn "  Consider using Socket's paid tier or manually reviewing new dependencies."
    fi

    if command -v sbt &>/dev/null; then
        log_warn "${BOLD}sbt/Scala${NC}: sfw free tier does not cover Scala/JVM packages."
        log_warn "  Consider using Socket's paid tier or Sonatype OSS Index."
    fi

    if command -v cargo &>/dev/null; then
        log_info "${BOLD}Rust/Cargo${NC}: sfw supports cargo — it will be wrapped automatically."
    fi
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Supply Chain Protection — sfw Malware Scanner Shim     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Adds shell wrappers so that npm, yarn, pnpm, and uv are"
echo "automatically routed through sfw for malware scanning."

check_sfw
install_shim
print_advisories

echo ""
echo -e "${GREEN}${BOLD}Shim installation complete.${NC}"
echo -e "Run ${BOLD}source ${SHELL_RCS[0]}${NC} to activate in this terminal."
echo ""
