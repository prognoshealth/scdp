#!/bin/bash
set -euo pipefail

# =============================================================================
# setup.sh — Supply Chain Attack Protection Toolkit
# Usage: bash setup.sh [--no-shim]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_SHIM=false

for arg in "$@"; do
    case "$arg" in
        --no-shim) SKIP_SHIM=true ;;
        --help|-h)
            echo "Usage: bash setup.sh [--no-shim]"
            echo ""
            echo "  --no-shim   Skip sfw malware scanner installation"
            echo ""
            echo "This script configures supply chain protections for your"
            echo "package managers. It modifies config files and shell RC files."
            echo "All changes are backed up before modification."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: bash setup.sh [--no-shim]"
            exit 1
            ;;
    esac
done

BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}=== Supply Chain Attack Protection Toolkit ===${NC}"
echo ""
echo "This script will:"
echo "  1. Configure release-age gating (7-day delay) on your package managers"
echo "  2. Set up pip age-gating shell wrapper"
if [[ "$SKIP_SHIM" == "false" ]]; then
    echo "  3. Install sfw (Socket Firewall) for malware scanning"
    echo "  4. Add shell wrappers to route package managers through sfw"
fi
echo ""
echo "All config files are backed up before modification."
echo ""

# --- Step 1: Age gating configs ---
echo -e "${BOLD}━━━ Step 1: Package Manager Age Gating ━━━${NC}"
bash "$SCRIPT_DIR/setup-age-gating.sh"

# --- Step 2: pip wrapper ---
echo ""
echo -e "${BOLD}━━━ Step 2: pip Age Gating Wrapper ━━━${NC}"
bash "$SCRIPT_DIR/setup-pip.sh"

# --- Step 3 & 4: sfw + shims ---
if [[ "$SKIP_SHIM" == "false" ]]; then
    echo ""
    echo -e "${BOLD}━━━ Step 3: Install sfw ━━━${NC}"
    bash "$SCRIPT_DIR/install-sfw.sh"

    echo ""
    echo -e "${BOLD}━━━ Step 4: sfw Shell Wrappers ━━━${NC}"
    bash "$SCRIPT_DIR/setup-shim.sh"
else
    echo ""
    echo -e "${BOLD}━━━ Step 3-4: sfw (skipped via --no-shim) ━━━${NC}"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                    Setup Complete                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal, or source your shell config:"
[[ -f "$HOME/.zshrc" ]]        && echo "     source ~/.zshrc"
[[ -f "$HOME/.bashrc" ]]       && echo "     source ~/.bashrc"
[[ -f "$HOME/.bash_profile" ]] && echo "     source ~/.bash_profile"
echo ""
echo "To revert: restore .bak files and remove sca-pip-age-gating/sca-shim blocks from shell RC files"
echo ""
