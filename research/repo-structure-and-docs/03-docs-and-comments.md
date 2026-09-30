# 03 — Keeping documentation and code comments true (research question C)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Drift:** the gap that opens between what a document or comment says and what the code does, as the code changes and the text does not.
- **Living document** and **dated record:** as in file 01. A living document must match today's code; a dated record describes one date and is replaced, not rewritten.
- **Comment:** text inside a code file that the computer ignores. A **header comment** sits at the top of a file or function and says what it is for. A **"why" comment** explains a reason the code cannot show; a **"what" comment** repeats what the code already says.
- **Generated section:** part of a document written by a program from the code, between two marker lines such as `<!-- BEGIN GENERATED: hooks -->` and `<!-- END GENERATED: hooks -->`.
- **Check mode:** a way of running a generator that changes nothing and fails when the document differs from what the code says, so a test run can catch drift.
- **Link checker:** a tool that follows the links in documents and reports broken ones. An **offline** check looks only at files in the repository; an **online** check also calls web sites.
- **Anchor (or fragment):** the part of a link after `#` that points at a heading inside a page.
- **Prose linter:** a tool that checks the wording and layout of documents, such as markdownlint or Vale.
- **Docs as code:** keeping documentation in the repository, reviewing it like code, and testing it automatically.
- **Freshness metadata:** a line in a document that records who owns it and when it was last checked.

## How this file is based on evidence

- **Sources.** This file cites 47 sources, 47 of them primary.
- **How they were chosen.** A research sub-agent read 89 pages (84 primary) on the items named in the question: style guides, studies of comment drift, generators with check modes, link checkers, and docs-as-code practice at GitLab, Google and Microsoft. The session's search budget ran out after its 47th search, so parts of questions 5 and 6 were fetched from known addresses rather than searched.
- **What I checked myself.** I re-read the Google shell guide, Google's documentation and code-review guides, the Stack Overflow article, the Wen and Fluri studies, the Cog, lychee and remark-validate-links documentation, the archived link-check action, npm's documentation test, ESLint's rule-file check and Kubernetes' documentation check.
- **What I measured.** On a clone of harness-kit at commit `e275280` I: compared every number in `README.md` with the code; listed every path in backticks in the markdown files and tested whether it exists; ran remark-validate-links 13.1.0 and markdownlint-cli2 0.23.3 with their default settings; counted comment lines; and built and ran a small generator with a check mode in a scratch copy (the worked example in file 07).
- **Labels** are as in file 01. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS

1. **The drift is in lists, numbers and indexes, not in the prose.** Your brief treats documents and comments as going out of date generally. Measured on harness-kit:
   - Every number in `README.md` matches the code: the time limits (540, 900, 900, 60, 300 and 120 seconds), the 10-second grace period, the four budgets, three gh tries 10 seconds apart, the 7-day nudge, the 5-second read, the 24-hour pass record, the Monday 03:00 UTC replay and the 8 shards. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - All 12 `.harness/<file>` names mentioned in the README, the skills and `hooks.json` are files some script reads. Of the 22 script names mentioned there, 20 are plugin scripts, one is `tests/validate.sh`, and the last, `approve-protected.sh`, is a consumer project's script that git-guard deliberately refuses. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - What did drift: the hook list in the gadget's `CLAUDE.md`, which names 6 hooks when harness-kit registers 9 (file 07 has the details); the research index (file 01); the hand-written case numbers and section letters in the tests (file 02); and the research proposal in file 04 of the first research. [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context] [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - So the fix is narrower than "keep all documents true": stop hand-maintaining lists, numbers and indexes. Generate them, check them, or delete them. [ASSUMPTION, built on the measurements above]
2. **Link checkers would find almost nothing to check in harness-kit.** Its markdown contains no markdown links at all, and only 17 addresses that start with `https://`. The research files cite 1,637 web addresses in their labels, written without `https://` by convention, which link checkers do not recognise; the 544 full addresses live in the two `sources.csv` files. remark-validate-links reported no problems because there was nothing for it to follow. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
3. **A naive "does this path exist" check would mostly raise false alarms.** Of 268 path-like names in backticks in harness-kit's markdown, 123 (46%) are not files in the repository. Every one I inspected in the README and the skills is legitimate: a file in a consumer project (such as `.harness/protected-paths`), a file made at run time (`.git/harness-kit/events.tsv`) or an example (`.reports/feat-login.md`). [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
4. **A prose linter with default settings is mostly noise here.** markdownlint-cli2 reported 3,066 issues in the README and the 16 research files; 2,560 of them (83%) are line length, which does not matter for prose. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured with markdownlint-cli2 0.23.3]
5. **Some comments point at evidence that is not in the repository.** Three comments in `time-limit.mjs` and one in `.harness/replay-machinery` cite `.reports/inc-….brief.md` as the source of a number, but `.reports/` is never committed; `check-reports.mjs` fails the check if it is. The evidence exists only on your Mac, and only until the report is removed. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

