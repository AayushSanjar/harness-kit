# 01 — Repository structure: folders, names, where tests and documents live, and how decisions are recorded (research question A)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Repository:** one git project, with its full history. Here, harness-kit (public) and control-chart-gadget (private).
- **Top-level folder:** a folder directly inside the repository's root folder, such as `tests/`.
- **Plugin root:** the folder that Claude Code copies to a user's machine when they install a plugin. In harness-kit this is `plugins/harness-kit/`, not the repository root.
- **Shipped and not shipped:** a file is shipped when it sits inside the plugin root and therefore reaches every user who installs the plugin. Tests and research outside the plugin root are not shipped.
- **Living document:** a document that must describe the code as it is today, such as a README. When the code changes, the document must change in the same commit.
- **Dated record:** a document that describes what was known or decided on a given date, such as a research file or a decision record. It is never rewritten to match today's code. When it stops being true, a newer record replaces it and the old one is marked as replaced.
- **Decision record (often called an ADR, "architecture decision record"):** a short file that states one decision, its context and its consequences, and whether it is still in force.
- **Index:** a file that lists other files, such as `research/README.md`.
- **Mirror layout:** a test folder whose sub-folders copy the source folders, so that `lib/rules/x.js` is tested by `tests/lib/rules/x.js`.
- **Co-location:** keeping a test file next to the file it tests, such as `auth.js` beside `auth.test.js`.
- **Maintenance tooling:** scripts that help maintain the repository (for example, a script that regenerates a document) but are not part of the product.
- **Forge app:** an app that runs on Atlassian's hosting. A **manifest** (`manifest.yml`) declares its parts; a **resolver** is its server-side function; **Custom UI** is a front end built as a normal web page.

## How this file is based on evidence

- **Sources.** This file cites 38 sources, 36 of them primary. A primary source is a project's own repository, documentation or blog, or the original paper.
- **How they were chosen.** A research sub-agent read 77 pages (75 primary) about the projects named in the question and a few well-run examples it chose: ESLint, the npm command-line tool, Node.js, git, bats-core, rbenv, nvm, ShellSpec and Anthropic's own plugin repositories, plus the decision-record literature. It is a chosen sample, not a random one, so the patterns below describe these projects only.
- **What I checked myself.** I re-read in the primary source every claim that a recommendation rests on (these carry a plain [VERIFIED] label with how I read them). I cloned harness-kit at commit `e275280` (version 0.20.0), read the files named below, and measured the rest with scripts. For control-chart-gadget I used only its `CLAUDE.md`, which this session loaded into my context automatically; I did not open any other file in it, as you asked.
- **How to read the labels.** [VERIFIED] means a primary source says it; the link (without "https://"), the date and how I read it follow. "full" means I read the whole page or file; "extract" means the fetch tool returned the passages I asked for, not the whole page; "measured" means I computed it on the harness-kit clone. [VERIFIED as read by a sub-agent] means a sub-agent read it in the primary source and I did not re-read it. [PARTIAL] means a secondary source or partial support. [ASSUMPTION] means my own inference or proposal. NOT FOUND means someone searched and found nothing. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.
- **A limit on the research.** The session's shared budget of 200 web searches ran out while the sub-agents worked. After that they fetched known addresses directly. The sub-agent could therefore not search for studies that compare folder layouts (see Negative results).

## CONTRADICTIONS

These contradict something your brief or your filing rule appears to treat as settled.

1. **harness-kit's public `research/` folder already holds product research about the gadget.** Your 30 September filing rule puts Forge and other product research in the private repository. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
   - `research/initial-harness/06-behaviour-checks.md` is about testing Atlassian Forge apps and has 68 lines that mention Forge, the gadget, Jira or Atlassian.
   - `research/design/03-data-visualisation.md` has a section on the cycle-time control chart itself.
   - `research/design/05-template.md` has a worked example titled "an Atlassian Forge dashboard gadget showing a cycle-time control chart".
   - `research/design/06-open-questions.md` asks four questions about the chart and the Forge widget.
   - `research/initial-harness/README.md`, `research/initial-harness/00-glossary.md`, `research/initial-harness/01-principles.md` and `research/initial-harness/07-open-questions.md` each carry Forge findings.
   - I found no passage about competitors, prices or listing plans. One line in `research/design/02-automated-checks.md` notes that Atlassian publishes no design requirements for Marketplace apps.
   - Moving these files now would not make them private: they stay in the public repository's history. [ASSUMPTION: how git history works]
   - The `ci-and-github` research that now sits, not yet committed, in the same `research/` folder on your Mac names the gadget's local folder path in its `00-decision.md`. That is technical, not business, but it becomes public when committed. [PARTIAL | harness-kit/research/ci-and-github (local, untracked) | 2026-09-30 | full for 00-decision.md]
