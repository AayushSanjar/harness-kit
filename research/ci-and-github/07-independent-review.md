# 07 — Independent review of the ci-and-github report

Written on Wednesday 30 September 2026. Reviewer: Claude Opus 5.5 in Cowork, a different model from the one that wrote files 00 to 06 (Claude Sonnet 5.5). I checked the report; I did not rewrite it. I ran no git command and committed nothing.

## Summary

I checked **59 claims**. **50 are CONFIRMED, 7 are WRONG and 2 are UNSUPPORTED.** Separately, the report marked **7 questions** NOT FOUND, and the harness-kit files or GitHub's public run data answer 6 of them (section 5). The seventh, the price of GitHub Pro, is still NOT FOUND.

**Does the recommendation in 00-decision.md still stand? Yes in direction, with six changes.** The central move still holds: replay every fault before `main` moves, keep the weekly run, and stop the duplicate runs on `main` and on tags only after the new place is proved. The evidence makes it stronger than the report thought.

The report's main cost figure is out of date. It said a full replay takes about 25 minutes. GitHub's own record of your runs shows that since v0.20.0 (part B, commit e275280) the whole replay run takes **10.9 minutes on `main` and 12.4 minutes on the branch**. [VERIFIED | GitHub Actions public API, runs 36697420941 and 36695203471, full read]

The six changes, each explained later in this file:

1. **Change the mechanism of step 2.** Do not make `release.sh` start a separate manual run and wait for it. Instead, change one condition in `validate.yml` so that every branch push runs the full replay, not only a push that changes a machinery file. [ASSUMPTION: my recommendation]
   - The reason is that `ci_wait` in `ci-lib.sh` takes a list of the commit's runs when the first run appears, and then waits only on those. A manual run started after that list is taken would not be waited on (section 3, D1). [VERIFIED | `ci-lib.sh` lines 88–95 and 136, full read of those lines]
   - Branches in harness-kit are pushed by `release.sh`, so in practice "every branch push" means "every release". [PARTIAL: `release.sh` step 3 pushes the branch; whether you ever push a branch by hand is NOT FOUND]
2. **Replace every time in 00 and 06.** They are built on the 25-minute figure from before part B. The corrected arithmetic is in section 4. The time until you know whether a change is sound falls from about 20 minutes today to about 17 to 19 minutes, and `main` no longer moves before the answer. It is not "34 to 35 falling to 31 to 32". [ASSUMPTION: arithmetic from measured run times]
3. **Raise `SHIP_CI_RUN_SECONDS` as part of the change.**
   - The report says `release.sh` gives up after 900 seconds, "less than the 25-minute replay". That comparison is wrong today: the branch replay run took 744 seconds, which fits under 900.
   - The margin is only about 2.5 minutes, though. Before part B, shards alone took up to 18.5 minutes.
   - So the limit should still be raised, with the measured value written beside it under your rule 42 ("standing question" before a threshold). [VERIFIED for the times; ASSUMPTION for the advice]
4. **Correct the gadget facts.**
   - The gadget has **15 faults, not 33**. The file `.harness/mutations.tsv` has 33 lines, but only 15 of them are entries. [VERIFIED | full read, on your Mac]
   - Both `.github/workflows/ci.yml` and `scripts/ship.sh` are on the gadget's `.harness/protected-paths`, so changes to them come as patches applied with `scripts/land.sh`. [VERIFIED | full read]
   - The gadget's `scripts/ship.sh` is a 1,324-byte wrapper around harness-kit's `ship.sh`. So "a targeted replay in `ship.sh`" is a change to harness-kit's plugin, which then reaches the gadget through an upgrade. [VERIFIED for the size and the header; ASSUMPTION for the consequence]
5. **Drop two speed ideas and re-order a third.**
   - Installing Claude Code takes 8 to 13 seconds per job, so caching or pinning it for speed is not worth doing. [VERIFIED | job step timings, run 36697420941]
   - Adding shards is not needed at today's sizes: the slowest shard took 4.6 minutes. [VERIFIED | same run]
   - The shards are unbalanced (1.9 to 4.6 minutes on the same run), so balancing them by measured time would help more than adding shards. [ASSUMPTION]
   - Folding the baseline stage into `validate` remains the largest single saving: that stage took 3.2 minutes on the critical path. [VERIFIED for the time]
6. **Add a rule for intermittent failures before moving the gate.**
   - One of the red `main` runs was a test that failed only sometimes. Defect D8 says: "the validate job passed the same case on the same commit, so it was intermittent". [VERIFIED | `.harness/defects.tsv`, full read]
   - Once the replay sits in front of the merge, such a failure blocks a release instead of turning `main` red. You need to decide in advance what `release.sh` should do then (for example: re-run once, then record a defect). The report does not address this. [ASSUMPTION]

