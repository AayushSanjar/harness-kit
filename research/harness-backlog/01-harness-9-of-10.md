# 01 — What a 9-out-of-10 AI-coding harness looks like, and how harness-kit scores (question A)

Written on Wednesday 30 September 2026. Research only: nothing in harness-kit or on GitHub was changed, and no git command was run.

## Terms used in this file

- **Harness.** Everything around the AI model that shapes and checks its work: instruction files, hooks, permission rules, the sandbox, tests, reviewers and CI. Martin Fowler's site puts it as "Agent = Model + Harness".
- **Guide and sensor.** A guide acts before the agent works (for example an instruction file). A sensor checks after the agent works (for example a test).
- **Deterministic control.** A control made of code that always gives the same answer, such as a test, a linter or a hook. An **inferential control** is a judgement made by an AI model, such as an AI reviewer.
- **Hook.** A script that Claude Code runs automatically at a fixed moment, for example before a tool call (called PreToolUse) or when Claude tries to finish its turn (called Stop).
- **Gate.** A check that can stop work from going further.
- **Permission rule.** A line in Claude Code's settings that allows or forbids a tool call. Claude Code enforces these rules itself, whatever the model decides.
- **Sandbox.** Claude Code's operating-system-level fence around shell commands, limiting which files and network hosts they can reach.
- **Fault replay.** harness-kit's list of 137 planted faults, each of which must make a named test fail. It tests the tests, like mutation testing.
- **Eval (evaluation).** A repeatable test of an AI component's behaviour, run several times because an AI's output varies.
- **Dogfooding.** Using your own product on your own work; here, running the harness on the harness's own repository.
- **Dimension.** One area on which a harness is scored in this file, from 0 to 10.
- **Consumer project.** A repository that installs harness-kit as a plugin.

## How this file is based on evidence

**Sources.** This file draws on 62 sources, of which 51 are primary. The primary sources are Anthropic's engineering posts and Claude Code documentation, OpenAI's own posts and documentation, GitHub's documentation and repositories, the harness-kit repository itself, and GitHub's public record of harness-kit's CI runs. The 11 secondary sources are the person's earlier research files and one vendor article that summarises the OWASP list.

**How they were chosen.**
1. Every source the question named came first.
2. Then pages those sources link to that bear on a dimension below.
3. Then web searches for any published maturity model or checklist for AI coding harnesses.
4. Then two public repositories not covered by the earlier file `research/initial-harness/03-reference-harnesses.md`: OpenAI's own `openai/codex` and GitHub's `github/gh-aw`.

Findings already made in `research/initial-harness/01` to `07` and in `research/ci-and-github/` are cited, not repeated.

**How pages were read.**
- **Full reads:** raw repository files (read with `curl`) and harness-kit's own files.
- **Extracts:** web pages were read through a tool in which a small model answers a question about the page, so each counts as an extract. For Claude Code's documentation pages that tool returned the whole page text, so those quotations are close to exact.
- **Not read:** the Codex AGENTS.md guide page, marmelab's 2026 survey, and the OWASP and DORA lists on their own pages. Nothing is claimed from them.

**Research sub-agent.** A research sub-agent did the external reading; I checked its harness-kit claims against the repository on the person's Mac (commit e275280, v0.20.0).

**Labels.**
- [VERIFIED] means a primary source says it; the link and date follow.
- [PARTIAL] means secondary, extract-only, or partly supported.
- [ASSUMPTION] means my own reasoning.
- NOT FOUND means I searched and found nothing.

## CONTRADICTIONS

1. **"The full fault replay takes about 25 minutes in CI" is out of date.**
   - Since v0.20.0 the whole replay run took 10.9 minutes on `main` and 12.4 minutes on the branch. The same commit's `validate` job spent 146 seconds running `tests/validate.sh`. [VERIFIED | GitHub REST API, harness-kit runs 36697420941 and 36695203471, read 2026-09-30, full read of the JSON]
   - The 25-minute figure comes from before part B (run 36683110696, 25.3 minutes).
2. **"More custom gates means higher quality" is contradicted by Anthropic's guidance and by harness-kit's own defect log.**
   - Anthropic writes: "Every component in a harness encodes an assumption about what the model can't do on its own", and advises "stripping away pieces that are no longer load-bearing" when a new model lands. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24, extract]
   - All 8 escaped defects recorded in `.harness/defects.tsv` (D1 to D8) are defects in harness-kit's own machinery: the CI wait, the fault replay, the time-limit helper, the Stop gate's skip and a fault entry. [VERIFIED | .harness/defects.tsv, full read]
   - Counter-case in your favour: Birgitta Böckeler names measuring "harness coverage and quality similar to what code coverage and mutation testing do for tests" as an unsolved need. Your fault replay does exactly that. [VERIFIED | martinfowler.com/articles/harness-engineering.html | 2026-04-02, extract]
