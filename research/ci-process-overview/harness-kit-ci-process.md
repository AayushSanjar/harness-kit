# How harness-kit's CI works today, and what to fix

Written on Wednesday 30 September 2026. This is a working document: add to it and correct it as the CI is redesigned.

## How to read the labels

- **[VERIFIED]** means I read it directly in the repository files named below, or saw it in the output of a command you ran.
- **[PARTIAL]** means part of the evidence is there, but not all of it.
- **[ASSUMPTION]** means it is my inference or estimate, and has not been checked.

## What this report is based on

I cloned harness-kit's `main` branch from GitHub at commit `e275280`, which is tagged `v0.20.0` (part B of the speed work). I read these files in full or in the parts that matter:

- `.github/workflows/validate.yml`, the only CI workflow in the repository. [VERIFIED]
- `plugins/harness-kit/scripts/release.sh`, the script you run to release. [VERIFIED]
- `plugins/harness-kit/scripts/replay-faults.sh`, the fault-replay tool that CI calls. [VERIFIED]
- `.harness/replay-machinery`, `.harness/check-only`, and the list of files in `.harness/`. [VERIFIED]
- `tests/validate.sh`, the full check, and the header of every test file in `tests/`. [VERIFIED]

The timings in this report come from the CI and terminal output you pasted on 29 and 30 September 2026.

---

## ⚠️ The most important finding

For a **normal** change (one that does not touch the replay machinery, defined below), **CI does not replay any faults on the branch before it is merged.** The faults are replayed only on `main`, after the merge.

The workflow file says so itself, in its own comment: a fault that some merged change let survive "shows up here, after the merge, as a red run on main". [VERIFIED]

This means the rule we agreed on 29 September, "main can never go red after a release", is true today **only** in two cases:

1. The change touches the replay machinery, so CI runs the full replay on the branch automatically.
2. You start the full replay on the branch by hand, as we did for v0.19.1.

For every other change, a problem can still be discovered after the merge. The CI redesign must close this gap.

---

## Terms used in this report

- **Workflow.** The recipe that tells GitHub what to run. harness-kit has one, `.github/workflows/validate.yml`.
- **Event.** The thing that starts the workflow, for example a push.
- **Run.** One execution of the workflow, started by one event.
- **Job.** One part of a run. Every job gets its own fresh, empty Linux machine, called a **runner**. harness-kit's runners are `ubuntu-24.04`, which is pinned on purpose so that the machine does not change underneath the project.
- **Step.** One command inside a job.
- **Artifact.** A folder of results that one job uploads so that a later job can download it.
- **Ref.** The name a push updates: a branch (for example `inc-speed-b` or `main`) or a tag (for example `v0.20.0`).
- **Fault.** A deliberate, small break in the harness's code, written as one line in `.harness/mutations.tsv`. There are 137 today. Replaying a fault means planting it in a throwaway copy of the code and checking that the matching test fails.
- **Merge-base.** The commit where a branch left `main`. "The files changed on a branch" means the files that differ between the merge-base and the branch.
- **Replay machinery.** The 7 files listed in `.harness/replay-machinery`. A mistake in any of them could change the replay's verdicts, so a change to them triggers a full replay.

---

## 1. What starts CI

The workflow starts on four kinds of event. [VERIFIED]

| Event | When it happens |
|---|---|
| `push` | Any push of **any branch or any tag**. There is no filter, so every ref you push starts its own run. |
| `pull_request` | A pull request is opened or updated. You do not use pull requests, because release.sh merges by fast-forward. |
| `workflow_dispatch` | You start it by hand: `gh workflow run validate.yml --ref <branch>`. |
| `schedule` | Automatically every **Monday at 03:00 UTC** (`cron: "0 3 * * 1"`), always on the latest commit of `main`. |

Two facts about the weekly schedule, quoted in the workflow file from GitHub's documentation [VERIFIED]:

- GitHub may delay scheduled runs when it is busy.
- In a public repository, GitHub switches scheduled runs off after 60 days with no activity. The session start-up picture shows the age of the last full replay, so a schedule that stopped would show up there.

One setting applies to every run: `HARNESS_KIT_REPLAY_SESSION_SECONDS: 1500`. The harness stops a fault replay itself after 25 minutes and reports it as TIMEOUT. That is deliberately below GitHub's 30-minute limit per job, so the harness reports the problem instead of GitHub silently cancelling the job. [VERIFIED]

