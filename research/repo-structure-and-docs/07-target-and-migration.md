# 07 — Target structure, policies, drift checks and migration, with worked examples (research question G)

Status on 30 September 2026. Research only: no repository was changed. The worked examples were built and run in a scratch copy of harness-kit in my cloud workspace, never in your repositories.

## Terms used in this file

- **Target structure:** the folder and file layout this file recommends reaching, step by step.
- **Migration step:** one small change, made on its own branch from its own brief, with its own test, that can be undone by reverting one commit.
- **Living document, dated record, generated section, check mode:** as defined in files 01 and 03.
- **Test helper library:** one file of shared test functions that every test file loads (file 02).
- **Kill matrix:** which test cases fail for which planted fault (file 04).
- **Scratch copy:** a throwaway copy of the repository where I tried the examples.
- **Protected file:** a file that Claude may not change directly; in the gadget, changes to it come as a patch that you apply with `scripts/land.sh`.
- **You and Claude Code:** in each step, "Claude Code" means a Claude Code session in the named repository doing the work under your normal brief-and-approve process; "you" means the steps you already run yourself (approving the brief, `land.sh`, `ship.sh`, `release.sh`).

## How this file is based on evidence

- **Sources.** This file cites 6 sources, 5 of them primary. It builds on files 01 to 06 and does not repeat their evidence; each recommendation points back to the file that supports it.
- **What I ran.** In a scratch copy of harness-kit at commit `e275280` I (1) moved the test helpers into a library and converted `tests/stop-gate.test.sh` to use it, then compared its output with the unchanged file's, and (2) wrote a README generator with a check mode, generated two tables, and planted a drift to see the check fail. The outputs are quoted below. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy]
- **What I could not see.** For control-chart-gadget I used only its `CLAUDE.md`, which this session loaded automatically. Everything about its tests below is labelled as an assumption about a Forge app of its type.
- **Labels** are as in file 01. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS that shape the migration

1. **Splitting a test file moves case labels, and case labels are keys.** `.harness/check-files` maps each check name to its test file, and a targeted replay runs only that file. After a split, a name whose file moved but whose map line did not is no longer targeted: `validate.sh --only` prints "lists no test file for …, so the whole check runs". Nothing breaks, but that replay quietly becomes a full-check run, which is the slowness you have spent a week removing. The map must change in the same commit as the split. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of tests/validate.sh]
2. **Test-file changes interact with the CI redesign.** The ci-and-github research starts by measuring each test file's time and running test files in parallel. [PARTIAL | harness-kit/research/ci-and-github (local, untracked) | 2026-09-30 | full for 00-decision.md] Splitting files changes those times, and more, smaller files balance better across parallel workers. Do the splits (step 6 below) after the CI redesign's measurement step, or measure again after them. [ASSUMPTION]
3. **No step below touches the process-management code you froze** (timers, sweeps, registries, process groups). The generator only reads the exported values in `time-limit.mjs`; it does not change them. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of the exports in time-limit.mjs]

## harness-kit

### Target structure

```
harness-kit/
├── README.md                      living: what it is, how to install, how to release;
│                                  generated tables of hooks and limits (worked example 2)
├── .claude-plugin/marketplace.json
├── plugins/harness-kit/           SHIPPED to users; unchanged in layout
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json           "description" cut to one sentence
│   ├── agents/reviewer.md
│   ├── skills/brief/, skills/record-defect/
│   └── scripts/                   runtime scripts, each opening with a header comment
├── tests/                         NOT shipped
│   ├── lib/test-lib.sh            new: result, verdict, describe, finish (worked example 1)
│   ├── <script>.test.sh           one file per script under test, named after it
│   ├── validate.sh                the runner; checks that every tests/*.test.sh is run
│   └── claude-builtins.txt
├── tools/                         new, NOT shipped: repository maintenance
│   └── gen-docs.mjs               writes and checks README's generated sections
├── .harness/                      unchanged; flaky tests recorded in defects.tsv
├── research/                      NOT shipped
│   ├── README.md                  index: one row per topic, with date and status; checked
│   ├── 00-glossary.md … 07-open-questions.md, sources.csv   topic 1 (26 September), left in place
│   ├── design/                    topic 2 (27 September)
│   ├── ci-process-overview/       topic 3 (30 September)
│   ├── ci-and-github/             topic 4 (30 September)
│   └── repo-structure-and-docs/   topic 5 (this research)
└── .github/workflows/validate.yml CI (the ci-and-github research's scope)
```

