# scdp — sfw malware-scanning aliases for Node-ecosystem package managers
#
# Sourced by the scdp loader in your shell RC. Defines an alias only for the
# tools that exist at shell-startup time, so `command -v <tool>` stays honest
# when a tool isn't installed.
#
# If sfw itself is missing, this file is a no-op.

command -v sfw >/dev/null 2>&1 || return 0

command -v npm  >/dev/null 2>&1 && alias npm='sfw npm'
command -v npx  >/dev/null 2>&1 && alias npx='sfw npx'
command -v yarn >/dev/null 2>&1 && alias yarn='sfw yarn'
command -v pnpm >/dev/null 2>&1 && alias pnpm='sfw pnpm'
command -v uv   >/dev/null 2>&1 && alias uv='sfw uv'