2. **The research index went out of date within one day.** `research/README.md` (now `research/initial-harness/README.md`) was committed once, on 26 September, and describes only files 00 to 07. It does not mention the `design/` sub-folder added on 27 September, whose own `sources.csv` lists 312 more web addresses, nor the two sub-folders now on your Mac. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
3. **The folder layout proposed in research file 04 is not what was built, and nothing says so.** Of the 11 plugin parts that `04-replication.md` Part C proposed on 26 September, 7 do not exist: the skills `define-done`, `verify`, `promote-rule` and `setup-project`, the `evaluator` agent, `templates/` and `evals/`. The proposed `tests/hooks/` and `tests/seeded-faults/` were replaced by `tests/*.test.sh` and `.harness/mutations.tsv`. The proposal is labelled as an assumption, which is honest, but a reader has no way to tell that it was superseded. [VERIFIED | github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/04-replication.md | 2026-09-26 | extract] [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

## 1. What harness-kit looks like today

[VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

| Place | What is in it | Size |
|---|---|---|
| `.claude-plugin/marketplace.json` | Makes the repository its own plugin marketplace, pointing at `./plugins/harness-kit` | 13 lines |
| `plugins/harness-kit/` | The plugin: `hooks/hooks.json`, `agents/reviewer.md`, two skills (`brief`, `record-defect`), and 38 scripts | 8,957 script lines: 2,992 shell, 5,965 JavaScript |
| `tests/` | 20 test files named `<name>.test.sh`, the runner `validate.sh`, and one data file | 8,048 lines of tests plus 370 in `validate.sh` |
| `.harness/` | Configuration the harness reads: the check command, the fault list, the check-to-file map, the defect log | 7 files |
| `research/` | Files 00 to 07 (26 September), `design/` (27 September), two `sources.csv` files | 4,442 lines of markdown |
| `.github/workflows/validate.yml` | CI (covered by the separate ci-and-github research) | 202 lines |
| `README.md` | Thirteen lines, most of them long paragraphs about the release and replay scripts and their limits | 13 lines |

There is no `docs/` folder and no folder for repository-only maintenance scripts. Decisions are recorded as `Decision:` lines in commit messages: the history holds 104 such lines. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

## 2. What well-run projects do

### 2.1 JavaScript and Node tools

| Project | Top-level folders (as read) | Where tests live, and how they are grouped | Shared test code | Maintenance scripts |
|---|---|---|---|---|
| ESLint | `bin/`, `conf/`, `docs/`, `lib/`, `messages/`, `packages/`, `templates/`, `tests/`, `tools/` | `tests/`, copying the source folders: `tests/lib/rules` tests `lib/rules` | not recorded | `tools/` and `Makefile.js` |
| npm command-line tool | `bin/`, `docs/`, `lib/`, `scripts/`, `smoke-tests/`, `test/`, `workspaces/` and others | `test/`, copying the source folders: `test/lib/commands/install.js` tests `lib/commands/install.js` | not recorded | `scripts/` |
| Node.js | `doc/`, `lib/`, `src/`, `test/`, `tools/`, `benchmark/`, `deps/` | `test/`, grouped by how the tests run (`parallel`, `sequential` and others), not by source folder | `test/common`, with data in `test/fixtures` | `tools/` |

Sources for the table: [VERIFIED as read by a sub-agent | eslint.org/docs/head/contribute/development-environment | accessed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/npm/cli | observed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/nodejs/node/blob/main/test/README.md | accessed 2026-09-30]

- The npm command-line tool publishes only a listed set of folders, so its tests never reach users. [VERIFIED as read by a sub-agent | github.com/npm/cli | observed 2026-09-30]
- Node.js asks for one new file per new test: "In principle, when adding a new test, it should be placed in a new file. Unless there is strong motivation to do so, refrain from appending new test cases to an existing file." [VERIFIED | github.com/nodejs/node/blob/main/doc/contributing/writing-tests.md | accessed 2026-09-30 | extract]
- Node.js names test files after what they test: "The first component of the name is `test`. The second is the module or subsystem being tested." [VERIFIED | github.com/nodejs/node/blob/main/doc/contributing/writing-tests.md | accessed 2026-09-30 | extract]

### 2.2 Shell tools

- **git** keeps its tests in `t/`, named `tNNNN-commandname-details.sh`, where the first digit is the family of commands, the second the command and the optional third the option being tested. Every test script sources one shared library, `test-lib.sh`, whose helpers are listed in `test-lib-functions.sh`. [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract]
- **bats-core**, a test framework for bash, recommends a `test/` folder with shared setup in `test/test_helper/common-setup.bash`, loaded by each test file. [VERIFIED as read by a sub-agent | bats-core.readthedocs.io/en/stable/tutorial.html | accessed 2026-09-30]
- **rbenv** keeps its commands in `libexec/` and its tests in `test/`, with one shared `test/test_helper.bash` that defines helpers such as `assert_success` and `assert_output`. [VERIFIED as read by a sub-agent | github.com/rbenv/rbenv | observed 2026-09-30]
- **nvm** splits its tests into `test/fast` and `test/slow`. [VERIFIED as read by a sub-agent | github.com/nvm-sh/nvm | observed 2026-09-30]
- **ShellSpec** keeps its tests in `spec/`, copying the structure of `bin/` and `lib/`, with one shared `spec/spec_helper.sh`. [VERIFIED as read by a sub-agent | github.com/shellspec/shellspec | latest release 0.28.1, 2021-01-11]

### 2.3 Claude Code plugins

- The plugin manifest goes in `.claude-plugin/plugin.json` and every other plugin file goes at the plugin root: "Put every other plugin file at the plugin root, not inside `.claude-plugin/`." [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-30 | full]
- The documented example layout includes "a `scripts/` folder that its hooks call", which is what harness-kit does. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-30 | full]
- "A `CLAUDE.md` at the plugin root isn't loaded as context", and `claude plugin validate` warns about one. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-30 | full]
- At install, Claude Code copies the plugin folder into its cache, and "Files outside the plugin directory aren't copied". [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-30 | full] Because harness-kit's marketplace points at `./plugins/harness-kit`, its `tests/`, `research/` and `.harness/` folders never reach users. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full]
- The only test folder Anthropic documents inside a plugin is `evals/`, for behaviour tests run by `claude plugin eval`. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugin-evals | accessed 2026-09-30]
- An official Anthropic plugin that ships unit tests of its own scripts: NOT FOUND. The sub-agent could not list the plugin folders, because GitHub's folder pages were blocked for the fetch tool. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official | observed 2026-09-30]
- A third-party marketplace found that everything under its `plugins/<name>/` folder reached every user, and moved its tests out. [PARTIAL | github.com/ScottHysom/claude-plugins/issues/23 | 2026-09-15]
- A skill is a `SKILL.md` file with optional `scripts/`, `references/` and `assets/` folders. [VERIFIED as read by a sub-agent | github.com/anthropics/skills | observed 2026-09-30]

