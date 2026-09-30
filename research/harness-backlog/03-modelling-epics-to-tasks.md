# 03 — Modelling Epic, Feature, Story, Task and Bug on GitHub Issues (question C)

Written on Wednesday 30 September 2026. Research only.

## Terms used in this file

- **Epic.** A large outcome that takes many pieces of work, for example "Faults are found before main moves".
- **Feature.** A capability inside an epic that a person could notice, made of several stories.
- **Story.** One change with visible value, small enough for one branch and one release.
- **Task.** One piece of technical work with no user-visible behaviour of its own (a configuration change, a documentation change, a clean-up).
- **Bug.** Something that behaves differently from what was agreed.
- **Regression.** A bug introduced by an earlier change.
- **Tracking issue.** An issue whose body lists and links the smaller issues that together deliver something big. Open-source projects use this where Jira uses an epic.
- **Acceptance criteria.** The statements that must be true for an item to count as done.
- **Given, When, Then.** A way of writing one acceptance criterion as a starting situation (Given), an action (When) and an observable result (Then).
- **Definition of Ready.** A checklist an item must pass before work on it may start.
- **Definition of Done.** A checklist every item must pass before it counts as finished.
- **Commit trailer.** A `Key: value` line at the end of a commit message, such as `Fixes: 54a4f0239f2e`.
- **Increment.** One branch, one brief, one release in harness-kit's process.

## How this file is based on evidence

**Sources.** This file draws on 65 sources, of which 59 are counted as primary. 54 were read; 9 are known only from a search-result title, and their content was not read. 2 are secondary.

**How they were chosen.**
- The project sample is 10 large, well-known open-source projects: kubernetes, rust-lang/rust, microsoft/vscode, golang/go, github/roadmap, dotnet/runtime, dotnet/aspire, grafana, home-assistant, and GitHub's own cli/cli and copilot-cli.
- For each I read the triage or contribution document and the issue templates in the repository.
- For methods, I read the Cucumber (Gherkin) documentation, Microsoft's Azure DevOps process documentation and Microsoft's engineering playbook, Mozilla's, Chromium's and the Linux kernel's regression practices, and GitHub's own documentation.
- The sample is a convenience sample of large projects, not a random one, and it contains no solo project. That matters because you work alone.

**How pages were read.**
- **Full reads:** every repository file, through its raw text.
- **Could not be read:** the Scrum Guide, Atlassian's and SAFe's own pages, and Dan North's articles, because their sites refused the connection. Claims about them are labelled [PARTIAL].
- **Not checked:** live label lists and live issues of the sampled projects. What they write in their process documents may lag what they do.

**Labels.**
- [VERIFIED] means a primary source says it.
- [PARTIAL] means secondary, title-only or partly supported.
- [ASSUMPTION] means my reasoning.
- NOT FOUND means searched and nothing found.

## CONTRADICTIONS

1. **"Epic > Feature > Story" is not Jira's default, and not GitHub's.**
   - It is the hierarchy of Azure DevOps's "Agile" process. [VERIFIED | MicrosoftDocs/azure-devops-docs choose-process.md, 16 June 2026, full read]
   - Azure's lightest "Basic" process is only Epic > Issue > Task. [VERIFIED | same]
   - Jira's default is Epic > Story, Task and Bug > Sub-task, with no Feature type. [PARTIAL: Atlassian's page was not readable]
   - GitHub's default issue types are Task, Bug and Feature, with no Epic or Story, and only for organisations (file 02). [VERIFIED | github/docs]
