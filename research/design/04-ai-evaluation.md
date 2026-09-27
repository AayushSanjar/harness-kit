# 04 — AI design-evaluation loops, and how to capture a person's taste (status on 27 September 2026)

**Sources and how they were selected.** This file cites 72 sources (distinct web pages), all listed in `sources.csv`. It answers research questions 4 and 6.
- **How they were found.** Three research sub-agents covered these questions. Together they ran about 63 web searches, until the session's search limit was reached, and about 260 page fetches.
- **Selection order.** Anthropic's own pages came first (anthropic.com, claude.com, platform.claude.com, code.claude.com, support.claude.com and the anthropics GitHub repositories). Then the original papers, read as arXiv full text where possible. Then the products' own documentation, then practitioners' own blogs. Secondary sources were used only where no primary page could be read.
- **What I re-read myself.** The harness-design post, both versions of the WebDevJudge paper, DesignPref, the pairwise-or-pointwise paper, WiserUI-Bench, UI-Lens and the frontend-design skill file. During the final check I re-read the skill file's wording on its planning passes, its quality floor and its button example.
- **What was actually seen.** No images were viewed. Descriptions of before-and-after designs in Anthropic's posts come from the posts' text.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. Definitions, method notes and numbered instructions are not research claims and carry no label. A label on the line that introduces a list or table applies to every item in it.

**Terms used in this file.**
- A **generator–evaluator loop**, which Anthropic calls the evaluator-optimizer workflow, has one model produce work while another model judges it and feeds back, repeatedly.
- **Calibration** is adjusting a judge until its verdicts match a reference, usually a person's labels.
- A **few-shot example** is a worked example placed in the prompt to show the judge what a good verdict looks like.
- A **Likert scale** is a rating scale such as 1 to 5.
- A **checklist** is a set of yes-or-no questions.
- **Position bias** is a judge's tendency to prefer whichever option it sees first, or second.
- **Self-preference bias** is a judge's tendency to rate its own output higher.
- A **jury**, or panel, is a group of different judge models whose verdicts are combined.
- The **true positive rate** and **true negative rate** are the shares of genuinely failing and genuinely passing items that the judge classifies correctly. Which class counts as "positive" is whatever the judge is built to flag.
- **Criteria drift** is the finding that people discover their criteria while grading examples.
- A **taste note** is a written record of one of the approving person's preferences, with a reason and an example; this is my term, defined in section I8.
- The three **layers** are those of `01-benchmark.md`, "The three layers": universal quality (rules that hold for any interface), platform conformance (the values of the project's design system) and taste and purpose (what the screen is for, and the approving person's preferences). This file calls the last two the platform layer and the taste layer.
- **Severity** says how much a failed rubric line matters. A **blocker** stops a candidate from becoming a finalist, a **major** failure counts against it in ranking, and a **minor** failure is only reported. A **ranking** line never fails a candidate, but is one of the criteria used when two candidates are compared. `05-template.md` defines these in full.
- A **held-out set** is a set of labelled examples that the judge never sees in its prompt, used only to measure it.
- A **regression guard** is a check kept only to catch a later change that breaks something that already worked.
- `00-glossary.md` defines every other term.

---

## Part A — What Anthropic has published

### A1. "Harness design for long-running application development" (24 March 2026)

The post describes a generator–evaluator loop for visual design in detail. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] It is the most detailed public description of such a loop that this research found. [ASSUMPTION]
- **Setup.**
  - The post is by a member of the Anthropic Labs team. The author says the design was inspired by generative adversarial networks, a machine-learning setup in which one network generates and another judges.
  - When agents grade their own work, they tend to praise it confidently even when a human would find it mediocre.
  - Tuning a separate evaluator to be sceptical proved far more tractable than making a generator critical of its own work.
- **The four criteria.** Both agents received the same criteria:
  - **Design quality**: the colours, typography, layout and imagery form a coherent whole with a distinct mood and identity.
  - **Originality**: there is evidence of custom decisions rather than template layouts, library defaults and patterns typical of AI-generated design.
  - **Craft**: technical execution, meaning typography hierarchy, spacing consistency, colour harmony and contrast ratios.
  - **Functionality**: users can understand what the interface does, find the primary actions and complete tasks without guessing.