The workflow can only read the repository (`permissions: contents: read`). It cannot push or change anything. [VERIFIED]

---

## 2. The four jobs, step by step

### Job 1: `validate`

**When it runs:** for every event. [VERIFIED]

**Measured time:** 2 minutes 13 seconds to 2 minutes 40 seconds on 29 and 30 September. [VERIFIED]

**Its steps, in order:**

1. **Checkout with full history** (`fetch-depth: 0`). This downloads the repository at the event's commit, including every branch. Full history is needed because one of the checks, `check-defects.mjs`, compares the defect log with `main` and needs the merge-base.
2. **Set up Node.js 22.** The harness's scripts are written in JavaScript.
3. **Plan the fault replay.** This runs `bash plugins/harness-kit/scripts/replay-faults.sh --plan`. It runs no tests. It only decides whether the replay machinery changed:
   1. It finds the base branch (the first line of `.harness/review-base`, which defaults to `main`) and the merge-base.
   2. It lists every file that differs between the merge-base and the commit.
   3. If any of those files is on the machinery list, it prints a line ending in `machinery changed: <files>`, and the step records `machinery=true`.
   4. Otherwise it records `machinery=false`.
   5. If the plan fails for any reason, the step records `machinery=true`, so that a replay runs rather than being skipped.
4. **Install Claude Code** from the internet, with `curl -fsSL https://claude.ai/install.sh | bash`. Claude Code is needed because two of the checks ask it to validate the plugin files.
5. **Show Claude Code's version,** so the log records which version ran.
6. **Run `bash tests/validate.sh`.** This is the full check, described in section 6. If any single check fails, the job fails and the run is red.

The job publishes one result for the later jobs: the `machinery` value from step 3.

### Job 2: `replay-baseline`

**When it runs:** only in the cases listed in section 3. It waits for job 1 to pass first. [VERIFIED]

**Measured time:** 3 minutes 11 seconds on 29 September. [VERIFIED]

**Its steps, in order:**

1. Checkout with full history.
2. Set up Node.js 22.
3. Install Claude Code.
4. **Run the baseline part:** `replay-faults.sh --part baseline --out "$RUNNER_TEMP/replay"`. This runs the **whole check once, with no fault planted,** in a copied working folder, and records for every test file whether it passed and how long it took. The results are written outside the checked-out code, so they cannot change it.
5. **Upload the results** as the artifact `replay-baseline`. If there are no result files, the job fails.

**Why the baseline exists.** A fault only proves something if its test **passes normally** and **fails only when the fault is planted**. If a test already fails without any fault, a failure with the fault proves nothing, so the replay marks that fault ERROR instead of KILLED. This is exactly how the Stop gate's racy-git bug (defect D8) was discovered on 29 September. The baseline's times are also used to give every fault's run a time limit, so that a fault which makes the code hang is reported as TIMEOUT instead of hanging forever.

### Job 3: `replay-shard`, on 8 machines at the same time

**When it runs:** in the same cases as job 2. It waits for jobs 1 and 2. [VERIFIED]

**Measured time:** 13 to 19 minutes per machine on 29 September, before part B. [VERIFIED] The time with part B's changes has not been read yet. [NOT FOUND]

**Its steps, on each of the 8 machines, in order:**

1. Checkout with full history.
2. Set up Node.js 22.
3. Install Claude Code.
4. **Download the baseline's results** (artifact `replay-baseline`). Each fault's time limit is taken from them.
5. **Run its shard:** `replay-faults.sh --part I/8`, where I is 1 to 8. A shard takes the faults at positions I, I+8, I+16 and so on, so 137 faults are split into 8 groups of 17 or 18.
6. For each fault in its group, the machine:
   1. makes a throwaway copy of the code;
   2. plants the fault in the copy;
   3. runs **only that fault's own test file**. This is new in part B, because `.harness/check-only` now exists. Before part B, it ran the whole check for every fault;
   4. records the verdict: KILLED, SURVIVED, TIMEOUT or ERROR;
   5. deletes the copy.

   Several faults run at the same time, up to the number of processor cores the machine has.
7. **Upload its results** as the artifact `replay-shard-I`.

`fail-fast: false` is set, so if one machine fails, the other seven still finish and you see every result. [VERIFIED]

### Job 4: `replay-verdicts`

