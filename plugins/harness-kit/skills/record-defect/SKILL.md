---
name: record-defect
description: Turn an escaped bug into a permanent guard. Finds the commit that introduced it, writes a protected test that fails because of it, fixes it, records a platform fact if the platform caused it, appends a line to .harness/defects.tsv and proposes a reviewer-evaluation case. Started only by the person, with a description of the bug.
argument-hint: <what went wrong, where it was seen, and how>
disable-model-invocation: true
---

# Record an escaped defect

The person found a bug that got past every check. Your job is to make sure this kind of bug is caught next time, and to leave a record of it. The bug, as the person described it:

> $ARGUMENTS

If that is empty or too vague to reproduce, ask the person what they saw, where (live, in a review, in a check, or themselves) and how to make it happen, and stop until they answer.

Work in this order. Each step says what counts as done; do not claim a step you could not finish, say so in the report instead.

## 1. Read the project's setup

Read what exists of: `.harness/check-command` (the first line is the project's check), `.harness/protected-paths`, `.harness/approve-command`, `.harness/review-reads` (its first path is the project's spec), `.harness/defects.tsv`, `.harness/mutations.tsv`, `.harness/check-files` and `.harness/reviewer-eval/cases.tsv`. Find where the project's tests live and how the check runs them.

## 2. Write the failing test first

Before you change any product code, write a test that fails **because of this bug**: it asserts the right behaviour, and its failure message names the bug. A test that fails because of a crash, a missing import or a typo in the test does not count. Put it where the project's check command runs it, in the style of the tests next to it, and give it a name the check prints on its PASS or FAIL line.

Run it (through the check command, or the narrowest command that runs it) and keep the exact FAIL line for the report. Done when you have that line.

## 3. Find the commit that introduced the bug

1. Find candidates: `git log -S'<text>'` or `git log -G'<regex>'` on the code at fault, `git blame` on the lines, `git log --follow -- <file>`.
2. Confirm one: in a temporary worktree (`git worktree add --detach <temp folder> <commit>`), copy the new test in and run it at the candidate and at its parent. The introducing commit is the one where the test fails and at whose parent it passes. If the parent cannot run the test at all (the feature did not exist yet), the introducing commit is the one that added the feature; say that in the report. When there are many candidates, `git bisect run` in that worktree finds it.
3. Remove the worktree (`git worktree remove --force <folder>`), also when a step failed. Never change the branch the person is on.

Done when you have the commit's full hash and the two runs' result lines. If you cannot find it, the hash is `unknown` and the report says why.

## 4. Protect the test

Add the test file's path to `.harness/protected-paths`, unless a line there already covers it (a folder line ends in `/`). The test is new, so the person approves it: after you finish, they run the project's approval command, the first line of `.harness/approve-command`, in their own terminal (`land.sh` also runs it). **Never run the approval command yourself, and never edit what it writes.** Put the command in "Your commands".

## 5. Fix the bug

Make the smallest change that makes the new test pass without weakening any other test. Run the new test (keep its PASS line) and then the whole check command (keep its final line). The Stop hook will not let you finish while the check fails.

## 6. A platform fact, if the platform caused it

If the cause was the platform's behaviour (a framework, runtime, library, API, browser or operating system doing something the code did not expect), not the project's own logic, add one fact to the project's spec, the first path in `.harness/review-reads`, in its platform facts section (make one, `## Platform facts`, if there is none). State what the platform does, in one or two sentences, and its source: the documentation's URL with the date you read it and the exact words quoted, or the experiment that showed it (the command and its output). If there is no review-reads file, do not guess where the spec is: put the fact in the report under "Decide".

## 7. The defect's line in `.harness/defects.tsv`

Append exactly one line. Create the file with the header comment below if it does not exist. **The file is append-only: never change or remove a line already in it.** `check-defects.mjs` fails a branch that changes or removes a line that was there at its merge-base, or adds a line not in this format.

```
# Escaped defects, one per line, tab-separated, append-only (harness-kit record-defect; checked by check-defects.mjs):
#   date  id  description  where-found  introducing-commit  test-added  fixing-commit
```

| Field | What goes in it |
|---|---|
| date | Today, `YYYY-MM-DD`. |
| id | `D` and the next number (`D1`, `D2`, ...): letters, digits, `.`, `_` or `-`, unique in the file. |
| description | One sentence: what went wrong, for whom. No tabs. |
| where-found | Exactly one of `live` (users or production), `review` (the reviewer, after its checks passed), `check` (a check that was not the one meant to catch it), `person` (the person noticed). |
| introducing-commit | The full hash from step 3, or `unknown`. |
| test-added | The test's path, a space, and its name as the check prints it. |
| fixing-commit | `this`: the commit that adds this line, which must also hold the fix. Git resolves it (`git blame` on the line); `check-defects.mjs` fails a `this` whose commit changes nothing but `.harness/defects.tsv`, and `node check-defects.mjs --resolve` prints the file with each `this` replaced by its commit. A hash only when the fix was committed before this line, such as a hotfix already shipped. |

No field may hold a tab or a line break.

## 8. Proposals for the person (in the report; do not add them)

1. **A reviewer-evaluation case**: one line for `.harness/reviewer-eval/cases.tsv` in its format (`id  defect  base  head  file-regex  keyword-regex  [spec-replacement]  [na_items]  [expected_item]`), with `head` the introducing commit, `base` its parent, a file regex naming the file the bug was in, and a keyword regex with words a reviewer would use for it. If the spec now holds text that gives the fix away, say which lines a spec replacement must leave out. Running an evaluation costs money, so the person decides whether to add and run it.
2. **A fault replay**: one line for `.harness/mutations.tsv` that puts the bug back (`id  file  find  replacement  check`: the fixed text, found exactly once in the file, with no version such as 0.9.0 and no date such as 2026-09-27 in it, which `replay-faults.sh` rejects as a fragile entry; the buggy text; the new test's name as the check prints it) and the matching `.harness/check-files` line (`name<TAB>test path`), so `replay-faults.sh` can prove the test keeps catching it. Give it only when the fix is a text change that a single find and replace undoes.

## 9. Report and commit draft

Write the report and the commit message draft where the harness-kit SessionStart lines say, as usual. In the report's Evidence, quote the new test's FAIL line before the fix, its PASS line after, the two runs that pin the introducing commit, and the check command's final line. The commit draft's body names every protected file changed (`.harness/protected-paths`, the new test, the spec if it is protected) with the reason, has a `Breaks:` line for the new test (what makes it fail: this bug), and a `Told:` line for any number from the person's description.

Never commit, push, run `land.sh`, `ship.sh`, `release.sh`, `upgrade.sh`, `review.sh` or `eval-reviewer.sh`, or run the approval command: those are the person's steps. (This skill's change always touches a protected file, the new test, so it is never Claude's to commit; the git-guard hook refuses a push and the person's scripts outside the temp folder anyway.)
