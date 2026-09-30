# 05 — Automated gardening: agents that find and fix drift, how they avoid being confidently wrong, and what a person approves (research question E)

Status on 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Gardening agent:** an AI agent that looks for drift (documents, comments or tests that no longer match the code) and proposes or makes fixes, on a schedule or when something happens.
- **Scheduled** means it runs at set times, for example every Sunday. **Event-driven** means it runs when something happens, for example when a pull request changes certain files.
- **Pull request (PR):** a proposed change on a branch that a person reviews before it is merged. A **draft pull request** is marked as not ready and cannot be merged until someone marks it ready.
- **Automerge:** merging a change automatically when its checks pass, with no person approving it.
- **Report-first:** the agent first writes a list of findings and proposed edits, and changes nothing until a person says which to apply.
- **Advisory agent:** an agent that may only report, never edit.
- **Safe outputs (GitHub's term):** a design where the agent runs with read-only access and asks for changes in a structured form, and a separate, limited job carries them out.
- **Prompt injection:** text in the material an agent reads (code, an issue, a web page) that tries to give the agent instructions.
- **Precision and recall:** of the problems an agent flags, precision is the share that are real; of the real problems, recall is the share it flags.
- **GitHub Actions minutes:** the machine time GitHub charges for its hosted CI machines.

## How this file is based on evidence

- **Sources.** This file cites 37 sources, 37 of them primary.
- **How they were chosen.** A research sub-agent read 78 pages (75 primary): OpenAI's post, the Claude Code GitHub Action's documentation and repository, GitHub Agentic Workflows' reference pages and sample workflows, Anthropic's and the community's documentation agents, commercial products, and research on automatic comment updating. Its searches ran out after 25; topics it could not search are marked NOT SEARCHED.
- **What your existing research already covers, and this file does not repeat:** OpenAI's recurring clean-up agents and the 20% of each week they replaced, GitHub Next's merge counts for its documentation workflows (88 of 103 and 57 of 59), Claude Code's scheduling options (`/loop`, cloud routines, desktop scheduled tasks, GitHub Actions schedules), and `/doctor` and `/skill-doctor`; also Anthropic's hookify, security-guidance, code-review and ralph-loop plugins, and a public showcase's monthly documentation-sync workflow. [VERIFIED | github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/04-replication.md | 2026-09-26 | extract] [VERIFIED | github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/03-reference-harnesses.md | 2026-09-26 | full]
- **What I checked myself.** I re-read OpenAI's post, the Claude Code GitHub Actions page and memory page (both returned in full), the Action's solutions and FAQ pages, GitHub Agentic Workflows' safe-output pages and security advisories, the documentation-updater sample, and Anthropic's comment-analyzer agent and claude-md-improver skill.
- **Labels** are as in file 01. Definitions, statements about how this research was done, and proposed steps are not research claims. A label placed just before or just after a list or table applies to every item in it.

## CONTRADICTIONS

1. **OpenAI's doc-gardening works because people do not have to approve it.** "Humans may review pull requests, but aren't required to. Over time, we've pushed almost all review effort towards being handled agent-to-agent." Clean-up changes are small: "Most of these can be reviewed in under a minute and automerged." [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract] Your operating model has the person approve every change. Copying OpenAI's gardener as designed means giving that up; keeping your model means a different design (section 7).
2. **The Claude Code GitHub Action on a schedule does not open pull requests by default.** "Claude doesn't create PRs by default. Instead, it pushes commits to a branch and provides a link to a pre-filled PR submission page." [VERIFIED | github.com/anthropics/claude-code-action/blob/main/docs/faq.md | accessed 2026-09-30 | extract] The official weekly maintenance example ends by asking Claude to "Create a single issue summarizing any findings." [VERIFIED | github.com/anthropics/claude-code-action/blob/main/docs/solutions.md | accessed 2026-09-30 | extract] In public repositories GitHub "disables the schedule after 60 days without repository activity". [VERIFIED | code.claude.com/docs/en/github-actions | accessed 2026-09-30 | full]
3. **GitHub Agentic Workflows has moved on, and its safety layer has had serious bugs.** It is now in public preview, not technical preview. [VERIFIED as read by a sub-agent | github.blog/changelog/ | 2026-06-11] Its Claude engine requires an Anthropic API key; no Claude subscription token is listed. [VERIFIED as read by a sub-agent | github.github.com/gh-aw/reference/engines/ | accessed 2026-09-30] Its security page lists ten advisories published in August 2026, four of them critical, including "safe-output validator forwards undeclared agent fields to the appliers (scope escape / mass assignment)". [VERIFIED | github.com/github/gh-aw/security/advisories | advisories published 2026-08-06 to 2026-08-29 | extract]
4. **The cheapest AI gardener is already built into Claude Code.** `/doctor prompt-audit` checks instruction files (CLAUDE.md, skills, agents, commands and rules) for "instructions written for older models, references to files or commands that don't exist, and files that contradict each other"; "nothing in your files changes until you ask Claude to apply them". It needs Claude Code v2.1.283 or later. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-30 | full]

