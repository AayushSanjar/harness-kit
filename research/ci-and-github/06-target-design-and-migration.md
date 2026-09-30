# 06 — Target design for both repositories, and a step-by-step migration (question F)

Written on Wednesday 30 September 2026. Research only: no repository was changed. This file describes changes for later; none of them has been made or tested.

## Terms used in this file

- **harness-kit.** Your public repository (github.com/AayushSanjar/harness-kit). **The gadget.** Your private repository control-chart-gadget, a Forge app that installs harness-kit.
- **Full replay.** The check of all 137 planted faults in harness-kit's `.harness/mutations.tsv` (33 in the gadget). **Targeted replay.** The check of only the faults tied to the files that changed. Both are defined in file 02.
- **Exact commit.** The specific commit that `main` will point to after the merge. Because you merge by fast-forward (moving `main` forward to a commit that already contains all of `main`), the commit that is tested is the commit that lands.
- **Pre-merge** means before `main` moves; **post-merge** means after.
- **Release (harness-kit).** Running `release.sh <tag>`, which is the only way `main` moves in harness-kit. **Ship (gadget).** Running `scripts/ship.sh`, the only way `main` moves in the gadget.
- **Gate.** A check that can stop a bad change reaching `main`. **Gate ledger.** The table in section 3 that lists every gate, where it runs today and where it runs in the target design.
- **Critical path.** The chain of jobs that must run one after another, so their total time decides how long the whole run takes. **Machine-minute.** One minute of one runner.
- **Baseline part, shard, verdicts job.** The three stages of the replay in CI, as in file 05.
- **Machinery.** The 7 files in `.harness/replay-machinery`; changing one makes a branch push replay in full.
- **Aggregator (gate) job, ruleset, required check, concurrency group.** As in file 01.
- **Attention time.** The minutes in which you must look at a screen or decide something, as opposed to elapsed time, when a job runs while you are away.
- **Scratch repository.** A throwaway copy of a repository on your own account, used to test a change without touching the real one.

## How this file is based on evidence

This file is a design, so most of its statements are my reasoning from the evidence in files 01 to 05. It cites 72 sources: 68 primary and 4 secondary; these are the same sources as in the earlier files, and no new research thread was run for this file. What is measured and what is not:

- **Measured by you (from your description and my notes):** the local check takes 358 to 379 seconds on your Mac; the whole `validate` job in CI takes 2 minutes 13 seconds to 2 minutes 40 seconds; the full replay takes about 25 minutes on 8 machines; a release costs you 30 to 60 minutes of attention; `main` went red after releases 4 times in 2 days. Before the recent "each fault runs only its own test file" change, a shard took 13 to 19 minutes.
- **Read by me in the files:** `validate.yml` in full, and the header comments of `release.sh`, `ship.sh`, `land.sh`, `ci-lib.sh` and `replay-faults.sh`. I did not read the bodies of those scripts, and I ran nothing.
- **NOT FOUND (never estimated as fact):** the time of a full replay after the "own test file" change; the duration of any single test file; the time to install Claude Code in CI; the gadget's CI time; and the price of GitHub Pro.

Every predicted time below is labelled **[ASSUMPTION]** and shows how it was worked out, so that step 0 of the migration can replace it with a measured number. Where the arithmetic gives a range, the range is real: I do not know which end applies.

Labels: **[VERIFIED]** means a primary source or the file itself says it. **[PARTIAL]** means only a header, extract or secondary source supports it. **[ASSUMPTION]** means my reasoning. **NOT FOUND** means I searched and found nothing.

## CONTRADICTIONS

These are the findings that changed the design, or that go against what you believe.

