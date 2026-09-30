# 07 — harness-kit backlog draft (question G)

Written on Wednesday 30 September 2026. This is a draft in tables. No issue has been created.

## Terms used in this file

- **Epic, Feature, Story, Task, Bug.** As defined in file 03.
- **ID.** The draft's own numbering, for example `2.1.1` means Epic 2, Feature 1, item 1. GitHub will give each issue its own number when it is created.
- **Order.** The suggested order of work across the whole backlog: 1 is first. It is a suggestion for you to set as Priority; the agent never sets it.
- **Size.** S means under half a day of your attention; M means one increment; L means it must be split before it is Ready (file 06).
- **Repo check.** What I found in the harness-kit repository (commit e275280, v0.20.0) on 30 September 2026:
  - **DONE:** already built; no issue is needed.
  - **PARTIAL:** some of it exists; the item covers the rest.
  - **NOT DONE:** the repository confirms the gap.
  - **NOT FOUND:** a thing the item assumes exists or happens was searched for and not found.
  - **CONFIRMED:** a problem the item assumes is real.
  - **CHANGED:** the CI research changes the item; the new wording is given.
  - **DROPPED:** the research says not to do it.
- **Deferred.** Kept for later, with the label `deferred` and a trigger: the event that should make you start it.
- **Front page.** The short plain-language section at the top of a brief or Summary: Current state, Problem, Change, Final outcome, What I decide, Time and risk.
- **Map file.** A short instruction file (`CLAUDE.md` importing `AGENTS.md`) that tells Claude where everything is.

## How this file is based on evidence

**Sources.** This file rests on the findings of files 01 to 06 and on `research/ci-and-github/` (including `07-independent-review.md`). It cites 13 direct sources, of which 11 are primary:
- harness-kit's own files, read in full on your Mac;
- GitHub's public record of harness-kit's CI runs;
- your stated plan of 29 and 30 September 2026, which lists your decisions and your triggers for deferred items.

**How each repo check was made.** Every item you listed was checked against the repository by reading the named file or by searching all scripts, tests and workflows for the relevant words. A search that found nothing is reported as NOT FOUND or NOT DONE, with what was searched.

**Where the CI research changed an item.** This happened in four places: 2.1.1, 2.1.4, 2.2.2 and 2.2.3.

**What this file leaves out.** Nothing about any product that uses harness-kit is in this file. Consumer projects are mentioned only in general terms.

**Labels.**
- [VERIFIED] means a primary source says it.
- [PARTIAL] means secondary or partly supported.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

Each repo check below is [VERIFIED] from the file named. Each description, acceptance criterion and order is [ASSUMPTION], a draft for you to change.

## CONTRADICTIONS

1. **"Full fault replay about 25 minutes in CI" is out of date.** Since v0.20.0 the whole replay run takes 10.9 minutes on `main` and 12.4 minutes on the branch. [VERIFIED | GitHub REST API, runs 36697420941 and 36695203471] This makes "replay before `main` moves" cheap enough to do on every release, and it changes item 2.1.1.
2. **"Main turned red after releases four times in two days" is confirmed, and the causes are known.** Three runs failed on 29 September (6f5e876, 0a07bd1, f84515e) and one was cancelled after 46.9 minutes on 28 September (a8f033e). [VERIFIED | GitHub REST API run list] The defect log names the causes:
   - D4: runs interfering with each other through a shared registry;
   - D6: a new fault entry "never replayed or planted before it shipped";
   - D8: a Stop-gate skip that failed intermittently.
   [VERIFIED | .harness/defects.tsv, full read] All three are the harness's own machinery, not product changes.
3. **You already practise the fix by hand.** On 29 September a manual full replay ran on `inc-speed-a-fix-1` eight seconds after its push, before release. [VERIFIED | GitHub REST API, run 36645873004] Item 2.1.1 makes this automatic instead of something you must remember.
4. **The "lean backlog" you planned inside harness-kit (a protected backlog file and a `/harness-kit:backlog` command) is replaced by GitHub Issues,** as you decided on 30 September. [VERIFIED | your stated plan] Its useful parts become Epic 1 and Epic 4.

## The epics, in suggested order