## 1. OpenAI's design, in its own words

- "A recurring 'doc-gardening' agent scans for stale or obsolete documentation that does not reflect the real code behavior and opens fix-up pull requests." [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract]
- Code checks the knowledge base first: "We enforce this mechanically. Dedicated linters and CI jobs validate that the knowledge base is up to date, cross-linked, and structured correctly." [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract]
- Their principles live in the repository and a recurring process enforces them: "we started encoding what we call 'golden principles' directly into the repository and built a recurring cleanup process." "This functions like garbage collection." [VERIFIED | openai.com/index/harness-engineering | 2026-02-11 | extract]
- An error rate, a revert count or an example of a wrong edit by the gardener: NOT FOUND in the post.

## 2. The Claude Code GitHub Action (anthropics/claude-code-action)

[VERIFIED | code.claude.com/docs/en/github-actions | accessed 2026-09-30 | full]

- **Scheduling.** "With a `prompt` input, the Claude Code GitHub Action runs in automation mode on any GitHub event, including a cron schedule." A plain-text prompt gets no shell or GitHub access "until you grant the tools the prompt needs". Results go to the workflow log by default.
- **Who can trigger it.** Scheduled runs skip the write-access check but still reject bots; GitHub attributes a scheduled run to "the one who last changed the workflow's `cron` schedule".
- **Cost has two parts.** The runners "consume your GitHub Actions minutes", and each run consumes model tokens; "If you authenticate with an OAuth token, runs use your Claude subscription instead of API billing." The token comes from `claude setup-token` on Pro, Max, Team and Enterprise plans.
- **Commits it makes may not trigger CI:** "GitHub doesn't trigger workflows on commits made with the default `GITHUB_TOKEN`."
- **Minutes:** "GitHub Actions usage is **free** for **self-hosted runners** and for **public repositories**". For private repositories, GitHub Free includes 2,000 minutes a month, and "If your account does not have a valid payment method on file, usage is blocked once you use up your quota." [VERIFIED | docs.github.com/en/billing/concepts/product-billing/github-actions | accessed 2026-09-30 | extract]
- **The official examples.** "Weekly Maintenance" runs at `0 0 * * 0` (Sunday midnight), includes the step "Verify README.md examples still work", ends with "Create a single issue summarizing any findings", and allows only `Read,Bash(npm:*),Bash(gh issue:*),Bash(git:*)`. "Sync API Documentation" runs when a pull request changes files under `src/api/` or `src/routes/`, and says "Commit any documentation updates to this PR branch." [VERIFIED | github.com/anthropics/claude-code-action/blob/main/docs/solutions.md | accessed 2026-09-30 | extract]
- **Security.** The Action's security page warns that external contributors "may include hidden instructions through HTML comments, invisible characters, hidden attributes, or other techniques". [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-action/blob/main/docs/security.md | accessed 2026-09-30] MIT licence; its latest release seen was v1.0.236 on 28 September. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-action | v1.0.236 on 28 Sep (2026, inferred)]

## 3. GitHub Agentic Workflows and its sample workflows

