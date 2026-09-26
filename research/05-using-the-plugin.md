# 05 — Using the harness-kit plugin from a separate private project (status on 26 September 2026)

**Sources and how they were selected.** This file cites 41 sources.
- **Documentation.** Anthropic's plugin documentation came first: the install, loading, organisation, marketplace, commands, troubleshooting, security and evals pages, plus the CLI, headless and GitHub Actions pages.
- **Bug reports and fixes.** I searched the anthropics/claude-code and anthropics/claude-code-action issue trackers for each reported bug, in several phrasings, and read the matching release notes.
- **Reports of real use.** I searched for third-party repositories and issues that show someone actually running an installation method.
- **Who read what.** A research sub-agent read about 60 pages. I then re-read these pages myself in raw text on 26 September 2026: plugin loading, organisation, plugin commands, marketplace reference, troubleshooting, security, plugin evals, the CLI reference, the claude-code-action `action.yml`, and release v2.1.232. I also re-opened issues #1229, #80802 and #96121 myself. Items I did not re-check are labelled "[VERIFIED as read by a sub-agent]" or [PARTIAL].
- **What was not done.** I did not install or run anything: that was out of scope for this research. Every "tested" statement below therefore reports someone else's test.
- URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source, a summary-only reading, or partial support. [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**Terms used in this file.**
- A **marketplace** is a catalog file, `.claude-plugin/marketplace.json`, that lists plugins and where to fetch each one.
- A **relative-path plugin** is listed in a marketplace by a path inside the same repository, such as `./`.
- An **external-source plugin** is fetched from somewhere else, such as its own GitHub repository.
- A **scope** is the settings file an install is recorded in:
  - user: `~/.claude/settings.json`;
  - project: `.claude/settings.json`, committed to git;
  - local: `.claude/settings.local.json`, not committed.
- The **workspace trust dialog** is the prompt Claude Code shows the first time you open a folder. Content from the repository is ignored until you accept it.
- The **plugin cache** is `~/.claude/plugins/cache/`, where installed plugins are copied.

---

## 1. Every supported way to install or load the plugin

| # | Method | How | Needs the trust dialog? | Works in `-p` or CI? | Edits picked up without reinstalling? | Label |
|---|---|---|---|---|---|---|
| 1 | Interactive `/plugin` | `/plugin marketplace add <owner>/harness-kit`, then `/plugin install harness-kit@harness-kit`, choosing a scope | No | No; `/plugin` does not run in `-p` | No (copied to the cache) | [VERIFIED as read by a sub-agent \| code.claude.com/docs/en/plugins/install \| accessed 2026-09-26] |
| 2 | Shell commands | `claude plugin marketplace add <source> --scope <s>`, then `claude plugin install <name>@<marketplace> --scope <s>`; exit code 0 or 1 | No | Yes, as a setup step | No | [VERIFIED \| code.claude.com/docs/en/plugins/cli-reference \| accessed 2026-09-26] |
| 3 | Project settings | Commit `extraKnownMarketplaces` and `enabledPlugins` in `.claude/settings.json` | **Yes** | Only in a folder already trusted | Relative-path plugin: yes, from the marketplace clone | [VERIFIED \| code.claude.com/docs/en/plugins/org; code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| 4 | User, local or `--settings` | The same keys in `~/.claude/settings.json`, an untracked `.claude/settings.local.json`, or the `--settings` flag | No | Yes | No | [VERIFIED \| code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| 5 | Local-folder marketplace | `claude plugin marketplace add ./path` or `~/path` | No | Yes | **Yes**: its relative-path plugins load in place at the next session or `/reload-plugins`, with no version bump | [VERIFIED \| code.claude.com/docs/en/plugins/loading; code.claude.com/docs/en/plugins/cli-reference \| accessed 2026-09-26] |
| 6 | `--plugin-dir` | `claude --plugin-dir <folder, .zip, or folder of plugins>`; repeat the flag for several | No | Yes | **Yes**, after `/reload-plugins` | [VERIFIED \| code.claude.com/docs/en/cli-reference; code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| 7 | `CLAUDE_CODE_PLUGIN_DIRS` | An environment variable that acts like `--plugin-dir` (v2.1.280 and later) | No | Yes | Yes | [VERIFIED \| code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26; the version is as read by a sub-agent] |
| 8 | Vendored "skills-directory" plugin | Put the plugin at `.claude/skills/harness-kit/` with its `.claude-plugin/plugin.json` | **Yes**; `-p` alone is not enough | No, unless trusted | Yes (loads in place) | [VERIFIED \| code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| 9 | Git submodule or vendored copy | Load the copy through method 5, 6 or 8 | Depends on the method | Depends | Depends | [ASSUMPTION, built on the verified rows 5, 6 and 8] |
| 10 | Seed folder (containers, CI) | Build with `CLAUDE_CODE_PLUGIN_CACHE_DIR=<dir>` and the install commands; run with `CLAUDE_CODE_PLUGIN_SEED_DIR=<dir>`; still needs `enabledPlugins` | No | Yes | No (read-only; auto-update forced off) | [VERIFIED \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] |
| 11 | GitHub Action inputs | `plugin_marketplaces` and `plugins` on `anthropics/claude-code-action@v1` | No | Yes | No | [VERIFIED \| raw.githubusercontent.com/anthropics/claude-code-action/main/action.yml \| observed 2026-09-26] |
| 12 | Agent SDK `plugins` option | The SDK equivalent of `--plugin-dir` | No | Yes | Yes | [VERIFIED \| code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| 13 | Managed settings, or plugins synced from claude.ai | Organisation-level; not needed for a solo developer | No | Yes | No | [VERIFIED \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] |

**Two rules that explain most surprises.**
- **Which settings actually trigger a download.** Claude Code downloads an external-source plugin only when one of these enables it: user settings, an untracked `.claude/settings.local.json`, the `--settings` flag, or managed settings. Project settings alone never trigger that download. A relative-path plugin needs no download record, because it loads from the marketplace copy. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **Name conflicts.** A `--plugin-dir` copy silently replaces an installed marketplace plugin with the same manifest name, and `claude plugin list` still shows the marketplace copy as enabled. Only the `--debug` log records the override. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]

**A documentation inconsistency.** The install page is reported to say every collaborator must run `claude plugin install … --scope project` once. It does not make the relative-path exception that the loading and organisation pages make. [PARTIAL | code.claude.com/docs/en/plugins/install | accessed 2026-09-26; as read by a sub-agent]

## 2. Making one repository both the marketplace and the plugin

- **The marketplace file.** `marketplace.json` lives in `.claude-plugin/`. Its required keys are `name`, `owner` (with `owner.name`) and `plugins`, and each entry needs `name` and `source`. [VERIFIED | code.claude.com/docs/en/plugins/marketplace-reference | accessed 2026-09-26]
- **One repository, two roles.** The repository can serve both roles. A marketplace entry whose `source` is `./` points at the repository root, where `.claude-plugin/plugin.json` also lives. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/publish | accessed 2026-09-26; the path rule is VERIFIED | code.claude.com/docs/en/plugins/marketplace-reference | accessed 2026-09-26]
- **Keep the entry name and the manifest name the same.** The entry name is the install id and the `enabledPlugins` key. The manifest name is the prefix on the plugin's skills and the name compared in conflicts. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26] If they differ, installing by the manifest name fails. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugin-marketplaces | accessed 2026-09-26]
- **Do not set `version` in both files.** `plugin.json` wins silently. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/host-marketplace | accessed 2026-09-26]
- **Reserved names.** Reserved marketplace names include Anthropic's own, `inline`, `skills-dir`, `github` and names starting with `claudeai-`. "harness-kit" is not reserved. [VERIFIED | code.claude.com/docs/en/plugins/marketplace-reference | accessed 2026-09-26]
- **A validation gotcha with the single-root layout.** For a folder, `claude plugin validate` checks `marketplace.json` when it exists, and when it validates a marketplace folder it does not open the plugins' skill, agent, command or hook files. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - So with `source: "./"`, running `claude plugin validate .` never checks the plugin's own files. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - Two ways around it:
    1. **Validate the plugin separately.** Pass the plugin manifest file path as well. Whether that also opens `hooks/hooks.json` is not stated (NOT FOUND).
    2. **Put the plugin in a subfolder** such as `plugins/harness-kit/`, with the entry source `./plugins/harness-kit`. Then `claude plugin validate ./plugins/harness-kit --strict` checks the plugin files and `claude plugin validate . --strict` checks the marketplace. [ASSUMPTION, built on the verified validator rules]
  - Counter-case: the subfolder layout makes paths longer, and anything the plugin needs at run time, such as templates, must live inside that subfolder, because files outside the plugin folder are not copied into the cache. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]

## 3. Pinning and updating versions

- **How Claude Code decides the version** [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]:
  - It uses `version` in `plugin.json` first, then `version` in the marketplace entry. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - With neither, it uses a commit SHA. For a relative-path plugin inside a git-hosted marketplace, that is the commit SHA of the installed folder. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - An update installs only when this computed version changes. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - So a fixed `version` string keeps everyone on the cached copy until you change the string. Leaving `version` out makes every commit a new version. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **Pinning the marketplace itself.** `claude plugin marketplace add <owner>/harness-kit#<ref>` (or `@<ref>`) clones the repository pinned to a branch or tag. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26] In settings, the marketplace source takes a `ref`. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/marketplace-reference | accessed 2026-09-26]