- **Weighting.** Design quality and originality were weighted above craft and functionality, because Claude already did well on the last two by default.
- **How the evaluator saw the page.** The evaluator used the Playwright MCP to navigate the live page itself, take screenshots and study the implementation before scoring.
- **Iterations.** Runs took 5 to 15 iterations per generation and lasted up to four hours. Scores rose and then levelled off, with room left.
- **Calibration.** The evaluator was calibrated with few-shot examples that included detailed score breakdowns, so that its judgement matched the author's preferences and drifted less between iterations.
- **The wording steered the generator.** A phrase in the criteria saying the best designs are "museum quality" shaped the character of the output.
- **What the author says about aesthetics.** Aesthetics cannot be fully reduced to a score, and tastes vary. But criteria that encode design principles can still improve results, because asking whether a design follows stated principles gets consistent answers where asking whether it is beautiful does not. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- **Details a sub-agent read in the same post.** [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
  - After each evaluation, the generator was told to choose: refine the current direction if scores were improving, or switch to a different aesthetic if not.
  - The author often preferred a middle iteration to the last one.
  - In one example, a museum website became a clean dark landing page by iteration nine, then was rebuilt as a navigable 3D room on iteration ten.
  - In the full application harness, the evaluator used different criteria (product depth, functionality, visual design and code quality), each with a hard threshold. It clicked through the running application as a user would.
  - Out of the box, the QA evaluator found real problems, then talked itself into approving the work, and tested only superficially. Several rounds of reading its logs and rewriting its prompt were needed.
  - The author says an evaluator is worth its cost when the task is beyond what the current model does reliably alone, and that this boundary moved outward with Opus 4.6.
- **Costs.** For the retro game-maker example, a single agent took 20 minutes and cost $9, while the full harness took 6 hours and cost $200. A later version of the harness on Opus 4.6 built a music application in 3 hours 50 minutes for $124.70. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- **What is missing.** A numeric score scale, a stopping rule, the few-shot examples themselves, and any measured agreement between the evaluator and a person are NOT FOUND in the post.

### A2. The frontend-design skill, and why models produce generic designs

**The current skill file.** [VERIFIED | raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md | accessed 2026-09-27]
- **Role.** Claude acts as design lead at a studio known for distinctive, non-template identities.
- **Process.** The skill works in two passes before any code is written.
  1. Plan first: 4 to 6 named hex colours, the typefaces, a layout described in prose and a rough text wireframe, and a set of principles.
  2. Review the plan against the brief and revise anything generic. Only then write the code.
  3. While building, critique the work by taking screenshots, if the environment supports them. The critique is part of building, not a separate final step.
- **Typography.** Use one or two type families, chosen for the brief rather than by default. Keep lines under 80 characters. Avoid accenting a single word, all-capital labels and unnecessary labels.
- **The five looks AI-generated design currently clusters around:**
  1. A cream background near #F4F1EA, a serif headline and a terracotta accent near #D97757.
  2. A near-black background with one acid-green or vermilion accent.
  3. A broadsheet newspaper layout with hairline rules and square corners.
  4. A kit of identical rounded cards with the same soft shadow and gradient washes.
  5. Stock page furniture, which the skill calls template chrome: all-capital small labels above headings, middle-dot separators, monospace data labels and arrows on links.
- **Brief first.** If the brief sets a visual direction, the brief's words win, even when they ask for one of those looks.
- **Quality floor.** The skill asks Claude to meet a quality floor without announcing it: the design works down to mobile, keyboard focus is visible, reduced motion is respected, and colours are accessible and harmonious.
- **Restraint.** Be bold in one place only.
- **Interface text.** A button says exactly what happens when it is used; the skill's example is a button labelled `Save changes` rather than `Submit`. Errors explain what went wrong without apologising. Empty states invite action.

**The older version, and why it matters.**
- The older version of the skill had a "never use" list of Inter, Roboto, Arial, system fonts and purple gradients. That structure now appears only on a third-party mirror. [PARTIAL | agenticskills.io/skills/frontend-design | synced 2026-05-24; secondary mirror]
- Anthropic's prompting documentation still carries a similar list. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27]
- A list of "generic AI design" is therefore a dated snapshot, not a permanent rule. [ASSUMPTION]

**The explanation for generic designs.** Anthropic's blog post "Improving frontend design through Skills" (12 November 2025) explains it this way. [VERIFIED as read by a sub-agent | claude.com/blog/improving-frontend-design-through-skills | 2025-11-12]
- Sampling follows the statistics of the training data, where safe, universally acceptable designs dominate. The post calls the result "AI slop".
- A skill, a markdown file Claude loads only when needed, can steer each design dimension.
- Guidance should sit at a middle level of detail: neither exact hex codes nor vague advice.
- The evidence offered is before-and-after examples, with no quantitative evaluation.

### A3. Claude Design (Anthropic Labs)

- **Launch.** Claude Design launched on 17 April 2026 as a research preview for making designs, prototypes, slides and one-pagers. It ran on Claude Opus 4.7 at launch. [VERIFIED as read by a sub-agent | anthropic.com/news/claude-design-anthropic-labs | 2026-04-17]
- **Design systems.** During onboarding it builds a team's design system by reading the team's code and design files, then applies the colours, typography and components to later work. [VERIFIED as read by a sub-agent | anthropic.com/news/claude-design-anthropic-labs | 2026-04-17]
- **Handoff.** Designs can be handed to Claude Code. [VERIFIED as read by a sub-agent | anthropic.com/news/claude-design-anthropic-labs | 2026-04-17]
- **What the help centre says about checking.** [VERIFIED as read by a sub-agent | support.claude.com/en/articles/14604416-get-started-with-claude-design | accessed 2026-09-27]
  - Claude checks its own output against the design system and fixes problems before the user sees them.
  - Claude can review a design for accessibility, contrast, information hierarchy and usability.
  - A user can ask for 2 to 3 alternative layouts.
- **Setting up a design system.** The help centre advises including real finished examples, not only specifications, when setting one up. [VERIFIED as read by a sub-agent | support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design | accessed 2026-09-27]
- **June 2026 update.** A 17 June 2026 update added design-system imports and `/design-sync` and `/design` commands in Claude Code. [VERIFIED as read by a sub-agent | claude.com/blog/claude-design-stays-on-brand-for-daily-work | 2026-06-17]
- **Evidence of accuracy.** Any accuracy figure for Claude Design's self-check, or any statement that a separate evaluator agent performs it: NOT FOUND.
- **Relevance to the harness.** Claude Design is a possible source of the platform layer, because it turns a codebase into a design system. Its self-check is the kind of self-grading that the harness post found lenient. [ASSUMPTION]

### A4. Anthropic's general guidance on evaluation

- **"Building effective agents" (19 December 2024).** The evaluator-optimizer workflow fits when clear criteria exist and responses measurably improve with feedback. The post advises stopping conditions such as a maximum number of iterations. [VERIFIED as read by a sub-agent | anthropic.com/engineering/building-effective-agents | 2024-12-19]
- **"Demystifying evals for AI agents" (9 January 2026).** [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
  - There are three kinds of grader:
    - code-based graders are fast and repeatable but brittle on subjective tasks;
    - model-based graders are flexible but vary between runs and need calibration against people;
    - human graders are the reference but slow and expensive.
  - Grade each dimension with its own isolated judge rather than one judge for everything.
  - Let the judge answer "Unknown" when it lacks information.
  - Start with 20 to 50 tasks drawn from real failures, balanced between cases where a behaviour should and should not occur.
  - Write tasks on which two domain experts would independently reach the same verdict.
- **Anthropic's evaluation documentation.** [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/test-and-evaluate/develop-tests | accessed 2026-09-27]
  - Use detailed rubrics.
  - Ask the grader for a specific output, such as correct or incorrect, or a score from 1 to 5.
  - Let the grader reason before its verdict, then discard the reasoning.
  - Grade with a different model from the one that produced the output.
- **Anthropic's prompting documentation.** It recommends 3 to 5 examples that are relevant, diverse enough to cover edge cases, and wrapped in example tags. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27]
- **Claude Code's best practices.** [VERIFIED as read by a sub-agent | code.claude.com/docs/en/best-practices | accessed 2026-09-27]
  - A verification subagent, meaning a fresh model with its own context, can try to refute the result so that the worker does not grade itself.
  - A reviewer asked to find gaps usually finds some even in sound work, so it should flag only gaps that affect correctness or the stated requirements.

---

## Part B — Other public generator–evaluator loops for user interfaces

Where a paper reports a sample, the entry gives it before the result. The DesignRepair entry and the product entries give no sample, because none was read.
- **ReLook (October 2025).**
  - How it works: the critic sees the prompt, the code and three screenshots taken at load, one second and two seconds. A revision is accepted only if it beats the best score so far, with at most 3 rounds at inference.
  - Sample: a human study of 100 randomly sampled tasks with 5 annotators.
  - Result: the trained model was judged better in 50 tasks, the same in 30 and worse in 20. With the critic, each query took about 123 seconds, against 18 seconds without it.
  [VERIFIED as read by a sub-agent | arxiv.org/html/2510.11498v1 | 2025-10-13]
- **WebGen-Agent (September 2025).**
  - How it works: a vision-language model scores screenshots and suggests improvements, then a GUI agent tests the live site, for at most 20 iterations.
  - Sample: WebGen-Bench, with 101 instructions and 647 test cases. How the benchmark selected its tasks is NOT FOUND.
  - Result: Claude-3.5-Sonnet's accuracy rose from 26.4% with a baseline agent to 51.9%, and its appearance score from 3.0 to 3.9.
  [VERIFIED as read by a sub-agent | arxiv.org/abs/2509.22644 | 2025-09-26]
- **DesignRepair (ICSE 2025).** It checks the source code and properties of the rendered page, retrieves Material Design guidelines, and repairs the code with GPT-4. [VERIFIED as read by a sub-agent | arxiv.org/abs/2411.01606 | 2024-11-03]
- **UICoder (NAACL 2024).**
  - How it works: it filters its own generated interface code with a compiler, a screenshot-to-text relevance score (CLIP), and de-duplication, then retrains on what is kept.
  - Sample: 200 randomly selected descriptions.
  - Result: the compile rate rose from 0.03 to 0.82.
  [VERIFIED as read by a sub-agent | arxiv.org/html/2406.07739v1 | 2024-06-11]
- **Self-Refine (2023).** One model generates, critiques its own output without screenshots, and refines, for up to 4 rounds. Across 7 tasks it improved results by about 20% absolute. [VERIFIED as read by a sub-agent | arxiv.org/abs/2303.17651 | 2023-03-30] Its website examples are qualitative only. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2303.17651 | 2023-03-30]
- **Products.**
  - Vercel's post on v0 describes fixes at the code level, not a screenshot critique. [VERIFIED as read by a sub-agent | vercel.com/blog/how-we-made-v0-an-effective-coding-agent | 2026-01-07]
  - Google's Stitch gives design critiques when the user asks. [VERIFIED as read by a sub-agent | blog.google/innovation-and-ai/models-and-research/google-labs/stitch-ai-ui-design | 2026-03-18]
  - Figma's design QA agent flags spacing, alignment and design-system violations, after which the user fixes and re-checks. [VERIFIED as read by a sub-agent | figma.com/solutions/ai-design-qa-agent | accessed 2026-09-27]
  - Lovable says its browser testing is not reliable for subtle visual details or colour differences. [VERIFIED as read by a sub-agent | docs.lovable.dev/features/browser-testing | accessed 2026-09-27]
  - An automatic visual critique loop in v0, Stitch, Figma Make or bolt.new: NOT FOUND.
- **Pattern.** The published loops differ in three ways. [ASSUMPTION, drawn from the entries above and A1]
  - Only ReLook keeps the best version so far and accepts a revision only if it beats it.
  - ReLook, WebGen-Agent and the harness post judge screenshots of the running page. DesignRepair checks code and page properties, and Self-Refine uses no screenshots.
  - The number of rounds ranges from 3 in ReLook and 4 in Self-Refine to 20 in WebGen-Agent; the harness post ran 5 to 15.
- **Consequence.** Keeping the best version so far, as ReLook does, fits the harness post's finding that its author often preferred a middle iteration to the last. [ASSUMPTION]

---

## Part C — How reliable are AI judges of design?

Each row states the sample before the result. `01-benchmark.md`, sections C1 to C7, discusses the headline figures.

| Study | Sample | What was judged | Result |
|---|---|---|---|
| WebDevJudge, version 3 | 654 pairs of web implementations from real prompts. [VERIFIED \| arxiv.org/html/2510.18560v3 \| 2026-03-03] | Judges rated overall web-development quality, using code, screenshots and rubric trees. | The best judges agreed about 70% of the time, against about 85% for the human row. Pairwise beat single-answer grading by more than 8 points. [VERIFIED \| arxiv.org/html/2510.18560v3 \| 2026-03-03] |
| ArtifactsBench | 280 randomly selected tasks, with outputs from 6 models, scored double-blind by experienced front-end engineers. [VERIFIED as read by a sub-agent \| arxiv.org/html/2507.04952 \| 2025-09-29] The number of engineers is NOT FOUND. | Judges ranked pairs of outputs, with a checklist per task and screenshots taken at set times. | Gemini-2.5-Pro agreed 90.95% of the time; with no screenshots it agreed 79.06%. [VERIFIED as read by a sub-agent \| arxiv.org/html/2507.04952 \| 2025-09-29] |
| UIClip | 12 designers aged 20 to 32, recruited at a university by word of mouth; held-out test sets of 201 pairs. [VERIFIED as read by a sub-agent \| arxiv.org/html/2404.12500 \| 2024-04-18] | Judges chose which of two app screens was better designed. | A trained model reached 75.12%. GPT-4V reached 51.58% and refused about 10% of examples. [VERIFIED as read by a sub-agent \| arxiv.org/html/2404.12500 \| 2024-04-18] |
| UICrit | 983 mobile screens with 3,059 critiques from 7 designers; the prompting test used 6 screens judged by 6 experts. [VERIFIED as read by a sub-agent \| arxiv.org/html/2407.08850 \| 2024-08-13] | People rated the quality of a model's written critiques. | Eight examples chosen for similarity, plus a coordinate overlay on the screenshot, raised critique quality from 0.31 to 0.48 (the "55% gain"). Human critiques scored 0.75. [VERIFIED as read by a sub-agent \| arxiv.org/html/2407.08850 \| 2024-08-13] |
| Feedback on UI mock-ups (CHI 2024) | 51 mobile mock-ups rated by 3 designers; a second test on 12 screens, each reviewed by 6 of 12 design experts, whose pooled findings held 100 distinct guideline violations. [VERIFIED as read by a sub-agent \| arxiv.org/html/2403.13139 \| 2024-03-19] | GPT-4 received a text description of the design (element types, positions, sizes, colours), not an image. | 52% of suggestions were accurate. Precision was 0.603 against the experts' 0.829; recall was 0.380 against 0.336. [VERIFIED as read by a sub-agent \| arxiv.org/html/2403.13139 \| 2024-03-19] |
| WiserUI-Bench | 300 UI pairs whose winners came from real A/B tests; no human-rater baseline. [VERIFIED \| arxiv.org/html/2505.05026v5 \| 2026-06-04] | Judges chose which design made more users act. | GPT-4o was 60.11% accurate on average, but consistent across both orders only 30.11% of the time, against 25% chance. [VERIFIED \| arxiv.org/html/2505.05026v5 \| 2026-06-04] |
| UI-Lens (CVPR 2026) | 4,759 pages annotated by design experts; 10 models. [VERIFIED \| cvpr.thecvf.com/virtual/2026/poster/38861 \| abstract; accessed 2026-09-27] | Models had to find display defects such as text overflow and overlapping containers. | Averaged over the models, F1 scores were 20.36% for text overflow and 31.21% for overlapping containers. [VERIFIED \| cvpr.thecvf.com/virtual/2026/poster/38861 \| abstract; accessed 2026-09-27] |
| Mobile usability ratings (HCII 2026) | 1,000 mobile screens with expert ratings. [PARTIAL \| link.springer.com/chapter/10.1007/978-3-032-30549-7_12 \| 2026-07-05; abstract only] | Models rated aesthetic and usability dimensions. | Models matched experts closely on aesthetics but overrated usability by 1 to 3 points. [PARTIAL \| link.springer.com/chapter/10.1007/978-3-032-30549-7_12 \| 2026-07-05; abstract only] |
| Design2Code | 100 examples, 5 crowd annotators each. [VERIFIED as read by a sub-agent \| arxiv.org/html/2403.03163 \| 2025-02-09] | Annotators compared rebuilt pages with their reference pages. | The annotators agreed only moderately (Fleiss' kappa 0.46), and no model was validated as a judge. [VERIFIED as read by a sub-agent \| arxiv.org/html/2403.03163 \| 2025-02-09] |
| UI-Bench | 194 hand-selected experts making over 4,000 pairwise judgements of 300 sites. [VERIFIED as read by a sub-agent \| arxiv.org/html/2508.20410v3 \| 2025-09-03] | Experts compared the visual design of two sites at a time, and nothing else. | The paper reports no agreement statistic between raters and no AI judge. [VERIFIED as read by a sub-agent \| arxiv.org/html/2508.20410v3 \| 2025-09-03] |

**What the table suggests.** [ASSUMPTION]
- A judge does best when it has a checklist written for the task, the code, and several screenshots.
- It does worst when asked to predict real user behaviour, or to find small geometric defects by eye.
- Its usability ratings run high, which matches the leniency the harness post describes.

---

## Part D — Designing the rubric

- **Binary checks beat 1-to-5 scales for grading one item.** In WebDevJudge's single-answer grading, binary rubric checks clearly beat the 1-to-5 Likert scale. In pairwise judging, giving no criteria did about as well as giving them. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Practitioners prefer pass or fail.** Hamel Husain's guide prefers pass-or-fail verdicts to 1-to-5 scales because nobody can act on a middle score. Each pass or fail comes with a written critique. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
- **Rubrics with typed items.** Rubrics as Rewards writes 7 to 20 self-contained rubric items per task and grades each as Essential, Important, Optional or Pitfall. [VERIFIED as read by a sub-agent | arxiv.org/html/2507.17746v2 | 2025-10-03]
  - Sample: about 20,000 medicine prompts and about 20,000 science prompts.
  - Result: the rubric-based reward gave relative gains of up to 31% on a medical benchmark over judges that give a single 1-to-5 score.
- **How long criteria should be.** In AutoCalibrate, effective criteria were mostly 60 to 600 words. Criteria that describe good and bad items in general did as well as criteria that describe each score level. [VERIFIED as read by a sub-agent | arxiv.org/html/2309.13308 | 2023-09-23]
- **One judge per dimension.** Anthropic recommends an isolated judge for each dimension and an "Unknown" option (A4). [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- **Consequence for the rubric format.** [ASSUMPTION]
  - Write each rubric line as one binary question that a stranger could answer.
  - Name the evidence the judge must cite, such as an element, a screenshot region or a script result.
  - Allow "unknown".
  - Keep holistic "which is better" questions for pairwise comparison between finalists.
  - Counter-case: binary lines lose the difference between "barely fails" and "badly fails". Severity levels (blocker, major, minor) on each line recover part of it.

---

## Part E — Pairwise comparison or single-answer grading?

- **For pairwise comparison.**
  - On its 654 pairs (see Part C), WebDevJudge found pairwise judging better than single-answer grading by more than 8 points. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
  - Draco learned good chart-ranking weights from ranked pairs. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf | 2019]
  - Eugene Yan's survey recommends pairwise comparison for subjective qualities. [VERIFIED as read by a sub-agent | eugeneyan.com/writing/llm-evaluators | 2024-08]
- **Against pairwise comparison.**
  - Sample: 400 modified instruction-following samples and 1,689 first-turn MT-Bench responses to 80 questions, judged only by small and mid-size Llama and Qwen models, with 3 to 72 billion parameters. [VERIFIED as read by a sub-agent | arxiv.org/html/2504.14716 | 2025-08-21]
  - Result: pairwise preferences flipped in about 35% of cases under distractors, against 9% for absolute scores. [VERIFIED | arxiv.org/abs/2504.14716 | 2025-08-21]
  - The authors of that study recommend absolute scoring for tasks such as correctness, and warn that pairwise protocols exaggerate small quality gaps. [VERIFIED as read by a sub-agent | arxiv.org/html/2504.14716 | 2025-08-21]
  - Eugene Yan recommends direct scoring for objective checks, because the better of two items can still be defective. [VERIFIED as read by a sub-agent | eugeneyan.com/writing/llm-evaluators | 2024-08]
  - MT-Bench's authors note that pairwise judging does not scale, because pairs grow with the square of the number of candidates. [VERIFIED as read by a sub-agent | arxiv.org/html/2306.05685 | 2023-12-24]
- **Recommendation.** [ASSUMPTION]
  - Use binary absolute checks for every rubric line. A line that compares a candidate with an approved reference screen is still one yes-or-no question, such as whether the candidate keeps the reference's meaning, asked with the two images in both orders.
  - Use pairwise comparison between candidates, in both orders, only to rank candidates that pass every blocker: in the loop, the new candidate against the best so far, and at the end, among the finalists.
  - Counter-case: if the finalists differ only in taste, both orders may keep disagreeing. The loop then has no winner, and that is the signal to show them to the person.

---

## Part F — Biases, and how to reduce them

- **Position bias.**
  - **Sample and extent.** Three authors labelled 80 questions. With ChatGPT as the judge, merely changing the order of the two answers let Vicuna-13B beat ChatGPT on 66 of the 80. With GPT-4 as the judge, swapping the order changed the verdict in 46.3% of one set of comparisons. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30]
  - **Fixes, measured.** For GPT-4, agreement with human labels (Cohen's kappa) rose step by step as fixes were added. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30]
    1. With no fix, kappa was 0.24.
    2. Generating several pieces of evidence before the verdict raised it to 0.30.
    3. Aggregating both orders raised it to 0.37.
    4. Sending the 20% most uncertain cases to humans raised it to 0.56.
    - The average human reached 0.54.
  - **In web judging.** In WebDevJudge, judges kept the same verdict after a swap 83% to 90% of the time. [PARTIAL | arxiv.org/html/2510.18560v3 | 2026-03-03; the sub-agent's reads disagreed on one model's figure]
  - **Few-shot examples help.** Sample: 80 pairs, each made of two GPT-3.5 answers to the same MT-Bench question. Result: adding three few-shot examples raised GPT-4's order consistency from 65.0% to 77.5%, at four times the prompt cost. [VERIFIED as read by a sub-agent | arxiv.org/html/2306.05685 | 2023-12-24]
- **Self-preference.** See `01-benchmark.md`, C6. The practical fixes are a different model family as judge, blind presentation without the name of the generator, and the evaluator never grading work it produced. [ASSUMPTION, following Anthropic's documentation in A4]
- **Style over substance.** The "Style over Substance" paper found that judges favour style over factual accuracy. [VERIFIED as read by a sub-agent | arxiv.org/abs/2409.15268 | 2025-01-27; abstract] Its sample is NOT FOUND, because only the abstract was read. Human crowd voters are swayed by presentation too: in Chatbot Arena, answer length had a clear effect on rankings. [VERIFIED as read by a sub-agent | lmsys.org/blog/2024-08-28-style-control | 2024-08-29]
- **Juries.**
  - Sample: text question-answering sets, and 500 Arena prompts. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.18796 | 2024-05-01]
  - Result: a panel of three smaller models from different families agreed with humans better than a single GPT-4 judge, with Cohen's kappa 0.763 against 0.627 on one set, at more than seven times lower cost. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.18796 | 2024-05-01]
  - A panel has not been tested for UI judging. [ASSUMPTION]
- **Reference-guided grading.** In MT-Bench, GPT-4 failed 14 of 20 maths judgements with the default prompt and 3 of 20 when given a reference answer. [VERIFIED as read by a sub-agent | arxiv.org/html/2306.05685 | 2023-12-24] For design, the equivalent of a reference answer is an approved reference screen. [ASSUMPTION]
- **Reasoning does not fix perception.** On WiserUI-Bench, reasoning strategies left average accuracy similar to or below plain prompting, although consistency across orders often improved. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
- **Leniency.**
  - The harness post's evaluator talked itself into approving work it had found problems in. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
  - The "Judging the Judges" study of 13 judge models reports a general tendency to leniency. [VERIFIED as read by a sub-agent | arxiv.org/abs/2406.12624 | 2025-08-18; abstract]
  - A practical instruction for the evaluator follows: any problem it finds counts, and it may not argue a found problem away. [ASSUMPTION]

---

## Part G — Calibrating the judge with reference examples

**How many examples the sources use or recommend.**
- **Anthropic.** 3 to 5 examples in a prompt, and 20 to 50 tasks to start an evaluation. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices and anthropic.com/engineering/demystifying-evals-for-ai-agents | accessed 2026-09-27; 2026-01-09]
- **Hamel Husain's guide.** [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
  - Start with about 30 examples and continue until no new failure modes appear.
  - Treat fewer than 60 as too few to validate a judge, because the confidence intervals are too wide.
  - Aim for about 100 examples per failure mode.
- **His FAQ.** Put 10 to 20% of the labelled items into a set that may appear in the prompt, 40 to 45% into a development set and 40 to 45% into a final test set, with 30 to 50 passes and 30 to 50 fails in each held-out set. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/evals-faq | modified 2026-09-21]
- **Eugene Yan.** He suggests 50 to 100 labels before writing criteria. [VERIFIED as read by a sub-agent | eugeneyan.com/writing/aligneval | 2024-10-27]
- **Research.**
  - UICrit used 8 examples chosen for visual and task similarity. [VERIFIED as read by a sub-agent | arxiv.org/html/2407.08850 | 2024-08-13]
  - DesignPref retrieved 8 of the designer's own examples. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - AutoCalibrate found 8 to 12 labelled examples enough to draft good criteria. [VERIFIED as read by a sub-agent | arxiv.org/html/2309.13308 | 2023-09-23]