1. **The full replay is not a check on `main` that duplicates an earlier one. For an ordinary change it is the only replay, and it happens after the merge.** [VERIFIED | `validate.yml` and its own comment: "a fault any other merged change let SURVIVE shows up here, after the merge, as a red run on main."] So the belief "full replay on every merge is necessary" is half right: the full replay is necessary, and it is in the wrong place. The evidence supports moving it in front of the merge, not deleting it (file 02, §6; Rust and Cargo test the exact candidate before it lands and have no test run on `main` at all, file 01, contradiction 3).
2. **You believe custom release scripts are safer than pull requests; the evidence supports keeping your script and adding a check GitHub enforces, not replacing the script.** No sampled project lands changes without a pull request (file 01, contradiction 4), but the practice closest to yours, everything-claude-code, keeps a hand-run `release.sh` and lets CI refuse the release unless CI passed on that exact commit (file 03). That is the shape recommended below. For harness-kit a ruleset that GitHub enforces is free and cannot be skipped with `git push --no-verify`. For the gadget it needs a paid plan (price NOT FOUND), and a merge queue is unavailable to both (file 04, contradictions 1 and 2).
3. **`release.sh` and `ship.sh` push the branch themselves, so for most changes "a replay on every branch push" and "a replay at release" happen at the same moment.** [VERIFIED | `release.sh` header, step 3: "Push the branch to origin"] Whether you push a branch by hand earlier: NOT FOUND. My earlier working plan had a targeted replay on every branch push as the first step. That step is worth much less than I thought, because it would run at release time, not earlier. Its value is speed (a few minutes instead of about 25), not earlier warning, so it is now an optional fast lane (step 12), and the first replay step is moving the full replay in front of the merge (step 2).
4. **A pre-merge full replay cannot be waited on with today's default limit.** [VERIFIED | `ci-lib.sh` header] Each `gh run watch` runs under `SHIP_CI_RUN_SECONDS`, 900 seconds by default; past it the release stops with `ci-timeout`. A full replay of about 25 minutes is 1,500 seconds. Today this limit is never reached because the replay on `main` is not waited on. The limit must be raised with the change, and the new value is a threshold that should be chosen from a measurement.
5. **harness-kit's own advice says not to run the replay in a consumer project's CI.** [VERIFIED | `replay-faults.sh` header: "Do not add it to a consumer project's CI: a private repository pays for its Actions minutes."] My earlier plan added a weekly full replay to the gadget's CI. Following your own header, the design below keeps the gadget's replay local and adds a targeted replay to `ship.sh`; a weekly CI replay for the gadget stays optional until its minutes are measured (step 11).
6. **Neither `ship.sh` nor `release.sh` runs a replay at all.** [VERIFIED | search of the whole plugin folder for `replay-faults`; the callers are `land.sh`, CI and the reports] So in the gadget, an ordinary change is replayed only if you run `replay-faults.sh` by hand or a protected-file patch goes through `land.sh`. Whether the gadget's `scripts/check.sh` runs it: NOT FOUND.
7. **The CI-runner-versus-Mac speed gap suggests test volume is not the only bottleneck.** The same `tests/validate.sh` takes 358 to 379 seconds on your Mac and 2 minutes 13 seconds to 2 minutes 40 seconds for the whole job on the runner, so the Mac is about 2.5 to 3 times slower. [ASSUMPTION for the cause; the two timings come from your runs] Step 0 measures per-file times on both machines, because if the slowness is a few files or a few commands on the Mac (for example, many small processes started one after another), the fix is smaller than any CI redesign.
8. **The 7 faults that run a whole check and the one-after-another job chain are unlisted costs.** [VERIFIED for both | my tally of `mutations.tsv` and `check-files`; `validate.yml` `needs:` lines] The replay stages run in a chain: `validate`, then `replay-baseline` (which needs `validate`), then `replay-shard` (which needs the baseline), then `replay-verdicts`. The whole-check work of `validate` and the baseline is done twice one after the other on the critical path (file 02, contradiction 4; file 05, row 1.10).

## 1. The design principles

1. **Every gate that exists today must still exist, and the gate ledger (section 3) must show where.** A gate is moved or made faster; it is not removed until its replacement has run successfully in the real flow.
2. **A fault is found before `main` moves.** The exact commit that lands must have passed the full replay. [Supported by file 02, §6, and the Rust and Cargo practice]
3. **A run that tests the same tree twice is removed only after the first run has been shown to be at least as strong.** The runs on `main` and on the tag test the tree that the branch already tested (file 01, §4).
4. **Waiting is not the same as attention.** Time in which GitHub works while you are away is acceptable; time in which you must watch is what to cut. `release.sh` is already resumable and shows a macOS notification when it stops or finishes (its header), so a long pre-merge replay costs elapsed time, not attention.
5. **Speed comes from doing less duplicate work and from more machines, never from checking less.** The knobs are: fewer repeated whole-check runs, faster test execution, more shards (up to the Free-plan limit of 20 jobs at once), and cancelling outdated runs.
6. **No custom code where a standard feature does the same job.** But a standard feature replaces a script only where file 04 found it equally strong: for example, GitHub's `timeout-minutes` and `concurrency`, but not a deny rule in place of `git-guard.mjs`.
7. **Each step is small, has a test with an expected result, can be undone, and comes with its strongest counter-case.** This also fits your gadget rules 1 to 3 (propose first, one item at a time).

