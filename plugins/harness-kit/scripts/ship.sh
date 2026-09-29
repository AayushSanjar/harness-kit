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
#      tree's .harness/reviews.tsv has no PASS for it yet:
#      a. THE BRIEF (brief-lib.sh). The branch's brief, .reports/<branch>.brief.md (written
#         by /harness-kit:brief <goal>), must exist, and its approval,
#         .reports/<branch>.brief.approved (written by approve-brief.sh when the person
#         answers y), must hold the brief's sha256 as it is now. Otherwise ship.sh stops
#         here, before the index, the check and the review, printing the exact fix: no
#         brief (run /harness-kit:brief, then approve-brief.sh), no approval (run approve-brief.sh), or
#         a brief changed since its approval (read it again and run approve-brief.sh). The
#         one opt-out is the person's, per project: a committed .harness/brief-optional
#         that HEAD's .harness/protected-paths lists (brief_optional). With it, a branch
#         with no brief goes on; a brief that is there must still be approved as it is.
#         A brief-optional that is not committed or not protected is not honoured, and the
#         stop says why.
#      b. THE INDEX. With .harness/index-command (optional; its first line, run as it is in
#         the project root), run it: it regenerates the project's index (such as a
#         decisions index built from the commits' Decision: lines) and must change nothing
#         when the index is up to date. If it changed or added files, the index was stale:
#         ship.sh commits exactly those files (.harness/reviews.tsv never), with the
#         message "Refresh the index (.harness/index-command)" and a body naming each file
#         with its reason, so the commit-msg hook passes it and the review sees the index.
#         A failing command, or a commit the hook refuses, stops here. The index must be a
#         tracked file, or a new one: a change to a file that was already untracked is not
#         seen. It runs only before a review, never for a diff already reviewed, so an
#         index that also lists ship.sh's own commits cannot start a review loop.
#      c. Run the project's check:
#      the first line of .harness/check-command, as it is. That line must carry
#      --skip-reviewed as a word, as land.sh requires (the branch is not reviewed yet, so the
#      review check would fail); ship.sh never adds it. A missing flag or a failing check
#      stops here, before any review is started (a review costs money). With no
#      check-command there is nothing to run, as in review.sh. The check's output (stdout
#      and stderr together) is shown and saved, with the command, HEAD and working tree it
#      ran on, and review.sh reuses it (HARNESS_KIT_CHECK_SAVED) instead of running the
#      check again.
#      d. Run review.sh (its input holds the brief and whether its approval matches). When
#         it records a verdict, whatever it is, ship.sh commits .harness/reviews.tsv alone,
#         with the message "Record review of <branch>: <verdict>" and a body naming
#         .harness/reviews.tsv with its reason (so the commit-msg hook passes it, and
#         nobody commits the line by hand). A verdict other than PASS then stops here, and
#         the verdict is shown.
#   3. If .harness/reviews.tsv still has an uncommitted PASS for the diff (an earlier run
#      recorded it), commit it the same way. Then check-reviewed.mjs must pass at HEAD.
#   4. Push the branch to origin.
#   5. Wait for CI (ci-lib.sh's ci_wait): the runs for the pushed head commit, waiting up
#      to SHIP_CI_APPEAR_SECONDS (default 180) for the first to appear, each until it
#      finishes; a completed run with any conclusion but "success" stops, printing the
#      run's URL. With .harness/ci-workflow (optional; first line, the workflow as `gh run
#      list --workflow` takes it), only that workflow's runs. It fails closed: a gh error,
#      or gh output that is not the JSON expected, is retried (SHIP_GH_TRIES tries in all,
#      default 3, SHIP_GH_RETRY_SECONDS apart, default 10), then stops with "CI result
#      unknown" (reason ci-unknown), the run's URL and how to resume, before the merge.
#   6. Check that the base can fast-forward (origin/<base> and <base> are both in the
#      branch), switch to the base, `git merge --ff-only <branch>`, push the base with
#      HARNESS_KIT_SHIP=1 set (the pre-push hook from install-hooks.sh refuses any other
#      push to the base), and delete the branch's report, commit draft, brief and brief
#      approval (.reports/, report-path.sh --name).
# It never forces a push, never rewrites history, and never deletes the branch. Its own
# commits (the index, the review line) go through the commit-msg hook like any other.
#
# TIME LIMITS (time-limit.mjs, through limit-lib.sh). The index command and the check run
# under the check limit (540 seconds by default), and a TIMEOUT stops with index-timeout or
# check-timeout, before any review; a reviewer run past its limit (review.sh exit 5) stops
# with review-timeout. The pushes and the fetch run under the git limit (300 seconds) and
# without prompts (hk_git_net: GIT_TERMINAL_PROMPT=0, ssh BatchMode=yes), so a push that
# would need a password or passphrase fails at once, saying so; a TIMEOUT stops with
# git-timeout, naming the command. CI's gh calls have their own limits (ci-lib.sh). Each
# TIMEOUT stops the command's whole process group. Temporary files are removed on any exit,
# a signal included (hk_temp, hk_on_exit).
#
# THE NOTIFICATION. On macOS, each STOPPED and the SHIPPED also show a notification
# (osascript `display notification`), as a ship waits minutes for CI. Refusals come at once,
# so they do not. Not on macOS (uname -s is not Darwin), nothing is shown.
#
# THE EVENT LOG. Each stop and each refusal (event STOPPED; a refusal's reason starts
# "refused-", such as refused-on-base, and a stop's is short, such as check-failed,
# review-not-pass, ci-not-green or ci-unknown; a TIMEOUT's is check-timeout, index-timeout,
# review-timeout, ci-timeout or git-timeout), with its message, and each SHIPPED, is
# appended to the local event log, .git/harness-kit/events.tsv (events.sh has the format),
# on the branch being shipped. So is the result of the check run before the review, through events.sh's
# harness_check_event: a CHECKED line when it differs from the branch's last recorded
# result. Outside a git repository nothing is recorded.
#
# THE TIME (events.sh's harness_timed_event). The whole run, from its start to its exit on
# any path (a refusal, a stop, a signal or the ship), is a TIMED line for "ship" against the
# ship budget (600 seconds by default; time-limit.mjs's BUDGETS), on the branch checked out
# at the exit. A time over the budget adds a TIMED line marked over and one warning line on
# stderr; it stops nothing.
#
# RESUMABLE. Re-running after a stop continues where it stopped. Steps 1-5 are worked out
# from git and GitHub again each time and cost nothing when already done: a recorded PASS
# is not reviewed again (nor is its brief checked again), pushing a pushed branch does
# nothing, and a finished CI run is read, not re-run. Step 6 leaves the branch, so before switching ship.sh writes the
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
# shellcheck source=ci-lib.sh
. "$HERE/ci-lib.sh"
# shellcheck source=brief-lib.sh
. "$HERE/brief-lib.sh"
# shellcheck source=limit-lib.sh
. "$HERE/limit-lib.sh"
# The whole run's time, recorded on any exit (THE TIME).
STARTED="$(harness_clock)"
timed_exit() { harness_timed_event ship.sh ship "$(harness_seconds_since "$STARTED")" "$(node "$HK_LIMIT_JS" budget ship)"; }
hk_on_exit timed_exit
CI_TOOL=ship.sh CI_APPEAR="$APPEAR" CI_POLL="$POLL" CI_RESUME="re-run ship.sh"