- **How many examples the harness post used:** NOT FOUND.

**How to choose them.**
- Include both good and bad examples. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12272 | 2024-04-18]
- Make them diverse enough to cover edge cases. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27]
- Balance cases where a behaviour should and should not occur. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- Retrieve the examples most similar to the item being judged. [VERIFIED as read by a sub-agent | arxiv.org/html/2407.08850 | 2024-08-13]
- A controlled comparison of choosing borderline cases against choosing at random: NOT SEARCHED, because the session's search limit had been reached.

**How to measure the judge.**
- Report the true positive rate and the true negative rate separately, because raw agreement misleads when one class is rare. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
- Prefer Cohen's kappa over correlation, because correlation does not correct for chance. [VERIFIED as read by a sub-agent | eugeneyan.com/writing/llm-evaluators | 2024-08]
- The usual reading of kappa is that 0.21 to 0.40 is fair agreement and 0.41 to 0.60 moderate. [VERIFIED as read by a sub-agent | eugeneyan.com/writing/llm-evaluators | 2024-08]
- Set the target relative to how well humans agree on the same items with the same rubric, since designers themselves agree only fairly (see `01-benchmark.md`, C4). [ASSUMPTION]

---

## Part H — When a person must decide

[ASSUMPTION for the list; the evidence for each item is cited]
1. **Writing and changing the rubric**, because criteria cannot be fully settled before grading (see I2), and the rubric's wording steers the generator. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12272 | 2024-04-18] [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
2. **Labelling the calibration set**, because the judge is calibrated to the person, not to a general standard. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
3. **Every pairwise comparison that flips when the order is swapped, and every "unknown"**, because sending uncertain cases to humans produced the largest single gain in the position-bias study. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30]
4. **Choosing among the finalists**, because designers agree only about 62% of the time on visual preference. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
5. **Purpose decisions that change what the screen means**, such as which statistic a chart shows.
6. **Periodic audits** of a sample of the judge's passes, because judges tend to be lenient. [VERIFIED as read by a sub-agent | arxiv.org/abs/2406.12624 | 2025-08-18; abstract]
- Counter-case: every human decision costs time. Anthropic's guidance calls human graders the reference standard but slow and expensive, and calls code-based graders fast but brittle on subjective tasks. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09] So for clear-cut objective checks, a validated script should take the work off both the person and the model judge, and the person's time should go to the decisions above. [ASSUMPTION]

