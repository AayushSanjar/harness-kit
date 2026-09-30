# 04 — Making a harness reusable, and making it improve itself from defects (status on 26 September 2026)

**Sources and how they were selected.** This file cites 51 sources. For reuse, I used Anthropic's plugin, sub-agent, hooks and organisation pages first, then the reader's known write-ups (OpenAI, Böckeler, Hashimoto) and Every's public plugin. For self-improvement, I used Anthropic's evaluation guide and the `claude plugin eval` page. I then added documentation of established tools that test checks (PIT, Semgrep, ESLint, ArchUnit, Copier), and community projects found by searches such as "seeded fault guardrail agent", "hook unit tests Claude Code" and "harness engineering benchmark". A research sub-agent read about 60 pages. I re-read these pages myself in raw text: plugin manifest reference, plugin components, sub-agents, plugin loading, organisation page, plugin security, platform support and plugin evals. Everything I re-read is labelled plainly [VERIFIED]. Claims that only the sub-agent read are labelled "[VERIFIED as read by a sub-agent]", or [PARTIAL] where the sub-agent itself was unsure. URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source or partial support. [ASSUMPTION] means my inference or proposal. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**Terms used in this file.**
- A **plugin** is an installable folder that bundles skills, agents, hooks and other parts.
- A **consumer project** is a repository that installs the plugin; here, the private Forge app.
- A **gate** is a check that can stop work.
- A **seeded fault** is a deliberate mistake planted to prove that a gate catches it.
- An **eval** (evaluation) is a repeatable test of agent behaviour, usually run several times because the agent's output varies.

---

# Part A — Reuse across different kinds of projects (question 4)

## A1. What a plugin can carry, and what it cannot

**It can carry** [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]:
- skills and older-style commands; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- agents (subagent definitions); [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- hooks (`hooks/hooks.json`); [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- MCP servers, meaning external tool servers; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- LSP servers, meaning language servers that report compile errors after edits; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- output styles and workflows; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- a `bin/` folder of executables; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- a default `settings.json`; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- user-configuration prompts (`userConfig`) and dependencies on other plugins; [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- experimental monitors, themes and an eval folder. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]

Only `name` is required in the manifest. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]

**It cannot carry the boundary itself.**
- A plugin's settings apply only `agent` and `subagentStatusLine`; other keys are dropped at load. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- So a plugin cannot deliver permission rules, sandbox settings or environment variables. Those must live in the consumer project's `.claude/settings.json`, the user's settings, or managed settings. [VERIFIED as a direct consequence of code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- This is the single most important constraint on the harness-kit design. [ASSUMPTION]

**Other limits that shape the design.**
- A `CLAUDE.md` at the plugin root is not loaded as context, and `claude plugin validate` warns about it. Instructions must be written as skills. [VERIFIED | code.claude.com/docs/en/plugins/components | accessed 2026-09-26]
- Plugin hooks and MCP servers run outside the sandbox with the user's full privileges. The plugin's MCP tool calls and `bin/` executables that Claude runs are still subject to permission rules. [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]
- A plugin with a top-level `bin/` folder "Can't be installed" in claude.ai chat or Cowork. Hooks and agents load in Cowork and Claude Code but not in chat. LSP servers, output styles and settings load only in Claude Code. [VERIFIED | claude.com/docs/plugins/platform-support | accessed 2026-09-26]
- `${CLAUDE_PLUGIN_ROOT}` points at the installed version's folder and changes with every version. `${CLAUDE_PLUGIN_DATA}` survives updates. Neither is set for commands Claude runs through the Bash tool. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26; VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins-reference]
- Files outside the plugin folder are not copied into the cache, so a script that reads `../shared` breaks after installation. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]