Why each change (details in the files named): [ASSUMPTION: my proposals, each resting on the evidence in the file named]
- `tests/lib/` and one test file per script: git's and Node.js's practice; removes 20 copies of one helper and 288 doubly typed labels (file 02).
- `tools/`: maintenance code stays out of what users install, as in ESLint and Node.js (file 01).
- Generated README tables: the only drift found in harness-kit's own documents is in hand-kept lists and numbers (file 03).
- The research index with status lines: the index went stale within a day, and a reader cannot tell a superseded proposal from a current one (file 01).
- A `LICENSE` file is not in the tree: harness-kit has none today, so others may read it but have no permission to reuse it. Whether to add one is your decision; it is outside this research's questions. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]

### Test files after the splits

[VERIFIED for the case counts | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured from label prefixes; the split itself is my proposal, ASSUMPTION]

| Today | Cases | After |
|---|---|---|
| `ship.test.sh` | 45 | `ship.test.sh` (23), `land.test.sh` (8), `session-start.test.sh` (8), `install-hooks.test.sh` (2), `approve-brief.test.sh` (2), `report-path.test.sh` (1), `check-reports.test.sh` (1) |
| `replay-faults.test.sh` | 39 | `replay-faults.test.sh` (33, including the two `validate.sh --only` cases), and 6 cases into `land.test.sh`, which then has 14 |
| `session-start.test.sh` | 15 | renamed `start-picture.test.sh` (13 start-up picture cases, since it tests `start-picture.mjs`); its 2 session-start cases join `session-start.test.sh` |
| `review.test.sh` | 21 | `review.test.sh` (12), `check-reviewed.test.sh` (5), `reviewer-guard.test.sh` (4) |
| `time-limit.test.sh` | 16 | `time-limit.test.sh` (12), `check-limits.test.sh` (4) |
| `brief-guard.test.sh` | 4 | `brief-guard.test.sh` (3); its git-guard case joins `git-guard.test.sh` |
| the other 14 files | | unchanged |

About 29 test files, each named after the one script it tests; the largest, `ship.test.sh`, keeps 23 cases.

### Rules for test files

