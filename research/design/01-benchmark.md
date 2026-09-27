# 01 — A benchmark for judging whether a user interface is well designed (status on 27 September 2026)

**Sources and how they were selected.** This file cites 50 sources (distinct web pages), all listed in `sources.csv`. Across the whole folder, `sources.csv` lists 313 distinct pages: 295 primary and 18 secondary.
- **How they were found.** Seven research sub-agents each took one research question. Together they ran about 200 web searches, until the session's search limit was reached, and about 760 page fetches. Later sources were reached by fetching known pages directly.
- **Selection order.** Official specifications and documentation came first (w3.org, atlassian.design, developer.atlassian.com, playwright.dev, anthropic.com, platform.claude.com, code.claude.com). Then the original paper, read as arXiv full text or an author copy. Then the tool's own repository. Secondary sources were used only where no primary page could be read.
- **Limits.** This was targeted searching, not a systematic review, so relevant studies that these searches did not reach may exist.
- **What I re-checked.** I re-read every claim under CONTRADICTIONS in its primary page myself, except where the label says "as read by a sub-agent".
- **What was actually seen.** No images were viewed, by me or by the sub-agents. Every statement about how something looks comes from the text of a page, not from seeing it.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. Definitions, method notes and numbered instructions are not research claims and carry no label. A label on the line that introduces a list applies to every item in that list.

**Terms used in this file.**
- A **user interface** (UI) is everything a person sees and operates on a screen.
- A **rubric** is a written list of criteria that a judge applies to a design.
- A **judge**, also called an **evaluator**, is a person or a model that decides whether a design meets the criteria. The **generator** is the model that produces the design.
- In **pairwise comparison** the judge sees two designs and picks the better one or declares a tie. In **single-answer grading**, also called **pointwise** grading, the judge scores one design on its own.
- The **agreement rate** is the share of items on which two judges give the same verdict.
- **Cohen's kappa** and **Krippendorff's alpha** are agreement scores corrected for chance. On both, 0 means chance-level agreement and 1 means perfect agreement.
- `00-glossary.md` defines every other term.

---

## CONTRADICTIONS

These findings contradict or qualify items on the list the reader treated as already known.

### C1. The 66% figure is out of date: the current version of the paper reports about 70%, and says larger models level off there.

- **The sample.** WebDevJudge's 654 pairs of web implementations were drawn from real user prompts in public crowd-vote data. Section C2 describes how they were chosen and labelled. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Version 1 of WebDevJudge, dated 21 October 2025.**
  - In this version, the best judge was Claude-4-Sonnet, which agreed with the reference labels on 66.06% of 654 pairs of web pages.
  - The row labelled Human reached 84.82%.
  [VERIFIED | arxiv.org/html/2510.18560v1 | 2025-10-21]
