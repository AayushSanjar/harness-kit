#!/usr/bin/env bash
# Tests for upgrade.sh: move a consumer project's harness-kit pin, re-add the marketplace,
# update the plugin, confirm the loaded version, install the pre-push and commit-msg hooks,
# run the project's approval, then write the pin's commit draft from harness-kit's own
# commits between the two tags and prove it passes the commit-msg hook.
#
# Every case runs in a temporary git repository, with a FAKE `claude` first on PATH. It
# appends each call to $FAKE_LOG/claude-calls and answers:
#   plugin marketplace add ...  exit $FAKE_ADD_EXIT (default 0)
#   plugin update ...           exit $FAKE_UPDATE_EXIT (default 0)
#   -p ...                      a stream-json session: a SessionStart hook event, then an
#                               init event listing harness-kit@harness-kit at
#                               $FAKE_LOADED (plus $FAKE_PLUGIN_ERRORS, a JSON array, if
#                               set), then it waits 30 s as a real session waits for the
#                               model. With FAKE_NO_INIT set, it prints an error and exits 1.
# harness-kit's own history is a local repository, $WORK/upstream (UPGRADE_UPSTREAM_URL),
# with the tags v0.8.0 and v0.9.0 and one commit between them. Nothing touches GitHub and
# no API call is made. Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPGRADE="$ROOT/plugins/harness-kit/scripts/upgrade.sh"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export UPGRADE_POLL_SECONDS=0 UPGRADE_INIT_SECONDS=20
unset FAKE_ADD_EXIT FAKE_UPDATE_EXIT FAKE_LOADED FAKE_PLUGIN_ERRORS FAKE_NO_INIT

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

describe() { printf 'exit %s (%ss)\nstderr: %s\nclaude calls:\n%s' "$STATUS" "$SECONDS_TAKEN" "$ERR" "$(cat "$DIR.log/claude-calls" 2>/dev/null)"; }

mkdir -p "$WORK/bin"
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_LOG/claude-calls"
case "$1 $2 $3" in
  "plugin marketplace add") exit "${FAKE_ADD_EXIT:-0}" ;;
esac
case "$1 $2" in
  "plugin update") exit "${FAKE_UPDATE_EXIT:-0}" ;;
esac
if [ "$1" = -p ]; then
  if [ -n "${FAKE_NO_INIT:-}" ]; then
    echo "fake claude: not logged in" >&2
    exit 1
  fi
  node -e '
    const [loaded, errors] = process.argv.slice(1);
    console.log(JSON.stringify({ type: "system", subtype: "hook_response", hook_event: "SessionStart", stdout: `harness-kit ${loaded} loaded\n` }));
    const init = { type: "system", subtype: "init", cwd: process.cwd(), plugins: [
      { name: "harness-kit", path: `/cache/harness-kit/harness-kit/${loaded}`, source: "harness-kit@harness-kit", version: loaded },
      { name: "other", path: "/cache/other/1.0.0", source: "other@elsewhere", version: "1.0.0" },
    ] };
    if (errors) init.plugin_errors = JSON.parse(errors);
    console.log(JSON.stringify(init));
  ' "${FAKE_LOADED:-0.9.0}" "${FAKE_PLUGIN_ERRORS:-}"
  # The session's pid, and a child of its own (as a real session starts MCP servers and
  # hooks), for the process-group case.
  echo $$ >"$FAKE_LOG/session.pid"
  sleep 30 &
  echo $! >"$FAKE_LOG/session.child"
  exec sleep 30
fi
echo "fake claude: unexpected call: $*" >&2
exit 64
FAKE
chmod +x "$WORK/bin/claude"

# The upstream: v0.8.0, then one commit with a Breaks: line, two Decision: lines (the first
# naming a path and continuing onto the next line), a Told: line, a body line with a number
# and a trailer, tagged v0.9.0.
UP="$WORK/upstream"
git init -q -b main "$UP"
git -C "$UP" commit -q --allow-empty -m "Start"
git -C "$UP" tag v0.8.0
git -C "$UP" commit -q --allow-empty -m 'Increment 9: faster checks. Version 0.9.0.

scripts/a.sh: 12 checks now.
Told: 224 PASS lines in the final run.
Breaks: tests/a.test.sh "a check" fails when a.sh skips 3 files.
Decision: plugins/harness-kit/scripts/old.mjs is gone; its 2 callers use new.mjs,
  and nothing else changes.
