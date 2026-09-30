# 02 — GitHub Issues and Projects for one person with a personal account (question B)

Written on Wednesday 30 September 2026. Research only: nothing was created or changed on GitHub.

## Terms used in this file

- **Issue.** A numbered item in a repository's issue list (`#12`), with a title, a body, comments, and an open or closed state.
- **Personal account.** A GitHub account that belongs to one person, as opposed to an **organisation**, which is a shared account that owns repositories on behalf of a group. harness-kit belongs to the personal account `AayushSanjar`.
- **Label.** A coloured tag attached to issues in one repository.
- **Milestone.** A named group of issues in one repository, with an optional due date and a percentage complete.
- **Sub-issue.** An issue linked under another issue, its **parent**, forming a tree.
- **Issue type.** A built-in classification (Task, Bug, Feature, or custom), defined by an organisation.
- **Issue field.** A typed value on an issue (such as Priority), also defined by an organisation.
- **Issue dependency.** A "blocked by" or "blocking" link between two issues.
- **Project.** GitHub's planning tool (formerly called Projects v2): a table, board or roadmap view over issues, with its own **custom fields** (for example Status or Priority). A **user project** belongs to a personal account.
- **Built-in workflow.** An automation inside a project, such as "when an issue is closed, set Status to Done".
- **Issue template and issue form.** Files in `.github/ISSUE_TEMPLATE/` that pre-fill a new issue. A template is plain Markdown; a form is a YAML file that shows input boxes.
- **Closing keyword.** A word such as `Fixes`, `Closes` or `Resolves` followed by `#12`, which closes issue 12 when the change reaches the default branch.
- **Default branch.** The main branch of the repository (`main` here).
- **gh.** GitHub's official command-line tool.
- **MCP server.** A program that offers tools to an AI agent. GitHub publishes an official one.
- **Classic token and fine-grained token.** Two kinds of personal access token (a password-like key for scripts). Classic tokens use broad scopes; fine-grained tokens are limited to named repositories and permissions.

## How this file is based on evidence

**Sources.** This file draws on 98 sources, of which 83 are primary.
- **Primary, from GitHub itself (77):**
  - 53 pages of GitHub's documentation source, read from the `github/docs` repository with every included snippet expanded (48 read in full, 5 searched for specific lines);
  - GitHub's limits and feature-flag data files;
  - 8 source files of `gh` plus its manual;
  - the README of GitHub's MCP server;
  - 9 GitHub blog or changelog posts.
- **Primary, my own live checks (6):** checks through GitHub's public programming interface on a personal-account repository.
- **Secondary (15):** community forum threads, other people's repository issues and personal blogs.

**How they were chosen.**
- Documentation pages were chosen by walking the documentation's own section tree for issues, labels, milestones and projects, then adding the pages the questions need.
- Changelogs and forum threads were found by web search, only where the documentation was silent or ambiguous.
- The two most important open questions (sub-issues on a personal account, and closing keywords on a direct push) were then tested against public data, as described in the contradictions.

**How pages were read.**
- **Full reads:** the documentation source files, the `gh` source, and the programming-interface answers.
- **Extracts:** blog posts, changelogs and forum threads, which came through a summarising fetch tool.

**Labels.**
- [VERIFIED] means a primary source says it.
- [PARTIAL] means secondary or partly supported.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

## CONTRADICTIONS

