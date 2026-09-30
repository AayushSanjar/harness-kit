# 00 — Decision summary: repository structure, test files, and keeping documents true

Status on 30 September 2026. Research only: no repository was changed.

**Terms.** A *living document* must match today's code (README, CLAUDE.md, skills); a *dated record* describes one date and is replaced, never rewritten; a *generated section* is written from the code by a script and checked; a *planted fault* is a deliberate break a test must catch. [VERIFIED]: primary source, with link and date; [PARTIAL]: secondary or partial; [ASSUMPTION]: my inference.

**Evidence.** Files 01 to 07 cite 186 distinct sources, 184 of them primary, chosen from those your question named, then each tool's own documentation and release pages; research sub-agents read about 650 pages. I re-read every source a recommendation rests on, measured harness-kit at commit `e275280`, and ran two worked examples in a scratch copy.

## CONTRADICTIONS

1. **Drift is in hand-kept lists, numbers and indexes, not prose.** Every number in harness-kit's README matches the code. What drifted: the gadget's `CLAUDE.md` lists 6 of harness-kit's 9 hooks; the research index omits `design/`; case numbers collided, skipped or fell out of order in five test files and `validate.sh`. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured] [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context]
2. **Tests are long because files test several scripts, not because of copying.** Copied lines are 2.6%; `ship.test.sh` tests seven scripts; 288 of about 295 cases type their label twice; one helper is copied into all 20 files. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
3. **Google's shell guide says scripts over 100 lines should be rewritten in another language;** 13 of harness-kit's 16 plugin shell scripts and 18 of its 20 test files exceed that. git's shell tests show it can work; I do not recommend a rewrite. [VERIFIED | google.github.io/styleguide/shellguide.html | accessed 2026-09-30 | extract]
4. **harness-kit's public `research/` already holds gadget product research** (Forge testing, the cycle-time chart); moving it leaves it in public history. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
5. **OpenAI's doc-gardener needs no human approval** ("Humans may review pull requests, but aren't required to"), and the Claude Code GitHub Action opens no pull request by default; neither fits your approve-everything model. [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract] [VERIFIED | github.com/anthropics/claude-code-action/blob/main/docs/faq.md | accessed 2026-09-30 | extract]
6. **Link checkers and prose linters find little of use here:** the markdown has no links, and markdownlint's defaults report 3,066 issues, 83% about line length. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured]
7. **The gadget's folder was connected, although you wrote that I cannot read it;** its `CLAUDE.md` loaded automatically (seen), and I opened nothing else.

## Recommendation

[ASSUMPTION, built on files 01 to 06, for this and both sections below.] Generate and check, or delete, every list, number and index a document shares with the code; give each script one test file; let AI gardening report, never merge. **Against it:** your plan stops to re-evaluate after the speed and CI work; weigh these small steps there. **Who should do them:** Claude Code in each repository, under your brief-and-approve process, since each step edits files there and must pass its checks; Cowork suited only the research. Later steps and fuller counter-cases are in file 07.

## harness-kit

- Sort files into living documents, dated records and working notes.
- Tests: one file per script, named after it; one shared file of helper functions, as git does; the label as each case's only name. No move to bats or ShellSpec.
- Research: one topic sub-folder each, with a status line in its `00-decision.md` and an index kept complete by a check; the first research's files stay where they are.
- Record which test cases fail for each planted fault; report the cases no fault makes fail, and the eight scripts without a planted fault.
- AI gardening: deterministic checks first, then a pass you start before adopting each batch of harness-kit changes into the gadget (`/doctor prompt-audit` and Anthropic's comment-analyzer, which only report). No scheduled agent yet; nothing merges without you.

**First three steps, run in the harness-kit repository.** Only steps 1 and 3 were tried, in a scratch copy. [VERIFIED | github.com/AayushSanjar/harness-kit | commit e275280, 2026-09-30 | measured in a scratch copy]

1. **Stop hand-numbering:** delete case numbers and section letters from comments only. *Test:* the same PASS and FAIL output (in the scratch copy, `stop-gate.test.sh` lost its 25 case numbers and printed the same 26 lines); no fault's find text contains them (0 of 137). *Counter-case:* "case 12" is easier to say than a label.
2. **Check that every test file runs:** `validate.sh` compares the files it runs with `tests/*.test.sh`. *Test:* it should pass today and fail on a planted missing line. *Counter-case:* letting it find the files itself removes the hand list, but changes the run order.
3. **Generate the README's hook and limit tables** with `tools/gen-docs.mjs` (58 lines, no dependency), check them in `validate.sh`, and cut the `hooks.json` description to one sentence. *Test:* in the scratch copy, changing one timeout made the check fail and name the fix. *Counter-case:* for two short lists, deleting them and pointing to the code is cheaper.

## control-chart-gadget

Moved on 30 September 2026 to the private control-chart-gadget repository, `research/repo-structure-and-docs/00-decision.md`.