- **Pinning an external plugin to an exact commit.** An external plugin entry can pin `sha`, a full 40-character commit. When both `ref` and `sha` are set, `sha` is checked out. [VERIFIED | code.claude.com/docs/en/plugins/marketplace-reference | accessed 2026-09-26]
- **Auto-update** [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]:
  - It runs only in interactive sessions, after a random delay of up to ten minutes following your first message. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - It is off by default for third-party marketplaces such as harness-kit. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - `DISABLE_AUTOUPDATER=1` and similar variables switch it off, unless `FORCE_AUTOUPDATE_PLUGINS=1` is also set. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **Updating by hand.** `claude plugin update harness-kit@harness-kit` refreshes the marketplace and installs only if the computed version changed. The new copy loads in the next session or after `/reload-plugins`. Until then, running hooks and MCP servers keep the old path. Old version folders are deleted 14 days later. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **Moving a pin.** When a declared marketplace's source changes in settings, for example a new `ref`, Claude Code re-fetches it and shows a notice that plugins changed. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **One registry per user.** There is one `known_marketplaces.json` per user, so a marketplace added in one project is available in every project. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26] A third-party test found that pinning different refs in different repositories on one machine does not isolate them: whichever repository registered the marketplace first wins (v2.1.267). [PARTIAL | github.com/misnaej/forge/issues/553 | 2026-09-10]