## 1. What to comment, and what not to

- **Google's shell style guide:** "Start each file with a description of its contents." "Any function that is not both obvious and short must have a function header comment. Any function in a library must have a function header comment regardless of length or complexity." A function header lists Globals, Arguments, Outputs and Returns. "Comment tricky, non-obvious, interesting or important parts of your code." "Don't comment everything." [VERIFIED | google.github.io/styleguide/shellguide.html | accessed 2026-09-30 | extract]
- **Google's code review guide:** comments "should not be explaining *what* some code is doing"; "Comments are for information that the code itself can't possibly contain, like the reasoning behind a decision." And: "If a CL changes how users build, test, interact with, or release code, check to see that it also updates associated documentation." [VERIFIED | google.github.io/eng-practices/review/reviewer/looking-for.html | accessed 2026-09-30 | extract]
- **Google's JavaScript style guide** requires JSDoc on "all classes, fields, and methods", and says "Do not use JSDoc (/** … */) for implementation comments." [VERIFIED as read by a sub-agent | google.github.io/styleguide/jsguide.html | accessed 2026-09-30]
- **A different view, the Linux kernel:** "Generally, you want your comments to tell WHAT your code does, not HOW", placed at the head of a function rather than inside its body. The kernel's "what" means the function's purpose, which is close to Google's "why" and far from restating each line. [VERIFIED as read by a sub-agent | docs.kernel.org/process/coding-style.html | accessed 2026-09-30]
- **Google Testing Blog, 2017:** comments should reveal intent, explaining why rather than what, and refactoring (a better name, an extracted function) should come before a comment. [VERIFIED as read by a sub-agent | testing.googleblog.com/2017/07/code-health-to-comment-or-not-to-comment.html | 2017-07-17]
- **Stack Overflow's nine rules (2021):** Rule 1 is "Comments should not duplicate the code", because such comments "can become out-of-date". Rule 8 is "Add comments when fixing bugs", because "commit messages tend to be brief, and the most important change may not be part of the most recent commit." [VERIFIED | stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/ | 2021-12-23 | extract]
- **Where history goes.** OpenStack forbids author tags in files: "We use version control instead." [VERIFIED as read by a sub-agent | docs.openstack.org/hacking/latest/user/hacking.html | accessed 2026-09-30] The GNU standards split the job: the reason a change was needed belongs "in comments in the code, where people will see it", while what was deleted or moved belongs in the change log. [VERIFIED as read by a sub-agent | www.gnu.org/prep/standards/html_node/Change-Log-Concepts.html | accessed 2026-09-30] So "keep history out of comments" means "keep the story of changes out"; the reason the code is the way it is belongs in the comment.
- **harness-kit today.** 28% of script lines and 15% of test lines are comments. Of about 3,764 comment lines, 67 carry history words such as version numbers, defect numbers or "increment" (for example "renamed to brief in v0.18.0"). Some of these are needed, such as notes on how old event-log formats are still read. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
- **A comment that restates code is a second copy of the code.** `time-limit.mjs` opens with a table of every limit and budget, then defines the same values in `LIMITS` and `BUDGETS` a few lines later. They match today; nothing keeps them matching. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of the header and the definitions]

