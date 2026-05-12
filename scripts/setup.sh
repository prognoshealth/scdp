#!/bin/bash
set -euo pipefail

# =============================================================================
# setup.sh — Supply Chain Attack Protection Toolkit
# Usage: ./setup.sh [--no-shim]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_SHIM=false
export SCDP_IN_SETUP=1   # signals to sub-scripts that they're running as part of the chain

for arg in "$@"; do
    case "$arg" in
        --no-shim) SKIP_SHIM=true ;;
        --help|-h)
            echo "Usage: ./setup.sh [--no-shim]"
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
            echo "Usage: ./setup.sh [--no-shim]"
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
echo "  1. Configure release-age gating (7-day delay) and disable lifecycle"
echo "     install scripts in your Node package managers (npm, pnpm, yarn, bun)"
echo "  2. Install the pip age-gating wrapper to ~/.config/scdp/pip.sh"
if [[ "$SKIP_SHIM" == "false" ]]; then
    echo "  3. Install sfw (Socket Firewall) for malware scanning"
    echo "  4. Install the sfw shim wrapper to ~/.config/scdp/sfw.sh"
fi
echo ""
echo "Existing package-manager config files are backed up before modification."
echo "A one-line loader is added to your shell RC files (one-time)."
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
    echo -e "${BOLD}━━━ Steps 3 & 4 skipped (--no-shim) ━━━${NC}"
    echo "Age gating is configured, but sfw malware scanning was not installed."
    echo "To add sfw later: ./scripts/install-sfw.sh && ./scripts/setup-shim.sh"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                     Setup Complete                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  Restart your terminal, or source the RC file(s) that received the loader:"
loader_in=()
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [[ -f "$rc" ]] && grep -qF "# scdp loader" "$rc" && loader_in+=("$rc")
done
if [[ ${#loader_in[@]} -gt 0 ]]; then
    for rc in "${loader_in[@]}"; do
        echo "     source ${rc/#$HOME/~}"
    done
else
    echo "     (none — open a new terminal)"
fi
echo ""
echo "To revert:"
echo "  - restore .bak files for any package-manager configs you want reverted"
echo "  - rm -rf ~/.config/scdp/"
echo "  - sed -i '' '/# scdp loader\$/d' ~/.zshrc   # repeat for ~/.bashrc, ~/.bash_profile as needed"
echo ""