- **Security of commit pins.** Researchers reported that a branch named exactly like a pinned SHA could replace the pinned commit ("Plugin4Shell"), and that this was fixed in v2.1.179. I did not find Anthropic's own confirmation. [PARTIAL | helpnetsecurity.com/2026/09/18/plugin4shell-ai-coding-agents-vulnerability | 2026-09-18]

## 4. Getting the plugin into GitHub Actions CI of the private project

| Option | How | Documented? | Reported to work in real CI? | Main risk |
|---|---|---|---|---|
| A. Checkout plus `--plugin-dir` | Check out harness-kit with `actions/checkout`, pinned to a full commit SHA, into a subfolder. Run `claude -p … --plugin-dir ./harness-kit` in a step. | Yes: `--plugin-dir` is the documented flag for `-p` runs [VERIFIED \| code.claude.com/docs/en/cli-reference \| accessed 2026-09-26] | NOT FOUND in CI. A reporter ran `claude -p --plugin-dir` locally on v2.1.218 and the plugin loaded (#80802). [VERIFIED \| github.com/anthropics/claude-code/issues/80802 \| observed 2026-09-26] | No Node dependency install for folders loaded in place [VERIFIED \| code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] |
| B. Action with a local-folder marketplace | Check out harness-kit, then `plugin_marketplaces: ./harness-kit` and `plugins: harness-kit@harness-kit` | Yes: local paths were added by pull request #761 (merged 2026-01-05) [VERIFIED as read by a sub-agent \| github.com/anthropics/claude-code-action/pull/761 \| merged 2026-01-05] | The plugin inputs are used in real CI runs: installs broke on 2026-05-05/06 through an installer regression, and users confirmed the fix. [PARTIAL \| github.com/anthropics/claude-code-action/issues/1290 \| 2026-05-06] | Installs at user scope on the runner and stops at the first failure [VERIFIED as read by a sub-agent from the action's source | github.com/anthropics/claude-code-action | observed 2026-09-26] |
| C. Action with the GitHub URL | `plugin_marketplaces: https://github.com/<owner>/harness-kit.git` | Yes [VERIFIED \| raw.githubusercontent.com/anthropics/claude-code-action/main/action.yml \| accessed 2026-09-26] | Yes for other repositories: datalogix/workflows installs its own plugin this way [VERIFIED as read by a sub-agent \| raw.githubusercontent.com/datalogix/workflows/main/.github/workflows/claude.yml \| observed 2026-09-26] | **Cannot pin a ref**: the request is open (#1229) [VERIFIED \| github.com/anthropics/claude-code-action/issues/1229 \| observed 2026-09-26] |
| D. Seed folder in a container image | Install into a seed at image build time and point `CLAUDE_CODE_PLUGIN_SEED_DIR` at it | Yes [VERIFIED \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] | NOT FOUND | Needs a custom image |
| E. Project settings plus pre-trust | Mark the checkout trusted with `hasTrustDialogAccepted` in `~/.claude.json`, and set `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1` | The mechanism is documented [VERIFIED \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] | NOT FOUND | Editing `~/.claude.json` in CI is an unusual path [ASSUMPTION] |

**Checking in CI that the harness really loaded.**
- Run with `--output-format stream-json --verbose`. The first event lists the loaded plugins, and failures appear under `plugin_errors`. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26; `plugin_errors` VERIFIED as read by a sub-agent | code.claude.com/docs/en/headless | accessed 2026-09-26]
- Make the job fail if `harness-kit` is missing or if any error is listed. [ASSUMPTION]
- A public harness-kit needs no token. Only a private marketplace would need `GH_TOKEN` and `gh auth setup-git`. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]

