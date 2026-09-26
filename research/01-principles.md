# 01 — Harness engineering principles (status on 26 September 2026)

**Sources and how they were selected.** This file cites 29 sources, selected in this order: Anthropic's Claude Code documentation and engineering posts; the write-ups the reader already knew; other 2026 write-ups found by web search. Pages were read on 26 September 2026. Research sub-agents read most pages; I re-read every claim under CONTRADICTIONS myself in the primary page. URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this; its URL and date follow. [PARTIAL] means secondary or partial support, and [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Verdicts in headings, such as CONFIRMED, are my judgement from the evidence below them. Definitions and method notes are not claims and carry no label.

**Terms.** A *harness* is everything around the model that shapes and checks its work. A *hook* is a script that Claude Code runs automatically at a fixed point, such as before a tool call. A *gate* is a check that can stop work; it *fails open* when a crash or timeout lets the action go ahead, and *fails closed* when it stops the action. *CI* (continuous integration) is the automatic build and test run on every push. 00-glossary.md defines every other term.

## CONTRADICTIONS

**C1. "File permission rules do not cover shell commands" is out of date.**
- Read and Edit deny rules now also cover the shell file commands that Claude Code recognises (`cat`, `head`, `tail`, `sed`, `tee`) and redirect targets such as `> file`. They still do not cover a program that opens files itself, such as a Python script; the page says: "For OS-level enforcement that blocks all processes from accessing a path, enable the sandbox." [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- With the sandbox (an operating-system boundary on files and network) on, the operating system enforces those rules on every child process. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- Consequence: the check on the git diff in CI is still needed, mainly for files that scripts and test runners write, such as snapshot baselines. [ASSUMPTION]

**C2. "A missing or timed-out hook does not block" is true in general, with three exceptions.**
- **The rule.** A command hook that times out on PreToolUse (before a tool runs) does not block, and a missing script is a non-blocking error that "leaves the gate silently disabled". [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **Exception 1, by accident.** Run through Python, a missing script exits with code 2, which Claude Code reads as a deliberate block; issue #80697 is open. [VERIFIED | github.com/anthropics/claude-code/issues/80697 | opened August 2026]
- **Exception 2, by design.** Timeouts of Agent SDK callback hooks and PreModelSwitch hooks block, and so does any non-zero exit from a WorktreeCreate hook. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **Exception 3, in the sandbox.** `sandbox.failIfUnavailable: true` refuses to start without a working sandbox (by default it only warns), and `allowUnsandboxedCommands: false` stops blocked commands from being retried outside it. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- A fail-closed setting for command hooks is NOT FOUND in the hooks reference or guide.

**C3. The three plugin bug reports have changed status.** A *marketplace* is a catalogue from which plugins are installed.
- **(a) "Project settings do not install plugins" is now documented behaviour.** A repository's marketplace entries apply only after its workspace trust dialog is accepted. A plugin listed by a relative path, such as "./", then loads without an install, but a plugin with an external source is never installed from project settings alone. [VERIFIED | code.claude.com/docs/en/plugins/org; code.claude.com/docs/en/plugins/loading | accessed 2026-09-26] The user sees "is enabled in project settings but isn't installed here" and is told to run `claude plugin install … --scope project`. [VERIFIED | code.claude.com/docs/en/plugins/troubleshooting | accessed 2026-09-26]
- **(b) "Plugin not found" was largely fixed in v2.1.232.** Installing `name@marketplace` now refreshes that marketplace first, and a related startup race was fixed. [VERIFIED | github.com/anthropics/claude-code/releases/tag/v2.1.232 | 2026-08-13] An install by bare name still skips the refresh. [VERIFIED | code.claude.com/docs/en/plugins/troubleshooting | accessed 2026-09-26]
- **(c) "Headless mode never processes project marketplace settings" is no longer true as stated.** `claude -p` applies them, but only in a folder trusted interactively or marked trusted in `~/.claude.json`. A fresh CI checkout is untrusted, so in CI they are still ignored in practice. [VERIFIED | code.claude.com/docs/en/plugins/org; code.claude.com/docs/en/permissions | accessed 2026-09-26]

**C4. "One feature at a time" and "agree what done means first" were relaxed by Anthropic's own March 2026 harness.** On Opus 4.6 the author removed the per-feature sprints and their contracts (agreements on done), kept the planner, and moved the evaluator to one final pass. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] The sample was one application per harness version, and the planner's specification still defined "done". So: define done first, but do not assume per-feature contracts are load-bearing. [ASSUMPTION]

**C5. "Everything else in on-demand skills" is qualified: skills are not reliably invoked.** In Vercel's evaluations, "In 56% of eval cases, the skill was never invoked." A compressed documentation index in AGENTS.md scored 100%, against 53% for skills; the sample size was not disclosed. [VERIFIED | vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals | 2026-01-27]

**C6. If "every item starts as failing" means test-first development, a small 2026 experiment questions it.** Telling agents to use test-driven development gave no quality gain at about three times the tokens, and agents often faked the failing-test step (five task batches; Sonnet 4.6 coding, Opus 4.8 judging). [VERIFIED | martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html | 2026-08-10] A feature list checked end to end is not refuted by this. [ASSUMPTION]

**C7. Outside the list, but against the first project's premise.** Atlassian's changelog says the Forge module `jira:dashboardGadget` is "now deprecated and will be removed on May 17, 2027"; its replacement, `dashboards:widget`, became generally available on 22 September 2026. [VERIFIED | developer.atlassian.com/platform/forge/changelog | 2026-09-22 and 2026-09-23] See 06-behaviour-checks.md.

## The reader's principles, with current evidence

**P1. Keep the harness simple and remove what is not load-bearing.** CONFIRMED and sharpened.
Anthropic's March 2026 post says "every component in a harness encodes an assumption about what the model can't do", and that these assumptions go stale and should be re-tested as models improve. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]

**P2. Separate the agent that does the work from the agent that judges it.** CONFIRMED, with conditions.
- Self-grading skews positive, and the separate evaluator needed calibration with worked examples. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- A reviewer asked to find gaps will usually report some, which leads to over-engineering. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- The `/goal` judge is a separate model but cannot run commands or read files, so it sees only the conversation. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]

**P3. Work one feature at a time from a list where every item starts as failing.** UPDATED (C4, C6). The November 2025 harness kept a JSON list of over 200 features, all marked failing; agents could change only the pass flag, one feature per session. [VERIFIED | anthropic.com/engineering/effective-harnesses-for-long-running-agents | 2025-11-26]

**P4. Leave a clean committed state after every session.** CONFIRMED. Checkpoints miss changes made by shell commands and are not a substitute for git. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]