---

## Part I — Capturing taste (research question 6)

### I1. Taste is personal

- **DesignPref.**
  - Sample: 20 professional designers rated the same 600 UI pairs. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25] Each had at least one year of UI design experience, and they were recruited through a university mailing list and online platforms. [VERIFIED as read by a sub-agent | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - Agreement: they agreed on 62.4% of either/or choices, with Cohen's kappa 0.248. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - Rationales: of 1,378 written rationales from 13 of the designers, the analysis found divergence on density, style and tone, decoration against utility, and how prominent actions should be. [VERIFIED as read by a sub-agent | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - Personal against pooled: per-designer models beat pooled ones, even though the pooled model saw about twenty times more labels. [VERIFIED | arxiv.org/html/2511.20513v1 | 2025-11-25] The gain was small: a model fine-tuned for one designer reached 60.16% on that designer's either/or choices, against 57.45% for the pooled model, and GPT-5 with no examples reached 57.70%. [VERIFIED as read by a sub-agent | arxiv.org/html/2511.20513v1 | 2025-11-25]
- **Experts against end users.** Sample: 100 sampled WebDevJudge items, re-annotated on the deployed pages by two software-engineering experts without a rubric. Result: the experts agreed with the original crowd votes only 53.0% of the time when ties were counted. [VERIFIED | arxiv.org/html/2510.18560v3 | 2026-03-03]
- **Groups differ.** 39,975 unpaid volunteers from 179 countries took part, and the cleaned data held ratings from 32,222 of them. Preferred colourfulness and complexity differed by gender, age, country and education. [VERIFIED as read by a sub-agent | eecs.harvard.edu/~kgajos/papers/2014/reinecke14visual.pdf | 2014]
- **First impressions.** The 2006 study "Attention web designers" reports that ratings of homepages shown for 50 milliseconds correlated highly with ratings after 500 milliseconds. Its sample sizes and correlation values could not be read. [PARTIAL | ingentaconnect.com/content/tandf/tbit/2006/00000025/00000002/art00003 | 2006-03-01; abstract only]
- **Consequence.** A harness cannot ship "good taste". It can ship a method for recording one person's taste and applying it consistently. [ASSUMPTION]

### I2. People find their criteria while grading

- **Sample.** The EvalGen study ("Who validates the validators?", UIST 2024) had nine practitioners, the first nine respondents to a social-media call who had built language-model pipelines. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12272 | 2024-04-18]
- **Findings.** [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12272 | 2024-04-18]
  - Participants needed criteria to grade outputs, but grading outputs was what helped them define the criteria. The authors call this criteria drift.
  - Participants added criteria when they met a new kind of bad output, and reinterpreted old criteria as they saw more.
  - Some who fixed their criteria before grading regretted it.