say() { echo "harness-kit ship.sh: $*" >&2; }
notify() { ci_notify "$1"; }
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

# verdict_of HASH: the verdict of the latest line in the working tree's reviews.tsv for the
# diff HASH, or nothing.
verdict_of() { [ -f "$REVIEWS" ] && awk -F'\t' -v h="$1" 'NF == 9 && $5 == h { v = $6 } END { print v }' "$REVIEWS"; }

# commit_with SUBJECT BODY PATH...: commit only PATHs (staged first) with that message,
# through the commit-msg hook like any commit. Returns git's status.
commit_with() {
  local subject="$1" body="$2" msg status
  shift 2
  hk_temp msg harness-kit-ship-msg || return 1
  printf '%s\n\n%s\n' "$subject" "$body" >"$msg"
  git add -A -- "$@" && git commit -q -F "$msg" -- "$@"
  status=$?
  rm -f "$msg"
  return "$status"
}

# commit_review VERDICT: commit .harness/reviews.tsv alone, with the standard message.
commit_review() {
  commit_with "Record review of $branch: $1" \
    "$REVIEWS: the line review.sh appended for this branch's current diff, verdict $1. ship.sh commits it; the file is append-only." \
    "$REVIEWS" || stop commit-review-failed "could not commit $REVIEWS (above). Commit it yourself, then re-run ship.sh."
  say "committed $REVIEWS: Record review of $branch: $1"
}