### 2.4 Where decisions and design notes are recorded

- **Michael Nygard's original proposal (2011).** "We will keep ADRs in the project repository under doc/arch/adr-NNN.md." "Numbers will not be reused." "If a decision is reversed, we will keep the old one around, but mark it as superseded." "The whole document should be one or two pages long." [VERIFIED | cognitect.com/blog/2011/11/15/documenting-architecture-decisions | 2011-11-15 | extract]
- **MADR 4.0.0** (a markdown template for decision records, released 17 September 2024) uses the folder `docs/decisions` and file names `NNNN-title-with-dashes.md`. Its status field includes "superseded by ADR-0123". Its reason for a separate folder: "Decisions are placed in the subfolder `decisions/` to keep them close to the documentation but also separate the decisions from other documentation." [VERIFIED | adr.github.io/madr | MADR 4.0.0, 2024-09-17 | extract]
- **adr-tools** uses `doc/adr` and can mark an earlier record as superseded when it writes a new one. [VERIFIED as read by a sub-agent | github.com/npryce/adr-tools | release 3.0.0 (year not shown); accessed 2026-09-30]
- **log4brains** says "an ADR is immutable" and avoids sequential numbers because they cause merge conflicts. [VERIFIED as read by a sub-agent | github.com/thomvaill/log4brains | v1.1.0, 2024-12-17]
- **The UK government's framework** (4 November 2025, updated 10 September 2026) lists what a record should contain, including "links to supporting documents", but says nothing about where to store records. [VERIFIED as read by a sub-agent | www.gov.uk/government/publications/architectural-decision-record-framework | 2025-11-04, updated 2026-09-10]
- **Kubernetes enhancement proposals** get one folder each, holding a `README.md` and a `kep.yaml` file whose fields include `status`, `creation-date` and `replaces`. [VERIFIED as read by a sub-agent | github.com/kubernetes/enhancements/tree/master/keps | observed 2026-09-30]
- **Python enhancement proposals.** "Once resolution is reached, a PEP is considered a historical document rather than a living specification." Supporting files may go "in a subdirectory called `pep-XXXX`", and "PEPs can also be superseded by a different PEP, rendering the original obsolete." [VERIFIED | peps.python.org/pep-0001/ | modified 2026-09-27 | extract]
- **Rust RFCs** are one file each; a substantial change becomes a new RFC with a note added to the original. [VERIFIED as read by a sub-agent | github.com/rust-lang/rfcs | observed 2026-09-30]
- **Counter-evidence from practice.** A former Google engineer writes of design documents: "In practice we humans are bad at updating documents, and for other practical reasons changes are often isolated into new documents." This is a first-hand account, not official Google policy. [VERIFIED as read by a sub-agent | www.industrialempathy.com/posts/design-docs-at-google/ | 2020-07-06]
- **Commit messages as the decision record.** None of the ten decision-record sources the sub-agent read keeps decisions in commit messages; seven keep each decision as its own file or folder. [PARTIAL: the sub-agent's tally over the sources in this section; I did not re-count] harness-kit and the gadget both do, and the gadget generates an index file from those lines. [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context]

### 2.5 How documentation is organised

- **Diátaxis** names four kinds of documentation: tutorials, how-to guides, reference and explanation. [VERIFIED as read by a sub-agent | diataxis.fr | accessed 2026-09-30] It warns against building an empty structure first: "It certainly does not mean that you should create empty structures for tutorials/howto guides/reference/explanation with nothing in them." It asks for small steps: "Complete that next single action, and consider it completed." [VERIFIED | diataxis.fr/how-to-use-diataxis/ | accessed 2026-09-30 | extract]
- **Google's documentation guide.** "A small set of fresh and accurate docs is better than a large assembly of 'documentation' in various states of disrepair." "Change your documentation in the same CL as the code change." (A CL is Google's word for one change under review, like one commit.) "Dead docs are bad." "Default to delete or leave behind if migrating." One section is titled "Duplication is Evil". [VERIFIED | google.github.io/styleguide/docguide/best_practices.html | accessed 2026-09-30 | extract]
- Google's README guide says every top-level folder of a code package should have an up-to-date `README.md`. [VERIFIED as read by a sub-agent | google.github.io/styleguide/docguide/READMEs.html | accessed 2026-09-30]
- **OpenAI's harness write-up** describes a `docs/` folder with `design-docs/`, `exec-plans/` (split into `active/` and `completed/`), `generated/`, `product-specs/` and `references/`, and it warns against one long instruction file: "It rots instantly. A monolithic manual turns into a graveyard of stale rules." Its knowledge base is policed by code: "Dedicated linters and CI jobs validate that the knowledge base is up to date, cross-linked, and structured correctly." [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract]

