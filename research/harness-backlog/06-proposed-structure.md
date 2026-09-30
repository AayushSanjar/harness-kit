# 06 — Proposed structure for harness-kit's backlog on GitHub (question F)

Written on Wednesday 30 September 2026. This is a proposal: nothing has been created.

## Terms used in this file

- **Label, milestone, sub-issue, project, custom field, built-in workflow, issue form, closing keyword.** As defined in file 02.
- **Epic, Feature, Story, Task, Bug, Definition of Ready, Definition of Done.** As defined in file 03.
- **Single-select field.** A project field whose value is one choice from a fixed list, for example Status. It can be a board column; a label cannot.
- **Status.** The project field that shows where an item is in the flow: Backlog, Ready, In progress, In review, Done.
- **Priority.** A project field that says how soon an item should be done, set only by you.
- **Size.** A project field that says roughly how big an item is.
- **Slug.** A short lowercase name made of words joined by hyphens, used in branch names.

## How this file is based on evidence

**Sources.** This file draws on the sources of files 02 and 03: 157 distinct sources, 136 of them primary. It adds no new research thread. Each choice below is [ASSUMPTION], my proposal, built on the verified facts it cites.

**How pages were read.** As stated in files 02 and 03.

## CONTRADICTIONS

1. **You cannot use GitHub's issue types (Bug, Feature, Task), because harness-kit belongs to a personal account.** [VERIFIED | file 02, contradiction 1] Types are therefore labels.
2. **Status cannot live in a label if you want a board.** Project views cannot group by label. [VERIFIED | file 02, contradiction 7] Status is therefore a project field.
3. **Jira's Epic > Story > Sub-task does not map one-to-one.** GitHub has no sub-task; a sub-issue is a full issue. [VERIFIED | github/docs adding-sub-issues] Checklists inside the issue body replace sub-tasks.

## 1. The structure at a glance

| Piece | What it holds | Who changes it |
|---|---|---|
| Labels `type:*` | What kind of item it is (one per issue) | Whoever creates the issue; the issue form sets it |
| A few other labels | Flags: `regression`, `needs-decision`, `deferred` | You, or the agent on your instruction |
| Sub-issues | Epic > (Feature >) Story, Task, Bug | Whoever creates the issue |
| "Blocked by" links | Real order dependencies | You |
| One user project "harness-kit backlog" | Status, Priority, Size; a board and a table | Status: the start script and the built-in workflows. Priority and Size: you |
| Issue forms | One form per type, with the required sections | Created once |
| `Fixes #N` in the released commit | Closes the item | The agent writes it; your `release.sh` push closes the issue |
| `docs/STATE.md` and `docs/DECISIONS.md` in the repository | Where things stand; what was decided and why | The agent, in each increment's commit |

**Why this split.**
- Labels and sub-issues travel with the issue and need only ordinary issue permissions, so the agent can read them with plain `gh issue list`.
- Status and Priority need a project, because only project fields can be board columns and sorted.
- Decisions and state stay in the repository, because a public issue tracker is not a design record and your research already lives in `research/`. [ASSUMPTION]

## 2. Labels

Create these once, with `gh label create NAME --description "…" --color HEX --force`. [VERIFIED command | gh source]

| Label | Meaning | Rule |
|---|---|---|
| `type:epic` | A large outcome; its sub-issues are the work | Never worked on directly; closed by you when its children are done |
| `type:feature` | Optional middle level inside an epic | Only when an epic has more than about eight leaf items in clear groups |
| `type:story` | A change with visible value, one increment | Given, When, Then acceptance criteria |
| `type:task` | Technical work with no visible behaviour, one increment | Checklist acceptance criteria |
| `type:bug` | Behaves differently from what was agreed | Steps, expected, actual; `Caused by:` line when known |
| `regression` | A bug introduced by an earlier change | Needs a `Caused by: #N / <commit>` line |
| `needs-decision` | Waiting for your decision | The start agent refuses these items |
| `deferred` | Kept for later, with a trigger | The body must have a `Trigger:` line; Status stays Backlog |

**Delete or ignore the 10 default labels.** Keep `documentation` if you like; the others (`good first issue`, `help wanted` and so on) are for projects with outside contributors. [ASSUMPTION]

**No priority labels and no status labels.** Priority and Status are project fields, so that there is one place for each.

## 3. The project: fields and views

**Create one user project,** named "harness-kit backlog", and link it to the repository. [VERIFIED steps | file 02]

**Fields:**

| Field | Type | Options | Set by |
|---|---|---|---|
| Status | Single select (built in) | Backlog, Ready, In progress, In review, Done | Backlog: when added. Ready: you. In progress: the start script. In review: you or `review.sh`. Done: the built-in workflow when the issue closes |
| Priority | Single select | P1 (next), P2 (soon), P3 (later) | You only |
| Size | Single select | S (under half a day of your attention), M (one increment), L (must be split before Ready) | You, with the agent's suggestion |
| Parent issue and Sub-issue progress | Built in, hidden by default | — | Automatic |

**Views:**
1. **Board**, grouped by Status. This is your daily view.
2. **Backlog table**, filtered to `-status:Done`, grouped by Parent issue, sorted by Priority. This is your planning view.
3. **Deferred**, filtered to `label:deferred`, showing each item's trigger line. This is your monthly look.

