# 00 — Decision summary: CI and release process for harness-kit and the gadget

Written on Wednesday 30 September 2026. Research only: no repository was changed. Details, sources and counter-cases are in files 01 to 06.

**Terms.** *Fault replay*: checking a fixed list of planted breaks (137 in harness-kit, 33 in the gadget) to prove the tests still catch each one; *full* runs all, *targeted* only those tied to changed files. *Fast-forward*: moving `main` to a commit that already contains all of `main`, so the tested commit is the landed commit. *Ruleset*: a GitHub setting that refuses changes to a branch unless named checks passed. *[VERIFIED]* primary source; *[PARTIAL]* extract or secondary; *[ASSUMPTION]* my reasoning; *NOT FOUND* searched, nothing found.

**Evidence.** This page rests on files 01 to 06 (485 distinct sources: 453 primary, 32 secondary) and cites 7 directly, all primary. Counts and selection methods are at the top of each file.

## Contradictions with what you believe

1. **"Full replay on every merge is necessary" is half right.** It is necessary but in the wrong place: for an ordinary change it runs only after the merge, which is why `main` went red 4 times in 2 days. [VERIFIED | your own `validate.yml` comment] Rust and Cargo test the exact commit before it lands and have no test run on `main` at all. [VERIFIED | their workflow files] 14 of 16 sampled projects do re-run tests on `main`, so it is not wrong, only not required. (Files 01, 02.)
2. **"Custom release scripts are safer than pull requests" has no support.** None of 9 large projects and 19 AI-harness repositories lands changes by a local script alone. The closest, everything-claude-code, keeps a hand script and makes CI refuse the release unless CI passed on that exact commit. Your pre-push hook can be skipped with `git push --no-verify`; a GitHub ruleset cannot. (Files 01, 03.) The belief is right in one place: `git-guard.mjs` blocks push forms that Claude Code's native deny rules miss. (File 04.)
3. **Private repositories do not get branch protection or a merge queue for free.** Both need a paid plan; a merge queue needs an organisation, so neither repository can use it. The Pro price is NOT FOUND. Rulesets are free for harness-kit (public) only. [VERIFIED | docs.github.com, re-read 2026-09-30]
4. **The gadget's ordinary changes are not replayed at all.** Neither `ship.sh` nor `release.sh` calls the replay; only `land.sh`, CI and manual runs do. [VERIFIED | search of the plugin folder]
5. **Two hidden costs:** 7 of 137 faults each run a whole check, and `release.sh` gives up on a CI run after 900 seconds, less than the 25-minute replay. [VERIFIED | my tally; `ci-lib.sh` header]
6. **Node 20 was removed from runners on 23 September 2026.** Whether your v4 actions still run: NOT FOUND (your runs of 29–30 September passed).

## Recommended target design, in plain words

**harness-kit.** Keep how you work. When you run `release.sh`, it also asks GitHub to run the **full replay on the exact commit**, waits for it (while you are away; the script already resumes and notifies), and only then fast-forwards `main` and pushes the tag. `main` cannot turn red from a replay again. After two releases show the same verdicts before and after, stop running anything on pushes to `main` and tags; keep the Monday run. Then, one at a time and each measured: parallel test files, the 7 whole-check faults, folding the baseline stage into `validate`, more shards, and a ruleset on `main` after a scratch-repository test.

**The gadget.** Keep `ship.sh` as the only way to `main`. Add npm caching, cancelling of outdated runs and timeouts to its CI, and a targeted replay in `ship.sh` before the push; do not cache Chromium (Playwright advises against it). Server-side rules need a paid plan: your decision.

**Nothing is removed until its replacement has run in the real flow;** file 06, section 3, lists every gate before and after.

**Expected effect [ASSUMPTION, built from your measured 358–379 s local check, 2m13s–2m40s CI job and about 25-minute replay].** Time until you know whether a change is sound: about 34 to 35 minutes today (about 9 to 10 at the terminal, then a 25-minute replay after `main` has already moved), about 31 to 32 after step 2 (before `main` moves), and about 20 to 28 after the speed steps. Attention: about 2 to 3 minutes per release, against your 30 to 60. Whole-check runs per release: 6 falling to 3. Step 0 replaces each number with a measured one.

## The first three steps

**Step 0 — measure (both repositories; changes nothing).** Per-job times of the last 30 runs, per-test-file times on your Mac and on a runner, the gadget's job time, and whether running test files 4 at a time gives identical results. *Counter-case:* runs on shared machines vary with load, so use medians and ranges.

**Step 1 — hygiene commit in harness-kit.** Current action versions (Node 24), a timeout on `validate`, and cancelling of outdated runs (never for `main`, tags or the weekly run). Test: same jobs and PASS lines; a second quick push cancels the first. `validate.yml` is a machinery file, so this branch runs the full replay, which exercises the new artifact actions. Undo: `git revert`. *Counter-case:* newer artifact actions may change how results merge and break the verdicts job; that run is the test.

**Step 2 — put the full replay in front of the merge (harness-kit, scratch repository first).** `release.sh` starts the replay on the pushed branch, waits with a raised limit, and the `main` run stays for now so the two verdicts can be compared. Test in a scratch copy: a release lands; a deliberately weakened test stops `release.sh` with `main` unchanged; an interrupted release resumes. Undo: `git revert`. *Counter-case:* about 25 more minutes elapse before each release. The alternative, a targeted replay before the merge and the full one weekly, is the mainstream shape but is only as strong as the hand-written file map; choose it only if step 0 shows the full replay too slow.

**Who.** Claude Code, inside the harness-kit repository (for the gadget, `/Users/aayushsanjar/Aayush_Projects/atlassian-app/control-chart-gadget`), proposing and committing each step under your rules; you run `release.sh` and `ship.sh`. Steps 3 to 12 are outlined in file 06.

**Not found.** No project in the research runs a curated fault replay in CI, so nothing outside your files validates the central move. Full-replay time after your optimisation, per-file test times, the Pro price, and whether a ruleset accepts your direct push are NOT FOUND.