## 2. The target design in plain words

### harness-kit (public repository)

Nothing changes in how you work: Claude commits on a branch, the Stop gate runs the check, and you run `release.sh <tag>` when the branch is ready. What changes is what happens after you type that command and what runs afterwards.

`release.sh` still refuses on the base branch, a detached head, uncommitted changes and a tag that already exists at another commit. It still runs the check and pushes the branch. Then it asks GitHub to run the **full replay on that exact commit** and waits for it, together with the ordinary `validate` run, under a wait limit long enough for the replay. If both pass, it fast-forwards `main` and pushes `main` and the tag together with `git push --atomic`, exactly as now. If a fault survives, it stops before `main` moves, prints the run's address, and you fix the branch and run `release.sh` again (it is already written to resume). Nothing is pushed to `main` until the replay has passed, so `main` cannot turn red because of a replay again.

After the release, nothing runs on the push to `main` or on the tag push, because the commit is the one that was already fully replayed. The weekly run on Monday at 03:00 UTC stays: it checks that `main` still passes on a clean machine with the newest runner image and Claude Code installer, it keeps the caches warm, and the start-up picture reads its age. A change to one of the 7 machinery files still triggers a full replay on the branch push, as today.

Workflow hygiene is added in a first, low-risk commit: current versions of the GitHub actions that run on Node 24, a `timeout-minutes` on the `validate` job, and cancelling an outdated run when a newer push arrives (never a run on `main`, a tag, or the schedule). Later, after each has been measured, the test files run in parallel, the 7 whole-check faults get their own test files, the baseline stage is folded into `validate`, and the number of shards is raised when the replay exceeds about 10 minutes. A ruleset on `main` requiring the `validate` check is added, but only after a scratch-repository test shows how GitHub treats your direct push of an already-green commit.

### The gadget (private repository)

`scripts/ship.sh` stays the only way to `main`. Its CI (`ci.yml`, one job on every branch except `main`) stays, with three additions that change no behaviour: the npm download cache (both lock files listed), cancelling outdated runs, and job timeouts. Chromium is not cached, because Playwright's own guide advises against it. `ship.sh` gains a targeted replay before the push, exactly as `land.sh` already does for patches, so an ordinary change is replayed at the same point as a protected-file patch. A weekly full replay in the gadget's CI is optional and decided only after the gadget's check time is measured, against the 2,000 free private minutes per month. Server-side rules on `main` need a paid GitHub plan; the price is NOT FOUND, so this stays your decision.

### What runs when

| Event | harness-kit today | harness-kit target | Gadget today | Gadget target |
|---|---|---|---|---|
| Push of a branch (not `main`) | `validate`; full replay only if machinery changed | Same, plus concurrency cancel, a timeout on `validate`, and (step 12, optional) a targeted replay | `check.sh` in one job | Same, plus cache, cancel and timeouts |
| Release or ship, before `main` moves | `release.sh`: local check, push, wait for `validate` | Local check, push, a **full replay of the exact commit** started and waited on, then fast-forward | `ship.sh`: brief, check, review, push, wait for CI | Same, plus a **targeted replay** before the push |
| Push to `main` | `validate` plus full replay | Nothing (after step 6) | Nothing in CI | Nothing |
| Push of a tag | `validate` | Nothing (after step 6) | Not used in CI | Not used in CI |
| Monday 03:00 UTC | Full replay of `main` | Same | Nothing | Optional (step 11) |
| Manual start | Full replay by hand | Same; also how `release.sh` starts the pre-merge replay | Nothing | Nothing |
| Pull request from a fork | `validate` | Same | Runs `check.sh` | Same |

## 3. The gate ledger: every gate, before and after

This table is the proof against "quality must not drop". A gate leaves its current place only in the step named in the last column, and only after its replacement has run in the real flow.

