#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-pip.sh — Age-gate pip installs (7-day delay)
#
# Since pip has no config file for age gating, this adds shell functions
# that inject --uploaded-prior-to on every pip install/download.
#
# If sfw (Socket Firewall) is on PATH, it will be used automatically
# for malware scanning too. If not, age gating still works on its own.
# =============================================================================

DELAY_DAYS=7
SCA_START="# >>> sca-pip-age-gating >>>"
SCA_END="# <<< sca-pip-age-gating <<<"

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

# --- Detect all shell RC files ---
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

remove_sentinel_block() {
    local file="$1" start="$2" end="$3"
    if [[ -f "$file" ]] && grep -q "$start" "$file"; then
        sed -i '' "/$start/,/$end/d" "$file"
    fi
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Supply Chain Protection — pip Age Gating (${DELAY_DAYS}-day delay) ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Adds shell functions that enforce a ${DELAY_DAYS}-day minimum release age"
echo "on pip install and pip download commands."
echo ""
echo "If sfw (Socket Firewall) is on PATH, it will also be used for"
echo "malware scanning. The two protections compose automatically."
echo ""

# Version check
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

INSTALL_DATE="$(date +%Y-%m-%d)"

generate_pip_block() {
    cat <<EOF
# >>> sca-pip-age-gating >>>
# Supply Chain Protection — pip age gating + malware scanning
#
# Wraps pip/pip3 install and download commands with --uploaded-prior-to
# to enforce a 7-day minimum release age. If sfw (Socket Firewall) is
# on PATH, commands are also routed through sfw for malware scanning.
#
# Installed by: setup-pip.sh
# Date: ${INSTALL_DATE}
# To remove: delete this block or run the revert instructions in README.md
#
EOF
    cat << 'FUNCS'
_sca_pip_cutoff() {
    if date -v-1d +%s &>/dev/null; then
        date -v-7d -u +%Y-%m-%dT%H:%M:%SZ        # macOS (BSD date)
    else
        date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ  # Linux (GNU date)
    fi
}
_sca_pip_cmd() {
    if command -v sfw &>/dev/null; then
        command sfw "$@"
    else
        command "$@"
    fi
}
pip() {
    case "$1" in
        install|download)
            _sca_pip_cmd pip "$1" --uploaded-prior-to "$(_sca_pip_cutoff)" "${@:2}"
            ;;
        *) _sca_pip_cmd pip "$@" ;;
    esac
}
pip3() {
    case "$1" in
        install|download)
            _sca_pip_cmd pip3 "$1" --uploaded-prior-to "$(_sca_pip_cutoff)" "${@:2}"
            ;;
        *) _sca_pip_cmd pip3 "$@" ;;
    esac
}
# <<< sca-pip-age-gating <<<
FUNCS
}

PIP_BLOCK="$(generate_pip_block)"

for rc in "${SHELL_RCS[@]}"; do
    [[ -f "$rc" ]] || touch "$rc"

    if [[ -L "$rc" ]]; then
        log_warn "$rc is a symlink — cannot modify automatically."
        log_warn "Add the following to $(readlink "$rc") manually:"
        echo ""
        echo "$PIP_BLOCK"
        echo ""
        continue
    fi

    # Back up
    cp "$rc" "${rc}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backed up $rc"

    # Remove old block if present
    remove_sentinel_block "$rc" "$SCA_START" "$SCA_END"

    echo "" >> "$rc"
    echo "$PIP_BLOCK" >> "$rc"

    log_done "Installed pip/pip3 age-gating wrapper in $rc"
done

echo ""
if command -v sfw &>/dev/null; then
    log_info "sfw detected — pip commands will also be scanned for malware."
else
    log_info "sfw not detected — only age gating is active."
    log_info "Run setup-shim.sh to add malware scanning."
fi

echo ""
echo -e "${GREEN}${BOLD}pip age-gating installed.${NC}"
echo -e "Run ${BOLD}source ${SHELL_RCS[0]}${NC} to activate in this terminal."
echo ""
