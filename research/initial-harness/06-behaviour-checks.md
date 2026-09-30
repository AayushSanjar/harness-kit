# 06 — Automated behaviour and visual checks for web interfaces, including Atlassian Forge (status on 26 September 2026)

**Sources and how they were selected.** This file cites 64 sources.
- **Selection order.** Official documentation first: playwright.dev, code.claude.com, developer.atlassian.com and anthropic.com. Then GitHub repositories and the Atlassian Developer Community forum. Then research papers on arXiv about models judging screenshots.
- **How they were found.** A research sub-agent ran about 51 searches, such as "Forge UI Kit unit testing", "Forge e2e testing Playwright 2FA" and "MLLM-as-a-judge web", and about 170 page fetches. This was targeted searching, not a systematic review.
- **What I re-checked.** I re-read the Forge changelog entries on the dashboard modules myself. Everything else is labelled "[VERIFIED as read by a sub-agent]" when the sub-agent read the primary page, or [PARTIAL].
- **What was actually seen.** No screenshots or images were viewed by me or by the sub-agent; everything comes from page text.
- URLs omit "https://".

**Labels.** [VERIFIED] means a primary page says this. [PARTIAL] means a secondary source or partial support. [ASSUMPTION] means my inference. NOT FOUND means I searched and found nothing. Statements about how this research was done, definitions in the short term lists or paragraphs, and numbered steps that are instructions are not research claims and carry no label. A label on the line that introduces a table applies to every row of that table.

**Terms used in this file.**
- A **behaviour check** asserts what the application does: this button saves, this list shows ten items.
- A **visual check** asserts what it looks like.
- A **baseline** (also called a golden master or approved fixture) is a stored expected output that a human approved. A new result is compared against it.
- **Playwright** is Microsoft's browser-automation and test framework.
- **MCP** (Model Context Protocol) is the standard way to give an AI model tools; a **Playwright MCP server** lets a model drive a browser.
- **Forge** is Atlassian's platform for apps that run inside Jira and Confluence.
- **UI Kit** is Forge's option where Atlassian's own components draw your screen.
- **Custom UI** is Forge's option where your own HTML and JavaScript run in a sandboxed frame (an iframe) inside Jira.
- A **resolver** is a Forge backend function that the front end calls.
- **`@forge/bridge`** is the library a Forge front end uses to talk to Jira and to its own backend.
- A **TOTP** is the six-digit time-based code from an authenticator app.

---

## Read first: findings that change the plan for the Forge gadget

1. **The module is deprecated.**
   - Atlassian's changelog says `jira:dashboardGadget` and `jira:dashboardBackgroundScript` are now deprecated and will be removed on 17 May 2027. [VERIFIED | developer.atlassian.com/platform/forge/changelog | entries of 2026-09-22 and 2026-09-23]
   - They are replaced by `dashboards:widget` and `dashboards:backgroundScript`, which were declared generally available on 22 September 2026. The new Jira dashboard experience rolls out from 23 September 2026. [VERIFIED | developer.atlassian.com/platform/forge/changelog | entries of 2026-09-22 and 2026-09-23]
   - Atlassian says it will provide migration tooling. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/jira-dashboards-upcoming-changes-and-new-forge-dashboard-widget-module-general-availability/102826 | 2026-09-23]
   - The `dashboards:widget` reference page still showed an Early Access banner and an opt-in beta note when read, and the old gadget page had no deprecation notice yet. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/dashboard-widget | last updated 2026-09-08]
2. **UI Kit cannot be rendered locally for tests.** In an Atlassian community thread, an Atlassian staff member wrote: "UI Kit 2 components can't be rendered locally for testing purposes." In April 2025 the same person said test support was on the backlog with no firm date. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/ui-kit2-unit-testing-jsx-components/75091 | 2023-12-06 and 2025-04-17]
3. **There is no official Forge unit-testing guide.** NOT FOUND after searching developer.atlassian.com for unit testing, Jest, and mocking `@forge/api` or `@forge/bridge`.
4. **Atlassian's Forge MCP server answers documentation questions only.** It does not run CLI commands, tests, deployments or log queries. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/forge-mcp | last updated 2026-08-28]
5. **Anthropic's November 2025 harness used Puppeteer, not Playwright.** Its end-to-end testing ran through the Puppeteer MCP server; the March 2026 harness used Playwright MCP. [VERIFIED | anthropic.com/engineering/effective-harnesses-for-long-running-agents | 2025-11-26; anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]