| Order | Epic | Outcome | Why this position |
|---|---|---|---|
| 1 | E1 The plan lives in the repository and on GitHub Issues | You can see what is next, why, and where things stand, without chat | Everything else needs a place to live |
| 2 | E2 Faults are found before `main` moves, and CI stays fast as tests grow | `main` never turns red after a release; waiting stays flat as tests grow | Fixes your two most visible problems |
| 3 | E3 harness-kit runs under its own harness | Every guard protects harness-kit's own work | Cheap, and it tests the harness where you use it most |
| 4 | E4 Starting work is one command | `/harness-kit:start` runs an item through the process | Needs E1's backlog to exist |
| 5 | E5 Every increment is plain to read and verified within budget | Briefs and Summaries open with a front page; size and time budgets hold | Your own planned "front page" and "verification discipline" |
| 6 | E6 The AI parts are measured | You know whether the reviewer finds real problems | Your planned reviewer eval |
| 7 | E7 Least privilege and supply chain | The agent's reach is fenced | Mostly deferred to your "before auto mode" trigger |
| 8 | E8 A simpler harness | Less custom code to maintain | Decisions, not builds |
| 9 | E9 Reuse by other projects | Adopting a release is one step | Needs the rest to be stable first |

---

## E1 — The plan lives in the repository and on GitHub Issues (order 1)

**Decisions behind this epic.**
- The backlog lives in GitHub Issues, one backlog per repository. [your decision, 30 September 2026]
- Types are labels, because issue types are organisation-only (file 02).
- Status and Priority are project fields (file 06).
- State and decisions live in committed files, because both vendors keep plans and decision logs in the repository (file 01, contradiction 4).

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 1.1 | Task | Set up labels, the project and issue forms | Create the labels, the user project (Status, Priority, Size, three views, built-in workflows) and one issue form per type, as in file 06. You do the settings screens using file 08; Claude Code writes the form files and a label script after you approve. | (1) Labels exist as listed in file 06. (2) The project has the fields and views listed. (3) `.github/ISSUE_TEMPLATE/` holds five forms and `config.yml`. (4) A test issue with one sub-issue shows the parent's progress. | files 02, 06, 08 | NOT DONE: no `.github/ISSUE_TEMPLATE/`, no issues | M | 1 |
| 1.2 | Task | Import this backlog as issues | Create one issue per row of this file: epics first, then children as sub-issues, deferred items with their trigger. Pace the writes at one per second or slower. | (1) Every row has an issue. (2) Every child is a sub-issue of its epic or feature. (3) No rate-limit error. (4) Rows marked DONE or DROPPED are not created, or are created closed as "not planned", as you choose. | file 02 (rate limits) | NOT DONE | M | 2 |
| 1.3 | Task | Add a map file for Claude | Add `AGENTS.md` (about 100 lines: what harness-kit is, the folder layout, the commands, the rules, what done means, where state and decisions live) and a `CLAUDE.md` that imports it. Include the list of decisions that stay with you (file 05). | (1) Under 200 lines together. (2) A check fails if a path named in them does not exist. (3) A new session in harness-kit shows the file loaded. | file 01 D1; code.claude.com memory docs | NOT DONE: no `CLAUDE.md` or `AGENTS.md` at the root | S | 3 |
| 1.4 | Story | Keep `docs/STATE.md` current | A file of at most about 40 lines saying what is released, what is in progress and what is next, updated in each increment's commit. | Given an increment that releases a change, when its last commit is made, then `docs/STATE.md` names the new version and the next Ready item; a check fails if the named version differs from `plugin.json`. | file 01 D11; your plan | NOT DONE: no state file | S | 4 |
| 1.5 | Story | Build `docs/DECISIONS.md` from commit `Decision:` lines | A script lists every `Decision:` line with its commit and date. It runs at release, so the reasons for choices can be read in one place. | Given commits with `Decision:` lines, when the script runs, then each appears once with its commit id, and the release fails if the file is out of date. | file 06; your practice | PARTIAL: commits carry `Decision:` lines, and `check-commits.mjs` and `upgrade-draft.mjs` read them; no index file exists | S | 5 |
| 1.6 | Task | Decide whether approved briefs are committed | Approved briefs are never committed today because `.gitignore` excludes `.reports/`. Decide whether a copy of each approved brief goes to `docs/briefs/` in the release commit. | A `Decision:` line records the choice and its reason. | file 01 contradiction 4 | CONFIRMED: `.gitignore` is exactly `.reports/` | S | 6 |
| 1.7 | Task | Reorganise `research/` into topic folders with an index | Move the eight top-level research files into topic folders and make `research/README.md` list every folder with one line each. | (1) No research file at the top level except `README.md` and `sources.csv`. (2) Every link inside the research files still resolves (a check). | your plan | PARTIAL: `ci-and-github/`, `ci-process-overview/`, `design/` and `harness-backlog/` exist; eight files remain at the top level; `research/README.md` lists only those eight | S | 7 |
| 1.8 | Task | Record corrections to earlier research | Add a short "Corrections" section where later findings changed earlier ones: the 25-minute replay, sub-issues on personal accounts, `Fixes #N` on direct pushes. | Each correction names the old claim, the new evidence and the date. | your plan ("research-journal corrections, any time") | NOT DONE | S | 8 |