**Levers a plugin does have for per-project values.**
- **`userConfig`** prompts for values when the plugin is enabled through `/plugin`. The value types are string, number, boolean, directory and file. Values reach hooks as `CLAUDE_PLUGIN_OPTION_<KEY>` environment variables and can be substituted into MCP settings and skill text. The dialog does not appear with `--plugin-dir`; use `/plugin configure` instead. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins-reference; code.claude.com/docs/en/plugins/create | accessed 2026-09-26]
- **`${CLAUDE_PROJECT_DIR}`** lets a plugin hook call a script that lives in the consumer project. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- **Dependencies** can pin other plugins with semantic-version ranges resolved against git tags named `<plugin>--v<version>`, which `claude plugin tag` creates. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/dependencies | accessed 2026-09-26]

## A2. Do subagents shipped in a plugin lose their hooks, MCP servers or permission mode? Yes.

- **The official statement.** For security reasons, plugin subagents do not support the `hooks`, `mcpServers` or `permissionMode` frontmatter fields; the fields are ignored when the agent loads from a plugin. The field table also marks `initialPrompt` as ignored for plugin subagents. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26] The components page lists the same ignored fields. [VERIFIED | code.claude.com/docs/en/plugins/components | accessed 2026-09-26]
- **What still works in a plugin agent.** `tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `skills`, `memory`, `background`, `isolation: worktree` and `color` still work. So a plugin reviewer can still be made read-only by giving it only read tools. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/components | accessed 2026-09-26]
- **Documented workarounds.**
  1. Copy the agent file into the project's `.claude/agents/` or `~/.claude/agents/`, where the fields work. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  2. Add session-wide `permissions.allow` rules, which then apply to the whole session, not only to that agent. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  3. Use plugin-level hooks, which also fire inside subagents. Their input carries `agent_id` and `agent_type`, and SubagentStart and SubagentStop matchers accept plugin-scoped names written as an anchored regular expression, such as `^harness-kit:reviewer$`. [VERIFIED | code.claude.com/docs/en/hooks; code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
- **Counter-case for workaround 3** [ASSUMPTION]: a plugin-level hook fires for every subagent in the session, so its cost, and any bug in its filter, affects all agents.
- **Related restrictions.**
  - The managed setting `allowManagedHooksOnly` blocks plugin hooks unless managed settings force-enable that plugin. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
  - Plugin-scoped subagent definitions are dropped when used as agent-team teammates (#78234, open). [VERIFIED | github.com/anthropics/claude-code/issues/78234 | 2026-07 (inferred)]
  - Plugin subagents could not reach plugin MCP tools (#21560, closed as not planned). [PARTIAL | github.com/anthropics/claude-code/issues/21560 | 2026-01-28]
  - Plugin MCP servers are ignored under `allowManagedMcpServersOnly` (#94803, open). [PARTIAL | github.com/anthropics/claude-code/issues/94803 | 2026-09-16]

## A3. How organisations distribute one harness

- **Force-installing across a fleet.** Managed settings (a policy file, device management, or the claude.ai admin console) can force-install plugins by setting `extraKnownMarketplaces` together with `enabledPlugins`. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
- **Restricting sources.** They can restrict sources with `strictKnownMarketplaces`, reject `--plugin-dir` with `disableSideloadFlags`, and allow only plugin-supplied skills, agents, hooks and MCP servers with `strictPluginOnlyCustomization`. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
- **Release channels.** Two marketplaces that point at different git refs of the same plugins can be assigned to different user groups. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
- **Relevance here** [ASSUMPTION]: a solo developer does not need managed settings. The release-channel idea still transfers, as a "stable" tag used by projects and a "latest" branch used while developing.

## A4. Templates, starter repositories and cross-tool standards

- **Harness templates.** Böckeler defines a harness template as a bundle of guides (controls that act before the agent works) and sensors (checks after it works), fitted to one service topology, meaning one kind of application shape. She warns that versioning such templates is hard, because non-deterministic guides and sensors are hard to test. [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
- **Harnessability.** Her term for the properties that make controls possible: a typed language, clear module boundaries, and frameworks with conventions. [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
- **Topology-based harnesses.** Her February memo predicted that teams would pick from a few harnesses for common topologies, and warned that updates contributed back are hard for other teams to absorb. [VERIFIED as read by a sub-agent | martinfowler.com/articles/exploring-gen-ai/harness-engineering-memo.html | 2026-02-17]
- **OpenAI's approach.** OpenAI keeps AGENTS.md at about 100 lines, as a table of contents into a structured `docs/` folder. Linters and CI check that those documents stay current. The post does not claim the approach generalises to other repositories. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
- **Cross-tool files.**
  - AGENTS.md is a cross-tool instruction file stewarded under the Linux Foundation. [VERIFIED as read by a sub-agent | agents.md | accessed 2026-09-26]
  - Claude Code reads it from v2.1.277 when no CLAUDE.md exists. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]
  - Claude Code skills follow the open Agent Skills format. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/skills | accessed 2026-09-26]
  - Instructions written as AGENTS.md plus skills are therefore the most portable part of a harness. [ASSUMPTION]
- **Keeping copies in sync with a template.** The closest established practice is Copier's `copier update`, which regenerates from the template and does a three-way merge, leaving conflicts for review. [VERIFIED as read by a sub-agent | copier.readthedocs.io/en/stable/updating | accessed 2026-09-26]
- **Negative results.** A cookiecutter-style scaffold made specifically for agent harnesses was NOT FOUND. `claude plugin init` scaffolds a plugin, not a harness. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/create | accessed 2026-09-26]

## A5. Which parts should stay generic, and which are project-specific

**Evidence.**
- **When to make a plugin.** Anthropic says to keep a plain `.claude/` folder while a setup serves one project, and to make a plugin to share it, install it across projects, or publish versioned releases. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/create | accessed 2026-09-26]
- **What belongs in the per-project instruction file:**
  - shell commands Claude cannot guess; [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  - style rules that differ from defaults; [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  - test runners; [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  - repository etiquette; [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  - project-specific architecture decisions; [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  - environment quirks. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
  [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- **The platform forces a split.** Permissions, sandbox settings and environment variables cannot come from a plugin (A1). [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- **Böckeler's three kinds of control:**
  - maintainability (duplication, complexity, coverage, drift); [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
  - architecture fitness (a project's own qualities, such as performance); [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
  - behaviour (does the application work?). [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
  She places cheap checks early and expensive ones in the pipeline. [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
- **What OpenAI keeps specific versus generic.** OpenAI's layer rules and *taste* rules are specific to its codebase. Its agent-to-agent review, documentation gardening and cleanup agents are not. [VERIFIED facts as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11; the classification is ASSUMPTION]
- **Every's split.** Every's plugin ships generic workflow skills, while each repository keeps its own learnings in `docs/solutions/`. [VERIFIED as read by a sub-agent | github.com/EveryInc/compound-engineering-plugin | observed 2026-09-26]

**Proposed split** [ASSUMPTION, built on the evidence above]:

| Part | Generic (lives in harness-kit) | Project-specific (lives in the consumer project) |
|---|---|---|
| Process | Skills for planning, the definition of done, verification, recording a defect, and review | The project's own spec and feature list |
| Gates | Hook scripts that call a project check command and turn its result into exit code 2 with a fix-it message | The actual build, test, lint and architecture commands (for example Maven, Gradle, npm or `forge lint`) |
| Oracle protection | A hook and a CI script that refuse unapproved edits to listed protected paths | The list of protected paths: tests, snapshots, approved fixtures, the feature list |
| Boundary | Templates for permission and sandbox settings, and a setup skill that copies them in | The resulting `.claude/settings.json`, including network domains and deny rules |
| Agents needing hooks or a permission mode | Agent templates | Copies placed in `.claude/agents/`, because plugin agents lose those fields |
| Review | Reviewer and evaluator agents (read-only tools) | A REVIEW or rubric file with the project's criteria |
| Measurement | Eval scaffolding, gate self-tests, seeded-fault runner | The project's defect log and its regression cases |

**Counter-case.** Böckeler's model suggests the reusable unit should be a template for one topology, for example "Forge app", rather than a kit that is generic for every project. The strongest checks depend on project structure. If most future projects share one topology, a topology-specific kit may beat a generic one. [VERIFIED as read by a sub-agent for her model | martinfowler.com/articles/harness-engineering.html | 2026-04-02; the recommendation is ASSUMPTION]

---

# Part B — Making the harness improve itself from defects (question 6)

## B1. Replaying past defects as tests

- **Start from real failures.** Anthropic's evaluation guide says "20-50 simple tasks drawn from real failures is a great start". [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - Capability evals start at a low pass rate and move into regression suites once they pass reliably. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - Each task needs a reference solution. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - Trials should start from clean, isolated environments. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - You should read the transcripts. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- **At the level of one bug**, the docs say to have Claude write a failing test that reproduces the issue, and then fix it. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- **Built-in replay in `claude plugin eval`** [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]:
  - Each case can seed fixture files with a `scaffold_script`, which runs only when you pass `--scaffold`. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - It can resume a saved conversation. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - It can use mock MCP servers. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - It can grade against a reference transcript with the `baseline` grader. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - These are the closest built-in tools for replaying a past failure. [ASSUMPTION]
- **Other practice.**
  - Anthropic's skill-creator has a benchmark mode that tracks pass rate, time and tokens across model changes. [VERIFIED as read by a sub-agent | claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills | 2026-03-03]
  - LangChain built a trace-analysis skill that looks for failure patterns in agent traces and uses them to drive harness changes. [VERIFIED as read by a sub-agent | langchain.com/blog/improving-deep-agents-with-harness-engineering | 2026-02-17]
- **Proposed pipeline** [ASSUMPTION]. Every escaped defect produces up to three artefacts:
  1. a failing test in the consumer project, which is the product regression; [ASSUMPTION]
  2. if a gate should have caught it, a seeded-fault fixture for that gate, which is the harness regression; [ASSUMPTION]
  3. if an instruction or skill should have prevented it, an eval case. [ASSUMPTION]
  - Counter-case: artefact 3 costs model calls on every run, so keep eval suites small and run them less often than unit tests. [ASSUMPTION]

## B2. Testing the harness itself: breaking each gate on purpose

- **What Anthropic documents.**
  - `claude plugin validate --strict` checks files statically. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - `claude plugin eval` checks behaviour. The plugin's hooks and real MCP servers run outside the evaluation's sandbox. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - You can test a hook by piping sample JSON into its script and checking the exit code. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/hooks-guide | accessed 2026-09-26]
  - `--include-hook-events` exposes hook events in headless output. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
- **Mutation or seeded-fault testing of agent gates is not in Anthropic's docs.** NOT FOUND. A sub-agent checked the plugin-evals, hooks, hooks-guide and plugin-creation pages.
- **Community examples** (small projects, weak evidence of wider practice):
  - A September 2026 pull request adds a *loop drill* that injects a known fault and asserts that the guardrail responds. It reports sensitivity (faults caught) and specificity (legitimate changes allowed). [VERIFIED as read by a sub-agent | github.com/cobusgreyling/loop-engineering/pull/600 | merged 2026-09-13]
  - An open proposal describes a registry of seeded faults, each applied in an isolated worktree, with each guard reported as *fired* or *did not fire*. [VERIFIED as read by a sub-agent | github.com/laithalsaadoon/microvms-agentd/issues/274 | 2026-09-25]
- **Established practice to borrow.** Each of these proves that a check fires on a violation and stays silent on compliant code. [VERIFIED as read by a sub-agent | pitest.org; docs.semgrep.dev/writing-rules/testing-rules; eslint.org/docs/latest/integrate/nodejs-api | accessed 2026-09-26]
  - PIT mutates JVM code to show whether tests catch the change, and runs from Maven or Gradle. [VERIFIED as read by a sub-agent | pitest.org; docs.semgrep.dev/writing-rules/testing-rules; eslint.org/docs/latest/integrate/nodejs-api | accessed 2026-09-26]
  - Semgrep rule tests annotate code with `ruleid:` (must match) and `ok:` (must not match). [VERIFIED as read by a sub-agent | pitest.org; docs.semgrep.dev/writing-rules/testing-rules; eslint.org/docs/latest/integrate/nodejs-api | accessed 2026-09-26]
  - ESLint's RuleTester runs valid and invalid cases. [VERIFIED as read by a sub-agent | pitest.org; docs.semgrep.dev/writing-rules/testing-rules; eslint.org/docs/latest/integrate/nodejs-api | accessed 2026-09-26]
  - Anthropic's own plugin-dev plugin ships scripts to validate hook schemas and to run a hook with sample input. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code/tree/main/plugins/plugin-dev | observed 2026-09-26]
- **An open question.** Böckeler asks how to measure harness coverage, and whether a sensor that never fires means good code or poor detection. [VERIFIED as read by a sub-agent | martinfowler.com/articles/harness-engineering.html | 2026-04-02]
- **Proposed gate-test ladder for harness-kit** [ASSUMPTION], from cheapest to most expensive:
  1. **Unit test every hook script** with recorded JSON inputs: one input that must produce exit code 2, and one that must produce exit code 0. [ASSUMPTION]
  2. **Keep a seeded-fault fixture** for each gate: a tiny repository state that violates exactly that gate. CI runs the gate against it and expects failure, then runs it against a clean state and expects success. [ASSUMPTION]
  3. **Run an end-to-end smoke test** with `claude -p --plugin-dir <kit> --include-hook-events --output-format stream-json` on a fixture. Assert that the hook fired and blocked. [ASSUMPTION]
  4. **Use `claude plugin eval`** only for things that need the model, such as whether a skill is triggered. [ASSUMPTION]
  - Re-run levels 1 to 3 on every new Claude Code version, because hooks have silently stopped firing between versions (issues #95650 and #80697). [VERIFIED | github.com/anthropics/claude-code/issues/95650 | 2026-09-20; github.com/anthropics/claude-code/issues/80697 | 2026-08 (inferred)]
  - Counter-case: levels 3 and 4 cost money and vary from run to run, and `claude plugin eval` cannot load the plugin's own agents today (#96121, open). [VERIFIED | github.com/anthropics/claude-code/issues/96121 | 2026-09-22]

## B3. Measuring harness quality

- **Consistency metrics.** pass@k is the chance that at least one of k attempts succeeds. pass^k is the chance that all k succeed; it is the stricter measure of consistency. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- **What `claude plugin eval` reports:** the score with the plugin, the score without it, the difference, the share of *perfect runs* (runs where every grader passed), estimated cost and duration. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
- **Changes to the harness alone can move results.**
  - LangChain held the model fixed and raised its Terminal-Bench 2.0 score from 52.8% to 66.5% through harness changes only: a verification loop, loop detection and time-budget warnings. The number of runs per configuration was not captured. [VERIFIED as read by a sub-agent | langchain.com/blog/improving-deep-agents-with-harness-engineering | 2026-02-17]
  - Infrastructure settings alone moved Terminal-Bench 2.0 scores by 6 points, so gaps under 3 points deserve scepticism. [VERIFIED as read by a sub-agent | anthropic.com/engineering/infrastructure-noise | 2026-02-05]
  - Bugs in the evaluation harness can dominate: one model went from 42% to 95% on a benchmark after grading fixes. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - Changing only the edit format to *hashline* (each line tagged with a short hash) beat the patch format for 14 of 16 models, and one model went from 6.7% to 68.3%; no significance analysis was reported. [VERIFIED as read by a sub-agent | stencil.so/blog/the-harness-problem | 2026-02-12] A smaller independent benchmark (3 models, single attempts) did not reproduce this: the ordinary replace format mostly won. [VERIFIED as read by a sub-agent | nwyin.com/blogs/hashline-vs-replace-edit-bench.html | 2026-03-23, updated 2026-09-17]
- **Proxy metrics used in practice.**
  - Merge rates of automated pull requests: GitHub Next reports, for example, 57 of 59 documentation-update pull requests merged. [VERIFIED as read by a sub-agent | github.github.com/gh-aw/blog/2026-01-13-meet-the-workflows-documentation | 2026-01-13]
  - A judge's veto rate: Spotify's judge vetoes about 25% of sessions. [VERIFIED | engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3 | 2025-12-09]
- **No built-in telemetry for this plugin.** Claude Code emits hook metrics only for official-marketplace plugins, so a third-party harness gets no built-in hook telemetry. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/measure | accessed 2026-09-26] Third-party plugin names are also redacted in OpenTelemetry events unless `OTEL_LOG_TOOL_DETAILS=1`. [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]
- **Standard definitions of harness metrics** (escaped defects, gate false-positive rate, human-intervention rate) were NOT FOUND in any harness-specific source.
- **Proposed metrics for harness-kit** [ASSUMPTION]:
  1. **Escaped-defect rate:** defects found after merge, per feature. [ASSUMPTION]
  2. **Gate catch rate:** the share of seeded faults each gate catches (from B2 level 2). [ASSUMPTION]
  3. **Gate false-block rate:** blocks a human overrode as wrong. [ASSUMPTION]
  4. **First-pass rate:** tasks where CI passes on the first push. [ASSUMPTION]
  5. **Human interventions per task.** [ASSUMPTION]
  6. **Cost and wall-clock time per task.** [ASSUMPTION]
  - Counter-case: with one developer and one project, the sample stays small for months, so treat trends as hints, not proof. [ASSUMPTION]

## B4. The ratchet: turning a repeated mistake into a permanent check

- **Evidence.**
  - OpenAI captures review comments and bugs as documentation or tooling. Its linters are written by the agent and carry fix-it messages. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
  - Hashimoto's rule is to "engineer a solution such that the agent never makes that mistake again". [VERIFIED as read by two sub-agents independently | mitchellh.com/writing/my-ai-adoption-journey | 2026-02-05]
  - Every's loop is plan, work, review and *compound*; the compound step writes the lesson to `docs/solutions/` and updates instructions. [VERIFIED as read by a sub-agent | every.to/chain-of-thought/compound-engineering-how-every-codes-with-agents | 2025-12-11]
  - Anthropic's hookify plugin can read the recent conversation, find behaviour you corrected, and propose rules. Its rules default to warning rather than blocking. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/README.md | observed 2026-09-26]
  - For existing code, ArchUnit's `FreezingArchRule` stores today's violations and fails only on new ones. That is a ready-made Java ratchet. [VERIFIED as read by a sub-agent | archunit.org/userguide/html/000_Index.html | accessed 2026-09-26]
  - Pruning is part of the ratchet: the docs say to delete CLAUDE.md lines Claude already follows, or to turn them into hooks. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- **Proposed promotion path** [ASSUMPTION]:
  1. note the mistake in the defect log; [ASSUMPTION]
  2. add one instruction line; [ASSUMPTION]
  3. if it repeats, add a warning hook; [ASSUMPTION]
  4. give that hook a seeded-fault test, then switch it to blocking; [ASSUMPTION]
  5. mirror it as a CI check if it protects a boundary. [ASSUMPTION]
  - Every rule gets an owner and a review date, so it can be removed when no longer needed. [ASSUMPTION]
  - Counter-case: this is slower than OpenAI's approach, where agent-written rules land fast and wrong ones are corrected cheaply. [ASSUMPTION]

## B5. Continuous clean-up of drift

- OpenAI runs recurring agents that scan for deviations from its *golden principles*, update quality grades and open small refactoring pull requests. A separate agent keeps documentation current. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
- GitHub Next runs daily workflows that open pull requests for humans. For example, 88 of 103 *docs unbloat* pull requests were merged. [VERIFIED as read by a sub-agent | github.github.com/gh-aw/blog/2026-01-13-meet-the-workflows-documentation]
- **Scheduling options in Claude Code.** [VERIFIED as read by a sub-agent | code.claude.com/docs/en/scheduled-tasks | accessed 2026-09-26]
  - `/loop` repeats a prompt on an interval; bare `/loop` runs a built-in maintenance prompt that `.claude/loop.md` can replace. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/scheduled-tasks | accessed 2026-09-26]
  - Cloud routines run at most hourly. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/scheduled-tasks | accessed 2026-09-26]
  - Desktop scheduled tasks and GitHub Actions schedules are the other options. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/scheduled-tasks | accessed 2026-09-26]
- **Why clean-up pays.** In one codebase, refactoring cut the input tokens per change from about 160,000 to about 27,000 (83% fewer). The sample is one codebase. [VERIFIED as read by a sub-agent | martinfowler.com/articles/exploring-gen-ai/refactoring-economic-benefit.html | 2026-07-30]
- **Hygiene commands.** `/doctor` proposes cuts to CLAUDE.md, and `/skill-doctor` flags skills that are never used. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26; VERIFIED as read by a sub-agent | code.claude.com/docs/en/whats-new | weeks of 2026-03-23 to 2026-09-11]

---

# Part C — Proposed plugin folder layout

Everything in this part is a design proposal [ASSUMPTION]. Each choice is built on the [VERIFIED] constraints above, which are named in brackets.

## C1. The public harness-kit repository (generic kit)

```
harness-kit/                               public repository = the marketplace
├── .claude-plugin/
│   └── marketplace.json                   one entry "harness-kit", source "./plugins/harness-kit"     (05 §2)
├── plugins/
│   └── harness-kit/                       the plugin: everything Claude Code loads or copies to its cache
│       ├── .claude-plugin/plugin.json     name "harness-kit", version, userConfig for check commands
│       ├── skills/                        instructions (a plugin cannot ship CLAUDE.md)                  [A1]
│       │   ├── define-done/SKILL.md       write the spec and feature list before coding
│       │   ├── verify/SKILL.md            run the project checks, show evidence, never claim success
│       │   ├── record-defect/SKILL.md     turn an escaped defect into test + seeded fault + eval         [B1]
│       │   ├── promote-rule/SKILL.md      the ratchet: note → warning hook → blocking hook → CI          [B4]
│       │   └── setup-project/SKILL.md     copy templates/ into a consumer project, merge settings        [A1, A2]
│       ├── agents/                        plugin agents: tools and model only, no hooks                  [A2]
│       │   ├── reviewer.md                read-only tools; reviews the diff against the spec
│       │   └── evaluator.md               read-only tools plus browser checks; grades against the rubric
│       ├── hooks/hooks.json               PreToolUse: protect listed paths; Stop: run the project check
│       │                                  command; SubagentStop matched to ^harness-kit:reviewer$         [A2]
│       ├── scripts/                       hook implementations, called through ${CLAUDE_PLUGIN_ROOT}
│       ├── templates/                     must sit inside the plugin: files outside are not cached        [A1]
│       │   ├── claude-settings.template   permission deny rules, sandbox block, pinned marketplace
│       │   ├── agents/                    agent files that need hooks or permissionMode                  [A2]
│       │   ├── harness-config.template    check commands, protected paths, budgets
│       │   ├── ci/                        CI job templates: diff guard, "harness-kit loaded" check
│       │   └── CLAUDE.template.md         short project instruction skeleton (under 200 lines)
│       └── evals/                         claude plugin eval cases (skill triggering, smoke test)        [B2]
├── tests/                                 repository-level only; never shipped to users
│   ├── hooks/                             recorded JSON inputs → expected exit codes (level 1)            [B2]
│   └── seeded-faults/                     one violating fixture per gate (level 2)                        [B2]
└── .github/workflows/                     validate marketplace and plugin with --strict; hook tests;
                                           seeded-fault run
