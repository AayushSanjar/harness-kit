#!/usr/bin/env bash
# Tests for git-guard.mjs, the PreToolUse hook on Bash that denies git push, destructive git
# (including git checkout . and -f, git stash drop and clear, and git rebase) and the
# person's scripts outside scratch copies under the OS temp folder.
#
# Each command is given to the hook as Claude Code gives it (JSON on stdin, with a cwd);
# nothing is run. The "real working tree" is a path outside the temp folder that need not
# exist (/harness-kit-guard-test/project), so the cases hold wherever the repository is,
# also in replay-faults.sh's worktrees under the temp folder. Prints one PASS or FAIL line
# per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/plugins/harness-kit/scripts/git-guard.mjs"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
REAL=/harness-kit-guard-test/project
failures=0

result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}

# decide CWD COMMAND: prints "deny" (with the reason on the next lines) or "allow".
decide() {
  local out
  out="$(node -e 'console.log(JSON.stringify({ tool_name: "Bash", tool_input: { command: process.argv[1] }, cwd: process.argv[2] }))' "$2" "$1" |
    node "$GUARD" 2>&1)"
  if [ -z "$out" ]; then
    echo allow
  else
    node -e '
      const o = JSON.parse(process.argv[1]).hookSpecificOutput;
      console.log(o.permissionDecision);
      console.log(o.permissionDecisionReason);
    ' "$out"
  fi
}

# expect LABEL WANT CWD COMMAND...: every COMMAND, run from CWD, must get WANT.
expect() {
  local label="$1" want="$2" cwd="$3" command got bad=""
  shift 3
  for command in "$@"; do
    got="$(decide "$cwd" "$command" | head -n 1)"
    [ "$got" = "$want" ] || bad="$bad
$got (want $want): $command"
  done
  if [ -z "$bad" ]; then result "$label" yes ""; else result "$label" no "${bad#?}"; fi
}

# 1. git push, of any kind and however it is written, in the real working tree; the reason
# names the command and the folder.
reason="$(decide "$REAL" 'git add -A && git push -u origin feature')"
push_ok=no
grep -qx deny <<<"$(head -n 1 <<<"$reason")" &&
  grep -qF "BLOCKED by harness-kit git-guard: \`git push\` in $REAL, not a scratch copy under the OS temp folder" <<<"$reason" &&
  grep -qF 'Claude never pushes' <<<"$reason" && grep -qF 'command: git push -u origin feature' <<<"$reason" && push_ok=yes
result "git-guard: a denial names the command, the folder and the reason" "$push_ok" "$reason"
expect "git-guard: git push in the real working tree is denied, however it is written" deny "$REAL" \
  'git push' 'git push --force origin main' 'git push origin :old' 'git push --dry-run' "git -C $REAL push" \
  'FOO=1 git push' 'env FOO=1 command git push' 'sudo -u root git push' '/usr/bin/git push' 'git -c a.b=c push' \
  'bash -c "git push"' "sh -lc 'git push'" 'echo $(git push)' 'echo `git push`' 'eval "git push"' \
  'if true; then git push; fi' 'for x in a; do git push; done' 'git status; git push' 'cd && git push'

# 2. Destructive git in the real working tree.
expect "git-guard: destructive git in the real working tree is denied" deny "$REAL" \
  'git reset --hard' 'git reset --hard HEAD~1' 'git checkout -- app.txt' 'git checkout HEAD -- a b' \
  'git restore app.txt' 'git restore --staged app.txt' 'git clean -f' 'git clean -fdx' 'git clean --force' \
  'git branch -D old' 'git branch --delete --force old' 'git branch -d -f old'
expect "git-guard: git checkout . and -f, git stash drop and clear, and git rebase are denied in the real working tree" deny "$REAL" \
  'git checkout .' 'git checkout HEAD .' 'git checkout -f' 'git checkout --force main' 'git checkout -fb topic' \
  'git stash drop' 'git stash drop stash@{1}' 'git stash clear' 'git rebase main' 'git rebase -i HEAD~3' 'git rebase --continue' \
  "git -C $REAL rebase --onto main old"
