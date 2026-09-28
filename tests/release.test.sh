#!/usr/bin/env bash
# Tests for release.sh: check, push the branch, wait for CI, fast-forward the base and push
# it with the tag, for a repository not reviewed through ship.sh.
#
# Every case runs in a temporary git repository whose "origin" is a local bare repository.
# release.sh finds a FAKE `gh` first on PATH (the same as tests/ship.test.sh's: canned run
# JSON, the conclusion in $FAKE_LOG/conclusion), a fake osascript that records calls, and a
# fake uname ($FAKE_UNAME). Nothing touches GitHub. Prints one PASS or FAIL line per case
# and exits non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/harness-kit/scripts"
RELEASE="$SCRIPTS/release.sh"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
failures=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export SHIP_POLL_SECONDS=0 SHIP_CI_APPEAR_SECONDS=0
unset FAKE_UNAME

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

describe() { printf 'exit %s\nstderr: %s\ngh calls: %s' "$STATUS" "$ERR" "$(cat "$DIR.log/gh-calls" 2>/dev/null)"; }

mkdir -p "$WORK/bin"
cat >"$WORK/bin/osascript" <<'FAKE'
#!/bin/sh
printf '%s ' "$@" >>"$FAKE_LOG/osascript-calls"
echo >>"$FAKE_LOG/osascript-calls"
FAKE
cat >"$WORK/bin/uname" <<'FAKE'
#!/bin/sh
if [ -n "${FAKE_UNAME:-}" ]; then echo "$FAKE_UNAME"; else exec /usr/bin/uname "$@"; fi
FAKE
cat >"$WORK/bin/gh" <<'FAKE'
#!/usr/bin/env node
const fs = require("fs");
const log = process.env.FAKE_LOG;
const args = process.argv.slice(2);
fs.appendFileSync(`${log}/gh-calls`, args.join(" ") + "\n");
const read = (f) => { try { return fs.readFileSync(`${log}/${f}`, "utf8").trim(); } catch { return ""; } };
const run = { databaseId: 4242, workflowName: "validate", status: "completed", conclusion: read("conclusion"),
  url: "https://ci.example.invalid/runs/4242" };
const sub = `${args[0]} ${args[1]}`;
if (sub === "run list") console.log(JSON.stringify([run]));
else if (sub === "run watch") process.exit(run.conclusion === "success" ? 0 : 1);
else if (sub === "run view") console.log(JSON.stringify({ status: run.status, conclusion: run.conclusion, url: run.url }));
else { console.error(`fake gh: unexpected call: ${args.join(" ")}`); process.exit(64); }
FAKE
chmod +x "$WORK/bin/osascript" "$WORK/bin/uname" "$WORK/bin/gh"

# new_repo NAME: main pushed to the bare origin NAME.git; a check command that runs
# scripts/check.sh with --skip-reviewed (it records its runs, and exits 1 when
# $DIR.log/red exists); a branch "next" with one more commit, not pushed. Prints its path.
new_repo() {
  local dir="$WORK/$1" bare="$WORK/$1.git"
  git init -q --bare "$bare"
  mkdir -p "$dir/.harness" "$dir/scripts" "$dir.log"
  git -C "$dir" init -q -b main
  printf 'v1\n' >"$dir/app.txt"
  printf 'echo run >>"%s/check-runs"; [ ! -e "%s/red" ] || { echo "FAIL unit: 1 failed"; exit 1; }; echo "all checks passed"\n' "$dir.log" "$dir.log" >"$dir/scripts/check.sh"
  printf 'sh scripts/check.sh --skip-reviewed\n' >"$dir/.harness/check-command"
  git -C "$dir" add -A && git -C "$dir" commit -q -m "main: initial"
  git -C "$dir" remote add origin "$bare"
  git -C "$dir" push -q -u origin main
  git -C "$dir" checkout -q -b next
  printf 'v2\n' >"$dir/app.txt"
  git -C "$dir" commit -q -am "next: v2"
  echo "$dir"
}

