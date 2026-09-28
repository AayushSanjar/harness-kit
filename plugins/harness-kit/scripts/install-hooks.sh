#!/usr/bin/env bash
# Install harness-kit's local git hook: a pre-push hook that refuses any push to the review
# base branch unless ship.sh is the one pushing.
#
#   install-hooks.sh     run from anywhere inside the project's git repository
#
# For people, in their own terminal; upgrade.sh runs it too. It writes one file,
# <git common dir>/hooks/pre-push (.git/hooks/pre-push in a normal clone, shared by every
# worktree), which is local: git never commits, pushes or clones it, so each clone runs
# install-hooks.sh once.
#
# THE HOOK. On every `git push`, git gives the hook one line per ref pushed ("<local ref>
# <local sha> <remote ref> <remote sha>"). When a remote ref is refs/heads/<base> (a
# change, a new branch or a deletion), the hook refuses the whole push, with the message
# "push through ship.sh", unless HARNESS_KIT_SHIP=1 is set: ship.sh sets it for its own
# push of the base, after the review and CI. <base> is read at push time from
# .harness/review-base (first line, default main), as ship.sh reads it. Pushes of other
# branches are never refused. `git push --no-verify` skips the hook, as it skips any
# pre-push hook: the hook stops mistakes, not a person who means it.
#
# NOT FOR EVERY REPOSITORY. Install it only where the base is pushed through ship.sh. A
# repository whose base is pushed by hand, such as harness-kit's own, must not install it:
# every hand push of the base would be refused. upgrade.sh runs install-hooks.sh, so a
# project like that removes <git common dir>/hooks/pre-push after an upgrade (or does not
# run upgrade.sh).
#
# AN EXISTING HOOK. A pre-push hook that harness-kit wrote (its second line is the marker
# below) is replaced, so a re-run or an upgrade brings it up to date. Any other pre-push
# hook is left as it is, and install-hooks.sh stops (exit 1) saying so. With
# core.hooksPath set, git runs hooks from that folder instead of .git/hooks, so the hook
# would never run: install-hooks.sh stops (exit 1) and says so, installing nothing.
#
# Exit status: 0 installed (or already up to date); 1 not installed (the message says why);
# 2 usage.
set -u

MARKER="# harness-kit pre-push hook (install-hooks.sh)"
say() { echo "harness-kit install-hooks.sh: $*" >&2; }

[ $# -eq 0 ] || { echo "usage: install-hooks.sh" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { say "not inside a git repository"; exit 2; }

hooks_path="$(git config --get core.hooksPath)"
if [ -n "$hooks_path" ]; then
  say "NOT INSTALLED: core.hooksPath is set ($hooks_path), so git does not run hooks from .git/hooks. Add the pre-push check to $hooks_path yourself, or unset core.hooksPath and run install-hooks.sh again."
  exit 1
fi
hooks="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
hook="$hooks/pre-push"
if [ -e "$hook" ] && [ "$(sed -n 2p "$hook")" != "$MARKER" ]; then
  say "NOT INSTALLED: $hook exists and harness-kit did not write it, so it is left as it is. Move it away (or merge the two by hand) and run install-hooks.sh again."
  exit 1
fi

mkdir -p "$hooks" || { say "NOT INSTALLED: cannot create $hooks"; exit 1; }
tmp="$hook.harness-kit.$$"
cat >"$tmp" <<HOOK
#!/bin/sh
$MARKER
# Refuses any push to the review base branch (.harness/review-base, default main) unless
# HARNESS_KIT_SHIP=1 is set, as ship.sh sets it for its own push. Reinstall with
# install-hooks.sh; do not edit.
[ "\${HARNESS_KIT_SHIP:-}" = 1 ] && exit 0
base="\$( { [ -f .harness/review-base ] && head -n 1 .harness/review-base; } | tr -d '\r' | tr -d '[:space:]')"
base="\${base:-main}"
refused=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "\$remote_ref" = "refs/heads/\$base" ] && refused=1
done
[ "\$refused" -eq 0 ] && exit 0
echo "harness-kit pre-push: refusing to push to \$base: push through ship.sh (it reviews the branch, waits for CI, then pushes \$base itself)." >&2
exit 1
HOOK
chmod +x "$tmp" && mv -f "$tmp" "$hook" || { rm -f "$tmp"; say "NOT INSTALLED: cannot write $hook"; exit 1; }
say "installed $hook: pushes to the review base branch are refused unless ship.sh makes them"
exit 0
