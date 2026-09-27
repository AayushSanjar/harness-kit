# 06 — Open questions, and what would settle each (status on 27 September 2026)

**Sources and how they were selected.** This file cites 36 sources (distinct web pages), all listed in `sources.csv`.
- **Where the questions come from.** Each question arises from a gap, a conflict or a NOT FOUND in files 01 to 05, and the sources cited are the ones that expose the gap.
- **The proposed ways of settling each question** are my suggestions and are labelled [ASSUMPTION].
- **What I re-read myself.** The pages whose label is VERIFIED without "as read by a sub-agent": the harness-design post, WebDevJudge version 3, DesignPref, WiserUI-Bench, the pairwise-or-pointwise paper, the UI-Lens abstract, the Forge widget context page, Jira's control chart page and Playwright's issue 13873.
- **What was actually seen.** No images were viewed.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. A label on the line that introduces a list applies to every item in it.

**Terms used in this file.**
- **CI** (continuous integration) is the automated server that builds and tests the code on every change.
- A **held-out set** is a group of labelled examples kept aside and never shown to a judge while it is tuned, so that it gives an honest measure of the judge.
- A **fixture** is a fixed, fake data set used for testing. The **dense fixture** is the one with about 400 items defined in `05-template.md`, section W1.2.
- `00-glossary.md` defines every other term.

**How each entry is laid out.** Each question has three parts:
- **Uncertain** says what is not known.
- **Why it matters** says what in the evaluator depends on it.
- **What would settle it** gives a concrete test or source.

The questions are ordered by how much the answer would change the evaluator.

---

## Q1. How well does a Claude-based judge agree with the approving person on this project's own designs?

- **Uncertain.** Every published agreement figure comes from other people, other tasks and other models. They range widely:
  - On 300 UI pairs whose winners came from real A/B tests, GPT-4o was consistent across both presentation orders only 30.11% of the time, against 25% chance. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
  - On 280 tasks with outputs from six models, a judge with a checklist per task agreed with engineers 90.95% of the time. [VERIFIED as read by a sub-agent | arxiv.org/html/2507.04952 | 2025-09-29]
- **Why it matters.** It decides how much of the loop can run without the person.
- **What would settle it.** [ASSUMPTION]
  - Label 60 to 100 designs or pairs, following the judge-building guidance in `04-ai-evaluation.md`, Part G.
  - Measure the judge's true positive rate, true negative rate and Cohen's kappa on a held-out set.
  - Repeat after every change to the rubric.

## Q2. How consistent is the approving person with themselves?

- **Uncertain.** In a study of 20 professional designers rating the same 600 UI pairs, designers agreed with each other only about 62% of the time. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25] How often one person gives the same verdict twice was not looked for in this research: NOT SEARCHED.
- **Why it matters.** A judge cannot be expected to agree with a person more often than that person agrees with themselves, so this sets the ceiling for Q1. [ASSUMPTION]
- **What would settle it.** Re-show 20 already-labelled pairs a week or more later, in shuffled order, and count how many verdicts repeat. [ASSUMPTION]

## Q3. Does a model favour interfaces it generated itself?

- **Uncertain.** Self-preference is shown for text and for image captions, and may stem from familiarity rather than authorship.
  - Summaries of 1,000 XSUM and 1,000 CNN/DailyMail news articles showed it. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.13076 | 2024-04-15]
  - All 12 multimodal judges that scored captions for 4,500 images showed it. [VERIFIED as read by a sub-agent | arxiv.org/html/2604.11589v1 | 2026-04-13]
  - A study found that judges favour familiar-sounding outputs whether or not they wrote them. [VERIFIED as read by a sub-agent | arxiv.org/abs/2410.21819 | 2025-06-21; abstract]
  - A study on interfaces: NOT FOUND.
- **Why it matters.** It decides whether the judge must come from a different model family than the generator, which affects cost and setup.
- **What would settle it.** [ASSUMPTION]
  - Take pairs the person rated equal, where one design was made by the judge's own model family and one by another family.
  - Measure how often the judge prefers its own family's design, in both orders.

## Q4. Does Claude's higher-resolution image tier, or its zoom action, close the gap on small layout defects?

- **Uncertain.**
  - On 4,759 expert-annotated pages, ten models found text overflow with an F1 score averaging 20.36%. [VERIFIED | cvpr.thecvf.com/virtual/2026/poster/38861 | abstract; accessed 2026-09-27] The abstract does not say whether current Claude models were among them, so whether they do better is unknown. [ASSUMPTION]
  - Anthropic's documentation describes a higher-resolution image tier for Claude 4.7 and later. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/vision | accessed 2026-09-27]
  - The computer-use tool offers a zoom action for inspecting small regions. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool | accessed 2026-09-27]
  - An evaluation of either for judging layout: NOT FOUND.
- **Why it matters.** If the gap closed, some script checks could be simplified. If not, scripts must own all geometry, as `01-benchmark.md` recommends.
- **What would settle it.** [ASSUMPTION]
  - Seed known defects into the project's own screens: a 2-pixel misalignment, a clipped label, an overlap, and a colour one step off its token.
  - Ask the judge to find them at the standard and the high resolution, with and without zoomed crops.

