# Shared by ship.sh and release.sh: reading gh's JSON, the macOS notification, and waiting
# for the CI runs of a pushed commit. Sourced, not run; written for bash 3.2 (macOS).
#
# The caller sets, before calling anything here:
#   CI_TOOL     its file name (ship.sh or release.sh), for messages and the notification title
#   CI_APPEAR   seconds to wait for the first run to appear
#   CI_POLL     seconds between polls
#   CI_RESUME   how to resume after a stop, as a phrase ("re-run release.sh v0.15.1")
# and defines `stop REASON MESSAGE`, which records the stop, prints it and exits.
#
# TIME LIMITS (time-limit.mjs, through limit-lib.sh, which this file sources). Each gh read
# runs under the gh-read limit (SHIP_GH_READ_SECONDS, 60 by default): a read past it is a
# failed try, retried like any other. Each gh run watch runs under the CI-run limit
# (SHIP_CI_RUN_SECONDS, 900 by default): past it, ci_wait stops with ci-timeout, the run's
# URL and how to resume; nothing was merged, pushed to the base or tagged. Each is stopped
# with its whole process group.

# shellcheck source=limit-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/limit-lib.sh"

# ci_notify MESSAGE: a macOS notification (osascript), so a person who looked away while CI
# ran sees the end. Skipped when not on macOS (uname -s is not Darwin); a failure is ignored.
ci_notify() {
  [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "harness-kit $CI_TOOL" "$1" >/dev/null 2>&1 || true
}

# ci_parse KIND: checks that stdin is the JSON that `gh run KIND` (list or view) prints, and
# prints what ci_wait reads from it. Returns 1, printing nothing, for anything else.
#   list  a JSON list of runs, each an object with a whole-number databaseId above 0 and a
#         string url: one "<databaseId> <url>" line per run (none for an empty list)
#   view  a JSON object with a string status: three lines, its status, its conclusion and
#         its url (empty when missing or not a string)
ci_parse() {
  node -e '
    let v;
    try { v = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(1); }
    const text = (x) => (typeof x === "string" ? x.replace(/\s+/g, " ") : "");
    const isObject = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
    if (process.argv[1] === "list") {
      if (!Array.isArray(v)) process.exit(1);
      const ok = (r) => isObject(r) && Number.isInteger(r.databaseId) && r.databaseId > 0 && typeof r.url === "string";
      if (!v.every(ok)) process.exit(1);
      for (const r of v) console.log(`${r.databaseId} ${text(r.url)}`);
    } else {
      if (!isObject(v) || typeof v.status !== "string") process.exit(1);
      console.log([text(v.status), text(v.conclusion), text(v.url)].join("\n"));
    }
  ' "$1"
}

# ci_gh_read KIND ARGS...: runs `gh ARGS...` (a `gh run KIND` command) up to CI_TRIES times,
# CI_RETRY_PAUSE seconds apart, until a try exits 0 with the JSON KIND expects (ci_parse).
# Returns 0 with ci_parse's lines in CI_READ; returns 1 when every try failed, with the last
# try's error in CI_ERROR. gh's stderr is shown as it comes.
ci_gh_read() {
  local kind="$1" try=1 out err code
  shift
  # One file for gh's stderr, removed on exit (hk_temp); /dev/null if it cannot be made.
  [ -n "${CI_ERRFILE:-}" ] || hk_temp CI_ERRFILE harness-kit-gh || CI_ERRFILE=/dev/null
  while :; do
    out="$(hk_limited gh-read "$CI_TOOL" gh "$@" 2>"$CI_ERRFILE")"
    code=$?
    err="$(cat "$CI_ERRFILE" 2>/dev/null)"
    [ -z "$err" ] || printf '%s\n' "$err" >&2
    if [ "$code" -eq 124 ]; then
      CI_ERROR="gh $1 $2 did not answer within its limit of $(hk_limit gh-read) seconds (TIMEOUT)"
    elif [ "$code" -eq 0 ]; then
      CI_READ="$(ci_parse "$kind" <<<"$out")" && return 0
      CI_ERROR="gh $1 $2 printed output that is not the expected JSON: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)"
    else
      CI_ERROR="gh $1 $2 failed (exit $code): $(printf '%s\n' "$err" | awk 'NF { print; exit }')"
    fi
    [ "$try" -lt "$CI_TRIES" ] || return 1
    try=$((try + 1))
    echo "harness-kit $CI_TOOL: $CI_ERROR; trying again in ${CI_RETRY_PAUSE}s (try $try of $CI_TRIES)" >&2
    sleep "$CI_RETRY_PAUSE"
  done
}

# ci_unknown WHAT WHERE: stops with "CI result unknown" (reason ci-unknown): WHAT could not be
# read after CI_TRIES tries, CI_ERROR the last error, WHERE the run's URL or how to look.
ci_unknown() {
  stop ci-unknown "CI result unknown for $1: $CI_ERROR ($CI_TRIES tries, ${CI_RETRY_PAUSE}s apart). $2. Nothing was merged, pushed to the base branch or tagged. When gh works again (gh auth status), ${CI_RESUME:-re-run $CI_TOOL} to resume."
}

# ci_wait HEAD BRANCH: find the CI runs for the pushed commit HEAD (gh run list --commit),
# waiting up to CI_APPEAR seconds for the first to appear; wait for each to finish (gh run
# watch), then read its result (gh run view). Which runs:
#   - with .harness/ci-workflow (optional; first line, the workflow as
#     `gh run list --workflow` takes it): that workflow's runs only, waiting for one to
#     appear even when other workflows' runs appeared first;
#   - without it: every run listed for the commit when the first one appears. A workflow
#     that starts later than that is not waited for.
#
# IT FAILS CLOSED. A run passes only when gh run view answers with status "completed" and
# conclusion "success"; that is the only place "passed" is printed. A completed run with any
# other conclusion stops (ci-not-green), printing the run's URL. Everything else is a
# failed try, retried up to CI_TRIES times in all, CI_RETRY_PAUSE seconds apart:
#   - a gh call that exits non-zero (a network timeout, gh logged out), or whose output is
#     not the JSON expected (ci_parse): each gh read is retried on its own (ci_gh_read);
#   - a run that is not completed after gh run watch, or completed with no conclusion: the
#     watch ended without a result (gh run watch's exit status cannot tell a red run from a
#     gh error, as --exit-status exits non-zero for both), so the run is watched again.
# When the tries run out, it stops with "CI result unknown" (reason ci-unknown): what could
# not be read, gh's last error, the run's URL (or, when the run list itself could not be
# read, the command to look with), and how to resume (CI_RESUME). The caller has not merged,
# pushed its base or tagged by then, and ci_wait never returns after a stop. When a watch
# fails but GitHub then reports the run completed with success, the run passes, and a line
# says first that the watch failed.
#
# The caller sets CI_RESUME ("re-run release.sh <tag>", "re-run ship.sh"). The tries and the
# pause are the person's numbers: SHIP_GH_TRIES (default 3) and SHIP_GH_RETRY_SECONDS
# (default 10); a value that is not a whole number (the tries: above 0) is not used, and
# the default is.
# Returns 0 when every run passed; otherwise it has called stop.
ci_wait() {
  local head="$1" branch="$2" fields workflow filter what waited ids id url try watched status conclusion view_url why
  fields=databaseId,status,conclusion,url,workflowName
  CI_TRIES="${SHIP_GH_TRIES:-3}" CI_RETRY_PAUSE="${SHIP_GH_RETRY_SECONDS:-10}"
  case "$CI_TRIES" in '' | *[!0-9]* | 0*) CI_TRIES=3 ;; esac
  case "$CI_RETRY_PAUSE" in '' | *[!0-9]*) CI_RETRY_PAUSE=10 ;; esac
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
    ci_gh_read list run list --commit "$head" ${filter[@]+"${filter[@]}"} --json "$fields" --limit 50 ||
      ci_unknown "the CI runs of $(git rev-parse --short "$head")" "There is no run URL, as the runs could not be listed; look with: gh run list --commit $head"
    ids="$(cut -d' ' -f1 <<<"$CI_READ")"
    [ -z "$ids" ] || break
    [ "$waited" -lt "$CI_APPEAR" ] ||
      stop no-ci-run "no $what for $(git rev-parse --short "$head") appeared within ${CI_APPEAR}s. Check that it runs on pushes to $branch, then ${CI_RESUME:-re-run $CI_TOOL} to keep waiting."
    echo "harness-kit $CI_TOOL: waiting for a $what to start for $(git rev-parse --short "$head")..." >&2
    sleep "$CI_POLL"
    waited=$((waited + CI_POLL))
  done
  local runs="$CI_READ"
  for id in $ids; do
    url="$(awk -v id="$id" '$1 == id { print $2; exit }' <<<"$runs")"
    try=1
    while :; do
      echo "harness-kit $CI_TOOL: waiting for CI run $id to finish..." >&2
      hk_limited ci-run "$CI_TOOL" gh run watch "$id" --exit-status --compact --interval "$CI_POLL" >&2 </dev/null
      watched=$?
      [ "$watched" -ne 124 ] ||
        stop ci-timeout "CI run $id did not finish within its limit of $(hk_limit ci-run) seconds (TIMEOUT, above): ${url:-(no URL listed)}. The watch was stopped. Nothing was merged, pushed to the base branch or tagged. ${CI_RESUME:-re-run $CI_TOOL} to keep waiting."
      ci_gh_read view run view "$id" --json status,conclusion,url || ci_unknown "CI run $id" "Run: ${url:-(no URL listed)}"
      { read -r status; read -r conclusion; read -r view_url; } <<<"$CI_READ"
      [ -z "$view_url" ] || url="$view_url"
      [ "$status" != completed ] || [ -z "$conclusion" ] || break
      if [ "$status" = completed ]; then
        why="GitHub reports CI run $id completed with no conclusion"
      else
        why="CI run $id is \"$status\" after gh run watch exited $watched"
      fi
      CI_ERROR="$why"
      [ "$try" -lt "$CI_TRIES" ] || ci_unknown "CI run $id" "Run: ${url:-(no URL listed)}"
      try=$((try + 1))
      echo "harness-kit $CI_TOOL: $why; watching it again in ${CI_RETRY_PAUSE}s (try $try of $CI_TRIES)" >&2
      sleep "$CI_RETRY_PAUSE"
    done
    [ "$conclusion" = success ] ||
      stop ci-not-green "CI run $id finished with conclusion \"$conclusion\", not success: $url. Fix the branch (or re-run the job if it was not the branch's fault), then ${CI_RESUME:-re-run $CI_TOOL}."
    [ "$watched" -eq 0 ] ||
      echo "harness-kit $CI_TOOL: gh run watch exited $watched for CI run $id, so its result was read from GitHub directly: completed, success" >&2
    # The only "passed": the loop above ends only on status "completed" with a conclusion,
    # and the line above stops on any conclusion but "success".
    echo "harness-kit $CI_TOOL: CI run $id passed: $url" >&2
  done
  return 0
}
