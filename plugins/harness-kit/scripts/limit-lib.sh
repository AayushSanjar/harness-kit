# The bash side of the time-limit helper (time-limit.mjs), sourced by the harness's bash
# scripts. Written for bash 3.2 (macOS).
#
#   hk_limited [--merge] NAME LABEL COMMAND...
#       Runs COMMAND under the limit NAME (a limit's name, or seconds) in its own process
#       group, with the hard stop: time-limit.mjs run. Returns COMMAND's status, or 124 on a
#       TIMEOUT (its line is on stderr). --merge sends COMMAND's stderr to its stdout, in
#       order. LABEL names the caller in the TIMEOUT line, such as land.sh.
#   hk_git_net LABEL GIT_ARGS...
#       Runs `git GIT_ARGS...`, one network command (push, fetch or ls-remote), under the git
#       limit and without prompts: GIT_TERMINAL_PROMPT=0, so git never asks for a username
#       or password, and GIT_SSH_COMMAND set to the ssh command git would use (the person's
#       GIT_SSH_COMMAND, else their core.sshCommand, else ssh) with -o BatchMode=yes added,
#       so ssh never asks for a password or passphrase. A failure adds one line saying so;
#       a TIMEOUT of a push adds one saying it may or may not have reached the remote.
#   hk_limit NAME
#       Prints the limit NAME in seconds.
#   hk_on_exit [FUNCTION]
#       Cleanup on any exit: on EXIT, INT, TERM, HUP and PIPE, FUNCTION runs (when given),
#       then every hk_temp path is removed, then the script exits: with its own status, or
#       130, 143, 129 or 141 for the signal. Call it once, before anything needs cleaning up;
#       a later call only sets FUNCTION.
#   hk_temp VAR [-d] PREFIX
#       Makes a temporary file (a folder with -d) under the OS temp folder, named
#       PREFIX.XXXXXX, and puts its path in VAR. It is removed on any exit (hk_on_exit is
#       set if it was not), and recorded in the helper's registry, so that the helper's
#       sweep removes it if this script is force-killed. Not in a subshell: VAR is set here.
[ -z "${HK_LIMIT_LIB:-}" ] || return 0
HK_LIMIT_LIB=1
HK_LIMIT_JS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/time-limit.mjs"
HK_EXIT_SET=""
HK_EXIT_FN=""
HK_TEMPS=""

hk_limited() {
  local merge=""
  if [ "${1:-}" = --merge ]; then merge=--merge; shift; fi
  local name="$1" label="$2"
  shift 2
  node "$HK_LIMIT_JS" run --limit "$name" --name "$label" $merge -- "$@"
}

hk_limit() { node "$HK_LIMIT_JS" limit "$1"; }

hk_git_net() {
  local label="$1" sub="" remote="" arg ssh status next=""
  shift
  for arg in "$@"; do
    if [ -n "$next" ]; then
      case "$arg" in -*) ;; *) remote="$arg"; break ;; esac
    else
      case "$arg" in push | fetch | ls-remote) sub="$arg"; next=1 ;; esac
    fi
  done
  ssh="${GIT_SSH_COMMAND:-}"
  [ -n "$ssh" ] || ssh="$(git config core.sshCommand 2>/dev/null)"
  [ -n "$ssh" ] || ssh=ssh
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh -o BatchMode=yes" \
    node "$HK_LIMIT_JS" run --limit git --name "$label" -- git "$@"
  status=$?
  if [ "$status" -eq 124 ]; then
    [ "$sub" != push ] ||
      echo "harness-kit $label: the push may or may not have reached ${remote:-the remote}; look with: git ls-remote ${remote:-<remote>}" >&2
  elif [ "$status" -ne 0 ]; then
    echo "harness-kit $label: git ${sub:-command} ran without prompts (GIT_TERMINAL_PROMPT=0, ssh BatchMode=yes); if it needed a password or passphrase, set up a credential helper or ssh-agent, then re-run." >&2
  fi
  return "$status"
}

hk__cleanup() {
  local fn="$HK_EXIT_FN" path
  HK_EXIT_FN=""
  [ -z "$fn" ] || "$fn"
  while IFS= read -r path; do
    [ -z "$path" ] || rm -rf -- "$path"
  done <<<"$HK_TEMPS"
  HK_TEMPS=""
}
hk__on_exit() {
  local status=$?
  trap '' PIPE
  hk__cleanup
  exit "$status"
}
hk__on_signal() {
  trap '' PIPE
  trap - EXIT
  hk__cleanup
  exit "$1"
}

hk_on_exit() {
  [ $# -eq 0 ] || HK_EXIT_FN="$1"
  [ -z "$HK_EXIT_SET" ] || return 0
  HK_EXIT_SET=1
  trap 'hk__on_exit' EXIT
  trap 'hk__on_signal 130' INT
  trap 'hk__on_signal 143' TERM
  trap 'hk__on_signal 129' HUP
  trap 'hk__on_signal 141' PIPE
}

hk_temp() {
  local var="$1" flag="" path record
  shift
  if [ "${1:-}" = -d ]; then flag=-d; shift; fi
  hk_on_exit
  path="$(mktemp $flag "${TMPDIR:-/tmp}/$1.XXXXXX")" || return 1
  HK_TEMPS="$HK_TEMPS$path"$'\n'
  record="$(node "$HK_LIMIT_JS" register --owner $$ path "$path")" && HK_TEMPS="$HK_TEMPS$record"$'\n'
  # no-limit: sets the caller's variable to the new path; runs no command
  eval "$var=\$path"
}
