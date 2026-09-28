#!/usr/bin/env bash
# Review, push, wait for CI and fast-forward the base branch: the person's last step.
#
#   ship.sh        run from anywhere inside the project's git repository, on the branch
#
# For people, in their own terminal: review.sh spends real money, and this pushes. In order,
# stopping at the first failure with a message saying what to do:
#   1. Refuse on the base branch (.harness/review-base, first line, default main), on a
#      detached HEAD, or with uncommitted changes to tracked files (.harness/reviews.tsv
#      excepted: review.sh writes it). Untracked files, such as .reports/, do not count.
#   2. If check-reviewed.mjs does not pass for the branch's current diff, and the working
#      tree's .harness/reviews.tsv has no PASS for it yet, first run the project's check:
#      the first line of .harness/check-command, as it is. That line must carry
#      --skip-reviewed as a word, as land.sh requires (the branch is not reviewed yet, so the
#      review check would fail); ship.sh never adds it. A missing flag or a failing check
#      stops here, before any review is started (a review costs money). With no
#      check-command there is nothing to run, as in review.sh. The check's output (stdout
#      and stderr together) is shown and saved, with the command, HEAD and working tree it
#      ran on, and review.sh reuses it (HARNESS_KIT_CHECK_SAVED) instead of running the
#      check again. Then run review.sh; a verdict other than PASS stops here, and the
#      verdict is shown.
#   3. If .harness/reviews.tsv changed, commit it alone: "Record review of <branch>: PASS".
#      Then check-reviewed.mjs must pass at HEAD.
#   4. Push the branch to origin.
#   5. Find the CI runs for the pushed head commit (gh run list --commit), waiting up to
#      SHIP_CI_APPEAR_SECONDS (default 180) for the first to appear; wait for each to
#      finish (gh run watch), then read its conclusion (gh run view). Anything but
#      "success" stops, printing the run's URL. Which runs:
#        - with .harness/ci-workflow (optional; first line, the workflow as
#          `gh run list --workflow` takes it): that workflow's runs only, waiting for one to
#          appear even when other workflows' runs appeared first;
#        - without it: every run listed for the commit when the first one appears. A
#          workflow that starts later than that is not waited for.
#   6. Check that the base can fast-forward (origin/<base> and <base> are both in the
#      branch), switch to the base, `git merge --ff-only <branch>`, push the base with
#      HARNESS_KIT_SHIP=1 set (the pre-push hook from install-hooks.sh refuses any other
#      push to the base), and delete the branch's report and commit draft (.reports/,
#      report-path.sh --name).
# It never forces a push, never rewrites history, and never deletes the branch.
#
# THE NOTIFICATION. On macOS, each STOPPED and the SHIPPED also show a notification
# (osascript `display notification`), as a ship waits minutes for CI. Refusals come at once,
# so they do not. Not on macOS (uname -s is not Darwin), nothing is shown.
#
# THE EVENT LOG. Each stop and each refusal (event STOPPED; a refusal's reason starts
# "refused-", such as refused-on-base, and a stop's is short, such as check-failed,
# review-not-pass or ci-not-green), with its message, and each SHIPPED, is appended to the
# local event log, .git/harness-kit/events.tsv (events.sh has the format), on the branch
# being shipped. Outside a git repository nothing is recorded.
#
# RESUMABLE. Re-running after a stop continues where it stopped. Steps 1-5 are worked out
# from git and GitHub again each time and cost nothing when already done: a recorded PASS
# is not reviewed again, pushing a pushed branch does nothing, and a finished CI run is
# read, not re-run. Step 6 leaves the branch, so before switching ship.sh writes the
# branch and its head to <git dir>/harness-kit-ship; run on the base branch with that
# file present, ship.sh finishes step 6 for that branch. The file is removed when the ship
# is done, or ignored and removed if the branch has moved since.
#
# Exit status: 0 shipped; 1 stopped (re-run after doing what the message says); 2 refused.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE=origin
APPEAR="${SHIP_CI_APPEAR_SECONDS:-180}"
POLL="${SHIP_POLL_SECONDS:-10}"

