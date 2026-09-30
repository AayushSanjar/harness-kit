# 04 — Free components you could reuse instead of custom code (question D)

Written on Wednesday 30 September 2026. Research only: no repository was changed, and nothing was installed.

## Terms used in this file

- **Component.** A tool, GitHub feature or Claude Code feature that does part of what a harness-kit script does by hand.
- **Free.** Usable at no charge by one person with one public repository (harness-kit) and one private repository (control-chart-gadget), both on a personal GitHub account. "Excluded, paid" means it costs money or is unavailable to these two repositories.
- **Licence.** MIT and Apache-2.0 are permissive open-source licences (free to use and change). GPL and AGPL are "copyleft" licences: free to run, but changes you distribute must be shared. A **custom EULA** (end-user licence agreement) is a company's own contract, not open source.
- **Stars.** GitHub bookmarks. They measure popularity, not quality, and stars can be bought, so I do not rank by them.
- **Tag commit date.** The date of the commit that a release tag points to. I use it as the release date when the release page prints no year.
- **Pin by commit SHA.** Naming an action by the long fingerprint of one exact commit instead of a movable version label such as `v4`, so that nobody can swap its contents later.
- **SARIF.** A file format for security scan results that GitHub can display in its Security tab. **Annotations** are simpler warnings shown on the workflow run.
- **Required check, ruleset, merge queue, aggregator (gate) job, fast-forward.** As defined in file 01.
- **Hook, `claude -p`, `--bare`, fault replay.** As defined in files 02 and 03.
- **Deny rule.** A line in Claude Code's settings that forbids any tool call matching a pattern.
- **Sandbox.** Claude Code's operating-system-level restriction on what shell commands may touch.
- **Piece.** One of harness-kit's hand-built parts, named by its file (for example `git-guard.mjs`).

## How this file is based on evidence

This file draws on 316 sources: 299 primary (each tool's own repository, releases page and documentation; GitHub's, Playwright's, Anthropic's and GNU's own documentation; vendor price pages; one GitHub security advisory; and the harness-kit clone itself) and 17 secondary (search-result lists and two mirror pages of issues in other people's repositories). I chose them by starting from the 14 areas of your CI and release process and the 9 hand-built parts of harness-kit, then picking, for each, the tools a solo maintainer would plausibly use. For each area I read the tool's own repository, releases page and documentation before anything else, and I did a shallow clone of about 40 public repositories to read their last-commit and tag dates. I preferred official documentation over blog posts and opened no blog post.

How pages were read. Every web page was read through a fetch tool that returns a summary written by a small model, so each counts as an **extract**, not a full read. A few files inside clones were read in full: Kodiak's quickstart, several harness-kit scripts and hook files, the official plugin marketplace file, and the tool documentation folders in clones. Star counts are the rounded figures GitHub prints ("4.2k"); exact counts are NOT FOUND because GitHub's programming interface returned "403 forbidden" and I did not route around it. The summarising tool made mistakes that I caught (stale newest-release numbers for pinact and Renovate, an invented year for zizmor, "MIT" and "complete source code" for the Claude Code repository whose licence file says "All rights reserved", and a wrong year for trufflehog); so I re-checked every version and year against git tags, and the dates below are tag commit dates unless said otherwise. The complete notes are in `evidence/D1-ci-components.md`, `evidence/D2-ai-and-mutation-components.md` and `evidence/A3-release-automation.md`.

Labels: **[VERIFIED]** means a primary source says it. **[PARTIAL]** means secondary, extract-only, or partly supported. **[ASSUMPTION]** means my reasoning. **NOT FOUND** means I searched and found nothing.

The column "Use?" is my own judgement, so every entry in it is [ASSUMPTION]. It has four values: **Adopt** (use it, low risk), **Consider** (worth it if a measurement or a decision in file 06 supports it), **Skip** (does not fit or costs more than it saves), **Excluded** (paid, unavailable to these repositories, or abandoned).

## CONTRADICTIONS

