# 02 — Test files: size, naming, structure, shared set-up, and testing shell scripts (research question B)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Test file:** one file of tests, such as `tests/stop-gate.test.sh`.
- **Test case:** one check inside a test file that ends in one pass or fail. In harness-kit each case prints one line, `PASS <label>` or `FAIL <label>`.
- **Label:** the sentence that names a case, such as "passing check: exit 0 silently". In harness-kit the label is also the case's identity: the fault list and the check-to-file map refer to cases by their exact label.
- **Unit under test:** the script or module a case exercises, such as `stop-gate.mjs`.
- **Runner:** the program that finds and runs test files. harness-kit's runner is `tests/validate.sh`.
- **Helper:** a function that tests share, such as harness-kit's `result` (prints the PASS or FAIL line) or `new_repo` (makes a temporary git repository). A **helper library** is one file of helpers that every test file loads.
- **Fixture:** the state a test sets up before it acts, such as a temporary folder with a fake check script. A **fresh fixture** is built anew for each case; a **shared fixture** is built once and reused.
- **Arrange-Act-Assert:** a way to lay out a case in three steps: set up, do the one thing being tested, check the result. **Given-When-Then** is the same idea in behaviour-driven wording.
- **Test smell:** a pattern in test code that makes tests hard to read or maintain. Examples below: an **Eager Test** checks too much at once; a **General Fixture** sets up more than the case needs; a **Mystery Guest** depends on set-up the reader cannot see; **Test Code Duplication** is the same test code repeated many times.
- **DRY and DAMP:** DRY ("don't repeat yourself") removes repetition. DAMP ("descriptive and meaningful phrases") accepts some repetition when it makes each test easier to read on its own.
- **bats, ShellSpec, shUnit2:** three test frameworks for shell scripts. **node:test** is the test runner built into Node.js.
- **TAP:** the Test Anything Protocol, a plain-text format for test results that many tools can read.
- **Planted fault and fault replay:** harness-kit's own method of proving tests work: a deliberate small break is put into a script, and a named test case must then fail. File 04 covers it.

## How this file is based on evidence

- **Sources.** This file cites 34 sources, 33 of them primary.
- **How they were chosen.** A research sub-agent read 81 pages (79 primary), starting from the sources named in the question (Google's testing book and blog, Wake, Fowler, Meszaros, Beck, the test tools' own documentation), then the tools' release pages and registries for versions. It could run only 14 web searches before the session's shared search budget ran out, so where it says NOT FOUND about benchmarks or migration case studies, that means "not searched", not "searched thoroughly".
- **What I checked myself.** I re-read Google's chapter on unit testing, the Node.js and git test conventions, the bats documentation pages on usage, writing tests and gotchas, Google's shell style guide and the Peruma study. I measured all 20 harness-kit test files at commit `e275280` with scripts, ran jscpd (a copy-and-paste detector, version 5.3.3) on them, and ran `tests/stop-gate.test.sh` in my cloud container.
- **Labels** are as in file 01: [VERIFIED] followed by the link, the date and how I read it; [VERIFIED as read by a sub-agent] followed by the link and the date; [PARTIAL]; [ASSUMPTION]; NOT FOUND. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS

1. **Google's shell style guide says long shell scripts should not be shell at all.** "If you are writing a script that is more than 100 lines long, or that uses non-straightforward control flow logic, you should rewrite it in a more structured language *now*." [VERIFIED | google.github.io/styleguide/shellguide.html | accessed 2026-09-30 | extract] In harness-kit, 13 of the 16 shell scripts are over 100 lines, and all 20 test files are bash, from 86 to 1,320 lines. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - Counter-case: this is Google's house rule, not a law. git runs one of the largest test suites in existence in shell, with its own shared library. [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract] harness-kit already follows the spirit of the rule: two thirds of its script lines (5,965 of 8,957) are JavaScript. The tests are shell because they drive scripts and hooks as separate processes, the way Claude Code runs them, which is a reasonable choice.
2. **The tests are long, but not because of copy and paste.** jscpd found 17 copied blocks covering 217 of the test lines (2.58%) at its default settings, and 406 lines (4.82%) with a lower threshold. The script folder has 0% copied shell and 1.16% copied JavaScript. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured with jscpd 5.3.3] What the measurements do show:
   - **Three files test more than one script.** `ship.test.sh` (1,320 lines) tests seven scripts; `replay-faults.test.sh` tests `replay-faults.sh` and `land.sh`; `time-limit.test.sh` tests `time-limit.mjs` and `check-limits.mjs`. `land.sh` is tested in two files, 8 cases in one and 6 in the other.
   - **288 of about 295 cases type their label twice,** once for the pass branch and once for the fail branch. No pair has drifted apart yet (negative result), but every rename has to change both.
   - **Hand-written case numbers have already drifted in five files:** `time-limit.test.sh` has two sections numbered 9 to 11, `upgrade.test.sh` has two cases numbered 12, `ship.test.sh` has case 23b before case 22, `brief-guard.test.sh` has case 6 before case 5, and `replay-faults.test.sh` has no case 6. In `tests/validate.sh` the letters that head each section are out of order, skip (c) and use (ae) twice. Nothing reads these numbers, so nothing catches the drift.
   - **One helper is copied into every file.** The `result` function is copied, identically, into all 20 test files; `describe` has 13 copies in 8 versions; `new_repo` has 9 copies, all different.
3. **"Which test file is not run?" has an answer.** The ci-and-github research left this NOT FOUND: it counted 20 test files where your description said 19. [PARTIAL | harness-kit/research/ci-and-github (local, untracked) | 2026-09-30 | extract of 05-mapping.md] `tests/validate.sh` runs all 20, each by its own hand-written line. Nothing checks that a new test file gets such a line. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of tests/validate.sh]

## 1. What a good test looks like

### Google's rules

- **Test behaviours, not methods.** "Rather than writing a test for each method, write a test for each *behavior*." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract] The same author's 2014 post: "It's a much better idea to use separate tests to verify separate behaviors." [VERIFIED as read by a sub-agent | testing.googleblog.com/2014/04/testing-on-toilet-test-behaviors-not.html | 2014-04-14]
- **The name says the behaviour, and "and" is a warning.** "If you need to use the word 'and' in a test name, there's a good chance that you're actually testing multiple behaviors." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract]
- **No clever logic in tests.** "Stick to straight-line code over clever logic, and consider tolerating some duplication when it makes the test more descriptive." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract] When a test needs logic, move it into a helper. [VERIFIED as read by a sub-agent | testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html | 2014-07-31]
- **Some duplication is fine; helpers are fine too.** "A little bit of duplication is OK in tests so long as that duplication makes the test simpler and clearer." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract] The later blog post adds that DRY "is still relevant in tests", for example for a helper that builds values. [VERIFIED as read by a sub-agent | testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make.html | 2019-12-03]
- **Helpers take only what the test cares about.** Helpers should let "the test author to specify only values they care about, and setting reasonable defaults for all other values." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract]
- **One scenario per test.** A test that calls the code a second time after checking the first result is testing more than one scenario. [VERIFIED as read by a sub-agent | testing.googleblog.com/2018/06/testing-on-toilet-keep-tests-focused.html | 2018-06-11]
- **Brittle tests** are ones "that fails in the face of an unrelated change to production code that does not introduce any real bugs." [VERIFIED | abseil.io/resources/swe-book/html/ch12.html | 2020 | extract]

### The classic patterns

- Bill Wake named Arrange-Act-Assert in 2001 and wrote it up in 2011. [VERIFIED as read by a sub-agent | xp123.com/articles/3a-arrange-act-assert/ | 2011-04-26] Martin Fowler links Given-When-Then to behaviour-driven development and to Meszaros's four phases: set up, exercise, verify, tear down. [VERIFIED as read by a sub-agent | martinfowler.com/bliki/GivenWhenThen.html | 2013-08-21]
- Meszaros's smells: an Eager Test "is verifying too much functionality in a single Test Method"; a General Fixture "is building or referencing a larger fixture than is needed"; a Mystery Guest hides part of the cause "outside the Test Method"; Test Code Duplication is "The same test code is repeated many times." [VERIFIED as read by a sub-agent | xunitpatterns.com | 2003-2008]
- Kent Beck's "Test Desiderata" lists twelve properties of good tests, among them isolated, deterministic, fast, readable, behavioural and specific ("if a test fails, the cause of the failure should be obvious"). [VERIFIED as read by a sub-agent | medium.com/@kentbeck_7670/test-desiderata-94150638a4b3 | 2019-10-18]