# shellcheck source=events.sh
. "$HERE/events.sh"

say() { echo "harness-kit ship.sh: $*" >&2; }
# notify MESSAGE: a macOS notification (osascript), so a person who looked away while CI ran
# sees the end. Skipped when not on macOS; a failure is ignored.
notify() {
  [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "harness-kit ship.sh" "$1" >/dev/null 2>&1 || true
}
# refuse REASON MESSAGE and stop REASON MESSAGE: record the stop in the event log (on the
# branch being shipped, once known), print it, and exit 2 or 1. A stop also notifies.
refuse() { harness_event ship.sh "${branch:-}" STOPPED "$1" "REFUSED: $2"; say "REFUSED: $2"; exit 2; }
stop() { harness_event ship.sh "${branch:-}" STOPPED "$1" "$2"; say "STOPPED: $2"; notify "STOPPED: $2"; exit 1; }

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse refused-not-a-repository "not inside a git repository"
cd "$PROJECT" || exit 2
STATE="$(git rev-parse --path-format=absolute --git-path harness-kit-ship)"
REVIEWS=.harness/reviews.tsv
base="$( { [ -f .harness/review-base ] && head -n 1 .harness/review-base; } | tr -d '\r' | tr -d '[:space:]')"
base="${base:-main}"

dirty() { git status --porcelain --untracked-files=no -- . ":(exclude)$REVIEWS"; }

# gh prints JSON; node reads it. FIELD of the first element of a JSON array, or of an object.
json_field() {
  node -e '
    let v = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (Array.isArray(v)) v = v[0] ?? {};
    const x = v[process.argv[1]];
    process.stdout.write(x === undefined || x === null ? "" : String(x));
  ' "$1"
}

# Step 6. Uses $branch and $head.
finish() {
  local report draft
  printf '%s\t%s\n' "$branch" "$head" >"$STATE" || stop state-file "cannot write $STATE"
  if [ "$(git symbolic-ref --short -q HEAD)" != "$base" ]; then
    git checkout -q "$base" || stop checkout-failed "could not switch to $base. Fix what git says, then re-run ship.sh (on $base or $branch)."
  fi
  git merge -q --ff-only "$branch" ||
    stop base-not-fast-forward "$base cannot fast-forward to $branch. You are on $base; nothing was pushed to it. Bring $branch up to date with $base, then re-run ship.sh on $branch."
  # HARNESS_KIT_SHIP=1: the pre-push hook (install-hooks.sh) lets this push of the base through.
  HARNESS_KIT_SHIP=1 git push -q "$REMOTE" "$base" ||
    stop push-base-failed "pushing $base failed (above). You are on $base, which is merged locally and not pushed. Fix the cause, then re-run ship.sh on $base to push it."
  report="$(bash "$HERE/report-path.sh" --name "$branch")" && rm -f -- "$report"
  draft="$(bash "$HERE/report-path.sh" --name "$branch" --commit)" && rm -f -- "$draft"
  rm -f -- "$STATE"
  harness_event ship.sh "$branch" SHIPPED "$base" "merged $(git rev-parse --short "$head") into $base and pushed it"
  say "SHIPPED: $branch ($(git rev-parse --short "$head")) is merged into $base and pushed; its report and commit draft were deleted. You are on $base."
  notify "SHIPPED: $branch is merged into $base and pushed."
  exit 0
}

# ---------------------------------------------------------------------------------------
# A ship that stopped after leaving its branch.
# ---------------------------------------------------------------------------------------
current="$(git symbolic-ref --short -q HEAD)" || refuse refused-detached "HEAD is detached; check out the branch to ship"
if [ -f "$STATE" ]; then
  IFS=$'\t' read -r branch head <"$STATE"
  if [ "$(git rev-parse -q --verify "refs/heads/$branch")" != "$head" ]; then
    say "an earlier ship of $branch stopped, but $branch has moved since; starting again"
    rm -f -- "$STATE"
  elif [ "$current" = "$base" ] || [ "$current" = "$branch" ]; then
    [ -z "$(dirty)" ] || refuse refused-uncommitted "there are uncommitted changes (git status); commit or stash them first"
    say "continuing the ship of $branch: CI passed for $(git rev-parse --short "$head"); merging into $base"
    finish
  else
    refuse refused-ship-in-progress "a ship of $branch is in progress (it stopped while merging into $base). Run ship.sh on $base to finish it, or delete $STATE to abandon it."
  fi
fi

# ---------------------------------------------------------------------------------------
# 1. Where we are.
# ---------------------------------------------------------------------------------------
branch="$current"
[ "$branch" != "$base" ] || refuse refused-on-base "you are on $base; check out the branch to ship"
[ -z "$(dirty)" ] || refuse refused-uncommitted "there are uncommitted changes (git status); commit or stash them first"

# ---------------------------------------------------------------------------------------
# 2-3. The review.
# ---------------------------------------------------------------------------------------
if node "$HERE/check-reviewed.mjs" >/dev/null 2>&1; then
  say "the branch's current diff already has a committed PASS review"
  [ -z "$(git status --porcelain --untracked-files=all -- "$REVIEWS")" ] ||
    say "note: $REVIEWS has uncommitted lines that this ship does not need; they are left as they are"
else
  state="$(node "$HERE/check-reviewed.mjs" --hash)" || stop diff-failed "could not work out the branch's diff: $state"
  hash="$(cut -f3 <<<"$state")"
  pending="$( [ -f "$REVIEWS" ] && awk -F'\t' -v h="$hash" 'NF == 9 && $5 == h { v = $6 } END { print v }' "$REVIEWS")"
  if [ "$pending" = PASS ]; then
    say "$REVIEWS already has an uncommitted PASS for this diff; not reviewing again"
  else
    check="$( { [ -f .harness/check-command ] && head -n 1 .harness/check-command; } | tr -d '\r')"
    if [ -z "$check" ]; then
      say "no .harness/check-command, so there is no check to run before the review"
    else
      grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check" ||
        stop no-skip-reviewed "the first line of .harness/check-command does not pass --skip-reviewed, so it would run the review check, which cannot pass before the review. No review was started. Add the flag where the project's check reads it (for a single command: $(sed -E 's/[[:space:]]+$//' <<<"$check") --skip-reviewed), commit, then re-run ship.sh."
      say "running the check before the review: $check"
      # Its output (stdout and stderr together) is saved with what it ran on, and review.sh
      # reuses it instead of running the check again.
      saved="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-ship-check.XXXXXX")" || stop temp-file "cannot make a temporary folder"
      trap 'rm -rf "$saved"' EXIT
      printf '%s\n' "$check" >"$saved/command"
      git rev-parse HEAD >"$saved/head"
      git status --porcelain --untracked-files=all >"$saved/tree"
      { /bin/sh -c "$check" </dev/null 2>&1; echo $? >"$saved/status"; } | tee "$saved/output"
      status="$(cat "$saved/status")"
      [ "$status" -eq 0 ] ||
        stop check-failed "the check failed (exit $status, above): $check. No review was started. Fix what it reports, commit, then re-run ship.sh."
    fi
    say "no PASS review for the branch's current diff; running review.sh"
    HARNESS_KIT_CHECK_SAVED="${saved:-}" bash "$HERE/review.sh"
    status=$?
    if [ "$status" -ne 0 ]; then
      verdict="$( [ -f "$REVIEWS" ] && awk -F'\t' -v h="$hash" 'NF == 9 && $5 == h { v = $6 " (" $7 ")" } END { print v }' "$REVIEWS")"
      if [ -n "$verdict" ]; then
        stop review-not-pass "the review's verdict is $verdict, not PASS (the review is above; its line is in $REVIEWS, uncommitted). Fix what it reports, commit, then re-run ship.sh."
      fi
      stop review-failed "the review did not complete (review.sh exit $status, above), so there is no verdict. Fix the cause, then re-run ship.sh."
    fi
  fi
  if [ -n "$(git status --porcelain --untracked-files=all -- "$REVIEWS")" ]; then
    git add -- "$REVIEWS" && git commit -q -m "Record review of $branch: PASS" -- "$REVIEWS" ||
      stop commit-review-failed "could not commit $REVIEWS (above). Commit it yourself, then re-run ship.sh."
    say "committed $REVIEWS: Record review of $branch: PASS"
  fi
  out="$(node "$HERE/check-reviewed.mjs" 2>&1)" || stop check-reviewed-failed "check-reviewed still fails at HEAD: $out"
