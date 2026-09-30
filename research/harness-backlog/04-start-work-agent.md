# 04 — An agent that starts work correctly (question D)

Written on Wednesday 30 September 2026. Research and design only: nothing was built.

## Terms used in this file

- **Start agent.** The capability designed here. When you ask Claude Code to start, it picks the right backlog item and walks it through harness-kit's process.
- **Skill.** A folder with a `SKILL.md` file that Claude Code loads as instructions. You start a skill by typing its name after a slash, for example `/harness-kit:brief`. Custom slash commands are now skills.
- **Dynamic context injection.** A skill line written as `` !`command` ``. Claude Code runs the command before the skill reaches the model and pastes in its output. If the command fails, the whole skill is abandoned.
- **Subagent.** A separate Claude instance with its own instructions and tool list, started by the main session.
- **Hook.** A script Claude Code runs at a fixed moment. **SessionStart** runs when a session begins; **UserPromptSubmit** runs when you send a message; **PreToolUse** runs before each tool call and can refuse it.
- **gh.** GitHub's command-line tool. **GitHub MCP server.** GitHub's official set of tools for an AI agent.
- **Spec-driven development.** A method in which the agent writes a specification and a plan, a person reviews them, and only then does the agent write code.
- **Ready.** The project Status that means you have decided an item may be started (file 06).
- **Status comment.** One comment on the issue that the harness edits as the work moves forward.
- **Increment, brief, approval.** harness-kit's existing process:
  - an **increment** is one branch;
  - a **brief** is the plan the agent writes into `.reports/<branch>.brief.md`;
  - an **approval** is your run of `approve-brief.sh`, which records the brief's checksum.

## How this file is based on evidence

**Sources.** This file draws on 97 sources, of which 94 are primary: vendor documentation, each tool's README, licence, source files and releases page, and harness-kit's own files. The 3 secondary sources are one article on Martin Fowler's site and two of your earlier research files.

**How they were chosen.** The sample is the list of tools named in the question. I added three sources that answer part of it directly:
- GitHub's documentation for its Copilot coding agent;
- the `gh` source code for `gh issue develop`;
- GitHub's page on closing keywords.

In Anthropic's official plugin marketplace file (314 entries), every entry's name and description was searched for issue, GitHub, backlog, ticket, task, plan, spec, commit and PR.

**How pages were read.**
- **Full reads:** repository files and licences.
- **Extracts:** documentation pages. For Claude Code's pages the whole text came back, so the quotations are close to exact.
- **NOT FOUND:** the last-commit date of every repository, because commit pages and GitHub's programming interface were blocked for the research tool. Release dates are given instead, and their year is sometimes not shown.

**Labels.**
- [VERIFIED] means a primary source says it.
- [PARTIAL] means secondary or partly supported.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

## CONTRADICTIONS

1. **No existing tool picks an item from a backlog you wrote by hand and runs it through a plan you must approve.**
   - CCPM reads GitHub Issues, but only issues it created from its own local files. For any other issue it says "No local task for issue #<N>. Run a sync first." [VERIFIED | automazeio/ccpm skill/ccpm/references/execute.md, full read]
   - Spec Kit writes issues from its task list but never reads a backlog. [VERIFIED | github/spec-kit templates/commands/taskstoissues.md, full read]
   - harness-kit's own approval (`approve-brief.sh` plus the brief-guard hook) is stricter than every spec tool read, because those tools ask for approval only in their instructions. [ASSUMPTION drawn from the files]
2. **`gh issue develop` creates the branch on GitHub, not on your machine.** Its source calls a mutation named `createLinkedBranch` and only then fetches. [VERIFIED | cli/cli pkg/cmd/issue/develop/develop.go, full read] That is a remote write your git-guard hook does not see, because it is not `git push`.
3. **CCPM and claude-code-action both push by design.**
   - CCPM's merge step runs `git push origin main`. [VERIFIED | ccpm references/sync.md]
   - The Claude Code GitHub Action "Always creates a new branch" when started from an issue, and commits to it. [VERIFIED | anthropics/claude-code-action docs/capabilities-and-limitations.md, full read]
   - Both collide with harness-kit's rule that only you push.
