#!/usr/bin/env bash
# Tests for the guards that keep Claude from writing a brief's approval
# (.reports/<branch>.brief.approved, which only approve-brief.sh writes) or the Stop hook's
# pass record (<git dir>/harness-kit/stop-gate-pass, which only the Stop hook writes):
# brief-guard.mjs on Write, Edit, MultiEdit and NotebookEdit, and git-guard.mjs on Bash.
#
# Each call is given to the hook as Claude Code gives it (JSON on stdin, with a cwd);
# nothing is run. The "real working tree" is a path outside the temp folder that need not
# exist (/harness-kit-guard-test/project), as in git-guard.test.sh. Prints one PASS or FAIL
# line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIEF_GUARD="$ROOT/plugins/harness-kit/scripts/brief-guard.mjs"
GIT_GUARD="$ROOT/plugins/harness-kit/scripts/git-guard.mjs"
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

# decide HOOK TOOL CWD INPUT_JSON: prints "deny" (with the reason on the next lines) or
# "allow". INPUT_JSON is the tool_input object.
decide() {
  local out
  out="$(node -e 'console.log(JSON.stringify({ tool_name: process.argv[1], tool_input: JSON.parse(process.argv[3]), cwd: process.argv[2] }))' "$2" "$3" "$4" |
    node "$1" 2>&1)"
  if [ -z "$out" ]; then
    echo allow
  else
    node -e '
      const o = JSON.parse(process.argv[1]).hookSpecificOutput;
      console.log(o.permissionDecision);
      console.log(o.permissionDecisionReason);
    ' "$out" 2>&1 || echo "unparsable: $out"
  fi
}

# file_call TOOL PATH: the tool_input JSON for a file tool on PATH.
file_call() {
  node -e '
    const [tool, path] = process.argv.slice(1);
    const input = tool === "NotebookEdit" ? { notebook_path: path, new_source: "x" }
      : tool === "Write" ? { file_path: path, content: "0123abcd" }
      : tool === "MultiEdit" ? { file_path: path, edits: [{ old_string: "a", new_string: "b" }] }
      : { file_path: path, old_string: "a", new_string: "b" };
    console.log(JSON.stringify(input));
  ' "$1" "$2"
}

# expect_file LABEL WANT CWD TOOL:PATH...: every call must get WANT from brief-guard.mjs.
expect_file() {
  local label="$1" want="$2" cwd="$3" call got bad=""
  shift 3
  for call in "$@"; do
    got="$(decide "$BRIEF_GUARD" "${call%%:*}" "$cwd" "$(file_call "${call%%:*}" "${call#*:}")" | head -n 1)"
    [ "$got" = "$want" ] || bad="$bad
$got (want $want): $call"
  done
  if [ -z "$bad" ]; then result "$label" yes ""; else result "$label" no "${bad#?}"; fi
}

# expect_bash LABEL WANT CWD COMMAND...: every command must get WANT from git-guard.mjs.
expect_bash() {
  local label="$1" want="$2" cwd="$3" command got bad=""
  shift 3
  for command in "$@"; do
    got="$(decide "$GIT_GUARD" Bash "$cwd" "$(node -e 'console.log(JSON.stringify({ command: process.argv[1] }))' "$command")" | head -n 1)"
    [ "$got" = "$want" ] || bad="$bad
$got (want $want): $command"
  done
  if [ -z "$bad" ]; then result "$label" yes ""; else result "$label" no "${bad#?}"; fi
}

# 1. File tools: an approval in the real tree, by an absolute or a relative path, is denied
# for every file tool; the reason names the tool, the file and approve-brief.sh.
reason="$(decide "$BRIEF_GUARD" Write "$REAL" "$(file_call Write .reports/feature.brief.approved)")"
reason_ok=no
grep -qx deny <<<"$(head -n 1 <<<"$reason")" &&
  grep -qF "BLOCKED by harness-kit brief-guard: Write of $REAL/.reports/feature.brief.approved, not a scratch copy" <<<"$reason" &&
  grep -qF 'only approve-brief.sh writes, run by the person in their own terminal' <<<"$reason" && reason_ok=yes
result "brief-guard: a denial names the tool, the file and approve-brief.sh" "$reason_ok" "$reason"
expect_file "brief-guard: Write, Edit, MultiEdit and NotebookEdit of a *.brief.approved file in the real tree are denied" deny "$REAL" \
  "Write:$REAL/.reports/feature.brief.approved" "Write:.reports/team-login.brief.approved" "Edit:.reports/feature.brief.approved" \
  "MultiEdit:$REAL/.reports/feature.brief.approved" "NotebookEdit:$REAL/x.brief.approved"

# 2. File tools: the brief itself, other files, and an approval in a scratch copy are allowed.
expect_file "brief-guard: the brief, other files and approvals in a scratch copy are allowed" allow "$REAL" \
  "Write:.reports/feature.brief.md" "Edit:$REAL/.reports/feature.md" "Write:$REAL/notes.brief.approved.md" \
  "Write:$WORK/clone/.reports/feature.brief.approved" "Edit:$WORK/x.brief.approved"