Decision: releases are tagged.

Co-Authored-By: Someone <someone@example.invalid>'
git -C "$UP" tag v0.9.0
export UPGRADE_UPSTREAM_URL="$UP"

# new_project NAME [APPROVE]: a repository whose .claude/settings.json pins harness-kit at
# v0.8.0, with an approval command that reads one answer from its input, records it and
# fails unless it is "y" (APPROVE "none": no approval command). Prints its path.
new_project() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.claude" "$dir/.harness" "$dir.log"
  git -C "$dir" init -q -b main
  cat >"$dir/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "deny": [
      "Edit(/.harness/**)"
    ]
  },
  "enabledPlugins": {
    "harness-kit@harness-kit": true
  },
  "extraKnownMarketplaces": {
    "harness-kit": {
      "source": {
        "source": "github",
        "repo": "AayushSanjar/harness-kit",
        "ref": "v0.8.0"
      }
    }
  }
}
JSON
  if [ "${2:-}" != none ]; then
    printf 'read answer; printf "%%s\\n" "$answer" > "%s/approved"; [ "$answer" = y ]\n' "$dir.log" >"$dir/.harness/approve-command"
  fi
  git -C "$dir" add -A && git -C "$dir" commit -q -m "initial"
  echo "$dir"
}

# run_upgrade DIR ANSWER ARGS...: run upgrade.sh in a subfolder of DIR with ANSWER as the
# terminal's input; sets STATUS, ERR, SECONDS_TAKEN and DIR.
run_upgrade() {
  DIR="$1"
  local answer="$2" start
  shift 2
  mkdir -p "$DIR/sub"
  rm -f "$DIR.log/claude-calls" "$DIR.log/approved"
  start=$(date +%s)
  (cd "$DIR/sub" && PATH="$WORK/bin:$PATH" FAKE_LOG="$DIR.log" bash "$UPGRADE" "$@" <<<"$answer" >/dev/null 2>"$WORK/stderr")
  STATUS=$?
  SECONDS_TAKEN=$(($(date +%s) - start))
  ERR="$(cat "$WORK/stderr")"
}

ref_of() { node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).extraKnownMarketplaces["harness-kit"].source.ref' "$1/.claude/settings.json"; }

# 1. Success: the pin moves (and nothing else in settings.json), the marketplace is re-added
# at the tag and the plugin updated, in that order; the session is stopped as soon as its
# init event is read (well before the fake's 30 s); install-hooks.sh installs the pre-push
# hook; the approval runs with the person's answer.
dir="$(new_project ok)"
run_upgrade "$dir" y 0.9.0
calls="$(cat "$dir.log/claude-calls" 2>/dev/null)"
changed="$(git -C "$dir" diff --numstat | tr '\t' ' ')"
if [ "$STATUS" -eq 0 ] && [ "$(ref_of "$dir")" = v0.9.0 ] &&
  [ "$changed" = "1 1 .claude/settings.json" ] &&
  [ "$(sed -n 1p <<<"$calls")" = "plugin marketplace add AayushSanjar/harness-kit#v0.9.0 --scope project" ] &&
  [ "$(sed -n 2p <<<"$calls")" = "plugin update harness-kit@harness-kit --scope project" ] &&
  grep -q '^-p .*--output-format stream-json --verbose' <<<"$(sed -n 3p <<<"$calls")" &&
  [ "$(wc -l <<<"$calls" | tr -d ' ')" = 3 ] && [ "$SECONDS_TAKEN" -lt 15 ] &&
  grep -q '4/7 a new session loads harness-kit@harness-kit 0.9.0' <<<"$ERR" &&
  grep -q '5/7 installed the pre-push and commit-msg hooks' <<<"$ERR" && grep -q '^# harness-kit pre-push hook' "$dir/.git/hooks/pre-push" &&
  grep -q '^# harness-kit commit-msg hook' "$dir/.git/hooks/commit-msg" &&
  [ "$(cat "$dir.log/approved" 2>/dev/null)" = y ] && grep -q 'UPGRADED' <<<"$ERR" &&
  [ -z "$(git -C "$dir" log --oneline -1 --skip 1)" ]; then
  result "upgrade.sh: pins the tag, re-adds the marketplace, updates, confirms the loaded version, installs the hook, then approves" yes ""
else
  result "upgrade.sh: pins the tag, re-adds the marketplace, updates, confirms the loaded version, installs the hook, then approves" no \
    "$(describe)