### How common the smells are

A study of 656 open-source Android apps with 1,187,055 test methods found that "only 21 apps (approximately 3%) did not exhibit any test smells". Share of test files with each smell: Assertion Roulette 58.46%, Eager Test 38.68%, General Fixture 11.67%, Mystery Guest 11.65%. [VERIFIED | testsmells.org/assets/publications/CASCON2019_TechnicalPaper.pdf | 2019-11 | extract] (Assertion Roulette means many assertions with no message, so a failure does not say which one failed.) The study covers Java unit tests only.

### How harness-kit's tests compare

[ASSUMPTION: my reading of the test files against the rules above]

- **Already good.** Every label is a behaviour sentence, often with the script's name first, as Google asks: "ship.sh: stops on red CI with the run's URL; main untouched". Every failure prints the exit code, output and error text, which is the "clear failure message" rule. Each file builds its own temporary folders and fakes for `gh` and `claude`, so cases do not touch GitHub or each other.
- **Weaker.** Some cases hold loops and pass flags (`ok=yes`, then `ok=no` inside a loop), which is the logic Google warns against, though often it is one behaviour spread over several calls, such as "4 failures in a row". The per-file `new_repo` helpers differ in all nine files, so a reader of one file cannot assume what another file's repository contains: a mild Mystery Guest.

## 2. Test file size, and when to split a file

- **Tool limits are tool defaults, not evidence.** ESLint's `max-lines` rule defaults to 300 lines and admits "there is not an objective maximum number of lines considered acceptable in a file". [VERIFIED as read by a sub-agent | eslint.org/docs/latest/rules/max-lines | accessed 2026-09-30] Checkstyle's `FileLength` defaults to 2,000 lines. [VERIFIED as read by a sub-agent | checkstyle.org/checks/sizes/filelength.html | 14.3.0 docs; accessed 2026-09-30] Sonar's Java rule S104 defaults to 750 lines. [VERIFIED as read by a sub-agent | github.com/SonarSource/sonar-java | master branch; accessed 2026-09-30] None of the three cites evidence for its number.
- **Research on smells is about test methods, not file length.** tsDetect detects 19 smells in JUnit tests and says nothing about file size. [VERIFIED as read by a sub-agent | testsmells.org/assets/publications/FSE2020_TechnicalPaper.pdf | 2020] A 2026 paper defines a "Test Obsessed by Method" smell, a test covering several paths of one method, and found 44 such tests in 11 of 12 Python standard-library suites. [VERIFIED as read by a sub-agent | arxiv.org/html/2602.00761v1 | 2026]
- **What well-run projects do instead** is split by what is tested: Node.js asks for a new file per new test and names each file after the module under test. [VERIFIED | github.com/nodejs/node/blob/main/doc/contributing/writing-tests.md | accessed 2026-09-30 | extract] git names each file after the command it tests. [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract]
- **An evidence-based maximum length for a test file: NOT FOUND.** The sub-agent could not search after the budget ran out, so this is "not searched properly".
- **Rule proposed for harness-kit** [ASSUMPTION, built on the practice above]: split a test file when it tests more than one script, when one script's cases live in more than one file, or when two sections of it collide, as the numbering collisions show. Do not split by line count, because no evidence supports any particular count; a count chosen now would be an invented threshold.

## 3. Naming test files and test cases

| Tool or project | Default test file names |
|---|---|
| Node.js built-in test runner | `**/*.test.{cjs,mjs,js}`, `**/*-test.{cjs,mjs,js}`, `**/*_test.{cjs,mjs,js}`, `**/test-*.{cjs,mjs,js}`, `**/test.{cjs,mjs,js}`, `**/test/**/*.{cjs,mjs,js}` |
| Jest | files in `__tests__` folders, or ending `.test` or `.spec` |
| Vitest | `**/*.{test,spec}.?(c\|m)[jt]s?(x)` |
| Maven Surefire (Java) | `**/Test*.java`, `**/*Test.java`, `**/*Tests.java`, `**/*TestCase.java` |
| bats | `.bats` files |
| ShellSpec | files ending `_spec.sh` under `spec/` |
| git | `tNNNN-commandname-details.sh` |