## Terms used in this file

- **CONFIRMED** means the source I opened says what the report says. **WRONG** means the source says something different, and I state what is true and where it comes from. **UNSUPPORTED** means I could not find support for the claim as the report states it.
- **Full read** means I or a sub-agent read the whole file as raw text: a file in harness-kit or the gadget on your Mac, a raw file from `raw.githubusercontent.com`, or a JSON answer from GitHub's public programming interface. **Extract** means a page fetched through a tool that returns a summary written by a small model. Its quotations are only as exact as that tool's output.
- **Run** means one execution of a GitHub Actions workflow. **Job** means one machine inside a run. **Step** means one command inside a job.
- **Public run data** means GitHub's public programming interface (`api.github.com`) for the public harness-kit repository. I read it without logging in, from the shell on your computer, because that address is blocked from my cloud workspace.
- **Part B** means your v0.20.0 speed change (commit e275280, released 30 September 2026), after which each fault runs only its own test file.
- **Machinery file** means one of the 7 files in `.harness/replay-machinery`. A branch push that changes one of them runs the full replay.
- **Fault, full replay, targeted replay, whole check** have the meanings given in files 02 and 06.

## 1. What I did, and how I chose the claims

**Copying (task 1).**
- I created `research/ci-and-github/` in harness-kit and copied the seven report files and `sources.csv` into it unchanged. [VERIFIED | the SHA-256 checksum of each copy equals that of its source, computed on both sides]
- I changed nothing else in harness-kit. I did not copy the `evidence/` folder, because it was not part of the report's file list.
- The new folder is untracked: it is not committed, and `research/README.md` does not yet list it.
- The folder does not affect `tests/validate.sh`:
  - `check-names.mjs` scans only `README.md` and the plugin folder (`tests/check-names.test.sh` lines 132–134). [VERIFIED | full read]
  - I also searched the copied files for every secret shape in `guard-secrets.mjs` and found none. [VERIFIED | full read]

**Which claims I checked (task 2).**
- Every numbered claim under "Contradictions" in 00-decision.md.
- Every part of the recommended design and each of the three first steps.
- 41 further claims across files 01 to 06, chosen by three rules, so the choice was deliberate and not random:
  - first, every claim that the recommendation or its times depend on;
  - second, at least three [VERIFIED]-labelled claims per file whose primary source could be read as a full raw file;
  - third, every NOT FOUND that the repositories or the public run data could answer.
- I did not re-check the sample counts that would need all 16 or 19 repositories re-read, for example "14 of 16 sampled projects re-run tests on `main`". Those remain as the report states them.

**Who read what.**
- I read the harness-kit and gadget files on your Mac myself, in full. Harness-kit's local `main` points at commit e275280, the same commit the report read. [VERIFIED | `.git/refs/heads/main` read as a file]
- I read the public run data myself.
- Two research sub-agents that I started read the external sources. Wherever they could, they read raw files in full, and they gave exact quotations with line numbers. The pages they could only read as extracts are marked below.

## 2. The contradictions in 00-decision.md

