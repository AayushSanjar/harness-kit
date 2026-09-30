# 03 — Reference harnesses and starter kits that people actually use (observed 26 September 2026)

**Sources and how they were selected.** This file cites 58 sources.

**Sample.**
- A research sub-agent examined 23 named repository candidates, 3 company write-ups and 21 further items found while searching.
- It included 15 repository or plugin entries and 4 company write-ups, and rejected 10 candidates (listed at the end).
- **How candidates were found:**
  - Anthropic's official plugin marketplace file and its public plugin directory (claude.com/plugins);
  - the lists github.com/hesreallyhim/awesome-claude-code and github.com/walkinglabs/awesome-harness-engineering;
  - web searches such as "TDD Guard Claude Code hooks", "Ralph Wiggum loop Claude Code critique", "Stripe Minions coding agents" and "Spotify background coding agent Honk".

**Inclusion rules.**
- The project is public and explicitly supports Claude Code.
- It enforces something through hooks, CI, tests or reviewer agents. Prompt-only kits were kept only when widely adopted.
- There is evidence of real use: stars, installs, downloads, or a write-up of use at a company.
- It shows activity in 2026, or its staleness is flagged.

**Bias.** The sample favours popular, English-language projects hosted on GitHub. It is not a random sample, so the comparison at the end describes this sample only.

**Reading method.**
- Pages were read as text; no images were viewed.
- Star counts come from the GitHub page as read on 2026-09-26.
- I re-checked two items myself: the star count and install commands of obra/superpowers, and the install commands of trailofbits/skills. The rest is labelled "[VERIFIED as read by a sub-agent]".
- URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source or partial support. [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**A caution about the evidence.**
- Stars and install counts measure popularity, not effectiveness. [ASSUMPTION]
- Peer-reviewed research found about 6 million suspected fake GitHub stars, with AI and LLM repositories prominent among fake-star campaigns. That study says nothing about any specific repository below. [VERIFIED as read by a sub-agent | arxiv.org/abs/2412.13459 | v2 2025-09-06, ICSE 2026]
- No harness in the sample publishes a controlled comparison of results with and without it. NOT FOUND. The closest is Anthropic's own two-application comparison (entry W4).

**Terms.**
- A **PreToolUse hook** runs before a tool call and can block it.
- A **PostToolUse hook** runs after a tool call; it cannot undo the call, but it can send feedback.
- A **Stop hook** runs when Claude tries to finish and can make it continue.
- A **model judge** is a separate model call that accepts or rejects work; its verdicts vary from run to run.
- 00-glossary.md defines the rest.

---

## Entries (open-source or public plugins)

### 1. Anthropic's official plugins: hookify, security-guidance, ralph-loop, code-review, pr-review-toolkit, plugin-dev
- **Where:**
  - github.com/anthropics/claude-plugins-official, licensed Apache-2.0 per the plugin licence files checked; [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official; github.com/anthropics/claude-code | observed 2026-09-26]
  - development copies in github.com/anthropics/claude-code/tree/main/plugins. That repository is marked all rights reserved, so copy from the official-marketplace repository instead. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official; github.com/anthropics/claude-code | observed 2026-09-26]
- **Adoption:**
  - install counts on Anthropic's directory: Code Review 438,525; Security Guidance 241,800; Ralph Loop 196,527; Hookify 60,376; [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-26]
  - the directory does not define what counts as an install; [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-26]
  - about 37.0k stars on the official-marketplace repository. [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-26]
- **What each enforces, and how:**
  - **hookify** turns Markdown rule files (`.claude/hookify.<name>.local.md`: an event, regex conditions, and warn or block) into PreToolUse, PostToolUse, Stop and UserPromptSubmit hooks. With no arguments, `/hookify` reads the conversation for behaviour you corrected and proposes rules. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-plugins-official/main/plugins/hookify/README.md | observed 2026-09-26]
  - **security-guidance v2** has three layers: a regex check after each edit, a background model review of the turn's diff at Stop, and an agentic review on commit or push. Anthropic's page says none of the layers block writes or commits. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/security-guidance | accessed 2026-09-26]
  - **ralph-loop** has one Stop hook that blocks the stop and feeds the original prompt back, with an iteration cap (unlimited by default) and an exact completion string. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-plugins-official/main/plugins/ralph-loop/README.md | observed 2026-09-26]
  - **code-review** runs parallel agents, keeps findings with confidence 80 or above, and ignores pre-existing issues and linter-level nits. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-code/main/plugins/code-review/README.md | observed 2026-09-26]
  - **plugin-dev** ships shell scripts that validate hook schemas and run a hook with sample input. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-code/main/plugins/plugin-dev/README.md | observed 2026-09-26]
