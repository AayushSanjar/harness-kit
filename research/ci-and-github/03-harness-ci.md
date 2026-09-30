# 03 — How AI-coding harness projects use CI and GitHub (question C)

Written on Wednesday 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **Harness.** A project that wraps an AI coding assistant with rules, hooks, skills or checks so that its output is safer and more consistent. harness-kit is one; so are most repositories in the sample below.
- **CI (continuous integration)** means checks that GitHub runs automatically when code is pushed or proposed. A **workflow** is one recipe file for it in `.github/workflows`.
- **Pull request** means a proposal to merge one branch into another. A **required check** is a named check that must pass before GitHub accepts the merge. A **merge queue** is a GitHub service that tests each pull request on top of the newest `main` before merging; its workflow trigger is called `merge_group`.
- **Path filter** means `paths:` or `paths-ignore:` in a workflow trigger, which makes the workflow run only when certain files change.
- **Hook.** A script that Claude Code (or git) runs automatically at a defined moment, for example before a command or before a push.
- **Advisory** means a check whose result is shown but does not stop a merge. **Blocking** means it does stop it.
- **`claude -p`** means running Claude Code once without a screen, from a script. **`--bare`** is its option that skips project hooks, skills, plugins and MCP servers.
- **Fault replay** means harness-kit's checking of a fixed list of 137 planted breaks (defined in file 02).

## How this file is based on evidence

This file draws on 51 sources: 48 primary (repository files, workflow files, Anthropic's own documentation and posts, OpenAI's and Spotify's own posts) and 3 secondary (two third-party summaries of Stripe's system, from VirtusLab and ByteByteGo, and one list of search results). The research thread behind this file read 69 sources in total, and the 51 cited here are those that support a statement in this file. I chose them in this order. First I took the list of harness projects in your earlier file `research/initial-harness/03-reference-harnesses.md` (15 entries covering 18 repositories) and used it only as a list of names. I added `anthropics/claude-code-action` and `anthropics/claude-plugins-community`. Then for every public repository I ran a shallow clone, listed `.github/workflows`, and read every workflow file in full, together with any contributing guide, pull request template, hook configuration and release script. Then I read Anthropic's documentation and posts, and the OpenAI, Spotify, Stripe, Fowler and GitHub blog pieces.

The sample is **19 repositories** (15 have workflows, 4 have none), plus 7 company or author write-ups. It is small, not random, and hand-picked from your list plus two additions. All 19 are public, so nothing here shows what a private repository on a personal account can do. Percentages describe the sample, not the market.

How pages were read. Files inside clones were read in full. Web pages were read through a fetch tool that returns a summary by a small model, so each is an extract; where a quotation mattered, my agent fetched again asking for the exact words. Star counts (read on 2026-09-30 from each repository page) are extracts and are shown only to say how popular a project is, never as evidence of quality. GitHub's programming interface answered "403 forbidden" and I did not route around it, so required-check settings, which live on GitHub and not in files, could mostly not be read. The full notes are in `evidence/C-harness-ci.md`.

Labels: **[VERIFIED]** means a primary source says it. **[PARTIAL]** means secondary, extract-only, or partly supported. **[ASSUMPTION]** means my reasoning. **NOT FOUND** means I searched and found nothing.

## CONTRADICTIONS