1. One test file per script under test, named `<script>.test.sh`. A thin wrapper tested together with its script may stay in that file, if the file's header says so.
2. Every test file starts by sourcing `tests/lib/test-lib.sh`, and its header comment says which script it tests and what fakes it uses.
3. A case's label is its only name: it starts with the script's name, it says the behaviour, and it is typed once. No case numbers or section letters.
4. Cases build fresh fixtures; the library provides only the shared parts (printing results, describing a failed run, git settings that make test repositories independent of your own, a local bare repository to act as `origin`).
5. A case holds straight-line checks; loops and flags belong in helpers (Google's rule, file 02).
6. When a script gets a planted fault, the fault names a case in that script's test file, and `.harness/check-files` maps it there in the same commit.

### Comment and documentation policy

The full text is in file 03, section 7. In one paragraph: every script opens with a header comment (what it is for, how it is run, what it prints and exits with); other comments explain why, never repeat what the next line does or copy a value defined in code, and cite only evidence that is tracked in the repository; the story of a change lives in the commit message; living documents are few, change in the same commit as the code, and have their lists generated and checked; research and decisions are dated records with a status line, replaced rather than rewritten.

### Drift checks, in the order to add them

| Order | Check | Added in step |
|---|---|---|
| 1 | Every `tests/*.test.sh` file is run by `validate.sh` | 2 |
| 2 | README's generated sections match the code (`node tools/gen-docs.mjs --check`) | 3 |
| 3 | `research/README.md` lists every topic folder, and every topic's `00-decision.md` has a status line | 4 |
| 4 | Names in living documents resolve (`.harness/` files are read by a script; named scripts exist or are listed consumer scripts), and no comment cites a `.reports/` file | 5 |
| 5 (report, not a gate) | Test-health report from the kill matrix | 7 |
| 6 (occasional, never blocking) | Online check of the addresses in `sources.csv` | later, if wanted |

### The AI gardener: whether and how

Not as a scheduled agent yet. First the deterministic checks above; then a person-started gardening pass before each batch adoption (step 8); then, only if its findings prove useful, a skill only you can start; and, optionally, a weekly issue-only run in harness-kit's public CI. Never automerge. The evidence and the stages are in file 05, section 8.

### Worked example 1: one test file, before and after

**Before** — `tests/stop-gate.test.sh` at commit `e275280`, lines 21 to 79 (excerpt):

```bash
failures=0

result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}
# ... new_project and run_gate, which stay in this file ...
is_block() { grep -q '"decision":"block"' <<<"$1"; }
describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# 1. No config file: exit 0, one stderr line, no decision.
dir="$(new_project no-config)"
run_gate "$dir" s-none false
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] &&
  [ "$ERR" = "harness-kit: no .harness/check-command, so the stop gate is off" ]; then
  result "no .harness/check-command: exit 0, gate off" yes ""
else
  result "no .harness/check-command: exit 0, gate off" no "$(describe)"
fi

# 2. Passing command: exit 0 silently.
dir="$(new_project passing 'echo "PASS everything"; exit 0')"
run_gate "$dir" s-pass false
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  result "passing check: exit 0 silently" yes ""
else
  result "passing check: exit 0 silently" no "$(describe)"
fi
```

What is wrong with it, by the rules in file 02: `result` and `describe` are copies of code that 19 other files also copy; each label is typed twice; each case carries a hand-written number that nothing reads, and in five other files such numbers have already collided, skipped or fallen out of order.

**After** — the new shared library, `tests/lib/test-lib.sh`:

```bash
# Shared helpers for harness-kit's test files. Each test file sources this first:
#   . "$ROOT/tests/lib/test-lib.sh"
# It prints one PASS or FAIL line per case; the label is the case's name and its only id.
failures=0

# result LABEL yes|no DETAIL: print PASS LABEL, or FAIL LABEL with DETAIL indented.
result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}

# describe: the last run's exit status and output, for a FAIL line. A file whose runs set
# other variables defines its own describe after sourcing this file.
describe() { printf 'exit %s\nstdout: %s\nstderr: %s' "$STATUS" "$OUT" "$ERR"; }

# verdict LABEL [DETAIL]: PASS when the command just before it succeeded, else FAIL with
# DETAIL (default: describe). Call it on the line right after the condition: it reads that
# condition's exit status ($?), so nothing may run in between.
verdict() {
  local status=$? label="$1"
  if [ "$status" -eq 0 ]; then result "$label" yes ""; else result "$label" no "${2-$(describe)}"; fi
}

# finish: the test file's exit status, 0 when no case failed.
finish() { [ "$failures" -eq 0 ]; }
```

**After** — the same part of `tests/stop-gate.test.sh`:

```bash
. "$ROOT/tests/lib/test-lib.sh"
# ... new_project and run_gate, unchanged ...
is_block() { grep -q '"decision":"block"' <<<"$1"; }

# No config file: exit 0, one stderr line, no decision.
dir="$(new_project no-config)"
run_gate "$dir" s-none false
{ [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] &&
  [ "$ERR" = "harness-kit: no .harness/check-command, so the stop gate is off" ]; }
verdict "no .harness/check-command: exit 0, gate off"

dir="$(new_project passing 'echo "PASS everything"; exit 0')"
run_gate "$dir" s-pass false
{ [ "$STATUS" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }
verdict "passing check: exit 0 silently"
```

The comment above the second case is gone because the label already says it; the comment above the first stays because it adds "one stderr line, no decision". A Java comparison: `verdict` plays the part of `assertTrue(message, condition)`, and the library is the shared test-utilities class.

**The proof.** In the scratch copy, a script converted the file mechanically: it sourced the library, deleted the two copied helpers, turned the 7 cases with the simple if-else shape into `verdict` lines and removed all 25 case numbers. The file went from 577 to 544 lines. It ran with the same 26 result lines, in the same order, as the unchanged file: 25 PASS and the one container-specific FAIL described in file 02, section 7. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy]