## 2. Evidence that comments and documents drift

- **Comments rarely change with the code.** Wen and colleagues mined 1.3 billion code changes in 1,500 Java systems: "13% to 20% of code changes trigger a comment change in the class and/or in the methods' comments", and across all change types, comments of methods co-evolved with the code in "7% of cases". They found "69 types of comment changes tackled by developers, 25 of which relevant for code-comment inconsistencies." [VERIFIED | www.inf.usi.ch/faculty/lanza/PUBS/P/Wen2019a.pdf | 2019 | extract]
- **When comments do change, it is usually with the code.** Fluri and colleagues, on three systems: "97% of comment changes are done in the same revision as the associated source code change", and newly added code "barely gets commented". [VERIFIED | www.merlin.uzh.ch/publication/show/2530 | 2007-10 | extract] These two findings do not conflict: most code changes leave comments alone, and the few comment changes ride along with code changes.
- **Outdated references in documentation are common.** Tan, Wagner and Treude analysed "over 3,000 GitHub projects and found that most projects contain at least one outdated code element reference at some point in their history". [VERIFIED | arxiv.org/abs/2212.01479 | 2022-12-02 | extract (abstract)]
- **Documentation problems are varied.** Aghajani and colleagues categorised 878 documentation-related artefacts from mailing lists, Stack Overflow, issue trackers and pull requests. [VERIFIED as read by a sub-agent | 2019.icse-conferences.org/details/icse-2019-Technical-Papers/49/Software-Documentation-Issues-Unveiled | 2019]
- **A narrow tool can find real inconsistencies.** @tComment checked only null-value and exception claims in Javadoc and found 29 inconsistencies in 7 projects. [VERIFIED as read by a sub-agent | www.cs.purdue.edu/homes/lintan/publications/@tComment-icst12.pdf | 2012]
- **Counter-evidence on harm.** Ibrahim and colleagues found that inconsistent comment updates "are not necessarily correlated with more bugs"; a sudden change in a file's usual update pattern was the risk. [VERIFIED as read by a sub-agent | sail.cs.queensu.ca/data/pdfs/JSS_OnTheRelationshipBetweenCommentUpdatePracticesAndSoftwareBugs.pdf | 2011] A 2024 preprint on 32 Apache projects found inconsistent changes about 1.5 times more likely to lead to a bug-introducing commit. [VERIFIED as read by a sub-agent | arxiv.org/html/2409.10781v1 | 2024-09-16]
- **All of these studies are on Java or C.** A study of shell scripts or markdown instruction files: NOT FOUND, and not searched.

## 3. Documentation generated from code, with a check

| Tool or project | How it works | Check mode |
|---|---|---|
| Cog (Python) | Runs small Python snippets inside a file and writes their output between `[[[cog ]]]` and `[[[end]]]` markers | `--check`: "Check that the files would not change if run again." `--check-fail-msg` adds a hint on failure |
| embedme (Node) | Copies source files into markdown code blocks | `--verify`; no release since 7 September 2022 |
| markdown-magic (Node) | Fills comment blocks from code, files or the web | no check flag found |
| doctoc (Node) | Writes a table of contents between `<!-- START doctoc -->` and `<!-- END doctoc -->` | `--dryrun` exits 1 when a file is out of date |
| terraform-docs | Writes a module's inputs and outputs between markers | `--output-check` |
| Kubernetes | Regenerates its docs and compares them with the committed copy | fails with "Generated docs need to be updated" and "Please run 'hack/update-generated-docs.sh'" |
| ESLint | A build step checks every rule file | fails with "Missing documentation for rule %s" or "Missing tests for rule %s" |
| npm command-line tool | A test compares its command list with its documentation files | the assertion "command list and docs files are the same" |

