# 07 — Open questions, and what would settle each one (status on 26 September 2026)

**Sources and how they were selected.** This file cites 30 sources. It adds no new research: each question comes from a gap, conflict or untested claim found while writing files 01 to 06, and each source is one already cited there. The questions are ordered by how much the answer could change the harness-kit design. URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source or partial support. [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**How to read each entry.** Each question has four parts:
- **Uncertain:** what is not known.
- **Why it matters:** the design decision that depends on it.
- **Evidence so far:** what the research found.
- **Would settle it:** a concrete test or source.

Most tests need the real `claude` program running on a Mac or in CI, which this research session was not allowed to do. So the natural place to run them is a Claude Code CLI session on the Mac, not a cloud research session. [ASSUMPTION]

---

## A. Installing and loading the plugin

**Q1. Does the primary installation method in 05 (section 9) work end to end on macOS with the current Claude Code?**
- **Uncertain:** no public report shows the whole sequence on macOS with version 2.1.28x. [ASSUMPTION]
- **Why it matters:** it is the recommended daily-use method. [ASSUMPTION]
- **Evidence so far:**
  - Anthropic's documentation shows the expected output of the marketplace command. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - One Windows user reported that project-enabled plugins load. [PARTIAL | github.com/anthropics/claude-code/issues/96984 | 2026-09-25]
- **Would settle it:** in a throwaway project, run steps 5 to 9 of 05 section 9. Record the Claude Code version, each command's output and exit code, and the first event of a headless run. [ASSUMPTION]

**Q2. After cloning the private project into a fresh folder and accepting trust, does harness-kit load from project settings alone, with no install command?**
- **Uncertain:** the pages disagree. [ASSUMPTION]
  - The loading and organisation pages say a relative-path plugin loads once the marketplace entry applies. [VERIFIED | code.claude.com/docs/en/plugins/loading; code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
  - The install page is reported to say every collaborator must install once. [PARTIAL | code.claude.com/docs/en/plugins/install | accessed 2026-09-26]
- **Why it matters:** it decides whether a second machine, or a future collaborator, needs a manual step. [ASSUMPTION]
- **Would settle it:** clone into a new folder, open `claude`, accept trust, and check `/plugin`. [ASSUMPTION]

**Q3. When the marketplace and the plugin share the repository root, does validating `.claude-plugin/plugin.json` also check `hooks/hooks.json`, skills and agents?**
- **Evidence so far:** a marketplace-folder run does not open plugin files. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26] Whether a run pointed at the manifest file checks them is NOT FOUND.
- **Why it matters:** it decides between the single-root layout and the subfolder layout (04 C1; 05 section 2). [ASSUMPTION]
- **Would settle it:** put a deliberate error into `hooks/hooks.json`, then run `claude plugin validate` on the root, on the manifest file, and on the plugin folder. See which runs fail. [ASSUMPTION]
- **2026-09-26 — ANSWERED** (Increment 1, break (i); Claude Code 2.1.283 on macOS) [TESTED | local run of tests/validate.sh | 2026-09-26]:
  - A JSON syntax error in `plugins/harness-kit/hooks/hooks.json` was caught by `claude plugin validate plugins/harness-kit --strict` (exit 1: `json: Invalid JSON syntax: JSON Parse error: Unexpected token ','`).
  - The marketplace run, `claude plugin validate . --strict` on the repository root, passed (exit 0) and did not catch it.
  - A run pointed at the manifest file, `claude plugin validate plugins/harness-kit/.claude-plugin/plugin.json --strict`, also validated `hooks/hooks.json` and failed with the same error (exit 1).
  - Caveat: tested in the subfolder layout (04 C1), not the single-root layout this question describes. That the manifest-file run behaves the same when `marketplace.json` sits beside it at the root is untested.

**Q4. Does `--plugin-dir` work in a GitHub Actions `claude -p` step? Does it work when passed through the Action's `claude_args`?**
- **Evidence so far:**
  - The flag is documented. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
  - A public report of it in CI is NOT FOUND.
  - Reading the Action's source suggests a second `--plugin-dir` would overwrite the first. [PARTIAL | github.com/anthropics/claude-code-action (base-action/src/parse-sdk-options.ts) | observed 2026-09-26]
- **Would settle it:** a CI job that checks out harness-kit at a SHA, runs `claude -p` with `--output-format stream-json --verbose`, and fails unless the first event lists harness-kit with no `plugin_errors`. [ASSUMPTION]

**Q5. Can two projects on one Mac pin different refs of the same marketplace?**
- **Evidence so far:**
  - There is one `known_marketplaces.json` per user. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - A third-party test says the first registration wins. [PARTIAL | github.com/misnaej/forge/issues/553 | 2026-09-10]
- **Would settle it:** two throwaway projects pinned to different tags. Check which version each loads, using `claude plugin list --json` and `claude plugin details`. [ASSUMPTION]

**Q6. Which release made `claude -p` honour project marketplace entries in trusted folders?**
- The version is NOT FOUND.
- **Why it matters:** it sets the minimum Claude Code version the kit should require in CI. [ASSUMPTION]
- **Would settle it:** search the full GitHub release notes, which the research could only read in part. [ASSUMPTION]

## B. Hooks, skills and agents behaving as documented

**Q7. Is issue #80802, where a plugin skill body is not injected through the Skill tool, still present in the current version on macOS?**
- **Why it matters:** if it is, a skill-based process in the plugin may be read as empty. [ASSUMPTION]
- **Evidence so far:** open, reported on v2.1.218. [VERIFIED | github.com/anthropics/claude-code/issues/80802 | observed 2026-09-26]
- **Would settle it:** a plugin whose SKILL.md contains a unique marker string. Invoke the skill in `claude -p --plugin-dir … --output-format stream-json`, and search the stream for the marker. [ASSUMPTION]

**Q8. Do hooks in a subagent's frontmatter fire on macOS?**
- **Why it matters:** the proposed design copies agents that need hooks into `.claude/agents/`, because plugin agents lose that field. [ASSUMPTION]
- **Evidence so far:** issue #95650 is open; the report was on Windows with Git Bash, v2.1.258. [VERIFIED | github.com/anthropics/claude-code/issues/95650 | 2026-09-20]
- **Would settle it:** a project agent whose PreToolUse hook blocks one harmless command. Delegate a task that runs it, and check whether it is blocked. [ASSUMPTION]

**Q9. Are path-scoped rules still loaded at session start whatever their `paths` say?**
- **Evidence so far:** issue #16299 is open. [VERIFIED | github.com/anthropics/claude-code/issues/16299 | 2026-01-05]
- **Would settle it:** an InstructionsLoaded hook that logs each load reason. A `path_glob_match` reason should appear only after a matching file is touched. [VERIFIED that the reason exists | code.claude.com/docs/en/hooks | accessed 2026-09-26]

**Q10. How should harness-kit's hooks behave when their own script is missing: fail open or fail closed?**
- **Evidence so far:**
  - A missing script launched through the shell fails open. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
  - A missing script launched through Python can fail closed by accident, because Python exits with code 2. [VERIFIED | github.com/anthropics/claude-code/issues/80697 | 2026-08 (inferred)]
- **Would settle it:** a design decision, then a unit test of each case. For example, launch every hook through a small shell wrapper that checks the script exists and chooses the exit code deliberately. [ASSUMPTION]

**Q11. Are the harness's skills actually invoked on natural phrasing?**
- **Evidence so far:** skills were never invoked in 56% of one team's evaluation cases. [VERIFIED | vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals | 2026-01-27]
- **Would settle it:** a `claude plugin eval` suite with `tool_used: Skill` graders, run three times per case with a pinned model. [VERIFIED that this is supported | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
- **Complication:** `claude plugin eval` does not load plugin agents today, so agent cases must wait. [VERIFIED | github.com/anthropics/claude-code/issues/96121 | 2026-09-22]

**Q12. What are the exact exit-code-2 rows for PreCompact, Elicitation and SubagentStop in the hooks reference?**
- **Evidence so far:** the research's fetches of the table were cut off, and one summarising fetch contradicted other Anthropic pages (02, section 6). [VERIFIED | code.claude.com/docs/en/agent-teams; code.claude.com/docs/en/hooks-guide | accessed 2026-09-26]
- **Would settle it:** read the table in a normal browser. [ASSUMPTION]

## C. Boundaries and CI

**Q13. Does the Claude Code sandbox start on GitHub-hosted Ubuntu runners, where it relies on bubblewrap?**
- It is NOT FOUND.
- **Why it matters:** if it does not, CI must rely on the diff check alone for file boundaries. [ASSUMPTION]
- **Would settle it:** a CI job with `sandbox.enabled` and `failIfUnavailable: true`. If the sandbox cannot start, the job refuses to run. [VERIFIED that the setting behaves this way | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]

**Q14. From v2.1.283, auto mode is the default starting mode in interactive sessions. Does that change which prompts the harness can rely on the human to see?**
- **Evidence so far:** the default changed. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26] Its effect on harness design is NOT FOUND.
- **Would settle it:** run the harness for a week in auto mode and log every classifier denial and every hook block. Compare this with the layered design in 02. [ASSUMPTION]

## D. The first project (Forge)

**Q15. Should the gadget be built on `dashboards:widget` or on `jira:dashboardGadget`?**
- **Evidence so far:**
  - The old module is deprecated, with removal on 17 May 2027. The new one is declared generally available, but its reference page still carried an Early Access banner. [VERIFIED | developer.atlassian.com/platform/forge/changelog | 2026-09-22 and 2026-09-23]
  - Atlassian says it will provide migration tooling. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/jira-dashboards-upcoming-changes-and-new-forge-dashboard-widget-module-general-availability/102826 | 2026-09-23]
