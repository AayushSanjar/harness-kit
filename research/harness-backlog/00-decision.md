# 00 — Decision: a 9/10 harness, a backlog on GitHub Issues, and a start agent

Written on Wednesday 30 September 2026. Research and drafting only; nothing was created on GitHub.

**Terms.**
- *Harness*: everything around the AI model that shapes and checks its work.
- *Epic, Story, Task, Bug*: work items from large to small (file 03).
- *Sub-issue*: an issue linked under a parent issue.
- *Project*: GitHub's board over issues, with fields such as *Status* and *Priority*.
- *Start agent*: the `/harness-kit:start` capability designed in file 04.
- *Fault replay*: harness-kit's 137 planted faults.
- Labels: *[VERIFIED]* primary source; *[PARTIAL]* secondary or partial; *[ASSUMPTION]* my reasoning; *NOT FOUND* searched, nothing found.

**Evidence.** 352 distinct sources, 315 of them primary. They were chosen by going to the owner's own page for each question (Anthropic, OpenAI, GitHub documentation source, each tool's repository), then to 10 open-source projects for practice. Of the sub-agents' reading rows, 201 were full reads and 151 were extracts through a summarising tool. Five sub-agents did the reading; I checked their harness-kit claims in the repository and ran the live checks below myself.

## Contradictions

1. **The full fault replay is about 11 to 12.5 minutes, not 25.** It is 10.9 minutes on `main` and 12.4 on the branch since v0.20.0. [VERIFIED | GitHub API, runs 36697420941 and 36695203471]
2. **Sub-issues work on a personal account, despite a forum claim that they do not.** `simonw/datasette` (owner type "User") has an issue with 36 sub-issues. [VERIFIED | GitHub API, 2026-09-30]
3. **`Fixes #N` in a commit pushed straight to `main` closes the issue, with no pull request.** `simonw/datasette` commit `9cdf95ac2c` is in no pull request and closed issue #2446. [VERIFIED | GitHub API] So `release.sh` can close issues.
4. **Issue types (Bug, Feature, Task) and issue fields exist only for organisations.** Types must be labels. [VERIFIED | github/docs]
5. **Epic > Feature > Story is neither Jira's nor GitHub's default, and none of 10 large projects uses more than one level above the working issue.** [VERIFIED | Azure DevOps docs; the projects' own files]
6. **All 8 recorded escaped defects are in harness-kit's own machinery.** Anthropic advises removing harness parts that are "no longer load-bearing". [VERIFIED | .harness/defects.tsv; anthropic.com, 2026-03-24] More custom gates has not meant fewer defects.
7. **No existing tool picks from a backlog you wrote and enforces your approval in code.** `gh issue develop` creates branches on GitHub, not locally. [VERIFIED | ccpm, spec-kit and gh source]

## Score today and the path to 9/10

**harness-kit scores 4.4 out of 10** on 14 dimensions (file 01). [ASSUMPTION: my scores on verified evidence]
- **Strongest (6 to 7):** the brief and its approval, the hooks, the Stop gate, the reviewer, and turning defects into checks.
- **Weakest (2 to 3):** plans kept outside the repository, no sandbox, no evals of the AI parts, harness-kit not running its own guards, and the amount of custom code.

**The path.** The following six moves reach about 7.5 to 8; 9 also needs the deferred items (full evals, pruning, a second project).
1. Put the plan and the backlog in the repository and on GitHub.
2. Replay faults before `main` moves.
3. Run harness-kit under its own plugin.
4. Add sandbox and permission rules.
5. Evaluate the AI parts.
6. Simplify.

## Recommended setup (file 06)

- **Labels** for type: `type:epic`, `type:feature` (optional), `type:story`, `type:task`, `type:bug`, plus `regression`, `needs-decision` and `deferred`.
- **Sub-issues** for the hierarchy.
- **One user project** with Status (Backlog, Ready, In progress, In review, Done), Priority (P1 to P3) and Size (S, M, L); a board, a backlog table and a deferred list.
- **Issue forms** that require a Why line, acceptance criteria and a Source.
- `Fixes #N` in the released commit closes issues.
- `docs/STATE.md` and `docs/DECISIONS.md` in the repository.
- **The start agent:** a script picks the Ready item by Priority, creates the branch locally, and Claude writes the brief; you approve, build proceeds, and you release. A new hook refuses every `gh` write except one status comment.

**The backlog draft** (file 07) has 9 epics and 65 items: 51 active, 12 deferred with your triggers, 1 already done and 1 dropped by the CI research.

## The first three steps

**Step 1 — Set up GitHub and import epics E1 to E4 (backlog items 1.1 and 1.2).**
- **Who:** you do the screens with file 08. Claude Code, in the harness-kit folder, writes the label script and the forms, and paces the import.
- **Counter-case:** a second place where the plan lives, and a classic token scope (`project`).
- **What would change it:** if the board proves unused after two weeks, drop the project and keep labels.
- **Confidence:** high that it works; medium that you will keep it up.

**Step 2 — Put the plan in the repository and run harness-kit under its own plugin (items 1.3, 1.4 and 3.1).**
- **Who:** Claude Code in the harness-kit folder, through the usual brief, approval and release.
- **Counter-case:** your own guards will now block you inside harness-kit, and loading the released plugin means you test the previous release, not the one being built.
- **What would change it:** if false blocks are frequent, fix those guards first (Epic 8).
- **Confidence:** high.

**Step 3 — Replay every fault on each branch push (items 2.1.1 and 2.1.2).**
- **What:** one condition in `validate.yml`, plus a wait limit chosen from measured runs. This stops `main` turning red after releases and automates what you already do by hand.
- **Who:** Claude Code in the harness-kit folder.
- **Counter-case:** about 12 more minutes before each release, and a test that fails only sometimes now blocks a release (item 2.1.3 must follow).
- **What would change it:** if branch replays grow past about 15 minutes, balance the shards (2.2.2) first.
- **Confidence:** high.

**Why not the start agent first?** It needs the backlog and the repository files to exist. Its cheapest part, a "Next step" line at session start (item 4.1), can be done at any time.

**Who does what overall.** Cowork was right for this research, because it needed the web, your repository and GitHub's public data together. Claude Code in the harness-kit folder is right for every build step.