| # | Claim in 00 | Verdict | Evidence and read mode |
|---|---|---|---|
| C1 | For an ordinary change the full replay runs only after the merge, which is why `main` went red 4 times in 2 days; Rust and Cargo have no test run on a push to `main` | **CONFIRMED** | [VERIFIED] `validate.yml` gives the replay jobs the condition "push to `main`, or machinery changed, or schedule, or manual" (full read). The public run data (full read) shows the pattern: ordinary branches ran `validate` only, for example inc-time-audit 2.0 min, and `main` then ran the replay. The non-green `main` runs are: a8f033e cancelled after 46.9 min (28 Sep), and 6f5e876, 0a07bd1 and f84515e failed (29 Sep), which is four in about 24 hours. `defects.tsv` D4, D6 and D8 name three of those runs. Cargo's `main.yml` triggers only on `merge_group` and `pull_request`. Rust's `ci.yml` runs on pushes to `automation/bors/auto` and try branches, not `master`. Both are full raw reads. |
| C2 | No sampled project lands changes by a local script alone; everything-claude-code keeps a hand script and CI refuses unless CI passed on the exact commit; your hook can be skipped with `--no-verify`; `git-guard.mjs` blocks push forms that deny rules miss | **CONFIRMED** (spot-checked) | [VERIFIED] everything-claude-code's `release.yml` fails with "The release commit must equal origin/main exactly", and `verify-release-gates.js` waits for "successful exact-SHA CI" (full reads). `install-hooks.sh` line 96: "git push --no-verify skips this hook: your deliberate override" (full read). Claude Code's permissions page lists `git -C . push origin main` among forms that `Bash(git push *)` does not stop (extract, returned as the full page text). [PARTIAL] I re-checked 2 of the 28 sampled repositories, not all of them. |
| C3 | Private repositories get no branch protection or merge queue for free; merge queue needs an organisation; rulesets are free for public harness-kit only; Pro price NOT FOUND | **CONFIRMED** | [VERIFIED] GitHub's docs source files `gated-features/protected-branches.md`, `repo-rules.md` and `merge-queue.md` (full raw reads) say exactly this. The rulesets sentence does not name GitHub Enterprise Server, a detail that does not matter to you. The Pro price is still NOT FOUND: `githubs-plans.md` lists what Pro includes but gives no price, and github.com/pricing does not list Pro (extract). |
| C4 | Neither `ship.sh` nor `release.sh` runs the replay, so the gadget's ordinary changes are not replayed | **CONFIRMED** | [VERIFIED] A search for "replay" in `ship.sh` and `release.sh` finds nothing. The gadget's `scripts/check.sh` mentions the replay only in a comment and does not run it (full reads). |
| C5a | 7 of the 137 faults each run a whole check | **CONFIRMED** | [VERIFIED] I counted with a script: 137 entries, of which 7 name a check that has no `tests/*.test.sh` in `.harness/check-files`, and `tests/validate.sh` lines 44–60 then run the whole check (full reads). The 7 fault ids match the report exactly. |
| C5b | `release.sh` gives up on a CI run after 900 seconds, "less than the 25-minute replay" | **WRONG** | [VERIFIED] The 900 seconds is correct (`ci-lib.sh` header). The 25 minutes is from before part B. Since v0.20.0 the whole run took 10.9 min on `main` and 12.4 min (744 s) on the branch (public run data, full read). So the limit is above the replay today, with a margin of about 2.5 minutes. |
| C6 | Node 20 was removed from runners on 23 September 2026; whether v4 actions still run is NOT FOUND | **CONFIRMED** (and the open part is now answered) | [VERIFIED] The GitHub changelog of 2026-09-23 says: "This is the final notification that Node 20 is no longer available on GitHub Actions runners" (extract). Your own run of 30 September carries the annotation: "The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/checkout@v4, actions/setup-node@v4" (public run data, full read). The runner's source code says the same: "Phase 3: Always use Node 24 regardless of environment variables" (full raw read). So v4 actions do not fail; the change in step 1 is hygiene, not an emergency. |

Result for section 2: 7 claims, 6 CONFIRMED, 1 WRONG.

## 3. The recommended design and the first three steps in 00-decision.md

