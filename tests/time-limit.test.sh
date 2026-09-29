#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/time-limit.mjs (the time-limit helper: its hard stop,
# its signals, its registry and sweep) and check-limits.mjs (the check that nothing starts
# long work without the helper). Each case uses tiny limits and a 1-second grace period, and
# waits for real only for those; TMPDIR is this test's own folder, so the helper's registry
# is too. Prints one PASS or FAIL line per case and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/harness-kit/scripts"
TL="$SCRIPTS/time-limit.mjs"
# The real path: ps and git print resolved paths, and macOS's temp folder is behind a symlink.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
# The helper's registry follows this test's TMPDIR, not a replay run's own registry.
unset HARNESS_KIT_REGISTRY_DIR
export HARNESS_KIT_LIMIT_GRACE_SECONDS=1
failures=0
PIDS=""
cleanup() {
  local p
  for p in $PIDS; do kill -9 "$p" 2>/dev/null; kill -9 -- "-$p" 2>/dev/null; done
  rm -rf "$WORK"
}
trap cleanup EXIT

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

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

# ---------------------------------------------------------------------------------------
# The hard stop.
# ---------------------------------------------------------------------------------------

# 1. A command past its limit: exit 124 and the TIMEOUT line, not the command's own status.
began=$SECONDS
out="$(node "$TL" run --limit 0.5 --name test -- sh -c 'sleep 5; exit 3' 2>&1)"
status=$?
took=$((SECONDS - began))
if [ "$status" -eq 124 ] && [ "$took" -le 3 ] &&
  [ "$out" = 'harness-kit test: TIMEOUT: `sh -c sleep 5; exit 3` ran longer than its limit of 0.5 seconds; it was stopped: SIGTERM to its process group, then SIGKILL 1 seconds later if it had not ended' ]; then
  result "time-limit: a command past its limit is stopped, exits 124 and prints TIMEOUT with its limit" yes ""
else
  result "time-limit: a command past its limit is stopped, exits 124 and prints TIMEOUT with its limit" no "exit $status after ${took}s: $out"
fi

# 2. A command that ignores SIGTERM (as its child does, inheriting it) is killed when the
# grace period ends: gone within 3 seconds of its limit (without the kill it would run 30).
began=$SECONDS
node "$TL" run --limit 0.5 -- sh -c "trap '' TERM; echo \$\$ >'$WORK/ignores.pid'; sleep 30 & echo \$! >'$WORK/ignores.child'; wait" 2>/dev/null
status=$?
took=$((SECONDS - began))
sleep 0.2
if [ "$status" -eq 124 ] && [ "$took" -le 4 ] && ! alive "$WORK/ignores.pid" && ! alive "$WORK/ignores.child"; then
  result "time-limit: a command that ignores SIGTERM is force-killed when the grace period ends" yes ""
else
  result "time-limit: a command that ignores SIGTERM is force-killed when the grace period ends" no \
    "exit $status after ${took}s; still alive: $(alive "$WORK/ignores.pid" && echo command) $(alive "$WORK/ignores.child" && echo child)"
fi

# 3. A grandchild in the command's process group goes too, even when the command's own
# process ends first, by itself.
node "$TL" run --limit 5 -- sh -c "sh -c 'sleep 30' & echo \$! >'$WORK/grand.pid'; sleep 0.2; exit 0"
status=$?
sleep 0.2
if [ "$status" -eq 0 ] && ! alive "$WORK/grand.pid"; then
  result "time-limit: a grandchild in the command's process group is stopped too" yes ""
else
  result "time-limit: a grandchild in the command's process group is stopped too" no "exit $status; the grandchild is $(alive "$WORK/grand.pid" && echo alive || echo gone)"
fi