### 2.6 Debates and counter-evidence

- The widely copied `golang-standards/project-layout` says of itself: "This is NOT an official standard defined by the core Go dev team." [VERIFIED as read by a sub-agent | github.com/golang-standards/project-layout | observed 2026-09-30] Go's own guide puts each test file beside the code it tests. [VERIFIED as read by a sub-agent | go.dev/doc/modules/layout | accessed 2026-09-30]
- Jest and Node's test runner both accept both conventions, a test folder or tests beside the code. [VERIFIED as read by a sub-agent | jestjs.io/docs/configuration | Jest 30.5 docs; accessed 2026-09-30] [VERIFIED | raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md | v24.x branch; accessed 2026-09-30 | extract]
- React's old documentation says "don't spend more than five minutes on choosing a file structure", and recommends keeping files that change together close together. [VERIFIED as read by a sub-agent | legacy.reactjs.org/docs/faq-structure.html | accessed 2026-09-30]
- Measured evidence that one layout beats another: NOT FOUND. The sub-agent could not search for it because the search budget was used up, so this is "not searched" more than "does not exist".

## 3. Patterns across the sample

- **Tests live in one top-level folder in all 11 code projects the sub-agent checked:** `test/` in 7, `tests/` in 2, `t/` in 1 and `spec/` in 1. [PARTIAL: the sub-agent's own tally of ESLint, npm, Node.js, execa, commander, git, bats-core, nvm, rbenv, ShellSpec and asdf; I did not re-count]
- **Grouping differs.** ESLint, npm and ShellSpec copy the source folders. Node.js groups by how tests run, git by numbered command family and nvm by speed. Both are used by well-run projects. [VERIFIED as read by a sub-agent | github.com/nodejs/node/blob/main/test/README.md | accessed 2026-09-30]
- **Shared test code is normal.** git, bats-core, rbenv, ShellSpec and Node.js each have one shared test helper library. [VERIFIED | github.com/git/git/blob/master/t/README | accessed 2026-09-30 | extract] [VERIFIED as read by a sub-agent | github.com/rbenv/rbenv | observed 2026-09-30]
- **Maintenance scripts** sit in `tools/` (ESLint, Node.js), `scripts/` (npm) or `hack/` (Kubernetes). [VERIFIED as read by a sub-agent | eslint.org/docs/head/contribute/development-environment | accessed 2026-09-30]
- **Decisions and proposals are dated records.** Nygard, MADR, log4brains, PEPs and RFCs all keep the old record and mark it as replaced rather than rewriting it. [VERIFIED | cognitect.com/blog/2011/11/15/documenting-architecture-decisions | 2011-11-15 | extract] [VERIFIED | peps.python.org/pep-0001/ | modified 2026-09-27 | extract]

## 4. What this suggests

All of this section is my proposal. [ASSUMPTION, built on the evidence above]

1. **Keep the split between shipped and not shipped.** harness-kit already keeps the plugin in `plugins/harness-kit/`, so tests and research stay out of users' caches. This is the most important structural choice, and it is already right. Repository-only tooling, such as a script that regenerates a document, belongs outside the plugin, in a root `tools/` folder, as ESLint and Node.js do.
2. **Sort every written file into one of three kinds, and give each kind one rule.**
   - Living documents (`README.md`, `SKILL.md` files, the agent file, script header comments, the `description` field in `hooks.json`) must match the code. Keep them few and short, generate their lists from the code, and check them in `tests/validate.sh`.
   - Dated records (research, decisions, the defect log, commit messages) are never rewritten. Each carries its date and a status, and a newer record marks the older one as replaced.
   - Working notes (`.reports/` briefs and summaries) are never committed, which harness-kit already enforces.
   - This is the direct answer to "nobody can keep track of what is still true": each file is either checked by code or openly dated.
3. **Research in topic sub-folders, with a checked index.** Each topic gets `research/<topic>/`, with `00-decision.md` first, a status line at its top ("current", "partly superseded by …", "superseded by …") and its own `sources.csv`. `research/README.md` lists every topic folder with its date and status, and a small check fails when a topic folder is missing from the index. The first eight files and `design/` stay where they are, because moving them would break references that cannot be edited: the append-only defect log names `research/02-claude-features.md`. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full]
4. **Decisions: keep the commit-message lines, and add what they lack.** Keep `Decision:` lines, because they tie a decision to the exact change. Add a generated index for harness-kit, as the gadget already has. Use a topic's `00-decision.md` for decisions that come out of research, since those need context longer than a commit message.
5. **Tests: one file per script under test, named after it, with one shared helper library.** This follows git's and Node.js's practice; file 02 has the evidence and file 07 the layout.

