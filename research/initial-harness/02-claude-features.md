# 02 — Claude Code features for a harness: what each guarantees and what it does not (status on 26 September 2026)

**Sources and how they were selected.** This file cites 54 sources. The main sources are Anthropic's Claude Code documentation pages (code.claude.com/docs), one page for each feature, plus the plugin pages and the changelog. Known bugs came from the anthropics/claude-code GitHub issue tracker. Issues were found by web search using the feature name plus "bug", and by following cross-links from the documentation. Two research sub-agents catalogued the features. I then re-read the raw text of these documentation pages myself on 26 September 2026: hooks, hooks guide, permissions, sandboxing, memory, sub-agents, agent teams, `/goal`, best practices, CLI reference, and the plugin pages. I also re-opened the design-critical issues myself (#16299, #23478, #25000, #58637, #78234, #80697, #80802, #92271, #95650 and #96121). Issues marked [PARTIAL] were read only by a sub-agent, through a tool that summarises pages, so their open or closed state may be stale. URLs omit "https://". Claude Code versions are written like "v2.1.232"; the newest version seen in the changelog was 2.1.283 (25 September 2026).

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source, a summary-only reading, or partial support. [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**The one idea to keep in mind.** Claude Code features fall into two groups.
- **Advisory features** put text into the model's context, and the model decides whether to follow it: CLAUDE.md, rules files, skills, output styles and subagent instructions. [ASSUMPTION: my grouping, supported by the page quoted below]
- **Enforcing features** run outside the model and can refuse an action whatever the model decides: hooks, permission rules, the sandbox and budget flags. [ASSUMPTION: my grouping, supported by the page quoted below]

Anthropic's documentation draws the same line: memory files are "context, not enforced configuration". [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26] Even the enforcing features have gaps, listed below. That is why a check in CI, outside the agent's reach, stays necessary.

---

## 1. CLAUDE.md, AGENTS.md, imports and auto memory

**What it is.** CLAUDE.md is a Markdown file of instructions that Claude Code loads at the start of every session. It can live at user level, in the project, or in managed (organisation) policy. Files in subfolders load when Claude works in those folders. AGENTS.md is a cross-tool instruction file that other coding agents also read. Auto memory is a set of notes that Claude writes for itself from your corrections. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]

**What it guarantees.**
- The files are loaded into context every session. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]
- From v2.1.277, Claude Code reads AGENTS.md when there is no CLAUDE.md or CLAUDE.local.md in the working folder or above it. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]
- Auto memory loads its first 200 lines or 25 KB each session. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]

**What it does not guarantee.**
- It does not guarantee that Claude follows the instructions. The page says to use a PreToolUse hook to block an action regardless of what Claude decides. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]
- The recommended size is under 200 lines per file, because longer files use more context and are followed less reliably. Imported files still enter the context, so imports organise text but do not save space. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]
- A CLAUDE.md shipped inside a plugin is not loaded at all. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]

**Known bugs and limits.**
- Issue #92271 (open, reported on v2.1.260): in bypassPermissions mode, an injected instruction steers the model to use shell commands instead of the Read, Edit and Write tools. That silently skips path-scoped rules, nested CLAUDE.md files, and hooks on those tools. The reporter's workaround is the environment variable `CLAUDE_CODE_THRIFTY_SONIC=0`. [VERIFIED as the issue's content | github.com/anthropics/claude-code/issues/92271 | opened 2026 (date not shown)]
- `/doctor` proposes cuts for CLAUDE.md content that Claude can work out from the code. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]

## 2. Rules files (`.claude/rules/*.md` with `paths`)

**What it is.** A rules file is a Markdown file of instructions, optionally with a `paths` list of file patterns. A rule with `paths` is meant to load only when Claude works with a matching file. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]

**What it guarantees.** The loading is observable. The InstructionsLoaded hook fires with the reason `path_glob_match` when a rule loads because of a path. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]