1. **Issue types (Bug, Feature, Task) do not exist for a personal account.**
   - The docs say: "Issue types are defined at the organization level and can be used to create a shared syntax across repos", and "Organization owners can modify issue types". [VERIFIED | github/docs syntax-for-issue-forms and managing-issue-types-in-an-organization, full read, 2026-09-30]
   - One outside test found that on a personal account, setting a type through the programming interface "returns success but silently ignores the type field". [PARTIAL | third-party issue TzuH-Hsu/github-project-os#42, 15 September 2026, extract]
   - The issues I read on a personal-account repository have no type value. [VERIFIED | GitHub REST API, simonw/datasette issues, read 2026-09-30]
   - The substitute is labels, or a single-choice field in a project.
2. **Issue fields (typed values such as Priority on the issue itself) are organisation-only too.** "Fields are defined at the organization level and apply across all repositories in your organization." [VERIFIED | github/docs managing-issue-fields-in-your-organization, full read] Custom fields in a project are the substitute.
3. **Earlier doubt resolved: sub-issues do work on a personal account.**
   - A community forum answer said sub-issues are "available only for organizations". [PARTIAL | GitHub Community discussion #175785, October 2025, non-staff, extract]
   - I checked a public repository owned by a personal account. `simonw/datasette` has owner type "User", and its issue #2937, "Tracking issue for things to review for Datasette 1.0" (opened 17 September 2026), has 36 sub-issues. Issues #2943 and #2944 have sub-issues too. [VERIFIED | GitHub REST API: /repos/simonw/datasette, /issues/2937/sub_issues, read 2026-09-30, full read of the JSON]
   - A one-issue test on harness-kit itself is still cheap insurance. [ASSUMPTION]
4. **Earlier doubt resolved: a closing keyword in a commit pushed straight to `main` closes the issue, with no pull request.**
   - The documentation only says the issue closes "when you merge the commit into the default branch" [VERIFIED | github/docs linking-a-pull-request-to-an-issue, full read], and one outside post claimed it "never fires on a direct push" [PARTIAL | ProAgentStore/platform#816, 19 September 2026, extract, no evidence given].
   - I checked a real case:
     - Commit `9cdf95ac2c` in `simonw/datasette`, whose message includes "closes #2446", is contained in no pull request.
     - Issue #2446 has a "closed" event at 2026-09-17 04:23:58 UTC carrying that commit's identifier, four seconds after the commit's time.
     - [VERIFIED | GitHub REST API: /commits/9cdf95ac2c…/pulls returned an empty list; /issues/2446/events, read 2026-09-30]
   - A normal push of `main` is a fast-forward, which is what `release.sh` does. So a `Fixes #N` line in a commit that `release.sh` pushes should close the issue at release time. [ASSUMPTION for release.sh specifically, reasoned from that case]
5. **An issue has no Status of its own.** It is only open or closed (with a reason). "Status" is a field of a project. An issue that is in no project has no Status. [VERIFIED for workflows updating a project's Status | github/docs using-the-built-in-automations; the wording "no status outside a project" is ASSUMPTION]
6. **The built-in CI token cannot reach a project, and neither can a fine-grained token for a user-owned project.**
   - "`GITHUB_TOKEN` is scoped to the repository level and cannot access Projects." [VERIFIED | github/docs automating-projects-using-actions]
   - The token documentation lists "Using fine-grained personal access token to access Projects owned by a user account" among the known gaps. [VERIFIED | github/docs managing-your-personal-access-tokens]
   - Scripts that write to your project need a classic token with the `project` scope. For `gh` this means running `gh auth refresh -s project` once.
7. **A project view cannot be grouped by label.** "You cannot group by title, labels, reviewers, or linked pull requests." [VERIFIED | github/docs customizing-the-table-layout] Anything you want as a board column must be a single-choice project field.
8. **Automation does not add issues that already exist.** "When you enable the auto-add workflow, existing items matching your criteria will not be added." GitHub Free allows one auto-add workflow. [VERIFIED | github/docs adding-items-automatically]
9. **GitHub does not close a parent issue when its sub-issues close.** NOT FOUND in the documentation. GitHub Next publishes a separate workflow to do it, which suggests the platform does not. [PARTIAL | githubnext/agentics docs/sub-issue-closer.md, full read]
10. **`gh` cannot create a milestone.** There is no `gh milestone` command; `gh issue create --milestone` only attaches an existing one. [VERIFIED | gh source, command list, 2026-09-30]

## 1. Summary table

| Feature | What it is | Works on a personal account with a public repository? | Limits | Cost |
|---|---|---|---|---|
| Sub-issues | Parent and child links, with a progress count on the parent | **Yes** [VERIFIED by a live example, contradiction 3] | 100 sub-issues per parent; 8 levels deep [VERIFIED \| adding-sub-issues; projects.yml] | Free |
| Issue types | Organisation-defined classification | **No** [VERIFIED] | 25 per organisation | n/a |
| Issue fields | Organisation-defined typed values on issues | **No** [VERIFIED] | 25 per organisation | n/a |
| Issue dependencies | "Blocked by" and "blocking" links | **Yes**: "available for users on GitHub Free, GitHub Pro …" [VERIFIED \| creating-issue-dependencies] | 50 per relationship type [VERIFIED \| changelog 2025-08-21] | Free |
| Labels | Per-repository tags | Yes [VERIFIED] | NOT FOUND (no documented cap) | Free |
| Milestones | Per-repository group with due date and % complete | Yes [VERIFIED] | Drag-to-reorder stops above 500 open issues in a milestone [VERIFIED] | Free |
| User project | Table, board or roadmap with custom fields and automations | Yes: "User projects can track issues and pull requests from the repositories owned by your personal account" [VERIFIED] | 50,000 items; 50 fields; 50 options per single-choice field; 1 auto-add workflow on Free [VERIFIED] | Free |
| Issue templates and forms | Files in `.github/ISSUE_TEMPLATE/` | Yes [VERIFIED]; the form's `type:` key does nothing without organisation issue types | Forms are "in public preview and subject to change" [VERIFIED] | Free |
| Closing keywords | `Fixes #12` in a commit or pull request | **Yes, including direct pushes to the default branch** [VERIFIED by a live example, contradiction 4]; other branches only add a reference | Default branch only | Free |
| Pinned issues | Up to 3 issues shown above the list | Yes [VERIFIED] | 3 per repository | Free |
| Saved replies | Reusable comment text | Yes [VERIFIED] | 100 per account | Free |
| Copilot coding agent | Assign an issue to GitHub's own agent | Paid Copilot plans only [VERIFIED \| about-cloud-agent] | — | Paid (not recommended here) |

## 2. Details that matter for your setup

**Sub-issues.**
- Create one from the parent issue with **Create sub-issue**, or attach an existing issue with **Add existing issue**. [VERIFIED | adding-sub-issues]
- `gh` 2.94.0 or later supports them directly [VERIFIED | gh source pkg/cmd/issue/create and edit, read 2026-09-30]:
  - `gh issue create --title T --body B --parent 12`;
  - `gh issue edit 12 --add-sub-issue 13,14`;
  - `gh issue edit 13 --parent 12`;
  - `gh issue view 12 --json parent,subIssues,subIssuesSummary`.
- Older `gh` versions need the programming interface, which takes the sub-issue's internal identifier, not its number. [VERIFIED | github-mcp-server README]
- In a project, the hidden fields **Parent issue** and **Sub-issue progress** can be shown, and a view can be grouped by Parent issue. [VERIFIED | about-parent-issue-and-sub-issue-progress-fields]

**Labels.**
- Every new repository has 10 default labels: accessibility, bug, documentation, duplicate, enhancement, good first issue, help wanted, invalid, question and wontfix. Labels are per repository. [VERIFIED | managing-labels]
- `gh label create NAME --description D --color HEX --force` creates or updates one. [VERIFIED | gh source]

**Projects.**
- **Create a project:** profile picture, then **Your profile**, then **Projects**, then **New project**. [VERIFIED | creating-a-project]
- **Link it to the repository:** repository **Projects** tab, then **Link a project**. [VERIFIED]
- **Custom field types:** text, number, date, single select and iteration (repeating time blocks). [VERIFIED]
- **Views:** table, board and roadmap. A board's columns can be set to any single-select or iteration field. [VERIFIED]
- **Built-in workflows:** open the project's **⋯** menu, then **Workflows**. [VERIFIED]
  - The documentation says two are on by default: an item closed sets Status to Done, and a merged pull request sets Done.
  - Changelogs add two newer defaults: an "Auto-close issue" workflow that closes an issue when its Status becomes Done (April 2024), and "Pull request linked to issue" (November 2025).
  - The sources disagree. Check the Workflows page after creating the project. [VERIFIED for each statement; the conflict is real]
- **Auto-add:** filters by `is`, `label`, `reason`, `assignee` and `no`. **Auto-archive:** filters by `is`, `reason` and `updated`. [VERIFIED]
- **gh commands** (the minimum token scope is `project`, or `read:project` for reading) [VERIFIED | gh source project.go and manual]:
  - `gh project field-list 1 --owner @me`
  - `gh project item-add 1 --owner @me --url <issue URL>`
  - `gh project item-edit … --field Status --value "In progress"`, which changes one field per call.
- **GitHub's MCP server:** the `projects` toolset is off by default. [VERIFIED | github-mcp-server README]

**Issue forms.**
- A form sets `name`, `description` and `body`, and optionally `title`, `labels`, `assignees` and `projects` (as `OWNER/NUMBER`). [VERIFIED | syntax-for-issue-forms]
- A label that does not already exist is not created.
- `blank_issues_enabled: false` in `config.yml` hides the blank issue from others; you, as owner, still see it, marked "Maintainers only". [VERIFIED | configuring-issue-templates]

**Closing keywords.**
- The keywords are close, closes, closed, fix, fixes, fixed, resolve, resolves and resolved, with or without a colon, in any case. [VERIFIED]
- Each issue needs its own keyword: write `Fixes #1, fixes #2`.
- Pushes to other branches do not close the issue; they only add a reference. [VERIFIED | GitHub blog 2013, extract; old documentation]

**Rate limits that affect an agent.**
- 5,000 requests per hour per user. [VERIFIED | REST rate-limit documentation]
- For creating content (issues, comments, labels, sub-issue links), "no more than 80 content-generating requests per minute and no more than 500 content-generating requests per hour". [VERIFIED | same page]
- A breach returns error 403 or 429.
- Importing a backlog of about 100 issues with sub-issue links is roughly 200 to 300 writes. It must be spread over at least one hour, one write per second or slower. [ASSUMPTION: arithmetic on those limits]

**Edit history.** GitHub now keeps "a limit of 100 stored edits per content item". [PARTIAL | changelog 2026-07-02, extract] A status comment edited on every step loses its oldest history after 100 edits.

## Negative results

- A GitHub statement, dated 2025 or 2026, that issue types or issue fields are available to personal accounts: NOT FOUND.
- A documented limit on labels per repository, projects per user or views per project: NOT FOUND.
- A `gh` command to create milestones, or an MCP server tool for issue dependencies: NOT FOUND.
- An up-to-date documentation list of default project workflows that agrees with the changelogs: NOT FOUND.
- A primary statement explicitly about "fast-forward" pushes and closing keywords: NOT FOUND. The live example covers an ordinary push, which is a fast-forward.

## Strongest counter-cases

- **Against using a project at all.** It adds a second place where state lives (Status), needs the `project` token scope for scripts, and cannot group by label. Labels, milestones and `gh issue list` filters may be enough for one person. The answer to that: labels give no board and no roadmap view, and you asked for one board.
- **Against labels as types.** Labels are free text, so an agent can invent `bug` next to `type:bug`. A fixed list, created once with `gh label create --force` and named in the instructions, reduces the drift. A weekly health check (file 05) catches the rest.
- **Against moving to a free organisation to get issue types.** It would unlock issue types and issue fields, but it changes the repository's owner and address, which the plugin's marketplace pin and every installation depend on. [ASSUMPTION] Not recommended for now.
- **Against the classic token scope.** A classic token with `project` scope can reach every project you own. For one person that is acceptable; set an expiry. [ASSUMPTION]

**Confidence.** High for the features table and both resolved contradictions, because each rests on documentation read in full or on live data. Medium for which project workflows are on by default, because the sources disagree.