1. **"Custom release and merge scripts are safer than pull requests" has no support, and one project states the opposite as a rule.** [VERIFIED for the sample] Of the 19 repositories and 7 write-ups, none lands feature work by a local script in place of a pull request (NOT FOUND). compound-engineering's `AGENTS.md` says: "Direct pushes and direct merges to `main` are not allowed; branch protection on `main` enforces this by requiring the `test` status check to pass. The direct path bypasses `release:validate`, the test suite, and PR title validation — past direct merges have caused version drift requiring multi-PR recovery." The nearest cases to a script are release steps only, and each one adds a CI check around the script: claude-code-action (a bot creates the tag after CI passes), cc-safety-net (a workflow started by hand pushes the release commit to `main` from CI), and everything-claude-code (a hand-run `scripts/release.sh`, after which a CI job refuses to publish unless the tag is signed, the commit equals `origin/main` and CI passed on that exact commit). The strongest evidence on your side is superpowers (292,100 stars), which has no workflows at all and releases with a hand `scripts/bump-version.sh`; but that shows "no gate", not "a script is a stronger gate".
2. **No harness project replays faults or runs mutation testing in CI, so "faults must be replayed after merge" has no precedent in either direction.** [NOT FOUND] Searching the 20 clones for "mutation", "mutant", "fault" and "replay" found only skill text, an instruction in `trailofbits/claude-code-config` telling the agent to use `cargo-mutants` or `mutmut`, and superpowers' planted-defect probes, which test reviewer skills and now live in a separate repository. What the sample does show is that projects with expensive checks make the pull-request check cheap and push heavy sweeps to a schedule (section 4). Martin Fowler's site puts expensive checks "post-integration in the pipeline" and "continuous drift sensors" outside the change lifecycle. [PARTIAL | Böckeler on martinfowler.com, 2026-04-02, extract] That is mild support for "slow things after merge or on a schedule", but for checks that are advisory. Your rule that every gate stays as strong is not a goal any sampled project states.
3. **Your earlier file `03-reference-harnesses.md` understates CI use and has three errors that the files themselves contradict.** [VERIFIED from clones] It says a CI or pull-request gate exists in "3 of 15". Reading the workflow directories, 15 of the 19 repositories have workflows and about 12 run pull-request tests or validation on their own product. It says compound-engineering has "No hooks or CI were found"; the repository has `ci.yml` (title lint, `release:validate`, `claude plugin validate --strict`, tests, Windows and macOS jobs), a release-please workflow and a stated required check. It says ChrisWiles has "four scheduled GitHub Actions workflows"; only three have a `schedule` trigger, and the fourth runs on pull requests and `@claude` comments. The likely cause is method (working from README pages instead of workflow files). I did not recheck that file's other content.
4. **OpenAI's published position relaxes blocking gates, in tension with "every gate must block".** "The repository operates with minimal blocking merge gates. Pull requests are short-lived." and "Test flakes are often addressed with follow-up runs rather than blocking progress indefinitely." [VERIFIED as statements | openai.com/index/harness-engineering, 2026-02-11, extract refetched for exact words] That is a large team whose agents produce far more than humans can read, a different risk regime; I do not think it transfers to a rule of "quality must not drop". [ASSUMPTION] I list it so it does not surprise you.
5. **`claude -p` in CI runs your own hooks unless you pass `--bare`.** [VERIFIED | Claude Code documentation, extract, 2026-09-30] Without `--bare`, `claude -p` still runs project hooks and `.mcp.json` servers even in a folder that was never trusted. `--bare` "is the recommended mode for scripted and SDK calls, and will become the default for -p in a future release". So any CI job that runs `claude -p` on your repository runs harness-kit's Stop gate and other hooks in the checkout unless told not to. Whether harness-kit's own tests rely on that behaviour: NOT FOUND (I did not read the tests for it).
6. **Path filters and required checks collide, and three independent projects document the same trap.** [VERIFIED | comments in spec-kit's `extension-version-guard.yml`, claude-plugins-official's `validate-plugins.yml` and `scan-plugins.yml`, and claude-plugins-community] A workflow skipped by a path filter never reports, so a required check "stays in 'Expected' state and blocks every PR". Their workaround is to run the workflow always and skip at step level. This matches file 01, contradiction 6.

## 1. The sample (all facts from files read in full, except stars)

`PR` means the `pull_request` trigger, `push` a push to `main`, `cron` a schedule, `disp` a manual start. No repository contains a `merge_group` trigger.