**What it does not guarantee.** Like CLAUDE.md, a rule is context, not enforcement. [VERIFIED | code.claude.com/docs/en/memory | accessed 2026-09-26]

**Known bugs and limits.**
- Issue #16299 (open, opened 2026-01-05, reported on v2.0.76): path-scoped rules load into context at session start whatever their `paths` say. [VERIFIED | github.com/anthropics/claude-code/issues/16299 | 2026-01-05]
- Issue #23478 (closed as not planned, opened 2026-02-05): rules loaded when Claude read a matching file, but not when it wrote or created one. [VERIFIED | github.com/anthropics/claude-code/issues/23478 | 2026-02-05]
- Further reports say that user-level rules ignore `paths` (#21858), that rules found through a git worktree ignore `paths` (#23569), and that rules do not load when Write creates a new file (#96361). [PARTIAL | github.com/anthropics/claude-code/issues/21858 | observed 2026-09-26; github.com/anthropics/claude-code/issues/23569 | 2026-02-06; github.com/anthropics/claude-code/issues/96361 | 2026-09-23]
- Design consequence [ASSUMPTION]: do not rely on a path rule to deliver a constraint at the moment a new file is created. Enforce such constraints with a hook or a CI check.

## 3. Skills

**What it is.** A skill is a folder with a SKILL.md file: a description plus instructions, and optionally scripts. Claude sees each skill's description at the start of a session and loads the full text only when it decides to use the skill. You can also run it yourself as `/skill-name`. Custom slash commands are now a kind of skill. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26; VERIFIED as read by a sub-agent | code.claude.com/docs/en/skills]

**What it guarantees.**
- The full text of a skill loads only when the skill is used. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- `disable-model-invocation: true` means only you can start the skill. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- A skill's `allowed-tools` pre-approves tools only for the turn that invokes the skill. [VERIFIED as read by a sub-agent in the raw page | code.claude.com/docs/en/skills | accessed 2026-09-26]
- Skills in a plugin are namespaced, as in `/harness-kit:verify`. [VERIFIED | code.claude.com/docs/en/plugins/components | accessed 2026-09-26]

**What it does not guarantee.**
- It does not guarantee that Claude will invoke the skill. In one public evaluation the skill was never invoked in 56% of cases. [VERIFIED | vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals | 2026-01-27]
- Every listed skill adds its description to the context on every turn, whether or not it is used. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/whats-new (week 36) | 2026-08-31 to 2026-09-04]
- The skill listing truncates the combined description text at 1,536 characters. [PARTIAL | code.claude.com/docs/en/skills | accessed 2026-09-26; summary reading]

**Known bugs and limits.**
- Issue #80802 (open, reported on v2.1.218): when Claude invokes a plugin skill through the Skill tool, the SKILL.md body is not put into context. This happens with `--plugin-dir` and with installed plugins. The issue itself says it repeats earlier reports #25834 and #68664, both closed. [VERIFIED | github.com/anthropics/claude-code/issues/80802 | observed 2026-09-26]
- Skills never triggered in `-p` runs with a heavy configuration (#34648). No disk skills loaded on v2.1.271 (#95367). [PARTIAL | github.com/anthropics/claude-code/issues/34648 | observed 2026-09-26; github.com/anthropics/claude-code/issues/95367 | 2026-09-18]
- Design consequence [ASSUMPTION]: never let a gate depend on a skill being read. Measure skill triggering with `claude plugin eval` (section 15).

## 4. Subagents

**What it is.** A subagent is a separate Claude instance with its own context window, its own system prompt and optionally its own tool list. The main session delegates a task to it and receives a summary back. Subagents are defined as Markdown files in `.claude/agents/`, in `~/.claude/agents/`, in managed policy, or in a plugin. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]