Sources: [VERIFIED | cog.readthedocs.io/en/latest/running.html | accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | www.npmjs.com/package/embedme | v1.22.1, 2022-09-07] [VERIFIED as read by a sub-agent | github.com/DavidWells/markdown-magic | 4.11.0, 2026-06-29] [VERIFIED as read by a sub-agent | raw.githubusercontent.com/thlorenz/doctoc/master/README.md | accessed 2026-09-30] [VERIFIED as read by a sub-agent | terraform-docs.io/reference/terraform-docs/ | accessed 2026-09-30] [VERIFIED | github.com/kubernetes/kubernetes/blob/master/hack/verify-generated-docs.sh | accessed 2026-09-30 | extract] [VERIFIED | github.com/eslint/eslint/blob/main/Makefile.js | accessed 2026-09-30 | extract] [VERIFIED | github.com/npm/cli/blob/latest/test/lib/docs.js | accessed 2026-09-30 | extract]

- **Examples that run.** Rust runs the code examples in its documentation as tests, "This makes sure that examples within your documentation are up to date and working", and Python's doctest does the same for docstrings. [VERIFIED as read by a sub-agent | doc.rust-lang.org/rustdoc/write-documentation/documentation-tests.html | accessed 2026-09-30] [VERIFIED as read by a sub-agent | docs.python.org/3/library/doctest.html | accessed 2026-09-30] For shell commands written in markdown, txm, clitest, scrut and cram run them and compare the output. [VERIFIED as read by a sub-agent | github.com/anko/txm | v8.2.0, 2023-07-03] [VERIFIED as read by a sub-agent | github.com/aureliojargas/clitest | 0.5.0 (year not shown); accessed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/facebookincubator/scrut | v0.4.3, 2026-01-28]
- **harness-kit already has this kind of check for configuration.** `tests/validate.sh` checks that the plugin name matches the marketplace entry, that the version is set only in `plugin.json`, that each checking hook's time limit plus the grace period is below its timeout in `hooks.json`, that `validate.yml` has the eight-shard replay shape, that the `brief` skill's template has its eight sections in order, and that commands are written by their full names. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of tests/validate.sh] What is missing is the same treatment for prose documents.
- **A dependency-free version works.** In a scratch copy I wrote a 58-line Node script that writes two README sections, a table of the hooks from `hooks.json` and a table of the limits from `time-limit.mjs`, and in check mode fails when they differ. It passed on the generated README and failed, naming the section, when I changed one timeout in `hooks.json`. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy] File 07 shows it.

## 4. Link and path checkers

| Tool | What it checks | Notes |
|---|---|---|
| lychee (Rust) | Links in markdown, HTML and text files, local and online | `--offline`: "Only check local files and block network requests". `--include-fragments`: "Enable the checking of fragments in links." Excludes go in `.lycheeignore`; `--cache` keeps results in `.lycheecache` |
| lychee-action | Runs lychee in GitHub Actions; its example runs on a daily schedule and can open an issue instead of failing | Apache-2.0 or MIT; v2.9.0, 9 July 2026 |
| remark-validate-links (Node) | "markdown links and images point to existing local files and headings in a Git repo" | "This plugin does not check external URLs"; "can work offline (making this plugin fast en prone to fewer false positives)"; only its command-line version checks headings in other files |
| markdown-link-check (Node) | Links in markdown, online | still released (v3.15.0, 28 July 2026); its best-known GitHub Action wrapper is archived |
| linkinator (Node) | Crawls sites or local files; checks anchors with `--check-fragments` | version 8 requires Node 22 or later |
| markdownlint-cli2 (Node) | Markdown layout rules | configuration-based; defaults are noisy (see CONTRADICTIONS 4) |
| Vale | Prose style rules, with word lists: entries in `reject.txt` are flagged as errors | needs a configuration file and downloaded styles |

Sources: [VERIFIED | raw.githubusercontent.com/lycheeverse/lychee/master/README.md | accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | github.com/lycheeverse/lychee-action | v2.9.0, 2026-07-09] [VERIFIED | raw.githubusercontent.com/remarkjs/remark-validate-links/main/readme.md | accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | github.com/tcort/markdown-link-check | v3.15.0, 2026-07-28] [VERIFIED as read by a sub-agent | github.com/JustinBeckwith/linkinator | 8.1.0, 2026-08-27] [VERIFIED as read by a sub-agent | github.com/DavidAnson/markdownlint-cli2 | 0.23.3, 2026-09-20 (secondary sources)] [VERIFIED as read by a sub-agent | docs.vale.sh/keys/vocabularies | accessed 2026-09-30]

