#!/usr/bin/env bash
# Move a consumer project to another harness-kit release.
#
#   upgrade.sh <version>     e.g. upgrade.sh 0.9.0 (or v0.9.0); run from anywhere inside
#                            the project's git repository
#
# For people, in their own terminal: it changes the project's settings, the user's plugin
# registry and the installed plugin, and ends with the project's approval, which asks the
# person. In order, stopping at the first failure with a message saying what to do:
#   0. The working tree: uncommitted changes to tracked files stop here, before anything is
#      changed, as the commit draft (step 7) covers every change upgrade.sh leaves.
#   1. The pin. In .claude/settings.json, extraKnownMarketplaces["harness-kit"].source.ref
#      becomes v<version>; .repo (the GitHub repository) must be there already. Nothing
#      else in the file changes.
#   2. The marketplace, re-added at that tag, declared in project settings:
#      claude plugin marketplace add <repo>#v<version> --scope project
#   3. The plugin: claude plugin update harness-kit@harness-kit --scope project
#   4. The version that loads. A headless session in the project
#      (claude -p ... --output-format stream-json --verbose) prints an init event first; its
#      "plugins" list must hold harness-kit@harness-kit at <version>, and its
#      "plugin_errors", if any, must not name harness-kit. The session is stopped as soon as
#      the init event is read, before the model answers, so nothing is spent; the wait is
#      at most UPGRADE_INIT_SECONDS (default 120).
#   5. The local git hooks: install-hooks.sh (next to this script), which installs the
#      pre-push hook that refuses pushes to the review base branch unless ship.sh makes
#      them, and the commit-msg hook that checks each commit message. A hook of either name
#      that harness-kit did not write, or core.hooksPath, stops here. A project that
#      pushes its base by hand must remove the pre-push hook afterwards (install-hooks.sh).
#   6. The approval: the first line of .harness/approve-command, run in the project with the
#      terminal's input, as land.sh runs it: the person reads the diff and answers. A
#      project with no approve-command is told to read `git diff` itself.
#   7. The commit draft. harness-kit's own commits from the old tag to the new one are
#      fetched (git fetch of both tags from github.com/<repo>, or from
#      UPGRADE_UPSTREAM_URL when set, into a temporary repository) and upgrade-draft.mjs
#      writes the pin's commit message to .reports/<branch>.commit.txt (report-path.sh
#      --commit, replacing what is there): each changed file named with its reason
#      (.claude/settings.json, .harness/protected.lock when the approval re-recorded it),
#      harness-kit's Breaks: lines kept, each of its Decision: lines relabelled
#      "Upstream:", and every number from its messages on a Told: line. The draft is then
#      proved: check-commits.mjs --message, the commit-msg hook's check, against a
#      temporary index holding exactly the changed files, must pass. The person commits
#      with the command printed at the end.
# It never commits and never pushes.
#
# Exit status: 0 upgraded and approved; 1 stopped (the message says what changed so far);
# 2 usage.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE=harness-kit
PLUGIN=harness-kit@harness-kit
WAIT="${UPGRADE_INIT_SECONDS:-120}"
POLL="${UPGRADE_POLL_SECONDS:-1}"

say() { echo "harness-kit upgrade.sh: $*" >&2; }
stop() { say "STOPPED: $*"; exit 1; }

if [ $# -ne 1 ]; then
  echo "usage: upgrade.sh <version>   (for example: upgrade.sh 0.9.0)" >&2
  exit 2
fi
version="${1#v}"
case "$version" in
  *[!0-9.]* | .* | *. | *..* | "") say "\"$1\" is not a version like 0.9.0"; exit 2 ;;
esac
[ "$(tr -cd . <<<"$version")" = .. ] || { say "\"$1\" is not a version like 0.9.0"; exit 2; }
tag="v$version"

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || { say "not inside a git repository"; exit 2; }
cd "$PROJECT" || exit 2
SETTINGS=.claude/settings.json
[ -f "$SETTINGS" ] || stop "there is no $SETTINGS, so there is no harness-kit pin to move. Nothing was changed."
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
  stop "there are uncommitted changes (git status); commit or stash them first, so that the commit draft upgrade.sh writes covers only the upgrade. Nothing was changed."
