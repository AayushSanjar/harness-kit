#!/usr/bin/env bash
# Install harness-kit's local git hooks: a pre-push hook that refuses any push to the review
# base branch unless ship.sh or release.sh is the one pushing, and a commit-msg hook that
# checks each commit message with check-commits.mjs's rules as it is committed.
#
#   install-hooks.sh     run from anywhere inside the project's git repository
#
# For people, in their own terminal; upgrade.sh runs it too. It writes three files in
# <git common dir>/hooks (.git/hooks in a normal clone, shared by every worktree): pre-push,
# commit-msg, and harness-kit-check-commits.mjs, a copy of check-commits.mjs from beside
# this script, which the commit-msg hook runs. They are local: git never commits, pushes or
# clones them, so each clone runs install-hooks.sh once, and the copy is as new as the
# install-hooks.sh that wrote it (upgrade.sh runs the one it ships beside).
#
# THE PRE-PUSH HOOK. On every `git push`, git gives the hook one line per ref pushed
# ("<local ref> <local sha> <remote ref> <remote sha>"). When a remote ref is
# refs/heads/<base> (a change, a new branch or a deletion), the hook refuses the whole push,
# with the message "push through ship.sh", unless HARNESS_KIT_SHIP=1 is set: ship.sh sets it
# for its own push of the base, after the review and CI, and release.sh for its push of the
# base and the tag, after the check and CI. <base> is read at push time from
# .harness/review-base (first line, default main), as ship.sh reads it. Pushes of other
# branches are never refused.
#
# THE COMMIT-MSG HOOK. On every `git commit` (a merge, an amend and a reword too), git gives
# the hook the file holding the new message; the hook runs
# `node harness-kit-check-commits.mjs --message <file>`: the message against the staged
# changes plus the branch so far (check-commits.mjs, THE MESSAGE MODE): every protected
# file the commit changes named, every number in its body in the diff or on a "Told:" line,
# and no "Decision:" line naming a path in .harness/removed-paths. A finding refuses the
# commit, printing each finding with its fix and where git saved the message. It needs
# node on PATH, as the rest of harness-kit does.
#
# THE OVERRIDE. `git push --no-verify` and `git commit --no-verify` skip these hooks, as
# they skip any: that is the person's deliberate override. The hooks stop mistakes, not a
# person who means it; CI's check-commits.mjs still reads every commit on the branch.
#
# EVERY REPOSITORY WHOSE BASE IS PUSHED THROUGH ship.sh OR release.sh. A repository whose
# base is pushed by hand must not install the pre-push hook: every hand push of the base
# would be refused. (harness-kit's own base is pushed by release.sh.)
#
# AN EXISTING HOOK. A pre-push or commit-msg hook that harness-kit wrote (its second line is
# its marker below) is replaced, so a re-run or an upgrade brings it up to date. Any other
# hook of either name is left as it is, and install-hooks.sh stops (exit 1) saying so,
# installing neither. With core.hooksPath set, git runs hooks from that folder instead of
# .git/hooks, so the hooks would never run: install-hooks.sh stops (exit 1) and says so,
# installing nothing.
#
# Exit status: 0 installed (or already up to date); 1 not installed (the message says why);
# 2 usage.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE_PUSH_MARKER="# harness-kit pre-push hook (install-hooks.sh)"
COMMIT_MSG_MARKER="# harness-kit commit-msg hook (install-hooks.sh)"
CHECK_COPY=harness-kit-check-commits.mjs
say() { echo "harness-kit install-hooks.sh: $*" >&2; }