- **Safe outputs:** "agents run read-only and request actions via structured output, while separate permission-controlled jobs execute those requests." [VERIFIED | github.github.com/gh-aw/reference/safe-outputs/ | accessed 2026-09-30 | extract]
- **Pull-request limits:** by default one pull request per run; `draft: true` is the default and "enforced as policy"; a patch is limited by default to 100 files and 4,096 KB; an `expires` setting closes stale pull requests; and changes to protected files (dependency manifests, `AGENTS.md`, `CLAUDE.md`, `.github/`, `CODEOWNERS`, `DESIGN.md`) get a "request changes" review that a person must clear. The page mentions no auto-merge. [VERIFIED | github.github.com/gh-aw/reference/safe-outputs-pull-requests/ | accessed 2026-09-30 | extract]
- **Cost controls:** a `stop-after` date that switches a workflow off, a default cap of 1,000 "AI Credits" per run (one credit is one US cent), a 20-minute limit on the agent step, and `skip-if-match`, a deterministic check that runs in a cheap first job and cancels the workflow "before the agent starts". [VERIFIED as read by a sub-agent | github.github.com/gh-aw/reference/cost-management/ | accessed 2026-09-30]
- **GitHub's own documentation updater does not use drafts.** Its sample workflow sets `draft: false`, `expires: 2d` and a 30-minute limit, and says: "If there are no merged PRs in the last 24 hours, exit gracefully without creating a PR". [VERIFIED | github.com/githubnext/agentics/blob/main/workflows/doc-updater.md | accessed 2026-09-30 | extract]
- **Merge rates vary widely by task:** a glossary maintainer 10 of 10 merged, a "documentation noob tester" 9 of 21 (43%), a slide-deck maintainer 2 of 5, a repository quality improver 25 of 40. [VERIFIED as read by a sub-agent | github.github.com/gh-aw/blog/2026-01-13-meet-the-workflows-documentation | 2026-01-13]
- **A case study with people in the loop:** documentation drafted from product pull requests, with "draft: true (we never auto-merge)" and a subject-matter reviewer taken from the original pull request, had all 82 draft pull requests merged; an earlier version had about 13% closed, mostly for drafting documentation for internal changes such as "a CI tweak or a logging refactor". [VERIFIED as read by a sub-agent | github.blog (David Pine and Peli de Halleux, documentation kept in a separate repository) | 2026-07-08 or 2026-08-07 (sources disagree)]

## 4. Ready-made Claude Code agents and skills

- **comment-analyzer** (in Anthropic's pr-review-toolkit plugin) cross-checks "every claim in the comment against the actual code implementation", flags comments that "merely restate obvious code", "Outdated references to refactored code" and "TODOs or FIXMEs that may have already been addressed", and reports Critical Issues, Improvement Opportunities, Recommended Removals and Positive Findings. It is advisory by design: "You analyze and provide feedback only. Do not modify code or comments directly." [VERIFIED | github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/comment-analyzer.md | accessed 2026-09-30 | extract]
- **pr-test-analyzer** (same plugin) looks at behavioural coverage rather than line coverage and rates each gap from 1 to 10. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/pr-test-analyzer.md | accessed 2026-09-30] The plugin shows 114,856 installs and an "Anthropic Verified" badge; its README says MIT while its LICENSE file is Apache 2.0. [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-30]
- **claude-md-improver** (in the claude-md-management plugin) scores each CLAUDE.md out of 100 on commands, architecture, non-obvious patterns, conciseness, currency and actionability, and must "ALWAYS output the quality report BEFORE making any updates" and then "ask user for confirmation before updating". [VERIFIED | github.com/anthropics/claude-plugins-official/blob/main/plugins/claude-md-management/skills/claude-md-improver/SKILL.md | accessed 2026-09-30 | extract] The plugin shows 287,247 installs. [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-30]
- **Community agents** (VoltAgent's documentation-engineer, wshobson's docs-architect, davila7's update-docs command) are instruction files with no check of their own that claims match the code; VoltAgent's collection says "We do not audit or guarantee the security or correctness of any subagent." [VERIFIED as read by a sub-agent | github.com/VoltAgent/awesome-claude-code-subagents | observed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/wshobson/agents | observed 2026-09-30] [VERIFIED as read by a sub-agent | github.com/davila7/claude-code-templates | observed 2026-09-30]
- **Commercial tools.** Swimm now leads with legacy-code modernisation and publishes no prices; its auto-sync check still marks documents as possibly out of date when referenced code changes. DeepDocs updates documentation automatically and says "You approve the updates"; it is paid. Mintlify's automations "require a Pro or Enterprise plan". None offered source code on the pages read. [VERIFIED as read by a sub-agent | swimm.io/pricing | observed 2026-09-30] [VERIFIED as read by a sub-agent | deepdocs.dev | observed 2026-09-30] [VERIFIED as read by a sub-agent | www.mintlify.com/docs | observed 2026-09-30]

## 5. How accurate are automatic comment and document fixes?

- **Automatic comment updates are often not what a person wants.** A 2020 model's update matched the developer's exactly 18.4% of the time, against 13.7% for a simple rule; in a human study of 250 examples, people chose the model's update 30.2% of the time and "None" 55.0% of the time. [VERIFIED as read by a sub-agent | aclanthology.org/2020.acl-main.168 | 2020]
- **Detecting stale comments is easier than fixing them.** A 2020 detector reached precision 88.6 and recall 72.4 on a Java benchmark of 40,688 examples. [PARTIAL | arxiv.org/abs/2010.01625 | 2020-10] A 2023 tool reached 72.3% accuracy on the same benchmark, against 64.6% for GPT-3.5 without examples. [PARTIAL | arxiv.org/abs/2306.06347 | 2023]
- **Stale code references are common:** most of over 3,000 GitHub projects had at least one at some point in their history. [VERIFIED | arxiv.org/abs/2212.01479 | 2022-12-02 | extract (abstract)]
- Studies from 2024 to 2026 of current models on stale comments, and published cases of a documentation agent merging a wrong fact: NOT SEARCHED (the search budget had run out).
- Anthropic's own caution applies to any reviewing agent: "A reviewer prompted to find gaps will usually report some, even when the work is sound, because that is what it was asked to do." [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-30 | full]

## 6. Claude Code features useful for gardening (not in your earlier research)

- **A hook for scheduled clean-up:** the `Setup` event fires for `claude -p --maintenance`, for "one-time dependency installation or scheduled cleanup that you trigger explicitly from CI or scripts". "Setup hooks can't block." [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-30 | extract]
- **Observation hooks:** `InstructionsLoaded` fires when a CLAUDE.md or rules file is loaded, and `FileChanged` when a watched file changes; neither can block. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-30 | extract]
- **Agent hooks** "spawn a subagent that can use tools like Read, Grep, and Glob to verify conditions before returning a decision"; they are experimental. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-30 | extract]
- **Evidence over assertion:** "Have Claude show evidence rather than asserting success: the test output, the command it ran and what it returned, or a screenshot of the result." [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-30 | full]
- **Idle scheduled tasks still cost tokens:** a scheduled task "fires on its interval even while the session is idle, sending your full context each time". [VERIFIED as read by a sub-agent | code.claude.com/docs/en/costs | accessed 2026-09-30]
- **CLAUDE.md upkeep:** keep each CLAUDE.md under 200 lines, review it "periodically to remove outdated or conflicting instructions", and leave out "Information that changes frequently". [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-30 | full] [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-30 | full]