| Gate | Where it runs today | Where it runs in the target design | Stronger, equal or weaker | Removed from the old place in step |
|---|---|---|---|---|
| The whole check passes on the exact commit | Local check in `release.sh`; `validate` on the branch push; `validate` again on `main` and on the tag | Local check (kept); `validate` on the branch push; the pre-merge replay run also runs `validate` | Equal (the same tree is tested; the runs on `main` and tag test the same tree) | 6 (the `main` and tag runs) |
| The reviewed diff has a PASS verdict (`check-reviewed`) | `validate` on the branch push (it runs without `--skip-reviewed`); on `main` the diff is empty | `validate` on the branch push | Equal | Never removed |
| Full fault replay | After the merge, on `main` (red `main` if it fails) | Before the merge, on the exact commit, plus weekly and for machinery | **Stronger** (found before `main` moves) | 6 |
| Full replay for a machinery change | Branch push, then `main` again | Branch push, then the pre-merge replay | Equal | 6 |
| An independent run on a clean machine with the current runner image and Claude Code installer | The run on `main` after each release | The pre-merge replay (same tree, a clean machine, run just before the merge) and the weekly run | Equal for the tree, slightly weaker for "one more run after the merge"; the weekly run covers drift | 6 |
| A fault entry that is not found exactly once in its file | Reported as an ERROR only when a replay runs, that is, after the merge for an ordinary change | The same rule, reported by a fast check on the branch (step 10) and by the pre-merge replay | **Stronger** (earlier) | Never removed |
| A gap in `check-files` (a fault with no test file, so a whole check runs) | Not reported | Reported by a consistency check (step 10) | **Stronger** | Not applicable |
| `main` cannot be changed by hand | The pre-push hook (`install-hooks.sh`), skippable with `git push --no-verify` and installed per clone | The hook (kept) plus, for harness-kit only, a ruleset that GitHub enforces | **Stronger** for harness-kit; equal for the gadget unless a paid plan is bought | Never removed |
| Waiting for CI fails closed ("CI result unknown" stops the release) | `ci_wait` in `ci-lib.sh` | Same rule, with a longer per-run limit; it may later be replaced by `gh run watch --exit-status` (step 7) | Equal | Not applicable |
| The tag is never moved and `main` is fast-forward only | `release.sh` | `release.sh` (unchanged) | Equal | Never removed |
| Secrets are blocked before they are written (`guard-secrets.mjs`) and commit messages are checked | Hooks (local) | Unchanged | Equal | Never removed |
| Approval files cannot be written by Claude (`brief-guard`, `git-guard`) | Hooks (local) | Unchanged | Equal | Never removed |
| Ordinary gadget changes are replayed | Not in the normal flow (contradiction 6) | Targeted replay in `ship.sh` | **Stronger** | Not applicable |

## 4. Predicted times, with the working shown

Everything in this section is an **[ASSUMPTION]**, built from your five measured figures and the job chain in `validate.yml`. Step 0 replaces each with a measured number.

**Today, per release, for harness-kit:**

- **Whole-check runs.** The whole check runs 6 times per release: the Stop gate (skipped if nothing changed since its last pass), the local check in `release.sh`, `validate` on the branch push, `validate` on `main`, the replay baseline on `main`, and `validate` on the tag. [VERIFIED | `validate.yml`, `release.sh` header]
- **CI jobs.** The branch push starts 1 job, the `main` push starts 11 (`validate`, the baseline, 8 shards and the verdicts job), and the tag push starts 1, which is 13 in all.
- **At your terminal.** The local check takes 358 to 379 seconds, which is 6.0 to 6.3 minutes. Pushing takes seconds. Waiting for `validate` takes 2.2 to 2.7 minutes plus the time for the run to appear (up to 3 minutes is allowed; the real time is NOT FOUND). Fast-forward, tag and push take seconds. Total: about 9 to 10 minutes.
- **After you leave.** The replay chain on `main` takes about 25 minutes (your figure). So you learn the truth about a change about 34 to 35 minutes after you typed `release.sh`, and `main` has already moved.
- **When a fault survives** (it happened 4 times in 2 days), you repair on a branch and release again: about 9 to 10 more minutes at the terminal and 25 more minutes of waiting. This repair cycle, plus reading the report, is where I think most of the 30 to 60 minutes of attention comes from. [ASSUMPTION: your figure is not broken down]

**The chain inside the 25 minutes.** The replay stages need each other in a line: `validate` (2.2 to 2.7 minutes), then the baseline (about the same, because it runs the whole check once, plus installing Claude Code), then the shard stage, then the verdicts job (about 1 minute). By subtraction, the shard stage takes about 18 to 20 minutes. [ASSUMPTION: 25 minus 2.2–2.7, minus about 2.5–3, minus about 1. This matches your earlier figure of 13 to 19 minutes per shard, which is before the "own test file" change; whether the shard time has changed since is NOT FOUND.] With 137 faults in 8 shards, each shard holds about 17 faults.

**Target A: the full replay moved in front of the merge, nothing else changed (steps 1 to 6).**