- **Would settle it:**
  - check whether a free developer site shows the new dashboards today; [ASSUMPTION]
  - read the widget module page again after Atlassian updates it; [ASSUMPTION]
  - ask in the Atlassian Developer Community whether new apps should start on the widget module. [ASSUMPTION]

**Q16. UI Kit or Custom UI, given that UI Kit cannot be rendered locally for tests?**
- **Evidence so far:** an Atlassian staff statement. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/ui-kit2-unit-testing-jsx-components/75091 | 2023-11-29 to 2025-04-17]
- **Would settle it:** a one-day spike. Build the same small widget both ways, and compare how much of each can be tested in the agent's loop, without Jira. Optionally include the unofficial forge-sim simulator. [PARTIAL | github.com/ryanackley/forge-sim | observed 2026-09-26]

**Q17. Is a Playwright suite that logs into a developer site with a TOTP code stable enough for CI?**
- **Evidence so far:**
  - Atlassian's support article describes the approach and warns that it may stop working. [VERIFIED as read by a sub-agent | support.atlassian.com/atlassian-cloud/kb/emailed-otp-marketplace-partners-automation-guide-for-e2eend-to-end-testing-using-two-step-verification2sv-mfa-2fa | updated 2025-09-25]
  - One forum user says it worked. [PARTIAL | community.developer.atlassian.com/t/forge-e2e-testing-and-2fa-with-playwright/94824 | 2025-08-27]