# 4. A hangup, an interrupt or a stop signal to the helper stops the group and exits with
# the signal's status. set -m: a background job keeps SIGINT (bash ignores it for background
# jobs without job control).
got=""
set -m
for pair in HUP:129 INT:130 TERM:143; do
  sig="${pair%:*}"
  want="${pair#*:}"
  node "$TL" run --limit 30 -- sh -c "echo \$\$ >'$WORK/sig.$sig'; sleep 30" &
  helper=$!
  PIDS="$PIDS $helper"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/sig.$sig" ] && break; sleep 0.1; done
  kill -"$sig" "$helper"
  wait "$helper" 2>/dev/null
  status=$?
  sleep 0.2
  alive "$WORK/sig.$sig" && status="$status, command alive"
  got="$got $sig:$status"
done
set +m
if [ "$got" = " HUP:129 INT:130 TERM:143" ]; then
  result "time-limit: a hangup, interrupt or stop signal to the helper stops the group and exits 129, 130 or 143" yes ""
else
  result "time-limit: a hangup, interrupt or stop signal to the helper stops the group and exits 129, 130 or 143" no "got:$got"
fi

# 5. Its output pipe closed (the reader gone), the helper stops the group and exits 141,
# even for a command that ignores SIGPIPE.
node "$TL" run --limit 5 -- sh -c "trap '' PIPE; echo \$\$ >'$WORK/pipe.pid'; while :; do echo y; sleep 0.1; done" | head -n 1 >/dev/null
status="${PIPESTATUS[0]}"
sleep 0.2
if [ "$status" -eq 141 ] && ! alive "$WORK/pipe.pid"; then
  result "time-limit: a closed output pipe stops the group and exits 141" yes ""
else
  result "time-limit: a closed output pipe stops the group and exits 141" no "exit $status; the command is $(alive "$WORK/pipe.pid" && echo alive || echo gone)"
fi

# 5b. A process outside the command's group (a detached child) holding its output open
# does not hold the helper (D5): once the command's first process has ended, the helper
# waits for the output at most one grace period (3 seconds here), says so, and returns the
# command's status. The command ended before its 1-second limit, so there is no TIMEOUT.
# Without the bound, the helper waits for the child's 30 seconds and reports a TIMEOUT.
began=$SECONDS
HARNESS_KIT_LIMIT_GRACE_SECONDS=3 node "$TL" run --limit 1 --name test -- node -e '
const c = require("child_process").spawn("sleep", ["30"], { detached: true, stdio: ["ignore", "inherit", "inherit"] });
require("fs").writeFileSync(process.argv[1], String(c.pid));
c.unref();' "$WORK/held.pid" 2>"$WORK/held.err" | cat >/dev/null
status="${PIPESTATUS[0]}"
took=$((SECONDS - began))
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/held.pid" ] && break; sleep 0.1; done
PIDS="$PIDS $(cat "$WORK/held.pid" 2>/dev/null)"
err="$(cat "$WORK/held.err")"
if [ "$status" -eq 0 ] && [ "$took" -le 6 ] && [ "$(grep -c . <<<"$err")" -eq 1 ] && ! grep -q TIMEOUT <<<"$err" &&
  grep -q 'ended, but a process outside its process group still held its output open; stopped waiting for it after 3 seconds$' <<<"$err"; then
  result "time-limit: a command whose first process ended finishes within the grace period even when a process outside its group holds its output" yes ""
else
  result "time-limit: a command whose first process ended finishes within the grace period even when a process outside its group holds its output" no "exit $status after ${took}s; stderr: $err"
fi

# ---------------------------------------------------------------------------------------
# The registry and the sweep.
# ---------------------------------------------------------------------------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
LIVE="$TMPDIR/harness-kit-live"