## 5. Developing the plugin and the project side by side, without pushing after every edit

- **The basic loop.** Start Claude in the project folder with `claude --plugin-dir <path to your local harness-kit clone>`. After each edit to the plugin, run `/reload-plugins`. No push and no version bump is needed, because the folder loads in place. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26; `/reload-plugins` VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
- **What reloading covers.** `/reload-plugins` reloads skills, agents, hooks, and plugin MCP and LSP servers. A reload that adds or removes MCP tools waits for `--force`, because it invalidates the prompt cache. Monitors need a full restart. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26; VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **An alternative.** Register the local clone as a local-folder marketplace; its relative-path plugins also load in place. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26] Adding it under the same name as a marketplace already declared in settings with a network source is refused. [VERIFIED | code.claude.com/docs/en/plugins/troubleshooting | accessed 2026-09-26]
- **Gotchas.**
  - `--plugin-dir` silently shadows an installed copy with the same name (section 1). [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - The `userConfig` dialog does not appear with `--plugin-dir`; use `/plugin configure`. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/create | accessed 2026-09-26]
  - Node dependencies are not installed for folders loaded in place. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
  - Paths above the plugin root work under `--plugin-dir` but break once the plugin is copied into the cache. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
- **Open bugs that affect this loop.**
  - #80802 (open, v2.1.218): a plugin skill invoked through the Skill tool gets no SKILL.md body, with `--plugin-dir` or installed. [VERIFIED | github.com/anthropics/claude-code/issues/80802 | observed 2026-09-26]
  - #97043 (opened 2026-09-25): typing a plugin command without its prefix gives "Unknown command". Use the full `/harness-kit:<command>` form. [PARTIAL | github.com/anthropics/claude-code/issues/97043 | 2026-09-25]