```

The plugin sits in a subfolder, not at the repository root, for two reasons [ASSUMPTION built on VERIFIED rules]:
- `claude plugin validate` on a marketplace folder does not open the plugins' skill, agent or hook files, so a separate validation of `plugins/harness-kit` is needed. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
- Test fixtures and CI files should not be copied into every user's plugin cache. [ASSUMPTION built on VERIFIED rules]

The single-root layout (`source: "./"`) also works and is simpler. Its cost is the validation gap described in 05 section 2. [ASSUMPTION, built on 05 section 2]

## C2. The private consumer project (project-specific parts)

```
<consumer project>/
├── CLAUDE.md                         project facts only: commands, quirks, architecture decisions
├── .claude/
│   ├── settings.json                 permission deny rules, sandbox, extraKnownMarketplaces (pinned ref),
│   │                                 enabledPlugins; this is the boundary a plugin cannot ship        [A1]
│   ├── rules/                        path-scoped instructions (advisory; see 02 section 2)
│   └── agents/                       copied agents that need hooks or permissionMode                 [A2]
├── .harness/
│   ├── config                        check commands (build, unit, lint, forge lint, UI tests), budgets
│   ├── protected-paths               tests, approved fixtures, snapshots, feature list
│   └── defects.md                    defect log that feeds B1 and B4
├── docs/spec/                        the spec and feature list that define "done"
├── tests/approved/                   approved fixtures and screenshot baselines (protected)
└── .github/workflows/                CI: full checks + diff guard + "harness-kit loaded" check (see 05)
```

## C3. Why this split, and the counter-case

- **Why** [ASSUMPTION]:
  - The plugin carries only what the platform lets a plugin carry and enforce: skills, hooks, read-only agents and evals. [ASSUMPTION]
  - Everything that forms the boundary lives in files the consumer project owns and commits: settings, protected paths, and agents that need hooks. [ASSUMPTION]
  - The CI checks run outside the agent entirely, so they still hold when hooks are disabled, skipped by `--bare`, or broken by a Claude Code regression. [ASSUMPTION]
- **Counter-case** [ASSUMPTION]:
  - The `setup-project` copy step creates template drift, the same problem Böckeler warns about. Copies in consumer projects fall behind the kit. [ASSUMPTION]
  - A mitigation is to keep templates small and re-run setup on each kit release, reviewing the diff, as `copier update` does. [ASSUMPTION]
  - If drift proves painful, the alternative is managed settings, which override everything but are an organisation-level tool, or accepting a less generic, topology-specific kit. [ASSUMPTION]
- **Note on `bin/`** [VERIFIED | claude.com/docs/plugins/platform-support | accessed 2026-09-26]: a top-level `bin/` folder makes the plugin uninstallable in Cowork and claude.ai chat. The layout above therefore keeps executables in `scripts/`, called by hooks, rather than in `bin/`.

## Negative results

- **An official mechanism to keep `hooks`, `mcpServers` or `permissionMode` in plugin agents,** other than copying the file into `.claude/agents/`: NOT FOUND.
- **Official guidance on seeded-fault or mutation testing of agent gates:** NOT FOUND.
- **Standard harness quality metrics** (escaped defects, gate false-block rate, intervention rate): NOT FOUND in any harness-specific source.
- **A named company case study of distributing one Claude Code harness across projects:** NOT FOUND. Only documented mechanisms and Every's public plugin were found.
- **A cookiecutter-style scaffold for agent harnesses:** NOT FOUND.