# 6. An owner force-killed: its group, its folder and its worktree are left; the next sweep
# stops the group, removes both and prunes the worktree.
repo="$WORK/repo"
git init -q "$repo" && git -C "$repo" commit -q --allow-empty -m initial
node "$TL" run --limit 60 -- sh -c "echo \$\$ >'$WORK/orphan.pid'; sleep 60" &
helper=$!
PIDS="$PIDS $helper"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/orphan.pid" ] && break; sleep 0.1; done
# The owner (sh, which runs the first register call and execs the second) is alive while it
# registers both, and gone after; each register call sweeps, so they share one owner.
mkdir "$TMPDIR/harness-kit-left.1"
git -C "$repo" worktree add -q --detach "$TMPDIR/harness-kit-left-wt.1"
sh -c 'node "$1" register --owner $$ path "$2" && exec node "$1" register --owner $$ worktree "$3" "$4"' - \
  "$TL" "$TMPDIR/harness-kit-left.1" "$repo" "$TMPDIR/harness-kit-left-wt.1" >/dev/null
kill -9 "$helper"
wait "$helper" 2>/dev/null
before="$(alive "$WORK/orphan.pid" && echo alive)"
out="$(node "$TL" sweep 2>&1)"
sleep 0.2
if [ "$before" = alive ] && ! alive "$WORK/orphan.pid" && [ ! -e "$TMPDIR/harness-kit-left.1" ] && [ ! -e "$TMPDIR/harness-kit-left-wt.1" ] &&
  [ "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" = 1 ] && [ -z "$(ls "$LIVE")" ] &&
  [ "$out" = "harness-kit time-limit: cleaned up after an earlier run that was killed: 1 process group(s) stopped, 1 temporary folder(s) and 1 worktree(s) removed" ]; then
  result "time-limit sweep: the group, folder and worktree of an owner that was force-killed are removed" yes ""
else
  result "time-limit sweep: the group, folder and worktree of an owner that was force-killed are removed" no \
    "the group before the sweep: ${before:-gone}; after: $(alive "$WORK/orphan.pid" && echo alive || echo gone)
folder: $(ls -d "$TMPDIR"/harness-kit-left* 2>&1)
worktrees: $(git -C "$repo" worktree list)
records: $(ls "$LIVE")
sweep: $out"
fi

# 7. A live owner's records are left alone: this shell's folder, and a running helper's group.
mkdir "$TMPDIR/harness-kit-mine.1"
node "$TL" register --owner $$ path "$TMPDIR/harness-kit-mine.1" >/dev/null
node "$TL" run --limit 60 -- sh -c "echo \$\$ >'$WORK/live.pid'; sleep 60" &
helper=$!
PIDS="$PIDS $helper"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/live.pid" ] && break; sleep 0.1; done
out="$(node "$TL" sweep 2>&1)"
if [ -d "$TMPDIR/harness-kit-mine.1" ] && alive "$WORK/live.pid" && [ "$(ls "$LIVE" | wc -l | tr -d ' ')" = 2 ] && [ -z "$out" ]; then
  result "time-limit sweep: a live owner's records are left alone" yes ""
else
  result "time-limit sweep: a live owner's records are left alone" no "folder: $(ls -d "$TMPDIR/harness-kit-mine.1" 2>&1); group: $(alive "$WORK/live.pid" && echo alive || echo gone); records: $(ls "$LIVE"); sweep: $out"