---

## 1. Browser automation for agents

- **Playwright Test (scripted tests).**
  - Its assertions wait for conditions ("web-first assertions"), each test is isolated, and third-party services should be mocked. [VERIFIED as read by a sub-agent | playwright.dev/docs/best-practices | accessed 2026-09-26]
  - With retries on, a test that fails and then passes is reported as "flaky", separately from passed and failed, so non-determinism is measured. [VERIFIED as read by a sub-agent | playwright.dev/docs/test-retries | accessed 2026-09-26]
- **Playwright MCP server.**
  - A model drives the browser through accessibility-tree snapshots instead of pixels. Optional assertion tools can be switched on with `--caps=testing`. `--storage-state` loads a saved login. [VERIFIED as read by a sub-agent | github.com/microsoft/playwright-mcp | observed 2026-09-26; the distinction is ASSUMPTION]
  - The deterministic part is how an action is applied, not which actions the model chooses. [VERIFIED as read by a sub-agent | github.com/microsoft/playwright-mcp | observed 2026-09-26; the distinction is ASSUMPTION]
- **Playwright's own advice for coding agents.** Playwright now recommends its command-line tool over MCP for coding agents, because it uses fewer tokens. [VERIFIED as read by a sub-agent | playwright.dev/docs/getting-started-cli | accessed 2026-09-26]
- **Playwright Test Agents** (planner, generator, healer) can be set up for Claude Code. The healer can patch or skip failing tests, so its edits need the same review as any test edit. [VERIFIED as read by a sub-agent | playwright.dev/docs/test-agents | accessed 2026-09-26; the review point is ASSUMPTION]
- **Chrome DevTools MCP** gives an agent performance traces, network and console data, screenshots and Lighthouse audits in a live Chrome. It collects usage statistics by default. [VERIFIED as read by a sub-agent | github.com/ChromeDevTools/chrome-devtools-mcp | observed 2026-09-26]
- **Claude in Chrome** (`claude --chrome`) uses your visible, logged-in Chrome. It pauses at logins and CAPTCHAs, and it needs a direct Anthropic plan login rather than an API key. That makes it a tool for interactive checks, not unattended CI. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/chrome | accessed 2026-09-26; the conclusion is ASSUMPTION]
- **Ranking by determinism** [ASSUMPTION]: Playwright Test scripts, then the Playwright command-line tool or MCP, then Claude in Chrome.
  - Counter-case: the less deterministic, exploratory tools find the bugs nobody wrote tests for, as both Anthropic articles report. [ASSUMPTION]
  - Pattern: explore with an agent, then turn each finding into a scripted Playwright test. [ASSUMPTION]

## 2. Screenshot comparison (visual checks)

- **How `toHaveScreenshot()` works.**
  - With no baseline, the first run fails and writes one. Baselines are named per browser and platform. [VERIFIED as read by a sub-agent | playwright.dev/docs/test-snapshots | accessed 2026-09-26]
  - Rendering varies with operating system, version, settings, hardware, power source and headless mode, so baselines must be made in the same environment they are checked in. [VERIFIED as read by a sub-agent | playwright.dev/docs/test-snapshots | accessed 2026-09-26]
  - The default tolerance `threshold` is 0.2. Animations are disabled by default. `mask` hides dynamic regions. [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-pageassertions | accessed 2026-09-26]
- **A trap for agents.** The `updateSnapshots` setting defaults to "missing", so a run writes any missing baseline. An agent that runs the suite twice passes the second time against a baseline it created itself. Set it to "none" for CI and agent runs, with baselines committed. [VERIFIED as read by a sub-agent for the default | playwright.dev/docs/api/class-testconfig | accessed 2026-09-26; the risk and the fix are ASSUMPTION]
- **Docker is not a complete fix.** The official Docker image should be pinned to the same version as `@playwright/test`. [VERIFIED as read by a sub-agent | playwright.dev/docs/docker | accessed 2026-09-26] A Playwright maintainer said ARM and Intel images produce different screenshots, so an Apple-silicon Mac and an x86 CI runner can disagree even with the same image tag. [VERIFIED as read by a sub-agent | github.com/microsoft/playwright/issues/13873 | 2022-05]
  - Practical consequence [ASSUMPTION]: generate and check baselines only in CI, never on the Mac.