| Repository (stars) | CI? | What CI runs | Required checks visible in files | Release mechanism |
|---|---|---|---|---|
| anthropics/claude-code (148.5k) | Yes (14 workflows) | Mostly issue triage and lifecycle done by Claude through `claude-code-action@v1`; one narrow test for `mods/**`. Product source is not public | NOT FOUND | 234 tags, mechanism not visible |
| anthropics/claude-code-action (8.9k) | Yes (14) | Tests, format, typecheck; orchestrator that makes real Claude calls with pinned models; Claude review; a check that every workflow calling Claude uses the firewall runner | NOT FOUND | A bot creates the tag after the "CI All" workflow succeeds on `main`; 304 tags |
| anthropics/claude-code-security-review (6.3k) | Yes (2) | Its own scanner run on itself, plus unit tests | NOT FOUND | None |
| anthropics/claude-plugins-official (37.1k) | Yes (9) | `claude plugin validate`, frontmatter, licence and link checks, an LLM policy scan run as `claude -p --bare --allowed-tools "Read,Glob,Grep" --json-schema`, a scope guard, a nightly bot that bumps plugin versions (max 60, commented "cost control") | Comments say `validate`, `scan` and `check` are required, plus an organisation ruleset requiring signatures | None (a catalogue) |
| anthropics/claude-quickstarts (17.8k) | Yes (3) | Lint, type check, tests and a Docker smoke test for one demo only | NOT FOUND | None |
| obra/superpowers (292.1k) | **No** | None; pull requests "MUST target the `dev` branch, not `main`" | n/a | Hand `bump-version.sh` |
| affaan-m/everything-claude-code (270k) | Yes (12) | Large matrix (3 systems, 3 Node versions, several package managers), packaged-install test, validation, lint, audit | NOT FOUND (an outside AI review service is configured) | Hand `release.sh`; then CI verifies signed tag, commit equals `origin/main`, exact-commit CI green, and publishes with provenance |
| EveryInc/compound-engineering-plugin (25.3k) | Yes (4) | Title lint, `release:validate`, pinned and cached `claude plugin validate --strict`, tests, Windows and macOS jobs, job timeouts | **Stated in `AGENTS.md`:** branch protection requires the `test` check | release-please opens a release pull request |
| snarktank/ralph (20.8k) | Pages deploy only | None for tests | NOT FOUND | None |
| github/spec-kit (139.0k) | Yes (18) | Lint, tests on 3 systems and 2 Python versions, weekly audit, CodeQL, agentic workflows that open draft pull requests with a credit cap | **Stated in a comment** (the Expected-state trap) | Manually started workflow creates branch, tag and pull request |
| nizos/tdd-guard (2.3k) | Yes (2) | Format, lint, type check, tests, an `All Checks Pass` aggregator job, concurrency cancel, npm cache, weekly security run | NOT FOUND | Mechanism NOT FOUND |
| nizos/probity (207) | Yes (3) | Matrix plus aggregator, security run, canary publish behind an approval environment | NOT FOUND | Canary from `main` |
| trailofbits/skills (6.9k) | Yes (3) | Validator with self-test, version-increment check, loadability with `claude`, pre-commit in CI, Claude review that skips drafts, bots and forks | **Stated in a comment:** "this is a required check" | None |
| trailofbits/claude-code-config (2.1k) | **No** | None | n/a | None |
| kenryu42/cc-safety-net (1.6k) | Yes (7) | Full check on 3 systems, randomised end-to-end re-run three times, build output must equal committed output, packed-runtime matrix, workflow linting, concurrency cancel | NOT FOUND | Hand-started workflow "transaction" pushes the release commit with `--expected-base`, has a dry run, then dispatches a publish |
| carlrannaberg/claudekit (760) | Yes (3), **weak** | Tests run with `continue-on-error: true` and shellcheck with `\|\| true`, so neither can fail the build | NOT FOUND | A bot tags when the version has no tag |
| ChrisWiles/claude-code-showcase (6k) | Yes (4), no test CI | Claude review with `--max-turns 10`, scheduled audits and docs sync | NOT FOUND | None |
| diet103/claude-code-infrastructure-showcase (10.0k) | **No** | None | n/a | None |
| disler/claude-code-hooks-mastery (3.9k) | **No** | None | n/a | None |