What this does not do: it barely shortens the file (6%). The length problem is solved by the splits, not by the library; the library removes copies and the doubly typed labels.

The trap to know about: `verdict` reads `$?`, the exit status of the command just before it, so nothing may run between the condition and `verdict`. The test files use `set -u` and not `set -e`, which is what makes this work. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | full read of the head of tests/stop-gate.test.sh]

### Worked example 2: one document, before and after

**Before** — `README.md` line 9 (one line, 1,244 characters):

> Every long-running step the harness starts runs under a hard time limit, through one helper, `plugins/harness-kit/scripts/time-limit.mjs`: the check (540 s), a reviewer run (900 s), a wait on one CI run (900 s), a gh read (60 s), a git push, fetch or ls-remote (300 s, and without prompts), and upgrade.sh's plugin commands and headless session (120 s each). Past its limit, a step's whole process group is stopped (SIGTERM, then SIGKILL 10 s later) and reported as TIMEOUT; each limit can be overridden by its environment variable, listed in the helper's header. The Stop hook stops its check at 540 s, before its own 600-second limit, so it blocks rather than lets Claude stop unchecked. [...]

and line 11, which lists the four budgets and their four environment variables in prose. The same numbers are written a third time in the header comment of `time-limit.mjs`, and a fourth time in the `LIMITS` and `BUDGETS` objects that the code actually uses. The hooks are not listed in the README at all; they are described in a 1,918-character `description` field inside `hooks.json`. Today every number agrees (file 03); nothing keeps them agreeing.

**After** — the README keeps one plain sentence and a generated table:

```markdown
Every long-running step runs under a hard time limit, through one helper,
`plugins/harness-kit/scripts/time-limit.mjs`; past its limit, the step's whole process
group is stopped and reported as TIMEOUT. The limits and budgets, from the helper itself:

<!-- BEGIN GENERATED: limits -->
| Name | Kind | Seconds | Overridden by |
|---|---|---|---|
| check | hard limit | 540 | `HARNESS_KIT_LIMIT_CHECK_SECONDS` |
| review | hard limit | 900 | `REVIEW_MAX_SECONDS` |
| ci-run | hard limit | 900 | `SHIP_CI_RUN_SECONDS` |
| gh-read | hard limit | 60 | `SHIP_GH_READ_SECONDS` |
| git | hard limit | 300 | `HARNESS_KIT_LIMIT_GIT_SECONDS` |
| plugin-command | hard limit | 120 | `UPGRADE_PLUGIN_SECONDS` |
| init | hard limit | 120 | `UPGRADE_INIT_SECONDS` |
| start-ci-read | hard limit | 5 | `HARNESS_KIT_LIMIT_START_CI_SECONDS` |
| grace period | SIGTERM to SIGKILL | 10 | `HARNESS_KIT_LIMIT_GRACE_SECONDS` |
| check | budget (warns only) | 120 | `HARNESS_KIT_BUDGET_CHECK_SECONDS` |
| replay | budget (warns only) | 180 | `HARNESS_KIT_BUDGET_REPLAY_SECONDS` |
| ship | budget (warns only) | 600 | `HARNESS_KIT_BUDGET_SHIP_SECONDS` |
| release | budget (warns only) | 600 | `HARNESS_KIT_BUDGET_RELEASE_SECONDS` |
<!-- END GENERATED: limits -->

## Hooks

<!-- BEGIN GENERATED: hooks -->
| When | Tools matched | Script | Timeout (seconds) |
|---|---|---|---|
| SessionStart | (no matcher) | `session-start.mjs` | Claude Code's default |
| Stop | (no matcher) | `stop-gate.mjs` | 600 |
| PreToolUse | Write, Edit, MultiEdit, NotebookEdit | `guard-secrets.mjs` | Claude Code's default |
| PreToolUse | Write, Edit, MultiEdit, NotebookEdit | `brief-guard.mjs` | Claude Code's default |
| PreToolUse | Bash | `guard-secrets.mjs` | Claude Code's default |
| PreToolUse | Bash | `git-guard.mjs` | Claude Code's default |
| PreToolUse | Bash | `background-guard.mjs` | Claude Code's default |
| PreToolUse | Bash | `predeploy-gate.mjs` | 600 |
| PreToolUse | EnterPlanMode | `plan-mode-guard.mjs` | Claude Code's default |
| PreToolUse | Write, Edit, MultiEdit, NotebookEdit, Bash, WebFetch, WebSearch | `reviewer-guard.mjs` | Claude Code's default |
<!-- END GENERATED: hooks -->
```