# brief_gate BRANCH: step 2a. Returns when the review may start; stops otherwise, with the fix.
brief_gate() {
  local approve="$HERE/approve-brief.sh" optional_note=""
  brief_load "$PROJECT" "$1" || stop brief-name "$BRIEF_ERROR"
  case "$BRIEF_STATE" in
    approved)
      say "the brief is approved as it is: $BRIEF"
      ;;
    missing)
      if brief_optional "$PROJECT"; then
        say "no brief ($BRIEF); this project makes briefs optional (.harness/brief-optional, protected)"
        return 0
      fi
      [ -z "$BRIEF_OPTIONAL_WHY" ] || optional_note=" (Note: $BRIEF_OPTIONAL_WHY.)"
      stop no-brief "there is no brief for $1 ($BRIEF), so no review was started. Fix: in Claude, run /harness-kit:brief <goal> to write it; read it, then approve it in your terminal: $approve; then re-run ship.sh.$optional_note"
      ;;
    unapproved)
      stop brief-not-approved "the brief $BRIEF has no approval ($BRIEF_APPROVAL), so no review was started. Fix: read it, then approve it in your terminal: $approve; then re-run ship.sh."
      ;;
    *)
      stop brief-changed "the brief $BRIEF changed after it was approved (its sha256 is $BRIEF_SHA; $BRIEF_APPROVAL holds $BRIEF_RECORDED), so no review was started. Fix: read it again, then approve it in your terminal: $approve; then re-run ship.sh."
      ;;
  esac
}

# refresh_index: step 2b. Commits the files .harness/index-command changed or added.
refresh_index() {
  local cmd before after changed body path paths status
  cmd="$( { [ -f .harness/index-command ] && head -n 1 .harness/index-command; } | tr -d '\r')"
  [ -n "$cmd" ] || return 0
  say "refreshing the index before the review: $cmd"
  before="$(git status --porcelain --untracked-files=all -- . ":(exclude)$REVIEWS")"
  hk_limited check ship.sh /bin/sh -c "$cmd" </dev/null >&2
  status=$?
  [ "$status" -ne 124 ] ||
    stop index-timeout "the index command did not finish within its limit of $(hk_limit check) seconds (TIMEOUT, above): $cmd. It was stopped; nothing was committed and no review was started. Find what hangs or runs slowly, then re-run ship.sh."
  [ "$status" -eq 0 ] ||
    stop index-failed "the index command failed (exit $status, above): $cmd. Nothing was committed and no review was started. Fix it, then re-run ship.sh."
  after="$(git status --porcelain --untracked-files=all -- . ":(exclude)$REVIEWS")"
  changed="$(grep -vxF -f <(printf '%s\n' "$before") <<<"$after" | cut -c4-)"
  if [ -z "$changed" ]; then
    say "the index is up to date: $cmd changed nothing"
    return 0
  fi
  body=""
  paths=()
  while IFS= read -r path; do
    paths+=("$path")
    body="$body$path: regenerated by the first line of .harness/index-command, which ship.sh ran before the review because the index was stale."$'\n'
  done <<<"$changed"
  commit_with "Refresh the index (.harness/index-command)" "${body%$'\n'}" "${paths[@]}" ||
    stop commit-index-failed "could not commit the refreshed index (above); it is in the working tree, uncommitted. Commit it yourself, then re-run ship.sh."
  say "committed the refreshed index: $(tr '\n' ' ' <<<"$changed")"
}

