#!/usr/bin/env bash
# Tests for check-names.mjs: harness-kit's commands are written by their full names
# (/harness-kit:<name>), no retired name comes back, and no skill is named like a Claude
# Code built-in (tests/claude-builtins.txt). Made-up plugin folders in a temporary folder,
# then this repository itself. Prints one PASS or FAIL line per case and exits non-zero if
# any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CN="$ROOT/plugins/harness-kit/scripts/check-names.mjs"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
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

# builtins FILE [NO_SOURCE|NO_VERSION]: a small built-in list, with or without a header line.
builtins() {
  {
    [ "${2:-}" = NO_SOURCE ] || echo "# source: https://code.claude.com/docs/en/commands.md"
    [ "${2:-}" = NO_VERSION ] || echo "# claude-code: 2.1.284"
    printf '%s\n' help plan review
  } >"$1"
}

# skill DIR FOLDER NAME [BODY]: DIR/skills/FOLDER/SKILL.md with frontmatter name NAME.
skill() {
  mkdir -p "$1/skills/$2"
  printf -- '---\nname: %s\ndescription: made up\n---\n\n%s\n' "$3" "${4:-Body.}" >"$1/skills/$2/SKILL.md"
}

# run DIR LIST: check-names on DIR's skills and on DIR itself; prints the exit status, then
# the output.
run() {
  local out status
  out="$(node "$CN" --builtins "$2" --skills "$1/skills" "$1" 2>&1)"
  status=$?
  echo "$status"
  echo "$out"
}

# (1) Bare names fail, each with its file and line: in a script message, in a SKILL.md and
# in a README.
d="$WORK/bare"
builtins "$WORK/list.txt"
skill "$d" brief brief
skill "$d" record-defect record-defect "If there is no brief, run /brief first; then \`/record-defect\` again."
mkdir -p "$d/scripts"
printf '#!/usr/bin/env bash\necho "Fix: in Claude, run /brief <goal> to write it"\n' >"$d/scripts/x.sh"
printf 'Type `/record-defect <bug>` in Claude.\n' >"$d/README.md"
out="$(run "$d" "$WORK/list.txt")"
if [ "$(head -1 <<<"$out")" = 1 ] &&
  grep -qF "$d/scripts/x.sh:2: bare: write /harness-kit:brief" <<<"$out" &&
  grep -qF "$d/skills/record-defect/SKILL.md:6: bare: write /harness-kit:brief" <<<"$out" &&
  grep -qF "$d/skills/record-defect/SKILL.md:6: bare: write /harness-kit:record-defect" <<<"$out" &&
  grep -qF "$d/README.md:1: bare: write /harness-kit:record-defect" <<<"$out"; then
  result "check-names: a bare /brief or /record-defect in a script message, a SKILL.md or README fails, naming the file and line" yes ""
else
  result "check-names: a bare /brief or /record-defect in a script message, a SKILL.md or README fails, naming the file and line" no "$out"
fi

# (2) The retired name fails, bare or in full.
d="$WORK/retired"
skill "$d" brief brief
printf 'In Claude, run /plan <goal>.\nOr /harness-kit:plan <goal>.\n' >"$d/notes.md"
out="$(run "$d" "$WORK/list.txt")"
if [ "$(head -1 <<<"$out")" = 1 ] &&
  grep -qF "$d/notes.md:1: retired: \"plan\" is no longer a harness-kit command" <<<"$out" &&
  grep -qF "$d/notes.md:2: retired: \"plan\" is no longer a harness-kit command" <<<"$out"; then
  result "check-names: the retired /plan fails, bare or as /harness-kit:plan" yes ""
else
  result "check-names: the retired /plan fails, bare or as /harness-kit:plan" no "$out"
fi

# (3) Full names and paths that hold a skill's name pass.
d="$WORK/full"
skill "$d" brief brief "Run /harness-kit:brief <goal>, then /harness-kit:record-defect <bug>."
skill "$d" record-defect record-defect
printf 'See skills/brief/SKILL.md and .reports/<branch>.brief.md; approve-brief.sh approves it.\n' >"$d/README.md"
out="$(run "$d" "$WORK/list.txt")"
if [ "$(head -1 <<<"$out")" = 0 ]; then
  result "check-names: full names, paths such as skills/brief/SKILL.md and .reports/<branch>.brief.md pass" yes ""
else
  result "check-names: full names, paths such as skills/brief/SKILL.md and .reports/<branch>.brief.md pass" no "$out"
fi

# (4) A skill named like a built-in fails, naming the built-in list.
d="$WORK/builtin"
skill "$d" plan plan
out="$(run "$d" "$WORK/list.txt")"
if [ "$(head -1 <<<"$out")" = 1 ] &&
  grep -qF "$d/skills/plan/SKILL.md:1: built-in: the skill \"plan\" is named like Claude Code's /plan ($WORK/list.txt)" <<<"$out"; then
  result "check-names: a skill named like a Claude Code built-in (plan) fails, naming the built-in list" yes ""
else
  result "check-names: a skill named like a Claude Code built-in (plan) fails, naming the built-in list" no "$out"
fi

# (5) The frontmatter name is the one checked, whatever the folder is called.
d="$WORK/frontmatter"
skill "$d" write-it Plan
out="$(run "$d" "$WORK/list.txt")"
if [ "$(head -1 <<<"$out")" = 1 ] &&
  grep -qF "$d/skills/write-it/SKILL.md:1: built-in: the skill \"Plan\" is named like Claude Code's /Plan" <<<"$out"; then
  result "check-names: a skill's frontmatter name is the name checked, not its folder" yes ""
else
  result "check-names: a skill's frontmatter name is the name checked, not its folder" no "$out"
fi

# (6) A built-in list without its source line, or without its claude-code line, fails.
d="$WORK/unsourced"
skill "$d" brief brief
builtins "$WORK/no-source.txt" NO_SOURCE
builtins "$WORK/no-version.txt" NO_VERSION
out1="$(run "$d" "$WORK/no-source.txt")"
out2="$(run "$d" "$WORK/no-version.txt")"
if [ "$(head -1 <<<"$out1")" = 1 ] && grep -qF "$WORK/no-source.txt:1: source:" <<<"$out1" &&
  [ "$(head -1 <<<"$out2")" = 1 ] && grep -qF "$WORK/no-version.txt:1: source:" <<<"$out2"; then
  result "check-names: a built-in list without its source URL or Claude Code version fails" yes ""
else
  result "check-names: a built-in list without its source URL or Claude Code version fails" no "no source: $out1"$'\n'"no version: $out2"
fi

# (7) This repository: README.md and the whole plugin, against the real built-in list.
out="$(node "$CN" --builtins "$ROOT/tests/claude-builtins.txt" --skills "$ROOT/plugins/harness-kit/skills" \
  "$ROOT/README.md" "$ROOT/plugins/harness-kit" 2>&1)"
status=$?
if [ "$status" -eq 0 ]; then
  result "check-names on this repository: no bare or retired harness command name, and no skill named like a built-in" yes ""
else
  result "check-names on this repository: no bare or retired harness command name, and no skill named like a built-in" no "$out"
fi

[ "$failures" -eq 0 ]