- **The authors' recommendations.** [VERIFIED as read by a sub-agent | arxiv.org/html/2404.12272 | 2024-04-18]
  - Let people revise criteria as they grade.
  - Include examples of both good and bad outputs in judge prompts.
  - Measure agreement when several people grade.
- **Practitioner advice.** Hamel Husain's FAQ adopts the term and advises writing rubrics after reviewing examples, not before. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/evals-faq | modified 2026-09-21]
- **Consequence for the harness.** [ASSUMPTION]
  - Draft the taste rubric only after the person has reacted to a first batch of rendered designs.
  - Version the rubric after every review session.
  - Counter-case: a changing rubric makes old and new scores incomparable, so each score must record the rubric version it used.

### I3. Turning preferences into written rules

- **Inverse Constitutional AI (ICLR 2025).** This method reverses Constitutional AI, which trains a model from a short list of written principles. [VERIFIED as read by a sub-agent | arxiv.org/html/2406.06560v2 | 2025-04-21]
  - **How it works.** It treats a set of "preferred against rejected" pairs as something to compress. An LLM proposes principles that would explain each choice. Similar principles are grouped, and each group's principle is kept only if it helps reconstruct the original choices.
  - **Sample.** Several datasets, including 648 cross-annotated pairs and two individual users with only 9 and 12 labels.
  - **Result.** In the paper's "unaligned" data, the labels were deliberately flipped so that a default judge mostly disagrees with them. On that data, in a test with 324 training and 324 test pairs, a written constitution raised agreement to 61%, against 34% for the default judge. On data that already matched the model's defaults, it added little. Personal constitutions from 9 and 12 labels improved reconstruction of each user's own choices but did not transfer to the other user.
  - **Limits.** The authors say a constitution is a lossy summary, and that correlation with the labels does not prove the annotators used those principles.
  - **Consequence.** Written taste rules pay off most where the person's taste departs from the model's defaults. The evidence comes from deliberately flipped labels, not from real people whose taste differs, so this is an extrapolation. [ASSUMPTION]