4. **A skill's `allowed-tools` field does not restrict tools.** "It does not restrict which tools are available: every tool remains callable." It only pre-approves them for one turn. The restricting field is `disallowed-tools`, and "The restriction clears when you send your next message." [VERIFIED | code.claude.com/docs/en/skills, 2026-09-30]
5. **`gh issue comment --edit-last` edits your own last comment.** It is documented as "Edit the last comment of the current user". When Claude runs `gh` on your machine, the current user is you. [VERIFIED for the wording | cli.github.com/manual/gh_issue_comment; the consequence is ASSUMPTION]
6. **Spec Kit's commands have been renamed** (`/speckit-specify` and so on), and a `converge` step follows `implement`. [VERIFIED | github/spec-kit README, full read]

## 1. The options compared

| Option | What it does | Set-up | Licence | Latest release (last commit NOT FOUND) | Main catch |
|---|---|---|---|---|---|
| Claude Code skills, hooks, subagents | Built-in extension points | Files in the plugin | Part of Claude Code | — | Skills and subagent prompts are advice; only hooks and permission rules enforce [VERIFIED \| code.claude.com features-overview] |
| anthropics/claude-code-action | Runs Claude Code on issue and pull-request events in GitHub Actions | GitHub App, a secret and a workflow file; admin access | MIT | v1.0.213, "01 Sep" (year not shown) | Pushes a branch; costs Actions minutes plus tokens; `approve-brief.sh` needs a terminal that CI lacks |
| github/github-mcp-server | Issues, sub-issues, projects and labels as agent tools | Remote (OAuth or token) or local | MIT | v1.11.0, "25 Aug" | Its tool calls are not seen by hooks that match shell and file tools; read-only mode exists (`--read-only`, or `/readonly` on the remote address) [VERIFIED \| README] |
| gh | Command line for issues and projects | `gh auth login`; `gh auth refresh -s project` | MIT | v2.100.0, 3 September 2026 | `gh issue develop` writes to GitHub |
| github/spec-kit | Constitution, specify, plan, tasks, implement, converge | `uv tool install specify-cli` | MIT | v1.0.3, "01 Sep" | Does not read a backlog; approval by instruction; many Markdown files to review |
| AWS Kiro | Requirements (EARS format), design and tasks documents | Separate program | NOT FOUND | NOT FOUND | Not a Claude Code plugin |
| Fission-AI/OpenSpec | Propose, apply and archive changes | npm | MIT | v1.11.0, "26 Aug" | "no rigid phase gates"; no issue reading |
| BMAD Method | Multi-role agile method as skills | Plugin marketplace | MIT | v6.12.0, "04 Sep" | Large; no issue reading found |
| claude-task-master | Task list from a requirements document, with a `next` tool | npm | MIT with Commons Clause | 0.43.1, "31 Mar" | The tool chooses the next task; tasks live in local files |
| CCPM | Requirements to epics to GitHub issues, with progress comments | Copy the skill folder | MIT | No releases | Only its own issues; pushes `main`; parallel agents |
| cc-sdd | Kiro-style specifications as skills | npx | MIT | v3.0.2, "13 Apr" | Approval is a JSON flag the agent can write |
| feature-dev (official plugin) | Seven-phase feature workflow | Plugin install | Apache-2.0 | — | Approval is the sentence "DO NOT START WITHOUT USER APPROVAL"; no issues |

**Which ones read GitHub Issues as the backlog?** Only CCPM, and only for issues it created itself. [VERIFIED as cited] The GitHub-side agents (claude-code-action, Copilot) are started by an event on one issue; they do not choose from a backlog.