| # | Part of the design | Verdict | Evidence and read mode |
|---|---|---|---|
| D1 | `release.sh` "asks GitHub to run the full replay on the exact commit" and waits for it | **UNSUPPORTED as specified** | [VERIFIED] `ci-lib.sh` lines 88–95: `ci_wait` finds "the CI runs for the pushed commit HEAD (gh run list --commit)" and, without `.harness/ci-workflow`, takes "every run listed for the commit when the first one appears" (full read). A manual run started after that moment is not in the list, so today's code does not guarantee the wait. The report flagged this as "not verified" in 06 but still put it in 00. [ASSUMPTION] The simpler way is to widen the replay condition in `validate.yml` to every branch push. Then the replay is part of the push's own run, and `ci_wait` waits for it without any new code. You already ran this pattern by hand once: the manual run on inc-speed-a-fix-1 (29 Sep, 25.1 min) was started 8 seconds after the branch push (public run data). |
| D2 | `release.sh` "already resumes and notifies" | **CONFIRMED** | [VERIFIED] `release.sh` header, sections "RESUMABLE" and "THE NOTIFICATION" (full read of the header). |
| D3 | After two matching releases, stop runs on pushes to `main` and tags; keep the Monday run | **CONFIRMED** (the premise) | [VERIFIED] For v0.20.0 the same commit e275280 ran three times: branch 12.4 min, `main` 10.9 min, tag 3.4 min (`validate` only, with the replay jobs skipped) (public run data). GitHub's docs say a push trigger with no branch or tag filter "will run for events affecting either branches or tags" (full raw read). |
| D4 | Speed steps: parallel test files, the 7 whole-check faults, folding the baseline stage into `validate`, a ruleset after a scratch test | **CONFIRMED** (the premises) | [VERIFIED] 17 of 20 test files use `mktemp` and 3 do not (full read). The baseline stage repeats the whole check that `validate` has just run on the same commit: 180 s against 146 s (job steps, run 36697420941). GitHub's docs say commits may be "pushed directly to the protected branch" after checks pass (full raw read). Whether the tests are independent enough to run in parallel is still NOT FOUND. |
| D5 | "More shards" when a replay exceeds about 10 minutes | **UNSUPPORTED** as a priority | [VERIFIED] The slowest shard took 4.6 min and the fastest 1.9 min on the same run. [ASSUMPTION] Balancing the shards by measured time would cut the shard stage from about 4.6 to about 3.5 minutes (the average); adding shards is not needed at 137 faults. |
| D6 | Gadget: keep `ship.sh`; add an npm cache with both lock files, cancelling of outdated runs, timeouts and a targeted replay; do not cache Chromium | **CONFIRMED**, with a correction | [VERIFIED] The gadget's `ci.yml` has none of the three additions; both lock files exist; Playwright's CI page says "Caching browser binaries is not recommended" (full raw read). The correction: `ci.yml` and `scripts/ship.sh` are protected paths, and `scripts/ship.sh` is a wrapper, so the replay change belongs in harness-kit's plugin (section 1, change 4). |
| D7 | Expected effect: about 34–35 minutes today, 31–32 after step 2, 20–28 after the speed steps | **WRONG** | [VERIFIED for the inputs] These numbers use the 25-minute replay from before part B. Section 4 gives the corrected arithmetic. |
| D8 | Whole-check runs per release: 6, falling to 3 | **CONFIRMED** | [VERIFIED] The six runs are: the Stop gate (when not skipped), the local check in `release.sh`, `validate` on the branch, `validate` and the baseline on `main`, and `validate` on the tag (`validate.yml` and public run data). [ASSUMPTION] With the replay on the branch, 3 remain (local, `validate`, baseline) and, after folding the baseline, 2. |
| D9 | Terms: "33 in the gadget" | **WRONG** | [VERIFIED] 15 entries: 33 lines, of which 15 have the five tab-separated fields (full read). |
| S0 | Step 0, measure | **CONFIRMED** as needed; partly done now | [VERIFIED] Per-job and per-step times for harness-kit are public, and I read them (section 4). Still NOT FOUND: per-test-file times on the Mac and on a runner, whether the tests can run in parallel, and the gadget's run times (its repository is private, and I did not read its runs). |
| S1 | Step 1, hygiene: Node 24 action versions, a timeout on `validate`, cancelling of outdated runs; the branch itself runs the full replay because `validate.yml` is a machinery file | **CONFIRMED** | [VERIFIED] The `validate` job has no `timeout-minutes` (full read). `validate.yml` is on `.harness/replay-machinery` (full read). checkout v5 and setup-node v5 declare `node24`, as do upload-artifact v6 and download-artifact v7; the newest are checkout 7.0.1, setup-node 7.0.0, upload-artifact 7.0.1 and download-artifact 8.0.1 (each `action.yml` and `package.json`, full raw reads). The default job timeout is 360 minutes (docs, full raw read; the report had marked this PARTIAL). [ASSUMPTION] Also missing from step 1: `node-version: 22` in all four jobs, which your earlier decision moves to 24. |
| S2 | Step 2 "adds about 25 minutes of elapsed time before each release" | **WRONG** | [VERIFIED] About 11 to 12.5 minutes today (C5b). The mechanism is covered in D1. |

Result for section 3: 11 claims, 6 CONFIRMED, 3 WRONG, 2 UNSUPPORTED.

## 4. The run times, and the corrected arithmetic

All figures come from GitHub's public run data for harness-kit, read in full on 30 September 2026. [VERIFIED]

| Run (commit) | Event | Whole run | validate | baseline | Shards (slowest / fastest) | verdicts |
|---|---|---|---|---|---|---|
| 36695203471 (e275280) | push to inc-speed-b (machinery) | 12.4 min | 3.6 | 3.4 | 5.0 / 1.8 | 0.3 |
| 36697420941 (e275280) | push to `main` | 10.9 min | 2.7 | 3.2 | 4.6 / 1.9 | 0.1 |
| 36697421656 (e275280) | push of tag v0.20.0 | 3.4 min | 3.3 | skipped | skipped | skipped |
| 36683110696 (9111ccc) | push to `main`, before part B | 25.3 min | 3.2 | 3.2 | 18.5 / 13.0 | 0.2 |

Steps of run 36697420941:
- Installing Claude Code took 13 seconds in `validate` and 8 to 9 seconds in the other jobs.
- `tests/validate.sh` took 146 seconds and the baseline part 180 seconds.
- The shards took 94 to 259 seconds.
- Checkout and setup of Node took 0 to 2 seconds each.
[VERIFIED]