- **ConstitutionMaker.** It turns three kinds of feedback into principles: praise, critique, and a rewrite of the output. [VERIFIED as read by a sub-agent | arxiv.org/html/2310.15428 | accessed 2026-09-27]
  - Sample: 14 industry professionals compared it with a stripped-down baseline.
  - Result: they found it easier to turn feedback into principles, and wrote more principles. The largest share of principles came from praise (42.1%), ahead of critique (29.5%).
  - Failure modes: principles were sometimes too specific, and switching between the user's and the designer's point of view produced contradictory principles.
- **OpenRubrics.** It shows an LLM a preferred and a rejected answer side by side, so that it writes rubric items that tell them apart. It keeps an item only if using it reproduces the human's choice. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.07743 | 2026-02-03]
- **Auto-Rubric.** It extracted its rubrics from only 70 preference pairs. With those rubrics a small model scored 80.91% on a reward benchmark, above a fully trained model of the same size at 78.20%. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.17314v1 | 2025-10-20]
- **Auto-Rubric as Reward, for images.** For image generation, rubrics built from pairwise preferences raised a judge's accuracy from 75.1% to 78.9% on the MM-RewardBench2 text-to-image set, which has 4,000 expert-annotated pairs across that benchmark. They also cut the position-bias gap from about 30–35 points to about 9–10. [VERIFIED as read by a sub-agent | arxiv.org/html/2605.08354v1 | 2026-05-08]
- **A study for interface design.** A study that turns one person's interface rejections into written rules and then tests them: NOT FOUND.