## Q5. Is pairwise comparison reliable for this person's taste, or does it mostly measure polish?

- **Uncertain.** The evidence points both ways.
  - On 654 pairs of web implementations, pairwise comparison beat single-answer grading by more than 8 points. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
  - On 400 modified instruction-following samples and 1,689 answers to MT-Bench questions, all text, pairwise preferences flipped in about 35% of cases under distracting features, against 9% for absolute scores. [VERIFIED | arxiv.org/abs/2504.14716 | 2025-08-21] [VERIFIED as read by a sub-agent | arxiv.org/html/2504.14716 | 2025-08-21]
  - On 300 A/B-tested UI pairs, pairwise judging was barely above chance at predicting the winner. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
- **Why it matters.** It decides whether ranking finalists can be delegated to the judge at all.
- **What would settle it.** [ASSUMPTION]
  - Record the share of the loop's comparisons that stay the same when the order is swapped.
  - Compare the judge's order-stable winners with the person's choices over several review sessions.

## Q6. Which statistic should a cycle-time chart use for its spread?

- **Uncertain.**
  - Atlassian's page says its control chart shows the average, the rolling average and the standard deviation of the data. [VERIFIED | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27]
  - A Kanban-metrics practitioner argues that lead-time distributions in knowledge work are never normally distributed, and favours percentiles. [VERIFIED as read by a sub-agent | connected-knowledge.com/2014/09/07/inside-lead-time-distribution | 2014-09-07] Applying this to cycle time, which is part of lead time, is my extrapolation. [ASSUMPTION]
  - A secondary source reports that Wheeler's process limits do not assume normality. [PARTIAL | en.wikipedia.org/wiki/Shewhart_individuals_control_chart | accessed 2026-09-27]
  - Vacanti's own primary argument: NOT FOUND.
- **Why it matters.** It changes what the chart claims, so it is the `spread_statistic` decision in the header of the first worked example in `05-template.md`.
- **What would settle it.** [ASSUMPTION]
  - Read Vacanti's book and Wheeler's articles directly; both could not be fetched.
  - Build three versions of the chart: one showing the standard deviation, one with percentile lines, and one with process limits.
  - Show them to the chart's intended users, ask them to answer the chart's key questions from each, and measure which version gives the most correct answers.

## Q7. Should the cycle-time axis be linear or logarithmic?

- **Uncertain.**
  - The practitioner source describes lead times as right-skewed, meaning a long tail of slow items. [VERIFIED as read by a sub-agent | connected-knowledge.com/2014/09/07/inside-lead-time-distribution | 2014-09-07] If cycle times are skewed the same way, a linear axis may squash most points near zero. [ASSUMPTION]
  - The Office for National Statistics says to avoid log scales unless nothing else shows the data clearly. [VERIFIED as read by a sub-agent | service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines | accessed 2026-09-27]
  - A study of log axes for cycle-time charts: NOT FOUND.
- **Why it matters.** It interacts with the zero-baseline rule (T-04 in the first worked example) and with how unusual items stand out (T-03).
- **What would settle it.** Use the same user test as in Q6, with a linear and a log version of the dense fixture. [ASSUMPTION]

## Q8. How tall is each row span of the new Forge dashboard widget, and does Atlassian Sans load in Custom UI?

- **Uncertain.**
  - The widget context gives the row span as a name, from xsmall to large, and a pixel height at run time. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | 2026-09-14] The pixel height for each name: NOT FOUND.
  - A community member reported that Atlassian's fonts did not load in Custom UI without adding the typography theme by hand. [PARTIAL | community.developer.atlassian.com/t/new-atlassian-fonts-in-forge-apps-with-custom-ui/93747 | 2025-07-10]
- **Why it matters.** Both affect the render matrix and rubric line P-03 in the first worked example.
- **What would settle it.** [ASSUMPTION]
  - On an Atlassian developer site, which is a free test site for building apps, log the widget context at each span.
  - Read the computed font family and the list of loaded fonts in a rendered Custom UI widget.

## Q9. Does Atlassian's ESLint plugin work with ESLint 9 in a Forge Custom UI project?

- **Uncertain.**
  - The plugin failed under ESLint 9 in 2024. [PARTIAL | community.developer.atlassian.com/t/atlassian-eslint-plugins-fail-with-eslint-9-x/82141 | 2024-07-27]
  - The package now ships a preset, a ready-made set of rules, in ESLint 9's configuration format. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/dist/cjs/presets/recommended-flat.codegen.js | accessed 2026-09-27]
  - Its README still shows only the older format. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md | accessed 2026-09-27]
- **Why it matters.** It decides whether rubric line P-11 can run as written.
- **What would settle it.** Install the plugin in a throwaway Custom UI project with the current ESLint, and run the recommended preset. [ASSUMPTION; not done here, because this research installs nothing]

## Q10. What minimum target size does the Atlassian Design System intend?