- **ARIA snapshots** (`toMatchAriaSnapshot`) compare the page's accessibility tree against a YAML template: roles, names and states. [VERIFIED as read by a sub-agent | playwright.dev/docs/aria-snapshots | accessed 2026-09-26]
  - They are far less sensitive to fonts and operating system than pixels, but miss purely visual defects such as overlaps or wrong colours. [ASSUMPTION]
- **Hosted tools:**
  - Chromatic, with Storybook; its free tier is 5,000 snapshots a month. [VERIFIED as read by a sub-agent | chromatic.com/pricing | accessed 2026-09-26]
  - Percy, which approves baselines in its web interface. [VERIFIED as read by a sub-agent | browserstack.com/docs/percy/overview/visual-testing-basics | accessed 2026-09-26]
  - Applitools, whose "99.9% of false positives" figure is a vendor claim I could not verify. [PARTIAL | applitools.com/platform/eyes | accessed 2026-09-26]
  - BackstopJS: maintenance status unclear; its README and its releases page disagree about the latest version. [PARTIAL | github.com/garris/BackstopJS | observed 2026-09-26]
  - Lost Pixel: archived on 2026-04-22. [VERIFIED as read by a sub-agent | github.com/lost-pixel/lost-pixel | archived 2026-04-22]

## 3. Approved fixtures, and stopping the agent from approving its own output

- **Approval testing.** ApprovalTests writes a "received" file and passes only if it matches the committed "approved" file; a human approves by renaming one to the other. [VERIFIED as read by a sub-agent | github.com/approvals/ApprovalTests.Java (GettingStarted) | observed 2026-09-26] The project's own AGENTS.md tells AI agents never to update approved files and always to ask the user. [VERIFIED as read by a sub-agent | github.com/approvals/ApprovalTests.Java/blob/master/AGENTS.md | observed 2026-09-26]
- **Snapshot testing.** Jest snapshots must be committed and reviewed. With `--ci`, Jest fails on a missing snapshot instead of writing it. [VERIFIED as read by a sub-agent | jestjs.io/docs/snapshot-testing; jestjs.io/docs/cli | accessed 2026-09-26]
- **Why a permission rule is not enough.** An `Edit(...)` deny rule blocks Claude's edit tools, recognised shell file commands and redirects. It does not block a test runner that rewrites files itself, such as `playwright test -u` or `jest -u`. [VERIFIED for the rule | code.claude.com/docs/en/permissions | accessed 2026-09-26; the test-runner example is ASSUMPTION]
- **Layered protection** [ASSUMPTION; each layer's mechanism is VERIFIED in 02]:
  1. An instruction in CLAUDE.md. This is advisory only. [ASSUMPTION; each layer's mechanism is VERIFIED in 02]
  2. An Edit deny rule on the baseline folders, plus a PreToolUse hook that blocks snapshot-update commands. The hook is a speed bump, because commands can be wrapped. [ASSUMPTION; each layer's mechanism is VERIFIED in 02]
  3. The sandbox with a write-deny on baseline folders, in strict mode. The operating system then blocks subprocess writes too. [VERIFIED for `sandbox.filesystem.denyWrite` as read by a sub-agent | code.claude.com/docs/en/sandboxing | accessed 2026-09-26]
  4. CI runs with `--ci` or `updateSnapshots: 'none'`, so a missing baseline fails. [ASSUMPTION; each layer's mechanism is VERIFIED in 02]
  5. A CI check fails when files under the baseline folders change without an approval label. GitHub CODEOWNERS can also require review, but code-owner review on private repositories needs a paid GitHub plan. [VERIFIED as read by a sub-agent | docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners | accessed 2026-09-26]
  - Only layers 4 and 5 are fully outside the agent's reach. [ASSUMPTION; each layer's mechanism is VERIFIED in 02]
  - Counter-case: every layer adds friction to legitimate updates. A solo developer may be served by layers 3 to 5 plus reading every baseline diff. [ASSUMPTION]
- **Existing workflows for regenerating baselines.** In primer/react, adding an "update snapshots" label regenerates screenshots inside CI's Docker image and a bot commits them. [VERIFIED as read by a sub-agent | github.com/primer/react/pull/7391 | merged 2026-01-07]

## 4. Testing Atlassian Forge apps

**Local development loop.**
- `forge tunnel` runs your app code locally and forwards calls from the Atlassian site to it. The app must be deployed and installed first; code changes rebundle automatically, but manifest changes need `forge deploy`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
- UI Kit changes need a page refresh. Custom UI can proxy to a local development server with hot reload, through `tunnel.port` in the manifest. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
- **Tunnel limits** [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]:
  - Custom UI tunnelling works only in Chrome and Firefox. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
  - The app UI is reachable only from the machine running the tunnel. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
  - Tunnelled resolvers never time out, unlike deployed ones. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
  - Logs during tunnelling do not appear in `forge logs`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
  - Local Node must match the manifest runtime. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/tunneling | last updated 2026-08-26]
- Docker is no longer needed for the tunnel, from CLI version 10.1.1. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/forge-tunnel-command-works-without-docker/85481 | 2024-10-22]

**Environments, deployment and sites.**
- There are three default environments: development, staging and production. Tunnelling is not allowed in staging or production. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/environments-and-versions | last updated 2024-10-30]
- `forge deploy` runs `forge lint` first, creates a new version, and supports `--non-interactive`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/cli-reference/deploy | accessed 2026-09-26]
- `forge install` takes a site, product and environment, and `--upgrade` after scope changes. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/cli-reference/install | accessed 2026-09-26]
- `forge lint` lists missing permission scopes, and `--fix` adds them. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/cli-reference/lint | accessed 2026-09-26]
- A free developer site is obtained through go.atlassian.com/cloud-dev. It includes Jira for 5 users, and Atlassian says to use it only for development and testing. I did not sign up. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/marketplace/getting-started | last updated 2026-04-21]
- `forge install --demo-site` creates a site with seeded data that lasts 90 days by default. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/getting-started | last updated 2026-08-26]
- CI authenticates with the `FORGE_EMAIL` and `FORGE_API_TOKEN` environment variables. Atlassian's pipeline example lints, deploys to staging non-interactively, and makes production deploys manual. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/set-up-cicd | last updated 2025-12-11]
- Each Forge CLI version is supported for six months, so a pinned CLI in CI must be refreshed at least that often. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/cli-reference | accessed 2026-09-26]