## 7. How gardeners avoid being confidently wrong, and what a person approves

[ASSUMPTION: my synthesis of sections 1 to 6; each row names the section that holds its evidence]

| Guard | Who uses it | Evidence |
|---|---|---|
| Deterministic checks run first, and the agent works only on what they flag or on a narrow scope | OpenAI (linters and CI jobs on the knowledge base); GitHub (a cheap pre-check that cancels the agent before it starts); Swimm (a failing check) | sections 1, 3, 4 |
| Report first, change only on approval | claude-md-improver; `/doctor prompt-audit`; comment-analyzer is advisory only | CONTRADICTIONS 4, section 4 |
| Evidence with every finding | Anthropic's best practices | section 6 |
| Small, capped, draft changes | GitHub Agentic Workflows: one pull request per run, drafts by default, patch limits, expiry, a stop date | section 3 |
| The writer cannot write directly | Safe outputs: the agent is read-only; a separate job applies approved outputs | section 3 |
| Protected files need a person | GitHub Agentic Workflows' protected-file rule; harness-kit's own protected paths | section 3 |
| A person merges | GitHub's case study ("we never auto-merge"); the Claude Code Action opens no pull request by default | sections 2, 3 |
| Measure acceptance | merge rates per workflow | section 3 |

[ASSUMPTION: my reading of the designs above] What the person approves, in the designs that keep a person in the loop: every change, one at a time, as a draft pull request or an issue; and every change to an instruction file or protected file. What OpenAI's design leaves to machines: review and merge of small clean-up changes (CONTRADICTIONS 1).

## 8. What this suggests

All of this section is my proposal. [ASSUMPTION, built on the evidence above]

A staged approach, each stage earning the next:

1. **Stage 0: deterministic checks** (file 03, section 7). They catch every drift case measured in this research: generated tables, the research index, names in living documents, runner completeness.
2. **Stage 1: a person-started gardening pass** in each repository, before each batch adoption of harness-kit into the gadget:
   - run `/doctor prompt-audit` (built in, report-first) on the instruction files;
   - run the comment-analyzer agent over the files changed since the last pass;
   - Claude writes one report to `.reports/` in which every finding has a file and line and a quoted piece of evidence, and proposes no edits it cannot back with evidence;
   - the person picks which findings become a brief, and the report records how many were accepted and rejected.