expect_file "brief-guard: an approval is allowed when Claude's folder is a scratch copy and the path is relative" allow "$WORK/clone" \
  "Write:.reports/feature.brief.approved"

# 3. Bash: any command naming an approval in the real tree is denied, however it names it.
expect_bash "git-guard: a shell command naming a *.brief.approved file in the real tree is denied" deny "$REAL" \
  'echo abc > .reports/feature.brief.approved' 'shasum -a 256 .reports/f.brief.md | cut -d" " -f1 >.reports/f.brief.approved' \
  'printf x | tee .reports/f.brief.approved' 'cp /tmp/x .reports/f.brief.approved' 'printf x >> "$ROOT/.reports/f.brief.approved"' \
  'bash -c "echo > a.brief.approved"' 'cat .reports/f.brief.approved' 'rm -f .reports/f.brief.approved' \
  'F=.reports/f.brief.approved' 'for f in .reports/*.brief.approved; do echo "$f"; done' \
  "cd $WORK && echo x > $REAL/.reports/f.brief.approved" 'echo "$(cat x.brief.approved)"'

# 4. Bash: the brief, a commit message that mentions an approval, and an approval in a
# scratch copy are allowed.
expect_bash "git-guard: the brief, mentions in a message and approvals in a scratch copy are allowed" allow "$REAL" \
  'echo x > .reports/feature.brief.md' 'cat .reports/feature.brief.md' \
  'git commit -m "approve-brief.sh writes .reports/feature.brief.approved"' \
  "cd $WORK && echo x > f.brief.approved" "echo x > $WORK/r/.reports/f.brief.approved" \
  $'cat <<EOF\n.reports/f.brief.approved\nEOF'

# 6. The Stop hook's pass record (<git dir>/harness-kit/stop-gate-pass), which only the Stop
# hook writes: the file tools and shell commands that name it in the real tree are denied,
# with a reason naming the Stop hook; in a scratch copy they are allowed.
reason="$(decide "$BRIEF_GUARD" Write "$REAL" "$(file_call Write .git/harness-kit/stop-gate-pass)")"
reason_ok=no
grep -qx deny <<<"$(head -n 1 <<<"$reason")" &&
  grep -qF "BLOCKED by harness-kit brief-guard: Write of $REAL/.git/harness-kit/stop-gate-pass, not a scratch copy" <<<"$reason" &&
  grep -qF "it is the Stop hook's pass record" <<<"$reason" && reason_ok=yes
result "brief-guard: a denial of the pass record names the Stop hook" "$reason_ok" "$reason"
expect_file "brief-guard: Write, Edit, MultiEdit and NotebookEdit of the Stop hook's pass record in the real tree are denied" deny "$REAL" \
  "Write:$REAL/.git/harness-kit/stop-gate-pass" "Write:.git/harness-kit/stop-gate-pass" "Edit:.git/harness-kit/stop-gate-pass" \
  "MultiEdit:$REAL/.git/worktrees/w/harness-kit/stop-gate-pass" "NotebookEdit:$REAL/.git/harness-kit/stop-gate-pass"
expect_file "brief-guard: the pass record in a scratch copy, and files only named like it, are allowed" allow "$REAL" \
  "Write:$WORK/clone/.git/harness-kit/stop-gate-pass" "Write:$REAL/stop-gate-pass.md" "Edit:$REAL/notes/stop-gate-passes"
expect_bash "git-guard: a shell command naming the Stop hook's pass record in the real tree is denied" deny "$REAL" \
  'echo "{}" > .git/harness-kit/stop-gate-pass' 'cp /tmp/x .git/harness-kit/stop-gate-pass' \
  'printf x | tee .git/harness-kit/stop-gate-pass' 'P=.git/harness-kit/stop-gate-pass' \
  "cd $WORK && echo x > $REAL/.git/harness-kit/stop-gate-pass"
expect_bash "git-guard: the pass record in a scratch copy, and a message that mentions it, are allowed" allow "$REAL" \
  "echo x > $WORK/r/.git/harness-kit/stop-gate-pass" 'git commit -m "the Stop hook writes .git/harness-kit/stop-gate-pass"'

# 5. Other tools pass silently; unreadable input exits 1 (the call goes ahead, the person
# sees the line).
other="$(echo '{"tool_name":"Read","tool_input":{"file_path":"/x/.reports/a.brief.approved"},"cwd":"/x"}' | node "$BRIEF_GUARD" 2>&1)"
other_status=$?
broken="$(echo 'not json' | node "$BRIEF_GUARD" 2>&1)"
broken_status=$?
if [ "$other_status" -eq 0 ] && [ -z "$other" ] && [ "$broken_status" -eq 1 ] &&
  grep -q '^harness-kit brief-guard: could not read hook input' <<<"$broken"; then
  result "brief-guard: other tools (Read) pass silently; unreadable input lets the call through with a note" yes ""
else
  result "brief-guard: other tools (Read) pass silently; unreadable input lets the call through with a note" no "other: $other_status $other
broken: $broken_status $broken"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures brief-guard case(s) failed"
  exit 1
fi