- **Reusable:**
  - hookify as a rule engine; [ASSUMPTION]
  - ralph-loop's capped Stop hook; [ASSUMPTION]
  - security-guidance's pattern of "cheap deterministic check first, then a separate-context model review"; [ASSUMPTION]
  - plugin-dev's hook test scripts. [ASSUMPTION]
- **Evidence that it works:**
  - A news report says Anthropic saw 30–40% fewer security review comments on pull requests opened with security-guidance during an internal rollout. [PARTIAL | helpnetsecurity.com/2026/05/27/anthropic-claude-code-security-guidance-plugin | 2026-05-27]
  - No independent evaluation of these plugins was found. NOT FOUND.
- **Weaknesses:**
  - The reviewers are model judgements, and security-guidance never blocks. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official | observed 2026-09-26]
  - Anthropic's own documents disagree on some details, such as how many review agents code-review uses. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-plugins-official | observed 2026-09-26]

### 2. anthropics/claude-quickstarts — "autonomous-coding" (Anthropic's long-running harness)
- **Where:** github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding. MIT licence; the repository was last pushed 2026-09-24. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding | observed 2026-09-26]
- **What it enforces, and how:**
  - An initializer agent writes `feature_list.json` (200 features, all failing). Each later session implements the next failing feature, flips its flag, commits, and updates `claude-progress.txt`. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-quickstarts/main/autonomous-coding/README.md and security.py | observed 2026-09-26]
  - A PreToolUse hook on shell commands enforces a fixed command allowlist; commands it cannot parse are blocked. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-quickstarts/main/autonomous-coding/README.md and security.py | observed 2026-09-26]
  - An operating-system sandbox and project-only file access complete the controls. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-quickstarts/main/autonomous-coding/README.md and security.py | observed 2026-09-26]
- **Reusable:** the allowlist hook, the feature list with pass flags, the progress file, the initializer and coding agent split, and `init.sh`. [ASSUMPTION]
- **Evidence:**
  - The companion write-up gives qualitative results only. [VERIFIED | anthropic.com/engineering/effective-harnesses-for-long-running-agents | 2025-11-26]
  - A full run takes many hours. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding | observed 2026-09-26]
- **Weakness:** "never edit tests" is an instruction; no code checks it. [ASSUMPTION]

### 3. anthropics/claude-code-security-review (a GitHub Action)
- **Where:** github.com/anthropics/claude-code-security-review. MIT licence, about 6.3k stars, last pushed 2026-02-11, no releases. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-security-review | observed 2026-09-26]
- **What it enforces:** it reviews only a pull request's changed files, with a false-positive filter, and posts line comments. It does not fail the build. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-security-review | observed 2026-09-26; the "does not fail the build" part is PARTIAL]
- **Evidence:**
  - Anthropic reports that it caught a remote code execution flaw and an SSRF flaw before merge. SSRF (server-side request forgery) is a flaw that lets an attacker make the server send requests to places it should not. These are two author-reported anecdotes. [VERIFIED as read by a sub-agent | claude.com/blog/automate-security-reviews-with-claude-code | 2025-08-06]
  - An independent Semgrep study of Claude Code with custom prompts (not this action) found a 14% true-positive rate and large run-to-run variation. [VERIFIED as read by a sub-agent | semgrep.dev/blog/2025/finding-vulnerabilities-in-modern-web-apps-using-claude-code-and-openai-codex | 2025-09-02]
- **Weakness:** stale, and the README warns that it is not hardened against prompt injection. Prompt injection means text in the reviewed code that tries to give the model instructions. [VERIFIED as read by a sub-agent | github.com/anthropics/claude-code-security-review | observed 2026-09-26]