**How the careful ones keep the agent in bounds.** [VERIFIED for each | the tools' own documentation]
- Tools that pick "next" do it in code, not by the model's judgement: CCPM's `next.sh`, Task Master's `next_task`.
- Event-based tools avoid choosing altogether: a person labels, assigns or mentions.
- Anthropic's own triage workflow may only change labels, through a wrapper script that allows four `gh` subcommands, with a cap on the number of calls.
- GitHub's Copilot agent can push only to its own branch, and the requester cannot approve its pull request.
- The Claude Code GitHub Action updates one comment in place, with checkboxes.

## 2. The simplest reliable design for harness-kit

Everything in this section is [ASSUMPTION]: it is my design, built from the verified pieces above.

**The one idea.** The model never decides which item, whether the brief is approved, or when anything leaves your machine.
- A script decides which item.
- You decide the rest.
- Hooks refuse everything else.
- The model writes only the brief, the code and the text of the status comment.

### What you type

- `/harness-kit:start` starts the next Ready item.
- `/harness-kit:start 42` starts issue 42, if it is Ready.
- `/harness-kit:start` typed again at any later point does not start anything new. It works out where the current branch is and tells you the single next step.

A plain "start" typed without the slash can be caught by a UserPromptSubmit hook, which answers "type /harness-kit:start". I recommend the explicit command only. A hook that guesses from free text is exactly the kind of fragile rule that produced harness-kit's own defects.

### What happens, step by step

| Step | Who | What |
|---|---|---|
| 1 | You | Type `/harness-kit:start [N]`. The skill has `disable-model-invocation: true`, so only you can start it. [VERIFIED feature \| code.claude.com/docs/en/skills] |
| 2 | A script, not Claude | The skill's first line injects `` !`node …/scripts/start.mjs $ARGUMENTS` ``. It runs these checks, and any failure aborts the skill, so Claude never sees it and cannot improvise: `gh auth status`; the working tree is clean; you are on `main` and it matches `origin/main`; the item's Status is Ready; its Definition of Ready is met (a Why line, acceptance criteria, size S or M, no open "blocked by" issues); no branch exists for it yet. With no number, it takes the Ready item with the highest Priority, then the lowest issue number. It prints the issue's title, body and comments. |
| 3 | The same script | Creates the branch locally with `git switch -c inc-<N>-<slug>`, never with `gh issue develop`. It writes the issue number to `.reports/<branch>.issue` and sets the project Status to "In progress" (one `gh project item-edit` call). |
| 4 | Claude | Writes the brief from the issue, using the existing brief procedure. That procedure moves into a shared file that both skills load, because the brief skill cannot be started by another skill. Every open decision still stops Claude and goes to you. |
| 5 | A script called by Claude | `record.mjs 42 --stage brief-written` edits one status comment. It finds the comment by a hidden marker line (`<!-- harness-kit:status -->`), never with `--edit-last`, and creates the comment if it is missing. The text says the branch, the brief path, and "waiting for approval". |
| 6 | Claude | Stops, and prints the approval command. |
| 7 | You | Read the brief's front page (file 07, Epic 5) and run `approve-brief.sh`. |
| 8 | You, then Claude | Type `/harness-kit:start` again, or say "go". The script sees that the approval matches and says "build now". Claude builds; the Stop hook runs the check; the status comment is updated to "building", then "check passing". The last commit message ends with `Fixes #42`. |
| 9 | You | Run `review.sh`, then `release.sh`, as today. The push of `main` closes issue 42 through `Fixes #42` (file 02, contradiction 4). The project's built-in workflow sets Status to Done. `release.sh` (your script) adds "released in vX.Y.Z" to the status comment. |

### What stays with you

- Marking items Ready, and setting Priority.
- Approving the brief.
- Answering open decisions and new numbers (limits, budgets).
- Running `review.sh`, `release.sh` and every push.
- Closing, reopening or rewriting issues by hand.
- Deciding that an epic is finished.

### What the agent must never do on its own

- Choose an item that is not the script's pick, or start without your command.
- Create a remote branch, push, or open or merge a pull request.
- Approve a brief or write an approval file.
- Change Priority, Status (except through the start script), labels, milestones or issue bodies.
- Close or reopen any issue.
- Comment on any issue other than the current one.
- Run your scripts (`approve-brief.sh`, `release.sh`, `ship.sh`, `land.sh`, `upgrade.sh`).

### What is enforced by code, and what only by instructions

| Rule | How it is held |
|---|---|
| Only you start the ritual | `disable-model-invocation: true` (a Claude Code feature) |
| The item is chosen by a rule | The injected script; if it fails, the skill aborts (documented behaviour) |
| No push, no remote branch, no pull request | The existing git-guard hook for `git push`, plus a new "gh-guard" PreToolUse hook. It allows only `gh issue view`, `gh issue list`, `gh project item-list`, `gh auth status` and the harness's own `record.mjs`, and refuses every other `gh` subcommand, including `gh issue develop`, `gh issue close`, `gh issue edit`, `gh pr` and `gh api` |
| No GitHub writes through the MCP server | Do not install it for this. If it is installed, add a PreToolUse hook on `mcp__github__.*` that refuses write tools, and use the read-only address |
| No self-approval | The existing brief-guard hook, and `approve-brief.sh`'s check that a terminal is attached |
| Done means the check passes | The existing Stop hook |
| Brief quality, comment wording, stopping after the brief | Instructions only. The reviewer later judges the diff against the approved brief |

**Known holes.**
- Hooks can be dodged by unusual command forms, and a hook that crashes or times out lets the call through. [VERIFIED as recorded in research/initial-harness/02-claude-features.md]
- The real backstop is on GitHub's side: the token `gh` uses. How to give Claude's sessions a narrower token than your own: NOT FOUND.

### Recording what happened on the issue

- **One status comment**, edited in place and found by its marker. It holds the current stage, the branch, the brief's path, the last check result and, at the end, the release tag.
- **The project Status.** It moves Ready, then In progress (set by the start script), then In review (set by `review.sh` or by you), then Done (set by the built-in workflow when the issue closes).
- **Closing** is done by `Fixes #N` in the released commit.
- Two limits apply. GitHub keeps 100 edits of a comment. [PARTIAL | changelog, extract] Agent comments appear as you, because they use your login, so the comment should say "written by harness-kit" in its first line. [ASSUMPTION]

## 3. Counter-cases

1. **Build a "Next step" line instead of a start agent.** The problem you described is remembering the steps. The session start-up picture already shows the brief state, the last check and the last review. One computed line ("Next: run approve-brief.sh") solves most of it, with no new writes to GitHub and no new hook. **This is the strongest counter-case.** My answer is to build that line first as the start agent's step 1 (file 07 orders it so), because the start agent's resume behaviour needs exactly that logic anyway.
2. **Use CCPM.** It is GitHub-Issues-native and posts structured progress comments. Against it: it works only on issues it created, it pushes `main`, it runs parallel agents in one worktree, and it has no releases to pin.
3. **Use Spec Kit.** It is the most widely used and is maintained by GitHub. Against it: it does not read a backlog, its approval is a prompt, and it would duplicate the brief rather than replace it.
4. **Move the work to GitHub with claude-code-action.** Against it: it pushes branches, it is built around pull requests, it costs Actions minutes plus tokens, and your approval needs a terminal.
5. **Use Claude Code's plan mode as the approval.** Against it: the approval leaves no checksum that a script or the reviewer can check.

**What would change the recommendation.**
- If Claude Code gains a way to limit `gh` to a narrower token per session, the gh-guard hook becomes a second layer instead of the main one.
- If Spec Kit or another tool starts reading an existing issue backlog and enforcing approval in code, compare it again before building.

**Confidence.** Medium in the design; high that no existing tool does this job as-is.

**Who should build it.** Claude Code inside the harness-kit folder, because it means editing and testing the plugin's skills, hooks and scripts. [ASSUMPTION]
