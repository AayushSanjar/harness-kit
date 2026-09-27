#!/usr/bin/env bash
# Print the path of Claude's final report, or of its commit message draft, for the current
# branch.
#
#   report-path.sh                        print $PROJECT/.reports/<branch>.md, create .reports/
#                                         and point .reports/latest.md at that file (a relative
#                                         symlink)
#   report-path.sh --commit               the same for the commit message draft:
#                                         .reports/<branch>.commit.txt, pointed at by
#                                         .reports/latest.commit.txt
#   report-path.sh --prune [--commit]     either of the above, after deleting stale reports
#                                         and stale commit drafts (below)
#   report-path.sh --name BRANCH [--commit]
#                                         print the path for BRANCH only; creates and changes
#                                         nothing
#
# Run from anywhere inside the project's git repository. <branch> is the branch name with
# every "/" replaced by "-"; on a detached HEAD it is "detached-<first 12 of the sha>".
# This is the only place the name is worked out: session-start.mjs and ship.sh call it.
#
# STALE FILES (--prune): a .reports/*.md report or .reports/*.commit.txt draft is deleted
# when no local branch maps to its name. The pointers themselves (latest.md,
# latest.commit.txt), the files they point at when --prune starts, and the current
# branch's report and draft are never deleted. The "/" to "-" mapping is not reversible,
# so the check goes from branches to names, never from a name back to a branch.
#
# Reports and drafts are for the person to read, not for git: check-reports.mjs fails if
# any file under .reports/ is tracked.
set -u

die() {
  echo "harness-kit report-path.sh: $*" >&2
  exit 1
}

USAGE="usage: report-path.sh [--prune] [--commit] | --name BRANCH [--commit]"

# report_name BRANCH: the file name for BRANCH, with $SUFFIX (.md or .commit.txt).
report_name() {
  local name="${1//\//-}"
  [ "$name" != latest ] || die "the branch \"$1\" would be named latest$SUFFIX, which is the pointer to the latest one; rename the branch"
  printf '%s%s' "$name" "$SUFFIX"
}

prune=no
only=""
SUFFIX=.md
while [ $# -gt 0 ]; do
  case "$1" in
    --prune) prune=yes ;;
    --commit) SUFFIX=.commit.txt ;;
    --name)
      [ -n "${2:-}" ] || die "$USAGE"
      only="$2"
      shift
      ;;
    *) die "$USAGE" ;;
  esac
  shift
done
[ -z "$only" ] || [ "$prune" = no ] || die "$USAGE"

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
REPORTS="$PROJECT/.reports"

if [ -n "$only" ]; then
  name="$(report_name "$only")" || exit 1
  printf '%s/%s\n' "$REPORTS" "$name"
  exit 0
fi

if branch="$(git -C "$PROJECT" symbolic-ref --short -q HEAD)"; then
  name="$(report_name "$branch")" || exit 1
else
  sha="$(git -C "$PROJECT" rev-parse -q --verify HEAD)" || die "HEAD is neither a branch nor a commit"
  name="detached-${sha:0:12}$SUFFIX"
fi

mkdir -p "$REPORTS" || die "cannot create $REPORTS"
latest="$REPORTS/latest$SUFFIX"
if [ -e "$latest" ] && [ ! -L "$latest" ]; then
  die "$latest is a regular file, not a pointer; move it away so it is not overwritten"
fi

# prune_kind EXT WHAT: delete the stale .reports/*EXT files, keeping latest<EXT>, the file it
# points at, and the current branch's file.
prune_kind() {
  local ext="$1" what="$2" keep current file base
  keep="$(readlink "$REPORTS/latest$ext" 2>/dev/null || true)"
  keep="${keep##*/}"
  current="${name%"$SUFFIX"}$ext"
  for file in "$REPORTS"/*"$ext"; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    base="${file##*/}"
    case "$base" in "latest$ext" | "$keep" | "$current") continue ;; esac
    if ! grep -qxF -- "${base%"$ext"}" <<<"$known"; then
      rm -f -- "$file" && echo "harness-kit: removed the stale $what .reports/$base (no local branch has that name)" >&2
    fi
  done
}

if [ "$prune" = yes ]; then
  known="$(git -C "$PROJECT" for-each-ref --format='%(refname:short)' refs/heads |
    while IFS= read -r b; do printf '%s\n' "${b//\//-}"; done)"
  prune_kind .md report
  prune_kind .commit.txt "commit draft"
fi

ln -sfn "$name" "$latest" || die "cannot point $latest at $name"
printf '%s/%s\n' "$REPORTS" "$name"
