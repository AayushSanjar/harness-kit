# Research: harness engineering for Claude-based software development (status on 26 September 2026)

**Sources.** This folder cites 232 distinct sources, all listed in `sources.csv`: 216 primary and 16 secondary.
- Each file states its own count and selection method at the top.
- Research sub-agents also read further pages that are not cited, and those are not counted.
- The sources were selected with Anthropic's documentation and engineering posts first, then primary write-ups by practitioners and companies, then GitHub issues and repositories, and then secondary coverage only where no primary source could be read.

**How to read the labels.** Every claim carries one of these:
- [VERIFIED]: a primary page says this; the URL and date follow the label.
- [PARTIAL]: a secondary source, or partial support.
- [ASSUMPTION]: the author's inference or proposal.
- NOT FOUND: searched for and not found.

A claim marked "as read by a sub-agent" was read in the primary page by a research sub-agent but not re-read by me. URLs inside the files omit "https://".

## Files

| File | What it answers |
|---|---|
| `00-glossary.md` | Every term used, defined simply, each with a one-line example |
| `01-principles.md` | CONTRADICTIONS with the principles the reader already held, then each principle with current evidence |
| `02-claude-features.md` | Each Claude Code feature a harness uses: what it guarantees, what it does not, and known bugs |
| `03-reference-harnesses.md` | 15 public harnesses or kits and 4 company write-ups: what they enforce, what is reusable, and evidence |
| `04-replication.md` | Reuse across projects and self-improvement from defects, ending with a proposed plugin folder layout |
| `05-using-the-plugin.md` | How a private project installs, pins, updates, validates and uses a plugin from a public repository, in CI too, ending with an installation method and a fallback |
| `06-behaviour-checks.md` | Automated behaviour and visual checks for web interfaces, and testing Atlassian Forge apps |
| `07-open-questions.md` | What remains uncertain, and the test or source that would settle each question |
| `sources.csv` | Every cited source: title, URL, publisher, date, primary or secondary, and the files that use it |

## The three findings most likely to change the design

1. **A plugin cannot carry the boundary itself.**
   - A plugin's settings apply only the `agent` and `subagentStatusLine` keys, so permission rules, sandbox settings and environment variables cannot ship inside the plugin. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
   - Subagents shipped in a plugin ignore their `hooks`, `mcpServers` and `permissionMode` fields. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
   - Plugin hooks run outside the sandbox, and an organisation setting can switch them off. [VERIFIED | code.claude.com/docs/en/sandboxing; code.claude.com/docs/en/hooks | accessed 2026-09-26]
   - Consequence: the kit must be split into a generic plugin plus project-owned settings, agent copies and CI checks. See 04 Part C. [ASSUMPTION]
2. **CI must load the plugin explicitly, and check that it loaded.**
   - A repository's marketplace settings apply only in a folder that was trusted. A fresh CI checkout is untrusted, so they are ignored there. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
   - The GitHub Action cannot yet pin a marketplace to a git ref. [VERIFIED | github.com/anthropics/claude-code-action/issues/1229 | observed 2026-09-26]
   - Consequence: in CI, check out the plugin at a pinned commit, load it with `--plugin-dir`, and fail the job unless the run's first event lists it. See 05 sections 4 and 8. [ASSUMPTION]
3. **The first project's Forge module is deprecated, and UI Kit cannot be unit-tested locally.**
   - `jira:dashboardGadget` will be removed on 17 May 2027, and `dashboards:widget` replaces it. [VERIFIED | developer.atlassian.com/platform/forge/changelog | 2026-09-22 and 2026-09-23]
   - An Atlassian staff member stated that UI Kit components cannot be rendered locally for tests. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/ui-kit2-unit-testing-jsx-components/75091 | 2023-11-29 to 2025-04-17]
   - Consequence: choose the module first, and consider Custom UI where fast in-loop behaviour checks matter. See 06. [ASSUMPTION]