3. **Stage 2, only if stage 1's findings are mostly accepted over several passes:** turn the pass into a harness-kit skill that only the person can start (`disable-model-invocation: true`, as the existing skills do), still report-first. How many passes and what acceptance rate are enough is a threshold to decide with evidence then, not now.
4. **Stage 3, optional and harness-kit only:** a weekly run of the same skill in harness-kit's public CI with the Claude Code GitHub Action, producing one issue, as the official maintenance example does, and pushing nothing. Minutes are free for a public repository; the model usage needs your deferred decision about a key or subscription token in CI.
5. **Never:** automerge, an agent writing protected files, more than one change per run, or any scheduled agent in the gadget's CI (private-repository minutes).

### control-chart-gadget

The same stages apply. Its `CLAUDE.md` is the first target for `/doctor prompt-audit`: it lists harness-kit's hooks by hand (file 07) and carries fast-changing facts such as tool versions, which Anthropic's guidance says to leave out. [VERIFIED | control-chart-gadget/CLAUDE.md (private repository) | version 4.3, 2026-09-28 | seen in context]

## Negative results

- An error rate or wrong-edit example for OpenAI's gardener: NOT FOUND.
- A gardening agent that proves its documentation edits against the code, rather than reviewing them: NOT FOUND.
- Swimm's free tier and whether its auto-sync uses AI: NOT FOUND.
- Recent studies of current models on stale comments: NOT SEARCHED.

## Strongest counter-cases

[ASSUMPTION: every counter-case below is my reasoning, drawing on the evidence in this file]

- **For automation now:** OpenAI's experience is that clean-up done continuously in small pieces is cheaper than bursts, and a person-started pass depends on the person remembering. The counter-counter: the start-up picture could show the days since the last pass, as it already does for the fault replay.
- **Against any AI gardener:** the deterministic checks may catch everything that matters, and a reviewing agent "will usually report some" gaps even when the work is sound, which costs reading time.
- **Against the ready-made agents:** they are prompts, and their quality is unmeasured for this code; the acceptance record in stage 1 is how you would find out.
- **Against GitHub Agentic Workflows specifically:** it is pre-1.0, its safety layer had four critical advisories in one month, and its Claude engine needs an API key.

## Sources used in this file, and how each was read

Each line gives the title, the address, the publisher, the date, whether the source is primary or secondary, and how it was read ("full": the whole text; "extract": the passages the fetch tool returned; "sub-agent extract": read by a research sub-agent and not re-read by me; "measured": computed on the harness-kit clone).

