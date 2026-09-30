# 08 — Beginner guide: GitHub Issues and Projects for harness-kit

Written on Wednesday 30 September 2026. A step-by-step guide for someone who knows Jira but has never used GitHub Issues or Projects. Nothing here has been done yet.

## Terms used in this file

- **Issue, label, sub-issue, project, field, view, built-in workflow, issue form.** As defined in file 02.
- **Screen.** A page on github.com. The address is given for each; addresses marked [ASSUMPTION] follow GitHub's usual pattern but were not confirmed in GitHub's documentation.
- **You** means you, working in the browser. **Claude Code** means the coding tool, working in the harness-kit folder on your Mac.
- **Jira equivalent.** The nearest thing in Jira, to help you map what you know.

## How this file is based on evidence

**Sources.** This file draws on the 92 sources of question B, of which 77 are primary. The screen names come from the step text in GitHub's own documentation, read in full from the `github/docs` repository. [VERIFIED unless marked] I did not click through the screens myself, because this research changed nothing on GitHub.

**Labels.**
- [VERIFIED] means a primary source says it.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

## CONTRADICTIONS (read before you start)

1. **There is no "Issue Type" drop-down for you.** It exists only for organisations. Types are labels here (file 02).
2. **An issue has no Status of its own.** Status lives in the project. Open and closed is all an issue has.
3. **There are no sub-tasks.** A sub-issue is a full issue. Use a checklist in the issue body for small steps.
4. **Moving a card to Done does not release anything.** In this setup an issue closes when the released commit says `Fixes #N`.

## Part 1 — The screens and what each one is for

| Screen | Address | What it is for | Jira equivalent |
|---|---|---|---|
| Repository Issues tab | `github.com/AayushSanjar/harness-kit/issues` [ASSUMPTION] | The list of all issues; filter by label, open or closed | Issue navigator |
| New issue chooser | `…/issues/new/choose` [ASSUMPTION] | Pick a form: Epic, Feature, Story, Task, Bug | Create issue, choosing a type |
| One issue | `…/issues/<number>` | Title, body, comments; right sidebar: Assignees, Labels, Projects, Milestone, **Relationships** (blocked by), **Development** (linked branches); sub-issues list under the body | Issue view |
| Labels | `…/labels` [ASSUMPTION] | Create and edit labels ("Above the list of issues … click Labels") [VERIFIED wording] | Labels and issue types |
| Your projects | `github.com/AayushSanjar?tab=projects` [ASSUMPTION] | Your personal projects list | Boards list |
| The project | `github.com/users/AayushSanjar/projects/<number>` [VERIFIED pattern] | Board and table views over your issues | Board and backlog |
| Project settings | project **⋯** menu, then **Settings** [VERIFIED] | Name, description, custom fields, visibility | Board settings |
| Project workflows | project **⋯** menu, then **Workflows** [VERIFIED] | Built-in automations | Automation rules |
| Repository settings | `…/settings`, then **Features**, then **Issues** [VERIFIED path] | Turn issues on; set up templates | Project settings |

## Part 2 — Set up once (about an hour of your time)

Each step says who does it. Do them in order; each step's check tells you it worked.

**Step 1 — You: make sure issues are on.**
- **Do:** open the repository's **Settings**; under **Features**, check that **Issues** is ticked. [VERIFIED path]
- **Check:** an **Issues** tab appears under the repository name.

**Step 2 — You: give `gh` permission to read and change projects.**
- **Do:** in your Mac's terminal, run `gh auth refresh -s project`. It opens a browser to approve. [VERIFIED command | gh source]
- **Why:** the start agent and scripts will read the project's Status field. A fine-grained token cannot reach a personal project, so this classic scope is the only way. [VERIFIED | file 02]
- **Check:** `gh auth status` lists `project` among the scopes.

