# scdp init — entrypoint sourced by your shell RC
#
# Idempotent: if this file is sourced more than once in the same shell
# (e.g. because ~/.bash_profile both runs the loader AND sources ~/.bashrc
# which runs it again), the second invocation returns immediately.
#
# Explicit list of wrapper files to source. Each guard means a wrapper that
# wasn't installed (e.g. you ran setup-pip.sh but not setup-shim.sh) is just
# skipped, not an error.
#
# To force a re-source after editing a wrapper: `unset _SCDP_LOADED && . ~/.config/scdp/init.sh`

[ -n "${_SCDP_LOADED:-}" ] && return 0
_SCDP_LOADED=1

_scdp_dir="${XDG_CONFIG_HOME:-$HOME/.config}/scdp"
[ -r "$_scdp_dir/pip.sh" ] && . "$_scdp_dir/pip.sh"
[ -r "$_scdp_dir/sfw.sh" ] && . "$_scdp_dir/sfw.sh"
unset _scdp_dir