**Unit and component testing.**
- **Custom UI** can be tested standalone with Jest, React Testing Library and a mock of `@forge/bridge`, because the bridge only works inside an Atlassian product. [VERIFIED as read by a sub-agent for the staff statement | community.developer.atlassian.com/t/bridgeapierror-unable-to-establish-a-connection-with-the-custom-ui-bridge/82212 | 2024-07-30; the testing approach is shown in the examples below]
- **UI Kit** components cannot be rendered locally (see "Read first", item 2). [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/how-do-i-write-tests-for-resolvers/91821 | 2025-05-08]
  - A community simulator, ryanackley/forge-sim, claims to run UI Kit code through the real `@forge/react` renderer and to mock Forge APIs. It has 5 stars, says it is not affiliated with Atlassian, and was not tested by me. [VERIFIED as its README's claims, as read by a sub-agent | github.com/ryanackley/forge-sim | observed 2026-09-26]
- **Resolvers.** An Atlassian staff member advised calling the exported resolver handler directly, rather than mocking `@forge/resolver`. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/how-do-i-write-tests-for-resolvers/91821 | 2025-05-08]
- **Storage.** A local emulator for Forge storage is only a proposal (RFC-148), with feedback closing 2026-10-01. [VERIFIED as read by a sub-agent | community.developer.atlassian.com/t/rfc-148-local-forge-storage-prototype-for-kvs-and-sql/102858 | 2026-09-24]

**Gadget and widget specifics.**
- The gadget module has a view mode and an edit (configuration) mode. Edit mode saves with `view.submit(...)`, and view mode reads the saved `gadgetConfiguration` from the context. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/jira-dashboard-gadget | last updated 2025-08-12]
- The new widget module uses `widgetEdit.onSave()`, and exposes layout width and height through `useWidgetContext()`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/dashboard-widget | last updated 2026-09-08]
- Edit mode and view mode are joined by a contract: whatever edit mode saves, view mode must be able to read. Unit tests can drive both by mocking the context. Only a test inside Jira proves the save works end to end. [ASSUMPTION]