Sources: [VERIFIED | raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md | v24.x branch; accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | jestjs.io/docs/configuration | Jest 30.5 docs; accessed 2026-09-30] [VERIFIED as read by a sub-agent | vitest.dev/config/include | v5 docs; accessed 2026-09-30] [VERIFIED as read by a sub-agent | maven.apache.org/surefire/maven-surefire-plugin/test-mojo.html | 3.6.0, published 2026-08-31] [VERIFIED as read by a sub-agent | bats-core.readthedocs.io/en/stable/tutorial.html | accessed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/shellspec/shellspec | latest release 0.28.1, 2021-01-11] [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract]

- harness-kit's `<name>.test.sh` fits the common pattern. The gap is that the name does not always match the unit: 17 of the 38 scripts have no test file with their name, because their cases live in another script's file. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
- For a Java comparison: Surefire's `FooTest.java` for `Foo.java` is the same idea as `land.test.sh` for `land.sh`. A test file that covers seven scripts is like one test class for seven production classes. [ASSUMPTION]

## 4. Testing shell scripts: frameworks, or hand-written test files

### bats-core

[VERIFIED | bats-core.readthedocs.io/en/stable/writing-tests.html | accessed 2026-09-30 | extract] [VERIFIED | bats-core.readthedocs.io/en/stable/usage.html | accessed 2026-09-30 | extract] [VERIFIED | bats-core.readthedocs.io/en/stable/gotchas.html | accessed 2026-09-30 | extract]

- Each case is an `@test "name" { ... }` block. `setup_file` and `teardown_file` run once per file, `setup_suite` once per run, and `load test_helper` sources a shared helper file.
- Cost: "Each Bats test file is evaluated *n+1* times, where *n* is the number of test cases in the file." Each case then runs "in its own process".
- Parallel runs: `--jobs` "requires GNU parallel or shenwei356/rush", and "Ordering of parallelised tests is not guaranteed, so this mode may break suites with dependencies between tests (or tests that write to shared locations)."
- Selection and output: `--filter-tags`, `--filter-status failed` to re-run only the cases that failed last time, and formatters for TAP and JUnit.
- Limits: `$BATS_TEST_TIMEOUT` aborts a slow case; `$BATS_TEST_RETRIES` re-runs a failed case.
- Gotchas that bite shell authors:
  - "My negated statement (e.g. ! true) does not fail the test, even when it should."
  - "I cannot register a test multiple times via for loop." So there are no generated or parameterised cases.
  - "The run function executes its command in a subshell which means the changes to variables won't be available in the calling shell."
  - "The set -e handling of [[ ]] and (( )) changed in Bash 4.1. Older versions, like 3.2 on MacOS, don't abort the test when they fail." macOS ships Bash 3.2.
- Latest release v1.14.0, 21 July 2026, MIT licence. The npm package lags behind at 1.13.0, and npm's `bats-file` package is a placeholder, so the helper libraries are installed as git submodules. [VERIFIED as read by a sub-agent | github.com/bats-core/bats-core | v1.14.0, 2026-07-21]

### ShellSpec and shUnit2

- ShellSpec is a behaviour-driven framework for all POSIX shells, with mocking, parallel runs and coverage through kcov. Its latest release is 0.28.1, dated 11 January 2021, and its changelog's "Unreleased" section is empty. [VERIFIED as read by a sub-agent | github.com/shellspec/shellspec | 0.28.1, 2021-01-11]
- shUnit2 is a JUnit-style framework for Bourne shells. Its latest release, 2.1.8, is from 2020, and its release notes say it "does not work when the `-e` shell option is set". [VERIFIED as read by a sub-agent | github.com/kward/shunit2 | 2.1.8 (2020, inferred)]

### git's own library