### I4. Learning from edits and rejections

- **PRELUDE and CIPHER (2024).** The agent writes, the user edits, and the size of the edit is the cost. CIPHER infers a short natural-language preference that explains each edit and stores it with its context. For a new task it retrieves the preferences of the most similar past contexts. [VERIFIED as read by a sub-agent | arxiv.org/html/2404.15269 | 2024-11-23]
  - Sample: simulated users only, played by GPT-4, over 200 rounds per task.
  - Result: on summarisation the total edit cost fell to 32,974, against 48,269 with no learning; an oracle that knew the true preference scored 6,573.
  - The authors say the most common failure is inferring the preference wrongly, and that testing with real people is future work.
- **Consequence for the harness.** A rejection with a stated reason plays the role of an edit. [ASSUMPTION]
  - Store the screen type and the inferred preference sentence.
  - Retrieve similar notes when judging a new screen.
  - Counter-case: the evidence comes from simulated users editing text, not from people judging visual designs.

### I5. Practitioner methods and products

- **"Critique shadowing"** (Hamel Husain). [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
  - One principal expert gives pass-or-fail verdicts with written critiques detailed enough for a new employee to follow.
  - Those critiques are reused directly as few-shot examples in the judge's prompt.
  - The judge is revised until it agrees with the expert; in the guide's case study that took three rounds to exceed 90%.
- **LangSmith (LangChain).** It stores human corrections of a judge's scores, with optional explanations, and feeds them back as few-shot examples. [VERIFIED as read by a sub-agent | langchain.com/blog/aligning-llm-as-a-judge-with-human-preferences | 2024-06-26]
- **Midjourney personalization.** [VERIFIED as read by a sub-agent | updates.midjourney.com/profiles-and-moodboards and docs.midjourney.com/hc/en-us/articles/32433330574221-Personalization | 2024-12-16; accessed 2026-09-27]
  - Its December 2024 announcement said 40 ratings start a personal style profile, and the profile is fairly stable by 200.
  - The current documentation says rating image pairs has been replaced by picking favourites from a grid.
  - The learning mechanism is not described.
- **ViPer (2024).** [VERIFIED as read by a sub-agent | arxiv.org/html/2407.17365 | 2024-07-24]
  - Sample: 20 invited users each commented on 8 to 20 images, and a language model turned the comments into lists of liked and disliked attributes. How the users were recruited is NOT FOUND.
  - Result: users picked their own personalised image 86.1% of the time over no personalisation. Comments on as few as eight images were enough.
- **A commercial product.** The marketing page of a product called Taste says it learns design taste from swipes and screenshots and outputs a Claude Code skill file with a profile, anti-preferences and reference samples. [VERIFIED as read by a sub-agent | buildwithtaste.com/how-it-works | accessed 2026-09-27] These are the vendor's own claims, and they were not tested here.

### I6. Formats from design practice

- **GOV.UK's design principles.** There are 11, each a short imperative title, a short rationale and two linked examples, with no counter-examples. [VERIFIED as read by a sub-agent | gov.uk/guidance/government-design-principles | updated 2025-04-02]
- **NN/g on principles.** The Nielsen Norman Group says principles should take a stand, be memorable, and not conflict, and that ten or more are hard to use. [VERIFIED as read by a sub-agent | nngroup.com/articles/design-principles | 2020-08-02]
- **NN/g on critiques.** Feedback in a critique should be tied to the design's goals, not to personal liking, with notes kept in a shared document and actions followed up. [VERIFIED as read by a sub-agent | nngroup.com/articles/design-critiques | 2016-10-23]
- **Discussing Design.** The book's critique framework asks four questions: what the objective is, which elements relate to it, whether they are effective, and why. [PARTIAL | zeitspace.com/blog/what-is-design-critique-communication | 2020-05-14; secondary]
- **Decision records.** An architecture decision record has a title, context, decision, status (proposed, accepted, deprecated or superseded) and consequences. Superseded records are kept. [VERIFIED as read by a sub-agent | cognitect.com/blog/2011/11/15/documenting-architecture-decisions | 2011-11-15] The GOV.UK Design System team adopted such records to explain why things are the way they are. [VERIFIED as read by a sub-agent | github.com/alphagov/govuk-design-system-architecture/blob/main/proposals/001-use-rfcs-and-adrs-to-discuss-proposals-and-record-decisions.md | 2018-03-16]
- **Do and don't pairs.** Atlassian's button guidance uses paired do and don't examples, each with a picture, a short directive and a one-sentence reason. [VERIFIED as read by a sub-agent | atlassian.design/components/button/usage | accessed 2026-09-27]

### I7. Where taste notes can live in Claude Code

- **Memory files.** Claude Code's memory files (CLAUDE.md) can sit at organisation, user, project and local level. The documentation recommends under 200 lines per file, and warns that if two rules contradict each other Claude may pick one arbitrarily. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/memory | accessed 2026-09-27]
- **Scoped rules.** Rules in `.claude/rules/` can be scoped to file paths, so that they load only when relevant. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/memory | accessed 2026-09-27]
- **Skills.** A skill's short description is always loaded, while its body loads only when the skill is used, and larger material such as examples belongs in supporting files. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/skills | accessed 2026-09-27]
- **Consequence.** The taste log and the reference screenshots belong in the project's repository, next to the rubric, and are loaded by the evaluator on demand, not placed in CLAUDE.md. [ASSUMPTION]