# run_release DIR CONCLUSION TAG: release.sh in DIR, with a fresh fake log.
run_release() {
  DIR="$1"
  rm -f "$DIR.log/gh-calls" "$DIR.log/osascript-calls" "$DIR.log/check-runs"
  printf '%s\n' "$2" >"$DIR.log/conclusion"
  (cd "$DIR" && PATH="$WORK/bin:$PATH" FAKE_LOG="$DIR.log" bash "$RELEASE" "$3" >/dev/null 2>"$WORK/stderr")
  STATUS=$?
  ERR="$(cat "$WORK/stderr")"
}

rev() { git -C "$1" rev-parse -q --verify "$2" 2>/dev/null; }
remote() { git --git-dir="$1.git" rev-parse -q --verify "$2" 2>/dev/null; }

# 1. Green: the check runs once, the branch is pushed, CI is waited for, main is
# fast-forwarded and pushed with the tag (at the branch's head) through the pre-push hook,
# and the person ends on main. On macOS a notification says RELEASED; the event log has it.
# In the same repository, with the same hook, a plain git push to main is refused.
dir="$(new_repo green)"
(cd "$dir" && bash "$SCRIPTS/install-hooks.sh" 2>/dev/null)
head="$(rev "$dir" HEAD)"
FAKE_UNAME=Darwin run_release "$dir" success v1.2.3
if [ "$STATUS" -eq 0 ] && grep -q 'RELEASED: next' <<<"$ERR" && [ "$(wc -l <"$dir.log/check-runs" | tr -d ' ')" = 1 ] &&
  [ "$(remote "$dir" refs/heads/next)" = "$head" ] && [ "$(remote "$dir" refs/heads/main)" = "$head" ] &&
  [ "$(remote "$dir" 'refs/tags/v1.2.3^{commit}')" = "$head" ] && [ "$(rev "$dir" main)" = "$head" ] &&
  [ "$(git -C "$dir" symbolic-ref --short HEAD)" = main ] && grep -q "run list --commit $head" "$dir.log/gh-calls" &&
  grep -q 'harness-kit release.sh RELEASED: v1.2.3' "$dir.log/osascript-calls" &&
  [ "$(cut -f2,3,5,6 "$dir/.git/harness-kit/events.tsv")" = "$(printf 'release.sh\tnext\tRELEASED\tv1.2.3')" ]; then
  released=yes
else
  released="$(describe)"
fi
printf 'v3\n' >"$dir/app.txt" && git -C "$dir" commit -q --no-verify -am "main: by hand"
plain="$(git -C "$dir" push -q origin main 2>&1)"
plain_status=$?
if [ "$released" = yes ] && [ "$plain_status" -ne 0 ] &&
  grep -q 'harness-kit pre-push: refusing to push to main: push through ship.sh' <<<"$plain" &&
  [ "$(remote "$dir" refs/heads/main)" = "$head" ]; then
  result "release.sh: green: checks, pushes the branch, waits for CI, pushes main and the tag through the pre-push hook" yes ""
else
  result "release.sh: green: checks, pushes the branch, waits for CI, pushes main and the tag through the pre-push hook" no "release: $released
plain push of main ($plain_status): $plain"
fi

# 2. A failing check: stops before pushing anything; nothing on the remote moves.
dir="$(new_repo red-check)"
touch "$dir.log/red"
main_before="$(rev "$dir" main)"
FAKE_UNAME=Darwin run_release "$dir" success v1.2.3
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: the check failed (exit 1, above): sh scripts/check.sh --skip-reviewed. Nothing was pushed.' <<<"$ERR" &&
  grep -q '^FAIL unit: 1 failed' <<<"$ERR" && [ -z "$(remote "$dir" refs/heads/next)" ] && [ ! -e "$dir.log/gh-calls" ] &&
  [ "$(remote "$dir" refs/heads/main)" = "$main_before" ] && [ -z "$(rev "$dir" refs/tags/v1.2.3)" ] &&
  grep -q 'STOPPED: the check failed' "$dir.log/osascript-calls"; then
  result "release.sh: a failing check stops it before any push" yes ""
else
  result "release.sh: a failing check stops it before any push" no "$(describe)"
fi