### 4. nizos/tdd-guard, and its successor nizos/probity
- **Where:** github.com/nizos/tdd-guard and github.com/nizos/probity, both MIT licence. [VERIFIED as read by a sub-agent | github.com/nizos/tdd-guard | observed 2026-09-26]
- **Adoption:** about 2.3k stars, and 18,405 npm downloads in the week 2026-08-23 to 08-29. [VERIFIED as read by a sub-agent | api.npmjs.org/downloads/point/last-week/tdd-guard | week 2026-08-23 to 2026-08-29]
- **What it enforces, and how:**
  - PreToolUse hooks on Write and Edit call a model that checks each pending edit against the latest test output. It blocks writing code without a failing test, writing more than the tests require, and adding several tests at once. [VERIFIED as read by a sub-agent | github.com/nizos/tdd-guard; github.com/nizos/probity | observed 2026-09-26]
  - Probity generalises this into a rule API. Some of its rules are regex checks and some are model-validated, and since v1.8.1 it fails closed on invalid results. [VERIFIED as read by a sub-agent | github.com/nizos/tdd-guard; github.com/nizos/probity | observed 2026-09-26]
- **Reusable:** the three-hook wiring, and Probity's rule API, which reads the session transcript instead of language-specific test reporters. [ASSUMPTION]
- **Evidence:** the author reports both missed violations and wrong blocks during early testing. No independent evaluation was found. [VERIFIED as read by a sub-agent | nizar.se/tdd-guard-for-claude-code | 2025-07-21]
- **Weaknesses:**
  - There is no Java, JUnit, Maven or Gradle test reporter. [VERIFIED as read by a sub-agent | github.com/nizos/tdd-guard | observed 2026-09-26]
  - A model call on every edit adds delay and cost. [ASSUMPTION]
  - Its premise, test-first, is questioned by a 2026 experiment (01, C6). [VERIFIED | martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html | 2026-08-10]

### 5. obra/superpowers
- **Where:** github.com/obra/superpowers. MIT licence; I observed 289.8k stars and 25.9k forks. [VERIFIED | github.com/obra/superpowers | observed 2026-09-26] Anthropic's directory lists 1,009,371 installs. [VERIFIED as read by a sub-agent | claude.com/plugins | observed 2026-09-26]
- **Install:** `/plugin install superpowers@claude-plugins-official`, or `/plugin marketplace add obra/superpowers-marketplace` followed by `/plugin install superpowers@superpowers-marketplace`. [VERIFIED | github.com/obra/superpowers | observed 2026-09-26]
- **What it enforces, and how:**
  - Its only hook is a SessionStart hook that injects a bootstrap telling Claude to use its skills. [VERIFIED as read by a sub-agent | github.com/obra/superpowers | observed 2026-09-26]
  - Its skills cover brainstorming, planning, test-driven development, systematic debugging, verification before completion, code review, subagent-driven development and git worktrees. [VERIFIED as read by a sub-agent | github.com/obra/superpowers | observed 2026-09-26]
  - No hook blocks anything, so compliance depends on the model. [VERIFIED as read by a sub-agent | github.com/obra/superpowers | observed 2026-09-26]
- **Reusable:** the skill texts, the bootstrap pattern, and the author's practice of testing skills with pressure scenarios run by subagents. [VERIFIED as read by a sub-agent | blog.fsck.com/2025/10/09/superpowers | 2025-10-09]
- **Evidence:**
  - Popularity only. An evaluation lab exists (prime-radiant-inc/superpowers-evals) but publishes no scores. [VERIFIED as read by a sub-agent | github.com/obra/superpowers | observed 2026-09-26]
  - Simon Willison described the design but reported no use of his own. [PARTIAL | simonwillison.net/2025/Oct/10/superpowers | 2025-10-10]

### 6. EveryInc/compound-engineering-plugin
- **Where:** github.com/EveryInc/compound-engineering-plugin. MIT licence, about 25.2k stars; v3.21.4 released 2026-08-06; works on 14 agent hosts. [VERIFIED as read by a sub-agent | github.com/EveryInc/compound-engineering-plugin | observed 2026-09-26]
- **What it enforces:** skill-based commands for brainstorm, plan, work, simplify, multi-agent review and "compound". The compound step records lessons in `docs/solutions/` with metadata for later retrieval. No hooks or CI were found. [VERIFIED as read by a sub-agent | github.com/EveryInc/compound-engineering-plugin | observed 2026-09-26]
- **Reusable:**
  - the compounding step, which is a ready-made ratchet for knowledge (04, B4); [ASSUMPTION]
  - "Compound Packs": folders of rules pinned from a git repository and shared across repositories. [VERIFIED as read by a sub-agent | github.com/EveryInc/compound-engineering-plugin | observed 2026-09-26]