**Step 3 — Claude Code: create the labels.**
- **Do:** ask Claude Code, in the harness-kit folder, to write a small script that runs `gh label create … --force` for each label in file 06, and show it to you. You run the script. (Under harness-kit's rules, Claude Code does not change GitHub itself.)
- **Check:** the Labels screen shows `type:epic`, `type:feature`, `type:story`, `type:task`, `type:bug`, `regression`, `needs-decision` and `deferred`.

**Step 4 — You: create the project.**
- **Do:** profile picture, **Your profile**, **Projects**, **New project**. Choose **Board**, name it "harness-kit backlog", and click **Create project**. [VERIFIED steps]
- **Check:** the project opens with columns such as Todo, In Progress and Done. The exact default names: NOT FOUND; you will rename them in step 6.

**Step 5 — You: link the project to the repository.**
- **Do:** in the repository, open the **Projects** tab, then **Link a project**, and choose "harness-kit backlog". [VERIFIED]
- **Check:** the project appears in the repository's Projects tab.

**Step 6 — You: set the Status options.**
- **Do:** project **⋯**, **Settings**, then the **Status** field. Make the options Backlog, Ready, In progress, In review, Done, in that order.
- **Check:** the board shows those five columns.

**Step 7 — You: add Priority and Size.**
- **Do:** in **Settings**, choose **New field**, type **Single select**:
  - Priority, with options P1, P2 and P3;
  - Size, with options S, M and L.
- **Check:** both appear as fields on each card.

**Step 8 — You: make the three views.**
- **Board:** the view that already exists, grouped by Status.
- **Backlog:**
  - **Do:** click **New view** and choose **Table**. Group by **Parent issue** (show the hidden field first) and sort by Priority. Filter with `-status:Done`.
  - **Check:** the view lists items under their parent, highest priority first.
- **Deferred:**
  - **Do:** click **New view** and choose **Table**, filtered with `label:deferred`.
  - **Check:** only items labelled `deferred` appear.

**Step 9 — You: set the automations.**
- **Do:** project **⋯**, **Workflows**, then:
  - **Item closed:** check that it is on and sets Done.
  - **Auto-add to project:** turn it on with the filter `is:issue`. This is your one free slot. [VERIFIED]
  - **Auto-archive items:** turn it on with `is:closed updated:<@today-1m`.
  - **Auto-close issue:** turn it off if it is on, so that dragging a card to Done never closes an issue by itself.
- **Check:** each workflow shows the state you set.

**Step 10 — Claude Code: add the issue forms.**
- **Do:** ask Claude Code to add the five forms and `config.yml` from file 06 in an increment. It goes through brief, your approval, the check and your release, like any change.
- **Check:** after the release, **New issue** shows the five forms.

**Step 11 — You: two small tests.**
- **Sub-issues:**
  - **Do:** make a throwaway issue A. From it, choose **Create sub-issue** to make issue B.
  - **Check:** A shows "0 of 1" progress.
  - Then close both with the reason "not planned".
- **Closing through a pushed commit:** this is already shown to work on another personal account (file 02). Your first real release with `Fixes #N` will confirm it for harness-kit.

## Part 3 — Everyday use

**Adding an item.**
1. Click **New issue** and pick the form.
2. Fill in Why, the acceptance criteria and Source.
3. If it belongs under an epic, open the epic and choose **Add existing issue** in its sub-issues list. The auto-add workflow puts it on the board in Backlog.

**Making an item Ready (your decision).**
1. Check it against the Definition of Ready in file 03.
2. Set Size (S or M; split an L first) and Priority.
3. Drag it to Ready.

**Starting work.** Once Epic 4 exists, type `/harness-kit:start` in Claude Code in the harness-kit folder. Until then, create the branch yourself and ask Claude Code to write the brief from the issue.

**While work runs.** The status comment on the issue shows the stage. The card moves to In progress by itself.

**Finishing.** You run the review and `release.sh` as today. The released commit's `Fixes #N` closes the issue, and the card moves to Done by itself.

**Once a week.** Read the backlog health report (Epic 4, item 4.8) and decide each fix.

## Part 4 — Blockers you are likely to meet, answered up front

| What you see | What it means | What to do |
|---|---|---|
| No "Type" field in the issue sidebar | Issue types are organisation-only | Use the `type:*` labels; this is expected |
| `gh project …` says the token lacks a scope | Step 2 was not done | Run `gh auth refresh -s project` |
| An old issue is not on the board | Auto-add ignores issues that existed before it was switched on [VERIFIED] | In the project, click **+ Add item**, type `#` and pick the issue |
| You cannot group the board by a label | Views cannot group by label [VERIFIED] | Group by Status or Parent issue; filter by label instead |
| A form's label did not appear on the new issue | A form only applies labels that already exist [VERIFIED] | Run the label script (step 3) again |
| An issue closed when you did not expect it | A commit on `main` contained `Fixes #N` for it | Reopen it, and check the commit message |
| GitHub says you are creating content too quickly | 80 writes per minute or 500 per hour exceeded [VERIFIED] | Wait an hour; import in smaller batches, one write per second |

## Negative results

- The exact default column names of a new board: NOT FOUND.
- Official addresses for the labels, milestones, workflows and settings screens: NOT FOUND in the documentation. The patterns above are [ASSUMPTION].

## Strongest counter-case

You could skip the project and use only labels and the Issues tab, which is less setup. You would lose the board and the priority sort, and the start agent would have to read a `ready` label instead of the Status field (file 06, counter-cases).

**Confidence.** Medium to high: the steps follow GitHub's documentation, but screen names change and I did not click through them.