# 3. Red CI: the branch is pushed, then it stops with the run's URL; main and the tag are
# untouched. Re-run once CI is green, it releases.
dir="$(new_repo red-ci)"
main_before="$(rev "$dir" main)"
run_release "$dir" failure v1.2.3
red="$(describe)"
red_ok=no
if [ "$STATUS" -eq 1 ] && grep -q 'CI run 4242 finished with conclusion "failure", not success: https://ci.example.invalid/runs/4242' <<<"$ERR" &&
  grep -q 're-run release.sh' <<<"$ERR" && [ "$(remote "$dir" refs/heads/next)" = "$(rev "$dir" next)" ] &&
  [ "$(remote "$dir" refs/heads/main)" = "$main_before" ] && [ "$(rev "$dir" main)" = "$main_before" ] &&
  [ -z "$(rev "$dir" refs/tags/v1.2.3)" ] && [ "$(git -C "$dir" symbolic-ref --short HEAD)" = next ]; then
  red_ok=yes
fi
run_release "$dir" success v1.2.3
if [ "$red_ok" = yes ] && [ "$STATUS" -eq 0 ] && [ "$(remote "$dir" refs/heads/main)" = "$(rev "$dir" next)" ]; then
  result "release.sh: red CI stops it with the run's URL, main and tag untouched; a re-run releases" yes ""
else
  result "release.sh: red CI stops it with the run's URL, main and tag untouched; a re-run releases" no "red: $red
re-run: $(describe)"
fi

# 4. Refusals, with nothing run or pushed: on main, uncommitted changes, a tag that exists
# at another commit (locally, or only on origin), and a tag name git refuses.
dir="$(new_repo refusals)"
git -C "$dir" checkout -q main
run_release "$dir" success v1.2.3
on_main="$STATUS: $ERR"
git -C "$dir" checkout -q next
printf 'dirty\n' >>"$dir/app.txt"
run_release "$dir" success v1.2.3
dirty="$STATUS: $ERR"
git -C "$dir" checkout -q -- app.txt
git -C "$dir" tag v0.9.0 main
run_release "$dir" success v0.9.0
tag_here="$STATUS: $ERR"
git -C "$dir" push -q origin v0.9.0 && git -C "$dir" tag -d v0.9.0 >/dev/null
run_release "$dir" success v0.9.0
tag_there="$STATUS: $ERR"
run_release "$dir" success 'bad..tag'
bad_tag="$STATUS: $ERR"
if grep -q '^2: .*REFUSED: you are on main' <<<"$on_main" &&
  grep -q '^2: .*REFUSED: there are uncommitted changes' <<<"$dirty" &&
  grep -q '^2: .*REFUSED: the tag v0.9.0 already exists here at' <<<"$tag_here" &&
  grep -q '^2: .*REFUSED: the tag v0.9.0 already exists on origin at' <<<"$tag_there" &&
  grep -q '^2: .*REFUSED: "bad..tag" is not a tag name git accepts' <<<"$bad_tag" &&
  [ ! -e "$dir.log/check-runs" ] && [ ! -e "$dir.log/gh-calls" ] && [ -z "$(remote "$dir" refs/heads/next)" ]; then
  result "release.sh: refuses on main, with uncommitted changes, or with a tag elsewhere or malformed" yes ""
else
  result "release.sh: refuses on main, with uncommitted changes, or with a tag elsewhere or malformed" no "on main: $on_main
dirty: $dirty
tag here: $tag_here
tag on origin: $tag_there
bad tag: $bad_tag"
fi

# 5. main moved on origin: it stops before touching main or making the tag.
dir="$(new_repo moved)"
other="$WORK/moved-other"
git clone -q -b main "$WORK/moved.git" "$other"
printf 'elsewhere\n' >"$other/other.txt"
git -C "$other" add -A && git -C "$other" commit -q -m "main moved" && git -C "$other" push -q origin main
moved_main="$(remote "$dir" refs/heads/main)"
run_release "$dir" success v1.2.3
if [ "$STATUS" -eq 1 ] && grep -q 'STOPPED: origin/main has commits that next does not, so main cannot fast-forward' <<<"$ERR" &&
  [ "$(remote "$dir" refs/heads/main)" = "$moved_main" ] && [ -z "$(rev "$dir" refs/tags/v1.2.3)" ] &&
  [ "$(git -C "$dir" symbolic-ref --short HEAD)" = next ]; then
  result "release.sh: a base that cannot fast-forward stops it before main or the tag move" yes ""
else
  result "release.sh: a base that cannot fast-forward stops it before main or the tag move" no "$(describe)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures release case(s) failed"
  exit 1
fi