The two tables above are the real output of the generator on harness-kit at `e275280`, not typed by hand. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy] What each hook enforces can then sit in one short line per hook under the table, or stay in each script's header comment; the `description` field in `hooks.json` shrinks to one sentence that points to the README. The limits' evidence, now cited to `.reports/` files that are not in the repository, moves to the commit that set each value.

**The generator,** `tools/gen-docs.mjs` (58 lines, Node only, no dependency):

```javascript
#!/usr/bin/env node
// Writes the generated sections of README.md from the code; with --check, changes nothing
// and exits 1 when a section differs from what the code says. A generated section sits
// between "<!-- BEGIN GENERATED: NAME -->" and "<!-- END GENERATED: NAME -->".
//   node tools/gen-docs.mjs            rewrite the sections
//   node tools/gen-docs.mjs --check    fail if any section is stale (tests/validate.sh runs this)
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const plugin = join(root, "plugins", "harness-kit");
const { LIMITS, GRACE, BUDGETS } = await import(pathToFileURL(join(plugin, "scripts", "time-limit.mjs")).href);

// One row per hook script that hooks.json registers, in the file's order.
const hooks = () => {
  const { hooks: events } = JSON.parse(readFileSync(join(plugin, "hooks", "hooks.json"), "utf8"));
  const rows = [];
  for (const [event, groups] of Object.entries(events))
    for (const group of groups)
      for (const hook of group.hooks)
        rows.push(`| ${event} | ${group.matcher ? group.matcher.split("|").join(", ") : "(no matcher)"} | \`${hook.args.at(-1).split("/").pop()}\` | ${hook.timeout ?? "Claude Code's default"} |`);
  return ["| When | Tools matched | Script | Timeout (seconds) |", "|---|---|---|---|", ...rows].join("\n");
};

// One row per named time limit and budget in time-limit.mjs.
const limits = () => [
  "| Name | Kind | Seconds | Overridden by |",
  "|---|---|---|---|",
  ...Object.entries(LIMITS).map(([name, l]) => `| ${name} | hard limit | ${l.seconds} | \`${l.env}\` |`),
  `| grace period | SIGTERM to SIGKILL | ${GRACE.seconds} | \`${GRACE.env}\` |`,
  ...Object.entries(BUDGETS).map(([name, b]) => `| ${name} | budget (warns only) | ${b.seconds} | \`${b.env}\` |`),
].join("\n");