expect "git-guard: the same are allowed in a scratch copy" allow "$REAL" \
  "cd $WORK && git checkout . && git stash drop && git rebase main"

# 3. The person's scripts in the real working tree, by path or through a shell.
expect "git-guard: land.sh, ship.sh, release.sh, upgrade.sh and approve-protected.sh are denied in the real working tree" deny "$REAL" \
  'bash plugins/harness-kit/scripts/ship.sh' 'bash "$PLUGIN/scripts/land.sh" fix.patch' './upgrade.sh 0.13.0' \
  'sh /x/release.sh v1.0.0' 'scripts/approve-protected.sh' '. ./ship.sh' 'nohup bash ship.sh'

# 4. The same commands inside a scratch copy under the temp folder: the cwd there, a cd
# that must have happened (&&, inside its subshell), git -C, a mktemp folder.
expect "git-guard: the same commands are allowed in a scratch copy under the temp folder" allow "$REAL" \
  "cd $WORK && git push" "git -C $WORK/clone push --force" "(cd $WORK && git reset --hard)" \
  'W=$(mktemp -d) && cd "$W" && git push' 'W="$(mktemp -d)"; cd "$W" && bash /x/ship.sh' \
  'cd "${TMPDIR:-/tmp}/scratch" && git clean -fdx' "cd /tmp/scratch && bash upgrade.sh 0.1.0"
expect "git-guard: every command is allowed when Claude's shell is already in a scratch copy" allow "$WORK/clone" \
  'git push' 'git reset --hard' 'bash ship.sh' 'git branch -D x'

# 5. A cd that may not have happened, or whose effect ended, leaves the real working tree
# possible: after ";", after "||", in its own subshell or pipeline; an unknown folder; the
# temp folder itself; a link from the temp folder into the real tree.
ln -s "$HOME" "$WORK/home-link"
expect "git-guard: a cd that may not have run, or ended with its subshell or pipeline, leaves the real tree" deny "$REAL" \
  "cd $WORK/home-link && git push" "cd $WORK; git push" "(cd $WORK); git push" "cd $WORK | git push" "cd $WORK || git push" \
  'cd - && git push' 'cd "$SOMEWHERE" && git push' 'cd /tmp && git push' "false || cd $WORK && git push"

# 6. Allowed in the real working tree: commits, reads, and text that only mentions the words.
expect "git-guard: commits, reads and mentions are allowed in the real working tree" allow "$REAL" \
  'git commit -m "do not git push; run ship.sh"' $'git commit -F - <<EOF\ngit push\nbash ship.sh\nEOF\necho done' \
  'git checkout main' 'git checkout -b topic' 'git clean -n' 'git branch -d merged' 'git status && git log --grep=push' \
  'cat plugins/harness-kit/scripts/ship.sh' 'grep -n release.sh README.md' 'bash tests/validate.sh' 'git stash' \
  'git stash list' 'git stash pop' 'git checkout -b fix' 'git log --grep=rebase' \
  "echo 'git push' # git push"

# 7. Not Bash, or unreadable input: nothing printed; a broken input exits 1 (the call goes
# ahead, the person sees the line).
other="$(echo '{"tool_name":"Write","tool_input":{"file_path":"x","content":"git push"},"cwd":"/x"}' | node "$GUARD" 2>&1)"
other_status=$?
broken="$(echo 'not json' | node "$GUARD" 2>&1)"
broken_status=$?
if [ "$other_status" -eq 0 ] && [ -z "$other" ] && [ "$broken_status" -eq 1 ] &&
  grep -q '^harness-kit git-guard: could not read hook input' <<<"$broken"; then
  result "git-guard: other tools pass silently; unreadable input lets the call through with a note" yes ""
else
  result "git-guard: other tools pass silently; unreadable input lets the call through with a note" no "other: $other_status $other
broken: $broken_status $broken"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures git-guard case(s) failed"
  exit 1
fi