## 6. Validating the plugin automatically

- **`claude plugin validate <path> [--strict] [--json]`** [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - Exit codes: 0 means passed, 1 means failed (with `--strict`, warnings count as failures), and 2 means the validator itself crashed. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - It checks the manifest schema and fields, component paths, the frontmatter of skills, agents and commands, and hook files, and it warns about a root `CLAUDE.md`. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26; VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/troubleshooting | accessed 2026-09-26]
  - It does not check the plugins' files in a marketplace run (section 2). [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
  - Two third-party reports say it runs on a CI runner without any login or API key (v2.1.248 and v2.1.274). [PARTIAL | github.com/MalcolmMcNeely/skills-marketplace/issues/19; github.com/codenamev/ai-software-architect/issues/61 | 2026-09-09 and 2026-09-17]
- **`claude plugin eval`** runs model-based behaviour tests. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Each case runs three times with the plugin and three times without it. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - For CI, use `--trust-plugin`, `--json`, `--threshold`, `--max-cost-usd` and `--no-publish`, and pin the model. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Exit codes: 0 means passed, 1 means failed, 2 means a partial run. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Every run is a real, paid model call. [VERIFIED | code.claude.com/docs/en/plugin-evals | accessed 2026-09-26]
  - Issue #96121 (open): the evaluation sandbox does not load the plugin's own agents. [VERIFIED | github.com/anthropics/claude-code/issues/96121 | 2026-09-22]
- **JSON schemas.**
  - SchemaStore hosts schemas for `plugin.json` and `marketplace.json`. They were generated on 2026-04-23 and appear to lack newer fields. [PARTIAL | schemastore.org/claude-code-plugin-manifest.json | generated 2026-04-23]
  - The schema URL used by Anthropic's official marketplace returned 404 when a sub-agent fetched it, and a third-party issue reports the same. [VERIFIED as read by a sub-agent | github.com/eranroseman/agent-plugins/issues/58 | 2026-09-18]
  - Treat `validate --strict` as the authority. [ASSUMPTION]
- **How Anthropic's official marketplace validates.** A workflow runs a shared validation action on pull requests. It installs the latest Claude Code, runs `claude plugin validate`, and adds its own rules, for example https-only sources and a 40-character SHA pin for every external source. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/anthropics/claude-plugins-official/main/.github/workflows/validate-plugins.yml | observed 2026-09-26]

## 7. Current status of the bugs the reader had found

| Reported problem | Issues found | Status on 2026-09-26 | Label |
|---|---|---|---|
| (a) Listing a plugin in project settings does not install it | #32606 (closed as not planned); #87030 (open: a project-scope install writes only `enabledPlugins`, not the marketplace); #84402 (open: trust granted to a parent folder was not enough; partly fixed in v2.1.232) | **Now documented behaviour, not a bug.** Project marketplace entries apply after trust. A relative-path plugin then loads. An external-source plugin needs `claude plugin install … --scope project` on each machine. | [VERIFIED docs \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] [PARTIAL issue states \| github.com/anthropics/claude-code/issues/32606 \| 2026-03-09; github.com/anthropics/claude-code/issues/87030 \| observed 2026-09-26; github.com/anthropics/claude-code/issues/84402 \| observed 2026-09-26] |
| (b) Installing from a newly added marketplace fails with "Plugin not found" | #51806 (closed as duplicate) | **Largely fixed in v2.1.232 (2026-08-13).** It can still happen with a bare-name install from the shell, an entry name that differs from the manifest name, or a repository name used instead of the marketplace name. | [VERIFIED \| github.com/anthropics/claude-code/releases/tag/v2.1.232 \| 2026-08-13; code.claude.com/docs/en/plugins/loading \| accessed 2026-09-26] [PARTIAL \| github.com/anthropics/claude-code/issues/51806 \| 2026-04-22] |
| (c) `claude -p` never processes project marketplace settings | #13096, #13097, #12840 (all closed as not planned, December 2025) | **Changed.** `-p` applies them in folders already trusted. A fresh CI checkout is untrusted, so in CI they are still ignored. The version that changed this is NOT FOUND. | [VERIFIED \| code.claude.com/docs/en/plugins/org \| accessed 2026-09-26] [PARTIAL \| github.com/anthropics/claude-code/issues/13096 \| 2025-12-04; github.com/anthropics/claude-code/issues/13097 \| 2025-12-04; github.com/anthropics/claude-code/issues/12840 \| 2025-12-02] |