- Every git test script sources `test-lib.sh`; each case is `test_expect_success` with a message that says what is tested, an optional prerequisite, and a script; `test_when_finished` registers clean-up that runs even when the case fails. [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract]
- This is the closest model for harness-kit: hand-written shell tests, one shared library, no third-party dependency.

### Transcript tests

- Cram tests "look like snippets of interactive shell sessions": commands and their expected output. Its last PyPI release, 0.7, is from 24 February 2016. [VERIFIED as read by a sub-agent | pypi.org/project/cram/ | 0.7, 2016-02-24] Meta's scrut does the same in markdown or cram files and was released on 28 January 2026. [VERIFIED as read by a sub-agent | github.com/facebookincubator/scrut | v0.4.3, 2026-01-28]

### What the CI research concluded

- For speed, the ci-and-github research rated bats "Skip": adopting it means rewriting about 8,100 lines, and its parallel mode needs GNU parallel or rush. [PARTIAL | harness-kit/research/ci-and-github (local, untracked) | 2026-09-30 | extract of 04-reusable-components.md]

### Verdict

[ASSUMPTION, built on the evidence above]

- **Do not migrate to bats or ShellSpec now.** ShellSpec is effectively unmaintained. bats would cost a rewrite of 295 cases, including the 137 fault entries that name cases by label, and adds new traps: `!` that does not fail, and `[[ ]]` that does not fail on macOS's Bash 3.2.
- **Adopt git's pattern instead:** one sourced helper library, `tests/lib/test-lib.sh`, one test file per script, labels as the only case names, and no hand numbering.
- **Java analogy:** today's layout is like re-writing `assertEquals` inside every test class. The library is the shared test-utilities module every class imports.

## 5. Shared set-up

- A Shared Fixture reuses one set-up across many tests; Meszaros warns it "can lead to 'collisions' between tests possibly resulting in Erratic Tests". [VERIFIED as read by a sub-agent | xunitpatterns.com | 2003-2008]
- An Object Mother, a class that builds example objects for many tests, has a drawback: "many tests will depend on the exact data in the mothers". [VERIFIED as read by a sub-agent | martinfowler.com/bliki/ObjectMother.html | 2006-10-24]
- harness-kit uses fresh fixtures (a new temporary folder per case), which is the safer default. The shared part worth extracting is small and stable: printing results, describing a failed run, git settings that make test repositories independent of the person's own git configuration, and a bare repository to act as `origin`. Each file then keeps only the set-up that is specific to its script, which is Google's "specify only values they care about". [ASSUMPTION]

## 6. The harness-kit test files, measured

[VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured; the scripts each file tests are from the comments in tests/validate.sh and the label prefixes]

| Test file | Lines | Cases | Scripts it tests | Notes |
|---|---|---|---|---|
| `ship.test.sh` | 1,320 | 45 | ship.sh (23), session-start.mjs (8), land.sh (8), install-hooks.sh (2), approve-brief.sh (2), report-path.sh (1), check-reports.mjs (1) | seven units; case 23b sits before 22 |
| `replay-faults.test.sh` | 1,116 | 39 | replay-faults.sh and .mjs (30), land.sh (6), validate.sh `--only` | numbered 1 to 5, then 7; also P1–P6, N1, T2, T3, B1 |
| `eval-reviewer.test.sh` | 607 | 23 | eval-reviewer.sh | |
| `stop-gate.test.sh` | 577 | 26 | stop-gate.mjs | |
| `session-start.test.sh` | 536 | 15 | start-picture.mjs | |
| `review.test.sh` | 464 | 21 | review.sh, check-reviewed.mjs, reviewer-guard.mjs | three units |
| `time-limit.test.sh` | 454 | 16 | time-limit.mjs (12), check-limits.mjs (4) | two sections numbered 9 to 11 |
| `release.test.sh` | 446 | 16 | release.sh | |
| `upgrade.test.sh` | 377 | 13 | upgrade.sh | two cases numbered 12 |
| `harness-metrics.test.sh` | 364 | 12 | harness-metrics.mjs | |
| `check-commits.test.sh` | 354 | 16 | check-commits.mjs | |
| `guard-secrets.test.sh` | 278 | 5 | guard-secrets.mjs | |
| `predeploy-gate.test.sh` | 248 | 15 | predeploy-gate.mjs, deploy.sh | |
| `check-defects.test.sh` | 186 | 9 | check-defects.mjs | |
| `brief-guard.test.sh` | 158 | 4 | brief-guard.mjs, git-guard.mjs | case 6 sits before 5 |
| `check-names.test.sh` | 142 | 7 | check-names.mjs | |
| `git-guard.test.sh` | 134 | 3 | git-guard.mjs | |
| `background-guard.test.sh` | 115 | 4 | background-guard.mjs | |
| `ci-replay.test.sh` | 86 | 2 | the replay triggers in validate.yml | |
| `plan-mode-guard.test.sh` | 86 | 4 | plan-mode-guard.mjs | |