- agentics: documentation updater workflow. https://github.com/githubnext/agentics/blob/main/workflows/doc-updater.md. GitHub Next; undated; accessed 2026-09-30; primary; read: extract.
- Anthropic plugin directory (install counts). https://claude.com/plugins. Anthropic; observed 2026-09-30; primary; read: sub-agent extract.
- awesome-claude-code-subagents (documentation-engineer). https://github.com/VoltAgent/awesome-claude-code-subagents. VoltAgent; observed 2026-09-30; primary; read: sub-agent extract.
- Best practices for Claude Code. https://code.claude.com/docs/en/best-practices. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Case study: agentic workflows drafting documentation pull requests. github.blog (David Pine and Peli de Halleux, documentation kept in a separate repository). GitHub blog; 2026-07-08 or 2026-08-07 (sources disagree); primary; read: sub-agent extract.
- Claude Code GitHub Actions. https://code.claude.com/docs/en/github-actions. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Claude Code: costs (scheduled tasks). https://code.claude.com/docs/en/costs. Anthropic; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- claude-code-action docs: FAQ. https://github.com/anthropics/claude-code-action/blob/main/docs/faq.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- claude-code-action docs: security. https://github.com/anthropics/claude-code-action/blob/main/docs/security.md. Anthropic; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- claude-code-action docs: solutions. https://github.com/anthropics/claude-code-action/blob/main/docs/solutions.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- claude-code-action repository and releases. https://github.com/anthropics/claude-code-action. Anthropic; v1.0.236 on 28 Sep (2026, inferred); primary; read: sub-agent extract.
- claude-code-templates (update-docs command). https://github.com/davila7/claude-code-templates. Daniel Avila; observed 2026-09-30; primary; read: sub-agent extract.
- claude-md-management: claude-md-improver skill. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/claude-md-management/skills/claude-md-improver/SKILL.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- control-chart-gadget CLAUDE.md, version 4.3. control-chart-gadget/CLAUDE.md (private repository). the person (private repository); 2026-09-28; primary; read: seen in context: loaded automatically by this session, not opened by me.
- Deep Just-In-Time Inconsistency Detection Between Comments and Source Code (Panthaplackel et al.). https://arxiv.org/abs/2010.01625. arXiv (AAAI 2021, venue not printed on the page read); 2020-10; primary; read: sub-agent extract.
- DeepDocs. https://deepdocs.dev. DeepDocs; observed 2026-09-30; primary; read: sub-agent extract.
- Detecting Outdated Code Element References in Software Repository Documentation (Tan, Wagner, Treude). https://arxiv.org/abs/2212.01479. arXiv; 2022-12-02; primary; read: extract (abstract).
- DocChecker: bootstrapping code LLMs for detecting code-comment inconsistencies. https://arxiv.org/abs/2306.06347. arXiv; 2023; primary; read: sub-agent extract.
- gh-aw security advisories. https://github.com/github/gh-aw/security/advisories. GitHub; advisories published 2026-08-06 to 2026-08-29; primary; read: extract.
- GitHub Actions billing. https://docs.github.com/en/billing/concepts/product-billing/github-actions. GitHub; undated; accessed 2026-09-30; primary; read: extract.
- GitHub Agentic Workflows: cost management. https://github.github.com/gh-aw/reference/cost-management/. GitHub; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- GitHub Agentic Workflows: engines. https://github.github.com/gh-aw/reference/engines/. GitHub; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- GitHub Agentic Workflows: Safe outputs. https://github.github.com/gh-aw/reference/safe-outputs/. GitHub; undated; accessed 2026-09-30; primary; read: extract.
- GitHub Agentic Workflows: Safe outputs for pull requests. https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/. GitHub; undated; accessed 2026-09-30; primary; read: extract.
- GitHub changelog: GitHub Agentic Workflows public preview. https://github.blog/changelog/. GitHub; 2026-06-11; primary; read: sub-agent extract.
- Harness engineering: leveraging Codex in an agent-first world. https://openai.com/index/harness-engineering. OpenAI (Ryan Lopopolo); 2026-02-11; primary; read: extract.
- harness-kit research 03: reference harnesses. https://github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/03-reference-harnesses.md. AayushSanjar (harness-kit); 2026-09-26; primary; read: full.
- harness-kit research 04: replication and self-improvement (Part B and Part C read). https://github.com/AayushSanjar/harness-kit/blob/main/research/initial-harness/04-replication.md. AayushSanjar (harness-kit); 2026-09-26; primary; read: extract (sections B2 to C3 read in full).
- Hooks reference. https://code.claude.com/docs/en/hooks. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- How Claude remembers your project (CLAUDE.md, /doctor prompt-audit). https://code.claude.com/docs/en/memory. Anthropic; undated; accessed 2026-09-30; primary; read: full.
- Learning to Update Natural Language Comments Based on Code Changes (Panthaplackel et al.). https://aclanthology.org/2020.acl-main.168. ACL 2020; 2020; primary; read: sub-agent extract.
- Meet the workflows: documentation. https://github.github.com/gh-aw/blog/2026-01-13-meet-the-workflows-documentation. GitHub Next (Don Syme, Peli de Halleux, Mara Kiefer); 2026-01-13; primary; read: sub-agent extract.
- Mintlify automations (plan requirement). https://www.mintlify.com/docs. Mintlify; observed 2026-09-30; primary; read: sub-agent extract.
- pr-review-toolkit: comment-analyzer agent. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/comment-analyzer.md. Anthropic; undated; accessed 2026-09-30; primary; read: extract.
- pr-review-toolkit: pr-test-analyzer agent. https://github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/agents/pr-test-analyzer.md. Anthropic; undated; accessed 2026-09-30; primary; read: sub-agent extract.
- Swimm pricing and home page. https://swimm.io/pricing. Swimm; observed 2026-09-30; primary; read: sub-agent extract.
- wshobson/agents (docs-architect). https://github.com/wshobson/agents. Seth Hobson; observed 2026-09-30; primary; read: sub-agent extract.