## E2 — Faults are found before `main` moves, and CI stays fast as tests grow (order 2)

**Decisions behind this epic.**
- Every release runs the full fault replay on the branch and is released only with 0 SURVIVED, 0 TIMEOUT and 0 ERROR. [your decision, 29 September 2026]
- Waiting time must stay flat as tests grow, with no drop in quality. [your requirement, 30 September 2026]
- The CI research recommends making the replay part of the branch push's own run. [research/ci-and-github/07-independent-review.md, change 1]

### F2.1 The replay runs before `main` moves

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 2.1.1 | Story | Run the full fault replay on every branch push | **CHANGED:** your list said "a targeted fault replay in CI on every branch push". The CI research recommends the full replay, because it takes about 11 to 12.5 minutes and `release.sh` is what pushes the branch. Change the replay jobs' condition in `validate.yml` so every branch push runs them; `release.sh` then waits for them with no new code. | Given a branch push that changes no machinery file, when CI runs, then the baseline, 8 shards and verdicts jobs run. Given a branch where one fault survives, when you run `release.sh`, then it stops before `main` moves and names the run. | 07-independent-review.md change 1 | NOT DONE: the replay jobs' `if:` covers only `main`, machinery changes, the schedule and manual starts (`validate.yml`) | M | 9 |
| 2.1.2 | Task | Raise `SHIP_CI_RUN_SECONDS` to a measured value | `release.sh` stops waiting after 900 seconds by default, and the last branch run took 744 seconds, leaving about 2.5 minutes of margin. Choose a new value from measured runs, through your standing-question step. | The new value is written beside its measurement; a run that takes longer than the old limit but less than the new one is waited on. | 07-independent-review.md change 3 | NOT DONE: `ci-lib.sh` header gives 900 s | S | 10 (with 2.1.1) |
| 2.1.3 | Story | Write the rule for intermittent replay failures | Once the replay runs before the merge, a test that fails only sometimes blocks a release instead of turning `main` red (as D8 did). Decide and implement what `release.sh` does then, for example re-run once and record a defect if the second run passes. | Given a replay that fails once and passes on re-run, when `release.sh` waits, then the rule you chose applies and a defect line is proposed. | 07-independent-review.md change 6; defect D8 | NOT DONE | M | 11 |
| 2.1.4 | Story | Stop CI runs on pushes to `main` and tags, after two matching releases | **CHANGED:** your items "skip main's duplicate full replay" and "remove duplicate tag runs if confirmed" become one. Add `branches-ignore: [main]` and `tags-ignore` to the push trigger, keeping the Monday schedule. | Given two releases whose branch and `main` replays gave the same verdicts, when this lands, then a push of `main` or a tag starts no run, and the Monday run still happens. | ci-and-github 00-decision.md; 07 D3 | CONFIRMED: v0.20.0 ran the same commit three times: branch 12.4 min, `main` 10.9 min, tag 3.4 min | S | 12 |
| 2.1.5 | Task | Test a ruleset on `main` in a scratch repository, then enable it | A server-side rule that requires the `validate` check cannot be skipped with `git push --no-verify`. First test in a throwaway copy whether your fast-forward push of an already-green commit is accepted. | (1) The scratch test result is written down. (2) If it passes, the ruleset is on and `release.sh` still lands. | ci-and-github 06 steps 3–4 | NOT DONE | S | 13 |

