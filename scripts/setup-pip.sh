#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-pip.sh — Install the scdp pip / pip3 age-gating wrapper
#
# Copies wrappers/pip.sh and wrappers/init.sh to ~/.config/scdp/ and ensures
# the scdp one-line loader (marker: "# scdp loader") is present in each
# detected shell RC file. The loader sources ~/.config/scdp/init.sh, which
# in turn sources pip.sh (and sfw.sh if installed) on shell startup.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER_SRC="$REPO_ROOT/wrappers/pip.sh"
INIT_SRC="$REPO_ROOT/wrappers/init.sh"
SCDP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/scdp"
WRAPPER_DEST="$SCDP_DIR/pip.sh"
INIT_DEST="$SCDP_DIR/init.sh"

LOADER_MARKER="# scdp loader"
PREV_LOADER_SENTINEL="# >>> scdp >>>"        # block-style loader from earlier prerelease
OLD_PIP_SENTINEL="# >>> sca-pip-age-gating >>>"

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
    if grep -qF "$OLD_PIP_SENTINEL" "$rc"; then
        log_warn "$rc still has an old '# >>> sca-pip-age-gating >>>' block."
        log_warn "  The new loader runs after it (last def wins) but please clean up:"
        log_warn "    sed -i '' '/# >>> sca-pip-age-gating >>>/,/# <<< sca-pip-age-gating <<</d' '$rc'"
    fi
    if grep -qF "$PREV_LOADER_SENTINEL" "$rc"; then
        log_warn "$rc has an intermediate '# >>> scdp >>>' loop loader (pre-1-liner)."
        log_warn "  The new one-line loader runs after it; please clean up:"
        log_warn "    sed -i '' '/# >>> scdp >>>/,/# <<< scdp <<</d' '$rc'"
    fi
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Supply Chain Protection - pip Age Gating                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Installs ~/.config/scdp/pip.sh which adds a 7-day minimum release age"
echo "to pip install / pip download. If sfw (Socket Firewall) is on PATH at"
echo "shell startup, the wrappers also route pip through sfw."
echo ""

for f in "$WRAPPER_SRC" "$INIT_SRC"; do
    if [[ ! -f "$f" ]]; then
        log_error "Missing $f — repo layout looks wrong."
        exit 1
    fi
done

# Advisory version check — wrapper itself works either way, but
# --uploaded-prior-to support requires pip >= 26.0.
if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
    pip_cmd="$(command -v pip3 2>/dev/null || command -v pip)"
    version="$($pip_cmd --version 2>/dev/null | awk '{print $2}')"

    version_gte() {
        local IFS='.'
        local -a v1=($1) v2=($2)
        for i in 0 1 2; do
            local a=${v1[$i]:-0}
            local b=${v2[$i]:-0}
            if (( a > b )); then return 0; fi
            if (( a < b )); then return 1; fi
        done
        return 0
    }

    if ! version_gte "$version" "26.0.0"; then
        log_error "██ pip $version is OUTDATED — --uploaded-prior-to requires >= 26.0.0 ██"
        log_error "██ Run: pip install --upgrade pip                                     ██"
        echo ""
    fi
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

echo ""
if command -v sfw &>/dev/null; then
    log_info "sfw detected — pip will also be scanned for malware."
else
    log_info "sfw not detected — only age gating is active."
    log_info "Run install-sfw.sh + setup-shim.sh to add malware scanning."
fi

echo ""
echo -e "${GREEN}${BOLD}pip age-gating installed.${NC}"
echo -e "Run ${BOLD}source ${SHELL_RCS[0]}${NC} to activate in this terminal."
echo ""