**Other open plugin problems worth knowing.**
- #96984 (opened 2026-09-25, Windows): plugins enabled through project settings load and work, but are reported as not installed. [PARTIAL | github.com/anthropics/claude-code/issues/96984 | 2026-09-25]
- #80802: plugin skill body not injected (section 5). [VERIFIED | github.com/anthropics/claude-code/issues/80802 | observed 2026-09-26]
- #78234: plugin agents dropped as agent-team teammates. [VERIFIED | github.com/anthropics/claude-code/issues/78234 | 2026-07 (inferred)]

## 8. The most reliable method for a solo developer using the Claude Code CLI on macOS

Each recommendation is my judgement from the evidence [ASSUMPTION], followed by its counter-case.

- **For daily use in the private project:** declare the marketplace and install at project scope with the shell commands, pinned to a release tag. The steps are in section 9. [ASSUMPTION]
  - Why: both commands are documented, run synchronously, return exit codes, and write both settings keys, which sidesteps #87030. Since v2.1.232 the install refreshes the marketplace first. The pin keeps you on a known release, and auto-update is off. [ASSUMPTION]
  - Counter-case 1: if you use harness-kit in several projects at different tags on one Mac, per-project pins may not isolate (section 3). Then use one user-scope pin, or separate marketplace names per channel. [ASSUMPTION]
  - Counter-case 2: if you want every commit immediately, leave out both `version` and the ref pin, and switch on auto-update. [ASSUMPTION]
- **For CI:** Option A (checkout pinned to a commit SHA plus `--plugin-dir`), with the loaded-plugin check. [ASSUMPTION]
  - Why: the pin lives in git, and no trust dialog or background install is involved. [ASSUMPTION]
  - Counter-case: this is not what a user gets from a GitHub install, and it skips the dependency install and the copy to the cache. Add a periodic CI job that installs from GitHub at the release tag with the shell commands (method 2), so the real install path is also tested. [ASSUMPTION]
- **For developing the plugin:** `--plugin-dir` pointing at a local clone, plus `/reload-plugins`. [ASSUMPTION]
  - Counter-case: it bypasses the cache, the `userConfig` dialog, trust and version pinning. It also silently shadows an installed copy. Before each release, run the section-9 method in a clean project. [ASSUMPTION]

## 9. Installation method (tested by others; not by me) and fallback

**Who has tested these steps.**
- **Anthropic's documentation** shows the exact output that `claude plugin marketplace add … --scope project` prints (quoted in step 5 below), which indicates the documentation authors ran it. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
- **Widely used third-party repositories** tell their users to add a GitHub marketplace and then install from it. Examples are obra/superpowers (`/plugin marketplace add obra/superpowers-marketplace`) and trailofbits/skills. [VERIFIED | github.com/obra/superpowers; github.com/trailofbits/skills | observed 2026-09-26]
- **One user reported** on v2.1.281 that plugins enabled through a project's settings load and work. That report was on Windows, with a status-display bug. [PARTIAL | github.com/anthropics/claude-code/issues/96984 | 2026-09-25]
- **What I did not do.** I did not run these steps myself. The macOS-specific run is still untested by me; see 07-open-questions.md, question Q1.

**Primary method: project-scope install from GitHub, pinned to a tag.** In the steps below, `<owner>` means the GitHub account that owns the harness-kit repository.