### F2.2 CI stays fast as tests grow

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 2.2.1 | Task | Merge the `validate` and `replay-baseline` jobs | Both run the whole check on the same commit, one after the other. Let `validate` also produce the baseline measurement, removing a stage of about 3.2 minutes from the critical path. | The replay run has three stages instead of four, and the verdicts of a full replay are identical before and after. | 07-independent-review.md change 5 | NOT DONE: separate jobs in `validate.yml` | M | 14 |
| 2.2.2 | Task | Balance the shards by measured time | **CHANGED:** your item was "calculate the number of shard machines from measured times". The research found the count is not the problem at 137 faults: shards on the same run took 1.9 to 4.6 minutes. Split the faults by their last measured times instead of by position. | The slowest shard is within about 30 seconds of the average on the next full replay. | 07-independent-review.md change 5; `replay-faults.sh` header ("entries at positions I, I+N, I+2N") | NOT DONE | M | 15 |
| 2.2.3 | Task | Cache dependencies in CI | **DROPPED:** installing Claude Code takes 8 to 13 seconds per job, and harness-kit has no npm dependencies. Do not create this issue, or create it closed as "not planned" with this reason. | — | 07-independent-review.md change 5 | DROPPED | — | — |
| 2.2.4 | Task | Prove the test files can run side by side | Run the 20 test files 4 at a time ten times and compare the PASS lines with a run one after another. 17 of 20 files make private temporary folders; three do not (`background-guard`, `ci-replay`, `plan-mode-guard`). | Ten parallel runs give exactly the same PASS lines as the sequential run, or the shared state found is named. | ci-and-github 04 §3 | NOT DONE | S | 16 |
| 2.2.5 | Story | Run test files in parallel, aiming at about 2 minutes | On the Mac and in CI, run the test files side by side, each file's output kept separate and printed in order. | Given the whole check, when it runs on your Mac, then it takes about 2 minutes or less (measured) and prints the same PASS lines. | your plan (speed part C) | NOT DONE: `tests/validate.sh` runs the files one after another | M | 17 |
| 2.2.6 | Task | Warn when one test file exceeds its time budget | Record each test file's time and warn once when a file exceeds a budget you set. | A deliberately slow test file triggers the warning, naming the file and its time. | your plan | PARTIAL: budgets exist for the whole check, a replay, `ship.sh` and `release.sh` (README); none per file | S | 18 |
| 2.2.7 | Task | Move Node from 22 to 24 everywhere it is set | CI must use the same Node as your Mac. | Every `node-version` is 24, and CI passes. | your decision | NOT DONE: `node-version: 22` in all four jobs of `validate.yml`; no other place found | S | 19 |
| 2.2.8 | Task | Move GitHub's actions to their Node 24 versions | checkout v5, setup-node v5, upload-artifact v6, download-artifact v7, as you decided (newer majors also exist). | A branch replay passes with the new versions, and the Node 20 warning is gone. | your decision; 07-independent-review.md C6 | NOT DONE: all four at v4. Not urgent: GitHub's runner already forces them onto Node 24 | S | 20 |

### F2.3 `release.sh` is safe to leave running

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 2.3.1 | Task | Keep the Mac awake while `release.sh` waits | A 12-minute wait can be cut short if the Mac sleeps. Wrap the wait in `caffeinate` on macOS. | While `release.sh` waits, the Mac does not sleep; on other systems nothing changes. | your plan | NOT FOUND: no `caffeinate` in `release.sh` | S | 21 |
| 2.3.2 | Task | Check up front that `main` is not checked out in another folder | Today this is only suggested after the fast-forward fails. Check it before anything is pushed. | With `main` checked out in another worktree, `release.sh` refuses at the start and says which folder. | your plan | PARTIAL: only mentioned in a failure message (`release.sh` line 172) | S | 22 |