fi
kill "$helper" 2>/dev/null
wait "$helper" 2>/dev/null
rm -rf "$TMPDIR/harness-kit-mine.1" "$LIVE"/*

# 8. A record whose owner is gone and whose group's first process id now belongs to another
# process (another start time) signals nothing, and is dropped.
(python3 -c 'import os, sys, time; os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)' "$WORK/reused.pid" &)
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/reused.pid" ] && break; sleep 0.1; done
PIDS="$PIDS $(cat "$WORK/reused.pid")"
( : ) &
gone=$!
wait "$gone"
mkdir -p "$LIVE"
printf '{"kind":"group","owner":%s,"ownerStart":"Thu Jan  1 00:00:00 1970","pgid":%s,"leaderStart":"Thu Jan  1 00:00:00 1970","command":"sleep"}\n' \
  "$gone" "$(cat "$WORK/reused.pid")" >"$LIVE/group.reused.json"
out="$(node "$TL" sweep 2>&1)"
if alive "$WORK/reused.pid" && [ ! -e "$LIVE/group.reused.json" ] && [ -z "$out" ]; then
  result "time-limit sweep: a record whose process id now has another start time signals nothing and is dropped" yes ""
else
  result "time-limit sweep: a record whose process id now has another start time signals nothing and is dropped" no \
    "the process is $(alive "$WORK/reused.pid" && echo alive || echo gone); record: $(ls "$LIVE"); sweep: $out"
fi

# Helpers for 9 to 11. group NAME: a process leading its own group, sleeping 30 seconds,
# its pid in $WORK/NAME.pid. lstart PID: its start time as the helper reads it. plant DIR
# NAME OWNER PGID LEADER_START: a group record in DIR, owned by OWNER (a dead pid, with a
# start time from 1970), for the group PGID.
group() {
  (python3 -c 'import os, sys, time; os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)' "$WORK/$1.pid" &)
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/$1.pid" ] && break; sleep 0.1; done
  PIDS="$PIDS $(cat "$WORK/$1.pid")"
}
lstart() { ps -o lstart= -p "$1" | sed 's/^ *//; s/ *$//'; }
plant() {
  mkdir -p "$1"
  printf '{"kind":"group","owner":%s,"ownerStart":"Thu Jan  1 00:00:00 1970","pgid":%s,"leaderStart":"%s","command":"sleep"}\n' \
    "$3" "$4" "$5" >"$1/group.$2.json"
}

# 9. HARNESS_KIT_REGISTRY_DIR names the registry: a sweep reads only that folder (a dead
# owner's record for a live group in the default folder is left alone), register writes in
# it, and a relative path is refused. The default sweep then stops that group, so the
# record was one it would act on.
group named
plant "$LIVE" named "$gone" "$(cat "$WORK/named.pid")" "$(lstart "$(cat "$WORK/named.pid")")"
out="$(HARNESS_KIT_REGISTRY_DIR="$WORK/named-reg" node "$TL" sweep 2>&1)"
rec="$(HARNESS_KIT_REGISTRY_DIR="$WORK/named-reg" node "$TL" register --owner $$ path "$WORK/named-path" 2>&1)"
rel="$(HARNESS_KIT_REGISTRY_DIR=relative/reg node "$TL" sweep 2>&1)"
left="$(alive "$WORK/named.pid" && [ -e "$LIVE/group.named.json" ] && echo yes)"
node "$TL" sweep >/dev/null 2>&1
sleep 0.2
if [ "$left" = yes ] && [ -z "$out" ] && [ "$(dirname "$rec")" = "$WORK/named-reg" ] && ! alive "$WORK/named.pid" &&
  [ "$rel" = 'harness-kit time-limit: nothing was swept: HARNESS_KIT_REGISTRY_DIR must be an absolute path, not "relative/reg"' ]; then
  result "time-limit: HARNESS_KIT_REGISTRY_DIR names the registry; the sweep reads only that folder" yes ""
else
  result "time-limit: HARNESS_KIT_REGISTRY_DIR names the registry; the sweep reads only that folder" no \
    "left alone by the named folder's sweep: ${left:-no}; its output: $out; record: $rec; relative: $rel; stopped by the default sweep: $(alive "$WORK/named.pid" && echo no || echo yes)"
fi

