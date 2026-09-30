# 01 — How well-run projects use CI and GitHub (question A)

Written on Wednesday 30 September 2026. Research only: no repository was changed.

## Terms used in this file

- **CI (continuous integration)** means checks that GitHub runs automatically when code is pushed or proposed.
- **Workflow, event, run, job, runner, step.** A workflow is a recipe file in `.github/workflows`. An event (for example `push`) starts a run of it. A run is made of jobs, each job gets its own fresh machine called a runner, and a job is made of steps (single commands).
- **Pull request** means a proposal to merge one branch into another, which GitHub can check and record. **Merge by local script** means a script on your own computer updates `main` directly, without a pull request.
- **Branch protection rule** and **ruleset** are GitHub settings that refuse changes to a branch or tag unless conditions hold. A ruleset is the newer and more flexible form.
- **Required status check** means a named check that must have passed before GitHub accepts a change to a protected branch.
- **Merge queue** means a GitHub service that tests each pull request on top of the latest `main` before merging it, one after another.
- **Fast-forward** means moving `main` to a commit that already contains all of `main`, so that the commit on `main` is exactly the commit that was tested.
- **Aggregator job (also called a gate job)** means one final job that succeeds only when all the real jobs succeeded, so that branch protection needs to name only one check.
- **Path filter** means a rule that runs a workflow only when certain files changed.
- **Test impact analysis** means choosing which tests to run from what a change touches, instead of running all of them.
- **Sharding** means splitting the tests over several machines at once. **Concurrency group** means a label that lets GitHub cancel an older run when a newer one starts.
- **Presubmit** means checks that run before a change lands, and **postsubmit** means checks that run after it has landed.
- **Flaky test** means a test that sometimes fails and sometimes passes on the same code.

## How this file is based on evidence

This file draws on 191 sources from three research threads (GitHub platform rules, real projects and speed techniques, release automation): 182 are primary (GitHub's own documentation, changelog and repositories, and the projects' own files) and 9 are secondary (two Martin Fowler pages, two trunkbaseddevelopment.com pages, and search-result lists). I chose them by going first to GitHub's own page for each question, then to the projects' own repositories. For real projects I built a hand-picked sample of 16 public repositories (9 large, 7 small; Rust 6, Java 3, JavaScript 3, Python 1, Go 1, Haskell 1, shell 1) and cloned each one to read its workflow files. The sample is not random and it over-represents Rust. Every percentage below is out of 16 and describes this sample only.

How pages were read: web pages were read by research sub-agents through a fetch tool that returns a summary written by a small model, so every web page counts as an extract, not a full read. Repository files in clones were read in full. Five claims that change the decision were re-read by me on the live GitHub page (they are marked "re-read by me"). The complete notes, with quotations and the source log, are in `evidence/A1-github-platform.md`, `evidence/A2-projects-and-speed.md` and `evidence/A3-release-automation.md`.

Labels: **[VERIFIED]** means a primary source says it. **[PARTIAL]** means secondary, or only partly supported. **[ASSUMPTION]** means my reasoning. **NOT FOUND** means I searched and found nothing.

## CONTRADICTIONS