1. In harness-kit, create `.claude-plugin/plugin.json` with `name` "harness-kit". Also create `.claude-plugin/marketplace.json` with marketplace `name` "harness-kit", an `owner.name`, and one plugin entry named "harness-kit". Give that entry the source `./`, or `./plugins/harness-kit` if you use the subfolder layout from section 2. [VERIFIED rules | code.claude.com/docs/en/plugins/marketplace-reference; code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
2. Validate before every release. Run `claude plugin validate . --strict` for the marketplace, and validate the plugin separately (section 2). Both must exit with 0. [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
3. Choose your versioning rule. Either set `version` in `plugin.json` and change it on every release, or leave it out so that each commit is a new version. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
4. Tag the release in harness-kit, for example `v0.1.0`, and push the tag to GitHub. [ASSUMPTION: a step I recommend]
5. In the private project's root folder on the Mac, run `claude plugin marketplace add <owner>/harness-kit#v0.1.0 --scope project`. Expect "Successfully added marketplace: harness-kit (declared in project settings)". [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
6. Run `claude plugin install harness-kit@harness-kit --scope project`. Always include `@harness-kit`: that form refreshes the marketplace first, while a bare name from the shell does not. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]
7. Start `claude` in the project and accept the workspace trust dialog. Run `/plugin` and confirm that harness-kit is listed with nothing in the Errors tab. Then run `claude plugin list` in a second terminal. [VERIFIED | code.claude.com/docs/en/plugins/org; code.claude.com/docs/en/plugins/troubleshooting | accessed 2026-09-26]
8. Check that the hooks load in a headless run: `claude -p "say ok" --output-format stream-json --verbose`. The first event must list harness-kit under `plugins`, with no `plugin_errors`. [VERIFIED | code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
9. Commit the `.claude/settings.json` that steps 5 and 6 wrote. [ASSUMPTION: a step I recommend]
10. To upgrade later, change the `ref` in `.claude/settings.json` to the new tag; a changed source triggers a re-fetch. Then run `claude plugin update harness-kit@harness-kit --scope project`, and `/reload-plugins` in any open session. [VERIFIED | code.claude.com/docs/en/plugins/loading | accessed 2026-09-26]

**Fallback method: load a local or vendored copy with `--plugin-dir`.** Use this when the primary method fails, or in CI.

1. Put a copy of harness-kit on disk: a local clone, a git submodule inside the project, or, in CI, an `actions/checkout` step pinned to a full commit SHA. [ASSUMPTION: a step I recommend]
2. Run `claude --plugin-dir <path to that copy>` from the project folder, or `claude -p … --plugin-dir <path>` in CI. [VERIFIED | code.claude.com/docs/en/cli-reference | accessed 2026-09-26]
3. Confirm the plugin loaded. It shows as `harness-kit@inline` in `/plugin`, or in the headless first event with no `plugin_errors`. [VERIFIED | code.claude.com/docs/en/plugins/loading; code.claude.com/docs/en/plugins/org | accessed 2026-09-26]
4. After edits, run `/reload-plugins` (section 5). [VERIFIED | code.claude.com/docs/en/plugins/cli-reference | accessed 2026-09-26]
- **Tested by:** Anthropic's own plugin-creation walkthrough uses `--plugin-dir` [VERIFIED as read by a sub-agent | code.claude.com/docs/en/plugins/create | accessed 2026-09-26]. The #80802 reporter ran `claude -p --plugin-dir` on v2.1.218, and the plugin loaded. [VERIFIED | github.com/anthropics/claude-code/issues/80802 | observed 2026-09-26]
- **Counter-case:** it is session-only, easy to forget in interactive use, not version-pinned unless your checkout is, and exposed to bug #80802. [ASSUMPTION]

## Negative results

- **The release that made `-p` honour project marketplaces in trusted folders:** NOT FOUND.
- **A public report of `--plugin-dir` used inside CI:** NOT FOUND. Also not found: any report of it passed through the GitHub Action's `claude_args`.
- **A test of the Action's `settings` input used to carry `extraKnownMarketplaces`:** NOT FOUND.
- **Whether validating `.claude-plugin/plugin.json` directly also checks `hooks/hooks.json`:** NOT FOUND.
- **An Anthropic-hosted JSON schema that resolves:** NOT FOUND; the URL returned 404.
- **Closed dates for most issues:** NOT FOUND. GitHub renders the timeline in the browser, and the sub-agent's API access was refused.