# 10. A start time that cannot be read counts as alive, and nothing is signalled: with a ps
# that fails, a live helper's record and group are left alone (a failed read is not another
# process); and a record whose group's first process start time was never read signals
# nothing, even when that first process is gone and the rest of its group lives on.
mkdir -p "$WORK/fakeps" && printf '#!/bin/sh\nexit 1\n' >"$WORK/fakeps/ps" && chmod +x "$WORK/fakeps/ps"
node "$TL" run --limit 60 -- sh -c "echo \$\$ >'$WORK/unread.pid'; sleep 60" &
helper=$!
PIDS="$PIDS $helper"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/unread.pid" ] && break; sleep 0.1; done
before="$(ls "$LIVE" | wc -l | tr -d ' ')"
out="$(PATH="$WORK/fakeps:$PATH" node "$TL" sweep 2>&1)"
after="$(ls "$LIVE" | wc -l | tr -d ' ')"
unread_alive="$(alive "$WORK/unread.pid" && echo yes)"
kill -TERM "$helper" 2>/dev/null
wait "$helper" 2>/dev/null
(python3 -c 'import os, sys, time
os.setsid()
if os.fork() == 0:
    open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(30)
else:
    open(sys.argv[2], "w").write(str(os.getpid()))' "$WORK/member.pid" "$WORK/leader.pid" &)
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/member.pid" ] && [ -s "$WORK/leader.pid" ] && break; sleep 0.1; done
PIDS="$PIDS $(cat "$WORK/member.pid")"
sleep 0.3
plant "$LIVE" unread "$gone" "$(cat "$WORK/leader.pid")" ""
out2="$(node "$TL" sweep 2>&1)"
sleep 0.2
if [ "$unread_alive" = yes ] && [ "$before" = "$after" ] && [ -z "$out" ] && alive "$WORK/member.pid" &&
  [ ! -e "$LIVE/group.unread.json" ] && [ -z "$out2" ]; then
  result "time-limit sweep: a start time that cannot be read counts as alive; nothing is signalled" yes ""
else
  result "time-limit sweep: a start time that cannot be read counts as alive; nothing is signalled" no \
    "with ps failing: the group is $([ "$unread_alive" = yes ] && echo alive || echo gone), records $before before and $after after, sweep: $out
first process never read: the member is $(alive "$WORK/member.pid" && echo alive || echo gone), record: $(ls "$LIVE"), sweep: $out2"
fi

# 11. The registry folder is owner-only: made 0700, and one of this user's made 0755 is
# tightened to 0700. The sweep refuses a folder that is a symbolic link (a dead owner's
# record for a live group behind it is not acted on) or belongs to another user (/usr,
# root's), in one line, and register refuses it too.
mode() { node -e 'console.log((require("fs").lstatSync(process.argv[1]).mode & 0o777).toString(8))' "$1"; }
HARNESS_KIT_REGISTRY_DIR="$WORK/own-new" node "$TL" register --owner $$ path "$WORK/own-path" >/dev/null 2>&1
mkdir "$WORK/own-old" && chmod 755 "$WORK/own-old"
HARNESS_KIT_REGISTRY_DIR="$WORK/own-old" node "$TL" register --owner $$ path "$WORK/own-path" >/dev/null 2>&1
modes="$(mode "$WORK/own-new") $(mode "$WORK/own-old")"
group linked
mkdir -m 700 "$WORK/own-real"
plant "$WORK/own-real" linked "$gone" "$(cat "$WORK/linked.pid")" "$(lstart "$(cat "$WORK/linked.pid")")"
ln -s "$WORK/own-real" "$WORK/own-link"
link_out="$(HARNESS_KIT_REGISTRY_DIR="$WORK/own-link" node "$TL" sweep 2>&1)"
link_left="$(alive "$WORK/linked.pid" && [ -e "$WORK/own-real/group.linked.json" ] && echo yes)"
HARNESS_KIT_REGISTRY_DIR="$WORK/own-real" node "$TL" sweep >/dev/null 2>&1
sleep 0.2
usr_ok=yes usr_out="" usr_reg=""
if [ "$(id -u)" != 0 ]; then
  usr_out="$(HARNESS_KIT_REGISTRY_DIR=/usr node "$TL" sweep 2>&1)"
  usr_reg="$(HARNESS_KIT_REGISTRY_DIR=/usr node "$TL" register --owner $$ path "$WORK/own-path" 2>&1)"
  usr_status=$?
  usr_line="the registry folder /usr is not used: it belongs to user id $(node -e 'console.log(require("fs").statSync("/usr").uid)'), not to this user ($(id -u))"
  [ "$usr_out" = "harness-kit time-limit: $usr_line; nothing was swept" ] && [ "$usr_status" -ne 0 ] &&
    grep -qxF "harness-kit time-limit: not recorded: $usr_line" <<<"$usr_reg" || usr_ok=no
fi
if [ "$modes" = "700 700" ] && [ "$link_left" = yes ] && ! alive "$WORK/linked.pid" && [ "$usr_ok" = yes ] &&
  [ "$link_out" = "harness-kit time-limit: the registry folder $WORK/own-link is not used: it is a symbolic link; nothing was swept" ]; then
  result "time-limit: the registry folder is owner-only, and the sweep refuses one that is a symlink or not this user's" yes ""
else
  result "time-limit: the registry folder is owner-only, and the sweep refuses one that is a symlink or not this user's" no \
    "modes (new, made 0755): $modes; symlink: left alone ${link_left:-no}, stopped through the real folder: $(alive "$WORK/linked.pid" && echo no || echo yes), sweep: $link_out
/usr: sweep: $usr_out; register: $usr_reg"
fi

# ---------------------------------------------------------------------------------------
# check-limits.mjs, on folders of made-up scripts.
# ---------------------------------------------------------------------------------------
CL="$SCRIPTS/check-limits.mjs"
fixture() {
  local dir="$WORK/fixture-$1"
  mkdir -p "$dir"
  cat >"$dir/$2"
  echo "$dir"
}

# 9. Long work in a .sh and a .mjs file without the helper fails, naming the file and line;
# the same through the helper passes, as do words in comments and quoted text.
dir="$(fixture bare run.sh <<'EOF'
#!/usr/bin/env bash
# claude -p "in a comment" and gh run watch 1 are not calls
echo "gh run watch and /bin/sh -c are only words here"
claude -p "Review" --output-format json <in >out
x="$(gh run watch "$id" --exit-status)"
/bin/sh -c "$check" </dev/null
EOF
)"
cat >"$dir/run.mjs" <<'EOF'
import { spawnSync } from "node:child_process";
const r = /x/.exec("x");
const a = spawnSync("/bin/sh", ["-c", check]);
const b = spawnSync(command, { shell: true });
EOF
bare="$(node "$CL" "$dir" 2>&1)"
bare_status=$?
wrapped="$(fixture wrapped run.sh <<'EOF'
#!/usr/bin/env bash
. limit-lib.sh
hk_limited review reviewer claude -p "Review" --output-format json <in >out
x="$(hk_limited ci-run release.sh gh run watch "$id" --exit-status)"
hk_limited --merge check land.sh /bin/sh -c "$check" </dev/null
node "$HK_LIMIT_JS" run --limit init --name upgrade.sh -- \
  claude -p "ok" &
