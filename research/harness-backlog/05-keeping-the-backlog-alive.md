# 05 — Keeping the backlog alive with little effort (question E)

Written on Wednesday 30 September 2026. Research only.

## Terms used in this file

- **Backlog.** The set of open issues that describe work not yet done.
- **Triage.** Deciding, for a new issue, what kind it is, whether it is valid, and where it goes.
- **Stale item.** An issue that has had no activity for a long time. A **stale bot** marks such issues and then closes them automatically.
- **Built-in workflow.** An automation inside a GitHub project, such as "when an issue closes, set Status to Done".
- **Auto-add.** A built-in workflow that adds new issues to a project when they match a filter.
- **Auto-archive.** A built-in workflow that hides old finished items from project views.
- **Health check.** A report, run weekly, that lists backlog problems without changing anything.
- **Prompt injection.** Text in an issue, written by anyone, that tries to give instructions to an AI agent reading it.
- **Closing keyword.** `Fixes #N`, `Closes #N` or `Resolves #N`, which closes the issue when the commit reaches `main`.

## How this file is based on evidence

**Sources.** This file draws on 56 sources, of which 53 are primary:
- GitHub's documentation source files;
- the repositories and licence files of `actions/stale` and `actions/add-to-project`;
- the workflows and scripts in Anthropic's `anthropics/claude-code` repository;
- GitHub's and GitHub Next's own tools;
- two research papers;
- maintainers' own posts;
- my live checks of GitHub's public data.

The 3 secondary sources are a blog experiment, a third-party workflow example and one failed fetch.

**How they were chosen.** For each question I went to the page that owns the answer rather than sampling.

**How pages were read.**
- **Full reads:** documentation source and repository files, read as raw text.
- **Extracts:** papers and blog posts.
- **Not trusted:** the release dates of `actions/stale` and `actions/add-to-project`, because the fetched release pages gave impossible sequences.

**Labels.**
- [VERIFIED] means a primary source says it.
- [PARTIAL] means secondary or partly supported.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

## CONTRADICTIONS

1. **Earlier doubt resolved: `Fixes #N` works on a commit pushed straight to `main`.**
   - The documentation only says "when you merge the commit into the default branch". [VERIFIED | github/docs linking-a-pull-request-to-an-issue]
   - A live example shows it working without a pull request: `simonw/datasette` commit `9cdf95ac2c` is in no pull request and closed issue #2446. [VERIFIED | GitHub REST API, read 2026-09-30] (Details in file 02.)
2. **GitHub does not close a parent issue when all its sub-issues close.** NOT FOUND in the documentation. GitHub Next publishes a separate "Sub-Issue Closer" workflow for it. [VERIFIED | githubnext/agentics docs/sub-issue-closer.md, full read]
3. **The best-known stale-bot paper is from 2019 and is not evidence against stale bots.**
   - "Should I stale or should I close?" (Wessel and others, BotSE 2019) only describes the settings of 765 projects. [VERIFIED | paper, extract]
   - The evidence against comes from a 2023 study of 20 large projects, which found "a considerable decrease in their number of active contributors" after a stale bot was adopted. [VERIFIED | arXiv 2305.18150, extract]
4. **Vendors disagree on agents merging their own work.**
   - GitHub's Copilot agent "cannot push directly to your default branch", and a human must merge. [VERIFIED | github/docs Copilot risks and mitigations, extract]
   - OpenAI says its agents "often squash and merge their own pull requests". [VERIFIED | openai.com harness-engineering, 2026-02-11, extract]
   - Your setup keeps merging with you, through `release.sh`, which is closer to GitHub's rule. [ASSUMPTION]

## 1. What updates itself when work lands

| Event | What updates | Needs | Evidence |
|---|---|---|---|
| A released commit contains `Fixes #42` | Issue 42 closes, with a link to the commit | Nothing | [VERIFIED \| live example, contradiction 1] |
| An issue in the project closes | Its Status becomes Done | Nothing: this workflow is on by default | "two workflows are enabled by default: When issues or pull requests in your project are closed, their status is set to Done …" [VERIFIED \| github/docs using-the-built-in-automations] |
| A new issue is opened | It joins the project | Turn on auto-add with the filter `is:issue` (your single free slot) | "existing items matching your criteria will not be added" [VERIFIED \| adding-items-automatically] |
| An item has been Done for a month | It disappears from views | Turn on auto-archive with `is:closed updated:<@today-1m` | [VERIFIED \| archiving-items-automatically] |
| All sub-issues close | Nothing | A person, or a separate workflow | NOT FOUND (contradiction 2) |

These built-in workflows run inside GitHub: no token and no Actions minutes. [ASSUMPTION] A GitHub Action that writes to your user-owned project would need a classic token with the `project` scope, because the built-in CI token and fine-grained tokens cannot reach it. [VERIFIED | github/docs automating-projects-using-actions; managing-your-personal-access-tokens] So avoid Actions for project updates and use the built-in workflows.

## 2. Stale items

**The tool.** `actions/stale` version 11.0.0 marks items stale after 60 days by default and closes them 7 days later as "not planned". Any comment resets the clock, so an agent that comments would keep items alive forever. [VERIFIED | actions/stale action.yml and README, full read]

