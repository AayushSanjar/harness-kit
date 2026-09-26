#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/guard-secrets.mjs. Each case feeds the hook
# fake PreToolUse input (or runs --scan) against a temporary folder or temporary git
# repository. Prints one PASS or FAIL line per case and exits non-zero if any fail.
#
# Every fake secret is assembled at runtime from pieces that match no rule on their
# own, so no secret-shaped string exists in this file. That is checked: `--scan` over
# this repository reads this file too.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/plugins/harness-kit/scripts/guard-secrets.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# Temporary repositories must not pick up the person's git config (hooks, signing).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

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

# rep CHAR N: CHAR repeated N times.
rep() {
  local s="" i
  for ((i = 0; i < $2; i++)); do s+="$1"; done
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Fake secrets, built from harmless pieces
# ---------------------------------------------------------------------------
D5="$(rep - 5)"
SEG="$(rep a 12)"
CRED_NAME="pass""word"
FAKE_PEM="${D5}BEGIN RSA PRIVATE KEY${D5}"$'\n'"$(rep A 64)"
FAKE_ATLASSIAN="ATA""TT3x$(rep a 24)"
FAKE_GITHUB="gh""p_$(rep a 36)"
FAKE_GITHUB_PAT="github""_pat_$(rep a 40)"
FAKE_ANTHROPIC="sk-""ant-$(rep a 30)"
FAKE_SLACK="xo""xb-$(rep 1 12)"
FAKE_AWS="AK""IA$(rep A 16)"
FAKE_GOOGLE="AI""za$(rep a 35)"
FAKE_JWT="ey""J${SEG}.${SEG}.${SEG}"
FAKE_VALUE="$(rep q 24)"
FAKE_ASSIGNMENT="const ${CRED_NAME} = \"${FAKE_VALUE}\";"

# ---------------------------------------------------------------------------
# Running the hook
# ---------------------------------------------------------------------------

# make_input TOOL CWD KEY=VALUE...: PreToolUse JSON. KEY "edits" becomes a
# one-element MultiEdit edits array.
make_input() {
  node -e '
    const [tool, cwd, ...pairs] = process.argv.slice(1);
    const toolInput = {};
    for (const pair of pairs) {
      const i = pair.indexOf("=");
      const key = pair.slice(0, i);
      const value = pair.slice(i + 1);
      if (key === "edits") toolInput.edits = [{ old_string: "x", new_string: value }];
      else toolInput[key] = value;
    }
    console.log(JSON.stringify({ hook_event_name: "PreToolUse", tool_name: tool, tool_input: toolInput, cwd }));
  ' "$@"
}

# run_guard TOOL CWD KEY=VALUE...: run the hook from CWD; sets OUT, ERR, STATUS.
run_guard() {
  local input
  input="$(make_input "$@")"
  OUT="$(cd "$2" && CLAUDE_PROJECT_DIR="$2" node "$GUARD" <<<"$input" 2>"$WORK/stderr")"
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

field() {
  node -e '
    try { console.log(JSON.parse(process.argv[1]).hookSpecificOutput[process.argv[2]] ?? "") } catch {}
  ' "$OUT" "$1"
}
describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# expect_deny LABEL [MUST_NOT_APPEAR [MUST_APPEAR]]: exit 0 with permissionDecision
# "deny". The reason must never repeat the secret itself.
expect_deny() {
  local label="$1" hidden="${2:-}" shown="${3:-}" reason
  reason="$(field permissionDecisionReason)"
  if [ "$STATUS" -eq 0 ] && [ "$(field permissionDecision)" = deny ] &&
    { [ -z "$hidden" ] || ! grep -qF -- "$hidden" <<<"$reason"; } &&
    { [ -z "$shown" ] || grep -qF -- "$shown" <<<"$reason"; }; then
    result "$label" yes ""
  else
    result "$label" no "$(describe)"
  fi
}

# expect_allow LABEL: exit 0, no output, so the normal permission flow continues.
expect_allow() {
  if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
    result "$1" yes ""
  else
    result "$1" no "$(describe)"
  fi
}

# new_repo NAME: a temporary git repository with one commit of a clean README.md.
new_repo() {
  local dir="$WORK/$1"
  git init -q "$dir" 2>/dev/null
  printf '# readme\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm init
  echo "$dir"
}

# ---------------------------------------------------------------------------
# Authoring: true positives by path
# ---------------------------------------------------------------------------
PROJ="$WORK/project"
mkdir -p "$PROJ"

run_guard Write "$PROJ" file_path="$PROJ/.env" content="A=1"
expect_deny "Write .env: denied"
run_guard Write "$PROJ" file_path="$PROJ/.env.local" content="A=1"
expect_deny "Write .env.local: denied"
run_guard Write "$PROJ" file_path="$PROJ/certs/server.pem" content="x"
expect_deny "Write a .pem file: denied"
run_guard Write "$PROJ" file_path="$PROJ/keys/id_rsa" content="x"
expect_deny "Write id_rsa: denied"
run_guard Write "$PROJ" file_path="$PROJ/.npmrc" content="registry=x"
expect_deny "Write .npmrc: denied"
run_guard Write "$PROJ" file_path="$PROJ/node_modules/pkg/index.js" content="x"
expect_deny "Write under node_modules/: denied"
run_guard Write "$PROJ" file_path="$PROJ/dist/app.js" content="x"
expect_deny "Write under dist/: denied"
run_guard Write "$PROJ" file_path="$PROJ/build/out.js" content="x"
expect_deny "Write under build/: denied"

# ---------------------------------------------------------------------------
# Authoring: true positives by content (a .txt file, so no path rule applies)
# ---------------------------------------------------------------------------
content_case() {
  local label="$1" fake="$2"
  run_guard Write "$PROJ" file_path="$PROJ/notes.txt" content="Some notes."$'\n'"$fake"$'\n'"More notes."
  expect_deny "Write $label: denied, value not echoed" "$fake"
}
content_case "a PEM private key block" "$FAKE_PEM"
content_case "an Atlassian API token" "$FAKE_ATLASSIAN"
content_case "a GitHub token" "$FAKE_GITHUB"
content_case "a GitHub fine-grained PAT" "$FAKE_GITHUB_PAT"
content_case "an Anthropic API key" "$FAKE_ANTHROPIC"
content_case "a Slack token" "$FAKE_SLACK"
content_case "an AWS access key id" "$FAKE_AWS"
content_case "a Google API key" "$FAKE_GOOGLE"
content_case "a JWT" "$FAKE_JWT"

run_guard Write "$PROJ" file_path="$PROJ/config.js" content="$FAKE_ASSIGNMENT"
expect_deny "Write a long quoted value assigned to a credential name in .js: denied" "$FAKE_VALUE"
run_guard Edit "$PROJ" file_path="$PROJ/app.js" old_string="x" new_string="const gh = '$FAKE_GITHUB';"
expect_deny "Edit new_string with a GitHub token: denied" "$FAKE_GITHUB"
run_guard MultiEdit "$PROJ" file_path="$PROJ/app.js" edits="const k = '$FAKE_AWS';"
expect_deny "MultiEdit edits with an AWS key: denied" "$FAKE_AWS"
run_guard NotebookEdit "$PROJ" notebook_path="$PROJ/nb.ipynb" new_source="client = Slack('$FAKE_SLACK')"
expect_deny "NotebookEdit new_source with a Slack token: denied" "$FAKE_SLACK"

# ---------------------------------------------------------------------------
# Authoring: true negatives
# ---------------------------------------------------------------------------
run_guard Write "$PROJ" file_path="$PROJ/.env.example" content="API_KEY="$'\n'"DATABASE_URL="
expect_allow "Write .env.example: allowed"
run_guard Write "$PROJ" file_path="$PROJ/.env.template" content="API_KEY="
expect_allow "Write .env.template: allowed"
run_guard Write "$PROJ" file_path="$PROJ/README.md" \
  content="Rotate the token often. Keep the API key and the secret out of git; the private key lives in a vault. Example: token = \"replace-with-your-own-value\""
expect_allow "Write prose using token, key and secret: allowed"
run_guard Write "$PROJ" file_path="$PROJ/src/issues.js" \
  content="const sortKey = row.key; const tokenCount = tokens.length; const keyMap = new Map();"
expect_allow "Write code naming sortKey and tokenCount: allowed"
PROJ_UNDER_BUILD="$WORK/build/checkout"
mkdir -p "$PROJ_UNDER_BUILD"
run_guard Write "$PROJ_UNDER_BUILD" file_path="$PROJ_UNDER_BUILD/src/app.js" content="export const x = 1;"
expect_allow "Write in a project whose parent folder is named build: allowed"
run_guard Bash "$PROJ" command="ls -la && echo done"
expect_allow "Bash command without git add: allowed"

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
repo="$(new_repo stage-named)"
printf 'settings\n%s\n' "$FAKE_GITHUB" >"$repo/config.txt"
run_guard Bash "$repo" command="git add config.txt"
expect_deny "git add of a file holding a GitHub token: denied" "$FAKE_GITHUB" "config.txt"

repo="$(new_repo stage-compound)"
printf 'settings\n%s\n' "$FAKE_JWT" >"$repo/session.txt"
run_guard Bash "$repo" command="git add -A && git commit -m wip"
expect_deny "git add -A && git commit -m wip in a temporary repository: denied" "$FAKE_JWT" "session.txt"

repo="$(new_repo stage-env)"
printf 'A=1\n' >"$repo/.env"
run_guard Bash "$repo" command="git add .env"
expect_deny "git add .env: denied by path" "" ".env"

repo="$(new_repo stage-commit-a)"
printf '# readme\n%s\n' "$FAKE_AWS" >"$repo/README.md"
run_guard Bash "$repo" command="git commit -am wip"
expect_deny "git commit -am on a tracked file now holding an AWS key: denied" "$FAKE_AWS" "README.md"

repo="$(new_repo stage-subdir)"
mkdir -p "$repo/sub"
printf '%s\n' "$FAKE_ANTHROPIC" >"$repo/sub/inner.txt"
run_guard Bash "$repo/sub" command="git add -A"
expect_deny "git add -A from a subdirectory: denied (content read from the repository root)" "" "sub/inner.txt"

repo="$(new_repo stage-dash-c)"
printf '%s\n' "$FAKE_GOOGLE" >"$repo/maps.txt"
run_guard Bash "$WORK" command="git -C $repo add ."
expect_deny "git -C <repo> add . from outside it: denied" "" "maps.txt"

repo="$(new_repo stage-clean)"
printf 'Plain notes about the token and the key.\n' >"$repo/notes.md"
run_guard Bash "$repo" command="git add notes.md && git status"
expect_allow "git add of a clean file: allowed"

# ---------------------------------------------------------------------------
# --scan
# ---------------------------------------------------------------------------
repo="$(new_repo scan)"
printf 'API_KEY=\n' >"$repo/.env.example"
printf 'Prose about the token and the key.\n' >"$repo/notes.md"
git -C "$repo" add .env.example notes.md
git -C "$repo" commit -qm clean
OUT="$(cd "$repo" && node "$GUARD" --scan 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 0 ] && grep -q '^guard-secrets --scan: 3 tracked files, 0 finding(s)$' <<<"$OUT"; then
  result "--scan on a clean temporary repository: exit 0, no findings" yes ""
else
  result "--scan on a clean temporary repository: exit 0, no findings" no "exit $STATUS; output: $OUT"
fi

mkdir -p "$repo/src"
printf '{\n  "name": "demo",\n  "client": "%s"\n}\n' "$FAKE_ANTHROPIC" >"$repo/src/settings.json"
git -C "$repo" add src/settings.json
git -C "$repo" commit -qm planted
OUT="$(cd "$repo" && node "$GUARD" --scan 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 1 ] && grep -q '^FINDING src/settings.json:3: an Anthropic API key$' <<<"$OUT" &&
  ! grep -qF -- "$FAKE_ANTHROPIC" <<<"$OUT"; then
  result "--scan with a planted secret: exit 1, file and rule named, value not printed" yes ""
else
  result "--scan with a planted secret: exit 1, file and rule named, value not printed" no "exit $STATUS; output: $OUT"
fi

mkdir -p "$WORK/not-a-repo"
OUT="$(cd "$WORK/not-a-repo" && GIT_CEILING_DIRECTORIES="$WORK" node "$GUARD" --scan 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 1 ] && grep -q 'could not list tracked files' <<<"$OUT"; then
  result "--scan outside a repository: fails loudly, not a clean result" yes ""
else
  result "--scan outside a repository: fails loudly, not a clean result" no "exit $STATUS; output: $OUT"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures guard-secrets case(s) failed"
  exit 1
fi