# Untracked files now, so that step 7 names only the files the upgrade adds.
untracked_before="$(git ls-files --others --exclude-standard)"

# ---------------------------------------------------------------------------------------
# 1. The pin. Prints the repository and the old ref, tab-separated.
# ---------------------------------------------------------------------------------------
pin="$(node -e '
  const fs = require("fs");
  const [file, name, tag] = process.argv.slice(1);
  const text = fs.readFileSync(file, "utf8");
  let settings;
  try { settings = JSON.parse(text); } catch (e) { console.error(`${file} is not valid JSON: ${e.message}`); process.exit(1); }
  const source = settings.extraKnownMarketplaces?.[name]?.source;
  if (!source || typeof source.repo !== "string" || typeof source.ref !== "string") {
    console.error(`${file} has no extraKnownMarketplaces["${name}"].source with a repo and a ref`);
    process.exit(1);
  }
  const old = source.ref;
  source.ref = tag;
  const indent = /^\{\r?\n([ \t]+)"/.exec(text)?.[1] ?? "  ";
  fs.writeFileSync(file, JSON.stringify(settings, null, indent) + "\n");
  console.log(`${source.repo}\t${old}`);
' "$SETTINGS" "$MARKETPLACE" "$tag" 2>&1)" || stop "$pin. Nothing was changed."
IFS=$'\t' read -r repo old <<<"$pin"
say "1/7 pinned $MARKETPLACE to $tag in $SETTINGS (was $old)"
CHANGED="$SETTINGS now pins $tag (was $old); to undo: git checkout -- $SETTINGS"

# ---------------------------------------------------------------------------------------
# 2-3. The marketplace and the plugin.
# ---------------------------------------------------------------------------------------
claude plugin marketplace add "$repo#$tag" --scope project >&2 ||
  stop "claude plugin marketplace add $repo#$tag --scope project failed (above). Check that the tag $tag exists on github.com/$repo. $CHANGED"
say "2/7 re-added the marketplace at $repo#$tag"
claude plugin update "$PLUGIN" --scope project >&2 ||
  stop "claude plugin update $PLUGIN --scope project failed (above). $CHANGED, and the marketplace is at $tag."
say "3/7 updated $PLUGIN"

# ---------------------------------------------------------------------------------------
# 4. The version a new session loads, from its init event.
# ---------------------------------------------------------------------------------------
work="$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-upgrade.XXXXXX")" || stop "cannot make a temporary folder. $CHANGED"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# init_event FILE: prints the first init event in FILE as JSON, or nothing.
init_event() {
  node -e '
    for (const line of require("fs").readFileSync(process.argv[1], "utf8").split("\n")) {
      try {
        const e = JSON.parse(line);
        if (e.type === "system" && e.subtype === "init") { console.log(JSON.stringify(e)); break; }
      } catch {}
    }
  ' "$1"
}

claude -p "Reply with the single word ok." --output-format stream-json --verbose --max-turns 1 \
  </dev/null >"$work/session.jsonl" 2>"$work/session.err" &
pid=$!
waited=0
event=""
while :; do
  event="$(init_event "$work/session.jsonl")"
  [ -z "$event" ] || break
  kill -0 "$pid" 2>/dev/null ||
    stop "the headless session ended without an init event: $(tail -c 2000 "$work/session.err"). $CHANGED, and the plugin is updated."
  [ "$waited" -lt "$WAIT" ] ||
    stop "no init event from the headless session within ${WAIT}s. $CHANGED, and the plugin is updated."
  sleep "$POLL"
  waited=$((waited + POLL))
done
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
pid=""

loaded="$(node -e '
  const [event, id, want] = [JSON.parse(process.argv[1]), process.argv[2], process.argv[3]];
  const errors = (event.plugin_errors ?? []).filter((e) => JSON.stringify(e).includes(id.split("@")[0]));
  if (errors.length > 0) { console.log(`the init event reports plugin errors for ${id}: ${JSON.stringify(errors)}`); process.exit(1); }
  const found = (event.plugins ?? []).filter((p) => p.source === id);
  if (found.length === 0) {
    const listed = (event.plugins ?? []).map((p) => `${p.source ?? p.name}@${p.version ?? "?"}`).join(", ") || "none";
    console.log(`the init event does not list ${id} (it lists: ${listed})`);
    process.exit(1);
  }
  const versions = found.map((p) => p.version);
  if (versions.some((v) => v !== want)) { console.log(`a new session loads ${id} ${versions.join(", ")}, not ${want}`); process.exit(1); }
  console.log(want);