- **Version 3, dated 3 March 2026.**
  - Version 3 keeps the 654 pairs but revises the labels to 269 wins for page A, 276 wins for page B and 109 ties.
  - GPT-4.1 is now best at 70.34%, and Claude-4-Sonnet is second at 70.18%.
  - The Human row is 84.56%.
  [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **The plateau.** Version 3 says smaller models improve with size, but larger and more capable models level off at about 70% agreement. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Another protocol gives a much higher number.** In ArtifactsBench, the sample was 280 randomly selected tasks with outputs from six models, rated double-blind by experienced front-end engineers; the number of engineers is not stated. A Gemini-2.5-Pro judge was given a checklist written for each task, the code, and several screenshots taken over time. It agreed with the engineers' pairwise rankings on 90.95% of pairs. [VERIFIED as read by a sub-agent | arxiv.org/html/2507.04952 | 2025-09-29]
- **Consequence.** The figure to quote is "about 70% for the best judges, against about 85% for the human row", with the paper version named. The protocol can move the number by 20 points, so 70% is not a fixed ceiling for AI judges. [ASSUMPTION]

### C2. The benchmark behind the figure measures web applications judged mainly through their code, not web designs judged by eye.

- **Where the 654 pairs came from.** The pairs were drawn from real user prompts in the public WebDev Arena crowd-vote data. The authors' filtering for safe, clear and feasible prompts, and for code that deploys, left 1,713 candidates, from which the 654 were taken. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **What kind of tasks they are.** The paper sorts the prompts into three categories of roughly a third each: digital design, game and app development, and web and specialised technologies. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **How the reference labels were made.** Experts judged the fully deployed pages with a rubric tree written for each prompt. The tree covered whether the request was fulfilled, the static quality, and the dynamic behaviour. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **What the judges relied on.** Judges were given the prompt, the code of both implementations and screenshots. Across five judge models, removing the code lowered agreement by 3.67 to 10.7 points, and by 7.95 to 10.7 points for the three strongest. Removing the screenshots lowered it by only 0.31 to 2.60 points. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Consequence.** The 66–70% figure is evidence about judging working web implementations, mostly through their code. It says little about how well a model judges visual design from pixels. [ASSUMPTION]

### C3. The 85% is not clearly agreement between two human experts, and two experts working without a rubric agreed only 65% of the time.

- **The Human row is not explained.** The paper does not clearly say how its Human row was computed. One of my readings linked it to the two expert annotators, while four targeted readings by a sub-agent found no description. [PARTIAL | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **The pilot re-annotation.** In a pilot, two experts re-annotated 100 sampled pairs on the deployed pages without a rubric.
  - They agreed with each other on 65.0% of pairs when ties were counted, and 91.3% when ties were excluded.
  - They agreed with the original crowd votes on only 53.0% of pairs, or 77.4% without ties.
  [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Agreement with rubric trees.** With human-written rubric trees, agreement between the annotators rose to 92.0%, or 95.5% without ties. With rubric trees generated by a language model it reached 90.0%, or 95.1%. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **The same two numbers mean something else in MT-Bench.** MT-Bench (2023) used 80 questions, with 479 to 1,343 expert votes behind each agreement figure. In it, GPT-4 judging pairwise agreed with the expert votes on 66% of first-turn votes when ties were counted, and on 85% when ties were excluded. Anyone quoting "66% versus 85%" should check which source it came from. [VERIFIED as read by a sub-agent | arxiv.org/html/2306.05685 | 2023-12-24]
- **Consequence.** The written rubric, more than expertise alone, is what made the human reference consistent. [ASSUMPTION]

### C4. When the question is purely visual preference, professional designers agree far less than 85%.

- **DesignPref: the sample.** 20 professional designers took part, each with at least one year of UI design experience, recruited through a university mailing list and online platforms.
  - Each rated the same 600 pairs of UI designs on a four-level scale, giving 12,000 judgements.
  - The designs were generated by GPT-5 and Gemini-2.5-Pro from 100 written screen descriptions.
  [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **DesignPref: agreement.**
  - On simple either/or preference, the mean agreement between two designers was 0.624, with Cohen's kappa 0.248 and Krippendorff's alpha 0.248.
  - On the four-level labels, mean agreement was 0.386 and alpha was 0.104.
  [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **DesignPref: where designers diverged.** They diverged on information density, on visual style and tone, on decorative imagery against plain utility, and on how prominent actions should be. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **DesignPref: personal against pooled models.**
  - A model fine-tuned on one designer's labels predicted that designer's choices with 60.16% accuracy, against 57.45% for a model trained on all designers pooled together.
  - GPT-5 given 8 similar examples from the designer's own history reached 58.89%, against 57.70% with no examples.
  [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **UIClip.** 12 designers, recruited by word of mouth at a university, rated pairs of app screens. On a shared set of 10 pairs their Krippendorff's alpha was 0.37. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12500 | 2024-04-18]
- **Consequence.** For taste, the realistic ceiling between two strangers is roughly 60–65% on either/or choices, not 85%. A judge should be compared with how consistently the specific person agrees with themselves, not with a general figure. [ASSUMPTION]

### C5. "Comparing pairs beats scoring one design alone" holds in some conditions and fails in others.

- **Where it holds.** In WebDevJudge version 3, GPT-4.1 agreed 60.86% of the time when scoring one page alone and 70.34% when comparing pairs. The paper reports an average gain of more than 8.0 points for pairwise comparison. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Where it fails: distractors.**
  - Sample: Tripathi and colleagues used 400 modified instruction-following samples and 1,689 answers from the MT-Bench question set, judged by four open models between 3 and 72 billion parameters. [VERIFIED as read by a sub-agent | arxiv.org/html/2504.14716 | 2025-08-21]
  - When the answers contained distractor features designed to exploit the judge, pairwise preferences flipped in about 35% of cases, against 9% for absolute scores. [VERIFIED | arxiv.org/abs/2504.14716 | 2025-08-21]
- **Where it fails: predicting which design users acted on.**
  - Sample: WiserUI-Bench uses 300 real UI pairs taken from public A/B-test case collections. The winner of each pair is the variant that led more users to act in the real test, and there is no human-rater baseline. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
  - GPT-4o picked the winner 60.11% of the time, averaged over both presentation orders. It picked the same correct design in both orders only 30.11% of the time, where chance is 25%. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
- **Where the two methods tie.** In MT-Bench, on its 80 questions, GPT-4 single-answer grading and pairwise comparison both agreed with humans 85% of the time on first-turn votes without ties. With ties counted, they scored 60% and 66%. [VERIFIED as read by a sub-agent | arxiv.org/html/2306.05685 | 2023-12-24]
- **A figure that should not be used as evidence here.** MLLM-as-a-Judge (arXiv 2402.04788) drew about 4,414 image and instruction pairs from 14 datasets, labelled by six of the paper's authors. [PARTIAL | arxiv.org/html/2402.04788 | 2024-06-11; the 4,414 figure comes from a single reading]
  - Its "about 79% against about 70%" figures are acceptance rates, meaning how often annotators accepted the model's judgement, across 10 of those datasets. [VERIFIED as read by a sub-agent | arxiv.org/html/2402.04788 | 2024-06-11]
  - The 14 datasets are general image tasks such as captioning, charts and maths questions. [VERIFIED as read by a sub-agent | mllm-judge.github.io | accessed 2026-09-27]
  - None of them asks a judge to rate interface design quality, so these figures are not evidence about judging interface design. [ASSUMPTION]
- **Consequence.** Use pairwise comparison, run in both orders, for the holistic question "which of these is better", and only among candidates that already pass every blocker. Use binary absolute checks for each rubric line. [ASSUMPTION]

### C6. "Models favour their own output" is established for text and image captions, but untested for interfaces, and its cause is disputed.

- **The original evidence is about text summaries.** The study used summaries of 1,000 XSUM and 1,000 CNN/DailyMail news articles written by three models, with no images. GPT-4 recognised its own summaries 73.5% of the time, and stronger self-recognition went with stronger self-preference. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.13076 | 2024-04-15]
- **The cause may be familiarity, not authorship.** Another study found that judges favour familiar-sounding outputs (low perplexity) more than humans do, whether or not the judge wrote them. Its sample is not stated in the abstract, which is all that was read. [VERIFIED as read by a sub-agent | arxiv.org/abs/2410.21819 | 2025-06-21; abstract]
- **It also appears with images.** Sample: 12 multimodal judges scored captions for 4,500 images. Result: all 12 showed self-preference. [VERIFIED as read by a sub-agent | arxiv.org/html/2604.11589v1 | 2026-04-13]
- **Interfaces: NOT FOUND.** No study that measures self-preference when a model judges interfaces or web pages it generated itself was found.
- **Anthropic's guidance and experience.**
  - Anthropic's evaluation documentation says it is best practice to grade with a different model from the one that produced the output. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/test-and-evaluate/develop-tests | accessed 2026-09-27]
  - The harness post says the tuned evaluator remained inclined to be generous toward output generated by a language model. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]

### C7. "Models miss fine spatial detail" is confirmed, and it extends to the defects an interface checker cares about.

- **UI-Lens (CVPR 2026).** The benchmark has 4,759 Chinese-language UI pages annotated by design experts, and 10 models were tested. Averaged over the models, the F1 scores were 20.36% for finding text overflow, 31.21% for overlapping containers and 10.61% for inconsistent text. F1 combines precision and recall; 100% is perfect. [VERIFIED | cvpr.thecvf.com/virtual/2026/poster/38861 | abstract; accessed 2026-09-27]
- **BlindTest.** On seven simple geometry tasks, such as whether two circles overlap, four vision-language models averaged 58.07% accuracy. The best, Claude 3.5 Sonnet, reached 77.84%. [VERIFIED as read by a sub-agent | arxiv.org/abs/2407.06581 | 2025-03-27]
- **Screenshots are shrunk before the model sees them.** Claude's vision documentation says oversized images are scaled down to fit two limits: on the standard tier, 1568 pixels on the long edge and 1568 visual tokens; on Claude 4.7 and later models, 2576 pixels and 4784 tokens. For example, a 1920 by 1080 screenshot becomes 1456 by 819 on the standard tier, because of the token limit. The documentation also says the model's coordinates and counts are approximate. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/vision | accessed 2026-09-27]
- **The higher-resolution tier: NOT FOUND.** No evaluation of whether the higher-resolution tier or the zoom action closes this gap was found.

### C8. The harness post is confirmed, with seven qualifications.

1. **The four criteria belong to the frontend experiment only.** Design quality, originality, craft and functionality were used there. The full-stack evaluator used product depth, functionality, visual design and code quality, and gave each a hard threshold. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
2. **The criteria were weighted.** Design quality and originality counted for more than craft and functionality, because Claude already scored well on the last two by default. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
3. **The evaluator did more than look at a rendered page.** It used the Playwright MCP to navigate the live page itself, taking screenshots and studying the implementation before scoring. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
4. **Calibration was aimed at one person's taste.** The few-shot examples with detailed score breakdowns were meant to align the evaluator with the author's own preferences and to reduce score drift across iterations. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
5. **Calibration also needed prompt tuning from logs.** The QA evaluator found real issues and then talked itself into approving the work anyway. Several rounds of reading its logs and editing its prompt were needed. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
6. **The rubric's wording steered the generator.** A phrase saying the best designs are "museum quality" pushed the designs toward one particular visual convergence. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
7. **No stopping rule, and no measured agreement.**
   - Scores rose and then levelled off, with room still left. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
   - The author often preferred a middle iteration to the last one. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
   - A numeric score scale, a stopping rule and any measured agreement between the evaluator and a human are NOT FOUND in the post.

---

## The three findings most likely to change the design of the evaluator

Each finding gives the evidence, the consequence for the harness, and the counter-case.

**1. Scripts must own everything that can be measured. The AI judge should never be asked to see geometry.**
- **Evidence.**
  - Averaged over ten models, text overflow was found with an F1 score of 20.36% (C7). [VERIFIED | cvpr.thecvf.com/virtual/2026/poster/38861 | abstract; accessed 2026-09-27]
  - Screenshots are shrunk before the model sees them (C7). [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/vision | accessed 2026-09-27]
  - Judges of web pages leaned on code far more than on screenshots (C2). [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Consequence.**
  - Contrast, target size, overflow, clipping, overlap, alignment to a spacing scale, token conformance and chart axis rules become deterministic scripts that read the page's element tree (the DOM) and its computed styles.
  - The evaluator receives the script report as input and is told not to re-judge those items.
  - The AI judge is kept for questions no script can answer: hierarchy, clarity of purpose, coherence, and taste.
  [ASSUMPTION]
- **Counter-case.** A script can only check the rules someone thought to write. So the judge should still be allowed to report "other problems" in free text, which then become candidate rules. [ASSUMPTION]

**2. The human ceiling for taste is low and personal, and it is the written rubric that creates agreement.**
- **Evidence.**
  - Designers agreed with each other 62.4% of the time on either/or visual choices (C4). [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - Models tuned to one designer beat pooled models (C4). [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - Expert agreement rose from 65.0% without a rubric to 92.0% with one (C3). [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
  - Anthropic calibrated its evaluator to the author's own preferences (C8). [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- **Consequence.**
  - The taste layer of the rubric must belong to the project and to the person who approves the designs.
  - Its lines should be binary checks that a stranger could apply.
  - The judge should be calibrated against that person's own labelled examples.
  - Success should be measured against that person's consistency with themselves on repeated items, not against a general percentage.
  [ASSUMPTION]
- **Counter-case.** With one person and few examples, a personal rubric can overfit: it memorises the quirks of a handful of decisions instead of the person's real preferences. Section I of `04-ai-evaluation.md` describes how to keep it small, dated and revisable. [ASSUMPTION]

**3. A pairwise verdict counts only if it survives swapping the order, and every unstable or "unknown" verdict goes to the human.**
- **Evidence.**
  - Pairwise preferences flipped in about 35% of cases under distractors (C5). [VERIFIED | arxiv.org/abs/2504.14716 | 2025-08-21]
  - On A/B-tested UI pairs, GPT-4o was consistent in both orders only 30.11% of the time, against 25% chance (C5). [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
  - In a text-judging study, with 80 questions labelled by three of the authors, one set of fixes raised GPT-4's agreement with human labels from Cohen's kappa 0.24 to 0.56, against an average human at 0.54. The fixes were generating evidence before the verdict, aggregating both orders, and sending the 20% most uncertain cases to humans. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30]
- **Consequence.**
  - The loop runs every pairwise comparison twice, once in each order.
  - It records a winner only when both runs agree.
  - It presents order-unstable pairs and "unknown" verdicts to the person as decisions, not as scores.
  [ASSUMPTION]
- **Counter-case.** Two runs per pair double the cost, and with many candidates the number of pairs grows with the square of the candidate count. So pairwise comparison should be reserved for a few finalists that have already passed the scripted checks. [ASSUMPTION]

**Two findings that nearly made this list.**
- **The rubric's wording steers the generator (C8).** The evaluator's rubric text should be written deliberately, and changes to it should be versioned. [ASSUMPTION]
- **"Originality" can conflict with platform conformance.** Atlassian's product font, Atlassian Sans, is derived from the Inter typeface. [VERIFIED as read by a sub-agent | atlassian.design/foundations/typography/product-typefaces-and-scale | accessed 2026-09-27] Anthropic's prompting documentation still names Inter among the overused fonts that make designs look generic. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27] A gadget inside Jira should therefore be judged on native fit rather than originality. [ASSUMPTION]

---

## Other findings that change earlier assumptions (outside the "already known" list)

- **The new widget pages still carry an Early Access label.**
  - Atlassian's changelog declared `dashboards:widget` generally available on 22 September 2026, and deprecated the older `jira:dashboardGadget`, with removal on 17 May 2027. [VERIFIED as read by a sub-agent | developer.atlassian.com/changelog | entries of 2026-09-22 and 2026-09-23]
  - Yet the widget hooks page still carried an Early Access label when read. Early Access is Atlassian's label for an experimental feature, and the page says it is not supported for production use. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | last updated 2026-09-14]
  - The same page lists the widget's layout context: pixel width and height, a row span from "xsmall" to "large", and a column span of 3, 4, 6, 8 or 12 on a 12-column grid. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | last updated 2026-09-14]
- **Anthropic's frontend-design skill has been rewritten.** The current file no longer bans Inter, Roboto and purple gradients. Instead it lists five looks that AI-generated design currently clusters around, with colour values, and a plan-then-review process. [VERIFIED | raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md | accessed 2026-09-27] Lists of "generic AI design" therefore go stale and need a date. [ASSUMPTION]
- **Atlassian's own chart guidance limits a chart to 5 to 6 colours.** It says chart colours meet 3:1 contrast against Atlassian surfaces but not against each other, so neighbouring chart colours need a border or a gap. [VERIFIED | atlassian.design/foundations/color/data-visualization-color | accessed 2026-09-27]

---

## The three layers

The benchmark has three layers. The first is generic: the plugin can ship it unchanged to every project. The second and third are supplied by each project. `05-template.md` turns the layers into a rubric file format.

### Layer 1 — Universal quality (generic: the same for every project)

This layer holds properties that do not depend on the brand, the platform or the purpose. Almost all of it can be measured by a script. The default bar is WCAG 2.2 at level AA. WCAG (Web Content Accessibility Guidelines) is the W3C accessibility standard, and level AA is the middle of its three levels of strictness, A, AA and AAA.

**1.1 Accessibility.** The main thresholds are below. `02-automated-checks.md` gives the tools and what each misses. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]
- Text needs a contrast ratio of at least 4.5:1 with its background. Large text needs 3:1; large means at least 18 point, or 14 point bold, which is about 24 pixels, or about 18.5 pixels bold.
- Parts of controls and of graphics that are needed to understand the content, such as chart lines and input borders, need 3:1 against adjacent colours.
- Colour must not be the only visual means of conveying information.
- Pointer targets need to be at least 24 by 24 CSS pixels, unless a spacing rule or another listed exception applies. A CSS pixel is the browser's unit of layout, which is not the same as a physical screen pixel.
- At a width of 320 CSS pixels, content must not need scrolling in two directions, except for content such as data tables, maps and diagrams that needs a two-dimensional layout.
- Nothing may be lost when a user sets line height to 1.5 times the font size, paragraph spacing to 2 times, letter spacing to 0.12 times and word spacing to 0.16 times.
- Keyboard focus must be visible, and the focused element must not be entirely hidden by the author's own content, such as a sticky header.

**The status of the standard.**
- W3C announced on 21 October 2025 that WCAG 2.2 is now the international standard ISO/IEC 40500:2025. [VERIFIED as read by a sub-agent | w3.org/WAI/news/2025-10-21/wcag22-iso | 2025-10-21]
- WCAG 3 is still a working draft, dated 10 September 2026. The draft says the contrast algorithm for WCAG 3 is yet to be determined. [VERIFIED as read by a sub-agent | w3.org/TR/wcag-3.0 | 2026-09-10]
- A conformance check should therefore use the WCAG 2 contrast ratio. Newer contrast measures can be reported only as extra information. [ASSUMPTION]

**1.2 Layout integrity.**
- Text must not overflow its container, be clipped, or overlap other text or controls. No element may stick out of its container or out of the viewport.
- This must hold at every size the design is shown at, and it must still hold when strings are made about 40% longer. Making strings artificially longer this way is called pseudo-localisation. [VERIFIED as read by a sub-agent | learn.microsoft.com/en-us/globalization/methodology/pseudolocalization | 2022-08-12]
- A 2017 study tested automatic detection of such layout failures from the page's element tree.
  - Sample: 25 pages from a random-website directory, checked by hand to be responsive, plus one motivating example, rendered at widths from 320 to 1400 pixels.
  - Result: the tool reported 197 true failures, 48 false alarms and 83 issues with no visible effect. The true failures reduced to 33 distinct failures on 16 of the 26 pages. [VERIFIED as read by a sub-agent | gregorykapfhammer.com/download/research/papers/key/Walsh2017-paper.pdf | 2017]

**1.3 Typographic and spacing discipline.**
- **The universal rule is discipline.** Every font size, line height, weight, spacing value and colour must come from a declared scale. [ASSUMPTION]
- **The scale itself belongs to the platform layer.** Public systems use different steps.
  - Atlassian's spacing is built on 8 pixels, with 2, 4 and 6 pixel sub-steps. [VERIFIED | atlassian.design/foundations/spacing | accessed 2026-09-27]
  - The GOV.UK Design System uses 5-pixel steps. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/spacing | accessed 2026-09-27]
  - A fixed "8-point grid" rule would therefore flag a well-known accessible design system as wrong. [ASSUMPTION]
- **Sizes and lengths.** WCAG sets no minimum font size, and the published line-length limits differ.
  - The US government's accessibility site says WCAG does not specify a minimum font size. [VERIFIED as read by a sub-agent | section508.gov/develop/fonts-typography | 2026-03] As evidence about WCAG itself, it is a secondary statement. [PARTIAL]
  - GOV.UK recommends no more than 75 characters per line. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/layout | accessed 2026-09-27]
  - WCAG's AAA level, the strictest level, asks that a way exists to limit lines to 80 characters. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/visual-presentation.html | 2026-03-09]
  - The numbers and the disagreement between sources are in `02-automated-checks.md`, section A7.

**1.4 States and interface text.**
- **States.** Every view that shows data needs a designed empty state, loading state and error state. [ASSUMPTION, supported by the platform guidance below]
- **Anthropic's rules for UI text.** The frontend-design skill gives these rules. [VERIFIED | raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md | accessed 2026-09-27]
  - Button labels say exactly what happens, such as "Save changes" rather than "Submit".
  - An action keeps the same name throughout a flow.
  - Error messages explain what went wrong without apologising.
  - Empty states invite the user to act.
- **The same rules in Atlassian's guidance.**
  - Atlassian's error messages have a title of 3 to 4 words and a body of 1 to 2 sentences that explains the cause and the fix. [VERIFIED as read by a sub-agent | atlassian.design/foundations/content/designing-messages/error-messages | accessed 2026-09-27]
  - Atlassian's empty states have a short title and 1 to 2 sentences. [VERIFIED as read by a sub-agent | atlassian.design/foundations/content/designing-messages/empty-state | accessed 2026-09-27]
  - These are platform rules that happen to agree with the generic ones. [ASSUMPTION]

**1.5 Usability, judged by a model or a person.**
- The harness post's functionality criterion is a usable generic definition: a user can understand what the interface does, find the primary actions, and complete tasks without guessing. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- This needs judgement, not a script. [ASSUMPTION]

**1.6 Data visualisation.**
- Some chart rules hold for any project:
  - People judge position along a common scale more accurately than length, angle, area or colour. Only position, length and angle were tested directly, with about 51 analysed participants per experiment who were not a random sample. [VERIFIED as read by a sub-agent | math.pku.edu.cn/teachers/xirb/Courses/biostatistics/Biostatistics2016/GraphicalPerception_Jasa1984.pdf | 1984]
  - A bar's value axis must include zero. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf | 2019]
  - Chart marks need 3:1 contrast. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/non-text-contrast.html | 2026-06-15]
  - Every chart needs a text title and a text alternative. [VERIFIED as read by a sub-agent | domoritz.de/papers/2022-Chartability.pdf | 2022]
- `03-data-visualisation.md` lists 40 candidate rules and which of them a script can check.

**1.7 What this layer cannot decide.** It cannot say whether the design serves its purpose, whether it fits the brand, or whether the person will like it. A design can pass every universal check and still be the wrong design. [ASSUMPTION]

### Layer 2 — Platform conformance (project-specific: the project names its design system)

This layer holds the design system the product must fit: its design tokens (named values such as `space.200` = 16 pixels), its components, its content rules and the platform's technical limits. The plugin cannot know these values. Each project supplies them, and the plugin supplies the checking method. [ASSUMPTION]

**For the Forge gadget, the benchmark is the Atlassian Design System (ADS).** Its main values:
- **Spacing.** The 8-pixel scale: 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64 and 80 pixels. [VERIFIED | atlassian.design/foundations/spacing | accessed 2026-09-27]
- **Type sizes and line heights.**
  - Headings run from 32 pixels on a 36-pixel line down to 12 pixels on a 16-pixel line.
  - Body text is 16 pixels on 24, 14 pixels on 20, or 12 pixels on 16.
  [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27]
- **Font.** The product font has been Atlassian Sans since the typography update became generally available on 9 September 2025. [VERIFIED as read by a sub-agent | atlassian.design/whats-new/new-typography-in-general-availability | 2025-09-09]
- **Chart colours.** There are eight categorical chart colours, to be used in their numbered order and no more than 5 to 6 in one chart. Specific tokens are assigned to titles, tick labels, gridlines, data marks and reference lines. [VERIFIED | atlassian.design/foundations/color/data-visualization-color | accessed 2026-09-27]
- **Content rules.** Sentence case is required for titles, headings, menu items, labels and buttons. [VERIFIED as read by a sub-agent | atlassian.design/foundations/content/language-and-grammar | accessed 2026-09-27]
- **Contrast.** ADS applies 4.5:1 to all text smaller than 24 pixels, which is stricter than WCAG for bold text between about 18.5 and 24 pixels. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27] When the platform and the universal layer disagree, the stricter rule should apply unless the project records a reason. [ASSUMPTION]
- **Forge limits.**
  - The UI Kit chart components cover bar, stacked bar, horizontal bar, horizontal stacked bar, line, pie and donut charts. They include no scatter plot and no control chart. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components | accessed 2026-09-27]
  - A Custom UI app must opt in to Atlassian's themes, such as dark mode, by calling `view.theme.enable()`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/design-tokens-and-theming | 2024-10-30]