**Built-in workflows** (the project's **⋯** menu, then **Workflows**):
- Keep "item closed sets Done" on.
- Turn on auto-add with `is:issue`.
- Turn on auto-archive with `is:closed updated:<@today-1m`.
- Check whether "Auto-close issue" is on. Turn it off: an issue should close only through `Fixes #N` on release, not because someone dragged a card to Done. [ASSUMPTION; the default is uncertain, see file 02]

**Milestones: none for now.** Your releases are tags, and a milestone per release adds upkeep with no reader. Revisit if you want a "what goes into v1.0" list. [ASSUMPTION]

## 4. Issue forms

Put one YAML file per type in `.github/ISSUE_TEMPLATE/`, plus a `config.yml` with `blank_issues_enabled: false`. Issue forms are "in public preview and subject to change". [VERIFIED | github/docs syntax-for-issue-forms] A form can set the label; it cannot set a project field, and its `type:` key does nothing on a personal account. [VERIFIED | same]

**Required sections by type:**

| Section | Epic | Feature | Story | Task | Bug |
|---|---|---|---|---|---|
| Why (the problem, one or two sentences) | yes | yes | yes | yes | yes |
| Outcome (what is true when done) | yes | yes | | | |
| Decisions behind it (with links) | yes | | | | |
| Acceptance criteria (Given, When, Then) | | | yes | | |
| Acceptance criteria (checklist) | | yes | | yes | |
| Steps to reproduce, expected, actual | | | | | yes |
| Caused by (issue or commit, when known) | | | | | yes |
| How it is checked (test, command or file) | | | yes | yes | yes |
| Source (research file, defect id or decision) | yes | yes | yes | yes | yes |
| Out of scope | yes | | yes | yes | |
| Trigger (only for deferred items) | optional | optional | optional | optional | |

**Example: the Story form** (a sketch, not tested):

```yaml
name: Story
description: A change with visible value, sized for one increment
labels: ["type:story"]
body:
  - type: textarea
    id: why
    attributes: { label: Why, description: The problem this solves, in one or two sentences }
    validations: { required: true }
  - type: textarea
    id: criteria
    attributes:
      label: Acceptance criteria
      description: Given, When, Then; each criterion names the test, command or file that checks it
    validations: { required: true }
  - type: input
    id: source
    attributes: { label: Source, description: Research file, defect id or decision this comes from }
    validations: { required: true }
  - type: textarea
    id: out-of-scope
    attributes: { label: Out of scope }
```

## 5. Naming and linking conventions

**Titles.**
- Stories and tasks start with a verb: "Replay every fault on each branch push".
- Bugs name the wrong behaviour: "Stop gate skips its check after a same-second edit".
- Epics name an outcome: "Faults are found before main moves".

**Branches.**
- Use `inc-<issue number>-<slug>`, for example `inc-42-branch-replay`, created locally by the start script.
- The brief file follows: `.reports/inc-42-branch-replay.brief.md`.
- Whether `ship.sh` and `release.sh` assume any branch-name pattern: not checked. The first increment of Epic 4 must check it. [ASSUMPTION]

**Commits.**
- The last commit of an increment ends with `Fixes #N`.
- A bug fix also carries `Fixes: <12-character commit id> ("<subject>")` when the cause is known (file 03).
- Decisions keep the existing `Decision:` line, which `docs/DECISIONS.md` is built from.

**Defects.** When `record-defect` runs, the new line in `.harness/defects.tsv` names the bug issue, and the bug issue names the defect id.

**Dependencies.** Use "blocked by" only for a real order ("this cannot start until that is released"), not for "related to". Relationships are capped at 50 per type. [VERIFIED | file 02]

## 6. Where the plan lives, so it stops living in chat

| Question | Where the answer lives |
|---|---|
| What are we doing next, and in what order? | The project board (Status Ready, sorted by Priority) |
| Why does this item exist? | The issue's Why and Source lines |
| What exactly will this branch change? | The approved brief in `.reports/` (and, if you decide so, a committed copy: see file 07, Story 1.4) |
| Where do things stand overall? | `docs/STATE.md`, updated in each increment's commit |
| What did we decide, and why? | `docs/DECISIONS.md`, built from commit `Decision:` lines |
| How does the harness work? | A map file (`CLAUDE.md` importing `AGENTS.md`) of about 100 lines, pointing into `research/` and `docs/` |

## Strongest counter-cases

- **Labels plus milestones only, no project.** This is fewer moving parts, with no `project` token scope. It also gives no board and no Priority sort, and you asked for a board.
- **A free organisation, for real issue types and issue fields.** It changes the repository's owner and address, which every installed copy of the plugin pins. Not now.
- **Status as a label.** The agent could then read it without the `project` scope, but you could not see it as board columns. If the `project` scope proves troublesome, fall back to a `ready` label read by the start script, and keep the board for viewing only.

**What would change this proposal.**
- If GitHub opens issue types to personal accounts, use them instead of `type:*` labels.
- If the start script's `gh project item-list` call proves unreliable, move Ready to a label.

**Confidence.** Medium: every piece rests on verified features, but the whole has not been tried.