EOF
)"
cat >"$wrapped/run.mjs" <<'EOF'
import { runLimited } from "./time-limit.mjs";
const a = await runLimited("/bin/sh", ["-c", check], { limit: 5 });
// no-limit: a made-up reason for this test
const b = spawnSync("gh", ["run", "list"]);
EOF
good="$(node "$CL" "$wrapped" 2>&1)"
good_status=$?
want="$dir/run.mjs:3: spawns /bin/sh without the time-limit helper (startLimited, runLimited) or a no-limit comment with a reason: const a = spawnSync(\"/bin/sh\", [\"-c\", check]);
$dir/run.mjs:4: runs a shell without the time-limit helper (startLimited, runLimited) or a no-limit comment with a reason: const b = spawnSync(command, { shell: true });
$dir/run.sh:4: starts claude without the time-limit helper (hk_limited, hk_git_net) or a no-limit comment with a reason: claude -p \"Review\" --output-format json <in >out
$dir/run.sh:5: calls gh without the time-limit helper (hk_limited, hk_git_net) or a no-limit comment with a reason: x=\"\$(gh run watch \"\$id\" --exit-status)\"
$dir/run.sh:6: runs a command line (sh -c) without the time-limit helper (hk_limited, hk_git_net) or a no-limit comment with a reason: /bin/sh -c \"\$check\" </dev/null"
if [ "$bare_status" -eq 1 ] && [ "$bare" = "$want" ] && [ "$good_status" -eq 0 ]; then
  result "check-limits: a bare claude -p, gh run watch or check-command run fails, naming the file and line" yes ""
