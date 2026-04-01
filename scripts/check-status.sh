#!/bin/bash
set -euo pipefail

# =============================================================================
# check-status.sh — Show current supply chain protection status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()      { echo -e "  ${GREEN}✓${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail()    { echo -e "  ${RED}✗${NC} $*"; }
dim()     { echo -e "  ${DIM}$*${NC}"; }
upgrade() { echo -e "    ${YELLOW}→ $*${NC}"; }

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

ini_value() {
    local file="$1" key="$2"
    if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
        grep "^${key}=" "$file" | head -1 | cut -d'=' -f2-
    fi
}

yaml_value() {
    local file="$1" key="$2"
    if [[ -f "$file" ]] && grep -q "^${key}:" "$file"; then
        grep "^${key}:" "$file" | head -1 | sed "s/^${key}:[[:space:]]*//"
    fi
}

toml_value() {
    local file="$1" key="$2"
    if [[ -f "$file" ]] && grep -qE "^${key}[[:space:]]*=" "$file"; then
        grep -E "^${key}[[:space:]]*=" "$file" | head -1 | sed 's/^[^=]*=[[:space:]]*//'
    fi
}

resolve_system_bin() {
    local name="$1"
    for dir in /usr/local/bin /usr/bin /opt/homebrew/bin; do
        if [[ -x "$dir/$name" ]]; then
            echo "$dir/$name"
            return
        fi
    done
}

# =============================================================================
# Version manager detection
# =============================================================================

HAS_NVM=false
HAS_PYENV=false

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh" 2>/dev/null
    HAS_NVM=true
fi

if [[ -d "$HOME/.pyenv" ]]; then
    eval "$(~/.pyenv/bin/pyenv init --path 2>/dev/null)" || true
    eval "$(~/.pyenv/bin/pyenv init - 2>/dev/null)" || true
    HAS_PYENV=true
fi

# =============================================================================

echo ""
echo -e "${BOLD}Supply Chain Protection — Status${NC}"

# =============================================================================
# SECTION 1: Age Gating
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RELEASE AGE GATING${NC}"
echo -e "${BOLD}  Delays installation of newly published packages${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"

# --- npm ---
echo ""
echo -e "${BOLD}npm${NC} ${DIM}(config: ~/.npmrc → min-release-age)${NC}"

if [[ "$HAS_NVM" == "true" ]]; then
    nvm_node="$(nvm current 2>/dev/null || echo "none")"
    if [[ "$nvm_node" != "none" && "$nvm_node" != "system" ]]; then
        nvm_npm="$(npm --version 2>/dev/null)"
        if version_gte "$nvm_npm" "11.10.0"; then
            ok "nvm ($nvm_node): npm v${nvm_npm} — supports age gating"
        else
            warn "nvm ($nvm_node): npm v${nvm_npm} — ${RED}needs >= 11.10.0${NC}"
            upgrade "npm install -g npm@latest"
        fi
    fi
fi