**For a document-heavy business web app,** the project names its own design system, or adopts a public one such as IBM Carbon, whose spacing scale and type sizes are published. [VERIFIED as read by a sub-agent | carbondesignsystem.com/elements/spacing/overview | 2026-09-23] `05-template.md` fills this in.

**How conformance is checked.** There are two complementary methods. [ASSUMPTION, built on the tools described in `02-automated-checks.md`, Part B]
- **Linting the source code.** Atlassian publishes ESLint and Stylelint rules that flag hard-coded colours and spacing where a token should be used. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md | accessed 2026-09-27]
- **Comparing the rendered page's computed styles with an allow-list of the token values.** This method sees what the user actually gets, including third-party components. It cannot tell whether a value came from a token or from an identical hard-coded number.

### Layer 3 — Taste and purpose (project-specific: the person decides)

This layer holds what the screen is for, who uses it, and what the approving person likes and rejects. No public benchmark can supply it. [ASSUMPTION]

**Purpose.**
- A screen has a job, such as answering "are we getting faster, and which items are unusual?".
- Parts of purpose can be tested objectively. One way is to ask a model to answer the screen's question from the rendered screenshot, then compare its answer with the underlying data. [ASSUMPTION; `05-template.md` calls this a comprehension probe]
- Whether a design makes real users act is a different question, and models predicted A/B-test winners barely above chance (C5). Claims about user behaviour therefore need real user data, not an AI judge. [ASSUMPTION]

