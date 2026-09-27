#!/usr/bin/env bash
# Print the path of Claude's final report for the current branch.
#
#   report-path.sh               print $PROJECT/.reports/<branch>.md, create .reports/ and
#                                point .reports/latest.md at that file (a relative symlink)
#   report-path.sh --prune       the same, after deleting stale reports (below)
#   report-path.sh --name BRANCH print the path for BRANCH only; creates and changes nothing
#
# Run from anywhere inside the project's git repository. <branch> is the branch name with
# every "/" replaced by "-"; on a detached HEAD it is "detached-<first 12 of the sha>".
# This is the only place the name is worked out: session-start.mjs and ship.sh call it.
#
# STALE REPORTS (--prune): a .reports/*.md file is deleted when no local branch maps to its
# name. latest.md itself, the file latest.md points at when --prune starts, and the
# current branch's report are never deleted. The "/" to "-" mapping is not reversible, so
# the check goes from branches to names, never from a name back to a branch.
#
# Reports are for the person to read, not for git: check-reports.mjs fails if any file
# under .reports/ is tracked.
set -u

die() {
  echo "harness-kit report-path.sh: $*" >&2
  exit 1
}

report_name() {
  local name="${1//\//-}"
  [ "$name" != latest ] || die "the branch \"$1\" would be named latest.md, which is the pointer to the latest report; rename the branch"
  printf '%s.md' "$name"
}

prune=no
only=""
case "${1:-}" in
  "") ;;
  --prune) prune=yes ;;
  --name)
    [ -n "${2:-}" ] || die "usage: report-path.sh [--prune | --name BRANCH]"
    only="$2"
    ;;
  *) die "usage: report-path.sh [--prune | --name BRANCH]" ;;
esac

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
  name="detached-${sha:0:12}.md"
fi

mkdir -p "$REPORTS" || die "cannot create $REPORTS"
latest="$REPORTS/latest.md"
if [ -e "$latest" ] && [ ! -L "$latest" ]; then
  die "$latest is a regular file, not a pointer; move it away so it is not overwritten"
fi

if [ "$prune" = yes ]; then
  keep="$(readlink "$latest" 2>/dev/null || true)"
  keep="${keep##*/}"
  known="$(git -C "$PROJECT" for-each-ref --format='%(refname:short)' refs/heads |
    while IFS= read -r b; do printf '%s.md\n' "${b//\//-}"; done)"
  for file in "$REPORTS"/*.md; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    base="${file##*/}"
    case "$base" in latest.md | "$keep" | "$name") continue ;; esac
    if ! grep -qxF -- "$base" <<<"$known"; then
      rm -f -- "$file" && echo "harness-kit: removed the stale report .reports/$base (no local branch has that name)" >&2
    fi
  done
fi

ln -sfn "$name" "$latest" || die "cannot point $latest at $name"
printf '%s/%s\n' "$REPORTS" "$name"