**When it runs:** in the same cases as jobs 2 and 3. It waits for jobs 1, 2 and 3. [VERIFIED]

**Measured time:** 8 to 18 seconds. [VERIFIED]

**Its steps, in order:**

1. Checkout (normal history is enough).
2. Set up Node.js 22. Claude Code is not installed, because this job runs no checks.
3. **Download all nine artifacts** (the baseline and the 8 shards) into one folder.
4. **Judge the parts:** `replay-faults.sh --judge`. It:
   1. checks that exactly one baseline exists and that every part came from this same commit, refusing any mix-up;
   2. counts the verdicts and prints one line, for example `137 replayed: 137 KILLED, 0 SURVIVED, 0 TIMEOUT, 0 ERROR`;
   3. fails the run unless every fault was KILLED. A missing part's faults count as ERROR.

### What each verdict means

| Verdict | Meaning | Real example |
|---|---|---|
| **KILLED** | The test failed when the fault was planted. The test works. | 136 of part B's first 137 faults. |
| **SURVIVED** | The test passed even with the fault planted. The test is too weak, or the fault changes nothing. | Defect D6 in v0.17.1: a fault that changed nothing, so no test could catch it. |
| **TIMEOUT** | With the fault planted, the check ran past its time limit. | None so far in this series. |
| **ERROR** | The fault could not be judged fairly. | Part A: the test already failed without any fault (the real racy-git bug, D8). Part B: the fault's search text appeared twice in its file, so the tool refused to guess where to plant it. |

---

## 3. The rule that decides whether jobs 2, 3 and 4 run

The workflow runs jobs 2 to 4 when **any one** of these is true [VERIFIED]:

1. The event is a **push to `main`**.
2. The event is a **push of any other ref** and job 1's plan recorded **`machinery=true`**.
3. The event is the **weekly schedule**.
4. The event is a **manual run** (`workflow_dispatch`).

In every other case, **only job 1 runs.** That includes a pull request, a normal branch push, and (inferred) a tag push.

---

## 4. Walkthroughs

### A. Working on a feature branch

**Before any push, on your Mac.** Claude Code builds and commits on the branch. It runs whatever checks and targeted replays its approved brief lists. Nothing here involves GitHub.

**When the branch is pushed.** GitHub starts **one run** (event `push`, ref = the branch).

- **A normal change** (the plan says `machinery=false`): **only job 1** runs, in about 2.5 minutes. **No fault is replayed in CI.** This is the gap described at the top.
- **A machinery change** (the plan says `machinery=true`, as with part B): **all four jobs** run. That is the full replay, about 25 minutes before part B's speed-up.
- **If you also start a run by hand** with `gh workflow run validate.yml --ref <branch>`, a **second** run happens on the same commit. release.sh waits for every run on the commit, so both must finish and pass.

### B. Releasing with `release.sh <tag>`

This happens on your Mac, in order. release.sh stops at the first failure, with a message saying what to do. [VERIFIED]

1. **It refuses** to start if you are on `main`, on a detached HEAD, have uncommitted changes to tracked files, give a tag name git does not accept, or the tag already exists at a different commit (checked locally and on GitHub).
2. **It runs the project's full check locally:** the first line of `.harness/check-command`, which is `bash tests/validate.sh --skip-reviewed`. It has a limit of 540 seconds. If the check fails or times out, nothing is pushed. It took 358 to 379 seconds on 29 and 30 September, against a budget of 120 seconds. [VERIFIED]
3. **It pushes the branch** to GitHub. If the branch is already pushed, nothing happens.
4. **It waits for CI:** every run for the branch's head commit. It waits up to 3 minutes (`SHIP_CI_APPEAR_SECONDS`, default 180) for the first run to appear, then for each run to finish. Any result other than success stops it and prints the run's link. If `gh` gives an error or an unexpected answer, it retries up to 3 times, 10 seconds apart, and then stops with "CI result unknown": it fails closed. It reads a run that has already finished instead of running it again.
5. **It fast-forwards `main`** to the branch's head. It refuses if `main` has commits the branch does not have. It **creates the tag** at the head, and **pushes `main` and the tag together, atomically:** both reach GitHub or neither does.
6. **It switches your folder to `main`.** On 30 September this failed because `main` was checked out in the separate `harness-kit-0.19.1` folder, and git allows each branch in only one folder at a time.
7. **It records the release** in the local event log (`.git/harness-kit/events.tsv`) and **shows a macOS notification** ("RELEASED" or "STOPPED"). So release.sh already notifies you. It does not keep the Mac awake; that still needs `caffeinate -i` in front of the command.