- **Would settle it:** run the login test on a schedule for two weeks and count the failures. [ASSUMPTION]

**Q18. How long do the fast checks take for this gadget?** The fast checks are unit tests, resolver tests, `forge lint` and ARIA snapshots.
- **Why it matters:** it decides whether they can run in a Stop hook on every turn, or only before commits. [ASSUMPTION]
- **Would settle it:** measure them on the first working version. Spotify and Stripe both keep in-loop checks fast. [PARTIAL | blog.bytebytego.com/p/how-stripes-minions-ship-1300-prs | 2026-03-16]

## E. Whether the principles hold for this project and model

**Q19. Is the per-feature "definition of done" still load-bearing on the current model for this kind of project?**
- **Evidence so far:** Anthropic dropped per-feature contracts on Opus 4.6, with one application as the sample. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- **Would settle it:** build two comparable small features, one with and one without a per-feature contract. Record defects found later, the cost, and the time. This is a tiny sample, so treat the result as a hint. [ASSUMPTION]

**Q20. Which harness-quality metrics are worth tracking, and what are their starting values?**
- **Evidence so far:** standard definitions were NOT FOUND (04, B3).
- **Would settle it:** record the six proposed metrics in 04 B3 for the first ten features, then keep only those that changed a decision. [ASSUMPTION]

## F. Evidence that could not be read

**Q21. Stripe's "Minions" articles.** Details such as "at most two CI rounds" are secondary only, because the article bodies render in the browser. [PARTIAL | blog.bytebytego.com/p/how-stripes-minions-ship-1300-prs | 2026-03-16]
- **Would settle it:** read the articles in a real browser. [ASSUMPTION]

**Q22. Star counts that look extreme** (for example about 268k for a repository created in January 2026). [VERIFIED as read by a sub-agent | github.com/affaan-m/everything-claude-code | observed 2026-09-26]
- **Evidence so far:** fake-star campaigns exist in this field, but no evidence about these repositories was found. [VERIFIED as read by a sub-agent | arxiv.org/abs/2412.13459 | 2024-12-18, v2 2025-09-06]
- **Why this is low priority:** it does not affect the design, because no design choice in these files rests on popularity. [ASSUMPTION]