**What it guarantees.**
- Frontmatter fields [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]:
  - `name` and `description`, which are required; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `tools`, the tools the subagent may use, and `disallowedTools`, which removes tools; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `model` and `effort`; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `permissionMode`, which is also written `manual` from v2.1.200; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `maxTurns`: when reached, the output is returned marked as partial and can be resumed; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `skills`: the full content of the listed skills is preloaded; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `mcpServers`, `hooks` and `memory`; [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
  - `background`, `omitClaudeMd`, `isolation: worktree`, `color`, `initialPrompt`, and `experimental.cacheTtl`. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
- `disallowedTools` works as a hard tool restriction. An entry such as `Bash(git push *)` removes the whole Bash tool. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
- Hooks defined in settings files also fire inside subagents. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]

**What it does not guarantee.**
- **Plugin subagents lose fields.** The page states: "plugin subagents don't support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields". `initialPrompt` is also ignored. The documented workaround is to copy the agent file into `.claude/agents/`, or to add session-wide allow rules. [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
- If the main session runs in bypassPermissions, acceptEdits or auto mode, the subagent uses that mode and ignores its own `permissionMode`. [VERIFIED as read by a sub-agent in the raw page | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]

**Known bugs and limits.**
- Issue #95650 (open, opened 2026-09-20, v2.1.258, Windows 11 with Git Bash): a PreToolUse hook in a subagent's frontmatter never fires, while the same hook in `.claude/settings.json` does. [VERIFIED | github.com/anthropics/claude-code/issues/95650 | 2026-09-20]
- Issue #25000 (opened 2026-02-11, v2.1.39): subagents ran shell commands despite deny rules in `settings.local.json`. It was closed as a duplicate. Whether the underlying problem is fixed is NOT FOUND. [VERIFIED | github.com/anthropics/claude-code/issues/25000 | 2026-02-11]
- Hooks written in agent frontmatter were not executed for subagents (#18392). [PARTIAL | github.com/anthropics/claude-code/issues/18392 | observed 2026-09-26]

## 5. Agent teams

**What it is.** An agent team is a lead Claude Code session plus several "teammate" sessions. They share a task list and send each other messages. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]

**What it guarantees.**
- The feature is experimental and off by default. It is enabled with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
- It has three quality-gate hooks [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]:
  - **TeammateIdle**: exit code 2 keeps the teammate working. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - **TaskCreated**: exit code 2 prevents the task from being created. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - **TaskCompleted**: exit code 2 prevents the task from being marked complete. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
- A teammate cannot approve a permission request on your behalf. Approval claims relayed between agents are treated as untrusted. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]