The case counts are the distinct literal labels my script found; a few labels built from variables may be missed.

## 7. A measured observation from running one file

I ran `tests/stop-gate.test.sh` three times in my Linux cloud container. 25 of its 26 cases passed every time; the case "a check that runs past its limit blocks the stop with TIMEOUT, and its process group is gone" failed every time, reporting two processes still running after the limit. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured] I did not investigate the cause, and harness-kit's own CI requires this case to pass, so treat it as a portability note, not a defect. It belongs to the same family as defect D7, a process-timing case that failed under load. File 04 returns to this. [ASSUMPTION]

## Negative results

- An evidence-based maximum length for a test file: NOT FOUND (not searched properly; the budget ran out).
- Measured speed overhead of bats per case: NOT FOUND. The only primary statement is the n+1 evaluation quoted above.
- A case study of moving a hand-written shell test suite to bats: NOT FOUND.
- A pass label and fail label that have drifted apart in harness-kit: none found among the 288 pairs.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against a shared library:** it creates one file every test depends on, so a mistake in it breaks all 20 files at once. The counter: every run shows it immediately, and git has run this way for many years.
- **Against splitting `ship.test.sh`:** its seven scripts are the person's own workflow and share heavy fixtures (a fake `gh`, a bare remote, a fake `claude`). Splitting may copy that set-up into seven files unless the shared parts move into the library first.
- **Against keeping bash for tests:** Google's 100-line rule, and the Bash 3.2 traps on macOS, both argue for writing new tests of the JavaScript scripts with `node:test`, which is built into Node.js and needs no new dependency. The cost is two test styles in one repository.
- **Against removing case numbers:** a reviewer can say "case 12" in conversation. The label does the same job, and it cannot collide.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- 3A – Arrange, Act, Assert. https://xp123.com/articles/3a-arrange-act-assert/. Bill Wake; 2011-04-26; primary; read: sub-agent extract.
- bats-core documentation: Gotchas. https://bats-core.readthedocs.io/en/stable/gotchas.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- bats-core documentation: Usage. https://bats-core.readthedocs.io/en/stable/usage.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- bats-core documentation: Writing tests. https://bats-core.readthedocs.io/en/stable/writing-tests.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- bats-core repository and changelog. https://github.com/bats-core/bats-core. bats-core; v1.14.0, 2026-07-21; primary; read: sub-agent extract.
- bats-core tutorial (test_helper and common setup). https://bats-core.readthedocs.io/en/stable/tutorial.html. bats-core; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Checkstyle: FileLength. https://checkstyle.org/checks/sizes/filelength.html. Checkstyle; 14.3.0 docs; accessed 2026-09-30; primary; read: sub-agent extract.
- ci-and-github research: 00-decision.md, and sections of 04, 05 and 07. harness-kit/research/ci-and-github (local, untracked). Cowork research job for the same person; 2026-09-30; secondary; read: full for 00-decision.md; extract for the others.
- Cram on PyPI. https://pypi.org/project/cram/. Brodie Rao; 0.7, 2016-02-24; primary; read: sub-agent extract.
- ESLint rule: max-lines. https://eslint.org/docs/latest/rules/max-lines. ESLint project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- git: t/README (the test suite's conventions). https://github.com/git/git/blob/master/t/README. Git project; undated; accessed 2026-09-30; primary; read: extract.
- GivenWhenThen. https://martinfowler.com/bliki/GivenWhenThen.html. Martin Fowler; 2013-08-21; primary; read: sub-agent extract.
- Google Shell Style Guide. https://google.github.io/styleguide/shellguide.html. Google; undated; accessed 2026-09-30; primary; read: extract.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- Jest configuration (testMatch). https://jestjs.io/docs/configuration. Jest project; Jest 30.5 docs; accessed 2026-09-30; primary; read: sub-agent extract.
- Maven Surefire: test goal (default includes). https://maven.apache.org/surefire/maven-surefire-plugin/test-mojo.html. Apache Maven; 3.6.0, published 2026-08-31; primary; read: sub-agent extract.
- Node.js v24 documentation: Test runner. https://raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md. Node.js project; v24.x branch; accessed 2026-09-30; primary; read: extract.
- Node.js: How to write a test for the Node.js project. https://github.com/nodejs/node/blob/main/doc/contributing/writing-tests.md. Node.js project; undated; accessed 2026-09-30; primary; read: extract.
- ObjectMother. https://martinfowler.com/bliki/ObjectMother.html. Martin Fowler; 2006-10-24; primary; read: sub-agent extract.
- On the Distribution of Test Smells in Open Source Android Applications (Peruma et al.). https://testsmells.org/assets/publications/CASCON2019_TechnicalPaper.pdf. CASCON 2019; 2019-11; primary; read: extract.
- scrut. https://github.com/facebookincubator/scrut. Meta (facebookincubator); v0.4.3, 2026-01-28; primary; read: sub-agent extract.
- ShellSpec repository, README and changelog. https://github.com/shellspec/shellspec. ShellSpec; latest release 0.28.1, 2021-01-11; primary; read: sub-agent extract.
- shUnit2 repository and release notes. https://github.com/kward/shunit2. Kate Ward; 2.1.8 (2020, inferred); primary; read: sub-agent extract.
- Software Engineering at Google, chapter 12: Unit Testing. https://abseil.io/resources/swe-book/html/ch12.html. Google / O'Reilly (Erik Kuefler); 2020; primary; read: extract.
- sonar-java: TooManyLinesOfCodeInFileCheck (rule S104). https://github.com/SonarSource/sonar-java. SonarSource; master branch; accessed 2026-09-30; primary; read: sub-agent extract.
- Test Desiderata. https://medium.com/@kentbeck_7670/test-desiderata-94150638a4b3. Kent Beck; 2019-10-18; primary; read: sub-agent extract.
- Test Obsessed by Method (Hora, Zaidman). https://arxiv.org/html/2602.00761v1. arXiv; 2026; primary; read: sub-agent extract.
- Testing on the Toilet: Don't Put Logic in Tests. https://testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html. Google Testing Blog (Erik Kuefler); 2014-07-31; primary; read: sub-agent extract.
- Testing on the Toilet: Keep Tests Focused. https://testing.googleblog.com/2018/06/testing-on-toilet-keep-tests-focused.html. Google Testing Blog (Ben Yu); 2018-06-11; primary; read: sub-agent extract.
- Testing on the Toilet: Test Behaviors, Not Methods. https://testing.googleblog.com/2014/04/testing-on-toilet-test-behaviors-not.html. Google Testing Blog (Erik Kuefler); 2014-04-14; primary; read: sub-agent extract.
- Testing on the Toilet: Tests Too DRY? Make Them DAMP!. https://testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make.html. Google Testing Blog (Derek Snyder, Erik Kuefler); 2019-12-03; primary; read: sub-agent extract.
- tsDetect: an open source test smells detection tool (Peruma et al.). https://testsmells.org/assets/publications/FSE2020_TechnicalPaper.pdf. ESEC/FSE 2020; 2020; primary; read: sub-agent extract.
- Vitest: include. https://vitest.dev/config/include. Vitest project; v5 docs; accessed 2026-09-30; primary; read: sub-agent extract.
- xUnit Test Patterns: test smells and fixture patterns (archived copy). https://xunitpatterns.com. Gerard Meszaros; 2003-2008; primary; read: sub-agent extract.
