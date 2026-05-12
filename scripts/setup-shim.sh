#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-shim.sh — Install the scdp sfw malware-scanning wrappers
# Requires: sfw installed (run install-sfw.sh first)
#
# Copies wrappers/sfw.sh and wrappers/init.sh to ~/.config/scdp/ and ensures
# the scdp one-line loader (marker: "# scdp loader") is present in each
# detected shell RC file. The loader sources ~/.config/scdp/init.sh, which
# in turn sources sfw.sh (and pip.sh if installed) on shell startup.
# =============================================================================

# Load version managers so we see the same tools the user does
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

if command -v fnm &>/dev/null; then
    eval "$(fnm env)" 2>/dev/null || true
fi

if command -v pyenv &>/dev/null; then
    eval "$(pyenv init --path 2>/dev/null)" || true
    eval "$(pyenv init - 2>/dev/null)" || true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER_SRC="$REPO_ROOT/wrappers/sfw.sh"
INIT_SRC="$REPO_ROOT/wrappers/init.sh"
SCDP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/scdp"
WRAPPER_DEST="$SCDP_DIR/sfw.sh"
INIT_DEST="$SCDP_DIR/init.sh"

LOADER_MARKER="# scdp loader"
PREV_LOADER_SENTINEL="# >>> scdp >>>"        # block-style loader from earlier prerelease
OLD_SHIM_SENTINEL="# >>> sca-shim >>>"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_done()  { echo -e "${GREEN}[DONE]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Returns true if the file references ~/.bashrc in a non-comment line —
# a best-effort check for the conventional `.bash_profile → .bashrc` chain.
bash_profile_chains_bashrc() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    grep -v '^[[:space:]]*#' "$file" | grep -q '\.bashrc'
}

detect_shell_rcs() {
    local rcs=()
    [[ -f "$HOME/.zshrc" ]] && rcs+=("$HOME/.zshrc")

    local has_bashrc=false has_bash_profile=false
    [[ -f "$HOME/.bashrc" ]]       && has_bashrc=true
    [[ -f "$HOME/.bash_profile" ]] && has_bash_profile=true

    if $has_bashrc && $has_bash_profile; then
        # If .bash_profile sources .bashrc (the common chain), write to .bashrc only;
        # login shells pick it up via the chain. Otherwise both are independent —
        # write to each so coverage holds.
        if bash_profile_chains_bashrc "$HOME/.bash_profile"; then
            rcs+=("$HOME/.bashrc")
        else
            rcs+=("$HOME/.bashrc" "$HOME/.bash_profile")
        fi
    elif $has_bashrc; then
        rcs+=("$HOME/.bashrc")
    elif $has_bash_profile; then
        rcs+=("$HOME/.bash_profile")
    fi

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

loader_line() {
    printf '[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/scdp/init.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/scdp/init.sh"  %s\n' "$LOADER_MARKER"
}

ensure_loader() {
    local rc="$1"
    [[ -f "$rc" ]] || touch "$rc"

    if [[ -L "$rc" ]]; then
        log_warn "$rc is a symlink — cannot modify automatically."
        log_warn "Add this line to $(readlink "$rc") manually:"
        echo ""
        loader_line
        echo ""
        return
    fi

    if grep -qF "$LOADER_MARKER" "$rc"; then
        log_info "Loader already present in $rc — skipping."
        return
    fi

    cp "$rc" "${rc}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backed up $rc"

    printf '\n' >> "$rc"
    loader_line >> "$rc"
    log_done "Loader installed in $rc"
}

warn_old_block() {
    local rc="$1"
    [[ -f "$rc" ]] || return
    if grep -qF "$OLD_SHIM_SENTINEL" "$rc"; then
        log_warn "$rc still has an old '# >>> sca-shim >>>' block."
        log_warn "  The new loader runs after it (last def wins) but please clean up:"
        log_warn "    sed -i '' '/# >>> sca-shim >>>/,/# <<< sca-shim <<</d' '$rc'"
    fi
    if grep -qF "$PREV_LOADER_SENTINEL" "$rc"; then
        log_warn "$rc has an intermediate '# >>> scdp >>>' loop loader (pre-1-liner)."
        log_warn "  The new one-line loader runs after it; please clean up:"
        log_warn "    sed -i '' '/# >>> scdp >>>/,/# <<< scdp <<</d' '$rc'"
    fi
}

print_advisories() {
    echo ""

    if command -v go &>/dev/null; then
        log_warn "${BOLD}Go${NC}: sfw free tier does not cover Go modules."
        log_warn "  Consider Socket's paid tier or manually review new dependencies."
    fi

    if command -v sbt &>/dev/null; then
        log_warn "${BOLD}sbt/Scala${NC}: sfw free tier does not cover Scala/JVM packages."
        log_warn "  Consider Socket's paid tier or Sonatype OSS Index."
    fi

    if command -v cargo &>/dev/null; then
        log_info "${BOLD}Rust/Cargo${NC}: sfw supports cargo — it will be wrapped automatically."
    fi
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Supply Chain Protection - sfw Malware Scanner Shim      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Installs ~/.config/scdp/sfw.sh which aliases npm, npx, yarn, pnpm,"
echo "and uv to route through sfw for malware scanning. Aliases are only"
echo "defined for tools that are installed at shell startup."
echo ""

for f in "$WRAPPER_SRC" "$INIT_SRC"; do
    if [[ ! -f "$f" ]]; then
        log_error "Missing $f — repo layout looks wrong."
        exit 1
    fi
done

if command -v sfw &>/dev/null; then
    log_done "sfw found: $(command -v sfw)"
else
    log_error "sfw is not installed. Run install-sfw.sh first."
    exit 1
fi

mkdir -p "$SCDP_DIR"
cp "$INIT_SRC" "$INIT_DEST"
cp "$WRAPPER_SRC" "$WRAPPER_DEST"
log_done "Installed $INIT_DEST"
log_done "Installed $WRAPPER_DEST"

echo ""
for rc in "${SHELL_RCS[@]}"; do
    warn_old_block "$rc"
    ensure_loader "$rc"
done

print_advisories

echo ""
echo -e "${GREEN}${BOLD}Shim installation complete.${NC}"
echo -e "Run ${BOLD}source ${SHELL_RCS[0]}${NC} to activate in this terminal."
echo ""
