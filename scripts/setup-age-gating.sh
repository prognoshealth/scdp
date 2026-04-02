#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-age-gating.sh — Configure release-age gating for package managers
# Target: macOS (zsh/bash)
# =============================================================================

# --- Load version managers so we see the same tools the user does ---
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

if command -v pyenv &>/dev/null; then
    eval "$(pyenv init --path 2>/dev/null)" || true
    eval "$(pyenv init - 2>/dev/null)" || true
fi

DELAY_DAYS=7
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

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

# Compare two semver strings: returns 0 if $1 >= $2
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

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}${BACKUP_SUFFIX}"
        log_info "Backed up $file → ${file}${BACKUP_SUFFIX}"
    fi
}

ensure_dir() {
    local dir
    dir="$(dirname "$1")"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# Set a key=value in an ini-style config file (like .npmrc)
set_ini_value() {
    local file="$1" key="$2" value="$3"
    ensure_dir "$file"
    if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
        sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
        log_done "Updated $key=$value in $file"
    else
        echo "${key}=${value}" >> "$file"
        log_done "Added $key=$value to $file"
    fi
}

# Set a top-level key in a YAML file
set_yaml_value() {
    local file="$1" key="$2" value="$3"
    ensure_dir "$file"
    if [[ -f "$file" ]] && grep -q "^${key}:" "$file"; then
        sed -i '' "s|^${key}:.*|${key}: ${value}|" "$file"
        log_done "Updated $key: $value in $file"
    else
        echo "${key}: ${value}" >> "$file"
        log_done "Added $key: $value to $file"
    fi
}

# Set a key in a TOML file under a specific section
set_toml_value() {
    local file="$1" section="$2" key="$3" value="$4"
    ensure_dir "$file"

    if [[ ! -f "$file" ]]; then
        printf '%s\n%s = %s\n' "$section" "$key" "$value" > "$file"
        log_done "Created $file with $key = $value"
        return
    fi

    if grep -q "^${key} " "$file" || grep -q "^${key}=" "$file"; then
        sed -i '' "s|^${key}[ =].*|${key} = ${value}|" "$file"
        log_done "Updated $key = $value in $file"
    elif grep -q "^\\${section}" "$file" 2>/dev/null || grep -q "^${section}" "$file"; then
        # Section exists, insert after it
        sed -i '' "/^${section//\[/\\[}/a\\
${key} = ${value}
" "$file"
        log_done "Added $key = $value under $section in $file"
    else
        # Section doesn't exist, append both
        printf '\n%s\n%s = %s\n' "$section" "$key" "$value" >> "$file"
        log_done "Added $section with $key = $value to $file"
    fi
}

# =============================================================================
# Package Manager Configurations
# =============================================================================

configure_npm() {
    echo ""
    log_info "${BOLD}npm${NC} — checking..."

    if command -v npm &>/dev/null; then
        local version
        version="$(npm --version 2>/dev/null)"
        if ! version_gte "$version" "11.10.0"; then
            log_error "██ npm $version is OUTDATED — min-release-age requires >= 11.10.0 ██"
            log_error "██ Run: npm install -g npm@latest                                  ██"
        fi
    else
        log_info "npm not installed — setting config proactively"
    fi

    local config="$HOME/.npmrc"
    backup_file "$config"
    # npm uses days (not minutes like pnpm)
    set_ini_value "$config" "min-release-age" "$DELAY_DAYS"
}

configure_pnpm() {
    echo ""
    log_info "${BOLD}pnpm${NC} — checking..."

    if command -v pnpm &>/dev/null; then
        local version
        version="$(pnpm --version 2>/dev/null)"
        if ! version_gte "$version" "10.16.0"; then
            log_error "██ pnpm $version is OUTDATED — minimum-release-age requires >= 10.16.0 ██"
            log_error "██ Run: npm install -g pnpm@latest                                      ██"
        fi
    else
        log_info "pnpm not installed — setting config proactively"
    fi

    # pnpm has its own global config (not ~/.npmrc)
    # $XDG_CONFIG_HOME/pnpm/rc if set, else macOS: ~/Library/Preferences/pnpm/rc, Linux: ~/.config/pnpm/rc
    local config
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        config="$XDG_CONFIG_HOME/pnpm/rc"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        config="$HOME/Library/Preferences/pnpm/rc"
    else
        config="$HOME/.config/pnpm/rc"
    fi
    backup_file "$config"
    set_ini_value "$config" "minimum-release-age" "10080"
}

configure_yarn() {
    echo ""
    log_info "${BOLD}yarn${NC} — checking..."

    if command -v yarn &>/dev/null; then
        local version
        version="$(yarn --version 2>/dev/null)"
        if ! version_gte "$version" "4.10.0"; then
            log_error "██ yarn $version is OUTDATED — npmMinimalAgeGate requires >= 4.10.0 ██"
            log_error "██ Run: corepack prepare yarn@stable --activate                      ██"
        fi
    else
        log_info "yarn not installed — setting config proactively"
    fi

    local config="$HOME/.yarnrc.yml"
    backup_file "$config"
    set_yaml_value "$config" "npmMinimalAgeGate" '"7d"'
}

configure_bun() {
    echo ""
    log_info "${BOLD}bun${NC} — checking..."

    if command -v bun &>/dev/null; then
        local version
        version="$(bun --version 2>/dev/null)"
        if ! version_gte "$version" "1.3.0"; then
            log_error "██ bun $version is OUTDATED — minimumReleaseAge requires >= 1.3.0 ██"
            log_error "██ Run: bun upgrade                                                ██"
        fi
    else
        log_info "bun not installed — setting config proactively"
    fi

    local config="$HOME/bunfig.toml"
    backup_file "$config"
    set_toml_value "$config" "[install]" "minimumReleaseAge" "604800"
}

configure_uv() {
    echo ""
    log_info "${BOLD}uv${NC} — checking..."

    if ! command -v uv &>/dev/null; then
        log_info "uv not installed — setting config proactively"
    fi

    local config="$HOME/.config/uv/uv.toml"

    backup_file "$config"
    set_toml_value "$config" "[pip]" "exclude-newer" "\"${DELAY_DAYS} days\""
}

configure_pip() {
    echo ""
    log_info "${BOLD}pip${NC} — checking..."

    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        local pip_cmd
        pip_cmd="$(command -v pip3 || command -v pip)"
        local version
        version="$($pip_cmd --version 2>/dev/null | awk '{print $2}')"
        if ! version_gte "$version" "26.0.0"; then
            log_error "██ pip $version is OUTDATED — --uploaded-prior-to requires >= 26.0.0 ██"
            log_error "██ Run: pip install --upgrade pip                                     ██"
        fi
    fi

    log_warn "pip has no config file support for age gating."
    log_warn "Run setup-shim.sh to get pip age-gating via a shell wrapper."
}

configure_go() {
    echo ""
    log_info "${BOLD}go${NC} — checking..."

    if ! command -v go &>/dev/null; then
        log_skip "go not installed"
        return
    fi

    log_warn "Go does not support release-age gating."
    log_warn "Consider: review new dependencies manually, use a curated GOPROXY,"
    log_warn "and pin dependencies in go.sum."
}

configure_sbt() {
    echo ""
    log_info "${BOLD}sbt${NC} — checking..."

    if ! command -v sbt &>/dev/null; then
        log_skip "sbt not installed"
        return
    fi

    log_warn "sbt/Scala does not support release-age gating."
    log_warn "Consider: pin exact versions in build.sbt and use dependencyLock plugin."
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Supply Chain Protection — Package Manager Defaults     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Setting ${DELAY_DAYS}-day minimum release age for all supported package managers."
echo "Existing config files will be backed up before modification."

configure_npm
configure_pnpm
configure_yarn
configure_bun
configure_uv
configure_pip
configure_go
configure_sbt

echo ""
echo -e "${GREEN}${BOLD}Defaults configuration complete.${NC}"
echo ""