**Counts from the table (n = 19).** Has workflows: 15. Runs pull-request tests or validation on its own product: about 12. Runs an AI review or AI policy scan in CI: 5 (claude-code-action, trailofbits/skills, ChrisWiles, security-review on itself, plugins-official scan), and 2 more configure an outside AI review service. Uses a `merge_group` trigger: 0 of 20 clones. Cancels superseded runs: 7. Caches dependencies or tools: 8. Uses path filters: 7. Required checks visible in files: 5 (by comment or rule), otherwise NOT FOUND, which is not proof of absence because those settings live on GitHub. [VERIFIED by search of the files]

## 2. Findings

**Pull requests are the merge point, and hooks sit beside CI, not instead of it.** [VERIFIED for the sample] Hooks appear in tdd-guard and probity (Husky), cc-safety-net (lefthook, including a pre-push `check`), claude-code-action (`scripts/pre-commit`), and trailofbits/skills (a pre-commit file also run in CI by `pre-commit/action`). Anthropic's own documentation assumes a pull request too: the GitHub Actions integration, `/code-review` and managed Code Review all attach to one. [VERIFIED | extracts]

**What runs where.** Fast format, lint, type and commit-message checks run locally; the full suite, operating-system matrices, packaged-install tests, scans and release verification run in CI. Several projects run the same command in both places: everything-claude-code ("Run `npm test` locally. It is the same gauntlet CI runs"), trailofbits/skills (one pre-commit file for both), and cc-safety-net (`check`). compound-engineering goes furthest: "Do not invent a parallel local-only mechanical suite" (`AGENTS.md`, read in full). Your design already runs the same `check.sh` locally and in CI, so it is on the common side of this practice. [VERIFIED for the sample; ASSUMPTION for the comparison]

**AI review is advisory everywhere it was observed.** [VERIFIED] Managed Code Review's check run is "always neutral" and never blocks a merge (Anthropic documentation, extract). claude-code-action cannot approve a pull request. claude-code-security-review turns a non-zero exit into a warning and reports zero findings on errors, that is, it fails open, and its README says it is "not hardened against prompt injection". The one AI step that is a required check is plugins-official `scan`, and its result is a structured JSON verdict, not free text. So deterministic checks are the gate; AI checks either advise or are forced into machine-checkable output.

**Star count says nothing about gate strength.** claudekit's unit tests cannot fail its build (`continue-on-error: true`), and superpowers, the most-starred project, has no CI at all. [VERIFIED]

**Company write-ups (all extracts).**

- Spotify (part 3, 2025-12-09): verifiers run before a pull request is opened: "If one of the verifiers fails, the PR isn't opened". [VERIFIED] Its CI rounds: NOT FOUND.
- Stripe: "At most two rounds of CI. If the code doesn't pass after the second push, the branch goes back to the human engineer." and CI "selectively runs tests from Stripe's battery of over three million tests". [PARTIAL: secondary only, ByteByteGo 2026-03-16 and a VirtusLab page; both primary Stripe pages returned no readable body]
- Anthropic's C compiler post: "I built a continuous integration pipeline and implemented stricter enforcement that allowed Claude to better test its work so that new commits can't break existing code." Its `--fast` option runs a 1% or 10% sample of tests for quick feedback. [VERIFIED | extract, exact words refetched]
- Anthropic's evals post (2026-01-09): automated evals are useful "in CI/CD, running on each agent change and model upgrade as the first line of defense". [VERIFIED]
- Anthropic's secure-development post (2026-07-21): "When a PR is opened at Anthropic, multiple agents automatically review it." and "We tier our codebase by risk, and make deliberate decisions on what parts to automate." [VERIFIED | extract]
- GitHub blog (2026-05-07): "Any change that weakens CI is a blocker. Full stop." and "Require a new test that fails on the pre-change behavior." [VERIFIED | extract] The second sentence is close to what your fault replay proves, at the level of one change.
- OpenAI, see contradiction 4. Its recurring background agents that scan for drift match your weekly scheduled run; the sample's analogues are ChrisWiles (weekly review), plugins-official (nightly version bump), spec-kit and tdd-guard (weekly audit).
- Anthropic's "effective harnesses" and "harness design" posts mention git only. Hashimoto's post does not mention CI. [VERIFIED as absence in the extracts]