- **Evidence:** Every says it runs five products with mostly single-engineer teams. It gives no quality metrics. [VERIFIED as read by a sub-agent | every.to/chain-of-thought/compound-engineering-how-every-codes-with-agents | 2025-12-11]

### 7. snarktank/ralph (the Ralph loop as a script)
- **Where:** github.com/snarktank/ralph. MIT licence, about 20.8k stars, last pushed 2026-02-02. [VERIFIED as read by a sub-agent | github.com/snarktank/ralph | observed 2026-09-26]
- **What it enforces:**
  - A bash loop runs `claude --dangerously-skip-permissions --print` up to 10 times, until the output contains a completion token. [VERIFIED as read by a sub-agent | github.com/snarktank/ralph | observed 2026-09-26]
  - The script runs no checks itself. Typecheck, lint, tests and "commit only if they pass" are instructions in CLAUDE.md. [VERIFIED as read by a sub-agent | github.com/snarktank/ralph | observed 2026-09-26]
- **Reusable:** the `prd.json` story list with pass flags, the append-only progress file, and archiving per branch. [ASSUMPTION]
- **Evidence:** the originator reports anecdotes, and says he would not use the loop in an existing codebase. [VERIFIED as read by a sub-agent | ghuntley.com/ralph | 2025-07-14]
- **Weakness:** it bypasses permission prompts, and nothing is enforced in code. [VERIFIED as read by a sub-agent | github.com/snarktank/ralph | observed 2026-09-26]

### 8. github/spec-kit
- **Where:** github.com/github/spec-kit. MIT licence, about 133.7k stars, v1.0.3 released 2026-09-01. Its documentation lists Claude among 38 integrations. [VERIFIED as read by a sub-agent | github.com/github/spec-kit | observed 2026-09-26]
- **What it enforces:** commands move a feature through constitution, specify, plan, tasks, implement and converge. Helper scripts exit with an error when `plan.md` or `tasks.md` is missing. [VERIFIED as read by a sub-agent | github.com/github/spec-kit | observed 2026-09-26]
- **Reusable:** the constitution, spec, plan and tasks templates, and the prerequisite scripts. [ASSUMPTION]
- **Evidence:** Böckeler tried it on a small task and found the Markdown volume tedious to review, the agent sometimes ignoring instructions, and the process "overkill" for the size of the problem. [VERIFIED as read by a sub-agent | martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html | 2025-10-15]

### 9. Trail of Bits: trailofbits/claude-code-config and trailofbits/skills
- **Where:**
  - github.com/trailofbits/claude-code-config: no licence file found, about 2.1k stars, last pushed 2026-04-02. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
  - github.com/trailofbits/skills: CC-BY-SA-4.0 licence, 6.9k stars, installed with `/plugin marketplace add trailofbits/skills`. [VERIFIED | github.com/trailofbits/skills | observed 2026-09-26]
- **What it enforces, and how** (config):
  - The sandbox is treated as the real boundary. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
  - Deny rules cover SSH keys, cloud credentials, tokens and shell start-up files. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
  - PreToolUse hooks exit with code 2 to block `rm -rf` (use `trash` instead), pushes to main, and the wrong package manager. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
  - An "anti-rationalization" Stop prompt hook sends the final reply to Haiku, which blocks the stop when Claude defers issues or skips failing tests. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
- **Reusable:** the deny rules, the three blocking hooks, and the Stop prompt hook. Its evaluator must be told to reply in raw JSON, or the hook silently stops working. [VERIFIED as read by a sub-agent | github.com/trailofbits/claude-code-config | observed 2026-09-26]
- **Evidence:** Trail of Bits reports that on some audits, auditors now find about 200 bugs a week against about 15 before. This is company-reported and not independently audited. [VERIFIED as read by a sub-agent | blog.trailofbits.com/2026/03/31/how-we-made-trail-of-bits-ai-native-so-far | 2026-03-31]