settings.json diff: $changed"
fi

# 2. The loaded version is not the one asked for: it stops before the approval, saying
# which version loads and what has changed so far.
dir="$(new_project stale)"
FAKE_LOADED=0.8.0 run_upgrade "$dir" y v0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: a new session loads harness-kit@harness-kit 0.8.0, not 0.9.0' <<<"$ERR" &&
  grep -q 'settings.json now pins v0.9.0 (was v0.8.0)' <<<"$ERR" &&
  [ ! -e "$dir.log/approved" ] && ! grep -q UPGRADED <<<"$ERR"; then
  result "upgrade.sh: a session that loads another version stops it before the approval" yes ""
else
  result "upgrade.sh: a session that loads another version stops it before the approval" no "$(describe)"
fi

# 3. Plugin errors for harness-kit in the init event stop it, even at the right version.
dir="$(new_project errors)"
FAKE_PLUGIN_ERRORS='[{"plugin":"harness-kit@harness-kit","error":"hooks.json is invalid"}]' run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the init event reports plugin errors for harness-kit@harness-kit' <<<"$ERR" &&
  [ ! -e "$dir.log/approved" ]; then
  result "upgrade.sh: plugin errors in the init event stop it before the approval" yes ""
else
  result "upgrade.sh: plugin errors in the init event stop it before the approval" no "$(describe)"
fi

# 4. A session with no init event stops it, with claude's error.
dir="$(new_project no-init)"
FAKE_NO_INIT=1 run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the headless session ended without an init event: fake claude: not logged in' <<<"$ERR" &&
  [ ! -e "$dir.log/approved" ]; then
  result "upgrade.sh: a session with no init event stops it" yes ""
else
  result "upgrade.sh: a session with no init event stops it" no "$(describe)"
fi

# 5. A failing marketplace add stops it at once: no update, no session, no approval; the
# message says the pin already moved and how to undo it.
dir="$(new_project add-fails)"
FAKE_ADD_EXIT=1 run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: claude plugin marketplace add AayushSanjar/harness-kit#v0.9.0 --scope project failed' <<<"$ERR" &&
  grep -q 'to undo: git checkout -- .claude/settings.json' <<<"$ERR" &&
  [ "$(wc -l <"$dir.log/claude-calls" | tr -d ' ')" = 1 ] && [ ! -e "$dir.log/approved" ]; then
  result "upgrade.sh: a failed marketplace add stops before the update" yes ""
else
  result "upgrade.sh: a failed marketplace add stops before the update" no "$(describe)"
fi

# 6. A failing update stops it before the session.
dir="$(new_project update-fails)"
FAKE_UPDATE_EXIT=1 run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: claude plugin update harness-kit@harness-kit --scope project failed' <<<"$ERR" &&
  [ "$(wc -l <"$dir.log/claude-calls" | tr -d ' ')" = 2 ] && [ ! -e "$dir.log/approved" ]; then
  result "upgrade.sh: a failed plugin update stops before the session" yes ""
else
  result "upgrade.sh: a failed plugin update stops before the session" no "$(describe)"
fi

# 7. The person declines the approval: exit 1, the pin moved, nothing committed.
dir="$(new_project declined)"
run_upgrade "$dir" n 0.9.0
if [ "$STATUS" -eq 1 ] && [ "$(cat "$dir.log/approved" 2>/dev/null)" = n ] &&
  grep -q 'STOPPED: the approval command failed or was declined (exit 1)' <<<"$ERR" &&
  [ "$(ref_of "$dir")" = v0.9.0 ] && [ -z "$(git -C "$dir" log --oneline -1 --skip 1)" ]; then
  result "upgrade.sh: a declined approval stops it, with nothing committed" yes ""
else
  result "upgrade.sh: a declined approval stops it, with nothing committed" no "$(describe)"
fi

# 8. No approval command: it upgrades and says to read the diff.
dir="$(new_project no-approve none)"
run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 0 ] && grep -q 'no .harness/approve-command' <<<"$ERR" && grep -q UPGRADED <<<"$ERR"; then
  result "upgrade.sh: with no approval command it upgrades and says to read the diff" yes ""
else
  result "upgrade.sh: with no approval command it upgrades and says to read the diff" no "$(describe)"
fi

