# 04 — Keeping tests healthy over time: tests that never fail, duplicate tests, removing tests, flaky tests (research question D)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Mutation testing:** a tool makes many small deliberate changes to the code, one at a time (each change is a **mutant**), and runs the tests against each. A mutant is **killed** when some test fails, and **survives** when every test still passes. A surviving mutant points at behaviour no test checks.
- **Planted fault and fault replay:** harness-kit's hand-written version of mutation testing. `.harness/mutations.tsv` lists 137 faults; each names a file, the text to find, its replacement, and the one test case that must fail. `replay-faults.sh` plants each fault in a copy of the repository and runs the tests.
- **Kill matrix:** a table of which test cases fail for which fault. Recording only the first failing case per fault is called **bailing**; recording every failing case gives the full matrix.
- **Killing, covering, not covering (Stryker's words):** a test is *killing* when it kills at least one mutant, *covering* when it runs the mutated code but kills none, and *not covering* when it does not even run it.
- **Redundant test:** a test whose failures are always accompanied by another test's failures, so removing it loses no detection. **Mutant subsumption** is the same idea applied to mutants.
- **Obsolete test:** a test of behaviour that no longer exists or no longer matters.
- **Flaky test:** a test that passes and fails on the same code. **Quarantine** means moving a flaky test out of the blocking run until it is fixed. A **retry** re-runs a failed test automatically.
- **Coverage:** which lines of code the tests run. It shows what is never executed, not what is checked.

## How this file is based on evidence

- **Sources.** This file cites 34 sources, 33 of them primary.
- **How they were chosen.** A research sub-agent read 81 documents (69 primary): the named papers by exact title, the tools' own documentation and release pages, and publisher records. Its search budget ran out after 25 searches; after that it fetched known addresses. Every read went through a fetch tool that returns a model-written extract, and the sub-agent caught and discarded one extract that had invented content.
- **What I checked myself.** I re-read Stryker's configuration page and its states page, Google's 2016 flaky-test post, the 2017 Google continuous-testing paper, the 2014 flaky-test study, chapters 11 and 12 of Google's testing book, the Node.js v24 test runner documentation and the bats writing-tests page. On the harness-kit clone at commit `e275280` I counted the fault entries, matched them to test cases and scripts, read the defect log, and ran `tests/stop-gate.test.sh` three times.
- **Labels** are as in file 01. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS

1. **harness-kit's replay proves each fault is caught by one named case, but it cannot say which tests catch nothing.** Each fault names the one case that must fail, which is the same as running a mutation tool with bailing on. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of the head of .harness/mutations.tsv] Measured:
   - The 137 faults name 124 distinct checks: 112 are test-case labels, 4 are checks inside `tests/validate.sh`, and 8 are labels built from variables that my script could not match.
   - Of 293 literal test-case labels, 181 (62%) are named by no fault. That does not mean they catch nothing; the replay simply does not record it.
   - Eight scripts have no planted fault at all: `brief-guard.mjs` and `reviewer-guard.mjs` (two of the guards), `check-commits.mjs` (443 lines, 16 cases), `check-reports.mjs`, `deploy.sh`, `eval-reviewer.mjs`, `report-path.sh` and `brief-lib.sh`.
   - [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - The full kill matrix is cheap to add: each replay already runs the fault's whole test file, which prints a PASS or FAIL line for every case, so recording every FAIL line needs no extra run. [ASSUMPTION, built on the README's statement that each fault is replayed "against its own test file"]
2. **Node's built-in test runner cannot retry a single test.** Neither the Node 22 nor the Node 24 documentation offers a per-test retry. From Node 24.7.0, `--test-rerun-failures` saves the state of a run so the next run repeats only failed tests; that resumes a run, it does not retry automatically. Its code coverage is still marked "Stability: 1 - Experimental". [VERIFIED | raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md | v24.x branch; accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | nodejs.org/en/blog/release/v24.7.0 | 2025-08-27] This matters to the gadget if its tests use `node:test`.
3. **Mutation testing of JavaScript is coarse under `node:test`.** StrykerJS, the main JavaScript mutation tool, has official runners for Jest, Mocha, Vitest, Jasmine, Karma, Cucumber and Tap, but none for `node:test`. [VERIFIED as read by a sub-agent | stryker-mutator.io/docs/stryker-js/plugins/ | accessed 2026-09-30] Through its TAP runner, "A test is always a test file", and through its generic command runner, all test details are unknown. [VERIFIED as read by a sub-agent | stryker-mutator.io/docs/stryker-js/tap-runner/ | accessed 2026-09-30] [VERIFIED as read by a sub-agent | stryker-mutator.io/docs/stryker-js/incremental/ | accessed 2026-09-30]
4. **A test that never fails is not a useless test.** Google found that most tests never fail, and its own conclusion was to run them less often, not to delete them (section 6). [VERIFIED | static.googleusercontent.com/media/research.google.com/en//pubs/archive/45861.pdf | 2017 | extract]

## 1. Mutation testing at scale: what Google learned

- **Scale in 2018:** used by 6,000 engineers on all code changes they author or review; more than 70,000 diffs, 1.1 million mutants and 150,000 actionable findings. Mutants are made only on changed lines that tests cover, at most one per line, and shown in code review. [VERIFIED as read by a sub-agent | web.eecs.umich.edu/~weimerw/2022-481W/readings/mutation-google.pdf | 2018]
- **Removing noise was the main work.** Over six years, developer feedback produced "more than one hundred rules" for skipping uninteresting code, which cut unproductive mutants "from 85% to 11%". [VERIFIED as read by a sub-agent | homes.cs.washington.edu/~rjust/publ/practical_mutation_testing_tse_2021.pdf | 2021]
- **Mutants relate to real bugs.** For 70% of 1,043 bugs, mutation testing would have reported a related mutant in the change that introduced the bug. And "more than 90% of all lines have a mutant majority fate of 100%", so mutants on one line are highly redundant. [VERIFIED as read by a sub-agent | www.arxiv.org/pdf/2103.07189 | 2021]

## 2. Using mutation results to judge tests

- **Stryker's three test states:** "Killing: The test is killing at least one mutant." "Covering: The test is covering mutants, but not killing any of them." "Not covering: The test is not even covering any mutants (and thus not killing any of them)." [VERIFIED | stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/ | accessed 2026-09-30 | extract]
- **Bailing hides tests.** Stryker's `disableBail` option makes the runner "report all failing tests when a mutant is killed instead of bailing after the first failing test", which Stryker says is useful "when using the 'Tests' view to hunt for tests that don't kill a single mutant." [VERIFIED | stryker-mutator.io/docs/stryker-js/configuration/ | accessed 2026-09-30 | extract]
- **Thresholds.** The default is `{ high: 80, low: 60, break: null }`; below `break`, "Stryker will exit with exit code 1, indicating a build failure." By default nothing breaks the build. [VERIFIED | stryker-mutator.io/docs/stryker-js/configuration/ | accessed 2026-09-30 | extract]
- **Only relevant tests run.** With the default `perTest` coverage analysis, "Only the tests that cover a specific mutant are executed for each mutant." [VERIFIED | stryker-mutator.io/docs/stryker-js/configuration/ | accessed 2026-09-30 | extract]
- **PIT** (the Java tool) has an option to keep running after the first failing test and record every failing test, and calls its incremental analysis "an experimental feature" whose assumption is "currently unproven". [VERIFIED as read by a sub-agent | pitest.org/quickstart/incremental_analysis/ | accessed 2026-09-30]
- A tool that reports tests which kill no mutant that another test does not also kill: NOT FOUND.

## 3. Finding duplicate and redundant tests

- **Reducing by coverage loses detection; reducing by mutants does not.** Across 18 projects, cutting a test suite by statement coverage shrank it by 62.9% on average "but loses up to 20.5% in killed mutants", while cutting by killed mutants lost none, at the cost of a suite 11.9 percentage points larger. [VERIFIED as read by a sub-agent | mir.cs.illinois.edu/gyori/pubs/fse14reduction.pdf | 2014]
- A survey defines the goal: "Test suite minimization seeks to eliminate redundant test cases in order to reduce the number of tests to run." [VERIFIED as read by a sub-agent | api.crossref.org/works/10.1002/stvr.430 | 2012-03]
- **Textual duplication:** jscpd supports bash files. [VERIFIED as read by a sub-agent | github.com/kucherenko/jscpd | v5.3.3, 2026-09-28] On harness-kit's tests it found 2.58% duplicated lines (file 02). [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured with jscpd 5.3.3] Duplicated text is therefore a small part of the problem.

## 4. Removing obsolete tests safely

- **Deletion is a normal part of test-suite change.** A study of six programs found that "most changes involve refactorings, deletions, and additions of test cases", not repairs. The paper's numbers on why tests were deleted: NOT FOUND, because the full text could not be reached. [VERIFIED as read by a sub-agent | research.ibm.com/publications/understanding-myths-and-realities-of-test-suite-evolution | 2012-11-11]
- **Google on tests that break without a real bug:** a brittle test is one "that fails in the face of an unrelated change to production code that does not introduce any real bugs". [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract] "Treat your tests like production code." [VERIFIED | abseil.io/resources/swe-book/html/ch11.html | 2020 | extract]
- A published practitioner rule of "delete a test only if the mutation score does not drop": NOT FOUND. The research above supports it as a reduction method.

## 5. Flaky tests

- **How common, at Google (2016):** "about 1.5% of all test runs reporting a 'flaky' result"; "Almost 16% of our tests have some level of flakiness associated with them!"; "about 84% of the transitions we observe from pass to fail involve a flaky test!" [VERIFIED | testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html | 2016-05-27 | extract]
- **What Google did:** re-run failing tests, mark a test flaky so it reports "a failure only if it fails 3 times in a row", and quarantine tests automatically when flakiness is too high. The same post warns that this "could easily mask a real race condition or some other bug in the code being tested". [VERIFIED | testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html | 2016-05-27 | extract]
- **How much is too much:** "Our experience suggests that as you approach 1% flakiness, the tests begin to lose value." "At Google, our flaky rate hovers around 0.15%." "Rerunning a test is only delaying the need to address the root cause of flakiness." [VERIFIED | abseil.io/resources/swe-book/html/ch11.html | 2020 | extract]
- **Causes:** in 201 commits that fixed flaky tests in 51 open-source projects, "74 out of 161 (45%) commits are from the Async Wait category", 20% concurrency and 12% test order. Fixes that add sleeps "are only decreasing the chance of a flaky failure". [VERIFIED | mir.cs.illinois.edu/marinov/publications/LuoETAL14FlakyTestsAnalysis.pdf | 2014-11 | extract]
- A 2021 survey of 76 papers found that 59% of surveyed developers dealt with flaky tests monthly, weekly or daily. [VERIFIED as read by a sub-agent | api.crossref.org/works/10.1145/3476105 | 2021-10-26]
- Martin Fowler's rule: "Place any non-deterministic test in a quarantined area. (But fix quarantined tests quickly.)", with a cap on how many tests may wait there. [VERIFIED as read by a sub-agent | martinfowler.com/articles/nonDeterminism.html | 2011-04-14]
- **Tool support:** bats has `$BATS_TEST_RETRIES` ("the maximum number of additional attempts") and `--filter-status failed` to re-run only failures. [VERIFIED | bats-core.readthedocs.io/en/stable/writing-tests.html | accessed 2026-09-30 | extract] [VERIFIED | bats-core.readthedocs.io/en/stable/usage.html | accessed 2026-09-30 | extract] Jest has `retryTimes`. [VERIFIED as read by a sub-agent | jestjs.io/docs/jest-object | Jest 30.5 docs; accessed 2026-09-30] Allure Report, which is open source, tracks each test's history across runs. [VERIFIED as read by a sub-agent | allurereport.org/docs/history-and-retries/ | accessed 2026-09-30]
- **harness-kit's own history.** The defect log records D7, a test that failed once under load because a stopped process had not yet written its process identifiers, fixed by giving it more time. It also records D8, a case that CI's replay caught failing on a commit where the same case passed in the ordinary check, which turned out to be a real bug rather than flakiness. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of .harness/defects.tsv] In my Linux container, one stop-gate case about a stopped process group failed three runs out of three, while the other 25 passed (file 02, section 7). [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured] All three involve process timing, the "async wait" family that Luo and colleagues found most common. [ASSUMPTION]

## 6. Tests that never fail

- Google studied more than 500,000 changes that affected 5.5 million test targets and 4 billion test outcomes in one month of 2016: "Of the 5.5 Million affected tests that we analyzed for a time period, only 63K ever failed", and "only a tiny fraction (1.23%) actually found a test breakage". Its conclusion: resources could be saved "had most of the 'always passing' tests been identified ahead of time, and executed less frequently". [VERIFIED | static.googleusercontent.com/media/research.google.com/en//pubs/archive/45861.pdf | 2017 | extract]
- Facebook's predictive test selection halved testing cost while still reporting "over 95% of individual test failures and over 99.9% of faulty changes". [VERIFIED as read by a sub-agent | arxiv.org/abs/1810.05286 | revised 2019-05-29]
- **Counter-case:** a test that never fails may simply guard code that has not changed; Google proposed running such tests less often, not deleting them. A test's value shows in whether it catches planted faults, especially ones no other test catches. [ASSUMPTION, built on the two sources above]

## 7. Coverage for shell scripts

- kcov measures bash coverage and ships for macOS and Linux. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/SimonKagstrom/kcov/master/doc/kcov.1 | v43, 2024-07-23] A comment in its bash engine says "Bash 4.2 and above supports BASH_XTRACEFD" and otherwise falls back to the error output, so with macOS's bash 3.2 its trace would share the script's error output. [PARTIAL | github.com/SimonKagstrom/kcov/blob/master/src/engines/bash-engine.cc | master branch; accessed 2026-09-30; read by a sub-agent; the macOS consequence is its inference]
- bashcov needs bash 4.3 or later and Ruby 3.2 or later. [VERIFIED as read by a sub-agent | rubygems.org/gems/bashcov | 4.0.0, 2026-08-25]
- For Node, c8 reports coverage from Node's built-in coverage. [VERIFIED as read by a sub-agent | github.com/bcoe/c8 | v11.0.0 (2026)]
- **Verdict** [ASSUMPTION]: skip coverage for harness-kit. Its planted faults already prove that tests check behaviour, which coverage cannot, and the bash tools fit poorly with macOS's default bash.

## 8. What this suggests

All of this section is my proposal. [ASSUMPTION, built on the evidence above]

### harness-kit

1. **Record the full kill matrix.** When a replay runs a fault's test file, keep every FAIL label it prints, not only the expected one, in the replay's results file. No extra runs are needed.
2. **Print a test-health report from it,** on demand, never as a gate:
   - cases named by no fault and failing for no fault: candidates to review, not to delete;
   - faults caught by exactly one case: those cases must never be deleted;
   - scripts with no planted fault (eight today, two of them guards): candidates for new faults.
3. **A deletion rule for tests.** A test may be removed only when (a) the behaviour it checks was removed in the same change, or (b) the matrix shows every fault it catches is also caught by another case, and the commit message quotes that evidence.
4. **A flaky-test record.** When a case fails and then passes on the same commit, add a line to the defect log, marked as flaky, with the case label, then either fix it or quarantine it with a date. No automatic retries in the blocking check: they hide the root cause, as Google warns.
5. **No coverage tool.**

### control-chart-gadget

1. Its planted faults (the ci-and-github research counts 33) can use the same kill-matrix idea. [PARTIAL | harness-kit/research/ci-and-github (local, untracked) | 2026-09-30 | full for 00-decision.md]
2. If its JavaScript tests run on Jest, Mocha or Vitest, StrykerJS can add generated mutants with per-test results; if they run on `node:test`, Stryker's results are per file only. Which runner it uses I could not see. StrykerJS would also be a new dependency, which the gadget's rule 6 says must be proposed first. [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context]
3. Browser tests (Playwright) are the usual home of flaky tests, because they wait on page events; they belong in the flaky record from their first failure. [ASSUMPTION, built on the async-wait finding above]

## Negative results

- A tool that reports tests killing no unique mutant: NOT FOUND.
- The Pinto study's numbers on why tests are deleted: NOT FOUND (paper not reachable).
- Empirical numbers on duplicated code in test suites: NOT FOUND (not searched after the budget ran out).
- A practitioner guideline tying test deletion to mutation score: NOT FOUND.
- Per-test coverage in c8 or Node's own coverage: NOT SEARCHED.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against the kill matrix:** harness-kit's faults are hand-picked, so a test that kills none of them may reveal a gap in the fault list, not a useless test. Google found coupled mutants for only 70% of real bugs.
- **Against a deletion rule:** it slows the removal of obviously dead tests. The rule's first branch covers them: behaviour removed in the same change.
- **Against no retries:** on shared CI machines, a retry can save a release from a one-off failure caused by load. The flaky record gives the same information without hiding it.
- **Against adding Stryker to the gadget:** a new dependency, run time, and noisy results until tuned; Google needed more than a hundred rules to cut the noise.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- A Survey of Flaky Tests (Parry et al.). https://api.crossref.org/works/10.1145/3476105. ACM TOSEM 31(1) via Crossref; 2021-10-26; primary; read: sub-agent extract.
- Allure Report: history and retries. https://allurereport.org/docs/history-and-retries/. Allure; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- An Empirical Analysis of Flaky Tests (Luo, Hariri, Eloussi, Marinov). https://mir.cs.illinois.edu/marinov/publications/LuoETAL14FlakyTestsAnalysis.pdf. FSE 2014; 2014-11; primary; read: extract.
- Balancing trade-offs in test-suite reduction (Shi et al.). https://mir.cs.illinois.edu/gyori/pubs/fse14reduction.pdf. FSE 2014; 2014; primary; read: sub-agent extract.
- bashcov on RubyGems. https://rubygems.org/gems/bashcov. infertux; 4.0.0, 2026-08-25; primary; read: sub-agent extract.
- bats-core documentation: Usage. https://bats-core.readthedocs.io/en/stable/usage.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- bats-core documentation: Writing tests. https://bats-core.readthedocs.io/en/stable/writing-tests.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- c8. https://github.com/bcoe/c8. Ben Coe; v11.0.0 (2026); primary; read: sub-agent extract.
- ci-and-github research: 00-decision.md, and sections of 04, 05 and 07. harness-kit/research/ci-and-github (local, untracked). Cowork research job for the same person; 2026-09-30; secondary; read: full for 00-decision.md; extract for the others.
- control-chart-gadget CLAUDE.md, version 4.3. control-chart-gadget/CLAUDE.md (private repository). the person (private repository); 2026-09-28; primary; read: seen in context: loaded automatically by this session, not opened by me.
- Does mutation testing improve testing practices? (Petrović et al.). https://www.arxiv.org/pdf/2103.07189. ICSE 2021 (arXiv preprint); 2021; primary; read: sub-agent extract.
- Eradicating Non-Determinism in Tests. https://martinfowler.com/articles/nonDeterminism.html. Martin Fowler; 2011-04-14; primary; read: sub-agent extract.
- Flaky Tests at Google and How We Mitigate Them. https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html. Google Testing Blog (John Micco); 2016-05-27; primary; read: extract.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- Jest object: retryTimes. https://jestjs.io/docs/jest-object. Jest project; Jest 30.5 docs; accessed 2026-09-30; primary; read: sub-agent extract.
- jscpd repository and FORMATS.md. https://github.com/kucherenko/jscpd. Andrey Kucherenko; v5.3.3, 2026-09-28; primary; read: sub-agent extract.
- kcov bash engine source. https://github.com/SimonKagstrom/kcov/blob/master/src/engines/bash-engine.cc. Simon Kagstrom; master branch; accessed 2026-09-30; primary; read: sub-agent extract.
- kcov manual page and releases. https://raw.githubusercontent.com/SimonKagstrom/kcov/master/doc/kcov.1. Simon Kagstrom; v43, 2024-07-23; primary; read: sub-agent extract.
- Mutant states and metrics. https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: extract.
- Node.js v24 documentation: Test runner. https://raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md. Node.js project; v24.x branch; accessed 2026-09-30; primary; read: extract.
- Node.js v24.7.0 release notes. https://nodejs.org/en/blog/release/v24.7.0. Node.js project; 2025-08-27; primary; read: sub-agent extract.
- PIT: incremental analysis. https://pitest.org/quickstart/incremental_analysis/. PIT (pitest); undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Practical Mutation Testing at Scale: A view from Google (Petrović et al.). https://homes.cs.washington.edu/~rjust/publ/practical_mutation_testing_tse_2021.pdf. IEEE TSE; 2021; primary; read: sub-agent extract.
- Predictive Test Selection (Machalica et al.). https://arxiv.org/abs/1810.05286. arXiv (Facebook); revised 2019-05-29; primary; read: sub-agent extract.
- Regression testing minimization, selection and prioritization: a survey (Yoo, Harman). https://api.crossref.org/works/10.1002/stvr.430. STVR 22(2) via Crossref; 2012-03; primary; read: sub-agent extract.
- Software Engineering at Google, chapter 11: Testing Overview. https://abseil.io/resources/swe-book/html/ch11.html. Google / O'Reilly; 2020; primary; read: extract.
- Software Engineering at Google, chapter 12: Unit Testing. https://abseil.io/resources/swe-book/html/ch12.html. Google / O'Reilly (Erik Kuefler); 2020; primary; read: extract.
- State of Mutation Testing at Google (Petrović, Ivanković). https://web.eecs.umich.edu/~weimerw/2022-481W/readings/mutation-google.pdf. ICSE-SEIP 2018; 2018; primary; read: sub-agent extract.
- StrykerJS configuration. https://stryker-mutator.io/docs/stryker-js/configuration/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: extract.
- StrykerJS incremental mode. https://stryker-mutator.io/docs/stryker-js/incremental/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- StrykerJS plugins (official test runners). https://stryker-mutator.io/docs/stryker-js/plugins/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- StrykerJS TAP runner. https://stryker-mutator.io/docs/stryker-js/tap-runner/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Taming Google-Scale Continuous Testing (Memon et al.). https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/45861.pdf. Google; ICSE-SEIP 2017; 2017; primary; read: extract.
- Understanding myths and realities of test-suite evolution (Pinto, Sinha, Orso). https://research.ibm.com/publications/understanding-myths-and-realities-of-test-suite-evolution. FSE 2012 (IBM Research page); 2012-11-11; primary; read: sub-agent extract.