**What it does not guarantee.**
- In `-p` (headless) mode, Claude does not spawn teammates at all. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
- The documented limitations [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]:
  - in-process teammates are not restored on resume; [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - task status can lag; [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - shutdown can be slow; [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - a session has one team, and there are no nested teams; [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - the lead is fixed; [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
  - permission modes are set at spawn time. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]
- A teammate can use a subagent definition from the project, user or managed scope. The `skills` field of that definition is not applied. [VERIFIED | code.claude.com/docs/en/agent-teams | accessed 2026-09-26]

**Known bugs and limits.** Issue #78234 (open, reported on v2.1.211) says plugin-scoped subagent definitions are silently dropped when used as teammates, so the teammate gets all tools. [VERIFIED | github.com/anthropics/claude-code/issues/78234 | 2026-07 (inferred)] The current page lists only project, user and managed scopes, which suggests this is now the intended behaviour. [ASSUMPTION]

## 6. Hooks

**What it is.** A hook is a handler that Claude Code runs automatically when a named event happens. It is configured in settings files, in a plugin's `hooks/hooks.json`, or in skill and subagent frontmatter. Handlers can be shell commands, HTTP endpoints, MCP tool calls, single model prompts, or subagents. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]

**The 33 events, and which can block.** The event list is complete, from the reference [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]. Where the reference's per-event exit-code table could not be read in full, I used the other page named on each line.

| Event | Can it stop or change what happens? | Evidence |
|---|---|---|
| PreToolUse | Yes. Exit code 2, or a JSON "deny", blocks the tool call. A deny works even in bypassPermissions mode. | [VERIFIED \| code.claude.com/docs/en/hooks; code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| PermissionRequest | Only through its JSON decision object. Exit code 2 is not honoured. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| UserPromptSubmit | Yes. It blocks the prompt and erases it. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| UserPromptExpansion | Yes. It blocks a typed command from expanding into a prompt. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| Stop | Yes. It prevents Claude from stopping. It is overridden after eight blocks in a row without progress. | [VERIFIED \| code.claude.com/docs/en/hooks; code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| SubagentStop | Yes, for prompt hooks: the reason is fed back so that the subagent keeps working. | [PARTIAL \| code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| TeammateIdle, TaskCreated, TaskCompleted | Yes, as described in section 5. | [VERIFIED \| code.claude.com/docs/en/agent-teams \| accessed 2026-09-26] |
| ConfigChange | Yes. Exit code 2 or a "block" decision stops a changed settings file from taking effect; no message is shown. | [VERIFIED \| code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| PreModelSwitch | Yes. It blocks a model switch. A timeout also blocks. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| WorktreeCreate | Yes. Any non-zero exit aborts the creation. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| WorktreeRemove | Yes. A non-zero exit fails the removal if the folder still exists. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| Elicitation | Probably yes: the guide lists it among events whose block shows no message. | [PARTIAL \| code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| PostToolUse, PostToolUseFailure, PostToolBatch | They cannot undo the action. A "block" decision ends the turn or feeds the reason back to Claude. | [VERIFIED \| code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| PreCompact | Reported as able to block compaction, but only by a summarising fetch that proved unreliable on this table. | [PARTIAL \| code.claude.com/docs/en/hooks, summarised fetch \| accessed 2026-09-26] |
| SessionStart, Setup and the remaining events (PermissionDenied, Notification, MessageDisplay, SubagentStart, StopFailure, InstructionsLoaded, CwdChanged, DirectoryAdded, FileChanged, PostCompact, PostModelSwitch, ElicitationResult, SessionEnd) | No. For SessionStart, exit code 2 only shows the error text. PermissionDenied can set a `retry` field. StopFailure discards all output. | [VERIFIED for SessionStart, PermissionDenied and StopFailure \| code.claude.com/docs/en/hooks; code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] [PARTIAL for the rest \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |

**What hooks guarantee.**
- A PreToolUse hook that exits with code 2 stops the call before permission rules are evaluated, so it wins over an allow rule. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- Several hooks matching the same event run in parallel, and a deny takes precedence. [VERIFIED | code.claude.com/docs/en/hooks-guide | accessed 2026-09-26]
- Default timeouts: 600 seconds for command, HTTP and MCP-tool hooks; 30 for prompt hooks; 60 for agent hooks. The command default drops to 30 on UserPromptSubmit and PreModelSwitch. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- Hooks configured in managed settings cannot be disabled by user or project settings. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- `--include-hook-events` puts hook lifecycle events into the headless output stream, which makes hooks testable. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]

**What hooks do not guarantee.**
- **Exit code 1 does not block.** Only exit code 2 blocks through the exit code alone. Any other code is a non-blocking error. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **A hook that cannot start does not block.** The shell exits with a code like 127 and the action proceeds, so a mistyped script path silently switches the gate off. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **Timeouts fail open.** A command, HTTP or MCP-tool hook that times out renders no decision, and a PreToolUse call continues. The exceptions are Agent SDK callback hooks and PreModelSwitch. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **The `if` filter is best-effort.** When Claude Code cannot tell which commands a shell input runs, it runs the hook anyway. The docs point to the permission system for a hard allow or deny. [VERIFIED | code.claude.com/docs/en/hooks | accessed 2026-09-26]
- **Hooks can be switched off.**
  - `disableAllHooks` switches off every hook except managed ones. [VERIFIED | code.claude.com/docs/en/hooks; code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
  - The managed setting `allowManagedHooksOnly` blocks user, project and plugin hooks, except hooks from plugins force-enabled in managed settings. [VERIFIED | code.claude.com/docs/en/hooks; code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
  - `--bare` mode skips hook discovery entirely. [VERIFIED | code.claude.com/docs/en/hooks; code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
- **Hooks run with your full user permissions and outside the sandbox.** [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]

**Known bugs and limits.**
- #80697 (open; reported on v2.1.218, reproduced on 2.1.233): a hook run through an interpreter such as Python exits with code 2 when its script is missing, and is then treated as a deliberate block. [VERIFIED | github.com/anthropics/claude-code/issues/80697 | 2026-08 (inferred)]
- #58637 (open, v2.1.131): with six or more background subagents, stale "running" entries made a Stop hook loop more than 150 times until the context was exhausted. [VERIFIED | github.com/anthropics/claude-code/issues/58637 | 2026-05 (inferred)]
- #95650 (open): subagent frontmatter hooks did not fire. See section 4. [VERIFIED | github.com/anthropics/claude-code/issues/95650 | 2026-09-20]
- Plugin Stop hooks did not run (#29767, closed). `CLAUDE_PLUGIN_ROOT` was not set for some plugin Stop hooks (#66557). [PARTIAL | github.com/anthropics/claude-code/issues/29767 | 2026-03-01; github.com/anthropics/claude-code/issues/66557 | observed 2026-09-26]
- There is no supported way to confirm which hook file actually ran (#83952). [PARTIAL | github.com/anthropics/claude-code/issues/83952 | observed 2026-09-26]

## 7. Permissions and permission modes

**What it is.** Permission rules in settings files decide whether a tool call is allowed, needs your approval ("ask"), or is refused. They are written like `Bash(npm test *)` or `Edit(src/**)`. A permission mode sets the default behaviour for calls that no rule covers. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]

**What it guarantees.**
- Rules are evaluated in the order deny, then ask, then allow. The first match decides, and specificity does not change the order. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- Read and Edit deny rules cover Claude's file tools, the shell file commands Claude Code recognises (`cat`, `head`, `tail`, `sed`, `tee`), and redirect targets. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- File path rules must be written as `Edit(...)` or `Read(...)`. A `Write(...)` path rule is accepted but never consulted, and Claude Code warns at startup. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- The modes are default (also called manual), acceptEdits, plan, dontAsk, bypassPermissions and auto. From v2.1.283, auto mode is the built-in starting mode for interactive terminal and VS Code sessions. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- In auto mode, a separate classifier model reviews actions before they run. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]

**What it does not guarantee.**
- Deny rules do not cover programs that open files themselves, such as Python or Node scripts. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- A shell deny rule does not match the same program called by its full path or inside `sh -c`. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- The auto-mode classifier misses some dangerous actions. Anthropic measured a false-negative rate of 17% on real "overeager" actions, meaning actions the user had not actually authorised, and 5.7% on synthetic data-exfiltration tests. Its false-positive rate was 0.4%. [VERIFIED | anthropic.com/engineering/claude-code-auto-mode | 2026-03-25]
- When the classifier repeatedly blocks actions in a `-p` run, Claude Code does not stop the run. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]
- bypassPermissions skips prompts even for writes to protected paths such as `.git` and `.claude`, and the page says to use it only in isolated containers or virtual machines. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]

**Known bugs and limits** (all read by a sub-agent; state not re-checked by me):
- Shell rules can be bypassed with equivalent forms such as `git -C path push` or `FOO=1 git push` (#66176). [PARTIAL | github.com/anthropics/claude-code/issues/66176 | observed 2026-09-26]
- The `@../` attachment syntax could read denied files (#61148). [PARTIAL | github.com/anthropics/claude-code/issues/61148 | observed 2026-09-26]
- Look-alike Unicode characters evade rule matching (#29489). [PARTIAL | github.com/anthropics/claude-code/issues/29489 | observed 2026-09-26]

## 8. Sandboxing

**What it is.** The sandbox is operating-system isolation for shell commands: Seatbelt on macOS, and bubblewrap on Linux and WSL2. It limits which files and network hosts a command and all its child processes can reach. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]

**What it guarantees.**
- The limits apply to Bash, PowerShell and Monitor commands and every process they start. Read and Edit deny rules are merged into the sandbox, so the operating system enforces them. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- Network traffic goes through a proxy that runs outside the sandbox and allows only listed domains. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- Inside writable folders, the sandbox still denies writes to the files that Claude Code loads configuration and code from. That stops a command from adding its own hook or permission. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- **Strict mode.** `allowUnsandboxedCommands: false` stops blocked commands from being retried outside the sandbox. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- **Required mode.** `failIfUnavailable: true` refuses to start without a working sandbox. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]

**What it does not guarantee.**
- By default, a sandbox that cannot start only warns, and commands run unsandboxed. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- Without strict mode, a blocked command can be retried outside the sandbox through the normal permission flow. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- It does not cover Claude's own Read, Edit and Write tools, which permission rules govern. [VERIFIED | code.claude.com/docs/en/permissions | accessed 2026-09-26]
- It does not cover hooks or MCP servers, which run outside it. [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]
- Commands you type yourself with the `!` prefix run outside the sandbox unless certain session types apply. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- It is not available on native Windows. [VERIFIED | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
- Anthropic reports that sandboxing cut permission prompts by 84%. [VERIFIED as read by a sub-agent | anthropic.com/engineering/claude-code-sandboxing | 2025-10-20]
- Whether the sandbox works inside GitHub-hosted runners is NOT FOUND.

## 9. Git worktrees

**What it is.** A git worktree is a second working copy of the same repository, on its own branch. `claude --worktree <name>` (or `-w`) starts a session in one under `.claude/worktrees/`, and a subagent with `isolation: worktree` gets its own temporary worktree. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]

**What it guarantees.**
- Edits in one worktree do not touch the files of another. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]
- A session in a worktree is blocked from editing files in the main checkout, and from redirecting git to it. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]

**What it does not guarantee.**
- The worktrees share one `.git` store. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]
- "Don't ask again" approvals are saved to the main checkout's local settings. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]
- Worktrees created in `-p` runs are not cleaned up automatically. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]
- Git LFS files arrive as pointer files until you run `git lfs pull`. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/worktrees | accessed 2026-09-26]
- Ports, databases and other machine-wide resources are shared. [ASSUMPTION]

## 10. Plugins and marketplaces (summary; details in 04 and 05)

**What it is.** A plugin is a folder with a `.claude-plugin/plugin.json` manifest. It can bundle skills, commands, agents, hooks, MCP servers, LSP (language server) configurations, output styles, workflows, a `bin/` folder, default settings, user-configuration prompts and dependencies. A marketplace is a catalog file (`.claude-plugin/marketplace.json`) that lists plugins and where to fetch them. [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]

**What it guarantees.**
- An enabled plugin's hooks register when it loads. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/components | accessed 2026-09-26]
- `claude plugin validate --strict` fails on warnings. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]

**What it does not guarantee.**
- **A plugin cannot ship permissions, sandbox settings or environment variables.** Only the `agent` and `subagentStatusLine` settings keys take effect, and "other keys are dropped at load". [VERIFIED | code.claude.com/docs/en/plugins-reference | accessed 2026-09-26]
- Plugin subagents lose `hooks`, `mcpServers` and `permissionMode` (section 4). [VERIFIED | code.claude.com/docs/en/sub-agents | accessed 2026-09-26]
- Plugin hooks and MCP servers run outside the sandbox with your user privileges. [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]
- A plugin with a top-level `bin/` folder cannot be installed in claude.ai chat or Cowork. It works only in Claude Code. [VERIFIED | claude.com/docs/plugins/platform-support | accessed 2026-09-26]

## 11. Headless mode (`claude -p`)

**What it is.** `claude -p "prompt"` runs one non-interactive session and prints the result, optionally as JSON or a stream of JSON events. It is how Claude Code runs in scripts and CI. [VERIFIED | code.claude.com/docs/en/best-practices | accessed 2026-09-26]

**What it guarantees.**
- Without `--bare`, a `-p` session still loads CLAUDE.md, project hooks, skills, MCP servers and installed plugins. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/headless | accessed 2026-09-26]
- With `--output-format stream-json --verbose`, the first event lists the loaded plugins, plus a `plugin_errors` list. That lets CI check that the harness actually loaded. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/headless | accessed 2026-09-26; the plugin list is also stated in code.claude.com/docs/en/plugins/org]
- `--plugin-dir` loads a plugin for that run only. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]

**What it does not guarantee.**
- `--bare` skips hooks, skills, custom commands, subagents, installed plugins, MCP servers, auto memory and CLAUDE.md. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
- `/plugin` commands do not run in `-p`. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/install | accessed 2026-09-26]
- Repository marketplace entries apply only in trusted folders (01, C3). [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
- A background shell task is terminated about five seconds after the final result. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/headless | accessed 2026-09-26]

## 12. The GitHub Action (`anthropics/claude-code-action@v1`)

**What it is.** A GitHub Action that runs Claude Code inside a GitHub Actions workflow, either when someone mentions `@claude` or with a fixed prompt. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/github-actions | accessed 2026-09-26]

**What it guarantees.**
- It has inputs named `prompt`, `claude_args` (extra command-line flags, for example `--max-turns`), `settings`, `plugin_marketplaces` and `plugins`. [VERIFIED | raw.githubusercontent.com/anthropics/claude-code-action/main/action.yml | accessed 2026-09-26]
- The action runs `claude plugin marketplace add` and then `claude plugin install` for the listed entries. It stops at the first failure. [VERIFIED as read by a sub-agent from the action's source | github.com/anthropics/claude-code-action (base-action/src/install-plugins.ts) | observed 2026-09-26]

**What it does not guarantee.**
- **It cannot pin a marketplace to a git ref.** Marketplace URLs must end in `.git`, with nothing after it. The request to allow `#ref` is open (#1229). [VERIFIED | github.com/anthropics/claude-code-action/issues/1229 | observed 2026-09-26]
- A local-folder marketplace, checked out by an earlier step, is accepted. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-action/pull/761 | merged 2026-01-05]
- Plugin installs broke in May 2026 because of a Claude Code installer regression, and were then fixed (#1290). [PARTIAL | github.com/anthropics/claude-code-action/issues/1290 | opened 2026-05-06]

## 13. The `/goal` command

**What it is.** `/goal <condition>` sets a completion condition. After each turn, a small, fast model (Haiku by default) checks the condition against the conversation. While the condition is "not yet met", Claude starts another turn. It is a session-scoped wrapper around a prompt-based Stop hook. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]

**What it guarantees.**
- The loop continues until the model judges the condition met or impossible, or until an error you must fix occurs. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]
- It works in `-p`, running the loop to completion in one invocation. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]
- The condition can be up to 4,000 characters. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]
- It is restored when you resume a session (v2.1.239 and later). [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26]