### F2.4 The fault list stays trustworthy

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 2.4.1 | Task | Fast check that each fault's search text appears exactly once | Report a broken fault entry in the ordinary check, not only when a replay runs. | A fault whose text appears twice makes `tests/validate.sh` fail on the branch, naming the fault. | your plan; 05-mapping.md row 4.2 | PARTIAL: the replay tool refuses such entries at replay time (`replay-faults.sh` header, line 70); no check in `validate.sh` | S | 23 |
| 2.4.2 | Story | Check that every fault a commit's "Breaks:" line claims was KILLED | D6 shipped a fault whose commit claimed a proof never run. | Given a commit whose "Breaks:" line names a fault with no KILLED record on the branch, when the check runs, then it fails and names the fault. | your plan; defect D6 | NOT FOUND: `session-start.mjs` asks for "Breaks:" lines; no check reads them against replay results | M | 24 |
| 2.4.3 | Task | Give the 7 whole-check faults their own test mapping | 7 of 137 faults run the whole check because their check has no test file in `.harness/check-files`. | Each of the 7 runs one test file, or the reason it cannot is written down. | ci-and-github 02, contradiction 4 | CONFIRMED: 7 faults, listed in 07-independent-review.md C5a | S | 25 |
| 2.4.4 | Task (deferred) | Fault entries that change several places | Trigger: another fault needs to change more than one place. | — | your plan | NOT DONE | — | deferred |

### F2.5 The check's output is readable

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 2.5.1 | Story | Show a summary view of the check's output | One plain line per part with its count and time, and full detail only for failures. | Given a passing check, when it finishes, then it prints at most one line per test file plus a total; given a failure, then that file's full output is shown. | your plan | NOT FOUND: no summary mode in `tests/validate.sh` | M | 26 |

## E3 — harness-kit runs under its own harness (order 3)

**Decisions behind this epic.**
- This is your planned "N2: harness-kit loads its own plugin".
- It loads the **released** plugin (pinned to a tag), not the working copy, so that a half-built guard never blocks the work that fixes it. [ASSUMPTION; the counter-case is that you then test the previous release, not the one you are building]

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 3.1 | Story | Load the released plugin in harness-kit's own sessions | Add `.claude/settings.json` that declares harness-kit's own marketplace pinned to the latest tag and enables the plugin, as a consumer project does. | Given a new Claude Code session in harness-kit, when it starts, then the start-up picture says "harness-kit vX.Y.Z loaded" and `git push` from Claude is refused. | file 01 D14; your plan | NOT DONE: no `.claude/` folder | S | 27 |
| 3.2 | Task | Add the `.harness/` files a consumer project has | Add a review checklist, protected paths and an approval command for harness-kit itself, so `review.sh` can run on its own branches. | `review.sh` runs on a harness-kit branch and writes a verdict. | file 01 D6 | NOT DONE: `.harness/` holds 7 files and no `review-checklist.md` | M | 28 |
| 3.3 | Bug | Hang tests can pass without checking anything | Five test cases that check a hung process is stopped count as passed even when nothing was checked. | Each of the five fails when the behaviour it checks is broken (proved by planting a fault once). | `.reports/inc-d7-flake.brief.md` line 42 | NOT DONE: listed as out of scope in that brief (`release.test.sh` T1, `ship.test.sh` T1 and T2, `stop-gate.test.sh` case 12, `time-limit.test.sh` case 2); no later brief fixes it | M | 29 |
| 3.4 | Task (deferred) | Warn when the installed Claude Code version differs from the built-in list's | Trigger: your backlog follow-up; start any time. | — | your plan | NOT DONE | S | deferred |

## E4 — Starting work is one command (order 4)