# Step 6. Uses $branch and $head.
finish() {
  local report draft brief
  printf '%s\t%s\n' "$branch" "$head" >"$STATE" || stop state-file "cannot write $STATE"
  if [ "$(git symbolic-ref --short -q HEAD)" != "$base" ]; then
    git checkout -q "$base" || stop checkout-failed "could not switch to $base. Fix what git says, then re-run ship.sh (on $base or $branch)."
  fi
  git merge -q --ff-only "$branch" ||
    stop base-not-fast-forward "$base cannot fast-forward to $branch. You are on $base; nothing was pushed to it. Bring $branch up to date with $base, then re-run ship.sh on $branch."
  # HARNESS_KIT_SHIP=1: the pre-push hook (install-hooks.sh) lets this push of the base through.
  HARNESS_KIT_SHIP=1 hk_git_net ship.sh push -q "$REMOTE" "$base"
  case $? in
    0) ;;
    124) stop git-timeout "git push of $base to $REMOTE did not finish within $(hk_limit git) seconds (TIMEOUT, above), and may or may not have reached $REMOTE. You are on $base, which is merged locally. Re-run ship.sh on $base to push it again." ;;
    *) stop push-base-failed "pushing $base failed (above). You are on $base, which is merged locally and not pushed. Fix the cause, then re-run ship.sh on $base to push it." ;;
  esac
  report="$(bash "$HERE/report-path.sh" --name "$branch")" && rm -f -- "$report"
  draft="$(bash "$HERE/report-path.sh" --name "$branch" --commit)" && rm -f -- "$draft"
  brief="$(bash "$HERE/report-path.sh" --name "$branch" --brief)" && rm -f -- "$brief" "${brief%.md}.approved"
  rm -f -- "$STATE"
  harness_event ship.sh "$branch" SHIPPED "$base" "merged $(git rev-parse --short "$head") into $base and pushed it"
  say "SHIPPED: $branch ($(git rev-parse --short "$head")) is merged into $base and pushed; its report, commit draft, brief and brief approval were deleted. You are on $base."
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
    brief_gate "$branch"
    refresh_index
    state="$(node "$HERE/check-reviewed.mjs" --hash)" || stop diff-failed "could not work out the branch's diff: $state"
    hash="$(cut -f3 <<<"$state")"
    check="$( { [ -f .harness/check-command ] && head -n 1 .harness/check-command; } | tr -d '\r')"
    if [ -z "$check" ]; then
      say "no .harness/check-command, so there is no check to run before the review"
    else
      grep -qE '(^|[[:space:]])--skip-reviewed([[:space:]]|$)' <<<"$check" ||
        stop no-skip-reviewed "the first line of .harness/check-command does not pass --skip-reviewed, so it would run the review check, which cannot pass before the review. No review was started. Add the flag where the project's check reads it (for a single command: $(sed -E 's/[[:space:]]+$//' <<<"$check") --skip-reviewed), commit, then re-run ship.sh."
      say "running the check before the review: $check"
      # Its output (stdout and stderr together) is saved with what it ran on, and review.sh
      # reuses it instead of running the check again.
      hk_temp saved -d harness-kit-ship-check || stop temp-file "cannot make a temporary folder"
      printf '%s\n' "$check" >"$saved/command"
      git rev-parse HEAD >"$saved/head"
      git status --porcelain --untracked-files=all >"$saved/tree"
      { hk_limited --merge check ship.sh /bin/sh -c "$check" </dev/null 2>&1; echo $? >"$saved/status"; } | tee "$saved/output"
      status="$(cat "$saved/status")"
      if [ "$status" -eq 124 ]; then
        limit="$(hk_limit check)"
        harness_check_event ship.sh "$branch" "timeout ${limit}s" <"$saved/output"
        stop check-timeout "the check did not finish within its limit of $limit seconds (TIMEOUT, above): $check. It was stopped, and no review was started. Find what hangs or runs slowly and fix it, commit, then re-run ship.sh."
      fi
      harness_check_event ship.sh "$branch" "$status" <"$saved/output"
      [ "$status" -eq 0 ] ||
        stop check-failed "the check failed (exit $status, above): $check. No review was started. Fix what it reports, commit, then re-run ship.sh."
    fi
    say "no PASS review for the branch's current diff; running review.sh"
    HARNESS_KIT_CHECK_SAVED="${saved:-}" bash "$HERE/review.sh"
    status=$?
    verdict="$(verdict_of "$hash")"
    if [ -n "$verdict" ] && [ -n "$(git status --porcelain --untracked-files=all -- "$REVIEWS")" ]; then
      commit_review "$verdict"
    fi
    if [ "$status" -eq 5 ]; then
      stop review-timeout "the reviewer ran longer than its limit of $(hk_limit review) seconds (review.sh exit 5, above) and was stopped, so there is no verdict and nothing was recorded. Re-run ship.sh to review again; if it happens again, split the branch."
    fi
    if [ "$status" -ne 0 ]; then
      if [ -n "$verdict" ]; then
        items="$(awk -F'\t' -v h="$hash" 'NF == 9 && $5 == h { v = $7 } END { print v }' "$REVIEWS")"
        stop review-not-pass "the review's verdict is $verdict ($items), not PASS (the review is above; its line is committed: Record review of $branch: $verdict). Fix what it reports, commit, then re-run ship.sh."
      fi
      stop review-failed "the review did not complete (review.sh exit $status, above), so there is no verdict. Fix the cause, then re-run ship.sh."
    fi
  fi
  if [ -n "$(git status --porcelain --untracked-files=all -- "$REVIEWS")" ]; then
    commit_review PASS
  fi
  out="$(node "$HERE/check-reviewed.mjs" 2>&1)" || stop check-reviewed-failed "check-reviewed still fails at HEAD: $out"