' "$event" "$PLUGIN" "$version")" ||
  stop "$loaded. $CHANGED, and the plugin is updated. Run \`claude plugin list --json\` to see what is installed."
say "4/7 a new session loads $PLUGIN $loaded"

# ---------------------------------------------------------------------------------------
# 5. The local git hook.
# ---------------------------------------------------------------------------------------
bash "$HERE/install-hooks.sh" ||
  stop "install-hooks.sh did not install the hooks (above). $CHANGED; the plugin is updated and loads $version. Fix what it says, then run install-hooks.sh (or upgrade.sh again)."
say "5/7 installed the pre-push and commit-msg hooks: pushes to the review base branch go through ship.sh, and each commit message is checked"

# ---------------------------------------------------------------------------------------
# 6. The approval.
# ---------------------------------------------------------------------------------------
approve="$( { [ -f .harness/approve-command ] && head -n 1 .harness/approve-command; } | tr -d '\r')"
if [ -z "$approve" ]; then
  say "6/7 no .harness/approve-command, so there is nothing to approve with; read \`git diff\` yourself."
else
  say "6/7 running the approval command: $approve"
  /bin/sh -c "$approve"
  status=$?
  [ "$status" -eq 0 ] ||
    stop "the approval command failed or was declined (exit $status). $CHANGED; the plugin is updated and loads $version. Nothing was committed."
fi

# ---------------------------------------------------------------------------------------
# 7. The commit draft, from harness-kit's own commits between the two tags, proved.
# ---------------------------------------------------------------------------------------
APPROVED="$CHANGED; the plugin is updated and loads $version; the hooks are installed and the approval passed"
url="${UPGRADE_UPSTREAM_URL:-https://github.com/$repo.git}"
git init -q --bare "$work/upstream" &&
  git -C "$work/upstream" fetch -q --no-tags "$url" "+refs/tags/$old:refs/tags/$old" "+refs/tags/$tag:refs/tags/$tag" >&2 ||
  stop "could not fetch the tags $old and $tag from $url (above), so the commit draft was not written. $APPROVED. Nothing was committed; run upgrade.sh $version again when $url can be reached."
git -C "$work/upstream" log --reverse --format=%H%x1f%s%x1f%b%x1e "refs/tags/$old..refs/tags/$tag" >"$work/upstream.log" ||
  stop "could not list harness-kit's commits from $old to $tag (above), so the commit draft was not written. $APPROVED. Nothing was committed."
changed=()
while IFS= read -r path; do [ -n "$path" ] && changed+=("$path"); done < <(
  git diff --name-only HEAD
  git ls-files --others --exclude-standard | grep -vxF -f <(printf '%s\n' "$untracked_before") | grep -v '^\.reports/'
)
draft="$(bash "$HERE/report-path.sh" --commit)" ||
  stop "report-path.sh --commit failed (above), so the commit draft was not written. $APPROVED. Nothing was committed."
node "$HERE/upgrade-draft.mjs" "$old" "$tag" "$repo" "$work/upstream.log" ${changed[@]+"${changed[@]}"} >"$draft" ||
  stop "upgrade-draft.mjs failed (above), so the commit draft was not written. $APPROVED. Nothing was committed."
proof="$(
  export GIT_INDEX_FILE="$work/index"
  git read-tree HEAD && git add -A -- ${changed[@]+"${changed[@]}"} && node "$HERE/check-commits.mjs" --message "$draft" 2>&1
)" || stop "the commit draft $draft does not pass the commit-msg hook's check (below), which is a harness-kit bug: report it. $APPROVED. Nothing was committed.
$proof"
say "7/7 wrote the commit draft $draft; the commit-msg hook's check passes it: ${proof%%$'\n'*}"

say "UPGRADED: $PLUGIN $version is pinned, installed and loads, the hooks are installed, and the commit draft is written. Nothing was committed."
say "Next: read 'git diff', then commit with the draft, and run /reload-plugins in any open session:"
say "    git add --$(printf ' %q' ${changed[@]+"${changed[@]}"}) && git commit -F $draft"
exit 0
