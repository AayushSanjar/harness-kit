# Shared by ship.sh and release.sh: reading gh's JSON, the macOS notification, and waiting
# for the CI runs of a pushed commit. Sourced, not run; written for bash 3.2 (macOS).
#
# The caller sets, before calling anything here:
#   CI_TOOL     its file name (ship.sh or release.sh), for messages and the notification title
#   CI_APPEAR   seconds to wait for the first run to appear
#   CI_POLL     seconds between polls
# and defines `stop REASON MESSAGE`, which records the stop, prints it and exits.

# ci_json_field FIELD: FIELD of the first element of the JSON array on stdin, or of the
# object on stdin; empty when missing.
ci_json_field() {
  node -e '
    let v = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (Array.isArray(v)) v = v[0] ?? {};
    const x = v[process.argv[1]];
    process.stdout.write(x === undefined || x === null ? "" : String(x));
  ' "$1"
}

# ci_notify MESSAGE: a macOS notification (osascript), so a person who looked away while CI
# ran sees the end. Skipped when not on macOS (uname -s is not Darwin); a failure is ignored.
ci_notify() {
  [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "harness-kit $CI_TOOL" "$1" >/dev/null 2>&1 || true
}

# ci_wait HEAD BRANCH: find the CI runs for the pushed commit HEAD (gh run list --commit),
# waiting up to CI_APPEAR seconds for the first to appear; wait for each to finish (gh run
# watch), then read its conclusion (gh run view). Anything but "success" stops, printing the
# run's URL. Which runs:
#   - with .harness/ci-workflow (optional; first line, the workflow as
#     `gh run list --workflow` takes it): that workflow's runs only, waiting for one to
#     appear even when other workflows' runs appeared first;
#   - without it: every run listed for the commit when the first one appears. A workflow
#     that starts later than that is not waited for.
# Returns 0 when every run passed; otherwise it has called stop.
ci_wait() {
  local head="$1" branch="$2" fields workflow filter what waited runs ids id run status conclusion url
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
      stop gh-failed "gh run list failed (above). Fix gh (gh auth status), then re-run $CI_TOOL."
    ids="$(node -e 'for (const r of JSON.parse(require("fs").readFileSync(0, "utf8"))) console.log(r.databaseId)' <<<"$runs")" ||
      stop gh-failed "gh run list did not print the expected JSON: $runs"
    [ -z "$ids" ] || break
    [ "$waited" -lt "$CI_APPEAR" ] ||
      stop no-ci-run "no $what for $(git rev-parse --short "$head") appeared within ${CI_APPEAR}s. Check that it runs on pushes to $branch, then re-run $CI_TOOL to keep waiting."
    echo "harness-kit $CI_TOOL: waiting for a $what to start for $(git rev-parse --short "$head")..." >&2
    sleep "$CI_POLL"
    waited=$((waited + CI_POLL))
  done
  for id in $ids; do
    echo "harness-kit $CI_TOOL: waiting for CI run $id to finish..." >&2
    gh run watch "$id" --exit-status --compact --interval "$CI_POLL" >&2
    run="$(gh run view "$id" --json status,conclusion,url)" || stop gh-failed "gh run view $id failed (above). Re-run $CI_TOOL to check the run again."
    status="$(ci_json_field status <<<"$run")"
    conclusion="$(ci_json_field conclusion <<<"$run")"
    url="$(ci_json_field url <<<"$run")"
    [ "$status" = completed ] ||
      stop ci-not-finished "CI run $id is $status, not finished: $url. Re-run $CI_TOOL to keep waiting."
    [ "$conclusion" = success ] ||
      stop ci-not-green "CI run $id finished with conclusion \"$conclusion\", not success: $url. Fix the branch (or re-run the job if it was not the branch's fault), then re-run $CI_TOOL."
    echo "harness-kit $CI_TOOL: CI run $id passed: $url" >&2
  done
  return 0
}