2. **None of the 10 sampled projects documents an epic level or more than one level above the working issue.**
   - They all use one big-item issue (called a tracking issue, umbrella issue, enhancement issue, plan item or proposal) plus one type label per issue. [VERIFIED | each project's triage document and templates]
   - Caution: most of these practices were written before sub-issues existed (sub-issues became available to everyone in 2025). Their absence does not prove sub-issues are a bad idea. [ASSUMPTION]
3. **"Definition of Ready" is not in the Scrum Guide.** From prior knowledge, the 2020 guide defines the Definition of Done and says only that items are "deemed ready for selection". [PARTIAL: the guide could not be read today]

## 1. How well-run projects model big work

| Project | Types | Parent and child | Priority | Bugs and regressions |
|---|---|---|---|---|
| Kubernetes | `kind/*` labels (bug, feature, cleanup, regression, flake…); a bot adds `needs-kind` if none | One tracking issue per enhancement, with a stage-by-stage checklist, plus a design document (KEP) in a repository | `priority/critical-urgent` … `priority/backlog`; `triage/accepted` means "ready to be actively worked on" | `kind/regression` [VERIFIED \| kubernetes/test-infra labels.md; kubernetes/enhancements templates] |
| Rust | `C-*` category labels, `T-*` team, `A-*` area | "Tracking Issue for XXX", labelled `C-tracking-issue`, a hub with a Steps checklist | `P-critical` … `P-low` after `I-prioritize` | `regression-from-stable-to-*`, `E-needs-bisection` [VERIFIED \| rust-forge; rust templates] |
| VS Code | "Each issue must have a type label" | Monthly iteration-plan issue, and a `plan-item` issue per feature | Milestones (a month, Backlog, On Deck); `important` label | `verified` / `verification-needed` after a fix [VERIFIED \| vscode wiki] |
| Go | State labels `NeedsInvestigation`, `NeedsDecision`, `NeedsFix` | Proposal issue plus optional design document | Milestones; `release-blocker` | Title prefix names the package [VERIFIED \| golang/wiki; golang/proposal] |
| GitHub roadmap | Labels for phase and area | Items sit in a project column per quarter | Quarter column | Closed with a changelog link [VERIFIED \| github/roadmap README] |
| .NET runtime and aspire | Exactly one type label (runtime); aspire's forms set `type: Bug` and `type: Feature` (an organisation) | One issue may track a whole feature | Milestones | — [VERIFIED \| issue-guide.md; aspire templates] |
| Grafana | Exactly one `type/*` label | — | `priority/*` labels | Critical bugs go to the next patch milestone [VERIFIED \| ISSUE_TRIAGE.md] |
| Home Assistant | Tracker is for bugs only | — | — | Bug form asks for the last working version [VERIFIED \| bug_report.yml] |

**The common pattern.** A big item is one issue with a checklist or links to ordinary issues. The type is one mandatory label. Priority is a small fixed label set or the milestone. Regressions have their own label and a "last working version" or bisection request. [VERIFIED as a summary of the sample]

## 2. How many levels for one person

**Recommendation [ASSUMPTION]: two levels always, a third only when it earns its place.**

1. **Epic:** an issue labelled `type:epic`, with sub-issues. One per outcome in the backlog.
2. **Leaf items:** Story, Task or Bug, each sized for one increment (one branch, one brief, one release). This is the only level the agent works on.
3. **Feature (optional):** use it only when an epic has more than about eight leaf items that fall into clear groups. In the harness-kit draft (file 07), three epics need it.

**Strongest case for fewer levels.**
- Every level must be created, linked, kept up to date and closed, and you pay all of that cost alone.
- None of the ten large projects uses more than one level above the working issue.
- The agent only ever consumes the leaf level.

**Strongest case for more levels.**
- Your Jira habits lower friction.
- GitHub rolls up sub-issue progress automatically, so an extra level is cheaper than it was with hand-kept checklists.
- A Feature level gives natural release-note headings.

**What would change the recommendation.** If after a month you find yourself creating Features you never look at, remove the level. If an epic's sub-issue list becomes too long to scan, add it.

**Confidence.** Medium.

## 3. Acceptance criteria

**Given, When, Then.**
- It grew out of behaviour-driven development, which Dan North described in 2006 in "Introducing BDD". [PARTIAL | cucumber/docs bdd/history.md, full read; the original article was not read]
- The Gherkin reference [VERIFIED | cucumber/docs gherkin/reference.md, full read]:
  - Given puts "the system in a known state";
  - When describes "an event, or an action";
  - Then describes "an expected outcome", which "should be on an observable output";
  - "3-5 steps per example" is recommended.
- Cucumber also advises describing behaviour, not implementation, and asking: "Will this wording need to change if the implementation does?" [VERIFIED | cucumber/docs better-gherkin.md, full read]

**An example for harness-kit** [ASSUMPTION: my illustration]:

```
Rule: A change is replayed against every fault before main moves
  Example: A surviving fault stops the release
    Given a branch whose change weakens a test so that one planted fault survives
    When the person runs release.sh with a new tag
    Then release.sh stops before fast-forwarding main
    And main on GitHub still points at the previous release
    And the stop message names the surviving fault and the CI run's address
```

**When a checklist is better.** Much harness work has no behaviour to illustrate: moving Node from 22 to 24, pinning actions, writing a documentation file. For those, a list of statements that can each be checked is clearer. Gherkin itself keeps "a list of business rules (general acceptance criteria)" in the feature description, and adds examples only where a rule has an interesting case. [VERIFIED | Gherkin reference] GitHub's advice for agent work asks for "complete acceptance criteria" without prescribing a format. [VERIFIED | github/docs copilot get-the-best-results.md, full read]

**Recommendation [ASSUMPTION].**
- Use Given, When, Then for Stories and Bugs, because they describe behaviour.
- Use a checklist for Tasks.
- Every criterion must name how it is checked: which test, which command, or which file.

## 4. Definition of Ready and Definition of Done

**What the sources say.**
- Microsoft's playbook defines a Definition of Ready as "the agreement … around how complete a user story should be in order to be selected", suggests putting it in the issue template, and warns: "Don't include items or details that only apply to one or two user stories". [VERIFIED | microsoft/code-with-engineering-playbook, full read]
- Critiques of a Definition of Ready used as a gate exist, notably by Mike Cohn, who warns it can become a stage gate. [PARTIAL: titles only]
- For agent work, GitHub says an ideal task has "a clear description", "complete acceptance criteria" and "directions about which files need to be changed", and to "think of the issue you assign to Copilot as a prompt". [VERIFIED | github/docs get-the-best-results.md, full read]
- A named "Definition of Done for AI agents" from any standards body or well-known project: NOT FOUND.

**Proposed Definition of Ready for harness-kit** [ASSUMPTION]. An item may be marked Ready only when all of these hold:
1. It has a "Why" line saying what problem it solves.
2. It has acceptance criteria, each naming how it is checked.
3. It is sized S or M (one increment). An L item must be split first.
4. Its "Source" line names the research file or defect it comes from.
5. Nothing it depends on is open (GitHub's "blocked by" list is empty).
6. Any number it needs (a limit, a budget) is listed as a question for you, not chosen by the agent. This mirrors the brief's "New thresholds" section.

This is five minutes of your time per item, and it is what the start agent (file 04) will refuse to work without.

**Proposed Definition of Done for harness-kit** [ASSUMPTION]. An item is Done only when all of these hold:
1. Its brief was approved by you (the checksum matches).
2. Every acceptance criterion is met, with the evidence quoted in the Summary.
3. `tests/validate.sh` passes (the Stop gate).
4. Every fault tied to the changed files is KILLED, and every new fault has been planted once.
5. The reviewer's verdict is PASS, or you recorded why you overruled it.
6. CI is green on the exact commit that `main` moved to, including the full fault replay.
7. The issue is closed by `Fixes #N` in the released commit, and the release tag exists.
8. `docs/STATE.md` says what changed, and `docs/DECISIONS.md` has any decision the item made.

**Counter-case.** A Definition of Ready used as a hard gate can stall a solo developer who could have clarified the item in thirty seconds. Keep it as the start agent's check, with your override written in the issue.

## 5. Linking a bug to what caused it

**What others do.** [VERIFIED for each]
- Mozilla gives a regression the `regression` keyword and a "Regressed By" field pointing at the bug whose change caused it. They stopped reusing blocks and blocked-by for this because it "made it difficult to understand what was a dependency and what was a regression". [mozilla gecko-dev docs, full read]
- The Linux kernel puts `Fixes: <12-character commit id> ("subject")` in the fixing commit's message. [torvalds/linux submitting-patches.rst, full read]
- `git bisect run <command>` finds the commit that introduced a bug automatically. [git/git documentation, full read]
- GitHub has no native "caused by" link. Its only relationships are sub-issues, blocked-by and blocking, and duplicates. [VERIFIED | github/docs]
- A "Regressed-by:" or "Caused-by:" commit convention: NOT FOUND in any project read.

**Lightest reliable way for harness-kit** [ASSUMPTION]:
1. On the bug issue, add the label `regression` and a line `Caused by: #<story> / <12-character commit id>` once known.
2. In the fixing commit, add `Fixes #<bug>` (which closes the issue on release) and a kernel-style trailer `Fixes: <commit id> ("<subject>")`.
3. When `record-defect` runs, it already records the introducing commit in `.harness/defects.tsv`; put the issue number in the same line.

**Counter-case.** At your volume, `git blame` when needed may be enough, and the extra lines may rarely be read. They cost seconds, and a weekly health check can find bugs without them.

## 6. Titles

**What others do.** [VERIFIED]
- Go prefixes titles with the package path.
- Rust titles tracking issues "Tracking Issue for …".
- The Linux kernel asks for the imperative mood ("make xyzzy do frotz").

**Recommendation [ASSUMPTION].**
- Stories and tasks get an imperative title that starts with a verb: "Replay every fault on each branch push".
- Bugs describe the wrong behaviour: "Stop gate skips its check after a same-second edit".
- Epics describe an outcome: "Faults are found before main moves".
- Do not use "As a developer, I want …": you are the only user, so the role adds words and no information. Keep a required "Why" line instead, because the agent needs the reason.

## Negative results

- An "epic" label or template in kubernetes, grafana, dotnet/runtime or dotnet/aspire: NOT FOUND.
- A documented "Caused-by:" commit convention: NOT FOUND.
- A published "Definition of Done for AI agents": NOT FOUND.
- Live use of sub-issues by the sampled projects: not checked (their pages were not readable here). A personal-account example, datasette, is in file 02.

## Strongest counter-cases

- **Three levels everywhere** is easier to explain and matches your Jira habit; the price is upkeep on items nobody reads.
- **Given, When, Then everywhere** gives the agent one format to turn into tests; the price is awkward criteria for configuration and documentation tasks.
- **No Definition of Ready** keeps you fast; the price is that the agent will start vague items and fill the gaps with guesses.

**Confidence.** Medium overall. High that no single standard exists and that big projects use fewer levels than Jira's default.