**End-to-end tests against a real Jira site.**
- Playwright's pattern is to log in once, save the storage state (cookies and local storage), reuse it in every test, and never commit it. [VERIFIED as read by a sub-agent | playwright.dev/docs/auth | accessed 2026-09-26]
- Atlassian's support article says automated test logins trigger emailed one-time codes. The fix is to turn on two-step verification with an authenticator app on the test account and generate the TOTP inside the test. The article warns that these workarounds may stop working. [VERIFIED as read by a sub-agent | support.atlassian.com/atlassian-cloud/kb/emailed-otp-marketplace-partners-automation-guide-for-e2eend-to-end-testing-using-two-step-verification2sv-mfa-2fa | updated 2025-09-25]
- Atlassian's Acceptable Use Policy prohibits circumventing security or authentication measures. A low-volume suite that logs in with real credentials and a TOTP does not obviously breach it, but bypassing verification would. This is not legal advice. [VERIFIED for the policy text as read by a sub-agent | atlassian.com/legal/acceptable-use-policy | effective 2025-10-07; the reading is ASSUMPTION]
- Atlassian's own end-to-end example uses WebdriverIO: it logs in through the page, switches into the Custom UI iframe, and allows for the "(Development)" title suffix. [VERIFIED as read by a sub-agent | atlassian.com/blog/development/end-to-end-testing-for-confluence-forge-apps | 2023-08-01, modified 2024-11-18]

**AI tooling from Atlassian.**
- The Forge MCP server is documentation only (see "Read first", item 4). [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/forge-mcp | last updated 2026-08-28]
- The Forge Skills plugin (`/plugin install forge-skills@atlassian-forge-skills`) bundles skills for building, reviewing, debugging and securing apps. None of them covers automated testing. Its debugger skill leaves `forge login` and `forge tunnel` to the user. [VERIFIED as read by a sub-agent | github.com/atlassian/forge-skills | observed 2026-09-26]

## 5. Community examples

- **atlassian/jenkins-for-jira**, an Atlassian-built Forge app, tests its Custom UI with Jest and React Testing Library, using a manual mock of `@forge/bridge`. Whether its tests pass was not verified. [VERIFIED as read by a sub-agent | github.com/atlassian/jenkins-for-jira | observed 2026-09-26]
- **remarkablemark/jira-dashboard-gadget**, a Custom UI gadget, mocks `@forge/bridge` globally, including `view.submit` for edit mode. Its CI requires 100% test coverage. Its `forge lint` step is commented out, and it has no deploy step. [VERIFIED as read by a sub-agent | github.com/remarkablemark/jira-dashboard-gadget | observed 2026-09-26]
- **Forum threads:**
  - Selenium was found fragile and Cypress unable to handle the iframes. [PARTIAL | community.developer.atlassian.com/t/forge-e2e-testing/61467 | 2022-09 to 2024-05; community.developer.atlassian.com/t/testing-forge-custom-ui-components-using-jest/50320 | 2021-07-27 to 2023-01-10; community.developer.atlassian.com/t/forge-e2e-testing-and-2fa-with-playwright/94824 | 2025-08-27]
  - Jest's "Cannot find module '@forge/bridge'" error was solved with a manual mock. [PARTIAL | community.developer.atlassian.com/t/forge-e2e-testing/61467 | 2022-09 to 2024-05; community.developer.atlassian.com/t/testing-forge-custom-ui-components-using-jest/50320 | 2021-07-27 to 2023-01-10; community.developer.atlassian.com/t/forge-e2e-testing-and-2fa-with-playwright/94824 | 2025-08-27]
  - One asker reported that Playwright with a TOTP login worked. [PARTIAL | community.developer.atlassian.com/t/forge-e2e-testing/61467 | 2022-09 to 2024-05; community.developer.atlassian.com/t/testing-forge-custom-ui-components-using-jest/50320 | 2021-07-27 to 2023-01-10; community.developer.atlassian.com/t/forge-e2e-testing-and-2fa-with-playwright/94824 | 2025-08-27]
- **A public repository running Playwright end-to-end or visual tests against a Forge app on a real Jira site, with visible passing CI:** NOT FOUND.