### 10. kenryu42/claude-code-safety-net (now shown as "cc-safety-net")
- **Where:** github.com/kenryu42/claude-code-safety-net. MIT licence, about 1.6k stars, releases on 2026-09-26; 4,192 npm downloads in the week 2026-09-05 to 09-11. [VERIFIED as read by a sub-agent | github.com/kenryu42/claude-code-safety-net | observed 2026-09-26]
- **What it enforces:**
  - A PreToolUse hook on every tool parses commands by meaning, so wrappers such as `bash -c` or reordered flags do not hide them. [VERIFIED as read by a sub-agent | github.com/kenryu42/claude-code-safety-net | observed 2026-09-26]
  - It blocks `git reset --hard`, forced pushes, `rm -rf` on dangerous targets, `find -delete`, and reading keys or `.env` files. [VERIFIED as read by a sub-agent | github.com/kenryu42/claude-code-safety-net | observed 2026-09-26]
  - It has three strictness modes. [VERIFIED as read by a sub-agent | github.com/kenryu42/claude-code-safety-net | observed 2026-09-26]
- **Reusable:** a drop-in safety layer. It covers the command-matching gaps that Anthropic's own rules have (02, section 7). [ASSUMPTION]
- **Evidence:** automated tests of the command analyser, as claimed in the README. No independent evaluation was found. [VERIFIED as read by a sub-agent | github.com/kenryu42/claude-code-safety-net | observed 2026-09-26]

### 11. carlrannaberg/claudekit
- **Where:** github.com/carlrannaberg/claudekit. MIT licence, about 760 stars, last pushed 2026-03-31. [VERIFIED as read by a sub-agent | github.com/carlrannaberg/claudekit | observed 2026-09-26]
- **What it enforces:**
  - Per-file checks after each edit: typecheck, lint, tests, a ban on TypeScript's `any`, and detection of code replaced by a comment. [VERIFIED as read by a sub-agent | github.com/carlrannaberg/claudekit | observed 2026-09-26]
  - Project-wide checks plus a git checkpoint at Stop and SubagentStop. [VERIFIED as read by a sub-agent | github.com/carlrannaberg/claudekit | observed 2026-09-26]
  - Which of its hooks block is NOT FOUND in the README.
- **Reusable:** the split between fast checks per file after each edit and full checks at Stop. [ASSUMPTION]
- **Weakness:** TypeScript and JavaScript only; low adoption. [VERIFIED as read by a sub-agent | github.com/carlrannaberg/claudekit | observed 2026-09-26]

### 12. affaan-m/everything-claude-code (now shown as "ECC")
- **Where:** github.com/affaan-m/everything-claude-code. MIT licence, about 268k stars, created 2026-01-18. [VERIFIED as read by a sub-agent | github.com/affaan-m/everything-claude-code | observed 2026-09-26]
- **What it enforces:**
  - Hooks on seven events, including one that stops Claude from editing linter or formatter configuration. [VERIFIED as read by a sub-agent | github.com/affaan-m/everything-claude-code | observed 2026-09-26]
  - A "fact-forcing gate" that blocks the first edit to each file until Claude has investigated it. [VERIFIED as read by a sub-agent | github.com/affaan-m/everything-claude-code | observed 2026-09-26]
  - It also ships Java, Kotlin and Spring skill texts and a scanner for agent configurations. [VERIFIED as read by a sub-agent | github.com/affaan-m/everything-claude-code | observed 2026-09-26]
- **Reusable:** the configuration-protection hook, which stops an agent from weakening lint rules. [ASSUMPTION]
- **Evidence and risk:** a third-party audit (by a vendor of a competing scanner) reported 28 command hooks installed globally, unsigned auto-updates, and a malware clone repository circulating. [PARTIAL | dev.to/joergmichno/we-audited-the-viral-213k-star-everything-claude-code-repo-and-found-a-malware-clone-in-the-wild-14hb | 2026-06-12]

### 13. diet103/claude-code-infrastructure-showcase
- **Where:** github.com/diet103/claude-code-infrastructure-showcase. MIT licence, about 10k stars, last pushed 2026-07-13. [VERIFIED as read by a sub-agent | github.com/diet103/claude-code-infrastructure-showcase | observed 2026-09-26]
- **What it enforces:** a UserPromptSubmit hook suggests skills from `skill-rules.json`, and a PreToolUse guard blocks edits until mandatory skills are activated. That is one answer to "skills are not reliably invoked" (01, C5). [VERIFIED as read by a sub-agent | github.com/diet103/claude-code-infrastructure-showcase | observed 2026-09-26]
- **Weakness:** the README says it is not a working application, and its optional Stop hooks are TypeScript-specific. [VERIFIED as read by a sub-agent | github.com/diet103/claude-code-infrastructure-showcase | observed 2026-09-26]