## 3. Claude Code's own tools that matter to you

- **`claude plugin validate [--strict]`**, with exit codes 0, 1 and 2, is used in CI by compound-engineering and plugins-official. harness-kit already runs it. [VERIFIED]
- **`claude plugin eval`** runs each test case three times, with and without the plugin as a baseline, and has `--threshold`, `--max-cost-usd`, a "Run evals in CI" section, and the advice "give quick every-change suites only graders that don't call a judge". No sampled workflow uses it (0 hits in 20 clones). [VERIFIED for the documentation; NOT FOUND in use]
- **Cost flags.** `--max-turns` is used by ChrisWiles and recommended by the documentation; `--max-budget-usd` (print mode only) is documented and used by no sampled workflow; plugins-community wraps its scan in the shell `timeout`. Anthropic's GitHub Actions page says runs consume Actions minutes plus tokens and recommends `--max-turns`, workflow timeouts and concurrency controls. [VERIFIED]
- **Managed Code Review** is a research preview for Team and Enterprise plans, "average $15-25 per review", never blocking, and not available with zero data retention. [VERIFIED | extract] That a personal account cannot use it is [ASSUMPTION] from the plan wording. `/code-review` and `/security-review` are local, on-demand commands and cost only tokens. [VERIFIED | extract]
- **Security design worth copying if you ever add an AI step.** claude-code-action lets only users with write access trigger it, restores `.claude/`, `.mcp.json`, `CLAUDE.md` and `.husky/` from the base branch on pull requests so a pull request cannot rewrite its own reviewer's rules, and runs on a firewalled runner. [VERIFIED | README and workflows, cloned]

## 4. Cost control seen in the sample

All sampled repositories are public, so minutes were not their cost; these are techniques, not private-repository evidence. [VERIFIED from files unless marked]

1. Run an AI review once per pull request (`types: [opened]` in claude-code-action), not on every push.
2. Cache an expensive verdict by content (plugins-official caches its scan by plugin, commit and policy hash for 30 days).
3. Skip inside the job rather than with a path filter, when the check is required.
4. `paths-ignore` for documentation-only changes (cc-safety-net) and `paths` for narrow areas.
5. Cancel superseded runs with `concurrency` (7 repositories).
6. Cache dependencies and pin tool versions (8 repositories cache; compound-engineering pins and caches the Claude command; trailofbits leaves it unpinned on purpose to catch breakage).
7. Skip drafts, bots and forks for AI review.
8. Hard caps: `--max-turns`, job timeouts, a maximum of 60 bumps, `max-ai-credits`, and a job that does nothing when a secret is absent.
9. Put heavy sweeps on a weekly or nightly schedule instead of every push (tdd-guard, probity, spec-kit, plugins-official, ChrisWiles).
10. One aggregator job ("All Checks Pass") so branch protection names one stable check. [ASSUMPTION about the purpose; the files do not state it]

Private-repository minute handling: NOT FOUND in the sample.

## 5. Release mechanisms seen

