# scdp — pip / pip3 age-gating wrappers
#
# Sourced by the scdp loader in your shell RC. Injects --uploaded-prior-to
# on `pip install` and `pip download` so newly published packages are
# delayed before they can be installed.
#
# Routes through sfw (Socket Firewall) when sfw is on PATH; falls back to
# direct pip otherwise. Decisions are made at source time (shell startup).

command -v pip  >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1 || return 0

if command -v sfw >/dev/null 2>&1; then
    _scdp_pip_run() { command sfw "$@"; }
else
    _scdp_pip_run() { command "$@"; }
fi

_scdp_pip_cutoff() {
    if date -v-1d +%s >/dev/null 2>&1; then
        date -v-7d -u +%Y-%m-%dT%H:%M:%SZ              # BSD date (macOS)
    else
        date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ    # GNU date (Linux)
    fi
}

if command -v pip >/dev/null 2>&1; then
    pip() {
        case "${1:-}" in
            install|download)
                _scdp_pip_run pip "$1" --uploaded-prior-to "$(_scdp_pip_cutoff)" "${@:2}"
                ;;
            *)
                _scdp_pip_run pip "$@"
                ;;
        esac
    }
fi

if command -v pip3 >/dev/null 2>&1; then
    pip3() {
        case "${1:-}" in
            install|download)
                _scdp_pip_run pip3 "$1" --uploaded-prior-to "$(_scdp_pip_cutoff)" "${@:2}"
                ;;
            *)
                _scdp_pip_run pip3 "$@"
                ;;
        esac
    }
fi