- **The false-alarm cost of online checks is documented by the tools themselves.** lychee's guide says that when checking many links from one site "chances are you will get rate limited at some point", and suggests accepting HTTP 429 (too many requests) as valid. [VERIFIED as read by a sub-agent | lychee.cli.rs/troubleshooting/rate-limits/ | accessed 2026-09-30]
- **Maintenance risk.** The widely used GitHub Action wrapper for markdown-link-check was archived on 20 April 2026: "This repository is now ⛔️ **deprecated** and is no longer actively maintained." It points to a maintained fork and to a different tool, Linkspector. [VERIFIED | github.com/gaurav-nelson/github-action-markdown-link-check | archived 2026-04-20 | extract]
- **What would help harness-kit.** An offline check has almost nothing to check today (CONTRADICTIONS 2). An online check has value only for the 544 addresses in `sources.csv`, as an occasional check of whether cited pages still exist, never as a blocking step, because rate limits and bot protection make it noisy. [ASSUMPTION]

## 5. Docs-as-code practice elsewhere

- **Write the Docs** describes the practice as issue trackers, git, plain-text markup, code review and automated tests, and notes that "You can block merging of new features if they don't include documentation". [VERIFIED as read by a sub-agent | www.writethedocs.org/guide/docs-as-code/ | accessed 2026-09-30]
- **GitLab** runs, on its documentation: markdownlint, Vale and a script of its own; an offline check of relative links and anchors ("Any link that requires a network connection is skipped"); a check for deleted or renamed pages without redirects; and checks that links from code to documentation still resolve. [VERIFIED as read by a sub-agent | docs.gitlab.com/development/documentation/testing/ | accessed 2026-09-30] Every GitLab page carries owner metadata, which a task turns into code-owner rules. [VERIFIED as read by a sub-agent | docs.gitlab.com/development/documentation/metadata/ | accessed 2026-09-30]
- **Google** treats documents like code: "Documents without owners become stale and difficult to maintain." Documents carry a freshness block, such as `freshness: { owner: \`username\` reviewed: '2019-02-27' }`, and "metadata in the documentation set will send email reminders when the document hasn't been touched in, for example, three months." [VERIFIED | abseil.io/resources/swe-book/html/ch10.html | 2020 | extract] Note that Google sends reminders; it does not fail builds on old dates.
- **Microsoft Learn** records in `ms.date` "the last time the article was substantially edited or guaranteed fresh", and states no required review interval. [VERIFIED as read by a sub-agent | learn.microsoft.com/en-us/contribute/content/metadata | 2025-05-01]
- A tool that fails a build when a document's review date is too old: NOT FOUND, and not searched after the budget ran out.

## 6. Checking that a document's commands, files and options still exist

- Real projects that do it: npm compares its command list with its documentation files; ESLint fails its build when a rule has no documentation page; Kubernetes regenerates and compares; the Rust command-line library clap runs the examples in its markdown with trycmd; GitLab checks links from code to documentation. [VERIFIED | github.com/npm/cli/blob/latest/test/lib/docs.js | accessed 2026-09-30 | extract] [VERIFIED | github.com/eslint/eslint/blob/main/Makefile.js | accessed 2026-09-30 | extract] [VERIFIED | github.com/kubernetes/kubernetes/blob/master/hack/verify-generated-docs.sh | accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | docs.rs/trycmd/latest/trycmd/ | 1.2.1; accessed 2026-09-30] [VERIFIED as read by a sub-agent | docs.gitlab.com/development/documentation/testing/ | accessed 2026-09-30]
- Doc Detective runs documentation as tests, including shell commands, under the AGPL-3.0 licence, and downloads browsers and drivers. [VERIFIED as read by a sub-agent | github.com/doc-detective/doc-detective | v4.38.1, 2026-08-13]
- Claude Code has a built-in audit that looks for exactly this in instruction files: `/doctor prompt-audit` looks for "references to files or commands that don't exist, and files that contradict each other", and "nothing in your files changes until you ask Claude to apply them". It needs Claude Code v2.1.283 or later. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-30 | full] File 05 covers it.
- **What works for harness-kit** [ASSUMPTION, built on my measurements]: a check scoped to names the code can confirm, such as "every `.harness/<file>` a living document mentions is read by some script" and "every script a living document names exists, or is on a short list of consumer-project scripts". A check of every backticked path would fail on 46% false alarms.