- Local check 6.0 to 6.3 minutes (kept), then push, and the full replay chain on the exact commit, about 25 minutes. `main` moves at about 31 to 32 minutes after you typed the command; the truth is known at the same moment, and `main` has not moved before it.
- No runs on `main` or the tag. The whole check runs 4 times (the local check, `validate` on the branch push, `validate` inside the dispatched run, and the baseline) instead of 6. CI jobs per release: 12 (the branch-push `validate`, plus the dispatched run's 11: `validate`, the baseline, 8 shards and the verdicts job), instead of 13. The branch-push `validate` and the dispatched run's `validate` test the same tree; removing that last duplicate is a possible later refinement and is not part of the steps below. Public-repository minutes are free, so the job count is not a cost; what falls is repeated work. [ASSUMPTION]
- Your attention: starting the command (1 to 2 minutes) and reading the end notification (about 1 minute). The 25 minutes of waiting is not attention, because `release.sh` is resumable and shows a notification. The repair cycle still exists but now happens before `main` moves.

**Target B: Target A plus the speed steps (7 to 10).**

- Folding the baseline into `validate` removes about 2.5 to 3 minutes from the chain (the baseline stage). Doubling the shards from 8 to 16 roughly halves the fault part of each shard. If fixed setup per shard (checkout, Node, Claude Code install, artifact download) is 1 to 2 minutes, the shard stage falls from 18–20 minutes to about 10 to 11 minutes. [ASSUMPTION: 2 + (18 to 20 minus 2) ÷ 2; the setup time per shard is NOT FOUND] Running the 20 test files in parallel shortens `validate` by an unknown amount, at least the difference between 4 parallel processes and one at a time, up to the longest single file. The 7 whole-check faults, given their own test files, save up to 15 to 19 machine-minutes across the shards, but the effect on the slowest shard is unknown.
- Predicted full replay: about 14 to 22 minutes, depending on which steps land. Predicted time from command to landing: about 20 to 28 minutes, with 2 to 3 minutes of your attention. Three whole-check runs instead of 6 (local, the branch-push `validate` and the dispatched run's `validate`; the baseline is folded in). [ASSUMPTION for all]

**Growth.** As faults are added, a full replay grows in proportion to their number divided by the number of shards. At about 17 faults per shard now, raising the shard count keeps the shard stage flat until it reaches 20 shards, the limit of jobs that run at the same time on the Free plan, which is about 340 faults. [ASSUMPTION: 20 × 17; the limit itself is VERIFIED, file 01 §6] Beyond that, the choices are the optional fast lane (a targeted replay before the merge, full replay weekly), a paid runner, or fewer whole-check fallbacks. That is a decision for later, and it needs the completeness check in step 12.

## 5. Worked example: one normal change and one release

### Example 1: a normal change in harness-kit

Suppose the increment edits `ship.sh` and `tests/ship.test.sh`. My tally shows 14 faults whose named test is `ship.test.sh`. I assume all 14 have their planted file in `ship.sh`; the real selection also takes faults whose check maps to a changed path in `.harness/check-files`, so the true number could be higher. [ASSUMPTION]

| Step | Who | Today | Target | Time |
|---|---|---|---|---|
| 1. Claude writes the change on the branch and tries to stop | Claude | The Stop gate runs the check, skipped if nothing changed since its last pass | Same | 6.0–6.3 minutes on your Mac when it runs (your measurement) |
| 2. Claude commits locally | Claude | Commit-message check in the commit-msg hook | Same | Seconds |
| 3. You run `release.sh vX.Y.Z` | You (1–2 minutes of attention) | Local check, push, wait for `validate` | Local check, push, start the full replay on the exact commit, wait for both | Today 9–10 minutes at the terminal. Target A: about 31–32 minutes elapsed with you away after the start. Target B: about 20–28 minutes |
| 4. CI on the branch | GitHub | `validate` only (no machinery change) | `validate` and the full replay, in the same run set | `validate` 2.2–2.7 minutes today; the replay chain about 25 minutes (Target A) |
| 5. `main` moves | `release.sh` | After `validate` passes, before any replay | After both pass | Seconds |
| 6. The replay finds a survivor | GitHub, then you | After `main` moved: a red run on `main`, found about 25 minutes later | Before `main` moved: `release.sh` stops with the run's address; you repair the branch and re-run | Repair cost per survivor: about 9–10 minutes at the terminal and 25 minutes waiting today; in the target the same repair happens with `main` unchanged |
| 7. Runs on `main` and on the tag | GitHub | `validate` twice more and the replay chain | Nothing | Saves the two `validate` runs on `main` and the tag (about 5 minutes of machine time) and the post-merge waiting; the replay chain moves before the merge rather than disappearing |

### Example 2: a release, and what the tag costs

A release is step 3 to 5 above plus the tag. `git push --atomic origin main vX.Y.Z` updates both references in one push, as today. Under the target design the tag push starts no run. Today the tag push starts a `validate` run of the same tree (2.2 to 2.7 minutes, on a machine you do not pay for). Expected times: as in section 4. The fully specified worked release is therefore: a total of about 31 to 32 minutes elapsed after migration steps 1 to 6, and about 20 to 28 minutes after the speed steps, with your attention limited to about 2 to 3 minutes. [ASSUMPTION for all times; your measured inputs are named in section 4]

### Example 3: a normal change in the gadget

A change to a Vite component. Claude works on `harness/inc-N`; the Stop gate runs `check.sh`; you run `scripts/ship.sh`, which requires an approved brief, runs the check, runs the review (one Claude run, limit $3.00 and 900 seconds), pushes, waits for CI and fast-forwards. In the target design `ship.sh` also runs a targeted replay of the faults tied to the changed files, before the push, and the CI job uses the npm cache and cancels outdated runs. Times: the gadget's check time, CI time and per-fault time are NOT FOUND, so I give no prediction; step 0 measures them. The formula for the extra local time is: the number of faults tied to the change, times one `--only` check, divided by the parallel jobs your Mac allows (`HARNESS_KIT_REPLAY_JOBS` and its CPU count). [VERIFIED | `replay-faults.sh` header for the mechanism]

## 6. The migration: small steps, each separately testable

Each step is a change to one repository, named, with a test whose expected result is stated, an undo, and the strongest case against it. **Who:** Claude Code, working inside the named repository on a branch `harness/inc-N`, proposes and commits under your rules (gadget rules 1 to 3, 33 and 41); you run `release.sh`, `ship.sh` and the approvals. The folder of the harness-kit repository on your Mac was not given to me; the gadget's is `/Users/aayushsanjar/Aayush_Projects/atlassian-app/control-chart-gadget`. If a file such as the gadget's `ci.yml` is on `.harness/protected-paths` (its list: NOT FOUND, I did not read it), the change comes as a patch under `.reports/` and you apply it with `scripts/land.sh`. Only steps 0, 1 and 2 are specified in full; the later steps are outlined, because their content depends on what step 0 measures.

### Step 0 — Measure (harness-kit and the gadget; changes nothing)

- **Why:** every predicted time in this file is an assumption; the design's speed goals depend on numbers that are NOT FOUND.
- **What Claude Code does:** (a) reads the last 30 runs of `validate.yml` and lists each job's start and end with `gh run list --workflow validate.yml --limit 30 --json databaseId,event,headBranch,conclusion,createdAt,updatedAt` and then `gh run view <id> --json jobs` for each; (b) times every `tests/*.test.sh` file separately on your Mac and, from a scratch branch with a temporary workflow, on a runner; (c) runs the 20 files with 4 at a time on a scratch branch and compares the set of PASS lines with the sequential run; (d) repeats (a) for the gadget's `ci.yml`, and times one `--only` check there; (e) times the Claude Code install step on a runner. Results go to `.reports/`, which is never committed.
- **Expected result:** a table with, at least, per-job times for 30 runs, 20 per-file times on each machine, whether the parallel run gives identical PASS lines, the gadget's job time, the install time, and the time of the shard stage.
- **Test:** the table exists and every cell is a measured number or an explicit "not measurable".
- **Undo:** delete the scratch branch.
- **Counter-case:** 30 runs on a public runner pool vary with load and queue time, so a median with the range is needed, not one number. A first run with a cold cache may look slower than later ones.

### Step 1 — A hygiene commit in harness-kit (no change in behaviour)

- **Change:** in `validate.yml`, the four action versions to a current major that runs on Node 24 (my notes have checkout v7.0.1, setup-node v7.0.0, upload-artifact v7, download-artifact v8; your earlier choice v5, v5, v6 and v7 also runs on Node 24, and is the lower-risk pick because it is what you already decided); a `timeout-minutes` on the `validate` job (it has none today; the replay jobs have 30); a concurrency group per branch that cancels an outdated run but never for `main`, a tag or the schedule. Do not add `paths:` filters. Do not touch the tag and `main` triggers yet.
- **Expected result on a test branch:** the same jobs and the same PASS lines as before; the deprecation notice about Node 20 no longer appears; a second push made within a minute of the first shows the first run as "cancelled". Because `validate.yml` is one of the 7 machinery files, this branch push itself runs the full replay chain, which exercises the new upload and download action versions and the shard matrix.
- **Test:** `gh run list --branch <branch> --limit 5` shows `completed success` for `validate`, the baseline, the 8 shards and the verdicts job; the release of that branch under the old `release.sh` still works.
- **Undo:** `git revert` the commit.
- **Counter-case:** newer major versions of the artifact actions may change how artifacts are named or merged; the workflow uses `merge-multiple` and a `replay-*` pattern, so a difference would break the verdicts job. The machinery run described above is the test for that. Whether v4 actions fail today after Node 20's removal on 23 September: NOT FOUND (your runs of 29–30 September passed), so this step is not an emergency fix.
- **Separate, gadget:** the same kind of change in `ci.yml` (`cache: npm` with both lock files listed, concurrency cancel for branches, `timeout-minutes`), as its own commit. It needs no other step first.

### Step 2 — Put the full replay in front of the merge (harness-kit)

- **Change:** two edits in `release.sh` and its helper, made and tested in a scratch repository first: (1) after the branch is pushed, start `validate.yml` on that branch by manual dispatch (the workflow already runs the replay stages for a manual start), and (2) raise `SHIP_CI_RUN_SECONDS` above the full replay's measured time with margin, so that waiting on it does not stop with `ci-timeout`. Run the standing question from your gadget rule 42 before writing the number, and write the measured time beside it. The `main` run is **not** removed in this step: for the first releases the replay runs twice, before and after, so their verdicts can be compared.
- **Expected result:** `release.sh` stops at the CI step until the dispatched replay has finished (whether `ci_wait` sees a manually started run for the same commit, and not only the run started by the push, is not verified, because I did not read the body of `ci-lib.sh`; test (a) below checks it); on success it fast-forwards and tags as today; on a failure it stops with the run's address before `main` moves.
- **Test, in a scratch repository (a copy of harness-kit on your account, with its own throwaway tag):** (a) a normal run lands and the tag is created; (b) weaken one test on a scratch branch so that a fault survives; `release.sh` must stop, and `git ls-remote origin main` must show `main` unchanged; (c) stop the run halfway and re-run `release.sh` with the same tag; it must resume without moving anything twice.
- **Undo:** `git revert` the `release.sh` change.
- **Counter-case:** this adds about 25 minutes of elapsed time before every release, and if your attention (not the elapsed time) is what you cannot spare, the notification and the resume are the mitigation. If elapsed time is the problem, the alternative is the fast lane (step 12): a targeted replay before the merge and the full replay weekly, which is the mainstream shape (file 02, §4) but is only as strong as the hand-written `check-files` map. Do not choose the fast lane unless a measurement shows the full replay too slow, and not before its completeness check exists.

### Steps 3 to 12 (outlined; each needs step 0's numbers)

| Step | Repository | Change | Test | Undo | Strongest counter-case |
|---|---|---|---|---|---|
| 3 | harness-kit, in a scratch repository | Test a ruleset that requires the `validate` check on `main`: does a direct fast-forward push of an already-green commit pass? What is the owner's bypass default? | The scratch push of a green commit is accepted and of a red commit refused; results written down | Delete the scratch repository | GitHub's wording says commits may be "pushed directly to the protected branch" after checks pass [PARTIAL]; if the scratch test shows the atomic push of `main` and a tag is refused, the ruleset is not adopted |
| 4 | harness-kit | Enable that ruleset on the real `main` (owner bypass off if the scratch test allows it) | `git push origin main` from a branch that is not green is refused; `release.sh` still lands | Disable the ruleset in the repository's settings (a settings change, not a commit) | A solo owner can bypass, and a refusal at the wrong moment blocks a hotfix |
| 5 | Both | Repeat measurement (step 0) after steps 1 to 4 for a baseline of "before removals" | Same table, new numbers | None needed | Small samples |
| 6 | harness-kit | After two releases whose pre-merge and post-merge replays gave identical verdicts: `branches-ignore: [main]` and `tags-ignore: ['**']` on `push`, and `main` removed from the replay `if:` rule. The weekly run stays | A push of `main` and of a tag starts no run (`gh run list --branch main --limit 3`); the weekly run and a manual start still work | `git revert` | You lose one independent run after the merge; the weekly run and the pre-merge run on the same tree cover it. Also `pull_request` from forks stays |
| 7 | harness-kit | Slim `release.sh`: replace the retry code around waiting with `gh run watch --exit-status` on the run id, keeping the fail-closed rule; decide the local duplicate check (keep, or run it while CI runs) | The release tests in `tests/release.test.sh` pass; a killed `gh` still gives "CI result unknown" | `git revert` | The fail-closed logic was written after failures; removing code that handled them risks reintroducing them. Do it only with a test for each stop reason |
| 8 | harness-kit | Run the test files in parallel (`xargs -P`) with each file's output kept separate and printed in order | The set and order of PASS lines equal the sequential run's, over 10 runs; the time falls | `git revert` | Hidden shared state makes results irregular; a gate must not become irregular |
| 9 | harness-kit | Give each of the 7 whole-check faults a test file in `check-files`, fold the baseline stage into `validate`, and raise the shard count only if the full replay exceeds about 10 minutes | Verdicts of a full replay identical before and after; the per-stage times measured | `git revert` | Folding the baseline changes the chain that gives each shard its time limit; a wrong limit gives false TIMEOUTs |
| 10 | harness-kit | Two fast checks in `validate.sh`: every fault's find text occurs exactly once in its file, and every fault's check has a mapped test file | A deliberately broken entry makes `validate.sh` fail on the branch, not only at replay time | `git revert` | More checks slow the run; both are cheap text scans |
| 11 | The gadget | A targeted replay in `ship.sh` before the push; a weekly CI replay only if the measured minutes are small against 2,000 free private minutes | `ship.sh` on a change with a tied fault runs it; a survivor stops the ship | `git revert` | Your own header says not to run replays in consumer CI; local time on your Mac is the price |
| 12 | harness-kit, optional | A targeted replay on ordinary branch pushes as a fast lane, plus a completeness check: on a schedule, compare the targeted selection with the full run's kills, and flag any fault killed by a test file that `check-files` did not list | The comparison flags a planted map gap | `git revert` | Only worth adding if the full replay is too slow after steps 7 to 10, because it adds machinery and its safety depends on the map |

## Negative results

- The time of a full replay after the "own test file" change, per-file test durations, the Claude Code install time, the gadget's CI time and per-check time: NOT FOUND (not measured).
- Whether v4 actions still run after 23 September 2026: NOT FOUND.
- Whether GitHub accepts a direct push of a green commit under a ruleset, whether a new ruleset's bypass list contains a personal owner, and the price of GitHub Pro: NOT FOUND.
- Whether you push branches by hand before `release.sh` does: NOT FOUND.
- Whether the gadget's `scripts/check.sh` or any hook runs the replay: NOT FOUND. The list `.harness/protected-paths` of the gadget: NOT FOUND (not read).
- The body of `release.sh`, `ship.sh`, `ci-lib.sh` and `replay-faults.mjs`: not read; headers only. Whether the manual start (`workflow_dispatch`) accepts a commit rather than a branch name: not verified; the design uses the branch's head, which is the same commit.
- Which of the 20 test files `validate.sh` does not run: NOT FOUND.
- No project in the samples runs a curated fault replay in CI (files 02 and 03), so nothing external validates or contradicts the design's central move.

## Strongest counter-cases

- **Against the whole design ("move the replay, do not remove it").** It adds elapsed time before every release (about 25 minutes until the replay is faster), and the total machine time of a release falls only by two `validate` runs. If elapsed time is your real cost, a design that runs the full replay less often (the fast lane) is what the mainstream practice does, at the price of trusting the hand-written `check-files` map.
- **Against removing the runs on `main` and the tag (step 6).** They are an independent check after the merge on a clean machine with that day's image and installer. The weekly run is the replacement, but it can be days later. If quality must not drop at all, keep them for a few releases after step 2 and compare.
- **Against the ruleset (steps 3 and 4).** It binds you only if the owner bypass is off, and its behaviour with a direct push is unverified. A mistake locks you out of releasing until you change a setting.
- **Against the speed steps (7 to 9).** Each removes or rearranges code that exists because something once failed. The tests you already have (about 8,100 lines) are the protection, and each step must show identical verdicts before and after.
- **Against my times.** Every predicted time rests on a rounded 25-minute figure, a subtraction, and an unmeasured setup time per shard. The design's direction does not depend on them; the size of the speed-up does.
- **Against the sources.** Nothing in the samples matches your fault-replay tool, so the design is reasoning from neighbouring practice (file 02) and from your own files, not from a project that does the same thing.