3. **Blocking plan mode goes against both vendors' main advice.**
   - `plan-mode-guard.mjs` refuses Claude's `EnterPlanMode` tool. [VERIFIED | hooks.json, full read]
   - Anthropic recommends "Explore", "Plan", "Implement", "Commit", and adds: "If you could describe the diff in one sentence, skip the plan." [VERIFIED | code.claude.com/docs/en/best-practices | 2026-09-30, extract returned as full page text]
   - OpenAI calls plan mode "the easiest and most effective option" for most users. [VERIFIED | developers.openai.com/codex/learn/best-practices | 2026-09-30, extract]
   - Nuance: you blocked it for a real reason. A bare `/plan` once opened the built-in plan mode, and work began on `main` without an approved brief. [PARTIAL | the person's own account, 29 September 2026; not recorded in the repository] The choice is between blocking it and making plan mode feed the brief.
4. **Your plans are not in the repository, which is where both vendors put them.**
   - Briefs live in `.reports/`, and `.gitignore` contains exactly `.reports/`, so no approved brief is ever committed. [VERIFIED | .gitignore, full read]
   - There is no `CLAUDE.md`, `AGENTS.md`, `STATE.md` or `DECISIONS.md` at the root. [VERIFIED | directory listing on the person's Mac, 2026-09-30]
   - OpenAI keeps "progress and decision logs that are checked into the repository". [VERIFIED | openai.com/index/harness-engineering | 2026-02-11, extract]
5. **The harness does not run on its own repository.** There is no `.claude/settings.json` in harness-kit, so its own sessions load none of its guards. [VERIFIED | directory listing, 2026-09-30] Loading a plugin from a marketplace declared in the repository is documented and small. [VERIFIED | code.claude.com/docs/en/plugins, as re-read in research/initial-harness/01-principles.md]
6. **Published maturity models exist, but none comes from Anthropic, OpenAI or GitHub.**
   - Those three publish practices, not levels (NOT FOUND for a model from them).
   - Four others exist. None is validated against outcomes, and all are vendor or consultant work:
     - the "Harness Model" matrix (10 dimensions, 5 stages) [VERIFIED | handsonarchitects.com | 2026-04-16, extract];
     - Factory's "Agent Readiness" (8 pillars, 5 levels, "60+ criteria") [VERIFIED | factory.com/news/agent-readiness | 2026-01-20, extract];
     - Faros's five layers [VERIFIED | faros.ai | 2026-05-22, extract];
     - the OWASP Top 10 for Agentic Applications, a risk list [PARTIAL | secondary summary].

## 1. The 14 dimensions of a 9/10 harness

I built these from the primary Anthropic, OpenAI, GitHub and Böckeler guidance, and used the published models only to check that no major area was missing. [ASSUMPTION for the selection]

| # | Dimension | What 9/10 looks like | Key evidence |
|---|---|---|---|
| D1 | Project memory in the repository | A short, human-written instruction file (CLAUDE.md or AGENTS.md, under about 200 lines) that acts as a map into a committed `docs/` folder holding decisions, state and plans; pruned regularly | "target under 200 lines per CLAUDE.md file" [VERIFIED \| code.claude.com/docs/en/memory \| 2026-09-30]; "A short `AGENTS.md` (roughly 100 lines) … serves primarily as a map" [VERIFIED \| openai.com harness-engineering \| 2026-02-11, extract] |
| D2 | Plan before code, approved by a human | For multi-file or uncertain changes, a spec that names files, states what is out of scope and ends with an end-to-end verification step; human approval; trivial changes skip it | "The most useful specs are self-contained … end with an end-to-end verification step" [VERIFIED \| code.claude.com/docs/en/best-practices \| 2026-09-30] |
| D3 | Deterministic guardrails | Every rule that must always hold is a hook or a permission rule, not an instruction; the set is small and tested | "hooks are deterministic and guarantee the action happens" [VERIFIED \| code.claude.com best-practices]; a plugin cannot ship permission rules [VERIFIED \| plugins-reference, as re-read in research/initial-harness/04] |
| D4 | Sandbox and least privilege | Shell runs in the operating-system sandbox with file and network isolation, required rather than optional; deny rules cover secrets | "sandboxing safely reduces permission prompts by 84%" [VERIFIED \| anthropic.com/engineering/claude-code-sandboxing \| 2025-10-20, extract] |
| D5 | Verification the agent runs itself | A fast check (seconds to about two minutes) that gates the stop, plus per-edit feedback and end-to-end checks; evidence shown, not claimed | "a Stop hook runs your check as a script and blocks the turn from ending until it passes" [VERIFIED \| code.claude.com best-practices] |
| D6 | Independent review | A reviewer in a fresh context that sees only the diff and the criteria, calibrated with examples and measured | "A reviewer running in a fresh subagent context sees only the diff and the criteria" [VERIFIED \| code.claude.com best-practices] |
| D7 | CI gate on the exact commit | The commit that lands is the commit that passed every required check, enforced by the server | earlier research: ci-and-github/00-decision.md, confirmed in 07-independent-review.md [VERIFIED as recorded there] |
| D8 | Evals of the AI parts | Each AI component has 20 to 50 cases from real failures, run several times, compared with no harness | "20-50 simple tasks drawn from real failures is a great start" [VERIFIED \| anthropic.com demystifying-evals \| 2026-01-09, extract]; `claude plugin eval` exists [VERIFIED \| code.claude.com/docs/en/plugin-evals] |
| D9 | Measurement | Per task: time, gate blocks, first-pass CI rate, escaped defects; the owner looks at them | Claude Code exports cost and token metrics through OpenTelemetry [VERIFIED \| code.claude.com/docs/en/monitoring-usage, extract]; standard harness metrics NOT FOUND |
| D10 | Defects become checks, and dead rules are removed | Each escaped defect becomes a regression test and, if needed, a check; rules that no longer earn their place are deleted | "prune it regularly … If Claude already does something correctly without the instruction, delete it or convert it to a hook" [VERIFIED \| code.claude.com best-practices] |
| D11 | Context and progress files | Each long task keeps a committed progress file; sessions cleared between tasks; the harness's own context cost is small | Anthropic's long-running harness kept `claude-progress.txt` committed [VERIFIED \| anthropic.com effective-harnesses \| 2025-11-26, extract] |
| D12 | Security | Secrets blocked and scanned on the server; untrusted content treated as hostile; actions and dependencies pinned and scanned | "Avoid piping untrusted content directly to Claude" [VERIFIED \| code.claude.com/docs/en/security]; gh-aw pins actions by commit hash [VERIFIED \| github/gh-aw architecture.mdx, full read] |
| D13 | Simplicity and standard components | Custom code only where nothing standard does the job; each component states its assumption and is re-tested when the model changes | Anthropic quotations in contradiction 2; "Keep that standalone setup while it serves one project or only you" [VERIFIED \| code.claude.com/docs/en/plugins/create] |
| D14 | Dogfooding | The harness's own repository runs under the harness, so its author feels every false block | A direct vendor statement: NOT FOUND. This dimension is [ASSUMPTION], supported by OpenAI building its harness inside the product it governs [VERIFIED \| openai.com harness-engineering, extract] |

## 2. harness-kit's score on each dimension

**Method.** Each score is my judgement [ASSUMPTION], built on the labelled evidence in the table. 9 means "matches what the best sources describe". I read the files; I did not run the harness.

| # | Score | Evidence | What it would take to reach 9 |
|---|---|---|---|
| D1 | **2** | No CLAUDE.md, AGENTS.md, STATE.md or DECISIONS.md. The README is 13 very long lines. [VERIFIED \| repository, 2026-09-30] | A map file of about 100 lines, `docs/STATE.md`, `docs/DECISIONS.md`, all committed; the backlog on GitHub Issues (file 06) |
| D2 | **6** | Strong: the brief skill has eight fixed sections, only you can start it (`disable-model-invocation: true`), `approve-brief.sh` records a checksum, and `brief-guard.mjs` stops Claude writing the approval. Weak: plan mode is blocked, briefs are never committed, and there is no light path for one-sentence changes. [VERIFIED \| brief/SKILL.md, hooks.json, .gitignore] | Commit approved briefs; decide on plan mode (contradiction 3); a named light path for tiny changes |
| D3 | **6** | Many PreToolUse hooks plus a Stop gate that fails closed on time. No permission-rule layer in harness-kit or in a consumer template. [VERIFIED \| hooks.json; no `.claude/settings.json`] | A committed `.claude/settings.json` and a template for consumer projects with deny rules, so hooks cover only what rules cannot |
| D4 | **2** | No sandbox setting anywhere. The reviewer agent is read-only by its tool list. [VERIFIED \| repository; agents/reviewer.md] | Sandbox required, network allowlist, deny rules for `~/.ssh` and `.env`: the person set this "before auto mode" as a trigger |
| D5 | **6** | Strong: the Stop gate runs the check, blocks rather than failing open, and skips when nothing changed. Weak: the full check took 358 to 379 seconds on the Mac against its own 120-second budget, and there is no per-edit feedback. [VERIFIED \| ci-process-overview; hooks.json has no PostToolUse] | Test files in parallel, or a fast tier under two minutes for the Stop gate |
| D6 | **6** | Strong: the reviewer starts every checklist item as FAILED and needs evidence, and `eval-reviewer.sh` exists. Weak: harness-kit has no `.harness/review-checklist.md` and no reviewer cases, so the reviewer cannot run on harness-kit itself. [VERIFIED \| agents/reviewer.md; `.harness/` listing] | A checklist for harness-kit and 10 to 15 reviewer cases from past branches |
| D7 | **4** | For an ordinary change the full replay runs only after `main` moves; `main` turned red 4 times on 28–29 September; no ruleset; actions named by movable tags; Node 22. [VERIFIED \| validate.yml; run data; 07-independent-review.md] | The ci-and-github changes: replay on every branch push, then a ruleset and pinned actions |
| D8 | **3** | The fault replay tests the tests (strong, but not an eval of AI behaviour); no `claude plugin eval` suite. [VERIFIED \| repository] | A small eval suite of the skills and the Stop-gate behaviour, 20 to 50 cases |
| D9 | **5** | A local event log with timings and budgets, and `harness-metrics.mjs` computing six numbers that print NOT FOUND instead of 0; no committed baseline; no cost records. [VERIFIED \| README; harness-metrics.mjs header] | Record the numbers at each release in the repository |
| D10 | **7** | `record-defect` turns an escaped bug into a failing test, a defect line and a fault proposal; `defects.tsv` is append-only and checked; 137 faults are replayed. No rule for retiring a gate. [VERIFIED \| record-defect/SKILL.md; defects.tsv] | A review date or retirement rule for each gate (the person's deferred "self-improving loop and pruning") |
| D11 | **4** | The session start-up picture shows the brief, the last check and replay age, but the overall plan lives in chat and the start-up picture adds many lines to every session. [VERIFIED for the hook; the plan location is the person's statement] | `docs/STATE.md` read and updated each session; a line budget for the start-up picture |
| D12 | **5** | Secrets blocked on write and scanned in CI; pushes and destructive git blocked. No sandbox, no pinned actions, no Dependabot file, no prompt-injection control. [VERIFIED \| hooks.json; repository] | Sandbox, pinned actions, Dependabot, GitHub secret scanning switched on |
| D13 | **3** | About 8,700 lines of scripts and 8,100 of tests for one part-time person; single scripts of 610 (`time-limit.mjs`), 685 (`replay-faults.mjs`) and 553 (`harness-metrics.mjs`) lines; all 8 recorded defects are in this machinery. [VERIFIED \| line counts, 07-independent-review.md X34; defects.tsv] | Stop adding machinery; replace custom parts where a standard one is equally strong (section 4) |
| D14 | **2** | No `.claude/settings.json`; no review checklist, protected paths or approval command for harness-kit itself. CI does check that the plugin loads headlessly. [VERIFIED \| repository; ci-process-overview] | Load the released plugin in harness-kit's own sessions, with the same `.harness/` files a consumer has |

**Overall today: 4.4 out of 10**, the plain average of the 14 scores. [ASSUMPTION: arithmetic on my judgement scores]

The pattern is more robust than the number. harness-kit scores 6 to 7 where it built custom deterministic machinery (D2, D3, D5, D6, D10). It scores 2 to 3 where the best harnesses rely on cheap standard pieces (D1, D4, D8, D14).

## 3. The path to 9/10

Each move below is [ASSUMPTION]. They are listed in the order in which they raise the average most for the least work. File 07 turns them into backlog items.

1. **Put the plan in the repository and run the harness on itself** (D1, D11, D14: +12 points in total, from 8 to 20 of 30). This means a map file, `docs/STATE.md`, `docs/DECISIONS.md`, the backlog on GitHub Issues, and the released plugin loaded in harness-kit's own sessions. It is small and mostly writing.
2. **Replay every fault before `main` moves** (D7: 4 to 8). This is one condition in `validate.yml`, plus a wait limit chosen from a measurement, as `research/ci-and-github/07-independent-review.md` recommends. Then add a ruleset on `main` and pin actions (D7 to 9, D12 to 7).
3. **Sandbox and permission rules** (D3 to 8, D4 to 8, D12 to 8). Your own trigger is "before auto mode". Waiting for it keeps D4 low.
4. **Evals of the AI parts** (D6 to 8, D8 to 7). Reviewer cases from 10 to 15 past branches (your planned E6), then a small `claude plugin eval` suite before the next change to any AI part (your trigger).
5. **Simplify** (D13 to 6 or 7), as listed in section 4.
6. **Measurement at release and a retirement rule for gates** (D9 to 7, D10 to 9).

**Realistic ceiling for one part-time person.** Reaching 9 on D8 (evals) and D9 (measurement) needs steady effort that a solo part-time project may not repay. After the six moves the average would be about 7.5 to 8. Reaching 9 overall needs the deferred items as well: full evals, pruning, and a second project to prove the harness is reusable. [ASSUMPTION]

**What would change this.** If a controlled comparison (the same tasks with and without harness-kit) showed that a dimension I score low does not change outcomes, its weight should fall. No such comparison exists for any harness. [NOT FOUND]

## 4. Over-engineered parts, and standard or free replacements

Each item is [ASSUMPTION] unless labelled. These build on `research/ci-and-github/05-mapping.md` and do not repeat it.

| Part | Why it looks over-engineered | Standard or free replacement | Strongest counter-case |
|---|---|---|---|
| `plan-mode-guard.mjs` | Blocks the planning tool both vendors recommend | Allow plan mode and have it produce the brief, or keep the block and document why | The block exists because a bare `/plan` once started work on `main` without an approved brief; after the rename to `/harness-kit:brief` that collision is gone, but plan mode's approval still leaves no checksum |
| `time-limit.mjs` (610 lines) and its sweep registry | Produced defects D2 to D5 | `timeout-minutes` in CI; the hook `timeout` field; GNU `timeout` for scripts | Hook timeouts fail open, and plain `timeout` does not kill whole process groups or clean worktrees; you already decided to freeze this code after the essentials |
| `guard-secrets.mjs` scan mode | Hand-written patterns (about 15 shapes) | gitleaks in CI (no licence key needed on a personal account) and GitHub secret scanning | The pre-write block has no standard replacement: keep that part |
| `reviewer-guard.mjs` | The reviewer's `tools` and `disallowedTools` already make it read-only | Remove the guard | A second layer catches a Claude Code bug that re-grants tools |
| `harness-metrics.mjs` (553 lines) | No baseline has ever been written in harness-kit | Keep only the numbers that change decisions: escaped defects and first-pass CI rate | Six numbers cost little once written |
| The start-up picture | Every line costs context in every session | A line budget | It is your main reminder of state until `docs/STATE.md` exists |

**Not over-engineered, and supported by the sources:**
- the fault replay;
- `record-defect` and the append-only defect log;
- the brief with checksum approval;
- `git-guard.mjs`, which blocks push forms that native deny rules miss [VERIFIED | code.claude.com/docs/en/permissions, as checked in ci-and-github/07-independent-review.md];
- the Stop gate's fail-closed timing.

## Negative results

- A maturity model or scored checklist from Anthropic, OpenAI or GitHub: NOT FOUND.
- A controlled with-and-without evaluation of any complete coding harness: NOT FOUND.
- A published harness that replays a curated list of planted faults in CI: NOT FOUND (as in ci-and-github).
- A vendor statement that a harness's repository must run its own harness: NOT FOUND.
- The Codex AGENTS.md guide page, marmelab's 2026 survey, and the full OWASP and DORA lists on their own pages: not read.
- Whether `ship.sh` blocks on the reviewer's verdict: not checked (headers only).

## Strongest counter-cases

- **The 9/10 picture is vendor-shaped.** Anthropic, OpenAI and GitHub sell the standard components recommended here. Their advice to use them is not neutral.
- **OpenAI's scale does not transfer.** Its harness served a team producing about a million lines. Much of that (per-worktree observability, cleanup agents) would be over-engineering for one part-time person.
- **Your custom gates caught real faults.** The CI replay found D6 (a fault that changed nothing) and D8 (a Stop-gate skip that failed open). Removing custom machinery must therefore be selective.
- **Scores are judgement.** Two reviewers could differ by one or two points on any dimension. Trust the ranking, not the decimal.

**Confidence.** Medium in the ranking (strong on custom gates, weak on memory, sandbox, evals and dogfooding). Low in any single number.

**Who should do it.** The changes are repository work with tests and CI, so Claude Code inside the harness-kit folder is the right tool. Cowork was right for this research because it combined the web, your files and GitHub's public data. [ASSUMPTION]