[ $# -eq 0 ] || { echo "usage: install-hooks.sh" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { say "not inside a git repository"; exit 2; }

hooks_path="$(git config --get core.hooksPath)"
if [ -n "$hooks_path" ]; then
  say "NOT INSTALLED: core.hooksPath is set ($hooks_path), so git does not run hooks from .git/hooks. Add the pre-push and commit-msg checks to $hooks_path yourself, or unset core.hooksPath and run install-hooks.sh again."
  exit 1
fi
hooks="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
for pair in "pre-push:$PRE_PUSH_MARKER" "commit-msg:$COMMIT_MSG_MARKER"; do
  hook="$hooks/${pair%%:*}"
  if [ -e "$hook" ] && [ "$(sed -n 2p "$hook")" != "${pair#*:}" ]; then
    say "NOT INSTALLED: $hook exists and harness-kit did not write it, so it is left as it is and no hook was installed. Move it away (or merge the two by hand) and run install-hooks.sh again."
    exit 1
  fi
done

mkdir -p "$hooks" || { say "NOT INSTALLED: cannot create $hooks"; exit 1; }
# write NAME: the hook's text from stdin into $hooks/NAME, executable, replacing it whole.
write() {
  local tmp="$hooks/$1.harness-kit.$$"
  cat >"$tmp" && chmod +x "$tmp" && mv -f "$tmp" "$hooks/$1" || { rm -f "$tmp"; say "NOT INSTALLED: cannot write $hooks/$1"; exit 1; }
}

write pre-push <<HOOK
#!/bin/sh
$PRE_PUSH_MARKER
# Refuses any push to the review base branch (.harness/review-base, default main) unless
# HARNESS_KIT_SHIP=1 is set, as ship.sh and release.sh set it for their own push. Reinstall
# with install-hooks.sh; do not edit.
[ "\${HARNESS_KIT_SHIP:-}" = 1 ] && exit 0
base="\$( { [ -f .harness/review-base ] && head -n 1 .harness/review-base; } | tr -d '\r' | tr -d '[:space:]')"
base="\${base:-main}"
refused=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "\$remote_ref" = "refs/heads/\$base" ] && refused=1
done
[ "\$refused" -eq 0 ] && exit 0
echo "harness-kit pre-push: refusing to push to \$base: push through ship.sh (it reviews the branch, waits for CI, then pushes \$base itself), or release.sh where the base is not reviewed. git push --no-verify skips this hook: your deliberate override." >&2
exit 1
HOOK

cp "$HERE/check-commits.mjs" "$hooks/$CHECK_COPY.harness-kit.$$" && mv -f "$hooks/$CHECK_COPY.harness-kit.$$" "$hooks/$CHECK_COPY" ||
  { rm -f "$hooks/$CHECK_COPY.harness-kit.$$"; say "NOT INSTALLED: cannot copy check-commits.mjs to $hooks/$CHECK_COPY"; exit 1; }

write commit-msg <<HOOK
#!/bin/sh
$COMMIT_MSG_MARKER
# Checks the message being committed with check-commits.mjs's rules (a copy beside this
# hook, $CHECK_COPY), against the staged changes plus the branch so far, and
# refuses the commit on any finding. git commit --no-verify skips it: the person's
# deliberate override. Reinstall with install-hooks.sh; do not edit.
check="\$(dirname "\$0")/$CHECK_COPY"
if [ ! -f "\$check" ]; then
  echo "harness-kit commit-msg: commit REFUSED: \$check is missing. Run install-hooks.sh again (or git commit --no-verify, your deliberate override)." >&2
  exit 1
fi
out="\$(node "\$check" --message "\$1" 2>&1)"
status=\$?
[ "\$status" -eq 0 ] && exit 0
printf '%s\n' "\$out" >&2
echo "harness-kit commit-msg: commit REFUSED (above). Git saved your message in \$1: fix what each finding says, then commit again, for example: git commit -e -F \$1 (with the same files staged). To commit anyway: git commit --no-verify, your deliberate override." >&2
exit 1
HOOK

say "installed $hooks/pre-push (pushes to the review base branch are refused unless ship.sh or release.sh makes them) and $hooks/commit-msg (each commit message is checked with check-commits.mjs's rules)"
exit 0