### I8. A proposed format for taste notes, and the flow from a rejection to a rubric line

[ASSUMPTION; built on I2 to I7]

**One taste note** has these fields, in plain sentences:
- **ID and date:** an ID such as TN-07 (TN for taste note, so that it cannot be confused with a rubric line), and the date of the review session.
- **Statement:** one sentence that a stranger could apply as a yes-or-no check. An invented example: reference lines are labelled directly at their right end, not in a legend.
- **Reason:** why the person wants it, in their words. An invented example: a legend forces the reader to look away from the data.
- **Evidence:** the rejected candidate and the chosen one, as file paths to screenshots.
- **Scope:** which screens or components it applies to.
- **Severity:** blocker, major, minor or ranking, chosen by the person. `05-template.md` defines the four values.
- **Status:** proposed (drafted, not yet accepted), active (accepted and applied), superseded (replaced by a named newer note) or retired (withdrawn by the person). Notes are never deleted.
- **Met by default:** yes or no. "Yes" means the generator already meets the note without being told, so the note serves only as a regression guard.
- **Origin:** the review session that produced it.

**The flow.**
1. The person picks between finalists and says, in their own words, why the others lost.
2. The evaluator, in a separate drafting task, drafts candidate taste notes from those reasons, contrasting the chosen and rejected screenshots, as OpenRubrics does with answers. Drafts have the status "proposed".
3. The person accepts, edits or discards each draft. Only accepted notes become active, and only active notes become rubric lines.
4. Each active note becomes a binary rubric line in the taste layer. When the judge checks that line, the note's chosen and rejected screenshots are given to it as examples.
5. Before the next run, the harness re-measures the judge on the person's development set, a held-out set of labelled items. If either of the judge's rates falls below the target recorded in the rubric's header, the new note is treated as ambiguous and is sent back to the person.
6. Notes that the generator already meets without being told are marked "met by default" and kept only as regression guards.

**Counter-cases.**
- With a handful of decisions, notes can overfit to one screen. The scope field and the rule that notes start as "proposed" limit this.
- Too many notes crowd the evaluator's prompt, and conflicting notes make it pick arbitrarily. Keeping fewer than ten active notes per screen type follows NN/g's advice that ten or more principles are hard to use.

---

## Negative results

- How many few-shot examples the harness post used, and its prompts and scores: NOT FOUND.
- An accuracy figure for Claude Design's self-check: NOT FOUND.
- A study of self-preference when a model judges interfaces it generated: NOT FOUND.
- A study that tests whether judges reward visual polish over working function in interfaces: NOT FOUND.
- A study that turns one person's interface rejections into written rules and tests them: NOT FOUND.
- A controlled comparison of borderline-case selection against random selection of judge examples: NOT SEARCHED, because the session's search limit had been reached.
- The number of engineers who rated ArtifactsBench: NOT FOUND.
- How WebGen-Bench selected its tasks: NOT FOUND.
- The sample of the "Style over Substance" study: NOT FOUND, because only the abstract was read.
- How ViPer recruited its participants: NOT FOUND.
- The numerical results of "MLLM as a UI Judge" (arXiv 2510.08783): NOT FOUND. The full text was refused with a rate-limit error, and only the abstract was read.
- The current number of picks that unlocks a Midjourney profile, and how it learns: NOT FOUND.
- The sample sizes of the 2006 "50 milliseconds" study: NOT FOUND, because the full text was blocked.