## 7. What this suggests

All of this section is my proposal. [ASSUMPTION, built on the evidence above]

### A comment policy (for both repositories)

1. Every script starts with a header comment: what it is for, how it is run, and what it prints or exits with. Library functions and any function that is not both short and obvious get a header comment too. This is Google's shell rule, and harness-kit mostly follows it already.
2. Other comments explain why: a reason, a constraint, a trap, a link to evidence. They do not restate what the next line does, and they do not copy values that are defined in code; point to the definition instead.
3. The story of a change goes in the commit message: what changed, the `Decision:` line, the defect number. A comment keeps only the reason that someone reading the code today needs, for example "old event logs, written before a format change, are still read here".
4. Evidence named in a comment must be something tracked in the repository: a commit hash, a file under `research/`, or a line in `.harness/defects.tsv`. Never a `.reports/` file.
5. No hand-maintained numbering or lettering of cases or sections. A label or a name is the identity.

### A documentation policy

1. Few living documents: for harness-kit, the README, the skill and agent files, and the `hooks.json` description, cut to one sentence. Everything else is a dated record or a working note (file 01).
2. Any list or number in a living document that the code also holds is generated between markers and checked by the test run, or removed and replaced by a pointer to where the code holds it.
3. A living document changes in the same commit as the behaviour it describes. harness-kit's session-start message already tells Claude to update every file, comment, test and document that describes behaviour it changed. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of hooks.json]
4. Dated records carry a date and a status line at the top, and are replaced, not rewritten.

### Drift checks, cheapest and most certain first

| Order | Check | What it catches | Cost |
|---|---|---|---|
| 1 | Every `tests/*.test.sh` is run, or the runner finds test files itself | a new test file that never runs | a few lines in `validate.sh` |
| 2 | Generated sections are up to date (`tools/gen-docs.mjs --check`) | hook and limit tables that disagree with the code | about 60 lines, no dependency |
| 3 | The research index lists every topic folder with a status line | an index missing a topic, as on 27 September | a few lines |
| 4 | Names in living documents resolve: `.harness/` files are read by some script; named scripts exist or are listed consumer scripts | a document naming a file or script that no longer exists | about 40 lines |
| 5 | No comment cites a `.reports/` file | evidence that exists only on one Mac | one search |
| 6 (occasional) | Online check of the addresses in `sources.csv` with lychee, not blocking | cited pages that disappeared | a Rust binary, network access, rate limits |
| 7 (optional) | markdownlint-cli2 with line length switched off | broken lists and headings | a Node dependency and a configuration file |

## Negative results

