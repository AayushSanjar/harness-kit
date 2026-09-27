#!/usr/bin/env bash
# Run the project's pre-deploy check, then the deploy only if the check passed.
#
#   deploy.sh <deploy command and its arguments>
#   deploy.sh forge deploy -e production
#   deploy.sh sh -c 'npm run build && forge deploy'
#
# For people, in their own terminal. predeploy-gate.mjs gates Claude's Bash calls
# only: a deploy typed in a shell never passes through a Claude Code hook. This runs
# the same .harness/predeploy-command, found by walking up from the current folder.
#
# With no .harness/predeploy-command it refuses instead of deploying unchecked:
# someone who chose this script expects a check, and a run that checked nothing must
# not look like one that passed.
set -u

if [ $# -eq 0 ]; then
  echo "usage: deploy.sh <deploy command and its arguments>" >&2
  exit 2
fi

root="$PWD"
while [ ! -f "$root/.harness/predeploy-command" ]; do
  if [ "$root" = "/" ]; then
    echo "harness-kit deploy.sh: no .harness/predeploy-command in $PWD or above; nothing was checked, so nothing was deployed" >&2
    exit 2
  fi
  root="$(dirname "$root")"
done

check="$(head -n 1 "$root/.harness/predeploy-command" | tr -d '\r')"
check="${check#"${check%%[![:space:]]*}"}"
if [ -z "$check" ]; then
  echo "harness-kit deploy.sh: $root/.harness/predeploy-command is empty; nothing was checked, so nothing was deployed" >&2
  exit 2
fi

echo "harness-kit deploy.sh: running the pre-deploy check in $root: $check" >&2
(cd "$root" && /bin/sh -c "$check")
status=$?

case "$status" in
  0) ;;
  126 | 127)
    echo "harness-kit deploy.sh: the check COULD NOT RUN (exit $status); not deploying: $*" >&2
    exit "$status"
    ;;
  *)
    echo "harness-kit deploy.sh: the check FAILED (exit $status); not deploying: $*" >&2
    exit "$status"
    ;;
esac

echo "harness-kit deploy.sh: the check passed; deploying: $*" >&2
exec "$@"