**Decisions behind this epic** (file 04).
- A script picks the item.
- You approve.
- Hooks refuse remote writes.
- The only GitHub writes are one status comment and the Status field, both made through the harness's own scripts.

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 4.1 | Story | Show the single next step in the start-up picture | The start-up picture computes and prints one line such as "Next: run approve-brief.sh". This is the cheapest answer to "I forget the steps" and the start agent's resume logic. | Given each state (no brief, brief not approved, approved, check failing, check passing, reviewed), when a session starts, then the line names the correct next command. | file 04 counter-case 1 | NOT DONE | M | 30 |
| 4.2 | Task | Check that `ship.sh` and `release.sh` accept branch names `inc-<N>-<slug>` | The start script will create such names. | Both scripts run on a branch named that way in their tests. | file 06 | Searched: no branch-name pattern in either script | S | 31 |
| 4.3 | Task | Move the brief procedure into a shared file | The brief skill cannot be started by another skill, so both skills must load the same procedure file. | `/harness-kit:brief` behaves exactly as before (its tests pass), and the start skill loads the same text. | file 04 step 4 | NOT DONE | S | 32 |
| 4.4 | Story | `/harness-kit:start` picks the Ready item and creates the local branch | `start.mjs` runs the checks in file 04, step 2, picks by Priority then issue number, creates the branch locally, and sets Status to In progress. | Given two Ready items with P1 and P2, when you type `/harness-kit:start`, then the P1 item's branch is created locally and no remote branch exists. Given a Ready item that fails the Definition of Ready, then the skill aborts and says which line is missing. | file 04 | NOT DONE | M | 33 |
| 4.5 | Story | Refuse every `gh` command except the allowed reading ones | A new "gh-guard" hook allows only `gh issue view`, `gh issue list`, `gh project item-list`, `gh auth status` and the harness's `record.mjs`. | `gh issue develop 1`, `gh issue close 1`, `gh pr create` and `gh api …` from Claude are each refused with a reason; `gh issue view 1` runs. | file 04 | NOT DONE | M | 34 |
| 4.6 | Story | Keep one status comment per issue | `record.mjs` finds the harness's comment by a hidden marker and edits it, or creates it, never using `--edit-last`. | Given you commented after the harness, when the harness updates its status, then your comment is unchanged and the harness's comment shows the new stage. | file 04 contradiction 5 | NOT DONE | M | 35 |
| 4.7 | Task | End the commit draft with `Fixes #N`, and record the release on the issue | The commit draft names the issue; `release.sh` adds "released in vX.Y.Z" to the status comment. | After a release, the issue is closed by the released commit and its status comment names the tag. | files 02 and 04 | NOT DONE | S | 36 |
| 4.8 | Story | Report backlog health weekly, changing nothing | The check in file 05, section 4, run by Claude Code with `gh`, writing one report. | The report lists each of the seven problem kinds with issue numbers, and makes no write to GitHub other than editing its one report comment, if you choose that. | file 05 | NOT DONE | M | 37 |

## E5 — Every increment is plain to read and verified within budget (order 5)

**Decisions behind this epic.**
- Your planned "front page" (E3 in your plan).
- Your planned "verification discipline" (E4 in your plan).
- Your release rule: one concern, at most about 10 new faults and about 10 minutes of verification, split before approval if over.

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 5.1 | Story | Open every brief and Summary with a front page | At most about 12 plain lines: Current state, Problem, Change, Final outcome, What I decide, Time and risk. `approve-brief.sh` shows it first, and a check enforces its presence and length. | Given a brief without the six headings, when `approve-brief.sh` runs, then it refuses and names the missing heading. | your plan | PARTIAL: recent briefs open with such lines (for example `.reports/inc-speed-a.brief.md` lines 1–4), but the brief skill's template does not require them and no check exists | M | 38 |
| 5.2 | Story | Verification plan with step times | Each long command in the brief, with its estimate, what it proves and no repeated proofs. | — | your plan | **DONE:** `skills/brief/SKILL.md` "Verification plan" (commands over 2 minutes with estimates, no step over 10 minutes, no repeated proofs) | — | — |
| 5.3 | Story | Check the size budget before approval | A brief that adds more than about 10 faults or plans more than about 10 minutes of verification must be split. The numbers go through your standing-question step. | Given a brief over either budget, when `approve-brief.sh` runs, then it refuses and says which budget. | your release rule | NOT FOUND: no size budget in the brief skill or any check | M | 39 |
| 5.4 | Story | Stop and ask before exceeding the approved verification | If a step would run longer than the brief's plan allows, Claude stops and asks. | Given a command not listed in the verification plan that runs over 2 minutes, when Claude starts it, then a hook refuses it and names the plan. | your plan | PARTIAL: the brief skill stops on a vague goal, on open decisions and on new thresholds, and says Claude may run a command over 2 minutes only if the plan lists it; enforcement by a hook: NOT FOUND | M | 40 |
| 5.5 | Story (deferred) | A fast Stop-gate tier under 2 minutes | Trigger: parallel test files (2.2.5) do not bring the check under about 2 minutes. | — | file 01 D5 | NOT DONE | — | deferred |

## E6 — The AI parts are measured (order 6)

