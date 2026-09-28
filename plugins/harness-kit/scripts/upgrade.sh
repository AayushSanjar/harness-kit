#!/usr/bin/env bash
# Move a consumer project to another harness-kit release.
#
#   upgrade.sh <version>     e.g. upgrade.sh 0.9.0 (or v0.9.0); run from anywhere inside
#                            the project's git repository
#
# For people, in their own terminal: it changes the project's settings, the user's plugin
# registry and the installed plugin, and ends with the project's approval, which asks the
# person. In order, stopping at the first failure with a message saying what to do:
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
#   5. The local git hook: install-hooks.sh (next to this script), which installs the
#      pre-push hook that refuses pushes to the review base branch unless ship.sh makes
#      them. A pre-push hook harness-kit did not write, or core.hooksPath, stops here. A
#      project that pushes its base by hand must remove the hook afterwards
#      (install-hooks.sh, NOT FOR EVERY REPOSITORY).
#   6. The approval: the first line of .harness/approve-command, run in the project with the
#      terminal's input, as land.sh runs it: the person reads the diff and answers. A
#      project with no approve-command is told to read `git diff` itself.
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
say "1/6 pinned $MARKETPLACE to $tag in $SETTINGS (was $old)"
CHANGED="$SETTINGS now pins $tag (was $old); to undo: git checkout -- $SETTINGS"

# ---------------------------------------------------------------------------------------
# 2-3. The marketplace and the plugin.
# ---------------------------------------------------------------------------------------
claude plugin marketplace add "$repo#$tag" --scope project >&2 ||
  stop "claude plugin marketplace add $repo#$tag --scope project failed (above). Check that the tag $tag exists on github.com/$repo. $CHANGED"
say "2/6 re-added the marketplace at $repo#$tag"
claude plugin update "$PLUGIN" --scope project >&2 ||
  stop "claude plugin update $PLUGIN --scope project failed (above). $CHANGED, and the marketplace is at $tag."
say "3/6 updated $PLUGIN"

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
say "4/6 a new session loads $PLUGIN $loaded"

# ---------------------------------------------------------------------------------------
# 5. The local git hook.
# ---------------------------------------------------------------------------------------
bash "$HERE/install-hooks.sh" ||
  stop "install-hooks.sh did not install the pre-push hook (above). $CHANGED; the plugin is updated and loads $version. Fix what it says, then run install-hooks.sh (or upgrade.sh again)."
say "5/6 installed the pre-push hook: pushes to the review base branch go through ship.sh"

# ---------------------------------------------------------------------------------------
# 6. The approval.
# ---------------------------------------------------------------------------------------
approve="$( { [ -f .harness/approve-command ] && head -n 1 .harness/approve-command; } | tr -d '\r')"
if [ -z "$approve" ]; then
  say "6/6 no .harness/approve-command, so there is nothing to approve with; read \`git diff\` yourself."
else
  say "6/6 running the approval command: $approve"
  /bin/sh -c "$approve"
  status=$?
  [ "$status" -eq 0 ] ||
    stop "the approval command failed or was declined (exit $status). $CHANGED; the plugin is updated and loads $version. Nothing was committed."
fi

say "UPGRADED: $PLUGIN $version is pinned, installed and loads, and the pre-push hook is installed. Nothing was committed."
say "Next: read 'git diff', commit it (with a reason for $SETTINGS), and run /reload-plugins in any open session."
exit 0