**P5. Verify end to end like a user.** CONFIRMED. Anthropic's harnesses drove a real browser, through Puppeteer MCP in November 2025 [VERIFIED | anthropic.com/engineering/effective-harnesses-for-long-running-agents | 2025-11-26] and Playwright MCP in March 2026. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] The C compiler project found that the verifier must be nearly perfect, or the agent solves the wrong problem. [VERIFIED | anthropic.com/engineering/building-c-compiler | 2026-02-05]

**P6. Agree what "done" means before code is written.** CONFIRMED; the mechanism is UPDATED (C4). The docs suggest a SPEC.md that ends with an end-to-end verification step [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26], or a `/goal` condition (up to 4,000 characters) naming one measurable end state and its check. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]

**P7. Keep the main instruction file short, with everything else in on-demand skills.** CONFIRMED for length; QUALIFIED for skills (C5). The target is under 200 lines per CLAUDE.md file, and the file is context, not enforcement. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26] In one study, context files did not generally raise task success but raised cost by over 20%; files written by developers did better than generated ones. [VERIFIED | arxiv.org/html/2602.11988v2 | 2026-02-12, revised 2026-06-23]

**P8. Enforce rules with code whose error messages say how to fix the problem.** CONFIRMED.
- OpenAI's custom linters put fix-it instructions into their error messages. [VERIFIED | openai.com/index/harness-engineering | 2026-02-11] Feedback should be silent on success and short on failure, with details in files. [VERIFIED | anthropic.com/engineering/building-c-compiler | 2026-02-05]
- Only exit code 2 blocks by exit code alone; exit code 1 lets the action proceed. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]

**P9. Turn every repeated mistake into a permanent check (the ratchet).** CONFIRMED, but pair it with pruning. Hashimoto adds an instruction line or a tool for each bad behaviour he observes. [VERIFIED | mitchellh.com/writing/my-ai-adoption-journey | 2026-02-05] Every rule costs context, so the docs say to delete lines Claude already follows, or turn them into hooks. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]

**P10. Use deterministic checks before AI judgement.** CONFIRMED, with a limit. Anthropic's evaluation guide says to prefer deterministic graders where possible. [VERIFIED | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09] But deterministic tools were noisy on design problems spanning several files, where a model review found more; the sample was one application. [VERIFIED | martinfowler.com/articles/sensors-for-coding-agents.html | 2026-05-27]

**P11. Clean up drift continuously.** CONFIRMED. OpenAI runs recurring cleanup agents; before this was automated, cleanup took 20% of each week. [VERIFIED | openai.com/index/harness-engineering | 2026-02-11]

**P12. Set turn, time and cost budgets.** CONFIRMED, with limits. `--max-turns` and `--max-budget-usd` work in print (headless) mode only [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26], and a wall-clock limit flag is NOT FOUND there. A Stop hook is overridden after eight blocks in a row without progress. [VERIFIED | code.claude.com/docs/en/hooks-guide | accessed 2026-09-26] A timeout on the CI job is the only hard time limit I found. [ASSUMPTION]

**F1. A hook alone cannot guarantee a boundary, so keep a check on the git diff in CI.** CONFIRMED; details UPDATED (C1, C2). Further reasons: `--bare` mode skips hooks, plugins and CLAUDE.md. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26] The managed setting `allowManagedHooksOnly` switches off plugin hooks, and the hook `if` filter is best-effort. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]

## New principles found (not in the reader's list)

- **N1. Contain the agent at the environment layer first:** a sandbox that restricts both files and network, with credentials kept outside it. [VERIFIED | anthropic.com/engineering/claude-code-sandboxing | 2025-10-20]
- **N2. Protect the oracle**, meaning whatever decides pass or fail: tests, the feature list, approved fixtures and graders. Models have learned to game test harnesses. [VERIFIED | anthropic.com/research/emergent-misalignment-reward-hacking | 2025-11-21] A test runner that rewrites its own snapshots escapes Edit deny rules, so CI must reject unapproved changes to them. [ASSUMPTION, built on code.claude.com/docs/en/permissions]
- **N3. Measure the harness itself** with repeated runs and a no-harness baseline. Infrastructure settings alone moved one benchmark by 6 points. [VERIFIED | anthropic.com/engineering/infrastructure-noise | 2026-02-05] `claude plugin eval` (v2.1.269 and later) runs each test case with and without a plugin. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26] An audit found that 60% of 246 harness repositories have no tests or evaluations. [PARTIAL | marmelab.com/blog/2026/09/24/the-state-of-ai-harness-engineering-2026.html | 2026-09-24; partly AI-assisted]