**Decisions behind this epic.**
- The reviewer eval is pulled forward, run locally and never in CI. [your plan]
- Full evals are deferred until the first change to any AI part. [your trigger]

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 6.1 | Story | Small reviewer eval from past branches | 10 to 15 past harness-kit branches with known verdicts, run with `eval-reviewer.sh`; every time you overrule the reviewer is recorded. | The eval reports catches and false alarms per case; an overrule adds a line to a record file. | your plan (E6); file 01 D6 | PARTIAL: `eval-reviewer.sh` and its tests exist; harness-kit has no cases file (`.harness/reviewer-eval/cases.tsv` absent) | M | 41 |
| 6.2 | Task | Record the harness numbers at each release | Run `harness-metrics.mjs` at release and commit the numbers, keeping only those that change decisions (escaped defects, first-pass CI rate). | Each release adds one dated line of numbers to a committed file. | file 01 D9 | PARTIAL: `harness-metrics.mjs` exists; no baseline in harness-kit | S | 42 |
| 6.3 | Story (deferred) | Full evals for every AI part | A `claude plugin eval` suite of 20 to 50 cases from real failures, run with and without the plugin, with an equal-or-better gate and held-out cases. Trigger: before the first change to any AI part. | — | your plan; file 01 D8 | NOT DONE | L | deferred |
| 6.4 | Story (deferred) | Self-improving loop and pruning of checks that never catch anything | Per-check records of what each check caught, a retirement rule, a harness health line, and proposals that wait for you. Trigger: a second harness defect of the same kind, or a check blocking falsely twice. | — | your plan; file 01 D10 | NOT DONE | L | deferred |

## E7 — Least privilege and supply chain (order 7)

**Decisions behind this epic.**
- The sandbox waits for your trigger ("before auto mode").
- Permission rules come as a second layer under the hooks, never instead of `git-guard.mjs` (ci-and-github 04, contradiction 3).

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 7.1 | Story | Deny rules as a second layer, and a template for consumer projects | Deny rules for secrets and destructive git in harness-kit's settings and in a template consumer projects copy, because a plugin cannot ship them. | With a hook disabled, a plain `git push` from Claude is still refused by the rule. | file 01 D3 | NOT DONE: no settings file, no template | M | 43 |
| 7.2 | Task | Pin actions by commit hash and add Dependabot for actions | Pin each action to a commit hash with its version in a comment, and let Dependabot propose updates. | Every `uses:` names a 40-character hash; `.github/dependabot.yml` exists. | file 01 D12 | NOT DONE: actions named `@v4`; no `dependabot.yml` | S | 44 |
| 7.3 | Task | Check GitHub secret scanning and push protection are on | Free for public repositories; confirm in the repository settings. | A screenshot or note records both as on. | ci-and-github 04, contradiction 7 | NOT FOUND: settings are not visible from the files | S | 45 |
| 7.4 | Story (deferred) | Require the sandbox | Sandbox on, fail if unavailable, network allowlist, deny `~/.ssh` and `.env`. Trigger: before auto mode. | — | your plan; file 01 D4 | NOT DONE | M | deferred |
| 7.5 | Story (deferred) | Risk tiers | Different gates by risk of change. Trigger: the first security, permission or manifest change. | — | your plan | NOT DONE | L | deferred |
| 7.6 | Task (deferred) | Dependency allowlist | Trigger: the first new dependency. | — | your plan | NOT DONE | S | deferred |
| 7.7 | Task (deferred) | Decide on an API key for reviews in CI | Trigger: only if reviews in CI are wanted. | — | your plan | NOT DONE | S | deferred |

## E8 — A simpler harness (order 8)