else
  result "check-limits: a bare claude -p, gh run watch or check-command run fails, naming the file and line" no \
    "bare (exit $bare_status):
$bare
wrapped (exit $good_status):
$good"
fi

# 10. A bare git push, fetch or ls-remote fails, naming the file and line; through hk_git_net
# it passes, and so does a git command that is not a network one, or git push in a string.
dir="$(fixture git ship.sh <<'EOF'
#!/usr/bin/env bash
git push -q -u "$REMOTE" "$branch"
HARNESS_KIT_SHIP=1 git push -q "$REMOTE" "$base" || stop x "git push failed"
git -C "$work/upstream" fetch -q --no-tags "$url"
tag="$(git ls-remote --tags origin | awk 'END { print $1 }')"
hk_git_net ship.sh fetch -q "$REMOTE" "$base"
git commit -q -m "message: git push later"
echo "git push --no-verify skips this hook"
EOF
)"
got="$(node "$CL" "$dir" 2>&1)"
status=$?
lines="$(cut -d: -f2 <<<"$got" | tr '\n' ' ')"
if [ "$status" -eq 1 ] && [ "$lines" = "2 3 4 5 " ] && [ "$(grep -c 'runs a git network command without the time-limit helper' <<<"$got")" = 4 ]; then
  result "check-limits: a bare git push, fetch or ls-remote fails, naming the file and line" yes ""
else
  result "check-limits: a bare git push, fetch or ls-remote fails, naming the file and line" no "exit $status:
$got"
fi

# 11. A no-limit comment without a reason fails, even where it would excuse a call.
dir="$(fixture marker approve.sh <<'EOF'
#!/usr/bin/env bash
# no-limit:
/bin/sh -c "$approve"
# no-limit: the approval command waits for the person
/bin/sh -c "$approve"
EOF
)"
got="$(node "$CL" "$dir" 2>&1)"
status=$?
if [ "$status" -eq 1 ] && [ "$(wc -l <<<"$got" | tr -d ' ')" = 1 ] &&
  [ "$got" = "$dir/approve.sh:2: a no-limit comment needs a reason after the colon: # no-limit:" ]; then
  result "check-limits: a no-limit marker without a reason fails" yes ""
else
  result "check-limits: a no-limit marker without a reason fails" no "exit $status:
$got"
fi

# 12. A script with mktemp and no hk_on_exit fails; with hk_on_exit it passes.
dir="$(fixture temp one.sh <<'EOF'
#!/usr/bin/env bash
tmp="$(mktemp "${TMPDIR:-/tmp}/x.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
EOF
)"
cat >"$dir/two.sh" <<'EOF'
#!/usr/bin/env bash
. limit-lib.sh
hk_on_exit
RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/kept.XXXXXX")"
EOF
got="$(node "$CL" "$dir" 2>&1)"
status=$?
if [ "$status" -eq 1 ] && [ "$got" = "$dir/one.sh:2: makes a temporary file with mktemp but sets no cleanup with hk_on_exit: tmp=\"\$(mktemp \"\${TMPDIR:-/tmp}/x.XXXXXX\")\"" ]; then
  result "check-limits: a script with mktemp and no hk_on_exit fails" yes ""
else
  result "check-limits: a script with mktemp and no hk_on_exit fails" no "exit $status:
$got"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures time-limit case(s) failed"
  exit 1
fi