# 9. Refusals that change nothing and call no claude: not a version, and no pin.
dir="$(new_project refuse)"
run_upgrade "$dir" y latest
bad_version="$STATUS: $ERR"
node -e '
  const f = process.argv[1], s = JSON.parse(require("fs").readFileSync(f, "utf8"));
  delete s.extraKnownMarketplaces;
  require("fs").writeFileSync(f, JSON.stringify(s, null, 2) + "\n");
' "$dir/.claude/settings.json"
git -C "$dir" commit -q -am "no pin"
run_upgrade "$dir" y 0.9.0
if grep -q '^2: .*"latest" is not a version like 0.9.0' <<<"$bad_version" &&
  [ "$STATUS" -eq 1 ] && grep -q 'has no extraKnownMarketplaces\["harness-kit"\].source with a repo and a ref. Nothing was changed.' <<<"$ERR" &&
  [ -z "$(git -C "$dir" status --porcelain -- .claude)" ] && [ ! -e "$dir.log/claude-calls" ]; then
  result "upgrade.sh: a bad version or a missing pin changes nothing and calls no claude" yes ""
else
  result "upgrade.sh: a bad version or a missing pin changes nothing and calls no claude" no "bad version: $bad_version
no pin: $(describe)"
fi

# 10. A pre-push hook harness-kit did not write: install-hooks.sh leaves it as it is, and
# upgrade.sh stops before the approval, saying what changed so far.
dir="$(new_project foreign-hook)"
printf '#!/bin/sh
echo mine
' >"$dir/.git/hooks/pre-push"
run_upgrade "$dir" y 0.9.0
if [ "$STATUS" -eq 1 ] && grep -q 'exists and harness-kit did not write it' <<<"$ERR" &&
  grep -q 'STOPPED: install-hooks.sh did not install the hooks' <<<"$ERR" &&
  [ "$(sed -n 2p "$dir/.git/hooks/pre-push")" = "echo mine" ] && [ ! -e "$dir.log/approved" ]; then
  result "upgrade.sh: a pre-push hook it did not write stops it before the approval, untouched" yes ""
else
  result "upgrade.sh: a pre-push hook it did not write stops it before the approval, untouched" no "$(describe)"
fi

# 11. The commit draft. The project protects .claude/settings.json and
# .harness/protected.lock (which its approval re-records) and has removed the path that
# harness-kit's first Decision: names. On a branch, the draft is written to
# .reports/<branch>.commit.txt: both files named with reasons, harness-kit's Breaks: line
# kept, its Decision: lines relabelled Upstream: (continuation too), its own Told: and file
# lines and its trailer left out, and every number carried on a Told: line; upgrade.sh
# says the hook's check passes it. The printed command then commits it through the
# installed commit-msg hook, and check-commits.mjs passes the branch.
dir="$(new_project draft none)"
printf '.claude/settings.json\n.harness/protected.lock\n' >"$dir/.harness/protected-paths"
printf 'plugins/harness-kit/scripts/old.mjs\n' >"$dir/.harness/removed-paths"
printf 'read answer; [ "$answer" = y ] && git hash-object .claude/settings.json > .harness/protected.lock\n' >"$dir/.harness/approve-command"
printf '.reports/\n' >"$dir/.gitignore"
git -C "$dir" add -A && git -C "$dir" commit -q -m "harness files"
git -C "$dir" checkout -q -b pin
run_upgrade "$dir" y 0.9.0
draft="$(cat "$dir/.reports/pin.commit.txt" 2>/dev/null)"
cmd="$(sed -n 's/^harness-kit upgrade.sh:     //p' <<<"$ERR")"
committed="$(cd "$dir" && eval "$cmd" 2>&1)"
commit_status=$?
check="$(cd "$dir" && node "$ROOT/plugins/harness-kit/scripts/check-commits.mjs" 2>&1)"
if [ "$STATUS" -eq 0 ] && [ "$(sed -n 1p <<<"$draft")" = "Pin harness-kit to v0.9.0 (was v0.8.0)" ] &&
  grep -qx '.claude/settings.json: pins the harness-kit marketplace to v0.9.0 (was v0.8.0); .*' <<<"$draft" &&
  grep -qx '.harness/protected.lock: re-recorded by the approval command .*' <<<"$draft" &&
  grep -qx -- '- Increment 9: faster checks. Version 0.9.0.' <<<"$draft" &&
  grep -qxF '  Breaks: tests/a.test.sh "a check" fails when a.sh skips 3 files.' <<<"$draft" &&
  grep -qxF '  Upstream: plugins/harness-kit/scripts/old.mjs is gone; its 2 callers use new.mjs,' <<<"$draft" &&
  grep -qxF '  and nothing else changes.' <<<"$draft" && grep -qxF '  Upstream: releases are tagged.' <<<"$draft" &&
  ! grep -q 'Decision:\|224\|12 checks\|Co-Authored-By' <<<"$draft" &&
  grep -qx "Told: the numbers in harness-kit's commits above are quoted from its commit messages (git log v0.8.0..v0.9.0 in github.com/AayushSanjar/harness-kit), not from this project's diff:" <<<"$draft" &&
  [ "$(tail -n 1 <<<"$draft")" = "  9 0.9.0 3 2" ] &&
  grep -q "7/7 wrote the commit draft $dir/.reports/pin.commit.txt; the commit-msg hook's check passes it: PASS check-commits" <<<"$ERR" &&
  [ "$cmd" = "git add -- .claude/settings.json .harness/protected.lock && git commit -F $dir/.reports/pin.commit.txt" ] &&
  [ "$commit_status" -eq 0 ] && [ "$(git -C "$dir" log -1 --format=%s)" = "Pin harness-kit to v0.9.0 (was v0.8.0)" ] &&
  [ -z "$(git -C "$dir" status --porcelain)" ] && grep -q '^PASS check-commits: 1 commit(s)' <<<"$check"; then
  result "upgrade.sh: writes the pin commit draft (Breaks kept, Decision relabelled Upstream, numbers on Told) and it passes the commit-msg hook" yes ""