sys_npm="$(resolve_system_bin npm)"
if [[ -n "$sys_npm" ]]; then
    sys_npm_ver="$($sys_npm --version 2>/dev/null)"
    if [[ "$sys_npm" == /usr/bin/* ]]; then
        dim "system ($sys_npm): v${sys_npm_ver} — managed by OS, cannot upgrade"
    elif version_gte "$sys_npm_ver" "11.10.0"; then
        ok "system ($sys_npm): v${sys_npm_ver} — supports age gating"
    else
        warn "system ($sys_npm): v${sys_npm_ver} — ${RED}needs >= 11.10.0${NC}"
        upgrade "brew upgrade node   # or: $sys_npm install -g npm@latest"
    fi
elif [[ "$HAS_NVM" != "true" ]] || [[ "$(nvm current 2>/dev/null)" == "none" ]]; then
    dim "Not installed"
fi

val="$(ini_value "$HOME/.npmrc" "min-release-age")"
if [[ -n "$val" ]]; then
    ok "Config: min-release-age=${val}"
else
    fail "Config: min-release-age not set"
    upgrade "bash $SCRIPT_DIR/setup-age-gating.sh"
fi

# --- pnpm ---
echo ""
# pnpm global config: $XDG_CONFIG_HOME/pnpm/rc if set, else OS default
if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    PNPM_RC="$XDG_CONFIG_HOME/pnpm/rc"
elif [[ "$(uname -s)" == "Darwin" ]]; then
    PNPM_RC="$HOME/Library/Preferences/pnpm/rc"
else
    PNPM_RC="$HOME/.config/pnpm/rc"
fi
echo -e "${BOLD}pnpm${NC} ${DIM}(config: $PNPM_RC → minimum-release-age)${NC}"
if command -v pnpm &>/dev/null; then
    version="$(pnpm --version 2>/dev/null)"
    where="$(command -v pnpm)"
    if version_gte "$version" "10.16.0"; then
        ok "Installed: v${version} ($where) — supports age gating"
    else
        warn "Installed: v${version} ($where) — ${RED}needs >= 10.16.0${NC}"
        upgrade "npm install -g pnpm@latest"
    fi
else
    dim "Not installed"
fi
val="$(ini_value "$PNPM_RC" "minimum-release-age")"
if [[ -n "$val" ]]; then
    ok "Config: minimum-release-age=${val}"
else
    fail "Config: minimum-release-age not set"
    upgrade "bash $SCRIPT_DIR/setup-age-gating.sh"
fi

# --- yarn ---
echo ""
echo -e "${BOLD}yarn${NC} ${DIM}(config: ~/.yarnrc.yml → npmMinimalAgeGate)${NC}"
if command -v yarn &>/dev/null; then
    version="$(yarn --version 2>/dev/null)"
    where="$(command -v yarn)"
    if version_gte "$version" "4.10.0"; then
        ok "Installed: v${version} ($where) — supports age gating"
    else
        warn "Installed: v${version} ($where) — ${RED}needs >= 4.10.0${NC}"
        upgrade "corepack prepare yarn@stable --activate"
    fi
else
    dim "Not installed"
fi
val="$(yaml_value "$HOME/.yarnrc.yml" "npmMinimalAgeGate")"
if [[ -n "$val" ]]; then
    ok "Config: npmMinimalAgeGate: ${val}"
else
    fail "Config: npmMinimalAgeGate not set"
    upgrade "bash $SCRIPT_DIR/setup-age-gating.sh"
fi

# --- bun ---
echo ""
echo -e "${BOLD}bun${NC} ${DIM}(config: ~/bunfig.toml → minimumReleaseAge)${NC}"
if command -v bun &>/dev/null; then
    version="$(bun --version 2>/dev/null)"
    where="$(command -v bun)"
    if version_gte "$version" "1.3.0"; then
        ok "Installed: v${version} ($where) — supports age gating"
    else
        warn "Installed: v${version} ($where) — ${RED}needs >= 1.3.0${NC}"
        upgrade "bun upgrade"
    fi
else
    dim "Not installed"
fi
val="$(toml_value "$HOME/bunfig.toml" "minimumReleaseAge")"
if [[ -n "$val" ]]; then
    ok "Config: minimumReleaseAge = ${val}"
else
    fail "Config: minimumReleaseAge not set"
    upgrade "bash $SCRIPT_DIR/setup-age-gating.sh"
fi

# --- uv ---
echo ""
echo -e "${BOLD}uv${NC} ${DIM}(config: ~/.config/uv/uv.toml → exclude-newer)${NC}"
if command -v uv &>/dev/null; then
    version="$(uv --version 2>/dev/null | awk '{print $2}')"
    where="$(command -v uv)"
    ok "Installed: v${version} ($where) — supports age gating"
else
    dim "Not installed"
fi
val="$(toml_value "$HOME/.config/uv/uv.toml" "exclude-newer")"
if [[ -n "$val" ]]; then
    ok "Config: exclude-newer = ${val}"
else
    fail "Config: exclude-newer not set"
    upgrade "bash $SCRIPT_DIR/setup-age-gating.sh"
fi

# --- pip ---
echo ""
echo -e "${BOLD}pip${NC} ${DIM}(no config file — age-gating via shell wrapper only)${NC}"

if [[ "$HAS_PYENV" == "true" ]]; then
    pyenv_ver="$(pyenv version-name 2>/dev/null || echo "system")"
    if [[ "$pyenv_ver" != "system" ]]; then
        pyenv_pip="$(pyenv exec pip3 --version 2>/dev/null | awk '{print $2}' || echo "")"
        if [[ -n "$pyenv_pip" ]]; then
            pyenv_python="$(pyenv exec python3 --version 2>/dev/null | awk '{print $2}')"
            if version_gte "$pyenv_pip" "26.0.0"; then
                ok "pyenv (Python ${pyenv_python}): pip v${pyenv_pip} — supports --uploaded-prior-to"
            else
                warn "pyenv (Python ${pyenv_python}): pip v${pyenv_pip} — ${RED}needs >= 26.0.0${NC}"
                upgrade "pyenv exec pip install --upgrade pip"
                if ! version_gte "$pyenv_python" "3.12.0"; then
                    upgrade "Consider: pyenv install 3.12.8 && pyenv global 3.12.8"
                fi
            fi
        fi
    fi
fi

sys_pip="$(resolve_system_bin pip3)"
[[ -z "$sys_pip" ]] && sys_pip="$(resolve_system_bin pip)"
if [[ -n "$sys_pip" ]]; then
    sys_pip_ver="$($sys_pip --version 2>/dev/null | awk '{print $2}')"
    sys_python_ver="$($sys_pip --version 2>/dev/null | sed 's/.*python //' | tr -d ')')"
    if [[ "$sys_pip" == /usr/bin/* ]]; then
        # macOS system Python (Xcode CLT) — not user-upgradeable
        dim "system ($sys_pip, Python ${sys_python_ver}): pip v${sys_pip_ver} — managed by macOS, cannot upgrade"
    elif version_gte "$sys_pip_ver" "26.0.0"; then
        ok "system ($sys_pip, Python ${sys_python_ver}): pip v${sys_pip_ver} — supports --uploaded-prior-to"
    else
        warn "system ($sys_pip, Python ${sys_python_ver}): pip v${sys_pip_ver} — ${RED}needs >= 26.0.0${NC}"
        upgrade "$sys_pip install --upgrade pip"
    fi
elif [[ "$HAS_PYENV" != "true" ]]; then
    dim "Not installed"
fi

# Check if shell wrapper is handling pip age-gating
pip_shim_found=false
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && grep -q "uploaded-prior-to" "$rc"; then
        pip_shim_found=true
        break
    fi
done
if [[ "$pip_shim_found" == "true" ]]; then
    ok "Shell wrapper: pip age-gating active"
else
    warn "Shell wrapper: pip age-gating not active"
    upgrade "bash $SCRIPT_DIR/setup-pip.sh"
fi

# --- go ---
echo ""
echo -e "${BOLD}go${NC} ${DIM}(no age-gating support)${NC}"
if command -v go &>/dev/null; then
    version="$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')"
    where="$(command -v go)"
    dim "Installed: v${version} ($where) — no age-gating available"
else
    dim "Not installed"
fi

# --- sbt ---
echo ""
echo -e "${BOLD}sbt${NC} ${DIM}(no age-gating support)${NC}"
if command -v sbt &>/dev/null; then
    where="$(command -v sbt)"
    dim "Installed ($where) — no age-gating available"
else
    dim "Not installed"
fi

# =============================================================================
# SECTION 2: Malware Detection
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  MALWARE DETECTION${NC}"
echo -e "${BOLD}  Scans packages against Socket.dev's malware database${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"

# --- sfw binary ---
echo ""
echo -e "${BOLD}sfw (Socket Firewall Free)${NC}"
if command -v sfw &>/dev/null; then
    ok "Installed: $(command -v sfw)"
else
    fail "Not installed"
    upgrade "bash $SCRIPT_DIR/install-sfw.sh"
fi

# --- Shell wrappers per tool ---
echo ""
echo -e "${BOLD}Shell wrapper status${NC} ${DIM}(intercepts commands with sfw proxy)${NC}"

# Collect all wrapped functions across RC files
check_wrapper() {
    local tool="$1"
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        if [[ -f "$rc" ]]; then
            # Check for alias or function definition
            if grep -q "alias ${tool}=" "$rc" || grep -q "^${tool}()" "$rc"; then
                return 0
            fi
        fi
    done
    return 1
}

# sfw shim tools (setup-shim.sh)
for tool in npm npx yarn pnpm uv; do
    if check_wrapper "$tool"; then
        ok "${tool} — wrapped (sfw)"
    else
        if command -v "$tool" &>/dev/null; then
            fail "${tool} — not wrapped"
            upgrade "bash $SCRIPT_DIR/setup-shim.sh"
        else
            dim "${tool} — not installed"
        fi
    fi
done

# pip (setup-pip.sh — handles both age-gating and sfw)
if check_wrapper "pip" || check_wrapper "pip3"; then
    ok "pip — wrapped (age-gating + sfw if available)"
else
    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        fail "pip — not wrapped"
        upgrade "bash $SCRIPT_DIR/setup-pip.sh"
    else
        dim "pip — not installed"
    fi
fi

# Not supported by sfw
echo ""
echo -e "${BOLD}Not supported by sfw free tier${NC}"
if command -v bun &>/dev/null; then
    warn "bun — ${YELLOW}not supported by sfw (age-gating only via bunfig.toml)${NC}"
fi
if command -v go &>/dev/null; then
    warn "go — ${YELLOW}not supported${NC}"
fi
if command -v sbt &>/dev/null; then
    warn "sbt/Scala — ${YELLOW}not supported${NC}"
fi
if command -v cargo &>/dev/null; then
    ok "cargo (Rust) — supported by sfw but not shimmed"
fi

# --- AI agent disclaimer ---
echo ""
echo -e "${BOLD}Note: AI coding agents${NC}"
echo -e "  The shell wrappers above are aliases/functions in your RC files."
echo -e "  Some AI agents (e.g. Claude Code) source your shell profile and will"
echo -e "  pick them up automatically; others may not."
echo ""
echo -e "  If your agent doesn't load your shell profile, add this to your prompt:"
echo ""
echo -e "    ${DIM}When running package install commands, always prefix them with \`sfw\`${NC}"
echo -e "    ${DIM}to route through the Socket Firewall for malware scanning.${NC}"
echo -e "    ${DIM}For example, use \`sfw npm install <pkg>\` instead of \`npm install <pkg>\`.${NC}"
echo -e "    ${DIM}This applies to npm, npx, yarn, pnpm, uv, and pip.${NC}"

echo ""
