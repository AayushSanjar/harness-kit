# 06 — Free components: tools, GitHub Actions, and Claude Code skills, agents, hooks and plugins (research question F)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Component:** anything ready-made you could adopt instead of writing it: a command-line tool, a GitHub Action (a packaged step for GitHub's CI), or a Claude Code plugin, skill, agent, hook or built-in command.
- **Licence:** the terms under which you may use and copy a component. MIT, ISC, BSD and Apache-2.0 are permissive. GPL requires that copies and changes you distribute stay under GPL; AGPL extends that to software offered over a network.
- **Latest release:** the newest published version, with the date as shown on the release page, a package registry or a changelog.
- **Stars:** the count of GitHub users who bookmarked a repository. **Installs:** the count Anthropic's plugin directory shows. Both measure popularity, not quality.
- **New dependency:** a component the repository would need to install. The gadget's own rules require proposing and justifying every new dependency first.
- **Verdict words:** *use now* (worth adopting in the first steps), *use later* (when a named condition arises), *pattern only* (copy the idea, not the tool), *skip*.

## How this file is based on evidence

- **Sources.** This file cites 63 sources, 63 of them primary.
- **How they were chosen.** Every component named in files 01 to 05, plus the ones the question named. Two research sub-agents checked each one's own release page, registry page or changelog: one read 138 pages (111 primary) for the documentation and structure tools, the other 112 pages (97 primary) for the test and agent tools. They used third-party aggregators only to find a year that GitHub did not display.
- **How far to trust the numbers.**
  - Stars are as the repository page displayed them through the fetch tool, which can show a cached view: the harness-kit page itself showed 1 commit on the day a clone showed 34. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
  - GitHub's release pages often show a date without a year; the year then comes from a registry or changelog, or is marked as inferred.
  - Several npm pages showed stale versions and were not used.
- **Overlap with the ci-and-github research.** Tools for CI speed and merging (xargs, GNU parallel, merge queues, actionlint and others) are in `research/ci-and-github/04-reusable-components.md` and are not repeated here. Where both files rate a tool, the verdicts agree.
- **Labels** are as in file 01. Each table row names its source; a row's facts were read by a sub-agent unless the row says otherwise. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS

1. **The components most worth adopting first cost nothing and add no dependency:** `/doctor prompt-audit`, `claude plugin details`, and a 60-line generator of your own. The well-known documentation tools (link checkers, prose linters) have little to find in harness-kit (file 03, CONTRADICTIONS 2 to 4). [ASSUMPTION, built on the tables below and on my measurements] [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
2. **The best-known GitHub Action for markdown link checking is archived** (20 April 2026). [VERIFIED | github.com/gaurav-nelson/github-action-markdown-link-check | archived 2026-04-20 | extract]
3. **ShellCheck directives already sit in harness-kit's scripts,** such as `# shellcheck source=limit-lib.sh`, but neither `tests/validate.sh` nor CI runs ShellCheck. This answers a question the ci-and-github research left NOT FOUND. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

## A. Already available: no install, no new dependency

| Component | What it does | What it replaces or adds | Licence and release | Catch | Verdict | Source |
|---|---|---|---|---|---|---|
| `/doctor prompt-audit` | Audits CLAUDE.md, skills, agents, commands and rules for references to files or commands that do not exist, contradictions and outdated instructions; report-first | Adds the first AI gardening pass (file 05), both repositories | Part of Claude Code, v2.1.283 or later | Model judgement; audits instruction files only, not scripts or READMEs | **Use now** | [VERIFIED \| code.claude.com/docs/en/memory \| accessed 2026-09-30 \| full] |
| `claude plugin details <name>` | Prints a plugin's components (skills, agents, hooks) without starting a session | Replaces the hand-written list of harness-kit hooks in the gadget's CLAUDE.md with a pointer | Part of Claude Code | Shows what is installed, which is what the gadget runs | **Use now** | [VERIFIED as cited in harness-kit's research/initial-harness/02, section 15, which I read in full \| code.claude.com/docs/en/plugins/security \| accessed 2026-09-26] |
| `claude plugin validate --strict` | Checks manifests, front matter and hook files | Already used by `tests/validate.sh` | Part of Claude Code | Does not open plugin files when run on a marketplace, which harness-kit already handles | **Keep** | [VERIFIED \| github.com/AayushSanjar/harness-kit \| commit e275280, 2026-09-30 \| full read of tests/validate.sh] |
| Your own generator with a check mode (`tools/gen-docs.mjs`) | Writes README tables from `hooks.json` and `time-limit.mjs`; `--check` fails when they differ | Removes hand-maintained hook and limit lists | Your code; about 60 lines of Node, prototyped in file 07 | Code to maintain; markers in the README | **Use now** | [VERIFIED \| github.com/AayushSanjar/harness-kit \| commit e275280, 2026-09-30 \| measured in a scratch copy] |
| Node.js built-in test runner (`node:test`) | Test runner with `describe`, `it`, set-up hooks, snapshots and parallel files | An option for new tests of pure JavaScript logic, with no dependency | Ships with Node; "Stability: 2 - Stable" | No per-test retry; coverage experimental; a second test style next to the bash files | **Use later**, for new pure-logic tests only | [VERIFIED \| raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md \| v24.x branch; accessed 2026-09-30 \| extract] |

## B. Anthropic's Claude Code plugins

| Component | What it does | What it replaces or adds | Licence and release | Installs | Catch | Verdict | Source |
|---|---|---|---|---|---|---|---|
| pr-review-toolkit: `comment-analyzer` agent | Checks every claim in a comment against the code; flags restating, outdated and misleading comments; advisory only | Adds the comment half of the gardening pass | README says MIT, LICENSE file says Apache 2.0; no version in plugin.json | 114,856, "Anthropic Verified" | Model judgement; "Don't over-use: Focus on changed code" | **Use now**, in stage 1 of file 05 | [VERIFIED \| github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/comment-analyzer.md \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| claude.com/plugins \| observed 2026-09-30] |
| pr-review-toolkit: `pr-test-analyzer` agent | Reviews test coverage by behaviour and rates gaps 1 to 10 | An occasional second opinion on test gaps | as above | as above | Model judgement; your fault replay is a stronger signal | **Use later**, when adding tests to a script with no planted fault | [VERIFIED as read by a sub-agent \| github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/pr-test-analyzer.md \| accessed 2026-09-30] |
| claude-md-management: `claude-md-improver` skill and `/revise-claude-md` | Scores each CLAUDE.md out of 100, reports first, asks before editing | Overlaps `/doctor prompt-audit` | LICENSE file Apache 2.0; plugin version 1.0.0 | 287,247 | Scores are model judgement | **Use later**, only if the built-in audit falls short | [VERIFIED \| github.com/anthropics/claude-plugins-official/blob/main/plugins/claude-md-management/skills/claude-md-improver/SKILL.md \| accessed 2026-09-30 \| extract] |

## C. Documentation and link tools

| Component | What it does | Licence | Latest release | Stars | Catch | Verdict | Source |
|---|---|---|---|---|---|---|---|
| lychee and lychee-action | Link checker for markdown, HTML and text, offline or online | Apache-2.0 or MIT | lychee 0.24.2, 1 May 2026; action v2.9.0, 9 July 2026 | 3.7k; 498 | Rust binary; online checks get rate-limited; does not see addresses written without `https://` | **Use later**, as an occasional, non-blocking check of `sources.csv` | [VERIFIED \| raw.githubusercontent.com/lycheeverse/lychee/master/README.md \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| github.com/lycheeverse/lychee \| lychee-v0.24.2, 2026-05-01] [VERIFIED as read by a sub-agent \| github.com/lycheeverse/lychee-action \| v2.9.0, 2026-07-09] |
| remark-validate-links with remark-cli | Offline check of local links and headings | MIT | 13.1.0, 21 February 2025; remark-cli 12.0.1, 30 April 2024 | 125; 9.0k | New dependency; harness-kit's markdown has no links for it to check | **Skip** | [VERIFIED \| raw.githubusercontent.com/remarkjs/remark-validate-links/main/readme.md \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| github.com/remarkjs/remark-validate-links \| 13.1.0, 2025-02-21] [VERIFIED as read by a sub-agent \| github.com/remarkjs/remark \| remark-cli 12.0.1, 2024-04-30] |
| markdown-link-check, and the tcort fork of its Action | Online link check of markdown | ISC; the fork is MIT | 3.15.0, 28 July 2026; fork v1.1.3 (date not found) | 707; 25 | The original Action is archived | **Skip** | [VERIFIED as read by a sub-agent \| github.com/tcort/markdown-link-check \| v3.15.0, 2026-07-28] [VERIFIED as read by a sub-agent \| github.com/tcort/github-action-markdown-link-check \| v1.1.3 (date not found); accessed 2026-09-30] |
| linkinator | Crawls sites or files and checks links and anchors | MIT | 8.1.0, 27 August 2026 | 1.3k | Needs Node 22 or later | **Skip** | [VERIFIED as read by a sub-agent \| github.com/JustinBeckwith/linkinator \| 8.1.0, 2026-08-27] |
| markdownlint-cli2 and its Action | Markdown layout rules | MIT | 0.23.3, 20 September 2026 (from secondary sources); Action v24.2.0, 2 August 2026 (year inferred) | 912; 187 | Default rules gave 3,066 findings on harness-kit, 83% about line length | **Use later**, only with line length switched off | [VERIFIED as read by a sub-agent \| github.com/DavidAnson/markdownlint-cli2 \| 0.23.3, 2026-09-20 (secondary sources)] [VERIFIED as read by a sub-agent \| github.com/DavidAnson/markdownlint-cli2-action \| v24.2.0, 2026-08-02 (year inferred)] |
| Vale and vale-action | Prose style rules with word lists | MIT | v3.23.0, 25 September (year not shown) | 6.2k | Needs a configuration and downloaded styles; the Action passes whatever Vale reports unless told otherwise | **Skip**: wording is not the problem | [VERIFIED as read by a sub-agent \| github.com/vale-cli/vale \| v3.23.0, 25 Sep (year not shown); accessed 2026-09-30] |
| Cog | Generates text inside files from Python snippets; `--check` | MIT | 3.6.0, 21 September 2025 | 406 | Python; runs code embedded in documents | **Pattern only**: your Node generator does the same without Python | [VERIFIED \| cog.readthedocs.io/en/latest/running.html \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| pypi.org/project/cogapp/ \| 3.6.0, 2025-09-21] |
| embedme | Copies source files into markdown code blocks; `--verify` | MIT | v1.22.1, 7 September 2022 | 238 | No release in four years | **Skip** | [VERIFIED as read by a sub-agent \| www.npmjs.com/package/embedme \| v1.22.1, 2022-09-07 (GitHub)] |
| markdown-magic | Fills comment blocks from code or files | MIT | 4.11.0, 29 June 2026 | 864 | No check flag found | **Skip** | [VERIFIED as read by a sub-agent \| github.com/DavidWells/markdown-magic \| 4.11.0, 2026-06-29] |
| doctoc | Writes a table of contents; `--dryrun` exits 1 when stale | MIT | v2.5.0, 12 June 2026 (secondary source) | 4.5k | Only tables of contents | **Skip** | [VERIFIED as read by a sub-agent \| github.com/thlorenz/doctoc \| v2.5.0, 2026-06-12 (secondary)] |
| txm, clitest, scrut, cram | Run the command examples written in documents and compare output | ISC; MIT; MIT; GPL-2.0 | v8.2.0, 3 July 2023; 0.5.0 (year not found); v0.4.3, 28 January 2026; 0.7, 24 February 2016 | 47; 175; 81; 232 | harness-kit's README has no runnable examples today; cram is unmaintained | **Use later**, if the README gains command examples (clitest is one shell file) | [VERIFIED as read by a sub-agent \| github.com/anko/txm \| v8.2.0, 2023-07-03] [VERIFIED as read by a sub-agent \| github.com/aureliojargas/clitest \| 0.5.0 (year not shown); accessed 2026-09-30] [VERIFIED as read by a sub-agent \| github.com/facebookincubator/scrut \| v0.4.3, 2026-01-28] [VERIFIED as read by a sub-agent \| pypi.org/project/cram/ \| 0.7, 2016-02-24] |
| Doc Detective | Runs documentation as tests, including shell commands and browser steps | AGPL-3.0 | v4.38.1, 13 August 2026 | 133 | Downloads browsers and drivers; tested on Node 20 and 22 only | **Skip** | [VERIFIED as read by a sub-agent \| github.com/doc-detective/doc-detective \| v4.38.1, 2026-08-13] |

## D. Test tools

| Component | What it does | Licence | Latest release | Stars | Catch | Verdict | Source |
|---|---|---|---|---|---|---|---|
| bats-core, with bats-support, bats-assert, bats-file | Bash test framework with per-case processes, set-up levels, tags, timeouts, retries, TAP and JUnit output | MIT (bats-core); helpers CC0 or 0BSD | v1.14.0, 21 July 2026 | 6.3k | A rewrite of 295 cases and 137 fault entries; `!` and `[[ ]]` traps on macOS bash 3.2; parallel runs need GNU parallel or rush | **Skip** (the ci-and-github research also skips it) | [VERIFIED \| bats-core.readthedocs.io/en/stable/gotchas.html \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| github.com/bats-core/bats-core \| v1.14.0, 2026-07-21] [VERIFIED as read by a sub-agent \| github.com/bats-core/bats-assert \| v2.2.4 (before 2026-02-08)] |
| git's `test-lib.sh` | One shared library that every test script sources | GPL-2.0, as part of git | not applicable | not applicable | Copying its code would bring GPL terms; copy the idea | **Pattern only** | [VERIFIED \| github.com/git/git/blob/master/t/README \| accessed 2026-09-30 \| extract] |
| ShellSpec | Behaviour-driven tests for all POSIX shells, with mocks and coverage | MIT | 0.28.1, 11 January 2021 | 1.4k | No release in over five years | **Skip** | [VERIFIED as read by a sub-agent \| github.com/shellspec/shellspec \| latest release 0.28.1, 2021-01-11] |
| shUnit2 | JUnit-style tests for Bourne shells | Apache-2.0 | 2.1.8 (2020, inferred) | 1.7k | Does not work with `set -e` | **Skip** | [VERIFIED as read by a sub-agent \| github.com/kward/shunit2 \| 2.1.8 (2020, inferred)] |
| ShellCheck | Finds bugs in shell scripts | GPL-3.0 (as a separate tool, running it imposes nothing on your code) | v0.11.0, 4 August 2025 | 40.0k | Not a drift tool; the CI runner image has an older version | **Use later**, as a check in `validate.sh`, as ci-and-github also suggests | [VERIFIED as read by a sub-agent \| github.com/koalaman/shellcheck \| v0.11.0, 2025-08-04] |
| shfmt | Formats shell scripts | BSD-3-Clause | v3.13.1 (2026) | 9.0k | A one-off reformat of every script would touch every line | **Skip** | [VERIFIED as read by a sub-agent \| github.com/mvdan/sh \| v3.13.1 (2026)] |
| jscpd | Finds copied blocks in about 220 languages, including bash | MIT | v5.3.3, 28 September 2026 | 6.2k | Found only 2.58% copied lines in harness-kit's tests | **Use later**, as an occasional measurement, not a gate | [VERIFIED as read by a sub-agent \| github.com/kucherenko/jscpd \| v5.3.3, 2026-09-28] [VERIFIED \| github.com/AayushSanjar/harness-kit \| commit e275280, 2026-09-30 \| measured with jscpd 5.3.3] |
| kcov, bashcov | Coverage of bash scripts | GPL-2.0; MIT | v43, 23 July 2024; 4.0.0, 25 August 2026 | 823; 173 | macOS bash 3.2 problems; bashcov needs bash 4.3 and Ruby 3.2 | **Skip** | [VERIFIED as read by a sub-agent \| raw.githubusercontent.com/SimonKagstrom/kcov/master/doc/kcov.1 \| v43, 2024-07-23] [VERIFIED as read by a sub-agent \| rubygems.org/gems/bashcov \| 4.0.0, 2026-08-25] |
| StrykerJS | Mutation testing for JavaScript, with per-test results | Apache-2.0 | 10.0.0, 14 August 2026 (year from the changelog) | about 3k | Cannot mutate shell; no runner for `node:test`; needs Node 22 or later; a new dependency for the gadget | **Use later**, gadget only, if its test runner is supported | [VERIFIED \| stryker-mutator.io/docs/stryker-js/configuration/ \| accessed 2026-09-30 \| extract] [VERIFIED as read by a sub-agent \| github.com/stryker-mutator/stryker-js \| v10.0.0, 2026-08-14 (year from changelog)] |
| c8 | Coverage reports from Node's built-in coverage | ISC | v11.0.0 (2026) | 2.1k | Coverage says what ran, not what was checked | **Skip** | [VERIFIED as read by a sub-agent \| github.com/bcoe/c8 \| v11.0.0 (2026)] |

## E. Structure and decision records

| Component | What it does | Licence | Latest release | Stars | Catch | Verdict | Source |
|---|---|---|---|---|---|---|---|
| MADR | Templates for decision records, with a status field including "superseded by" | MIT or CC0-1.0 | 4.0.0, 17 September 2024 | 2.4k | Templates only | **Pattern only**: use its status words in each `00-decision.md` | [VERIFIED \| adr.github.io/madr \| MADR 4.0.0, 2024-09-17 \| extract] [VERIFIED as read by a sub-agent \| github.com/adr/madr \| 4.0.0, 2024-09-17] |
| adr-tools | Shell commands to create and supersede decision records | GPL-3.0 for the tool, CC BY 4.0 for what it generates | 3.0.0 (year not found, no later than March 2021) | 5.7k | Few commits since its last release | **Skip** | [VERIFIED as read by a sub-agent \| github.com/npryce/adr-tools \| release 3.0.0 (year not shown); accessed 2026-09-30] |
| log4brains | Writes, previews and publishes decision records as a web site | Apache-2.0 | v1.1.0, 17 December 2024 | 1.5k | Released "after a very long pause" | **Skip** | [VERIFIED as read by a sub-agent \| github.com/thomvaill/log4brains \| v1.1.0, 2024-12-17] |
| knip | Finds unused files, dependencies and exports in JavaScript projects | ISC | 6.38.0, 23 September 2026 | 12.3k | Needs a `package.json` and the right plugins; harness-kit has no `package.json` | **Use later**, gadget only, as a proposed dependency | [VERIFIED as read by a sub-agent \| github.com/webpro-nl/knip \| knip@6.38.0, 2026-09-23] |
| dependency-cruiser | Checks import rules between folders, such as "the front end never imports server code" | MIT | v18.4.0, 20 September 2026 | 7.2k | Version 18 needs Node 22 or 24; a rules file to maintain | **Use later**, gadget only, if its own boundary check grows | [VERIFIED as read by a sub-agent \| github.com/sverweij/dependency-cruiser \| v18.4.0, 2026-09-20] |
| `forge lint` (Atlassian Forge command-line tool) | Checks that the manifest declares the scopes and outgoing domains the code uses; runs before `forge deploy` | Atlassian's licence | Forge CLI 14.0.0, 14 September 2026 (secondary source) | not applicable | `forge deploy --no-verify` skips it | **Keep**, gadget | [VERIFIED as read by a sub-agent \| developer.atlassian.com/platform/forge/cli-reference/lint/ \| accessed 2026-09-30] |

## F. Agents that garden on a schedule

| Component | What it does | Licence | Latest release | Stars | Catch | Verdict | Source |
|---|---|---|---|---|---|---|---|
| Claude Code GitHub Action (anthropics/claude-code-action) | Runs Claude Code in GitHub Actions on an event or a schedule | MIT | v1.0.236, 28 September (2026, inferred) | 8.9k | Actions minutes (free for public repositories); an API key or subscription token in CI; pushes branches, opens no pull request by default | **Use later**, harness-kit only (stage 3 of file 05) | [VERIFIED \| code.claude.com/docs/en/github-actions \| accessed 2026-09-30 \| full] [VERIFIED as read by a sub-agent \| github.com/anthropics/claude-code-action \| v1.0.236 on 28 Sep (2026, inferred)] |
| GitHub Agentic Workflows (gh-aw) and the agentics samples | Agent workflows written in markdown, with safe outputs, drafts and limits | MIT | v0.89.21, 23 September (2026, inferred); agentics has no releases | 5.2k; 850 | Pre-1.0; four critical advisories in August 2026; Claude engine needs an API key | **Skip** for now | [VERIFIED \| github.com/github/gh-aw/security/advisories \| advisories published 2026-08-06 to 2026-08-29 \| extract] [VERIFIED as read by a sub-agent \| github.com/github/gh-aw \| v0.89.21, 23 Sep (2026, inferred)] [VERIFIED as read by a sub-agent \| github.com/githubnext/agentics \| no releases; observed 2026-09-30] |
| Community documentation agents (VoltAgent documentation-engineer, wshobson docs-architect, davila7 update-docs) | Prompt files that write or update documentation | MIT | no releases | 22.9k; 40.0k; 30.8k | No check against the code; "We do not audit or guarantee the security or correctness of any subagent" | **Skip** | [VERIFIED as read by a sub-agent \| github.com/VoltAgent/awesome-claude-code-subagents \| observed 2026-09-30] [VERIFIED as read by a sub-agent \| github.com/wshobson/agents \| observed 2026-09-30] [VERIFIED as read by a sub-agent \| github.com/davila7/claude-code-templates \| observed 2026-09-30] |
| Swimm, DeepDocs, Mintlify | Commercial tools that flag or update documentation when code changes | proprietary | not applicable | not applicable | Paid or unpublished prices; no source code | **Skip** | [VERIFIED as read by a sub-agent \| swimm.io/pricing \| observed 2026-09-30] [VERIFIED as read by a sub-agent \| deepdocs.dev \| observed 2026-09-30] [VERIFIED as read by a sub-agent \| www.mintlify.com/docs \| observed 2026-09-30] |

## Notes

1. **Why so few "use now" verdicts.** The measured drift in harness-kit sits in hand-maintained lists, numbers and indexes (file 03). No off-the-shelf tool knows that `hooks.json` and a README table describe the same thing; a short script of your own does. [ASSUMPTION, built on my measurements]
2. **Licences.** Running a GPL tool (ShellCheck, kcov) imposes nothing on your code. Copying GPL code into harness-kit, for example git's `test-lib.sh`, would. harness-kit declares no licence of its own in the files I read, which matters to anyone who wants to reuse it. [ASSUMPTION about licence effects; the missing licence file is VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
3. **Node versions.** linkinator 8, dependency-cruiser 18 and StrykerJS 10 need Node 22 or later, and Doc Detective is tested only on Node 20 and 22. This fits your decision to move harness-kit to Node 24; check each tool on 24 before adopting it. [VERIFIED as read by a sub-agent | github.com/sverweij/dependency-cruiser | v18.4.0, 2026-09-20] [VERIFIED as read by a sub-agent | github.com/doc-detective/doc-detective | v4.38.1, 2026-08-13]
4. **Popularity is not evidence of fit.** Several of the most-starred items here (community agent collections) are unaudited prompt files, by their own description. [VERIFIED as read by a sub-agent | github.com/VoltAgent/awesome-claude-code-subagents | observed 2026-09-30]

## Negative results

- A tool that checks prose documents against a JSON configuration such as `hooks.json`: NOT FOUND. The pattern (generate, then check) exists; the tool does not.
- The release dates of the tcort link-check Action, clitest 0.5.0, adr-tools 3.0.0 and vale-action v3.0.0: NOT FOUND (pages show no year).
- A free tier for Swimm: NOT FOUND.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against writing your own generator:** it is one more script to test and maintain, in a repository that is already large; a mature tool such as Cog has been tested by many users. The counter: Cog brings Python and executes code embedded in documents.
- **Against skipping link checks:** 544 cited addresses will decay over months; an occasional online run costs little if it never blocks.
- **Against ShellCheck "later":** it catches real bugs cheaply, and the scripts already carry its directives, so someone already relies on it by hand. Adding it is a small, separate step.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- adr-tools. https://github.com/npryce/adr-tools. Nat Pryce; release 3.0.0 (year not shown); accessed 2026-09-30; primary; read: sub-agent extract.
- agentics sample workflows. https://github.com/githubnext/agentics. GitHub Next; no releases; observed 2026-09-30; primary; read: sub-agent extract.
- Anthropic plugin directory (install counts). https://claude.com/plugins. Anthropic; observed 2026-09-30; primary; read: sub-agent extract.
- awesome-claude-code-subagents (documentation-engineer). https://github.com/VoltAgent/awesome-claude-code-subagents. VoltAgent; observed 2026-09-30; primary; read: sub-agent extract.
- bashcov on RubyGems. https://rubygems.org/gems/bashcov. infertux; 4.0.0, 2026-08-25; primary; read: sub-agent extract.
- bats-assert. https://github.com/bats-core/bats-assert. bats-core; v2.2.4 (before 2026-02-08); primary; read: sub-agent extract.
- bats-core documentation: Gotchas. https://bats-core.readthedocs.io/en/stable/gotchas.html. bats-core; undated; accessed 2026-09-30; primary; read: extract.
- bats-core repository and changelog. https://github.com/bats-core/bats-core. bats-core; v1.14.0, 2026-07-21; primary; read: sub-agent extract.
- c8. https://github.com/bcoe/c8. Ben Coe; v11.0.0 (2026); primary; read: sub-agent extract.
- Claude Code GitHub Actions. https://code.claude.com/docs/en/github-actions. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Claude Code: plugin security (claude plugin details). https://code.claude.com/docs/en/plugins/security. Anthropic; accessed 2026-09-26 by the earlier research; primary; read: cited in harness-kit research/initial-harness/02 section 15, which I read in full; page not re-read.
- claude-code-action repository and releases. https://github.com/anthropics/claude-code-action. Anthropic; v1.0.236 on 28 Sep (2026, inferred); primary; read: sub-agent extract.
- claude-code-templates (update-docs command). https://github.com/davila7/claude-code-templates. Daniel Avila; observed 2026-09-30; primary; read: sub-agent extract.
- claude-md-management: claude-md-improver skill. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/claude-md-management/skills/claude-md-improver/SKILL.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- clitest. https://github.com/aureliojargas/clitest. Aurelio Jargas; 0.5.0 (year not shown); accessed 2026-09-30; primary; read: sub-agent extract.
- Cog documentation: Running Cog. https://cog.readthedocs.io/en/latest/running.html. Ned Batchelder; undated; accessed 2026-09-30; primary; read: extract.
- cogapp (Cog) on PyPI. https://pypi.org/project/cogapp/. Ned Batchelder; 3.6.0, 2025-09-21; primary; read: sub-agent extract.
- Cram on PyPI. https://pypi.org/project/cram/. Brodie Rao; 0.7, 2016-02-24; primary; read: sub-agent extract.
- DeepDocs. https://deepdocs.dev. DeepDocs; observed 2026-09-30; primary; read: sub-agent extract.
- dependency-cruiser. https://github.com/sverweij/dependency-cruiser. Sander Verweij; v18.4.0, 2026-09-20; primary; read: sub-agent extract.
- Doc Detective. https://github.com/doc-detective/doc-detective. Doc Detective project; v4.38.1, 2026-08-13; primary; read: sub-agent extract.
- doctoc repository. https://github.com/thlorenz/doctoc. Thorsten Lorenz; v2.5.0, 2026-06-12 (secondary); primary; read: sub-agent extract.
- embedme. https://www.npmjs.com/package/embedme. Zak Henry; v1.22.1, 2022-09-07 (GitHub); primary; read: sub-agent extract.
- Forge CLI: forge lint. https://developer.atlassian.com/platform/forge/cli-reference/lint/. Atlassian; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- gh-aw repository. https://github.com/github/gh-aw. GitHub; v0.89.21, 23 Sep (2026, inferred); primary; read: sub-agent extract.
- gh-aw security advisories. https://github.com/github/gh-aw/security/advisories. GitHub; advisories published 2026-08-06 to 2026-08-29; primary; read: extract.
- git: t/README (the test suite's conventions). https://github.com/git/git/blob/master/t/README. Git project; undated; accessed 2026-09-30; primary; read: extract.
- github-action-markdown-link-check (archived). https://github.com/gaurav-nelson/github-action-markdown-link-check. Gaurav Nelson; archived 2026-04-20; primary; read: extract.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- How Claude remembers your project (CLAUDE.md, /doctor prompt-audit). https://code.claude.com/docs/en/memory. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- jscpd repository and FORMATS.md. https://github.com/kucherenko/jscpd. Andrey Kucherenko; v5.3.3, 2026-09-28; primary; read: sub-agent extract.
- kcov manual page and releases. https://raw.githubusercontent.com/SimonKagstrom/kcov/master/doc/kcov.1. Simon Kagstrom; v43, 2024-07-23; primary; read: sub-agent extract.
- knip. https://github.com/webpro-nl/knip. Lars Kappert (webpro-nl); knip@6.38.0, 2026-09-23; primary; read: sub-agent extract.
- linkinator. https://github.com/JustinBeckwith/linkinator. Justin Beckwith; 8.1.0, 2026-08-27; primary; read: sub-agent extract.
- log4brains. https://github.com/thomvaill/log4brains. Thomas Vaillant; v1.1.0, 2024-12-17; primary; read: sub-agent extract.
- lychee README (command-line options). https://raw.githubusercontent.com/lycheeverse/lychee/master/README.md. lycheeverse; undated; accessed 2026-09-30; primary; read: extract.
- lychee repository and releases. https://github.com/lycheeverse/lychee. lycheeverse; lychee-v0.24.2, 2026-05-01; primary; read: sub-agent extract.
- lychee-action. https://github.com/lycheeverse/lychee-action. lycheeverse; v2.9.0, 2026-07-09; primary; read: sub-agent extract.
- MADR repository. https://github.com/adr/madr. adr.github.io; 4.0.0, 2024-09-17; primary; read: sub-agent extract.
- MADR: Markdown Architectural Decision Records. https://adr.github.io/madr. adr.github.io (MADR project); MADR 4.0.0, 2024-09-17; primary; read: extract.
- markdown-link-check. https://github.com/tcort/markdown-link-check. Thomas Cort; v3.15.0, 2026-07-28; primary; read: sub-agent extract.
- markdown-magic. https://github.com/DavidWells/markdown-magic. David Wells; 4.11.0, 2026-06-29; primary; read: sub-agent extract.
- markdownlint-cli2. https://github.com/DavidAnson/markdownlint-cli2. David Anson; 0.23.3, 2026-09-20 (secondary sources); primary; read: sub-agent extract.
- markdownlint-cli2-action. https://github.com/DavidAnson/markdownlint-cli2-action. David Anson; v24.2.0, 2026-08-02 (year inferred); primary; read: sub-agent extract.
- Mintlify automations (plan requirement). https://www.mintlify.com/docs. Mintlify; observed 2026-09-30; primary; read: sub-agent extract.
- Node.js v24 documentation: Test runner. https://raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md. Node.js project; v24.x branch; accessed 2026-09-30; primary; read: extract.
- pr-review-toolkit: comment-analyzer agent. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/comment-analyzer.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- pr-review-toolkit: pr-test-analyzer agent. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/pr-test-analyzer.md. Anthropic; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- remark (remark-cli). https://github.com/remarkjs/remark. remarkjs; remark-cli 12.0.1, 2024-04-30; primary; read: sub-agent extract.
- remark-validate-links readme. https://raw.githubusercontent.com/remarkjs/remark-validate-links/main/readme.md. remarkjs; undated; accessed 2026-09-30; primary; read: extract.
- remark-validate-links repository. https://github.com/remarkjs/remark-validate-links. remarkjs; 13.1.0, 2025-02-21; primary; read: sub-agent extract.
- scrut. https://github.com/facebookincubator/scrut. Meta (facebookincubator); v0.4.3, 2026-01-28; primary; read: sub-agent extract.
- ShellCheck. https://github.com/koalaman/shellcheck. Vidar Holen (koalaman); v0.11.0, 2025-08-04; primary; read: sub-agent extract.
- ShellSpec repository, README and changelog. https://github.com/shellspec/shellspec. ShellSpec; latest release 0.28.1, 2021-01-11; primary; read: sub-agent extract.
- shfmt (mvdan/sh). https://github.com/mvdan/sh. Daniel Martí; v3.13.1 (2026); primary; read: sub-agent extract.
- shUnit2 repository and release notes. https://github.com/kward/shunit2. Kate Ward; 2.1.8 (2020, inferred); primary; read: sub-agent extract.
- StrykerJS configuration. https://stryker-mutator.io/docs/stryker-js/configuration/. Stryker Mutator; undated; accessed 2026-09-30; primary; read: extract.
- StrykerJS repository and v10.0.0 release. https://github.com/stryker-mutator/stryker-js. Stryker Mutator; v10.0.0, 2026-08-14 (year from changelog); primary; read: sub-agent extract.
- Swimm pricing and home page. https://swimm.io/pricing. Swimm; observed 2026-09-30; primary; read: sub-agent extract.
- tcort/github-action-markdown-link-check (maintained fork). https://github.com/tcort/github-action-markdown-link-check. Thomas Cort; v1.1.3 (date not found); accessed 2026-09-30; primary; read: sub-agent extract.
- txm. https://github.com/anko/txm. anko; v8.2.0, 2023-07-03; primary; read: sub-agent extract.
- Vale. https://github.com/vale-cli/vale. vale-cli; v3.23.0, 25 Sep (year not shown); accessed 2026-09-30; primary; read: sub-agent extract.
- wshobson/agents (docs-architect). https://github.com/wshobson/agents. Seth Hobson; observed 2026-09-30; primary; read: sub-agent extract.