**What it does not guarantee.**
- The evaluator "doesn't run commands or read files independently". It only reads what Claude has shown in the conversation, so it can be fooled by claimed results that were never run. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26; the consequence is ASSUMPTION]
- A turn or time limit written into the condition is judged by the model from the conversation, so it is a soft limit. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26; the consequence is ASSUMPTION]
- `/goal` is unavailable when `disableAllHooks` is true or `allowManagedHooksOnly` is set. [VERIFIED | code.claude.com/docs/en/goal | accessed 2026-09-26; the consequence is ASSUMPTION]
- Codex CLI or other tools may have a similarly named command. I did not research this, so any comparison is NOT FOUND.

## 14. Budgets: turns, time and cost

| Budget | Where | What happens at the limit | Label |
|---|---|---|---|
| `--max-turns N` | CLI, print mode only | The run exits with an error. There is no limit by default. | [VERIFIED \| code.claude.com/docs/en/cli-reference \| accessed 2026-09-26] |
| `--max-budget-usd X` | CLI, print mode only | The run stops. Subagent spend counts towards the cap. | [VERIFIED \| code.claude.com/docs/en/cli-reference \| accessed 2026-09-26] |
| `maxTurns` | Subagent frontmatter | The output is returned marked partial and can be resumed. | [VERIFIED \| code.claude.com/docs/en/sub-agents \| accessed 2026-09-26] |
| A turn or time clause in `/goal` | Session | The model judges it: a soft limit. | [VERIFIED \| code.claude.com/docs/en/goal \| accessed 2026-09-26] |
| Stop-hook block cap | Hooks | The hook is overridden after 8 blocks in a row without progress. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` changes the number. | [VERIFIED \| code.claude.com/docs/en/hooks-guide \| accessed 2026-09-26] |
| Hook `timeout` | Hooks | The hook is cancelled and usually renders no decision. | [VERIFIED \| code.claude.com/docs/en/hooks \| accessed 2026-09-26] |
| `--max-cost-usd` | `claude plugin eval` | No new runs start; the command exits with code 2 and partial results. | [VERIFIED \| code.claude.com/docs/en/plugin-evals \| accessed 2026-09-26] |
| Wall-clock limit for a whole session | CLI | NOT FOUND. Use the CI job's own timeout. | [ASSUMPTION for the workaround] |

A sub-agent read that v2.1.281 fixed a turn that could retry forever while ignoring `--max-turns`. [PARTIAL | code.claude.com/docs/en/changelog | entries 2026-09-17 to 2026-09-25]

## 15. Tools for testing a plugin harness

- **`claude plugin validate <path> [--strict] [--json]`** checks manifests, frontmatter and hook files statically. Exit code 0 means passed; 1 means failed, and with `--strict` warnings count as failures. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
- **`claude plugin eval`** (v2.1.269 and later) runs test cases from an `evals/` folder. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Each case runs three times with the plugin and three times without it, and the report shows the difference. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - The graders are regex, tool-used, tool-order, file-exists, a model judge, and comparison with a reference transcript. "There are no custom-code graders." [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - For CI: `--json`, `--threshold`, `--max-cost-usd`, `--trust-plugin` and `--no-publish`. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Exit codes: 0 means all cases passed; 1 means a case failed; 2 means a partial run. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - The plugin's hooks and real MCP servers run outside the evaluation's sandbox. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
- **Issue #96121** (open, opened 2026-09-22, v2.1.280): the evaluation sandbox never loads the plugin's own agent files, so cases that call plugin agents fail with "Agent type not found". [VERIFIED | github.com/anthropics/claude-code/issues/96121 | 2026-09-22]
- **`/skill-doctor`** (v2.1.252) reports each skill's context cost and how often it is used. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/whats-new (week 36) | 2026-08-31 to 2026-09-04]
- **`claude plugin details <name>`** prints a plugin's component inventory without starting a session. [VERIFIED | code.claude.com/docs/en/plugins/security | accessed 2026-09-26]

## Negative results

- **A fail-closed setting for command hooks:** NOT FOUND. I searched the hooks reference and hooks guide for fail, closed, timeout and crash.
- **A wall-clock time limit for a session:** NOT FOUND in the CLI reference.
- **The full per-event exit-code table in the hooks reference:** my fetches were cut off after the Stop row, and one summarising fetch produced rows that contradicted two other Anthropic pages. I therefore did not use that fetch, and marked the affected rows [PARTIAL].
- **Whether the sandbox works on GitHub-hosted runners:** NOT FOUND.
- **A documented character budget for the whole skill listing:** only a per-skill truncation figure was found. [PARTIAL | code.claude.com/docs/en/skills | accessed 2026-09-26]