fi
head="$(git rev-parse HEAD)"

# ---------------------------------------------------------------------------------------
# 4. Push the branch.
# ---------------------------------------------------------------------------------------
git push -q -u "$REMOTE" "$branch" || stop push-branch-failed "pushing $branch to $REMOTE failed (above). Fix the cause, then re-run ship.sh."
say "pushed $branch ($(git rev-parse --short "$head")) to $REMOTE"

# ---------------------------------------------------------------------------------------
# 5. CI for the pushed head.
# ---------------------------------------------------------------------------------------
fields=databaseId,status,conclusion,url,workflowName
workflow="$( { [ -f .harness/ci-workflow ] && head -n 1 .harness/ci-workflow; } | tr -d '\r')"
workflow="${workflow#"${workflow%%[![:space:]]*}"}"
workflow="${workflow%"${workflow##*[![:space:]]}"}"
filter=()
what="CI run"
if [ -n "$workflow" ]; then
  filter=(--workflow "$workflow")
  what="run of the workflow \"$workflow\" (.harness/ci-workflow)"
fi
waited=0
while :; do
  # ${filter[@]+...}: an empty array is "unbound" under set -u in bash 3.2 (macOS).
  runs="$(gh run list --commit "$head" ${filter[@]+"${filter[@]}"} --json "$fields" --limit 50)" ||
    stop gh-failed "gh run list failed (above). Fix gh (gh auth status), then re-run ship.sh."
  ids="$(node -e 'for (const r of JSON.parse(require("fs").readFileSync(0, "utf8"))) console.log(r.databaseId)' <<<"$runs")" ||
    stop gh-failed "gh run list did not print the expected JSON: $runs"
  [ -z "$ids" ] || break
  [ "$waited" -lt "$APPEAR" ] ||
    stop no-ci-run "no $what for $(git rev-parse --short "$head") appeared within ${APPEAR}s. Check that it runs on pushes to $branch, then re-run ship.sh to keep waiting."
  say "waiting for a $what to start for $(git rev-parse --short "$head")..."
  sleep "$POLL"
  waited=$((waited + POLL))
done
for id in $ids; do
  say "waiting for CI run $id to finish..."
  gh run watch "$id" --exit-status --compact --interval "$POLL" >&2
  run="$(gh run view "$id" --json status,conclusion,url)" || stop gh-failed "gh run view $id failed (above). Re-run ship.sh to check the run again."
  status="$(json_field status <<<"$run")"
  conclusion="$(json_field conclusion <<<"$run")"
  url="$(json_field url <<<"$run")"
  [ "$status" = completed ] ||
    stop ci-not-finished "CI run $id is $status, not finished: $url. Re-run ship.sh to keep waiting."
  [ "$conclusion" = success ] ||
    stop ci-not-green "CI run $id finished with conclusion \"$conclusion\", not success: $url. Fix the branch (or re-run the job if it was not the branch's fault), then re-run ship.sh."
  say "CI run $id passed: $url"
done

# ---------------------------------------------------------------------------------------
# 6. Merge into the base, push it, delete the report and the commit draft.
# ---------------------------------------------------------------------------------------
git fetch -q "$REMOTE" "$base" || stop fetch-failed "could not fetch $base from $REMOTE (above). Re-run ship.sh."
for ref in "refs/remotes/$REMOTE/$base" "refs/heads/$base"; do
  if git rev-parse -q --verify "$ref" >/dev/null && ! git merge-base --is-ancestor "$ref" "$head"; then
    stop base-not-fast-forward "${ref#refs/*/} has commits that $branch does not, so $base cannot fast-forward. Bring $branch up to date with $base (it will need a new review and CI), then re-run ship.sh."
  fi
done
finish