### 14. disler/claude-code-hooks-mastery
- **Where:** github.com/disler/claude-code-hooks-mastery. No licence found, about 3.9k stars. [VERIFIED as read by a sub-agent | github.com/disler/claude-code-hooks-mastery | observed 2026-09-26]
- **What it enforces:** single-file Python hooks for 13 events. They block `rm -rf` variants and `.env` access, and PostToolUse validators block on Python lint and type errors. A builder agent is paired with a read-only validator agent. [VERIFIED as read by a sub-agent | github.com/disler/claude-code-hooks-mastery | observed 2026-09-26]
- **Reusable:** exit-code examples, and the builder with read-only validator pattern. With no licence, reuse is legally unclear. [ASSUMPTION]

### 15. ChrisWiles/claude-code-showcase
- **Where:** github.com/ChrisWiles/claude-code-showcase. MIT licence, about 6.0k stars, created and last pushed 2026-01-06. [VERIFIED as read by a sub-agent | github.com/ChrisWiles/claude-code-showcase | observed 2026-09-26]
- **What it enforces:** a PreToolUse hook blocks edits on the main branch with exit code 2. It also has four scheduled GitHub Actions workflows: pull-request review, weekly quality, monthly documentation sync, and a dependency audit. Some of its checks exit with 0 or 1, so they never block. [VERIFIED as read by a sub-agent | github.com/ChrisWiles/claude-code-showcase | observed 2026-09-26]
- **Reusable:** the branch guard, and the set of scheduled CI workflows. [ASSUMPTION]

## Company write-ups (write-up only; code not public)

- **W1. OpenAI, "Harness engineering"** (Ryan Lopopolo, 2026-02-11). The agent is Codex, not Claude. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
  - Scale: about 1 million lines and 1,500 pull requests in five months, with no hand-written code. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
  - Controls: custom linters and structural tests enforce layers, and their error messages carry fix-it instructions. The application boots in each git worktree with its own logs, metrics and traces. AGENTS.md is a map of about 100 lines. [VERIFIED as read by a sub-agent | openai.com/index/harness-engineering | 2026-02-11]
  - Independent verification: NOT FOUND.
- **W2. Stripe, "Minions"** (Alistair Gray, 2026-02-09 and 2026-02-19). [VERIFIED as read by a sub-agent | stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents | 2026-02-09]
  - More than 1,000 pull requests merged each week, written end to end by agents and reviewed by humans. [VERIFIED as read by a sub-agent from the page excerpt | stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents | 2026-02-09]
  - The article bodies could not be read. Secondary summaries say the agent interleaves deterministic steps (git, linters, tests) with agent loops, and that a task gets at most two CI rounds before it returns to a human. [PARTIAL | blog.bytebytego.com/p/how-stripes-minions-ship-1300-prs | 2026-03-16]
- **W3. Spotify, "Honk"** (Charas and Bruggmann, parts 1–3, November–December 2025). [VERIFIED | engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3 | 2025-12-09]
  - Claude Code performed best of the agents Spotify tried. [VERIFIED as read by a sub-agent | engineering.atspotify.com/2025/11/context-engineering-background-coding-agents-part-2 | 2025-11-24]
  - Verifiers switch on by ecosystem, for example Maven when a `pom.xml` exists, and all run through a Claude Code Stop hook before a pull request is created. [VERIFIED | engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3 | 2025-12-09]
  - A model judge compares the diff with the prompt and vetoes about a quarter of sessions. [VERIFIED | engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3 | 2025-12-09]
  - The agent runs in a sandboxed container. [VERIFIED | engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3 | 2025-12-09]
  - This is the most Java-relevant evidence found. [ASSUMPTION]