**Corrected arithmetic.** Everything in this paragraph is [ASSUMPTION] built from the figures above and your measured 358 to 379 second local check.
- **An ordinary change today.** The local check takes 6 to 6.3 minutes. `validate` on the branch takes about 2.5 to 3.6 minutes. After `main` moves, the replay on `main` takes about 11 minutes. So you learn the truth about 20 minutes after typing `release.sh`, after `main` has moved.
- **After the replay moves to the branch push.** The local check takes 6 minutes, then the whole branch run about 11 to 12.5 minutes. So you learn the truth at about 17 to 19 minutes, before `main` moves.
- **After folding the baseline stage (about 3 minutes) and balancing shards (about 1 minute).** About 13 to 15 minutes.
- **Growth.**
  - Each shard held about 17 faults and took 1.9 to 4.6 minutes.
  - At the Free plan's limit of 20 jobs at once, 20 shards would hold about 340 faults at today's per-shard time.
  - So at today's per-fault times the report's "340 faults" ceiling happens to survive, but its derivation (shards of 18 to 20 minutes) is out of date.

## 5. Further claims from files 01 to 06

| # | File | Claim | Verdict | Evidence and read mode |
|---|---|---|---|---|
| X1 | 01 | Merge queue availability sentence | CONFIRMED | [VERIFIED] `gated-features/merge-queue.md`, full raw read |
| X2 | 01 | "…or pushed directly to the protected branch." | CONFIRMED | [VERIFIED] `about-protected-branches.md` line 99, full raw read |
| X3 | 01 | A workflow skipped by a path filter leaves its required check Pending; a job skipped by `if:` reports Success | CONFIRMED | [VERIFIED] `troubleshooting-required-status-checks.md` lines 76–77, full raw read (the page has moved to `content/pull-requests/how-tos/...`) |
| X4 | 01 | Standard Linux runner: 4 vCPU and 16 GB public, 2 vCPU and 8 GB private | CONFIRMED | [VERIFIED] `supported-github-runners.md`, full raw read |
| X5 | 01 | 20 jobs at once on Free; 256 jobs per matrix | CONFIRMED | [VERIFIED] `actions/reference/limits.md`, full raw read |
| X6 | 01 | 2,000 free private minutes (Pro 3,000); $0.006 per Linux 2-core minute; free on public repositories | CONFIRMED | [VERIFIED] billing reusables, full raw reads |
| X7 | 01 | Cache: 10 GB, 7 days, branch scope, pull-request caches not restorable by the base | CONFIRMED | [VERIFIED] `dependency-caching.md`, full raw read |
| X8 | 01 | Default job timeout 360 minutes (marked PARTIAL in the report) | CONFIRMED | [VERIFIED] `workflow-syntax.md` line 1226: "Default: 360", full raw read |
| X9 | 01 | Vite's file says `cancel-in-progress: ${{ github.ref_name != 'main' }}` | **WRONG** | [VERIFIED] Vite's `ci.yml` has `group: ${{ github.workflow }}-${{ github.event.number \|\| github.sha }}` and `cancel-in-progress: true`, and `ref_name` does not appear anywhere in the file (full raw read). [ASSUMPTION] Pushes to `main` get a group per commit, so in practice they are not cancelled, but the quotation is not in the file. |
| X10 | 01 | Rust and Cargo test the candidate before it lands and have no push-triggered test run on `main` | CONFIRMED | [VERIFIED] see C1 |
| X11 | 01 | "Pull request authors cannot approve their own pull requests." | CONFIRMED | [VERIFIED] `request-changes-tips.md`, full raw read |
| X12 | 01 | Playwright: "Caching browser binaries is not recommended…" | CONFIRMED | [VERIFIED] `docs/src/ci.md` line 1008, full raw read |
| X13 | 02 | PHP-CS-Fixer runs mutation tests only on pull requests, with that comment | CONFIRMED | [VERIFIED] `ci.yml` lines 261 and 268, full raw read |
| X14 | 02 | phpstan-src: `mutation-testing` only on pull requests, `--min-msi=100` | CONFIRMED | [VERIFIED] `tests.yml` lines 271, 275 and 360 (branch 2.1.x), full raw read |
| X15 | 02 | cargo-mutants: "not a substitute for a full test run" | CONFIRMED | [VERIFIED] `book/src/in-diff.md` line 20, full raw read |
| X16 | 02 | Pitest 1.18.0 removed the SCM goal | CONFIRMED | [VERIFIED] README release notes "#1379 Fully remove deprecated scm maven goal", full raw read |
| X17 | 02 | `replay-faults.sh`: targeted by default; "LOCAL ONLY"; find text must be in the file exactly once | CONFIRMED | [VERIFIED] header lines 5–7, 27–29 and 69–71, full read |
| X18 | 02 | Faults per test file (replay-faults 28, time-limit 18, stop-gate 17, and so on) and `check-files` 308 lines | CONFIRMED | [VERIFIED] my own count matches every number; `wc -l` gives 308 |
| X19 | 03 | compound-engineering's `AGENTS.md` quotation | CONFIRMED in substance; the quotation is not exact | [VERIFIED] The file says "All changes to `main` go through pull requests. Direct pushes and direct merges are not allowed; branch protection on `main` enforces this…". The report's quotation adds "to `main`" inside the second sentence. Full raw read. |
| X20 | 03 | Your earlier `research/initial-harness/03-reference-harnesses.md` says "3 of 15", "No hooks or CI were found" for compound-engineering, and "four scheduled" workflows for ChrisWiles, and the repositories contradict the last two | CONFIRMED | [VERIFIED] The three phrases are at lines 222, 118 and 190 (full read). compound-engineering has `ci.yml` running `claude plugin validate --strict`. ChrisWiles has 3 scheduled workflows and 1 that runs on pull requests and comments (full raw reads). [PARTIAL] That the workflows number exactly four comes from the ChrisWiles README, because the directory listing was blocked. I did not re-check the "about 12 of 19" count. |
| X21 | 03 | claudekit's unit tests use `continue-on-error: true` and shellcheck `\|\| true` | CONFIRMED | [VERIFIED] `test-hooks.yml` lines 29–31, 64–66 and 95, full raw read |
| X22 | 03 | everything-claude-code's release gates | CONFIRMED | [VERIFIED] see C2 |
| X23 | 03 | Without `--bare`, `claude -p` runs project hooks; `--bare` "is the recommended mode…" | CONFIRMED | [VERIFIED] code.claude.com/docs/en/headless, extract returned as full page text |
| X24 | 03 | Managed Code Review: neutral result, "$15-25", Team and Enterprise | CONFIRMED | [VERIFIED] code.claude.com/docs/en/code-review, extract returned as full page text |
| X25 | 03 | The "Expected" state trap is documented by spec-kit and claude-plugins-official | CONFIRMED | [VERIFIED] `extension-version-guard.yml` lines 13–14 and `validate-plugins.yml` lines 13–15, full raw reads |
| X26 | 04 | Deny-rule table, "isn't a security boundary", "can't carve an exception", a bare tool name removes the tool | CONFIRMED | [VERIFIED] code.claude.com/docs/en/permissions, extract returned as full page text |
| X27 | 04 | gitleaks-action: personal accounts need no licence key | CONFIRMED | [VERIFIED] README line 90, full raw read |
| X28 | 04 | tj-actions CVE-2025-30066: High, affected up to 45.0.7, patched 46.0.1 | CONFIRMED | [PARTIAL] github.com/advisories/GHSA-mrrh-fwg8-r2c3, extract only |
| X29 | 04 | 17 of 20 test files use `mktemp`; background-guard, ci-replay and plan-mode-guard do not | CONFIRMED | [VERIFIED] full read, counted |
| X30 | 04 | `install-hooks.sh` hook skippable with `--no-verify` | CONFIRMED | [VERIFIED] lines 33 and 96, full read |
| X31 | 05 | CI runs `tests/validate.sh` without `--skip-reviewed`; `.harness/check-command` has it | CONFIRMED | [VERIFIED] `validate.yml` line 78 and `check-command`, full reads |
| X32 | 05 | `check-reviewed.mjs` passes an empty diff | CONFIRMED | [VERIFIED] lines 16, 21, 71 and 107, full read |
| X33 | 05 | A tag push starts `validate` | CONFIRMED | [VERIFIED] run 36697421656 and the GitHub docs sentence in D3 |
| X34 | 05 | Line counts (release.sh 187, ship.sh 373, time-limit.mjs 610, replay-faults.sh 379, replay-faults.mjs 685, check-commits.mjs 443, guard-secrets.mjs 391, git-guard.mjs 377, stop-gate.mjs 331, install-hooks.sh 124, plan-mode-guard.mjs 36, ci-lib.sh 180, validate.sh 370, validate.yml 202) | CONFIRMED | [VERIFIED] `wc -l` on your Mac, all equal |
| X35 | 06 | `release.sh` pushes the branch itself (step 3) | CONFIRMED | [VERIFIED] header |
| X36 | 06 | Each `gh run watch` runs under `SHIP_CI_RUN_SECONDS`, 900 by default | CONFIRMED | [VERIFIED] `ci-lib.sh` lines 13–14 and 152 |
| X37 | 06 | The shard stage takes about 18–20 minutes and setup per shard is 1–2 minutes | **WRONG** | [VERIFIED] Since part B the shard stage is 4.6 to 5.0 minutes, and setup (checkout, Node, Claude Code install, download) is about 13 to 15 seconds (section 4) |
| X38 | 06 | The growth ceiling of about 340 faults, derived from shards of 18–20 minutes | **WRONG** in its derivation | [VERIFIED for the inputs] The number survives by coincidence (section 4); the arithmetic behind it does not |
| X39 | 06 | The Mac is about 2.5–3 times slower than the runner for `tests/validate.sh` | CONFIRMED | [VERIFIED] The step took 146 s on the runner, against your 358–379 s on the Mac |
| X40 | 05 | The gadget's `ci.yml`: one job, `branches-ignore: [main]`, checkout@v5, setup-node@v5 on Node 24, no cache, `npm ci` twice, Chromium `--only-shell`, `scripts/check.sh` | CONFIRMED | [VERIFIED] full read |
| X41 | 01 | Rulesets carry "the same plan wording" as protected branches | CONFIRMED | [VERIFIED] with the Enterprise Server nuance noted in C3 |