**Anthropic's own practice.** Anthropic does not use `actions/stale` on its own repository. Its own script [VERIFIED | anthropics/claude-code scripts/sweep.ts, full read]:
- marks an issue stale after 14 days;
- skips issues that are assigned or have 10 or more thumbs-up reactions;
- closes after another 14 days, unless a person commented.

**For you.** You are the only person filing issues, so the argument against stale bots (driving contributors away) mostly does not apply. The real risk is a bot silently closing real work as "not planned". [ASSUMPTION]

**Recommendation.** No stale bot. The weekly health check lists old items and you decide. [ASSUMPTION]

## 3. AI triage

**Anthropic's triage workflow on its own repository** is the best-documented example. [VERIFIED | anthropics/claude-code .github/workflows/claude-issue-triage.yml and scripts, full read]
- It runs claude-code-action when an issue is opened.
- It may only add or remove labels.
- It reaches GitHub through a wrapper script that allows only `issue view`, `issue list`, `search issues` and `label list`.
- It is capped at two label-editing calls.
- It uses the short-lived CI token, on a firewalled runner.
- Duplicates are closed by a plain script with no AI, three days after the bot's comment, unless the author objects.

**The catch.**
- Anyone can open an issue on a public repository, and issue text reaches the model. Anthropic's documentation calls letting non-collaborators trigger the action "RISKY". [VERIFIED | claude-code-action docs/security.md, full read]
- If a local Claude Code session reads issue text under your full `gh` login, the same risk applies without those fences. [ASSUMPTION]

**Recommendation.** No AI triage for now. Revisit it only if other people start filing issues, and then copy Anthropic's pattern exactly: labels only, a wrapper script, call caps, and no personal token. [ASSUMPTION]

## 4. A weekly health check

An existing tool that does the structural checks you need: NOT FOUND.
- The closest is GitHub's `issue-metrics` action, which measures response and close times, not structure. [VERIFIED | github-community-projects/issue-metrics README]
- GitHub Next's "Issue Arborist" creates parent links by itself, which would change your hierarchy without asking. [VERIFIED | githubnext/agentics]

**Proposed check** [ASSUMPTION]. A script run by Claude Code on your Mac once a week, which **reports only**. It writes `docs/backlog-health.md` or edits one pinned "Backlog health" issue. It lists:
1. open issues with no `type:*` label, or with more than one;
2. Stories, Tasks and Bugs with no parent Epic;
3. items marked Ready that fail the Definition of Ready (no Why line, no acceptance criteria, or size L);
4. items In progress with no update for 14 days;
5. open parents whose sub-issues are all closed ("close this epic?"), read with `gh issue view N --json parent,subIssues,subIssuesSummary` [VERIFIED fields | github/docs browsing-sub-issues];
6. bugs labelled `regression` with no "Caused by:" line;
7. closed issues whose project Status is not Done, and the reverse.

It changes nothing. You decide each fix, or tell Claude to make it.

**Limits to respect.** Content-creating calls are limited to 80 per minute and 500 per hour, and GitHub advises "wait at least one second between each request" for writes. [VERIFIED | GitHub REST rate-limit and best-practices documentation] A read-only weekly report is far below these limits.

## 5. What must stay your decision

The sources agree that humans set direction:
- "We prioritize work, translate user feedback into acceptance criteria, and validate outcomes." [VERIFIED | OpenAI harness-engineering, 2026-02-11, extract]
- Humans "should retain control over how their goals are pursued, particularly before high-stakes decisions". [VERIFIED | Anthropic, "Our framework for developing safe and trustworthy agents", 2025-08-04, extract]

**Yours** [ASSUMPTION]:
- priority and order;
- marking items Ready;
- closing as "not planned";
- accepting a report as a real bug;
- approving scope and acceptance criteria;
- deciding that an epic is finished;
- reopening.

**The agent's, within the rules**:
- drafting items;
- filling in missing links and labels that follow from a written rule, after you approve the change;
- commenting with evidence;
- closing the issue its own released commit fixes, through `Fixes #N`, for an item whose brief you approved.

## Negative results

- Native closing of a parent when its sub-issues close: NOT FOUND.
- A tool that runs the structural health checks above: NOT FOUND.
- The cost of one run of Anthropic's triage workflow: NOT FOUND.
- A readable post defending stale bots: NOT FOUND (the one found failed to load).
- Reliable release dates for `actions/stale` and `actions/add-to-project`: NOT FOUND.

## Strongest counter-cases

- **A report nobody reads changes nothing.** If you skip the weekly report, the backlog drifts exactly as without it. The mitigation is to make the start agent show the report's first three lines when it starts. [ASSUMPTION]
- **`Fixes #N` closes the issue when the commit reaches `main`, which is also when it is released.** In your flow those are the same moment, so "Done" means "released". If you ever push `main` outside `release.sh`, "Done" will no longer mean "released".
- **Auto-add adds every new issue, including noise.** For a repository where only you file issues, that is fine.
- **No AI triage means nothing happens while Claude is not running.** For one person, that is the point: nothing changes without you.

**Confidence.** High for what updates automatically (documentation plus a live example). Medium for the health-check design.