Every git network command has a 300-second limit and never asks for a password or passphrase, so a push that would need one fails straight away instead of hanging. release.sh can be re-run with the same tag after a stop, and it continues where it stopped. It never forces a push, never rewrites history, never moves an existing tag and never deletes the branch. [VERIFIED]

### C. What CI does after a release

The push in step 5 sends two refs, `main` and the tag, so GitHub starts **two runs**. [PARTIAL: this is GitHub's standard behaviour, one run per pushed ref, but not yet confirmed on your runs]

- **The run for `main`** (event `push`, ref `main`): **all four jobs,** because it is `main`. This is a full replay, about 25 minutes before part B's speed-up, **on the exact commit that may already have passed a full replay on the branch.** For a machinery change, this is a pure duplicate.
- **The run for the tag** (event `push`, ref = the tag): **only job 1,** about 2.5 minutes. [ASSUMPTION: inferred, because the tag's commit is the same as `main`'s, so the plan finds no changed files and records `machinery=false`]

To confirm both, run:

```
cd /Users/aayushsanjar/Aayush_Projects/harness-kit && gh run list --limit 6 --json headBranch,event,status,conclusion,createdAt --jq '.[] | "\(.createdAt) \(.event) \(.headBranch) \(.status) \(.conclusion)"'
```

After the v0.20.0 release, you should see one run with `headBranch` `main` and one with `headBranch` `v0.20.0`.

### D. The weekly run and a manual run

- **Weekly:** every Monday at 03:00 UTC, **all four jobs,** on the latest commit of `main`.
- **Manual:** **all four jobs,** on whichever branch you name.

---

## 5. The measured times so far

| What | Time | When |
|---|---|---|
| Job 1, `validate` | 2 min 13 s to 2 min 40 s | 29 and 30 September [VERIFIED] |
| Job 2, `replay-baseline` | 3 min 11 s | 29 September [VERIFIED] |
| Job 3, each of the 8 shards | 13 min 6 s to 18 min 56 s | 29 September, before part B [VERIFIED] |
| Job 4, `replay-verdicts` | 8 s to 18 s | 29 and 30 September [VERIFIED] |
| A whole full-replay run | about 25 min | 29 September, before part B [VERIFIED] |
| A whole full-replay run after part B | not read yet | [NOT FOUND] |
| The full check on your Mac | 358 to 379 s | 29 and 30 September [VERIFIED] |
| A whole `release.sh` run | 587 s | v0.19.0 [VERIFIED] |

---

## 6. What the full check (`tests/validate.sh`) contains

One run prints about 385 PASS lines. [VERIFIED] It has two parts.

### About 15 repository-wide checks

| Check | Why it exists |
|---|---|
| `claude plugin validate --strict`, on the marketplace and on the plugin | Claude Code itself confirms the plugin files are valid, so the plugin will load. |
| The session start prints "harness-kit X loaded" | Proves the plugin really loads, at the right version. |
| `plugin.json` matches `marketplace.json` | A mismatch breaks installs and upgrades. |
| The version is set only in `plugin.json` | One source of truth for the version. |
| `guard-secrets.mjs --scan` finds nothing | No secrets are committed in the repository. |
| `check-limits.mjs`: no long work without the time-limit helper | Stops a repeat of the 7-hour hang (D2). |
| `hooks.json`: every hook's time limit fits inside Claude Code's timeout | Stops a hook being killed half-way. |
| `.harness/defects.tsv` passes `check-defects.mjs` | The defect history can only be added to, never rewritten. |
| `validate.yml` has one baseline, shards 1 to 8, and a verdicts job | The CI replay cannot be quietly disabled. |
| Both skills can only be started by you | Claude cannot start them by itself. |
| The brief skill's eight sections are in order | Briefs stay consistent. |
| Nothing under `.reports/` is committed | Local reports never leak into the repository. |

### 19 test files, one per part of the harness

| Test file | What it protects | Size |
|---|---|---|
| `ship.test.sh` | ship.sh, land.sh and reports: how changes reach a project's `main` | 1,318 lines, about 88 s |
| `replay-faults.test.sh` | the fault-replay tool itself | 1,006 lines, about 53 s |
| `eval-reviewer.test.sh` | the tool that measures the AI reviewer | 607 lines |
| `stop-gate.test.sh` | the Stop gate: checks must pass before Claude stops | 577 lines, about 40 s |
| `review.test.sh` | the AI review step, and the guard that keeps the reviewer read-only | 464 lines |
| `time-limit.test.sh` | the time-limit helper that stops hung processes | 454 lines |
| `release.test.sh` | release.sh | 446 lines |
| `session-start.test.sh` | the session start-up picture | 429 lines |
| `upgrade.test.sh` | upgrade.sh, which moves a project to a new harness version | 377 lines |
| `harness-metrics.test.sh` | the metrics tool | 364 lines |
| `check-commits.test.sh` | the commit-message rules | 354 lines |
| `guard-secrets.test.sh` | blocks secrets from being written or committed | 278 lines |
| `predeploy-gate.test.sh` | blocks deploys unless the checks pass | 248 lines |
| `check-defects.test.sh` | the defect-log rules | 186 lines |
| `brief-guard.test.sh` | Claude cannot approve its own brief or forge a pass record | 158 lines |
| `check-names.test.sh` | the command-name rules | 142 lines |
| `git-guard.test.sh` | blocks `git push` and destructive git commands | 134 lines |
| `background-guard.test.sh` | blocks background commands without a time limit | 115 lines |
| `plan-mode-guard.test.sh` | blocks Claude from entering plan mode | 86 lines |

For scale: the harness has about 8,700 lines of scripts and about 8,100 lines of tests. [VERIFIED: counted on 30 September] The research scored "keep it simple" at 4 out of 10 for this reason.

---

## 7. What to fix in the CI redesign

| Finding | Why it matters | Proposed fix |
|---|---|---|
| **Normal changes get no fault replay before merging.** | A problem can still turn `main` red after a release. This is the gap at the top of this report. | Every branch push runs a **targeted** replay in CI: only the faults tied to the changed files, so it stays fast. Machinery changes keep the full replay. |
| **`main` repeats a full replay that the branch already passed.** | About 25 minutes of duplicate work per machinery release (before part B). | Skip the full replay on `main` when the exact same commit already passed a full replay on its branch. |
| **Jobs 1 and 2 both run the full check, one after the other.** | About 3 minutes wasted per full run. | Merge them: job 1 runs the check the replay's way (in a copied folder, file by file, timed) and publishes the baseline itself. |
| **Every job reinstalls Node.js and Claude Code from the internet.** | 11 machine start-ups per full run, each paying the set-up cost. | Cache the downloads. |
| **The number of shard machines is fixed at 8.** | It does not scale as tests grow. | Calculate the number from measured times, so that no machine takes longer than about 5 minutes. |
| **Test files run one after another** inside validate.sh. | The full check takes about 6 minutes on your Mac. | Run the test files in parallel on each machine (part C). |
| **A tag push starts its own run** (inferred). | About 2.5 minutes of duplicate work per release. | Confirm with the command in section 4C. If it is a duplicate of `main`'s run, skip tag pushes. |
| **release.sh does not keep the Mac awake.** | A release can stall if the Mac sleeps. | release.sh keeps the Mac awake itself. It already sends a notification. |
| **release.sh does not check whether `main` is checked out in another folder.** | The final "switch to main" step failed on 30 September. | Check this before starting, and say plainly what to do. |
| **Fault search text is checked only during the slow CI replay.** | Part B's ERROR (a search text appearing twice) could have been caught in seconds. | A fast local check that every fault's text appears exactly once. |
| **The output is about 385 technical lines.** | Hard to follow while watching. | A summary view: one plain line per part, with a count and a time. Full detail only on failure. |
| **The CI actions use Node 20,** which GitHub has deprecated. | Warnings now, and eventually a failure. | Move to the first Node 24 versions: checkout v5, setup-node v5, upload-artifact v6, download-artifact v7. |

---

## 8. What is not yet known

1. **Whether a tag push really runs only job 1.** This is inferred. The command in section 4C confirms it.
2. **How long a full run takes after part B,** now that each fault runs only its own test file. This number decides how much more speed-up is needed.
3. **How many processor cores GitHub's `ubuntu-24.04` runner gives a public repository.** This decides how much running test files in parallel (part C) will help on CI. [ASSUMPTION: about 4]