Result for section 5: 41 claims, 38 CONFIRMED, 3 WRONG.

**Totals: 7 + 11 + 41 = 59 claims; 50 CONFIRMED, 7 WRONG, 2 UNSUPPORTED.**

## 6. Questions the report left NOT FOUND that can now be answered

These are not counted above, because saying NOT FOUND is honest when the author searched and found nothing. But six of the seven had an answer in reach, from your own files or from public data.

1. **Do v4 actions still run after 23 September?** Yes: they are forced onto Node 24 (C6). [VERIFIED]
2. **How long does a full replay take after part B?** 10.9 to 12.4 minutes for the whole run (section 4). [VERIFIED] The report used the 25-minute figure from before part B, although the newer runs were already public.
3. **How long does installing Claude Code take in CI?** 8 to 13 seconds. [VERIFIED]
4. **Which of the 20 test files does `validate.sh` not run (your description said 19)?** None: every one of the 20 is named in `tests/validate.sh` at least twice. [VERIFIED by search; ASSUMPTION that being named means being run]
5. **Does the gadget's `check.sh` run the replay?** No. [VERIFIED]
6. **Is the gadget's `ci.yml` on its protected paths?** Yes, and so is `scripts/ship.sh`. [VERIFIED]
7. **What does GitHub Pro cost?** Still NOT FOUND.