1. **"Private repositories can use branch protection and merge queue for free" is false.** GitHub's documentation says: "Protected branches are available in public repositories with GitHub Free and GitHub Free for organizations. Protected branches are also available in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server." [VERIFIED | docs.github.com about-protected-branches | accessed 2026-09-30, re-read by me] Rulesets, auto-merge and code owners carry the same plan wording. [VERIFIED | docs.github.com about-rulesets | accessed 2026-09-30] So control-chart-gadget (private, personal account) gets no server-side rule on the free plan. The price of GitHub Pro: NOT FOUND on any page my agents fetched, so I cannot say what the rules would cost.
2. **Merge queue is not available to either of your repositories.** "Pull request merge queues are available in any public repository owned by an organization, or in private repositories owned by organizations using GitHub Enterprise Cloud." [VERIFIED | docs.github.com managing-a-merge-queue | accessed 2026-09-30, re-read by me] Both repositories belong to a personal account, so neither qualifies, and a merge queue cannot be the way to remove the duplicate run on `main`.
3. **"Full fault replay on every push to main is necessary" and "faults must be replayed after merge" are not how the strictest projects work.** Rust and Cargo run their full test suite on the exact commit before it lands, and have no push-triggered test run on `main` at all. [VERIFIED | rust-lang/rust and rust-lang/cargo workflow files, cloned | 2026-09-30] Meta runs its full suite on the newest `master` only "once every few hours". [VERIFIED | arxiv.org/abs/1810.05286 | extract] Counter-fact: 14 of the 16 sampled projects do re-run tests after a push to `main`, so a post-merge run is normal; what is not normal is running the slowest tier on every `main` push. See section 4.
4. **"Custom release and merge scripts are safer than pull requests" has no support in this sample.** All 9 large projects bring changes in through a pull request, even when a bot or script performs the last step. [VERIFIED | workflow files and last 100 commits of each, cloned] Two nuances: a solo maintainer (BurntSushi/ripgrep) pushes mostly straight to `master` and relies on CI afterwards, and casey/just tags from a local script but only after cloning a fresh copy of already-tested `master`. So "a solo maintainer pushes directly" is a legitimate practice; "a local script is a stronger gate than GitHub" is not evidenced. The weakness of your gate is that it is local: harness-kit's pre-push hook can be skipped with `git push --no-verify` and must be installed in every clone, while a ruleset on GitHub cannot be skipped from your laptop. [VERIFIED for the hook, from install-hooks.sh; ASSUMPTION for the comparison]
5. **Node 20 is not merely "deprecated"; it was removed from GitHub's runners on 23 September 2026.** "This is the final notification that Node 20 is no longer available on GitHub Actions runners. Runners now use Node 24 for JavaScript actions." [VERIFIED | github.blog changelog 2026-09-23 | re-read by me] The changelog does not say whether actions that still declare `node20` (checkout@v4, setup-node@v4 and the artifact actions at v4) fail or are forced onto Node 24. NOT FOUND. Your CI runs of 29 and 30 September still passed, which suggests they still run. [PARTIAL]
6. **"Add `paths:` filters to save minutes" collides with required checks.** If a whole workflow is skipped by a path filter, its checks stay "Pending" and block the merge, whereas a job skipped by an `if:` condition reports success. [VERIFIED | docs.github.com troubleshooting-required-status-checks | accessed 2026-09-30] The standard workaround, used by 4 of the 16 sampled projects, is one always-running aggregator job as the only required check.
7. **Caching the Playwright browser is advised against by Playwright itself.** "Caching browser binaries is not recommended, since the amount of time it takes to restore the cache is comparable to the time it takes to download the binaries." [VERIFIED | playwright.dev/docs/ci | accessed 2026-09-30] control-chart-gadget installs Chromium in every run; measure before adding a cache.

## 1. Pull requests and rules, versus merging by local script

**What a required status check can enforce.** "Required status checks must have a `successful`, `skipped`, or `neutral` status before collaborators can make changes to a protected branch." [VERIFIED | about-protected-branches | accessed 2026-09-30] A check can only be required if it "completed successfully within the chosen repository during the past seven days". [VERIFIED | troubleshooting-required-status-checks] Rulesets also offer "require branches to be up to date before merging", required linear history, and a choice of which GitHub App must report the check.

**Can a solo owner be bound by the rules?** By default no: "the restrictions of a branch protection rule don't apply to people with admin permissions to the repository", and an option exists to apply them to admins as well. [VERIFIED | about-protected-branches] A ruleset can list who may bypass it, including "repository administrators", with a mode "for pull requests only" that leaves a trail in the audit log. [VERIFIED | about-rulesets] Whether the owner of a personal repository is on a new ruleset's bypass list by default: NOT FOUND. So a solo owner is bound only if he chooses to be.

**Required approvals block a solo developer.** "Pull request authors cannot approve their own pull requests." [VERIFIED | docs.github.com approving-a-pull-request-with-required-reviews] Therefore a rule that demands one or more approvals cannot be satisfied by a solo maintainer, and the usual solo setting is zero required approvals plus required checks. That this is "the standard" is [ASSUMPTION]: NOT FOUND as a GitHub statement.

**Can a green commit be pushed straight to a protected branch?** GitHub says: "After all required status checks pass, any commits must either be pushed to another branch and then merged or pushed directly to the protected branch." [VERIFIED | about-protected-branches] That sentence supports releasing by fast-forwarding `main` to an already-green commit under a ruleset. The documentation does not describe exactly what GitHub checks on such a push, so [PARTIAL]: test it on a scratch repository before relying on it (this is a migration step in file 06).