- **W4. Anthropic, "Harness design for long-running application development"** (Prithvi Rajasekaran, 2026-03-24). [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
  - A planner, a generator and an evaluator that uses Playwright MCP. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
  - A solo run took 20 minutes and cost $9. The full harness took 6 hours and cost $200. A later version on Opus 4.6 took 3 hours 50 minutes and cost $124.70. There are two applications in total. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]

## What recurs across the sample

[ASSUMPTION: my classification of the 15 entries and 4 write-ups above]

| Mechanism | Open-source entries using it | Companies |
|---|---|---|
| PreToolUse blocking (a hard gate before an action) | 10 of 15, mostly for safety: destructive commands, secrets, protected branches | Companies sandbox the agent instead: containers, devboxes, per-worktree environments |
| Deterministic feedback after each edit (lint, types, tests, patterns) | 5 of 15 | Stripe's fast local lint; Spotify's verify tool |
| A Stop hook as the "definition of done" | 5 of 15 | Spotify runs all verifiers in a Stop hook |
| A separate-context model reviewer or judge | 9 of 15 | Spotify's scope judge; Anthropic's evaluator |
| A CI or pull-request gate | 3 of 15 | Mandatory at all three companies, with human review |

**Observations** [ASSUMPTION]:
1. Open-source kits mostly block for safety, not correctness. Correctness checks are mostly feedback or model verdicts. [ASSUMPTION]
2. The companies run deterministic verifiers themselves, cap the number of iterations, and keep humans on pull requests. [ASSUMPTION]
3. Java support is thin. The only Java-specific enforcement found is Spotify's Maven verifier, which is a write-up only. NOT FOUND: any open-source Claude Code harness in this sample with blocking hooks specific to Maven or Gradle.

## Rejected candidates, and why

The facts below were read by a sub-agent; each rejection is my judgement.
- **buildermethods/agent-os:** prompt-level only; no hooks, CI or tests. [VERIFIED as read by a sub-agent | github.com/buildermethods/agent-os | observed 2026-09-26]
- **wshobson/agents:** about 39.9k stars, but mostly prompt definitions. Its `plugin-eval` framework is worth reading. [VERIFIED as read by a sub-agent | github.com/wshobson/agents | observed 2026-09-26]
- **SuperClaude_Framework:** no deterministic checks, and speed claims without published benchmarks. [VERIFIED as read by a sub-agent | github.com/SuperClaude-Org/SuperClaude_Framework | observed 2026-09-26]
- **parcadei/Continuous-Claude-v3:** its hooks serve context continuity, not correctness; it has been stale since January 2026. [VERIFIED as read by a sub-agent | github.com/parcadei/Continuous-Claude-v3 | observed 2026-09-26]
- **humanlayer/humanlayer:** deprecated, per its README. Its `create_plan` command, which splits success criteria into automated and manual checks, is still worth reading. [VERIFIED as read by a sub-agent | github.com/humanlayer/humanlayer | observed 2026-09-26]
- **steveyegge/beads:** a task-state and memory layer, not a gate. [VERIFIED as read by a sub-agent | github.com/steveyegge/beads | observed 2026-09-26]
- **davila7/claude-code-templates:** a catalogue with no harness-level design. [VERIFIED as read by a sub-agent | github.com/davila7/claude-code-templates | observed 2026-09-26]
- **anthropics/claude-code-action:** a building block, not a harness (see 05). [VERIFIED | github.com/anthropics/claude-code-action | observed 2026-09-26]
- **Small harnesses listed in awesome-harness-engineering:** no evidence of adoption was found. [VERIFIED as read by a sub-agent | github.com/walkinglabs/awesome-harness-engineering | observed 2026-09-26]
- **harness.io:** a company whose name collides with the topic; excluded without research. [ASSUMPTION]

## Negative results

- **A controlled with-and-without evaluation of any harness:** NOT FOUND.
- **The Stripe article bodies:** could not be read, because they render in the browser. Their details are [PARTIAL | blog.bytebytego.com/p/how-stripes-minions-ship-1300-prs | 2026-03-16].
- **GitHub commit-history pages:** blocked for the sub-agent's fetch tool. Last-push dates come from a public relay of the GitHub API (ungh.cc). [PARTIAL | ungh.cc | observed 2026-09-26]
- **Licence files for Trail of Bits' config and disler's hooks-mastery:** NOT FOUND.
- **Published evaluation scores for superpowers:** NOT FOUND.