fi
head="$(git rev-parse HEAD)"

# ---------------------------------------------------------------------------------------
# 4. Push the branch.
# ---------------------------------------------------------------------------------------
hk_git_net ship.sh push -q -u "$REMOTE" "$branch"
case $? in
  0) ;;
  124) stop git-timeout "git push of $branch to $REMOTE did not finish within $(hk_limit git) seconds (TIMEOUT, above), and may or may not have reached $REMOTE. Re-run ship.sh: pushing a pushed branch does nothing." ;;
  *) stop push-branch-failed "pushing $branch to $REMOTE failed (above). Fix the cause, then re-run ship.sh." ;;
esac
say "pushed $branch ($(git rev-parse --short "$head")) to $REMOTE"

# ---------------------------------------------------------------------------------------
# 5. CI for the pushed head.
# ---------------------------------------------------------------------------------------
ci_wait "$head" "$branch"

# ---------------------------------------------------------------------------------------
# 6. Merge into the base, push it, delete the report, the commit draft and the brief.
# ---------------------------------------------------------------------------------------
hk_git_net ship.sh fetch -q "$REMOTE" "$base"
case $? in
  0) ;;
  124) stop git-timeout "git fetch of $base from $REMOTE did not finish within $(hk_limit git) seconds (TIMEOUT, above). Nothing was merged. Re-run ship.sh." ;;
  *) stop fetch-failed "could not fetch $base from $REMOTE (above). Re-run ship.sh." ;;
esac
for ref in "refs/remotes/$REMOTE/$base" "refs/heads/$base"; do
  if git rev-parse -q --verify "$ref" >/dev/null && ! git merge-base --is-ancestor "$ref" "$head"; then
    stop base-not-fast-forward "${ref#refs/*/} has commits that $branch does not, so $base cannot fast-forward. Bring $branch up to date with $base (it will need a new review and CI), then re-run ship.sh."
  fi
done
finish