**What the sample does.** Of the 9 large projects, 4 use the plain merge button (Vite, Ruff, Home Assistant, Kafka), 3 use a bot or queue (Rust's bors; Cargo and JUnit through GitHub's queue, inferred from a `merge_group` trigger, so [PARTIAL]), 1 uses a label-driven landing script (Node's commit queue), and 1 merges the pull request locally with git (Spring Boot). None lands changes without a pull request. Among the 7 small projects the practice is mixed: pull requests only (just, mostly type-fest), mixed (fd, fzf, ShellCheck, bats-core), mainly direct pushes (ripgrep). No project in the sample keeps a home-written local script as its only gate to `main` (NOT FOUND). [VERIFIED for the counts; the reading is PARTIAL]

## 2. Which GitHub features work on which repository and plan

This table is derived from the quoted GitHub sentences. Y means available and N means not available, per those sentences; the cells for a free organisation are my derivation from the same sentences [ASSUMPTION].

| Feature | Public, free personal (harness-kit) | Private, free personal (gadget today) | Private, GitHub Pro personal | Private, organisation Team | Private, Enterprise Cloud |
|---|---|---|---|---|---|
| Branch protection, required checks | Y | N | Y | Y | Y |
| Rulesets (incl. tag rules) | Y | N | Y | Y | Y |
| Auto-merge | Y | N | Y | Y | Y |
| Environments | Y | N | Y | Y | Y |
| Merge queue | N (personal) | N | N | N | Y |
| Secret scanning and push protection | Y, free | N | N | Y, paid add-on | Y, paid add-on |

Prices read on 2026-09-30 on github.com/pricing (extract): Free "2,000 CI/CD minutes/month"; Team "3,000 CI/CD minutes/month"; Enterprise "50,000". [VERIFIED] Private-repository minutes beyond the allowance cost $0.006 per minute on a 2-core Linux runner, and "GitHub rounds the minutes and partial minutes each job uses up to the nearest whole minute". [VERIFIED | docs.github.com actions-runner-pricing and billing pages] Standard runners stay free for public repositories: "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted runners." [VERIFIED] A public repository's standard Linux runner has 4 vCPU and 16 GB; a private repository's has 2 vCPU and 8 GB. [VERIFIED | docs.github.com github-hosted-runners | re-read by me] A charge on self-hosted runners announced for 1 March 2026 was postponed and I found no new date. [VERIFIED for the postponement]

## 3. Merge queues

A merge queue exists to test the exact result of merging, in order. It requires the `merge_group` workflow event, and it is unavailable to personal-account repositories (contradiction 2). Only 2 of the 16 sampled projects appear to use GitHub's queue (Cargo, JUnit), and Rust uses its own bot with a queue. For your repositories the queue is irrelevant; fast-forward merging already gives the same guarantee for one committer, because the commit that lands is the commit that was tested. [ASSUMPTION, reasoned from how fast-forward works]

## 4. Running only what a change affects, and what runs on main

**Path filters.** Native `paths:` filters work at workflow level and cause the trap in contradiction 6. Vite, Home Assistant and Ruff instead use a small job that computes what changed and later jobs test that result in an `if:` condition, plus an aggregator job. Home Assistant is the strongest example: on pull requests only the changed integrations' tests run, and on pushes to its main branches the full suite is forced. Ruff does the same and makes `main` a superset of the pull-request run. [VERIFIED | their ci.yaml files, cloned]

**Test impact analysis.** Google runs affected tests before submission and everything continuously afterwards; its own paper says it cannot test every change individually. [VERIFIED | research.google, Memon et al., ICSE 2017 abstract] Meta's published model runs fewer than a third of the tests that dependency analysis would choose, yet reports "over 99.9% of faulty changes". [VERIFIED | arxiv.org/abs/1810.05286 | extract] In the sample, only JUnit uses a product for this (Develocity predictive selection, on pull requests, with the remaining tests run on every other event). Develocity is free only through an open-source sponsorship whose application steps I could not find, and the price of Launchable is NOT FOUND. Neither suits a solo private project. Tools such as Nx and Turborepo (affected-project detection) need a project graph and give little for a single-package repository. [ASSUMPTION for fit]

**The post-merge question, answered from the sample.** Fourteen of 16 repositories re-run tests after a push to their main branch. Two do not (Rust, Cargo), and both test the merge candidate before landing through a serialised bot or queue. Among projects without a queue, the majority pattern is a cheap tier before merge and a wider tier after (Spring Boot, Home Assistant, Ruff, JUnit, Kafka). Google's book says postsubmit can "accept longer times and some instability". [VERIFIED | Software Engineering at Google, ch. 23 | extract] No source states that a post-merge re-run of an already-tested fast-forwarded commit is waste, but Rust and Jane Street's rule (only commits that passed everything are ever merged) make it redundant by design. [VERIFIED for both; the conclusion is ASSUMPTION] There is one mechanism-level reason to keep a run on `main`: caches created in a pull request "cannot be restored by the base branch or other pull requests", so a run on the default branch is what warms the cache for later runs. [VERIFIED | docs.github.com dependency-caching] A weekly run on `main` serves that purpose.

## 5. Test result caching and dependency caching

Gradle, Bazel, Nx and Turborepo cache test and build results by input hash; the mechanism is free, and hosted remote caches are free only in some cases (Turborepo's Vercel cache "is free to use on all plans"; Nx Cloud has a free Hobby tier of 50,000 credits). [VERIFIED | extracts] None of it applies to a bash test suite unless the tests are turned into tasks with declared inputs. [ASSUMPTION]

For dependency caching, `actions/cache` has a 10 GB limit per repository, evicts entries unused for 7 days, and restores only from the current branch, the default branch and, for pull requests, the base branch. [VERIFIED | docs.github.com dependency-caching] setup-node's `cache: npm` caches the download cache, not `node_modules`, and needs a lock file. [VERIFIED | README extract] Nine of the 16 sampled projects cache something; 7 (mostly small ones) do not, including the top-tier Cargo, which reinstalls tools in every job. [VERIFIED]

## 6. Splitting tests over machines by measured timing

Zero of the 16 sampled projects split by measured time on GitHub Actions. Home Assistant splits into 10 groups by test count, Rust splits by hand-named jobs. [VERIFIED | workflow files] Free tools exist for other frameworks: pytest-split (MIT) balances by stored durations; Jest and Playwright shard without timing; cargo-nextest partitions by hash or slice. Timing-based services are paid or platform-specific (Knapsack Pro $10 per committer per month; CircleCI only on CircleCI; Buildkite's splitter on its own platform). [VERIFIED | extracts] For a bash test suite no free general splitter was found. NOT FOUND. GitHub's matrix, which harness-kit already uses, is the mechanism. Two limits matter: a matrix may have 256 jobs, and a Free-plan account may run only 20 jobs at the same time. [VERIFIED | docs.github.com actions limits | extract] That 20 is the ceiling on how far adding shards can keep waiting time flat.

## 7. Cancelling outdated runs, reusable workflows, timeouts

**Concurrency.** "By default, any existing `pending` job or workflow in the same concurrency group will be canceled and the new queued job or workflow will take its place"; setting `cancel-in-progress: true` also cancels a running one. GitHub's own example excludes release branches from cancelling. [VERIFIED | docs.github.com concurrency] Ten of 16 sampled projects use it; three cancel only pull-request runs and never runs on `main`, and Vite's file states this: `cancel-in-progress: ${{ github.ref_name != 'main' }}`. [VERIFIED | files] It is standard, and it matters most on a private repository, where a cancelled run stops the meter.

**Reusable workflows and composite actions.** A reusable workflow (`on: workflow_call`) can hold several jobs and use secrets; a composite action bundles steps inside one job. For one owner, a composite action for "install Node and Claude Code" is the natural way to remove the repeated setup steps, and a reusable workflow is for sharing whole jobs. [VERIFIED for the properties | docs.github.com reuse-automations; the fit is ASSUMPTION]

**Timeouts.** The default job timeout is 360 minutes; `timeout-minutes` lowers it per job or step. [VERIFIED | workflow syntax | extract, one of two extracts disagreed on the default, so PARTIAL]

## 8. Flaky tests

Google reported about 1.5% of test runs flaky and "almost 16%" of tests with some flakiness; its mitigations are automatic reruns, marking a test flaky so it reports failure only after three failures in a row, and automatic quarantine. [VERIFIED | Google Testing Blog, 2016-05-27 | extract] Free tools: cargo-nextest `--retries`, Playwright `--retries`, Gradle test retry. Apache Kafka has the most complete design in the sample (a catalogue of flaky and new tests kept on a git branch and updated only from `trunk` runs, with retries for flaky tests). Ruff and Home Assistant, both large, use no retries at all. [VERIFIED | files] For a solo project, retry with a visible report is cheap; a quarantine service is over-engineering unless flakiness appears. [ASSUMPTION] There is no evidence in this research that harness-kit has a flaky-test problem. NOT FOUND.

## 9. Release automation

Fifteen projects with a determinable answer split like this: a tag push or a workflow started with a tag name, 7; a prepared pull request plus a human step, 2; a bot-maintained release pull request, 3; fully automatic, 2; no releases, 1 (Anthropic's own plugin marketplace has no tags and no release workflow). [VERIFIED | workflow files; sample of 16, 4 of which are release tools themselves] There is no single standard: projects shipping compiled programs favour the tag-triggered workflow, and npm projects favour release pull requests.

The tools, from their own repositories (dates are tag dates read from clones): release-please (Apache-2.0, v17.11.2, 2026-08-24, 7.4k stars; its GitHub Action has had no commit for four months and bundles an older engine), semantic-release (MIT, v25.0.9, 2026-08-05), changesets (MIT, cli 3.0.3, 2026-09-14). All three decide the version from commit messages or changeset files, and two need pull requests. **They do not fit harness-kit**: its version lives in one file only (`plugins/harness-kit/.claude-plugin/plugin.json`; the marketplace file deliberately has none and `tests/validate.sh` forbids one), it is bumped inside each work commit rather than at release time, and its commit messages are not Conventional Commits. [VERIFIED | clone at e275280 and Claude Code's plugin documentation] Release tools that run in a workflow with the built-in `GITHUB_TOKEN` create pull requests and tags that "will not trigger future GitHub actions workflows", so they need a personal access token or a GitHub App key. [VERIFIED | release-please README, cloned] For a solo developer the tag-and-push step is not the slow part of a release; waiting for and repairing CI is. [ASSUMPTION, reasoned from release.sh and your timings]

Tag protection: the old "protected tags" feature was retired on 30 August 2024 in favour of rulesets. [VERIFIED | GitHub changelog 2024-05-29] A tag ruleset is free on public repositories and needs a paid plan on private ones. Immutable releases exist (GitHub changelog 2025-10-28) but apply to GitHub Release objects, and harness-kit has none, only tags. [VERIFIED]

## 10. Summary table: standard, optional, and cost

| Practice | Standard or optional | Public repo (free runners) | Private repo (2,000 free minutes, then $0.006 per minute) |
|---|---|---|---|
| Pull request, required checks, rulesets | Standard for large projects; optional for solo | Free | Needs a paid plan (Pro or above); price NOT FOUND |
| Merge queue | Optional; used by 3 of 9 large sampled projects | Organisation-owned repositories only | Enterprise Cloud organisations only |
| Path filters | Optional | Free | Free; saves minutes; mind the Pending trap |
| Test impact analysis | Optional; large projects only | Free tools exist; predictive services are paid or by sponsorship | Same |
| Dependency cache | Standard for large projects (9 of 16) | Free within 10 GB | Free within 10 GB; counts as storage |
| Test result cache | Optional; tied to Gradle, Bazel, Nx, Turborepo | Free mechanism | Same |
| Sharding by measured time | Optional; used by 0 of 16 on GitHub Actions | Free with your own script | Each shard is billed as a whole minute, so 8 shards cost more than 1 job |
| Cancel outdated runs | Standard (10 of 16) | Free | Saves money |
| Aggregator (gate) job | Standard where required checks exist (4 of 16) | Free | Costs about one minute per run |
| Flaky-test retry with report | Optional | Free tools | Free tools |
| Reusable workflow or composite action | Optional | Free | Free |
| Release automation | No standard | Free | Free apart from minutes |

## Negative results

No project in the sample uses a home-written local script as its only gate (NOT FOUND). No merge-queue or Mergify configuration file was found in any of the 16 clones except Rust's `rust-bors.toml`; queue settings that live in repository settings could not be read because the GitHub API returned HTTP 403 to my fetch tool, and I did not route around that. No project uses timing-based sharding on GitHub Actions. Nothing states that a post-merge re-run of an already-tested commit is waste. GitHub has no built-in setting that skips a duplicate run for a commit that already passed; the closest is the git project's own workflow step "skip already-tested commits/trees", which queries earlier runs through the API. [VERIFIED | code.googlesource.com/git] The GitHub Pro price, the default bypass list of a new ruleset, and whether v4 actions fail after 23 September are all NOT FOUND. Microsoft/vscode, python/cpython and grafana/grafana were on my candidate list and were not read.

## Strongest counter-cases

- **Against pull requests and rulesets:** on the private repository they need a paid plan; a solo owner may bypass them; a merge queue is impossible on a personal account; and each pull request adds ceremony and attention time, which is one of your stated problems.
- **Against ignoring `main` after a fast-forward:** the run on `main` is also an independent check on a clean runner with the current runner image and the current Claude Code installer, which can change between the branch run and the main run. [ASSUMPTION] A weekly run covers most of this.
- **Against copying large projects:** the sample is 16 hand-picked projects, mostly teams with paid infrastructure (Ruff's larger runners, Rust's own machine pool, Develocity servers) and organisation accounts. The solo projects in the sample (ripgrep, fd, fzf, ShellCheck, type-fest) run one simple workflow with no cache, no sharding and no path filters, and are excellent projects.
- **Against trusting the figures:** every web quotation passed through a summarising tool. Plan and price sentences that decide a purchase should be re-read on the live page.
