# Shared by approve-brief.sh, review.sh and ship.sh, which source it: where a branch's brief
# and its approval are, and whether the approval matches the brief. Written for bash 3.2
# (macOS).
#
# THE BRIEF is .reports/<branch>.brief.md (report-path.sh --name <branch> --brief), written
# by the plan skill (/plan <goal>). THE APPROVAL is .reports/<branch>.brief.approved, written
# only by approve-brief.sh when the person answers y (git-guard.mjs and brief-guard.mjs deny
# Claude writing it, by any tool, outside scratch copies): one line, the brief's sha256 in
# lowercase hex. Both are for the person, not for git (check-reports.mjs fails if either is
# tracked), and ship.sh deletes both when the branch ships.

# brief_sha256 FILE: prints FILE's sha256, lowercase hex.
brief_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum <"$1" | cut -d' ' -f1
  else
    shasum -a 256 <"$1" | cut -d' ' -f1
  fi
}

# brief_load PROJECT BRANCH: sets, for BRANCH's brief,
#   BRIEF           the brief's path, relative to PROJECT (.reports/<branch>.brief.md)
#   BRIEF_APPROVAL  the approval's path, relative to PROJECT (.reports/<branch>.brief.approved)
#   BRIEF_SHA       the brief's sha256 now (empty when there is no brief)
#   BRIEF_RECORDED  the approval's first line (empty when there is no approval)
#   BRIEF_STATE     missing     there is no brief
#                   unapproved  a brief, and no approval
#                   changed     an approval that does not hold the brief's sha256: the brief
#                               changed after the person approved it
#                   approved    an approval holding the brief's sha256
# Returns 1, with the reason in BRIEF_ERROR, when BRANCH has no brief name (report-path.sh
# refuses it).
brief_load() {
  local project="$1" branch="$2" path
  BRIEF="" BRIEF_APPROVAL="" BRIEF_SHA="" BRIEF_RECORDED="" BRIEF_STATE="" BRIEF_ERROR=""
  path="$(cd "$project" && bash "$(dirname "${BASH_SOURCE[0]}")/report-path.sh" --name "$branch" --brief 2>&1)" ||
    { BRIEF_ERROR="$path"; return 1; }
  BRIEF="${path#"$project"/}"
  BRIEF_APPROVAL="${BRIEF%.md}.approved"
  if [ ! -f "$project/$BRIEF" ]; then
    BRIEF_STATE=missing
    return 0
  fi
  BRIEF_SHA="$(brief_sha256 "$project/$BRIEF")"
  if [ ! -f "$project/$BRIEF_APPROVAL" ]; then
    BRIEF_STATE=unapproved
    return 0
  fi
  BRIEF_RECORDED="$(head -n 1 "$project/$BRIEF_APPROVAL" | tr -d '\r[:space:]')"
  if [ "$BRIEF_RECORDED" = "$BRIEF_SHA" ]; then BRIEF_STATE=approved; else BRIEF_STATE=changed; fi
}

# brief_optional PROJECT: returns 0 when the project has made briefs optional, the person's
# decision per project: .harness/brief-optional is committed (at HEAD) and HEAD's
# .harness/protected-paths lists it (by its path, or a folder line ending "/" above it; the
# format check-commits.mjs reads), so a change to it goes through land.sh and the approval.
# Otherwise returns 1, with BRIEF_OPTIONAL_WHY saying why when the file is there but is not
# honoured (empty when there is no such file).
brief_optional() {
  local project="$1" file=.harness/brief-optional
  BRIEF_OPTIONAL_WHY=""
  if ! git -C "$project" cat-file -e "HEAD:$file" 2>/dev/null; then
    [ ! -e "$project/$file" ] || BRIEF_OPTIONAL_WHY="$file exists but is not committed, so it is not honoured"
    return 1
  fi
  git -C "$project" show HEAD:.harness/protected-paths 2>/dev/null | tr -d '\r' |
    awk -v f="$file" '
      { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); sub(/^\.\//, "") }
      $0 == "" || /^#/ { next }
      $0 == f || (/\/$/ && index(f, $0) == 1) { found = 1 }
      END { exit found ? 0 : 1 }' && return 0
  BRIEF_OPTIONAL_WHY="$file is committed but .harness/protected-paths does not list it, so it is not honoured: only a protected file (changed through land.sh and the approval) can make briefs optional"
  return 1
}

# brief_review_section PROJECT BRANCH: prints the body of the BRIEF section of the reviewer's
# input (review.sh): the brief's path, whether its approval matches, and the brief itself.
brief_review_section() {
  local project="$1" branch="$2"
  if [ "$branch" = "(detached)" ] || ! brief_load "$project" "$branch"; then
    echo "none: HEAD is not on a branch with a brief name, so there is no brief"
    return 0
  fi
  if [ "$BRIEF_STATE" = missing ]; then
    if brief_optional "$project"; then
      echo "none: this branch has no brief ($BRIEF); the project makes briefs optional (.harness/brief-optional, protected)"
    else
      echo "none: this branch has no brief ($BRIEF)"
    fi
    return 0
  fi
  echo "brief: $BRIEF"
  case "$BRIEF_STATE" in
    approved) echo "approval: MATCHES: $BRIEF_APPROVAL holds this brief's sha256 ($BRIEF_SHA); the person approved the brief as it is below" ;;
    changed) echo "approval: DOES NOT MATCH: $BRIEF_APPROVAL holds $BRIEF_RECORDED, but this brief's sha256 is $BRIEF_SHA: the brief changed after the person approved it" ;;
    *) echo "approval: NONE: there is no $BRIEF_APPROVAL; the person has not approved this brief" ;;
  esac
  echo
  cat "$project/$BRIEF"
}