- Studies of drift in shell scripts or markdown instruction files: NOT FOUND, and not searched.
- A tool that fails a build on an old review date: NOT FOUND.
- In harness-kit: no README number that disagrees with the code, no broken markdown link, and no pass label and fail label that have drifted apart.
- A check flag in markdown-magic: NOT FOUND in the README the sub-agent read.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against generated sections:** markers clutter the markdown, and the generator is code to maintain; if the list is short, deleting it and pointing to the code is cheaper and cannot drift.
- **Against a comment policy:** rules about comments are judgement calls, and no deterministic check can tell a "why" comment from a "what" comment. Only rules 4 and 5 are mechanically checkable; the rest depend on review, human or AI (file 05).
- **Against link checking at all:** in this repository it would mostly check other people's web sites, whose failures you cannot fix; a cited page that disappears does not make the research wrong, only harder to re-check.
- **For keeping history in comments:** the Stack Overflow article and the GNU standards both argue that the reason for a bug fix should live next to the code, because commit messages are brief and hard to find. The policy above keeps the reason and moves only the story.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- @tComment: Testing Javadoc Comments to Detect Comment-Code Inconsistencies (Tan et al.). https://www.cs.purdue.edu/homes/lintan/publications/@tComment-icst12.pdf. ICST 2012; 2012; primary; read: sub-agent extract.
- A Large-Scale Empirical Study on Code-Comment Inconsistencies (Wen, Nagy, Bavota, Lanza). https://www.inf.usi.ch/faculty/lanza/PUBS/P/Wen2019a.pdf. Università della Svizzera italiana; ICPC 2019; 2019; primary; read: extract.
- Best practices for writing code comments. https://stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/. Stack Overflow blog (Ellen Spertus); 2021-12-23; primary; read: extract.
- clitest. https://github.com/aureliojargas/clitest. Aurelio Jargas; 0.5.0 (year not shown); accessed 2026-09-30; primary; read: sub-agent extract.
- Code Health: To Comment or Not to Comment?. https://testing.googleblog.com/2017/07/code-health-to-comment-or-not-to-comment.html. Google Testing Blog (Dori Reuveni, Kevin Bourrillion); 2017-07-17; primary; read: sub-agent extract.
- Cog documentation: Running Cog. https://cog.readthedocs.io/en/latest/running.html. Ned Batchelder; undated; accessed 2026-09-30; primary; read: extract.
- control-chart-gadget CLAUDE.md, version 4.3. control-chart-gadget/CLAUDE.md (private repository). the person (private repository); 2026-09-28; primary; read: seen in context: loaded automatically by this session, not opened by me.
- Detecting Outdated Code Element References in Software Repository Documentation (Tan, Wagner, Treude). https://arxiv.org/abs/2212.01479. arXiv; 2022-12-02; primary; read: extract (abstract).
- Do code and comments co-evolve? (Fluri, Würsch, Gall). https://www.merlin.uzh.ch/publication/show/2530. University of Zurich; WCRE 2007; 2007-10; primary; read: extract.
- Doc Detective. https://github.com/doc-detective/doc-detective. Doc Detective project; v4.38.1, 2026-08-13; primary; read: sub-agent extract.
- Docs as Code. https://www.writethedocs.org/guide/docs-as-code/. Write the Docs; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- doctoc README. https://raw.githubusercontent.com/thlorenz/doctoc/master/README.md. Thorsten Lorenz; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- embedme. https://www.npmjs.com/package/embedme. Zak Henry; v1.22.1, 2022-09-07 (GitHub); primary; read: sub-agent extract.
- ESLint Makefile.js (checkRuleFiles). https://github.com/eslint/eslint/blob/main/Makefile.js. ESLint project; undated; accessed 2026-09-30; primary; read: extract.
- github-action-markdown-link-check (archived). https://github.com/gaurav-nelson/github-action-markdown-link-check. Gaurav Nelson; archived 2026-04-20; primary; read: extract.
- GitLab: Documentation metadata. https://docs.gitlab.com/development/documentation/metadata/. GitLab; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- GitLab: Documentation testing. https://docs.gitlab.com/development/documentation/testing/. GitLab; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- GNU Coding Standards 6.8.1: Change Log Concepts. https://www.gnu.org/prep/standards/html_node/Change-Log-Concepts.html. Free Software Foundation; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Google JavaScript Style Guide. https://google.github.io/styleguide/jsguide.html. Google; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Google Shell Style Guide. https://google.github.io/styleguide/shellguide.html. Google; undated; accessed 2026-09-30; primary; read: extract.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- How Claude remembers your project (CLAUDE.md, /doctor prompt-audit). https://code.claude.com/docs/en/memory. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Inconsistent code-comment changes and bug-introducing commits (Radmanesh et al.). https://arxiv.org/html/2409.10781v1. arXiv; 2024-09-16; primary; read: sub-agent extract.
- Kubernetes hack/verify-generated-docs.sh. https://github.com/kubernetes/kubernetes/blob/master/hack/verify-generated-docs.sh. Kubernetes project; undated; accessed 2026-09-30; primary; read: extract.
- linkinator. https://github.com/JustinBeckwith/linkinator. Justin Beckwith; 8.1.0, 2026-08-27; primary; read: sub-agent extract.
- Linux kernel coding style (section 8: commenting). https://docs.kernel.org/process/coding-style.html. kernel.org; accessed 2026-09-30; primary; read: sub-agent extract.
- lychee README (command-line options). https://raw.githubusercontent.com/lycheeverse/lychee/master/README.md. lycheeverse; undated; accessed 2026-09-30; primary; read: extract.
- lychee-action. https://github.com/lycheeverse/lychee-action. lycheeverse; v2.9.0, 2026-07-09; primary; read: sub-agent extract.
- lychee: rate limits. https://lychee.cli.rs/troubleshooting/rate-limits/. lycheeverse; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- markdown-link-check. https://github.com/tcort/markdown-link-check. Thomas Cort; v3.15.0, 2026-07-28; primary; read: sub-agent extract.
- markdown-magic. https://github.com/DavidWells/markdown-magic. David Wells; 4.11.0, 2026-06-29; primary; read: sub-agent extract.
- markdownlint-cli2. https://github.com/DavidAnson/markdownlint-cli2. David Anson; 0.23.3, 2026-09-20 (secondary sources); primary; read: sub-agent extract.
- Microsoft Learn: metadata (ms.date). https://learn.microsoft.com/en-us/contribute/content/metadata. Microsoft; 2025-05-01; primary; read: sub-agent extract.
- npm CLI test: test/lib/docs.js. https://github.com/npm/cli/blob/latest/test/lib/docs.js. npm; undated; accessed 2026-09-30; primary; read: extract.
- On the relationship between comment update practices and software bugs (Ibrahim et al.). https://sail.cs.queensu.ca/data/pdfs/JSS_OnTheRelationshipBetweenCommentUpdatePracticesAndSoftwareBugs.pdf. Journal of Systems and Software; 2011; primary; read: sub-agent extract.
- OpenStack hacking rules (H105: no author tags). https://docs.openstack.org/hacking/latest/user/hacking.html. OpenStack; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Python doctest. https://docs.python.org/3/library/doctest.html. Python Software Foundation; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- remark-validate-links readme. https://raw.githubusercontent.com/remarkjs/remark-validate-links/main/readme.md. remarkjs; undated; accessed 2026-09-30; primary; read: extract.
- rustdoc: Documentation tests. https://doc.rust-lang.org/rustdoc/write-documentation/documentation-tests.html. Rust project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- scrut. https://github.com/facebookincubator/scrut. Meta (facebookincubator); v0.4.3, 2026-01-28; primary; read: sub-agent extract.
- Software Documentation Issues Unveiled (Aghajani et al.). https://2019.icse-conferences.org/details/icse-2019-Technical-Papers/49/Software-Documentation-Issues-Unveiled. ICSE 2019; 2019; primary; read: sub-agent extract.
- Software Engineering at Google, chapter 10: Documentation. https://abseil.io/resources/swe-book/html/ch10.html. Google / O'Reilly (Tom Manshreck); 2020; primary; read: extract.
- terraform-docs reference (--output-check). https://terraform-docs.io/reference/terraform-docs/. terraform-docs project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- trycmd. https://docs.rs/trycmd/latest/trycmd/. trycmd project; 1.2.1; accessed 2026-09-30; primary; read: sub-agent extract.
- txm. https://github.com/anko/txm. anko; v8.2.0, 2023-07-03; primary; read: sub-agent extract.
- Vale: vocabularies. https://docs.vale.sh/keys/vocabularies. vale-cli; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- What to look for in a code review. https://google.github.io/eng-practices/review/reviewer/looking-for.html. Google engineering practices; undated; accessed 2026-09-30; primary; read: extract.