A bot opens a release pull request that a human merges (compound-engineering). A bot tags after CI passes on a version-bump commit (claude-code-action, claudekit). A workflow started by hand checks, prepares and pushes the release commit from CI, then starts a publish workflow, with `--expected-base` (refuse if `main` moved) and a dry-run mode (cc-safety-net). A hand script plus CI gates that refuse to publish unless the tag is signed, the commit equals `origin/main` and CI passed on that exact commit (everything-claude-code). A workflow creates branch, tag and pull request (spec-kit). A canary package behind an approval environment (probity). A hand script with a `dev` branch (superpowers). [VERIFIED from files] The closest match to your `release.sh` is everything-claude-code, and it **keeps the script and moves the last check into CI, on the exact commit**. That is the shape file 06 recommends for harness-kit's release.

## Negative results

- Mutation testing or fault replay in a harness project's CI: NOT FOUND (20 clones searched).
- Merging feature work by a local script in place of a pull request: NOT FOUND in 19 repositories and 7 write-ups.
- A `merge_group` trigger: NOT FOUND in any of 20 clones.
- `claude plugin eval` and `--max-budget-usd` in any sampled workflow: NOT FOUND.
- Private-repository CI cost handling: NOT FOUND (all sampled repositories are public).
- Stripe's "two rounds of CI" from a primary page: NOT FOUND (both stripe.dev pages unreadable through the fetch tool); Spotify's number of CI rounds: NOT FOUND.
- A Thoughtworks Technology Radar entry on CI for coding agents: NOT FOUND (the search returned generic radar pages).
- Required-check and branch-protection settings for most repositories: NOT FOUND (they live on GitHub and the programming interface returned 403; only comments in files give evidence).
- The release mechanism of tdd-guard: NOT FOUND in files (80 tags but no tag workflow).
- How Anthropic gates its own CLI: NOT FOUND (the source is not public, and the claude-code repository has no product build or test workflow).
- The OpenAI article's extract contains none of "mutation", "fault injection", "required checks" or "branch protection". [VERIFIED for the extract only]

## Strongest counter-cases

- **Against "pull requests and CI on pull requests are the norm".** The most-starred project has no workflows, and three other well-known harness repositories are CI-free. Much of the sample is prompts and skills, with little to test, unlike your roughly 8,700 lines of scripts and 8,100 lines of tests. [figures from your earlier research, not rechecked] A solo developer also gets no second human reviewer from a pull request; the value is a stable place for required checks, CI history and optional AI review. [ASSUMPTION]
- **Against "do not merge by script".** Absence in a public, mostly team sample is weak evidence about a solo private project. Scripted steps do exist (cc-safety-net pushes a release commit from a CI-run workflow; everything-claude-code releases from a hand script), wrapped by CI verification. A script that verifies what a required check would verify is not weaker in principle. It is weaker because nothing outside your machine enforces it. [ASSUMPTION]
- **Against "no harness replays faults, so there is no precedent".** That is what makes harness-kit unusual, and unusual can mean pioneering or over-built. The GitHub blog line "Require a new test that fails on the pre-change behavior" supports per-change proof of test strength, and Fowler's site supports moving expensive checks off the fast path. Both are opinion pieces, not measurements.
- **Against "AI review is advisory; deterministic checks are the gate".** plugins-official makes an AI scan a required check (structured output, cached), and OpenAI reports mostly agent-to-agent review with minimal blocking. So an AI step can be a hard gate when its output is machine-checkable, and the direction of travel at some large teams is fewer blocking gates.
- **Against "run once, cache by content, skip at step level, schedule heavy sweeps".** None of it was shown on a private repository with metered minutes. Managed Code Review costs about $15 to $25 per review and is for Team and Enterprise only.
- **Against "hooks complement CI".** cc-safety-net runs the full `check` at pre-push and everything-claude-code says to run "the same gauntlet CI runs" locally, so for a solo developer the local run is effectively the main gate and CI a confirmation. compound-engineering takes the opposite view, so the sample disagrees with itself.
- **Against the whole sample.** Public, popular, English-language, GitHub-heavy, hand-picked, n = 19 plus 7 write-ups. Company write-ups describe fleets of agents, a different risk regime from one person and one private app.