1. **Branch protection, rulesets and auto-merge are free for harness-kit and not for control-chart-gadget.** [VERIFIED | docs.github.com, accessed 2026-09-30] "Protected branches are available in public repositories with GitHub Free and GitHub Free for organizations. Protected branches are also available in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server." Rulesets and auto-merge carry the same wording. So the "free for private repositories" belief is false. The monthly price of GitHub Pro: NOT FOUND (GitHub's price page lists Free at $0, Team at "$4 USD per user/month for the first 12 months" and Enterprise at "$21"; the plans page names Pro without a price). Whether your account is already on Pro: NOT FOUND.
2. **A merge queue is unavailable to both repositories.** "Pull request merge queues are available in any public repository owned by an organization, or in private repositories owned by organizations using GitHub Enterprise Cloud." [VERIFIED | docs.github.com, re-read by me] The only queue you could use without changing the account type is Mergify's, a third-party app (free for up to 5 users on private repositories, and every plan includes its queue [VERIFIED | mergify.com/pricing, extract]), which needs a pull request and write access to the repository.
3. **"Custom scripts are safer" is TRUE in one place, and it is the place where the evidence supports your belief.** Anthropic's own table says a deny rule `Bash(git push *)` stops `git push origin main` but does not stop `git -C . push origin main`, `git -c push.default=current push origin main` or `git 'push' origin main`, and that a deny rule "isn't a security boundary around the program". [VERIFIED | code.claude.com/docs/en/permissions, "What a Bash rule doesn't match"] `git-guard.mjs` is written to handle those forms (`git -C`, `bash -c`, `eval`, tracking `cd`) [VERIFIED | its own source], and no native rule can carve a scratch-copy exception out of a deny ("An allow rule can't carve an exception out of a deny rule"). So for git-guard, the native feature is a second layer, not a replacement. This is the opposite of contradiction 4 in file 01, and I report both.
4. **Every automatic AI review product works only on pull requests.** Anthropic's managed Code Review, `claude-code-action`, the `code-review` plugin, `claude-code-security-review` and Copilot code review all need one. [VERIFIED | Anthropic and GitHub documentation] Anthropic's managed review also always ends with a "neutral" result, "so it never blocks merging through branch protection rules". So none of them can be a blocking gate by itself, and none can serve a fast-forward-by-script flow. Your local `review.sh` is the only kind that fits that flow.
5. **Caching the Playwright browser is advised against by Playwright itself** (file 01, contradiction 7). [VERIFIED | playwright.dev/docs/ci]
6. **`gitleaks-action` is no longer open source.** From v2.0.0 it is under a custom licence agreement with Gitleaks LLC. Repositories in an organisation account need a licence key (described as free); "if you are scanning repos that belong to a personal account, then no license key is required". [VERIFIED | LICENSE.txt and README, read in full] Both your repositories are personal, so no key is needed today; moving either into an organisation would need one. The gitleaks command-line tool is a separate MIT project with no key.
7. **GitHub's own secret scanning is not available to the private repository.** Push protection and secret scanning on private repositories need "GitHub Secret Protection" ($19 per active committer per month), which the pricing page says is for Team and Enterprise organisations and "not available for personal accounts". [PARTIAL | extracts of docs.github.com and github.com/security/plans] They are on automatically for public repositories, so harness-kit already has them if they are enabled (not checked). For control-chart-gadget the free options are gitleaks, trufflehog, detect-secrets or your own `guard-secrets.mjs`.
8. **A one-line replacement for `plan-mode-guard.mjs` probably exists but is untested.** Anthropic's tools reference lists `EnterPlanMode` as needing no permission, and its permissions page says a bare tool name in a deny rule "removes the tool from Claude's context entirely". So `"deny": ["EnterPlanMode"]` in project settings very probably does what the 36-line script does. [PARTIAL | documentation only; my `claude doctor` run printed no warning but no validation result either, so it is not a test] A plugin cannot ship permission rules, so it would have to live in every project's `.claude/settings.json`.
9. **The current Anthropic workflow example uses `actions/checkout@v6`, and the newest major I found is v7.0.1**, while `validate.yml` uses v4 (Node 20, removed from runners on 23 September 2026; see file 01, contradiction 5). [VERIFIED | code.claude.com/docs/en/github-actions and the checkout releases page]

## 1. GitHub's own features

| Name | What it does | Could replace or simplify | Licence, release, stars | Free for harness-kit / gadget | Catch | Use? |
|---|---|---|---|---|---|---|
| Branch protection and rulesets (required checks) | Server-side rules: `main` cannot change unless named checks pass | Merge step of `ship.sh`; the local pre-push hook in `install-hooks.sh` | GitHub feature | Yes / **No, needs Pro or higher** | A workflow skipped by a path filter leaves its required check Pending and blocks the merge; a solo owner may bypass (default bypass list NOT FOUND) | Adopt for harness-kit; Consider for gadget (a purchase) |
| Auto-merge (`gh pr merge --auto`) | Merges a pull request when required checks pass | Waiting at the terminal for CI | GitHub feature | Yes / **No** | Needs a pull request and required checks; cannot push a tag and `main` together (ASSUMPTION) | Consider |
| Merge queue | Tests each pull request on the newest `main`, one after another | Duplicate run on `main` | GitHub feature | **No / No** (organisation or Enterprise Cloud only) | Unavailable | Excluded |
| Required workflows via rulesets | An organisation rule that a named workflow must pass on many repositories | Skip-CI logic | GitHub feature, blog says Enterprise Cloud | No / No | Personal-account availability NOT FOUND | Excluded |
| `gh run watch`, `gh pr checks --watch` | Wait for a run or a pull request's checks; `--exit-status` fails when it fails | Waiting on CI | GitHub CLI 2.98.0 is preinstalled on the runner image (image 20260823) | Yes / Yes | harness-kit already uses `gh run watch` inside `time-limit.mjs`'s CI wait; what is custom is the retry and fail-closed logic around it | Adopt (already used) |
| Actions `timeout-minutes` | GitHub cancels a job or step after N minutes | The CI side of `time-limit.mjs` | GitHub feature | Yes / Yes | CI only, not on your Mac; the default is 360 minutes according to one extract, and a second extract did not state it [PARTIAL] | Adopt |
| `concurrency` with `cancel-in-progress` | Cancels an outdated run when a newer one starts | Nothing today | GitHub feature | Yes / Yes (saves minutes) | Exclude `main` and tags from cancelling | Adopt |
| Dependabot version updates for Actions | Opens pull requests that raise action versions | Manual action upgrades (`pinact`, Renovate) | GitHub feature | Yes / Yes ("No specific plan restrictions" stated) | Opens pull requests, so it fits a pull-request flow better than fast-forward; behaviour with SHA-pinned actions: NOT FOUND | Consider |
| GitHub secret scanning and push protection | Blocks a push containing a known token format | The CI `--scan` of `guard-secrets.mjs` | GitHub feature | Yes automatically / **No** | Write-access users can bypass with a reason | Adopt (harness-kit, check it is on) |

## 2. Merging, releasing and tagging

| Name | What it does | Could replace or simplify | Licence, release, stars | Free for harness-kit / gadget | Catch | Use? |
|---|---|---|---|---|---|---|
| Mergify (app) | Merge queue with batching; conditions on files and checks | Merge step; duplicate `main` run (gadget only) | Service proprietary (engine source NOT FOUND); its CLI is Apache-2.0, tag 2026.9.16.1, 29 stars | Yes / Yes up to 5 users | Third-party app with repository write access; needs pull requests; how it treats path-skipped required checks: NOT FOUND | Skip |
| Kodiak (app) | Merges pull requests labelled `automerge` | Merge step | AGPL-3.0; v0.59.1, 2026-03-13; 1.1k stars; last commit 2026-09-08 | Yes / needs a paid plan for the branch protection it depends on | Its own quickstart says to configure branch protection with required checks first | Skip |
| bors-ng | Merge bot | Merge step | Apache-2.0; no releases; last commit 2024-01-31 | n/a | Archived by its owner on 2024-04-04 | Excluded |
| release-please | Opens a release pull request from Conventional Commit messages; tags when it is merged | `release.sh` | Apache-2.0; v17.11.2, 2026-08-24; 7.4k stars; last commit 2026-09-14 | Yes / Yes | harness-kit's commits are not Conventional Commits and its version lives in one file bumped inside each work commit; with the built-in token, its tags and pull requests "will not trigger future GitHub actions workflows", so it needs a personal token or app key | Skip |
| semantic-release | Automated versioning and publishing from commit messages | `release.sh` | MIT; v25.0.9, 2026-08-05; 24.0k stars | Yes / Yes | Same commit-format assumption; aimed at package publishing | Skip |
| changesets | Versions and changelogs driven by small "changeset" files | `release.sh` | MIT; @changesets/cli 3.0.3 (tag commit 2026-09-14); 12.2k stars | Yes / Yes | Aimed at npm monorepos | Skip |
| cocogitto | Conventional Commit checks, version bump, changelog | `release.sh`, commit checks | MIT; 7.0.0, 2026-03-04; 1.2k stars | Yes / Yes | Rust binary; same commit-format mismatch | Skip |
| `claude plugin tag` | Creates an annotated tag `<name>--v<version>` after checking that `plugin.json` and the marketplace entry agree; `--push` optional | The tagging step of `release.sh` | Part of Claude Code | Yes / n/a | Tag name pattern differs from `vX.Y.Z`; the Claude Code version that introduced it: NOT FOUND | Skip |
| `git push --atomic origin main <tag>` | Updates two references in one push | (what `release.sh` already does) | git | Yes / Yes | No free tool replaces it; every pull-request tool merges one branch | Adopt (keep) |

Only the mechanism of release automation is covered here; the ranking of release designs for your two repositories is in file 06. There is no single standard, and the tools that need pull requests do not fit a fast-forward flow. [VERIFIED for the tools' documentation; ASSUMPTION for the fit]

## 3. Running tests faster and splitting them

| Name | What it does | Could replace or simplify | Licence, release, stars | Free for harness-kit / gadget | Catch | Use? |
|---|---|---|---|---|---|---|
| `xargs -P N` | "Run up to max-procs processes at a time" | `tests/validate.sh` running test files one after another | GNU findutils (licence not fetched) | Yes / Yes | Output of parallel children is "produced in an indeterminate order (and very likely mixed up)", so each file's output must go to its own file and be printed in order; test files must be independent | Adopt (after checking independence) |
| GNU parallel | Runs jobs in parallel with grouped output | Same | GPL-3.0-or-later; version 20231122 preinstalled on the runner | Yes on the runner; not on a default Mac | Prints a citation notice on first use | Consider |
| GNU make `-j` | Parallel targets | Same | Not fetched; page returned "429" and robots.txt | n/a | Needs a Makefile of 19 targets; no gain over `xargs` (ASSUMPTION) | Skip |
| bats-core | Bash test framework with `--jobs N` | Same | MIT; v1.14.0, 2026-07-21; 6.3k stars | Yes / Yes | Parallel mode needs GNU parallel or rush; your tests are plain scripts printing PASS lines, so adopting it means rewriting about 8,100 lines | Skip |
| ShellSpec | BDD framework for POSIX shells | Same | MIT; 0.28.1, 2021-01-11; 1.4k stars; last commit 2024-09-12 | Yes / Yes | Unmaintained; same rewrite | Excluded |
| just, Task (go-task) | Command runners | Wrapper only | just: CC0-1.0, 1.58.0, 2026-08-03, 35.3k stars. Task: MIT, v3.53.1, 2026-08-18, 16.0k stars | Yes / Yes | An extra binary on Mac and runner; no parallelism of its own (ASSUMPTION) | Skip |
| Playwright `--shard` | Splits a Playwright suite as `--shard=x/y` and merges reports | Gadget layout probe only | Apache-2.0; v1.63.0, 2026-09-04; 96.9k stars | Yes / Yes | Playwright only; cannot shard harness-kit's bash tests | Skip until the probe is slow |
| Timing-based test splitters | Split by measured duration | Fixed 8-shard matrix | none free and general found | n/a | NOT FOUND for bash or fault lists. One search returned Depot (a CI service, pricing not checked) and Tuist (Swift). Knapsack Pro is $10 per committer per month | Excluded |

Free runner sizes: a standard Linux runner has 4 vCPU and 16 GB on a public repository and 2 vCPU and 8 GB on a private one, so running test files in parallel can speed harness-kit up by at most about 4 times and the gadget by about 2 times, and only if the files are CPU-bound. [VERIFIED for the sizes; ASSUMPTION for the ceiling, because per-file durations are NOT FOUND.] Seventeen of the 20 `tests/*.test.sh` files create private temporary folders with `mktemp`; three do not (`background-guard`, `ci-replay`, `plan-mode-guard`); only `git-guard.test.sh` mentions `$HOME`. Whether any test shares a global resource such as a port or the real user registry: NOT FOUND (all 20 files would need reading). [VERIFIED for the counts]

## 4. Choosing which tests run, and caching

| Name | What it does | Could replace or simplify | Licence, release, stars | Free for harness-kit / gadget | Catch | Use? |
|---|---|---|---|---|---|---|
| `git diff --name-only` | Lists changed files without any third-party action | Changed-file tools | git | Yes / Yes | `replay-faults.sh --plan` already does this; needs `fetch-depth: 0` (already used) | Adopt (already) |
| dorny/paths-filter | Outputs which path groups changed so later jobs can use `if:` | Workflow-level `paths:` | MIT; v4.0.3, 2026-08-05; 3.3k stars | Yes / Yes | A job-level `if:` avoids the stuck Pending trap; third-party action, pin by SHA | Consider |
| tj-actions/changed-files | Lists changed files | Same | MIT; v47.0.6, 2026-04-18; 2.7k stars | Yes / Yes | A tag-rewriting attack (CVE-2025-30066, High, CVSS 8.6, published 2025-03-15) exposed secrets in workflow logs in versions up to 45.0.7; patched in 46.0.1 [VERIFIED | GitHub advisory GHSA-mrrh-fwg8-r2c3] | Skip |
| `actions/cache` | Saves and restores files between runs | Repeated downloads | MIT; v6.1.0, tag commit 2026-06-23; 5.5k stars | Yes / Yes | 10 GB per repository; entries unused for 7 days removed; a run restores only from its own branch, the default branch and a pull request's base, never from sibling branches [VERIFIED | docs.github.com dependency-caching] | Adopt where a measured gain exists |
| `actions/setup-node` with `cache: npm` | Installs Node and caches the npm download cache | Repeated `npm ci` downloads | MIT; v7.0.0, 2026-07-14; 4.9k stars | n/a (harness-kit has no `package.json`) / Yes | Caches the download cache, not `node_modules`; needs a lock file; the gadget has two, so both paths must be listed | Adopt (gadget) |
| `actions/checkout` | Checks out the repository | Version currency | MIT; v7.0.1, 2026-07-20; 8.5k stars | Yes / Yes | See contradiction 9 | Adopt |
| Claude Code install caching | `curl -fsSL https://claude.ai/install.sh \| bash` accepts a version (`... \| bash -s 2.1.89`) or the `stable` channel; native installs update themselves | Repeated installs in CI | Anthropic documentation | Yes / Yes | Install time in CI: NOT FOUND (not timed); an unpinned install cannot be cached safely (ASSUMPTION) | Consider after a measurement |
| Nx | Monorepo tasks with cache and affected-project detection | Test selection, result cache | MIT; 22.7.12 (2026-09-10) shown as latest, newest tag 23.2.1 (not reconciled); 29.3k stars | Free tier "Hobby", 50,000 credits; personal private repositories: NOT FOUND | Needs a project graph; no benefit for single-package repositories (ASSUMPTION) | Skip |
| Turborepo | Caches task outputs by input hash | Build cache | MIT; v2.11.5, 2026-09-28; 31.1k stars | Yes ("free to use on all plans") | Gain limited for one Vite app whose slow step is the browser probe; none for bash | Skip |
| Bazel | Hermetic build and test system | Result cache | Apache-2.0; 9.2.0, 2026-07-13; 25.6k stars | Yes | Very high learning cost; would mean rewriting builds | Skip |
| Gradle build cache, Develocity | Gradle-specific caching | n/a | Mixed; contains a proprietary component | n/a | Neither repository uses Gradle | Excluded |

## 5. Commit messages, secrets and hooks

| Name | What it does | Could replace or simplify | Licence, release, stars | Free for harness-kit / gadget | Catch | Use? |
|---|---|---|---|---|---|---|
| commitlint | Lints commit messages (Conventional Commits by default); custom plugins possible | `check-commits.mjs` (443 lines plus 354 lines of tests) | MIT; v21.2.3, 2026-09-19; 18.7k stars | Yes / Yes | Checks message shape only. `check-commits.mjs` enforces three project-specific rules (protected files named in the body, every number in a body found in the diff or a `Told:` line, no `Decision:` line naming a removed path); no candidate has them built in; whether commitlint's plugin system could host them was not verified | Skip |
| conventional-pre-commit, gitlint, cocogitto | Commit format checks | Same | Apache-2.0 v4.4.0 (2026-02-18); MIT 0.19.1 (2023-03-10, stale); MIT 7.0.0 (2026-03-04) | Yes / Yes | Same mismatch; gitlint is unmaintained | Skip |
| gitleaks (command-line tool) | Scans files and history for secrets; 222 default rules in the clone | The CI `--scan` mode of `guard-secrets.mjs` (391 lines, about 15 shapes) | MIT; v8.30.1, release page 21 March 2026 (tag commit 12 March); 29.4k stars; last commit 2026-07-22 | Yes / Yes | The README says it is "feature complete" and "future releases will be security patches only", with the author moving to another tool; it does not hook Claude's tool calls, so it cannot replace the pre-write block; more rules are not proof of better detection | Consider (CI scan only) |
| gitleaks-action | Runs gitleaks in Actions | Same | Custom EULA; v3.0.0, 2026-05-30; 646 stars | Yes (personal) / Yes (personal) | See contradiction 6 | Skip |
| TruffleHog | Finds and verifies leaked credentials | Same | AGPL-3.0; v3.97.9, 2026-09-24; 27.6k stars | Yes / Yes | Verification contacts credential providers; heavier than needed | Skip |
| detect-secrets | Baseline-based secret detection | Same | Apache-2.0; v1.5.0, 2024-05-06; 4.6k stars | Yes / Yes | Slow release cadence | Skip |
| Agent Guard | Wraps gitleaks for agents | Same | MIT; 17 stars | Yes / Yes | Tiny adoption, quality unverified | Skip |
| lefthook, pre-commit, husky | Git hook managers | `install-hooks.sh` (124 lines) | lefthook MIT v2.1.15 (2026-09-29, 8.8k); pre-commit MIT v4.6.2 (2026-08-10, 15.6k); husky MIT v9.1.7 (2024-11-18, 35.3k) | Yes / Yes | Still need an install command per clone. Husky installs on `npm install`, but harness-kit has no `package.json`, so it fits only the gadget | Skip (gadget: Consider husky) |

## 6. Keeping workflow files healthy

| Name | What it does | Licence, release, stars | Catch | Use? |
|---|---|---|---|---|
| actionlint | Checks workflow syntax, expression types and action inputs; runs shellcheck on `run:` scripts | MIT; v1.7.12, 2026-03-30; 4.2k stars; last commit 2026-04-19 | Single binary; last commit five months old but stable | Adopt |
| zizmor | Security audit of workflow files (injection, unpinned actions, excessive permissions) | MIT; v1.30.1, 2026-09-09; 6.6k stars | SARIF upload works for public repositories and Enterprise organisations; for the private repository use `--format=github` annotations | Adopt |
| pinact | Pins actions to commit SHAs, updates them, checks version comments | MIT; v5.0.0, 2026-09-12; 1.2k stars | Version 5 changed its flags; needs a GitHub token to resolve tags | Consider |
| Renovate | Dependency update bot including action digests | AGPL-3.0-only; 44.124.0, 2026-09-30; 22.4k stars | Pricing for private repositories: NOT FOUND; heavier than Dependabot | Skip |
| ShellCheck | Static analysis of shell scripts | GPL-3.0; v0.11.0, 2025-08-04; 40.0k stars | The Ubuntu 24.04 runner image has 0.9.0, older; whether `tests/validate.sh` already runs it: NOT FOUND | Consider |
| ludeeus/action-shellcheck | Action wrapper for shellcheck | MIT; 2.0.0, 2023-01-29; 350 stars | Stale; the runner already has shellcheck | Excluded |

Each new tool adds a job to the run it is meant to speed up. The strongest counter-case is that a tool is itself an attack surface (tj-actions/changed-files above), so pin by SHA and run these in the existing job or one small parallel job. [ASSUMPTION]

## 7. Claude Code's own features that overlap your hand-built parts

All from Anthropic's documentation, read as extracts on 2026-09-30; the current release is v2.1.285 (tag commit 2026-09-29). Claude Code is proprietary ("All rights reserved").

| Native feature | What it does | Overlaps with | Catch | Use? |
|---|---|---|---|---|
| `permissions.deny` (project or managed settings) | Forbids matching tool calls; deny beats ask beats allow in any scope; a managed deny cannot be overridden | `git-guard.mjs` (partly), `plan-mode-guard.mjs`, `brief-guard.mjs` (partly) | Matches command text only; see contradiction 3; no exception for a temporary folder; hooks fail open on timeout but a deny rule still holds | Consider as a second layer |
| Sandbox (`/sandbox`) | Operating-system enforcement (Seatbelt on macOS, bubblewrap on Linux) of file and network limits for shell commands | Push by network, write protection of approval files | "not a complete isolation boundary"; shell commands only; limits network by domain, not by git subcommand; `dangerouslyDisableSandbox` escape hatch (turn off with `allowUnsandboxedCommands: false`); whether `denyWrite` accepts a pattern such as `*.brief.approved`: NOT FOUND | Consider |
| Stop hook, command type | Your script runs when Claude tries to stop; exit 2 keeps it working | `stop-gate.mjs` core | Claude Code overrides a Stop hook after 8 blocks in a row; a timed-out hook renders no decision, so it fails open | Keep custom (see notes) |
| Stop hook, agent type | A sub-agent runs the tests and judges | `stop-gate.mjs` alternative | Documented as experimental; a model decides and it costs tokens at every stop | Skip |
| `/goal` | A small model judges after each turn whether a stated condition holds | Not a gate | "doesn't run commands or read files independently" | Skip |
| `claude plugin validate [--strict] [--json]` | Checks manifests and skills, agents and commands; exit 0, 1 or 2 | Plugin validation | Checks files, not behaviour; harness-kit already runs it | Adopt (already) |
| `claude plugin eval` | Runs a plugin's eval cases (prompt plus graders) three times by default, with and without the plugin | `eval-reviewer.sh` (partly) | Four of six grader types cost nothing; the model-judged ones are paid model calls; CI needs credentials and `--trust-plugin`; `--max-cost-usd` caps spend; requires Claude Code 2.1.269 or later; cost for harness-kit: NOT FOUND. No sampled project uses it in CI | Consider (free graders only) |
| `/code-review`, `/security-review` | Local review of a diff or branch in your session | `review.sh` (partly) | Counts toward normal usage; does not read `REVIEW.md`; no per-item checklist with quoted evidence | Skip |
| `--max-turns`, `--max-budget-usd`, hook `timeout` | Cap turns, dollars or a hook's seconds | `time-limit.mjs` (partly) | Print mode only for the first two; turns and dollars are not seconds; no flag limits the total time of a `claude -p` run (NOT FOUND) | Adopt (already used in `review-lib.sh`) |
| GNU `timeout` | Time limit; `-k` adds a later kill; exit 124 | `time-limit.mjs` (partly) | Not installed on macOS by default (Homebrew coreutils provides `gtimeout`) [PARTIAL: search titles only]; does not sweep temporary folders or keep named budgets | Consider (CI uses `timeout-minutes` instead) |

## 8. AI review and third-party hook tools

| Name | What it does | Licence, release, stars | Catch | Use? |
|---|---|---|---|---|
| Official `code-review` plugin | Five parallel review agents; comments on a pull request only for findings scored 80 or more | Apache-2.0; part of claude-plugins-official (37.1k stars; last commit 2026-09-29) | Needs a pull request and `gh`; its false-positive list tells reviewers to skip anything CI would catch | Skip |
| Official `pr-review-toolkit` | Six specialised review agents | Apache-2.0 | Interactive, not run from a script by design (ASSUMPTION) | Skip |
| `claude-code-action` | GitHub Action that runs Claude on pull request events | MIT; v1.0.213 (1 September, year not displayed); 8.9k stars; last commit 2026-09-30 | Needs pull requests and an API key or subscription token; costs minutes plus tokens; whether subscription tokens may be used in CI under Anthropic's terms: NOT FOUND | Skip |
| `claude-code-security-review` | Reviews a pull request diff for vulnerabilities | MIT; no releases; 6.3k stars; last commit 2026-02-11 | Stale; "not hardened against prompt injection" | Excluded |
| Managed Code Review | Multi-agent review on Anthropic's servers | Service, research preview | Team and Enterprise only; averages $15–25 per review; eligibility of a personal-account repository: NOT FOUND | Excluded |
| Ultrareview | Cloud review, findings reproduced independently | Service, research preview | Three one-time free runs on Pro and Max, then about $5–25 per review; not for zero-data-retention organisations | Excluded |
| Copilot code review | AI review on pull requests | Service | "Available for all paid Copilot plans"; Free plan not listed; a free GitHub-native AI review: NOT FOUND | Excluded |
| CodeRabbit | AI review service | Service | Pricing page: Essentials $24, Team $48, Advanced $72 per developer per month; 14-day trial; no permanent free plan shown | Excluded |
| kenryu42/cc-safety-net | Parses commands by meaning and blocks destructive git and file commands | MIT; v2.4.14 (2026-09-30); 1.6k stars; last commit 2026-09-30 | Its rules cover force, delete and mirror pushes but not a plain `git push` [VERIFIED by search of the clone]; its README says "A broken config file never blocks anything" (fails open); it does not cover approval files, your scripts or scratch copies | Consider as an extra layer |
| Dippy | Parses Bash to auto-approve safe commands | MIT; v0.2.7 (March 2026, year as displayed); 240 stars | Mainly reduces prompts; quality unverified | Skip |
| hookify (official) | Markdown rules with a regex; can block a command or a stop | Apache-2.0 | Regex on command text; its Stop example checks whether test commands appear in the transcript, it does not run them | Skip |
| Trail of Bits `claude-code-config` | Settings template with deny rules and regex hooks | No licence file found in the clone | Blocks only `git push.*(main\|master)`; reuse rights unclear | Skip |
| `security-guidance` (official) | About 25 regex reminders after each edit, model reviews at Stop and at commit | Apache-2.0; marketplace version 2.0.7 | Its hooks run after the file is written, so it cannot deny a write; the model layers cost tokens | Skip |
| ralph-loop (official) | Stop hook that re-feeds a prompt until a promise tag appears | Apache-2.0; 1.0.0 | Completion is Claude's own statement; runs no check | Skip |
| tdd-guard | Blocks edits that break test-first discipline | MIT; v1.7.0 (2026-06-23); 2.3k stars | Guards edits, not stopping; a different job | Skip |
| Plannotator | Browser page for annotating and approving a plan | Apache-2.0 or MIT; 9.1k stars | Helps you approve; does not stop Claude approving; sends an update check to GitHub with no opt-out | Skip |
| Official marketplace | 314 plugin entries searched for release, CI, ship, merge, changelog and similar terms | Apache-2.0 | No release or changelog plugin: NOT FOUND | n/a |

## 9. Mutation and fault tools

| Name | What it mutates | Maintained? | Could it run "fault X must fail test Y" from a list? | Use? |
|---|---|---|---|---|
| universalmutator | Any text through rule files (regular expressions or comby); ships rules for C, C++, Java, JavaScript, Python, Swift, R, Rust, Go, Lisp, Fortran and contract languages; **none for shell** | Apache-2.0; release and last commit 2026-05-20; 157 stars | Partly. A custom rule file is one `pattern ==> replacement` per line, but `analyze_mutants` takes one test command for all mutants, with no expected test per fault. A wrapper would be needed | Skip |
| StrykerJS | JavaScript and TypeScript | Apache-2.0; v10.0.0, 2026-08-14; 3.0k stars; last commit 2026-09-11 | No. Cannot parse `.sh`; with the plain command runner "all tests are executed for each mutant". It could mutate your 14 `.mjs` scripts, but the tests are bash | Skip (gadget: Consider, see file 02) |
| mutmut, Mull, comby | Python; C and C++; not a mutation tool | 3.8.0 (2026-09-12); 0.34.1 (2026-09-13); comby last release 2022 | No (wrong language, or helper only) | Skip |
| cargo-mutants, Infection, Pitest, Cosmic Ray, go-mutesting, Stryker.NET | Rust, PHP, Java, Python, Go, .NET | See file 02 | Not evaluated for shell | n/a |

Any tool that mutates shell scripts: NOT FOUND. Any tool that takes a curated fault list and asserts which test must fail: NOT FOUND. A GitHub issue dated 2026-08-01 in an unrelated project says its coverage and mutation tools "neither reach shell scripts" [PARTIAL: secondary extract; it shows only that project found none]. So `replay-faults` (about 1,060 lines plus 137 hand-written faults) is not a poor copy of a standard tool; it is a different kind of tool, for which nothing free exists. [ASSUMPTION for the reading; VERIFIED for the search results]

## 10. Notes: what the evidence says about each of your hand-built parts

- **`release.sh` and the merge step of `ship.sh`.** Nothing free replaces `git push --atomic origin main tag`. Auto-merge and rulesets are free for harness-kit and not for the gadget (contradiction 1). Whether the merge button or auto-merge can also create a tag: NOT FOUND (I did not read the release-creation documentation). GitHub waiting for CI, instead of your terminal, is the real gain. [VERIFIED for availability; ASSUMPTION for the design]
- **`time-limit.mjs` (610 lines).** It does more than a timeout: named limits with environment overrides, process-group termination (SIGTERM, then SIGKILL after a grace period), signal forwarding, and a registry that sweeps leftover temporary folders and worktrees. [VERIFIED | its header] GNU `timeout`, `timeout-minutes` and the hook `timeout` each cover one of the places a limit is needed (scripts, CI jobs, hooks) but none sweeps or keeps named budgets. Whether Claude Code kills a timed-out hook's process group: NOT FOUND. The half that could be simplified is the plain timeout; whether the registry sweep is still needed depends on whether the leaks it handles still occur, and I have no evidence either way.
- **`replay-faults.sh` sharding.** No free general tool shards bash tests or a fault list by measured time. GitHub's matrix, which you already use, is the mechanism.
- **`tests/validate.sh`.** The tests folder holds 20 `*.test.sh` files, while your description says 19; which one is not run: NOT FOUND (not traced). `xargs -P`, with each file's output kept separate, is the smallest change. The counter-case is hidden shared state making failures irregular, which would weaken a gate that must not weaken.
- **Stop gate.** A native command Stop hook would be about ten lines. What the 331 lines of `stop-gate.mjs` add is the skip when nothing changed since the last pass (a pass record valid for at most 24 hours), the fail-closed time limit (the check is stopped at 540 seconds so the hook's own 600-second limit does not silently allow the stop), the event log and a per-session budget warning. A free, maintained tool that runs a project's check at stop with those properties: NOT FOUND. [VERIFIED for the documentation; ASSUMPTION for the ten lines]
- **`guard-secrets.mjs`.** Nothing free replaces the block before a write. Gitleaks in CI could widen the scan half of the job and retire the CI `--scan` mode; its own tool is in security-patch-only mode.
- **`check-commits.mjs`.** No tool checks its three rules. Keep custom.
- **`review.sh`.** Its cap is `--max-budget-usd 3.00`, below the published averages of the managed products ($15–25) and cloud reviews (about $5–25). The $3.00 is a ceiling, not a measured cost, and the real cost per review is NOT FOUND in the files I read. Whether it finds as many real defects as any alternative is unmeasured for every tool compared here. [VERIFIED for the flags and prices; ASSUMPTION for the verdict]
- **`plan-mode-guard.mjs` and `brief-guard.mjs`.** Native plan mode is a human dialog, and a hook cannot auto-approve it ("intended behavior", an open issue; a PreToolUse deny on `ExitPlanMode` was ignored in one closed issue [PARTIAL | mirror pages]). No native feature makes an approval token that Claude cannot write (NOT FOUND). The closest are an `Edit(**/*.brief.approved)` deny, which does not cover a script Claude writes and runs, and a sandbox write restriction whose pattern support is unverified.
- **`install-hooks.sh` (124 lines).** No candidate removes the per-clone install step for harness-kit.
- **Workflow hygiene.** actionlint and zizmor are single-file tools that fit into the existing job; Dependabot needs no install.

## Negative results

- Exact star counts: NOT FOUND (interface blocked). Release times with year and zone: NOT FOUND directly; years derived from tag commits. `actions/cache` releases page: not readable (robots.txt).
- GitHub Pro monthly price, and whether your account is on Pro: NOT FOUND. Whether an owner can bypass required checks on a solo repository, and the default bypass list of a new ruleset: NOT FOUND.
- Whether Node 20 actions still run after 23 September 2026: NOT FOUND.
- Whether Claude Code kills a timed-out hook's process group: NOT FOUND. Whether GNU `timeout`'s default mode signals the whole process group: NOT FOUND as an explicit sentence.
- Licences of GNU coreutils, findutils, make, git and the GitHub CLI: not fetched. GNU make `-j` documentation: NOT FOUND ("429" and robots.txt).
- A free general test splitter for bash tests: NOT FOUND. A tool that mutates shell: NOT FOUND. A tool that takes a curated fault list with the test that must fail: NOT FOUND.
- A free, maintained tool that runs a project check at stop with skip-when-unchanged and a fail-closed time limit: NOT FOUND. A native approval token Claude cannot write: NOT FOUND. A flag for the total wall-clock time of a `claude -p` run: NOT FOUND.
- A release, changelog or ship plugin in the official marketplace: NOT FOUND. A free GitHub-native AI review on the free plan: NOT FOUND.
- Install time of Claude Code in CI, per-file test durations, cost per review of `claude-code-action` and of a `plugin eval` suite: NOT FOUND (needs measurement).
- Mergify's engine source and its handling of required checks skipped by path filters; Nx Cloud's free tier for personal private repositories; Renovate, Develocity and Depot prices: NOT FOUND or not checked.
- Not fetched: last commits of Dippy, Plannotator, Agent Guard and the OneRedOak and Chachamaru127 workflow repositories; managed-settings file path for one developer; whether the sandbox `denyWrite` accepts patterns; whether commitlint can host custom rules.
- Not searched: pre-commit.ci and other hosted variants.
- Untrue or weaker than expected: bors-ng is archived; ludeeus/action-shellcheck, gitlint and ShellSpec are effectively unmaintained; a merge queue is not free for personal accounts; caching Playwright browsers is advised against; the gitleaks action is not MIT any more.

## Strongest counter-cases

- **Against moving harness-kit to pull requests with required checks.** Fast-forward through a script keeps history linear and gives one atomic push of `main` and the tag, which a merge button cannot do. A pull request adds ceremony for a solo maintainer with no reviewer, and a solo owner may be able to bypass the rule (NOT FOUND). Without a merge queue, two pull requests can each pass against an old `main` and break it when both merge, unless "require branches to be up to date" is set (not verified).
- **Against using GitHub features for the gadget.** They need a paid plan; if you will not pay, only the local pre-push hook remains, and `--no-verify` bypasses it.
- **Against `xargs -P`.** Hidden shared state (ports, `$HOME`, registries) can make failures irregular, and the private runner has 2 vCPU, so the gain there is small.
- **Against gitleaks in CI.** It adds a binary to pin, false positives need an allowlist file, and guard-secrets already blocks at authoring time.
- **Against actionlint, zizmor and pinact.** Every new tool is a new dependency and can be an attack surface.
- **Against keeping `check-commits.mjs`, `time-limit.mjs` and `install-hooks.sh` custom.** They are 443, 610 and 124 lines that you must maintain, and your own brief says custom scripts produced most defects. GNU `timeout` would remove most of `time-limit.mjs`'s job for shell scripts at the cost of the registry sweep.
- **Against not caching Chromium.** Playwright's statement is about restore time being comparable to download time; on a slow or rate-limited network a cache may still help. I measured neither.
- **Against deny rules as a second layer.** Two lists can drift, and the gain is limited to the case where the hook itself fails open, which may be rare. [ASSUMPTION]
- **Against replacing the plan-mode guard with one deny line.** It is untested, it must be added to every consumer project, a plugin cannot deliver it, and if a later Claude Code version treats unknown names differently the protection could silently vanish, whereas a script with a test and a fault in `mutations.tsv` cannot.
- **Against keeping the custom reviewer.** Anthropic's managed and cloud reviews verify each finding in a separate step with many agents; yours is one agent limited to 40 turns and $3.00, and no comparison of defects found exists. If your review time (30 to 60 minutes per release) is the real cost, the paid products may be worth it, though they need pull requests.
- **Against "no off-the-shelf mutation tool".** universalmutator with a rule file and a small wrapper might do the job in fewer lines than about 1,060, and would find faults nobody listed; but automatically generated mutants on shell would include many with no effect, which is why such tools are noisy. [ASSUMPTION]
- **Against my sample.** I chose the candidates by plausibility for a solo maintainer, from Anthropic's, GitHub's and each tool's own pages. Stars are not evidence of quality, and I read no independent effectiveness evaluation of any candidate.