## 7. Important questions the report missed

1. **What actually turned `main` red, and would a replay on the branch have caught it?** The report did not read `.harness/defects.tsv`, which answers this. [VERIFIED | full read, for the three descriptions below]
   - D6 was a new fault entry that "was never replayed or planted before it shipped" and did nothing. A targeted replay selects entries that are "new or changed since the merge-base" (`replay-faults.sh` header), so even the cheap targeted replay would have caught it before the merge. [ASSUMPTION for the "would have caught"]
   - D4 was runs interfering with each other through a shared registry.
   - D8 was an intermittent test.
   - So the late surprises came as much from the harness's own new faults and irregular tests as from product changes. That supports the design, and it raises question 2.
2. **What should a pre-merge replay do when a test fails only sometimes?** Today such a failure turns `main` red after the merge. In the new design it would stop a release. You need a written rule, for example "re-run once, and record a defect if the second run passes". [ASSUMPTION]
3. **Is the replay's split of faults into shards balanced?** It is not: 1.9 to 5.0 minutes on the same run. The split is by position ("entries at positions I, I+N, I+2N…", `replay-faults.sh` header). Balancing by the previous run's per-fault times is a smaller and safer change than adding shards. [VERIFIED for the imbalance and the rule; ASSUMPTION for the advice]
4. **Should every commit's "Breaks:" line be backed by a KILLED result?** D6 says "that commit's Breaks: line claimed its test fails with it" although the fault had never been replayed. Your own earlier fix list included this check; the report's step 10 covers only "find text exactly once". [VERIFIED | `defects.tsv`]
5. **Does cancelling outdated runs interact with `release.sh`?** If a second push to the same branch cancels a run that `release.sh` is waiting on, `ci_wait` sees "cancelled" and stops. It fails closed, which is safe, but you should know the message you will see. [ASSUMPTION from the `ci-lib.sh` header's "a completed run with any conclusion but success stops"]
6. **Which Node version should CI use?** `validate.yml` sets `node-version: 22` in all four jobs [VERIFIED], while your earlier decision was to move to 24 everywhere. The report's step 1 changes the action versions but not this line.
7. **Does the weekly safety net keep running?** GitHub disables scheduled workflows in a public repository after 60 days without activity (quoted in `validate.yml`'s own comment). If releases pause for two months, the weekly run silently stops. The start-up picture shows its age, but nothing fails. [VERIFIED for the quotation in your file]
8. **Should your private file path be published?** Files 00 and 06 name `/Users/aayushsanjar/Aayush_Projects/atlassian-app/control-chart-gadget`. It is not business content, so I left it unchanged. It will be public once committed to harness-kit. Your call. [VERIFIED | 00 line 36 and 06]

## 8. Task 3: business passages about control-chart-gadget

**Result: none found, so nothing was withheld.**

Method:
- I searched files 00 to 06 and `sources.csv` for "marketplace", "competitor", "pricing", "price", "customer", "revenue", "licence state", "demand", "Jira", "Forge", "Atlassian", "listing", "subscription" and "trial".
- I read every match, and every one of the 61 lines that mention "gadget".
- Every price in the report is a price of GitHub, Anthropic or third-party tools, not of the gadget.
- Every "marketplace" is the Claude Code plugin marketplace.
- The gadget is described only technically: a Forge app, its CI file, its check, its fault count and its protected paths.
- `sources.csv` has one Atlassian row, "Atlassian Forge: running forge deploy in CI/CD", which is technical.

[VERIFIED | full read of the matched lines]

## 9. Counter-cases to this review

- **Against my run-time corrections.** The figures come from one release (v0.20.0) after part B. Shared runners vary with load, and one run is not a median. The direction is safe (11 to 12 minutes against 25), but the exact numbers should be re-read after a few more releases.
- **Against my simpler step 2 (the replay on every branch push).** If you ever push branches by hand for other reasons, each push would spend about 11 minutes of free public runner time and run the replay earlier than needed. The report's manual-start design avoids that, at the cost of changing `ci_wait`. Choose the manual-start design only if you do push branches by hand.
- **Against "the recommendation stands".** I did not re-check the report's sample-wide counts (16 projects, 19 harness repositories, 9 mutation repositories). If those samples were misread, some context shifts. But the recommendation rests mainly on your own files and run data, which I did check.
- **Against the extracts.** Four external items were read only as extracts (the two changelog posts, the GitHub advisory, and the pricing pages). The Claude Code documentation pages came back as full page text through the fetch tool, but that is still not a raw file.

## 10. Sources used by this review

Each entry gives the read mode.
- **Your files on your Mac** (full reads):
  - harness-kit: `.github/workflows/validate.yml`, `.harness/*`, `tests/validate.sh`, `tests/check-names.test.sh`, the headers and parts of `release.sh`, `ship.sh`, `ci-lib.sh`, `replay-faults.sh`, `check-reviewed.mjs`, `install-hooks.sh` and `guard-secrets.mjs`, and `research/initial-harness/03-reference-harnesses.md`.
  - control-chart-gadget: `.github/workflows/ci.yml`, `.harness/protected-paths`, `.harness/mutations.tsv`, `scripts/check.sh` and `scripts/ship.sh`.
- **GitHub public run data for AayushSanjar/harness-kit** (full JSON reads, 30 September 2026): the list of the last 86 runs; the jobs of runs 36697420941, 36695203471, 36697421656, 36683110696, 36640236504, 36580479762, 36568268523 and 36495866037; and the annotations of two jobs.
- **GitHub docs source, github/docs on GitHub** (full raw reads): the gated-features reusables for protected branches, rulesets and merge queue; `about-protected-branches.md`; `troubleshooting-required-status-checks.md`; `supported-github-runners.md`; `limits.md`; the billing reusables; `dependency-caching.md`; `run-on-specific-branches-or-tags1.md`; `workflow-syntax.md`; `githubs-plans.md`; `request-changes-tips.md`.
- **GitHub changelog** of 2025-09-19 and 2026-09-23 (extracts).
- **GitHub's own action and runner code** (full raw reads): actions/runner `HandlerFactory.cs` and `NodeUtil.cs`; the `action.yml` and `package.json` of actions/checkout, setup-node, upload-artifact and download-artifact.
- **Other projects' repositories** (full raw reads): microsoft/playwright `docs/src/ci.md`; rust-lang/cargo `main.yml`; rust-lang/rust `ci.yml`; vitejs/vite `ci.yml`; PHP-CS-Fixer `ci.yml`; phpstan-src `tests.yml`; cargo-mutants `in-diff.md`; pitest `README.md`; compound-engineering `AGENTS.md` and `ci.yml`; ChrisWiles' four workflows; claudekit `test-hooks.yml`; everything-claude-code `release.yml` and `verify-release-gates.js`; gitleaks-action `README.md`; spec-kit `extension-version-guard.yml`; claude-plugins-official `validate-plugins.yml`.
- **Claude Code documentation** (extracts returned as full page text): the permissions, headless and code-review pages.
- **Extract only:** github.com/advisories/GHSA-mrrh-fwg8-r2c3; github.com/pricing.