## 6. Visual judgement by an AI model

- **Pair comparison beats absolute scoring.**
  - Multimodal judges agreed with humans about 78–79% of the time when comparing two outputs, but less when giving absolute scores (about 70%). [VERIFIED as read by a sub-agent | arxiv.org/abs/2402.04788 | 2024]
  - On 654 pairs of web implementations, the best judge (Claude 4 Sonnet) agreed with humans 66% of the time, against 85% between human experts. [VERIFIED as read by a sub-agent | arxiv.org/abs/2510.18560 | 2025-10-21]
- **Fine spatial detail is weak.** Vision models failed on simple geometry when shapes overlapped or sat close together. [VERIFIED as read by a sub-agent | arxiv.org/abs/2407.06581 | 2024-07-09]
- **Models favour their own output.** They rate their own outputs higher than others' that humans rate equal. [VERIFIED as read by a sub-agent | proceedings.neurips.cc/paper_files/paper/2024/hash/7f1f0218e45f5414c79c0679633e47bc-Abstract-Conference.html | NeurIPS 2024, Panickssery, Bowman and Feng]
- **Screenshots are downscaled.** Anthropic's guidance says images above the size limit are shrunk before the model sees them, so one- or two-pixel regressions in a full-page screenshot may be invisible to the model. [VERIFIED for the limits as read by a sub-agent | claude.com/blog/best-practices-for-computer-and-browser-use-with-claude | 2026-05-13; the consequence is ASSUMPTION]
- **When to use which** [ASSUMPTION]:
  - If an approved baseline exists and the question is "did anything change?", use pixel comparison generated in CI, or ARIA snapshots. [ASSUMPTION]
  - If there is no baseline, or the question is "does it match the design?", use a model judge in a separate session. Give it the spec and a reference image, compare pairs rather than scoring alone, and leave final approval to a human. [ASSUMPTION]
  - Counter-case: pixel checks raise false alarms across machines, and ARIA checks miss visual defects. Only the model can notice meaning-level problems such as a wrong chart. [ASSUMPTION]

## 7. What this suggests for the Forge gadget harness

[ASSUMPTION; each step has its counter-case]
1. **Decide the module first.** Build on `dashboards:widget` unless your developer site cannot show the new dashboards yet. [ASSUMPTION; each step has its counter-case]
   - Counter-case: the old gadget module keeps working during the rollout, until May 2027, and Atlassian promises migration tooling. [ASSUMPTION]
2. **Prefer Custom UI if automated tests matter most.** It can be unit-tested and snapshot-tested with standard tools by mocking `@forge/bridge`. UI Kit can only be tested inside Jira, or through an unofficial simulator. [ASSUMPTION; each step has its counter-case]
   - Counter-case: UI Kit gives Atlassian's look, accessibility and security model with less code. [ASSUMPTION]
3. **Put the fast checks inside the agent's loop.** These are unit tests, resolver tests, `forge lint`, and ARIA snapshots of the rendered widget. Keep them short enough to run in a Stop hook. [ASSUMPTION; each step has its counter-case]
4. **Run the slow checks in CI.** This is Playwright against a development-environment install on a developer site, with a TOTP login, baselines generated in CI, and `updateSnapshots: 'none'`. [ASSUMPTION; each step has its counter-case]
5. **Protect the baselines with the layered approach in section 3.** Use a model judge only for "matches the design" questions, never as the only gate. [ASSUMPTION; each step has its counter-case]

## Negative results

- **An official Forge unit-testing guide:** NOT FOUND.
- **An official local renderer or testing utilities for UI Kit:** NOT FOUND.
- **Official Atlassian guidance on Playwright for Forge:** NOT FOUND.
- **An Atlassian statement on CAPTCHAs during automated login:** NOT FOUND.
- **A resize or height API for gadgets:** NOT FOUND. The new widget module exposes layout size.
- **Playwright documentation recommending Docker specifically for screenshot baselines:** NOT FOUND.
- **A public workflow that combines a changed-paths filter with a required label for snapshot folders:** NOT FOUND.
- **A testing skill in Atlassian's Forge Skills plugin:** NOT FOUND.
- **The full rule list for `forge lint`:** NOT FOUND; the linting page returned 404.