**Taste.**
- **Taste is personal.** Designers diverge on density, tone, decoration and emphasis, and per-person models beat pooled ones (C4). [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **Taste also varies by group.** Sample: 39,975 unpaid volunteers from 179 countries took part through the LabintheWild website; after cleaning, 32,222 participants had given 771,083 ratings of 430 website screenshots. Result: preferred colourfulness and visual complexity differed by gender, age, country and education. [VERIFIED as read by a sub-agent | eecs.harvard.edu/~kgajos/papers/2014/reinecke14visual.pdf | 2014]
- **So taste enters the rubric as the approving person's own notes.** Each rejection becomes a dated rule with a reason and an example. [ASSUMPTION; the method and its evidence are in `04-ai-evaluation.md`, section I]

**The criteria themselves are a taste choice.**
- The harness post weighted originality heavily, for standalone websites (C8). [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- For a gadget embedded in Jira, the equivalent criterion is native fit: the gadget should look like part of the product. The project should set these weights explicitly. [ASSUMPTION]

### How the layers combine

| Layer | Who supplies it | Who checks it | Example rule written as a sentence |
|---|---|---|---|
| 1. Universal | The plugin ships it. A project may make a threshold stricter freely, but must record a reason whenever it makes one looser. | Scripts check most rules; a model judges usability. | "Every text element has at least 4.5:1 contrast with its background, or 3:1 if it is large text." |
| 2. Platform | The project names its design system and points to its token values. | Scripts check source code and computed styles; a model checks components and patterns that scripts cannot see. | "Every margin, padding and gap on the rendered page is one of the design system's spacing values." |
| 3. Taste and purpose | The project writes a purpose statement; the approving person writes taste notes and approves reference examples. | A model applies binary taste rules and comparison between finalists; the person makes the final choice. | "The chart shows at a glance which items took unusually long, without opening a tooltip." |

[ASSUMPTION for the division; the example rules draw on sources cited above]

---

## Negative results for this file

- **Self-preference when a model judges interfaces it generated:** NOT FOUND.
- **A numeric agreement figure between Anthropic's design evaluator and a human:** NOT FOUND in the harness post.
- **A published, validated threshold for the number of distinct font sizes on a page:** NOT FOUND.
- **Empirical support for the 8-point grid:** NOT SEARCHED, because the session's search limit was reached.
- **How the WebDevJudge Human row was computed:** NOT FOUND in a clear form; see C3.
- **An evaluation of Claude's high-resolution image tier for judging layout:** NOT FOUND.