### control-chart-gadget

From the CLAUDE.md and from what a Forge app of this kind needs: [ASSUMPTION, built on the evidence above]

- Its documents are already split well: `docs/SPEC.md` as the authority, `docs/STATE.md` for status, `docs/CHECKLIST.md`, and a generated `docs/DECISIONS-INDEX.md`. [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context]
- The same three kinds apply. `SPEC.md` and `CLAUDE.md` are living documents, so they must be checked or kept short. `STATE.md` is a living document that goes stale by nature, so it needs a "last verified" date at its top. harness-kit's start-up picture already shows its first ten lines, so that date would be seen every session. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | extract: the test names in `.harness/check-files`]
- A Forge app has two front ends with their own dependencies: the Custom UI in `static/view/` and the resolvers in `src/`. Tests should follow the same rule as harness-kit: named after the file they test, in one agreed place. Whether that place is beside the code or in a test folder matters less than choosing one; both are accepted by Node's runner and by Jest. [VERIFIED | raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md | v24.x branch; accessed 2026-09-30 | extract]

## Negative results

- Measured evidence that one folder layout is better than another: NOT FOUND, and not searched properly, because the search budget ran out.
- An official Anthropic plugin with unit tests for its own scripts: NOT FOUND.
- Guidance on where to keep research notes, as opposed to decisions: only MADR's sentence about keeping decisions separate from other documentation was found. [VERIFIED | adr.github.io/madr | MADR 4.0.0, 2024-09-17 | extract]
- None of the decision-record sources uses commit messages as the record. That is a difference from the sample, not proof that the method is wrong.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against sorting documents into kinds:** it adds a rule every writer must remember. The counter to that counter is to make it mechanical: a status line that a check reads, not a convention to remember.
- **Against a checked research index:** the index is one more file that can drift, which is exactly what happened on 27 September. It is worth having only if a check keeps it complete; without the check, drop it and rely on folder names.
- **Against leaving the first eight research files in the root of `research/`:** the root then mixes one topic with the index. The cost of moving them is broken references in an append-only file, so leaving them is the cheaper evil.
- **Against moving gadget material out of harness-kit:** the history stays public, so moving protects nothing already written. The value is only in stopping new product material from landing in the public repository.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- adr-tools. https://github.com/npryce/adr-tools. Nat Pryce; release 3.0.0 (year not shown); accessed 2026-09-30; primary; read: sub-agent extract.
- anthropics/skills repository. https://github.com/anthropics/skills. Anthropic; observed 2026-09-30; primary; read: sub-agent extract.
- Architectural Decision Record Framework. https://www.gov.uk/government/publications/architectural-decision-record-framework. UK Department for Science, Innovation and Technology; 2025-11-04, updated 2026-09-10; primary; read: sub-agent extract.
- bats-core tutorial (test_helper and common setup). https://bats-core.readthedocs.io/en/stable/tutorial.html. bats-core; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- ci-and-github research: 00-decision.md, and sections of 04, 05 and 07. harness-kit/research/ci-and-github (local, untracked). Cowork research job for the same person; 2026-09-30; secondary; read: full for 00-decision.md; extract for the others.
- Claude Code: plugin evals. https://code.claude.com/docs/en/plugin-evals. Anthropic; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- claude-plugins-official repository. https://github.com/anthropics/claude-plugins-official. Anthropic; observed 2026-09-30; primary; read: sub-agent extract.
- control-chart-gadget CLAUDE.md, version 4.3. control-chart-gadget/CLAUDE.md (private repository). the person (private repository); 2026-09-28; primary; read: seen in context: loaded automatically by this session, not opened by me.
- Design Docs at Google. https://www.industrialempathy.com/posts/design-docs-at-google/. Malte Ubl; 2020-07-06; primary; read: sub-agent extract.
- Diátaxis framework (home). https://diataxis.fr. Daniele Procida; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Diátaxis: How to use Diátaxis. https://diataxis.fr/how-to-use-diataxis/. Daniele Procida; undated; accessed 2026-09-30; primary; read: extract.
- Documentation Best Practices (Google documentation guide). https://google.github.io/styleguide/docguide/best_practices.html. Google; undated; accessed 2026-09-30; primary; read: extract.
- Documenting Architecture Decisions. https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions. Cognitect (Michael Nygard); 2011-11-15; primary; read: extract.
- ESLint: development environment (folder layout). https://eslint.org/docs/head/contribute/development-environment. ESLint project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- git: t/README (the test suite's conventions). https://github.com/git/git/blob/master/t/README. Git project; undated; accessed 2026-09-30; primary; read: extract.
- golang-standards/project-layout (and issue 117). https://github.com/golang-standards/project-layout. golang-standards (community); observed 2026-09-30; primary; read: sub-agent extract.
- Google documentation guide: READMEs. https://google.github.io/styleguide/docguide/READMEs.html. Google; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Harness engineering: leveraging Codex in an agent-first world. https://openai.com/index/harness-engineering. OpenAI (Ryan Lopopolo); 2026-02-11; primary; read: extract.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- harness-kit research 04: replication and self-improvement (Part B and Part C read). https://github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/04-replication.md. AayushSanjar (harness-kit); 2026-09-26; primary; read: extract (sections B2 to C3 read in full).
- Jest configuration (testMatch). https://jestjs.io/docs/configuration. Jest project; Jest 30.5 docs; accessed 2026-09-30; primary; read: sub-agent extract.
- Kubernetes Enhancement Proposals (KEP) folder and kep.yaml template. https://github.com/kubernetes/enhancements/tree/master/keps. Kubernetes project; observed 2026-09-30; primary; read: sub-agent extract.
- log4brains. https://github.com/thomvaill/log4brains. Thomas Vaillant; v1.1.0, 2024-12-17; primary; read: sub-agent extract.
- MADR: Markdown Architectural Decision Records. https://adr.github.io/madr. adr.github.io (MADR project); MADR 4.0.0, 2024-09-17; primary; read: extract.
- Node.js test/README.md. https://github.com/nodejs/node/blob/main/test/README.md. Node.js project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Node.js v24 documentation: Test runner. https://raw.githubusercontent.com/nodejs/node/v24.x/doc/api/test.md. Node.js project; v24.x branch; accessed 2026-09-30; primary; read: extract.
- Node.js: How to write a test for the Node.js project. https://github.com/nodejs/node/blob/main/doc/contributing/writing-tests.md. Node.js project; undated; accessed 2026-09-30; primary; read: extract.
- npm CLI repository (layout, files field, tests). https://github.com/npm/cli. npm; observed 2026-09-30; primary; read: sub-agent extract.
- nvm repository (test/fast, test/slow). https://github.com/nvm-sh/nvm. nvm; observed 2026-09-30; primary; read: sub-agent extract.
- Organizing a Go module. https://go.dev/doc/modules/layout. Go project; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- PEP 1: PEP Purpose and Guidelines. https://peps.python.org/pep-0001/. Python Software Foundation; modified 2026-09-27; accessed 2026-09-30; primary; read: extract.
- Plugin loading reference. https://code.claude.com/docs/en/plugins/loading. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Plugin manifest reference (standard layout). https://code.claude.com/docs/en/plugins-reference. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- rbenv repository (libexec/, test/, test_helper.bash). https://github.com/rbenv/rbenv. rbenv; observed 2026-09-30; primary; read: sub-agent extract.
- React (legacy docs): File Structure. https://legacy.reactjs.org/docs/faq-structure.html. Meta / React; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Rust RFCs repository. https://github.com/rust-lang/rfcs. Rust project; observed 2026-09-30; primary; read: sub-agent extract.
- ShellSpec repository, README and changelog. https://github.com/shellspec/shellspec. ShellSpec; latest release 0.28.1, 2021-01-11; primary; read: sub-agent extract.
- Third-party marketplace issue: tests shipped inside plugin folders. https://github.com/ScottHysom/claude-plugins/issues/23. ScottHysom (third party); 2026-09-15; secondary; read: sub-agent extract.