- **Uncertain.** A target size in pixels is NOT FOUND in Atlassian's accessibility and button pages, so the rubric falls back on WCAG's 24 pixels. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/target-size-minimum.html | 2026-05-11]
- **Why it matters.** A platform value stricter than 24 pixels would tighten rubric line U-06.
- **What would settle it.** Measure the rendered sizes of Atlassian's standard components, or ask Atlassian on its developer forum. [ASSUMPTION]

## Q11. How many calibration examples does design taste need?

- **Uncertain.**
  - Most of the numbers in use come from general advice on building judges: 3 to 5 examples in a prompt, and 60 to 100 examples to validate a judge. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27] [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
  - Two design studies used 8 retrieved examples each, but neither measured how agreement grows with the number of examples. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25] [VERIFIED as read by a sub-agent | arxiv.org/html/2407.08850 | 2024-08-13]
  - A learning curve for design taste: NOT FOUND.
- **Why it matters.** It decides how long the person must label before the loop can be trusted.
- **What would settle it.** Measure the judge's agreement after 8, 16, 32 and 64 labelled examples, on the same held-out set. [ASSUMPTION]

## Q12. Do written taste notes improve the judge, or just lengthen its prompt?

- **Uncertain.**
  - Written principles helped most where preferences departed from the model's defaults, in text tasks. The sample included 648 cross-annotated text pairs and two individual users with 9 and 12 labels. [VERIFIED as read by a sub-agent | arxiv.org/html/2406.06560v2 | 2025-04-21]
  - A study that turns interface rejections into rules and tests them: NOT FOUND.
- **Why it matters.** It decides whether the taste log is worth its upkeep.
- **What would settle it.** On the held-out set, compare the judge with and without the active taste notes, keeping the prompt examples the same. [ASSUMPTION]

## Q13. Does the rubric's wording steer the generator towards one look?

- **Uncertain.** The harness post reports that a single phrase, "museum quality", steered its output. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] A measurement of how strongly rubric wording steers a generator was not found in the sources read, and no dedicated search was run: NOT SEARCHED.
- **Why it matters.** If the generator reads the rubric, rewording a line could change the designs as much as it changes the judge's verdicts.
- **What would settle it.** Run the loop twice with the same brief and two wordings of one taste line. Then compare the candidates' measurable properties, such as colour count, density and type sizes. [ASSUMPTION]

## Q14. Which contrast rule wins where Atlassian and WCAG differ, and is APCA usable?

- **Uncertain.**
  - Atlassian treats text under 24 pixels as small, while WCAG counts bold text from about 18.5 pixels as large. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27] [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/contrast-minimum.html | 2026-06-01]
  - The WCAG 3 draft leaves its contrast method undecided. [VERIFIED as read by a sub-agent | w3.org/TR/wcag-3.0 | 2026-09-10]
  - The APCA repository, the home of an alternative contrast measure, shows a non-commercial beta licence badge. [VERIFIED as read by a sub-agent | github.com/Myndex/SAPC-APCA | accessed 2026-09-27]
- **Why it matters.** The first point decides rubric line U-01 for Atlassian projects. The licence decides whether a public plugin can bundle APCA code.
- **What would settle it.** [ASSUMPTION]
  - For the first question, the rubric's rule that the stricter value wins unless a reason is recorded settles it by policy.
  - For the second, read APCA's licence text before bundling anything. This is not legal advice.

## Q15. How stable are screenshots between a laptop with an ARM processor and a CI server with an x86 processor, using the same browser flags?

- **Uncertain.**
  - ARM and x86 are two families of computer processors. In Playwright's issue tracker, a maintainer said that ARM-based and Intel-based Docker images are expected to produce different screenshots, because they contain different libraries and programs. [VERIFIED | github.com/microsoft/playwright/issues/13873 | issue opened 2022-05; accessed 2026-09-27]
  - A third-party plugin claims that six Chromium command-line flags make text rendering the same on macOS and Linux. [PARTIAL | github.com/FRSOURCE/cypress-plugin-visual-regression-diff/pull/421 | merged 2026-09-22; third-party]
- **Why it matters.** It decides whether visual-conformance baselines can ever be produced on a developer's laptop, or only on the CI server.
- **What would settle it.** Render the same fixture on both kinds of machine, with and without the six flags, and record the pixel difference. [ASSUMPTION]

## Q16. Will pixelmatch's switch to a new colour measure change what thresholds mean?

- **Uncertain.**
  - pixelmatch is the image-comparison library Playwright uses. [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-pageassertions | accessed 2026-09-27]
  - In its published version, the threshold is squared and multiplied by 35,215 to give the largest colour difference allowed. [VERIFIED as read by a sub-agent | unpkg.com/pixelmatch@7.2.0/index.js | accessed 2026-09-27]
  - On its main branch, the threshold itself is the largest allowed distance in the OKLab colour space. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/mapbox/pixelmatch/main/index.js | accessed 2026-09-27]
- **Why it matters.** If Playwright adopts the new version, the same threshold number would mean something different, and baselines could start failing or passing unexpectedly.
- **What would settle it.** Watch pixelmatch's releases and Playwright's changelog, and pin both versions in the meantime. [ASSUMPTION]