**Decisions behind this epic.**
- Freeze the process-management code after the essentials: nothing new there without a real failure. [your decision, 29 September 2026]
- Anthropic's advice is to remove parts that are no longer load-bearing (file 01, contradiction 2).

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 8.1 | Task | Write the freeze rule for process-management code into the map file | State that the time-limit helper, sweeps, registries and process-group code change only after a real failure. | The rule is in the map file, and the reviewer checklist refers to it. | your decision | NOT DONE: not written in the repository | S | 46 |
| 8.2 | Task (needs-decision) | Decide on plan mode | Keep refusing `EnterPlanMode`, or let plan mode produce the brief. Both vendors recommend plan mode; your block exists for a real reason. | A `Decision:` line records the choice. | file 01 contradiction 3 | CONFIRMED: `plan-mode-guard.mjs` refuses it | S | 47 |
| 8.3 | Task (needs-decision) | Decide whether `reviewer-guard.mjs` is still needed | The reviewer agent's tool lists already make it read-only. | A `Decision:` line records keep or remove, with the reason. | file 01 §4 | CONFIRMED: `agents/reviewer.md` lists `tools: Read, Grep, Glob` | S | 48 |
| 8.4 | Task | Replace the CI scan half of `guard-secrets.mjs` | Use gitleaks (no licence key for personal accounts) or GitHub secret scanning for the repository scan, and keep the pre-write block. | CI scans with the standard tool; the pre-write tests still pass. | file 01 §4; ci-and-github 04 | NOT DONE | S | 49 |
| 8.5 | Task | Give the start-up picture a line budget | Every line costs context in every session. | A check fails if the start-up picture prints more lines than the budget you set. | file 01 §4 | PARTIAL: the start-up picture has a 16-line cap (`start-picture.mjs` header), but the SessionStart instructions have no budget | S | 50 |

## E9 — Reuse by other projects (order 9)

**Decisions behind this epic.** Adoption happens in batches, and generic reuse waits for your own triggers. [your plan]

| ID | Type | Title | Description | Acceptance criteria | Source | Repo check | Size | Order |
|---|---|---|---|---|---|---|---|---|
| 9.1 | Story | One-step adoption | `upgrade.sh` creates the adoption branch, commits the pin, and drafts the adoption brief, so adopting a release is one command. | Given a consumer project on an older release, when you run `upgrade.sh <version>`, then a branch, a commit and a draft brief exist, and nothing is pushed. | your plan (speed part E) | PARTIAL: `upgrade.sh` moves the pin, checks the loaded version, runs the approval and writes a commit draft (header steps 0–7); it creates no branch and no brief | M | 51 |
| 9.2 | Story (deferred) | Generic scripts, a setup command and one guide | Trigger: set by you, tied to a consumer project's milestone. | — | your plan | NOT DONE | L | deferred |
| 9.3 | Story (deferred) | Second project with a kick-off capability | Trigger: when a second project starts. | — | your plan | NOT DONE | L | deferred |
| 9.4 | Story (deferred) | Live browser check | A check that runs the product in a real browser. Trigger: a consumer project first needs behaviour a test cannot see. | — | your plan; research/initial-harness/06-behaviour-checks.md | NOT DONE | L | deferred |

## Summary of the repo checks

| Check result | Items |
|---|---|
| DONE | 5.2 |
| PARTIAL | 1.5, 1.7, 2.2.6, 2.3.2, 2.4.1, 5.1, 5.4, 6.1, 6.2, 8.5, 9.1 |
| CONFIRMED (the problem is real) | 1.6, 2.1.4, 2.4.3, 8.2, 8.3 |
| NOT FOUND | 2.3.1, 2.4.2, 2.5.1, 5.3, 7.3 |
| CHANGED by the CI research | 2.1.1, 2.1.4, 2.2.2 |
| DROPPED by the CI research | 2.2.3 |
| NOT DONE | all others |

**Size of the draft.** 9 epics, 5 features and 65 items. Of those, 12 are deferred, 1 is done and 1 is dropped, leaving 51 active items. [VERIFIED by counting this file's tables]

## Strongest counter-cases

- **This is too much backlog for one part-time person.** 51 active items at about one per day is more than two months of work before any product work. Your answer so far has been "the harness at 9/10 first". The alternative is to stop after E1 to E4 (items 1 to 37), re-score with file 01, and decide then.
- **The order puts CI before the start agent.** If remembering the steps is the bigger pain, move E4's items 4.1 and 4.4 before E2. Item 4.1 is cheap enough to do first in any order.
- **Importing everything at once creates noise.** You could import only E1 to E4 and keep the rest in this file until they come near.

**What would change the order.**
- A new red `main` would move E2 to first.
- A false block from a guard, after E3, would move E8 up.
- The first change to an AI part triggers 6.3.

**Confidence.** High for the repo checks: each rests on a file read or searched on 30 September 2026. Medium for the descriptions and the order, which are drafts for you to challenge.
