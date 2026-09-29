---
name: plan
description: Write the branch's brief before any work starts. Reads the project's spec and setup, raises any OPEN spec rule the goal touches, and writes .reports/<branch>.brief.md with fixed sections (goal, scope, spec rules, acceptance tests, verification plan, blast radius, new thresholds, protected files) for the person to approve with approve-brief.sh. ship.sh will not start a review without an approved brief. Started only by the person, with the goal.
argument-hint: <the goal of this branch, in the person's words>
disable-model-invocation: true
---

# Plan the branch: write its brief

The person wants this done on the current branch:

> $ARGUMENTS

If that is empty, or too vague to say which files would change, ask the person what they want and why, and stop until they answer.

Your job here is the brief, and only the brief. **Change no other file**: no code, no tests, no spec, no `.harness/` file, no commit. The work starts after the person approves the brief, in their own terminal.

## 1. Where the brief goes

The brief is `.reports/<branch>.brief.md`: the report path the harness-kit SessionStart line gave you, with `.md` replaced by `.brief.md` (for `.reports/feat-login.md`, `.reports/feat-login.brief.md`). If there was no report line, it is the branch name with every `/` replaced by `-`, in `.reports/` at the project root. If a brief is already there, read it first: you are revising it, and the person approves the new one.

Never write `.reports/<branch>.brief.approved`, and never run `approve-brief.sh`: the approval is the person's. The harness-kit hooks refuse both to you: the script, and any file tool or shell command that names an approval file (read one with the Read tool). The script also refuses to run without a terminal.

## 2. Read the project

Read what exists of:

- `.harness/review-reads`: every path it lists. The first is the project's spec. Find the spec's rules (each has an id, such as `S12` or `AUTH-3`) that the goal touches.
- `.harness/protected-paths`: the files the person approves changes to (a folder line ends in `/`).
- `.harness/check-command`, `.harness/review-checklist.md`, `.harness/mutations.tsv` and `.harness/check-files`: how the project checks itself.
- The project's own instructions (`CLAUDE.md`, the README) for its standing-question step: how it asks the person to set a new threshold (a limit, a timeout, a budget, a retry count, a size) instead of Claude choosing one.
- The code the goal will change, enough to say which files change and which tests prove it.

## 3. OPEN rules come first

If a spec rule the goal touches is marked OPEN (its status says OPEN, or it says the person has not decided it yet), **stop before planning further**. Tell the person, for each one: its id, what it says, and the question it leaves open, with the options you can see and what each would mean for this goal. Wait for their answer. Do not choose for them, and do not write a brief that assumes an answer. Once they have answered, write the brief with their answer in it (quoted), and say that the spec itself still says OPEN until it is updated.

## 4. Write the brief

Replace what is in the file. Use exactly these sections, in this order, each a `##` heading with these words. Write plain, full sentences, one idea to a sentence; no tables, no shorthand. A section with nothing in it says so in a sentence ("No spec rule is touched."), never an empty heading.

```
# Brief: <the goal, in one line>

## Goal
## Scope
## Spec rules touched
## Acceptance tests
## Verification plan
## Blast radius
## New thresholds
## Protected files expected
```

What goes under each:

- **Goal.** What the branch will do, and why, in two to four sentences, in the person's terms. Say how the person will know it is done.
- **Scope.** Every file expected to change, by its path from the project root, each with one sentence saying what changes in it. Then, under the sentence "Out of scope:", what this branch will not do, even though it is close by, so that the reviewer can hold the diff to it.
- **Spec rules touched.** Each rule by its id, with what it says and whether the branch implements it, changes it or relies on it. Name any rule marked OPEN, with the person's answer from step 3. If there is no spec (no `.harness/review-reads`), say so.
- **Acceptance tests.** Each test the branch will add or change: where it goes, what it checks, and what makes it fail (the wrong behaviour it catches). A test that cannot fail proves nothing, so every test here names its failure.
- **Verification plan.** Each command the work will run that you expect to take over 2 minutes (a whole check, a fault replay, an evaluation, a slow test file): the command, its estimated time and what the estimate rests on (a measured time, with where it was measured, or why there is none), what it proves, and which earlier proof it repeats. No two steps prove the same thing: a step that would only repeat another's proof is left out, and any repeat that stays (a gate that always runs, such as the Stop hook's check) is named, with why. No step takes over 10 minutes: split longer work (a replay into parts, a suite into its files), and start each long step under a hard limit below 10 minutes. The session's time rule lets Claude run a command over 2 minutes only if this section lists it. If nothing will take over 2 minutes, say so.
- **Blast radius.** Every file, comment, test and document that describes the behaviour this branch changes, found by searching the project (names, messages, flags, file names, the words a person would use). Each one is either in the Scope, or listed here with why it stays as it is.
- **New thresholds.** Each new number the change needs a value for (a limit, a timeout, a budget, a retry count, a size), with what it limits. Each one goes through the project's standing-question step: say so, and do not pick the value yourself. If the project has no standing-question step, say that, and list the thresholds as questions for the person. If there are none, say so.
- **Protected files expected.** Each file in `.harness/protected-paths` (or under a folder line there) that the branch expects to change, and why. Those changes go to the person as a patch that they apply with `land.sh`, which runs the approval; you never commit them. If there are none, say so.

## 5. Hand it to the person

End your turn with:

1. The brief's path.
2. Any OPEN rule, new threshold or question still waiting for the person.
3. Under "Your commands", the approval, run by the person in their own terminal from anywhere inside the project: `<the harness-kit plugin folder>/scripts/approve-brief.sh` (the folder that holds this skill's `skills/` folder). It shows the brief and asks "Approve this brief? [y/N]"; on y it records the brief's sha256.

Then stop. Do not start the work until the person tells you to. Any change to the brief after it is approved, even a word, makes the approval stop matching: `ship.sh` then stops before the review, and the reviewer is told. If the work shows the brief was wrong, change the brief, say what changed, and ask the person to approve it again, rather than drift from it.

When you do the work later, the brief is what you are measured against: the report's "Deviations:" heading names anything done differently from it or beyond it, and the reviewer judges the diff's scope against it.