const SECTIONS = { hooks, limits };
const file = join(root, "README.md");
const text = readFileSync(file, "utf8");
const check = process.argv.includes("--check");
let out = text;
const stale = [];
for (const [name, render] of Object.entries(SECTIONS)) {
  const re = new RegExp(`(<!-- BEGIN GENERATED: ${name} -->\\n)([\\s\\S]*?)(<!-- END GENERATED: ${name} -->)`);
  const m = re.exec(out);
  if (!m) { stale.push(`${name}: no BEGIN/END GENERATED markers in README.md`); continue; }
  const want = `${render()}\n`;
  if (m[2] !== want) stale.push(name);
  out = out.replace(re, `$1${want}$3`);
}
if (check) {
  if (stale.length > 0) {
    console.log(`README.md: generated section(s) out of date: ${stale.join(", ")}. Run: node tools/gen-docs.mjs`);
    process.exit(1);
  }
  console.log(`README.md: ${Object.keys(SECTIONS).length} generated sections match the code`);
} else {
  writeFileSync(file, out);
  console.log(`README.md: ${stale.length} section(s) rewritten`);
}
```

**The proof,** from the scratch copy: [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy]

```
first --check, sections still empty:   README.md: generated section(s) out of date: hooks, limits. Run: node tools/gen-docs.mjs   (exit 1)
after generating:                      README.md: 2 generated sections match the code                                          (exit 0)
Stop hook timeout changed to 601:      README.md: generated section(s) out of date: hooks. Run: node tools/gen-docs.mjs          (exit 1)
```

The failure message names the fix, which is the practice your first research recorded for OpenAI's linters (principle P8). [VERIFIED | github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/01-principles.md | 2026-09-26 | full]

### Migration steps for harness-kit

Safest and most valuable first. Each step is one branch, one brief (`/harness-kit:brief`), one concern, run in the repository `harness-kit` (folder `harness-kit/` on your Mac). "Test" is what Claude Code runs and shows you; "Undo" is one revert. [ASSUMPTION: all steps are proposals]

**Step 1 — Stop hand-numbering.**
- *Today:* case numbers in test comments and section letters in `validate.sh` have already collided, skipped or fallen out of order in six files.
- *Change:* delete the numbers and letters from comments only; no code changes.
- *After:* nothing left to drift; cases are named by their labels.
- *Test:* every test file prints the same PASS and FAIL lines, in the same order, before and after. No fault's find text contains a numbered comment, so the fault list is untouched (I checked: 0 of 137 do). [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
- *Counter-case:* "case 12" is handy in conversation; the label is longer to say.

**Step 2 — Check that every test file runs.**
- *Today:* `validate.sh` runs each of the 20 files by a hand-written line; nothing notices a 21st file that has no line.
- *Change:* a few lines in `validate.sh` that compare the files it runs with `tests/*.test.sh` and fail on any difference, plus one planted fault that removes a file's line and must be caught.
- *After:* a new test file cannot silently never run.
- *Test:* the check passes on today's tree and fails on the planted fault.
- *Counter-case:* letting `validate.sh` discover the files itself would remove the hand list completely, but changes the order in which files run; this step keeps the order and adds only the check.

**Step 3 — Generate the README's lists from the code.**
- *Today:* limits and budgets written in prose in the README, again in a comment, and in the code; hooks described in a 1,918-character field inside `hooks.json`.
- *Change:* `tools/gen-docs.mjs` (worked example 2), two generated tables in the README, the `hooks.json` description cut to one sentence, and `node tools/gen-docs.mjs --check` in `validate.sh`, with a planted fault that changes a timeout without regenerating.
- *After:* the README's lists cannot disagree with the code without the check failing; consumers such as the gadget can point to one table.
- *Test:* the check passes after generation and fails on the planted drift, with the message naming the fix.
- *Counter-case:* markers and a generator to maintain; if you prefer, delete the lists and point to `time-limit.mjs` instead, which cannot drift at all.

**Step 4 — Index the research, with status lines.**
- *Today:* the index lists only the first topic; nothing marks which proposals were superseded.
- *Change:* one row per topic folder in `research/README.md` (date, status, where its decision lives), a status line at the top of each topic's `00-decision.md`, and a small check that every topic folder has a row. The first topic's files stay where they are, because the append-only defect log cites one of them by path.
- *After:* a reader, or Claude, can tell current research from history at a glance.
- *Test:* the check passes, and fails on a planted topic folder with no row.
- *Counter-case:* one more file to keep; without the check, skip the index and rely on folder names.

**Step 5 — Check the names in living documents.**
- *Today:* all names resolve (file 03), but nothing would notice if a script or `.harness/` file were renamed and a document were not.
- *Change:* a check that every `.harness/<file>` named in the README, skills, agent and `hooks.json` is read by some script, and every script named there exists or is on a short list of consumer-project scripts; plus a check that no comment cites a `.reports/` file, after moving the four existing citations to their commits.
- *After:* renames cannot leave living documents pointing at nothing.
- *Test:* passes today; fails on planted renames.
- *Counter-case:* the consumer-script list is itself hand-kept; keep it next to git-guard's list of your scripts, which already names them.

**Step 6 — Shared helper library, then split the multi-script test files** (after the CI redesign's measurement step).
- *Today:* one helper copied into 20 files; three files test several scripts; `land.sh` is tested in two files.
- *Change, in separate commits:* add `tests/lib/test-lib.sh` and convert files one at a time; then split `ship.test.sh`, `replay-faults.test.sh`, `session-start.test.sh`, `review.test.sh`, `time-limit.test.sh` and `brief-guard.test.sh` as in the table above, changing `.harness/check-files` in the same commit as each split.
- *After:* about 29 test files, each named after its script; one place to change a shared helper.
- *Test:* for each commit, the union of PASS lines is identical before and after; `validate.sh --only <name>` finds the new file for every moved name; a targeted replay of the moved faults gives the same verdicts.
- *Counter-case:* the largest diff in this plan; the shared fakes in `ship.test.sh` must move into the library first, or they will be copied seven times.

**Step 7 — Record the kill matrix and print a test-health report.**
- *Today:* each fault proves one named case; 181 of 293 cases are named by no fault; eight scripts, two of them guards, have no planted fault.
- *Change:* keep every FAIL line a replay prints, and add `tools/test-health.mjs` to report cases no fault reaches, faults caught by exactly one case, and scripts with no fault. If the replay already saves each run's full output, the report can read it without touching the replay; if not, recording it changes a replay-machinery file, which by your rule means a full replay for that branch.
- *After:* you can see which tests matter most and which may be dead weight, and the deletion rule in file 04 has its evidence.
- *Test:* on a small replay, the matrix lists every failing case per fault, and the report names the eight scripts.
- *Counter-case:* the faults are hand-picked, so "caught by no fault" can mean a missing fault rather than a useless test.

**Step 8 — The first gardening pass** (before the next batch adoption; no code change).
- *Change:* in harness-kit, run `/doctor prompt-audit` and the comment-analyzer agent over the scripts changed since the last pass; Claude writes one report in `.reports/` with a file, a line and quoted evidence for each finding; you choose which become a brief; the report counts accepted and rejected findings.
- *Counter-case:* it costs reading time and model usage, and a reviewing agent tends to find something; the counts will show whether it earns its place.

## control-chart-gadget

Moved on 30 September 2026 to the private control-chart-gadget repository, `research/repo-structure-and-docs/07-target-and-migration.md`.

## Negative results

- A way to split test files that keeps targeted replays targeted without changing `.harness/check-files`: NOT FOUND; the map must move with the cases.
- Where the gadget's tests live and which runner they use: NOT FOUND (not visible to me).
- Whether the replay already saves every case's output line: NOT CHECKED; step 7 depends on it.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **Against doing any of this now:** your agreed plan is to finish the speed work and the CI redesign, then stop and re-evaluate before more harness work. Every step here is harness work. The counter: steps 1 to 5 are small, independent and mostly documentation, and step 3 removes the class of drift that prompted this research; steps 6 and 7 can wait for the re-evaluation.
- **Against the library and the splits:** a large diff in the test suite that every future change depends on, for a gain in navigation rather than in bugs caught.
- **Against generated documentation:** for two short tables, deleting the lists and pointing to the code is cheaper and cannot drift; the generator pays only if more lists follow.
- **Against the gadget steps:** the gadget adopts harness-kit in batches; changing its `CLAUDE.md` outside an adoption batch adds a branch. Fold G2 into the next adoption batch.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- Best practices for Claude Code. https://code.claude.com/docs/en/best-practices. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- ci-and-github research: 00-decision.md, and sections of 04, 05 and 07. harness-kit/research/ci-and-github (local, untracked). Cowork research job for the same person; 2026-09-30; secondary; read: full for 00-decision.md; extract for the others.
- control-chart-gadget CLAUDE.md, version 4.3. control-chart-gadget/CLAUDE.md (private repository). the person (private repository); 2026-09-28; primary; read: seen in context: loaded automatically by this session, not opened by me.
- harness-kit repository at commit e275280 (v0.20.0): files read and measured by me. https://github.com/AayushSanjar/harness-kit. AayushSanjar (harness-kit); commit dated 2026-09-30; primary; read: full for the files named in the text; measured for counts.
- harness-kit research 01: harness engineering principles. https://github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/01-principles.md. AayushSanjar (harness-kit); 2026-09-26; primary; read: full.
- How Claude remembers your project (CLAUDE.md, /doctor prompt-audit). https://code.claude.com/docs/en/memory. Anthropic; undated; accessed 2026-09-30; primary; read: full.