else
  result "upgrade.sh: writes the pin commit draft (Breaks kept, Decision relabelled Upstream, numbers on Told) and it passes the commit-msg hook" no "$(describe)
draft:
$draft
command: $cmd
commit ($commit_status): $committed
check-commits: $check"
fi

# 12. Uncommitted changes to a tracked file: it stops before changing anything or calling
# claude. harness-kit's history that cannot be fetched stops it after the approval, with no
# draft and nothing committed.
dir="$(new_project dirty)"
printf '{}\n' >"$dir/.claude/other.json" && git -C "$dir" add -A && git -C "$dir" commit -q -m other
printf '{"x": 1}\n' >"$dir/.claude/other.json"
run_upgrade "$dir" y 0.9.0
dirty="$STATUS: $ERR"
dirty_calls="$(cat "$dir.log/claude-calls" 2>/dev/null)"
dir="$(new_project no-upstream)"
UPGRADE_UPSTREAM_URL="$WORK/nowhere" run_upgrade "$dir" y 0.9.0
if grep -q '^1: .*STOPPED: there are uncommitted changes (git status); commit or stash them first' <<<"$dirty" &&
  [ -z "$dirty_calls" ] && [ "$(ref_of "$WORK/dirty")" = v0.8.0 ] &&
  [ "$STATUS" -eq 1 ] && grep -q "STOPPED: could not fetch the tags v0.8.0 and v0.9.0 from $WORK/nowhere" <<<"$ERR" &&
  [ "$(cat "$dir.log/approved" 2>/dev/null)" = y ] && [ ! -s "$dir/.reports/main.commit.txt" ] &&
  [ -z "$(git -C "$dir" log --oneline -1 --skip 1)" ]; then
  result "upgrade.sh: uncommitted changes stop it before anything; unreachable upstream stops it before the draft" yes ""
else
  result "upgrade.sh: uncommitted changes stop it before anything; unreachable upstream stops it before the draft" no "dirty: $dirty
dirty claude calls: $dirty_calls
no upstream: $(describe)"
fi

# 12. After the init event, the headless session is stopped with its whole process group:
# the session and the child it started are both gone when upgrade.sh ends.
dir="$(new_project whole-group)"
HARNESS_KIT_LIMIT_GRACE_SECONDS=1 run_upgrade "$dir" y 0.9.0
sleep 0.2
left=""
for f in session.pid session.child; do
  [ -s "$dir.log/$f" ] && kill -0 "$(cat "$dir.log/$f")" 2>/dev/null && left="$left $f"
done
if [ "$STATUS" -eq 0 ] && [ -s "$dir.log/session.child" ] && [ -z "$left" ]; then
  result "upgrade.sh: after the init event, the headless session's whole process group is gone" yes ""
else
  result "upgrade.sh: after the init event, the headless session's whole process group is gone" no "$(describe)
still running:${left:- nothing}"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures upgrade case(s) failed"
  exit 1
fi
