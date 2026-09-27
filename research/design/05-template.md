# 05 — The template: rubric file format, evaluator instructions, the loop, and two worked examples (status on 27 September 2026)

**Sources and how they were selected.** This file cites 76 sources (distinct web pages), all listed in `sources.csv`. It answers research question 7.
- **What this file is.** It is a proposal, so most of its statements are my design choices and are labelled [ASSUMPTION]. The facts those choices rest on come from files 01 to 04, or from the primary pages cited here, and keep their labels.
- **Where the example values come from.** Values in the worked examples come from the cited sources where a label says so. The rest are illustrative choices, labelled [ASSUMPTION].
- **The worked examples are illustrations.** The configuration fields of W1 and the screens of W2 are invented for illustration.
- **What I re-read myself.** The pages whose label is VERIFIED without "as read by a sub-agent": the harness-design post, DesignPref, WiserUI-Bench, the UI-Lens abstract, the frontend-design skill file, Atlassian's spacing, typography and data-visualisation colour pages, the Forge widget context page, Jira's control chart page, the GOV.UK table page and the MDN page on numeric figures.
- **What was actually seen.** No images were viewed.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. Definitions, method notes and numbered instructions are not research claims and carry no label. A label on the line that introduces a list or table applies to every item in it.

**Terms used in this file.**
- The **rubric file** is the Markdown file in which a project writes its criteria. A **rubric line** is one criterion in it.
- A rubric line's **check** says who decides it, and its **severity** says how much a failure matters. Section a.3 defines the values of both.
- The **render matrix** is the full set of sizes, themes, states and data sets that every candidate design is rendered in. One combination of size, theme, state and data set is a **render-matrix cell**.
- A **fixture** is a fixed, fake data set used for testing, so that every run shows the same data. The **dense fixture** of the first worked example is the one with about 400 items.
- A **candidate** is one design produced by the generator. A **finalist** is a candidate shown to the person.
- A **comprehension probe** is a check in which a model answers the screen's key questions from screenshots alone, and a script compares the answers with the answers expected from the fixture.
- **Labelled items** are designs, or pairs of designs, that the approving person has judged, with a short critique. They are split into three sets: **prompt examples**, which the evaluator may see in its prompt, and a **development set** and a **test set**, which it never sees. The last two are **held-out sets**.
- The **taste log** is the list of taste notes defined in `04-ai-evaluation.md`, section I8.
- **CI**, continuous integration, is the automated build and test run that a server performs for every change.
- `00-glossary.md` defines every other term.

---

## 0. What is generic and what each project supplies

| Part | Generic: ships in the plugin, the same for every project | Project-specific: each project supplies it |
|---|---|---|
| Universal rubric lines (section a.4) | The lines, their default thresholds and the scripts that check them. | Stricter thresholds, and any loosening with a written reason. |
| Platform rubric lines | The checking methods: the allow-list of computed styles, the source-code lint step and the chart-token check. | The design system's values, its lint configuration and its content rules, written as platform lines. |
| Taste and purpose lines | The line format, the comprehension-probe method and the taste-note flow. | The purpose, the key questions with their expected answers, the purpose decisions, the taste notes and the reference screenshots. |
| Render matrix | The rule that every candidate is rendered across a declared matrix, deterministically. | The sizes, themes, states and fixtures. |
| Evaluator instructions (section b) | The instructions, in full. | Nothing. The harness passes each call the project's rubric, prompt examples and screenshots. |
| Loop (section c) | The steps and the stopping rules. | The number of candidates, the iteration cap, the number of finalists and the budget. |
| Labelled items | The three-way split and the measuring method: true positive and true negative rates, and kappa. | The labelled items themselves, made by the approving person. |

[ASSUMPTION for the division; the evidence behind it is in `01-benchmark.md`, "The three layers"]

---

## (a) The rubric file format

### a.1 Where the files live in a project

[ASSUMPTION for the layout]
- `design/rubric.md` holds the rubric: a header block and the rubric lines.
- `design/taste-log.md` holds the taste notes, newest first, in the format of `04-ai-evaluation.md`, section I8.
- `design/references/` holds reference screenshots: approved and rejected candidates, the approved baseline for visual conformance, and screenshots of native platform screens. Each is named after the taste note, decision or rubric line that uses it.
- `design/labels/examples/` holds the prompt examples.
- `design/labels/dev/` and `design/labels/test/` hold the development set and the test set. The evaluator never sees these. A screenshot used as a taste note's evidence counts as a prompt example, so it must not also appear in the development or test set.
- `design/fixtures/` holds one data set for each state in the render matrix, with the expected answer to each key question.

**How the labelled items are split.** Hamel Husain's FAQ puts 10 to 20% of labelled items into a set that may appear in the prompt, 40 to 45% into a development set and 40 to 45% into a test set, with 30 to 50 passes and 30 to 50 fails in each of the last two. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/evals-faq | modified 2026-09-21] In this template, the development set is used every time the rubric or the evaluator's prompt examples change, and the test set only for a final measurement before the judge's numbers are reported. [ASSUMPTION]

Keeping these files in the project's repository means they are versioned with the code they judge. Counter-case: screenshots in git make the repository grow. Store them at a small fixed size, and prune rejected ones once their taste note is retired. [ASSUMPTION]

### a.2 The header block

The rubric file starts with a header block. Its fields are listed below, and the worked examples in sections W1 and W2 fill them in. [ASSUMPTION]

| Field | What it holds |
|---|---|
| `rubric_version` | A number that increases with every change, recorded next to every result. |
| `purpose` | One or two sentences on what the screen is for. |
| `key_questions` | The questions a user must be able to answer from the screen. Each has an expected answer, taken from the fixture, and a tolerance. These drive the comprehension probe. |
| `primary_tasks` | What a user must be able to do on the screen. |
| `decisions` | Purpose decisions that the person makes, each with its options, the choice, the reason and the date, or marked undecided. While a decision is undecided, the generator is asked for candidates that cover each option, and the finalists include one of each. |
| `platform` | The design system, the source of its token values, and its version. |
| `host` | Where the screen runs, when that constrains it, such as a Forge module and the size information it provides. |
| `render_matrix` | The sizes, themes, states and fixtures, with a name for each. |
| `weights` | For ranking only: how much native fit, originality, density and similar holistic qualities matter. For example, "native fit high, originality low". |
| `approver` | The role of the person who makes final choices. |
| `candidates_per_iteration`, `max_iterations`, `finalists` | The loop's numbers. |
| `budget` | The time and cost limit for one run of the loop. |
| `judge_model_family` | Preferably a different model family from the generator's. |
| `calibration` | The paths to the three label sets, the agreement target, and the date and result of the last measurement. |

### a.3 The format of one rubric line

Each rubric line is a level-three heading followed by fixed fields, so that both a person and a script can read it. [ASSUMPTION; the binary form and the "unknown" verdict follow `04-ai-evaluation.md`, Part D]

```markdown
### U-08 Nothing overflows, is clipped, or overlaps
- Rule: No text or control overflows its container, is clipped, overlaps another text or control, or extends beyond the viewport, at any size in the render matrix.
- Why: Layout failures are common and models detect them poorly, so a script must own this check.
- Check: script
- Method: compare each visible element's scroll size with its visible size; test text and control boxes for overlap; test boxes against their container and the viewport.
- Pass when: no findings, except elements that truncate deliberately with an ellipsis and show the full text on hover, focus or expansion.
- Severity: blocker
- Evidence: element selector, render-matrix cell, and a cropped screenshot of each finding.
- Applies to: every screen, every render-matrix cell.
- Source: developer.mozilla.org/en-US/docs/Web/API/Element/scrollWidth; ReDeCheck (see 02-automated-checks.md, A9).
- Status: active since rubric_version 1
```

**What the fields mean.**
- **ID prefix.** U means universal, P platform, and T taste and purpose. V means visual conformance to an approved design and is optional.
- **Check** takes one of six values.
  - `script`: a deterministic script decides.
  - `script+judge`: a script measures and lists every case, and the judge decides only the question that the line names, such as whether a flagged element is needed to understand the content. The judge never overrides a measurement.
  - `probe`: the judge answers the key questions from screenshots alone, and a script compares the answers with the expected answers. The script's comparison is the verdict.
  - `compare`: the judge looks at the candidate next to the reference screenshot that the line names and answers the line's yes-or-no question. The question is asked twice, with the two images in both orders, and only an answer that agrees in both orders counts; otherwise the verdict is "unknown".
  - `judge`: the judge decides alone and must cite evidence.
  - `person`: the approving person decides.
- **Severity** takes one of four values, and it does not depend on who checks the line.
  - `blocker`: a candidate that fails the line cannot become a finalist, and goes back to the generator with the findings.
  - `major`: a failure counts against the candidate when candidates are ranked.
  - `minor`: a failure is reported only.
  - `ranking`: the line never fails a candidate. It is a criterion of the comparison that ranks candidates, so its check is always `judge`, applied only inside that comparison.
- **Status** is `active` or `retired`. A line exists only after the person has accepted it, so proposals live in the taste log, not in the rubric. Retired lines are kept for history but not applied.

**How the lines combine into a decision.**
1. The `script` lines run first. A candidate that fails a `script` blocker goes back to the generator at once with the findings, and no judge time is spent on it.
2. Then the `script+judge`, `probe`, `compare` and `judge` lines run, and each is answered pass, fail or unknown. A failed blocker sends the candidate back to the generator.
3. An "unknown" on a blocker or major line goes to the person's queue. For ranking, each such unknown counts as one major failure, so an unclear candidate ranks below clear ones but can still become a finalist. The person settles its unknowns before it can be chosen.
4. `person` lines are answered by the person when the finalists are shown.
5. Candidates that pass every blocker are ranked, first by the number of major failures, fewest first. Ties are broken by a comparison in both orders, on one holistic question: which candidate better serves the purpose, the ranking lines and the active taste notes, given the header's `weights`?
6. Every result records the `rubric_version` it used.

### a.4 The universal lines: the generic part, shipped by the plugin

The plugin ships these lines. A project may tighten a threshold, but loosening one needs a written reason in the rubric. The universal lines contain no design-system values: checks against a design system's scales are platform lines, which each project writes with the generic allow-list method (see W1.4 and W2.4), so that one violation is never counted twice. [ASSUMPTION for the selection, the checks and the severities; the thresholds carry the labels of the sources given]

| ID | Rule | Check | Pass when | Severity | Source |
|---|---|---|---|---|---|
| U-01 | Text has enough contrast with its background, in every state and theme. | script | The ratio is at least 4.5:1, or 3:1 for large text, which is text of 24 CSS pixels or more, or about 18.5 pixels or more if bold. Ratios are not rounded. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/contrast-minimum.html \| 2026-06-01] |
| U-02 | Chart marks, input borders and focus indicators that are needed to understand the content contrast with what is next to them. | script+judge | A script measures every such element against the colours next to it, and each reaches 3:1. The judge decides only whether a failing element is needed to understand the content. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/non-text-contrast.html \| 2026-06-15] |
| U-03 | Colour is never the only way information is shown. | script+judge | A script lists every chart series, status and error state; the judge confirms that each has a second cue besides colour: text, shape, pattern or icon. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/use-of-color.html \| 2025-09-16] |
| U-04 | Keyboard focus is visible on every focusable element. | script | Focusing changes the element's appearance. A project aiming at Level AAA also requires the indicator to be at least as large as a 2 CSS pixel thick perimeter of the unfocused element, with 3:1 contrast between the focused and unfocused states. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/focus-visible.html \| 2026-07-12]; [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/focus-appearance.html \| 2026-08-10] |
| U-05 | The focused element is never completely hidden by other content. | script | No focused element is fully covered. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html \| 2026-06-15] |
| U-06 | Pointer targets are large enough, or spaced enough. | script+judge | A script checks that each target is at least 24 by 24 CSS pixels or passes the 24-pixel spacing-circle test. The axe `target-size` rule, which is off by default, must be enabled and must have run. The judge decides only whether a failing target falls under one of the criterion's exceptions, such as an equivalent control elsewhere on the page. | blocker | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/target-size-minimum.html \| 2026-05-11]; [VERIFIED as read by a sub-agent \| github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md \| accessed 2026-09-27] |
| U-07 | An automated accessibility scan finds no violations. | script | axe-core, run with the wcag2a, wcag2aa, wcag21a, wcag21aa and wcag22aa tags, reports zero violations. Its "needs review" results are listed for the person; the judge does not decide them. | blocker | [VERIFIED as read by a sub-agent \| github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md \| accessed 2026-09-27] |
| U-08 | Nothing overflows, is clipped, overlaps or sticks out. | script | There are no findings in any render-matrix cell, except deliberate ellipses with the full text available. | blocker | [VERIFIED as read by a sub-agent \| developer.mozilla.org/en-US/docs/Web/API/Element/scrollWidth \| 2025-04-19] |
| U-09 | The layout survives longer text. | script | U-08 still passes with every string lengthened by 40%. | major | [VERIFIED as read by a sub-agent \| learn.microsoft.com/en-us/globalization/methodology/pseudolocalization \| 2022-08-12] |
| U-10 | The layout survives the user's text-spacing settings. | script | U-08 still passes with line height 1.5, paragraph spacing 2, letter spacing 0.12 and word spacing 0.16 times the font size. | blocker | [VERIFIED as read by a sub-agent \| w3.org/TR/WCAG22 \| 2024-12-12] |
| U-11 | A full page works at 200% zoom and at 320 CSS pixels wide. | script | At 200% zoom, no content or function is lost. At 320 CSS pixels wide, no content is lost, and nothing scrolls in two directions except data tables, maps and diagrams. For embedded components, see the worked example's override. | blocker | [VERIFIED as read by a sub-agent \| w3.org/TR/WCAG22 \| 2024-12-12] for 200% zoom; [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/reflow.html \| 2026-08-10] for 320 pixels |
| U-12 | Body text is not smaller than the floor the project declares. | script | The computed size is at or above the floor. The plugin ships no default floor, because WCAG sets no minimum font size and the sizes that design systems and studies give differ (W2.3 lists some). | major | [VERIFIED as read by a sub-agent \| section508.gov/develop/fonts-typography \| 2026-03] for WCAG setting no minimum |
| U-13 | Long passages of text have readable lines. | script | Lines are at most the project's character limit, and the default limit is 80. WCAG's Level AAA criterion 1.4.8 only asks for a way to limit lines to 80 characters, so the default limit is my choice. | minor | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/visual-presentation.html \| 2026-03-09] |
| U-14 | Every data view has designed empty, loading and error states. | script+judge | A script renders every state fixture and fails any blank area or raw error text it can detect. The judge checks that each state says what happened and, where one exists, offers a way forward. | major | [ASSUMPTION] |
| U-15 | Interface text says what happens. | judge | Buttons name the action. Errors say what went wrong and how to fix it, without apologising. Empty states invite action. | minor | [VERIFIED \| raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md \| accessed 2026-09-27] |
| U-16 | A user can understand what the screen does, find the primary action and complete the primary task without guessing. | judge | The judge can name the primary action and the path to complete each primary task. | major | [VERIFIED \| anthropic.com/engineering/harness-design-long-running-apps \| 2026-03-24] |
| U-17 | A bar or area chart's value axis includes zero. | script | Rule 2 of `03-data-visualisation.md`, section 4, passes. | blocker | [VERIFIED as read by a sub-agent \| idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf \| 2019] |
| U-18 | Charts follow the other universal chart rules that a script can check. | script | Every rule in `03-data-visualisation.md`, section 4, with layer U and script "yes" passes where it applies. Rule 2 is U-17, and rule 24 is covered by U-02. | major | Each rule's own source in 03, section 4 |
| U-19 | Charts follow the universal chart rules that need judgement. | script+judge | For every rule in `03-data-visualisation.md`, section 4, with layer U and script "partly" or "no", the script flags the cases and the judge confirms each one. For rule 36, which has no script part, the script's list is simply every chart. | minor | Each rule's own source in 03, section 4 |
| U-20 | Rendering is deterministic wherever a pixel comparison is used. | script | Rendering the same screen twice gives zero pixel difference. | blocker | [ASSUMPTION] |

**Optional visual-conformance lines.** These apply when an approved design exists. [ASSUMPTION; the tolerances follow `02-automated-checks.md`, section C5]

| ID | Rule | Check | Pass when | Severity |
|---|---|---|---|---|
| V-01 | Elements match the approved design in position, size, colour and text. | script | Positions and sizes are within 2 CSS pixels, token colours are exactly equal, and the text is identical. | major |
| V-02 | Nothing else visible has changed. | script | In CI only, a Playwright screenshot comparison passes at threshold 0.2, with the allowed share of differing pixels set from the measured noise. CI is the only place where the environment is fixed enough for this comparison. | minor |
| V-03 | The design still means the same thing as the approved one. | compare | The reference is the approved baseline at the same render-matrix cell. The judge answers yes, in both orders, to this question: does the candidate show the same information and allow the same actions? This line is never the only reason to pass. | major |

---

## (b) The evaluator agent's instructions

The text below is written to be pasted as the evaluator agent's instructions. [ASSUMPTION; the source of each instruction is given after the text]

> **You are the design evaluator.** You judge designs that another agent made. You never edit files, and you never judge a design you produced yourself. Each call gives you one task: one rubric line, the comprehension probe, one comparison, an open review, or drafting taste notes. Do only that task.
>
> **What you may receive.**
> 1. The rubric file, with its header and its lines.
> 2. The script report. It lists every script finding with an element selector, a render-matrix cell and a cropped screenshot.
> 3. Screenshots of the candidate at the render-matrix cells that the task names, and zoomed crops on request.
> 4. For a rubric line or a comparison: up to five prompt examples, in example tags. Each is a past design with the person's verdict and critique, chosen because it is similar to this screen. For a line that comes from a taste note, two of them are the note's chosen and rejected screenshots.
> 5. For a `compare` line: the candidate and the reference screenshot that the line names, labelled only "first" and "second".
> 6. For a comparison: two candidates labelled only "first" and "second", and any reference screenshots that the ranking lines name.
>
> **What you must not do.**
> - Do not re-judge any measurement from a script. For a `script+judge` line, decide only the question the line gives you. You may report a problem the scripts missed in an open review.
> - Do not estimate pixel positions, sizes, spacing or contrast from screenshots. If a question depends on a measurement, answer "unknown" and name the measurement you need. The comprehension probe is the one exception, described below.
> - Do not fail a line for something the line does not say.
> - Do not consider which candidate is newer, which model made it, or which one you saw first.
>
> **Task: one rubric line.**
> 1. Write down what you see that bears on the rule, and where: the screen, the element, and the render-matrix cell.
> 2. Only then give the verdict: pass, fail or unknown.
> 3. If you found a problem, it counts. Do not talk yourself out of a problem you found.
> 4. Use "unknown" when the evidence is missing, too small or cut off, and ask for the zoomed crop you need.
> 5. For a `compare` line, answer the line's yes-or-no question about the candidate and the reference. You will be asked again with the two images in the other order.
>
> **Task: the comprehension probe.** For each key question in the header, answer from the screenshots alone, as a user would read the screen. This is the one task in which you read values off the screen: give them roughly, as a user would, without measuring. Do not use the fixture data. The harness compares your answers with the expected answers.
>
> **Task: one comparison.** Answer one question: which candidate better serves the purpose, the ranking lines and the active taste notes, given the weights in the header? Answer "first", "second" or "no clear difference", with the three most important reasons, each tied to a rubric line or a taste note. The harness will ask again with the order reversed, and only answers that agree in both orders count.
>
> **Task: open review.** List problems that no rubric line covers but that affect the stated purpose, a primary task or an active taste note. For each, give the evidence, the screen, and a proposed rule sentence, in case the person wants it as a new line. Do not list matters of taste that no note covers.
>
> **Task: drafting taste notes.** You receive the person's choice among the finalists, their reasons in their own words, and the screenshots. For each reason, draft one taste note in the format of the taste log: a statement that a stranger could check with yes or no, the reason in the person's words, the chosen and rejected screenshots as evidence, and a proposed scope and severity. Mark every draft "proposed". Do not add reasons the person did not give.
>
> **What to return.** For a rubric line: the line ID, the evidence, and then the verdict. For the probe: one answer per key question. For a comparison: the answer and the three reasons. For an open review: the list of problems. For drafting: the draft notes.

**Where each instruction comes from.**
- **A separate evaluator that never grades its own work.** Anthropic found self-grading lenient, and its documentation recommends grading with a different model from the one that produced the output. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/test-and-evaluate/develop-tests | accessed 2026-09-27]
- **One task per call.** Anthropic recommends grading each dimension with its own isolated judge. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- **Measurements are not re-judged, and nothing is estimated from pixels.** Averaged over ten models, UI-Lens found text overflow with an F1 score of 20.36%. [VERIFIED | cvpr.thecvf.com/virtual/2026/poster/38861 | abstract; accessed 2026-09-27] Claude's vision documentation says oversized images are scaled down before the model sees them. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/vision | accessed 2026-09-27]
- **Failing only on what a line says.** A reviewer asked to find gaps usually finds some even in sound work. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/best-practices | accessed 2026-09-27]
- **Evidence first, then the verdict.** In the position-bias study, generating evidence before the verdict was the first of the fixes that raised agreement. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30]
- **A found problem counts.** The harness post's evaluator talked itself into approving work in which it had found problems. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- **"Unknown" is allowed.** Anthropic's evaluation guidance recommends it. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- **Up to five similar examples, from their own set.** Anthropic recommends 3 to 5 examples. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices | accessed 2026-09-27] UICrit gained most from examples chosen for similarity. [VERIFIED as read by a sub-agent | arxiv.org/html/2407.08850 | 2024-08-13] Keeping prompt examples apart from the measuring sets follows Hamel Husain's split. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/evals-faq | modified 2026-09-21]
- **Both orders, and only agreeing answers count.** In the position-bias study, aggregating both orders raised agreement with human labels. [VERIFIED as read by a sub-agent | arxiv.org/html/2305.17926 | 2023-08-30] On WiserUI-Bench, GPT-4o gave the same answer in both orders only 30.11% of the time. [VERIFIED | arxiv.org/html/2505.05026v5 | 2026-06-04]
- **The probe's exception.** The probe tests what a user would read off the screen, so the judge's rough reading is the thing being measured, not an estimate that replaces a measurement. [ASSUMPTION]
- **Drafting taste notes by contrast.** OpenRubrics writes rubric items by contrasting a preferred and a rejected answer. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.07743 | 2026-02-03]
- **Blind labels "first" and "second".** These guard against the self-preference and familiarity effects described in `01-benchmark.md`, C6. [ASSUMPTION]

**Counter-cases.** [ASSUMPTION]
- Strict instructions make the judge more conservative, so it will answer "unknown" more often and send more items to the person. That is the intended trade, because a person's minute is cheaper than a wrong approval. The number of unknowns should still be tracked; a rising count means the render matrix or the crops need improving.
- One call per task multiplies cost. Putting several lines into one call is cheaper, but lets the verdicts influence each other.

---

## (c) The loop: from generating, to evaluating, to showing the person finalists

[ASSUMPTION for the loop; the evidence for each step is cited]

**Step 0. Prepare, once per project.**
1. Fill in the rubric header, the platform lines and the render matrix.
2. Create a fixture for every state, with the expected answer to each key question.
3. Have the person label designs or pairs as pass or fail, each with a short critique. Hamel Husain's guide says to start with about 30 examples and keep going until no new failure modes appear, treats fewer than 60 as too few to validate a judge because the confidence intervals are too wide, and aims for about 100 examples per failure mode. [VERIFIED as read by a sub-agent | hamel.dev/blog/posts/llm-judge | modified 2026-09-01]
4. Split the labelled items into prompt examples, a development set and a test set, as described in section a.1.
5. Measure the person's own consistency by showing them 20 of their labelled items again after about a week. Their re-test agreement is the share of those items they label the same way as before.
6. Set the agreement target and record it in the header's `calibration` field. A proposed starting target is that the judge's true positive rate and true negative rate on the development set are both within 10 percentage points of the person's own re-test agreement. Counter-case: with 30 items per class, one item moves a rate by about 3 points, so differences of a few points are noise, and the 10-point margin is a starting value to revise once data exists.
7. Measure the judge on the development set, and adjust the rubric wording or the prompt examples until it meets the target. Then measure it once on the test set, and record both results.

**Step 1. Generate.**
- The generator makes three candidates by default, in deliberately different directions. While a decision in the header is undecided, the candidates cover each of its options.
- After each round it is told either to refine a direction that is scoring well or to change direction, as in the harness post. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]

**Step 2. Render.**
- Every candidate is rendered in every render-matrix cell, deterministically. That means fonts loaded, the clock fixed, data seeded, and the viewport, scale, locale, timezone and colour scheme set. See `02-automated-checks.md`, C6.
- U-20, the self-difference test, runs first wherever a pixel comparison will be used.

**Step 3. Script gate.**
- The `script` lines run, universal and platform.
- For every failed `script` blocker, the generator receives the rule, the element, the property, the value found and the allowed value, and the candidate goes back to Step 1 without judge time. Findings in this form tell the generator exactly what to fix.

**Step 4. Judge.**
- For candidates that passed the gate, the harness runs the `script+judge`, `judge` and `compare` lines, one isolated call per line, as Anthropic's guidance recommends. [VERIFIED as read by a sub-agent | anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09]
- It runs the comprehension probe and compares the answers with the expected answers. Each key question states its tolerance: an exact match for a direction or a count, and the same interval between two axis ticks as the true value for a number.
- It runs one open review per candidate.
- A candidate that fails a blocker in this step also goes back to Step 1.

**Step 5. Compare.**
- Each new candidate that passed every blocker is ranked against the best design so far, by the rule in section a.3: fewer major failures wins, counting each unknown on a blocker or major line as one, and a tie is settled by a comparison in both orders.
- A new candidate replaces the best so far only if it wins, and a comparison win counts only when both orders agree. ReLook likewise accepts a revision only if it beats the best score so far. [VERIFIED as read by a sub-agent | arxiv.org/html/2510.11498v1 | 2025-10-13]
- Comparisons whose two orders disagree are recorded for the person.

**Step 6. Iterate or stop.** Stop when any of these holds:
1. The best design so far passes every blocker and major line, and no new candidate has beaten it for two iterations in a row.
2. The iteration cap is reached. The default is 5, the bottom of the harness post's range of 5 to 15 [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24], to control cost.
3. The header's time or cost budget is spent.

**Step 7. Choose finalists.**
- Pick the top two or three from all iterations, not only the last. The harness post's author often preferred a middle iteration to the last one. [VERIFIED as read by a sub-agent | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24]
- Include one finalist for each option of any undecided decision.

**Step 8. Show the person.**
- Show the finalists side by side, at the same render-matrix cell and theme, with the script report, the judge's evidence, the open-review problems, the comparisons whose orders disagreed, and the unknowns.
- Ask the person to settle the unknowns on blocker and major lines, any `person` lines, and any undecided decision.
- Then ask two questions: which one, and why did the others lose?

**Step 9. Learn.**
1. The evaluator drafts taste notes from the person's reasons, using the drafting task in section (b). Every draft has the status "proposed".
2. The person accepts, edits or discards each draft.
3. Each accepted note becomes active and adds one taste line, and the rubric version increases.
4. The judge is re-measured on the development set. If either of its rates falls below the target in the header, the new note is treated as ambiguous and goes back to the person.
5. See `04-ai-evaluation.md`, section I8, for the note format and the flow.

**Step 10. Freeze.**
- The chosen design becomes the approved baseline for the visual-conformance lines V-01 to V-03.
- The next change to the same screen is then checked against it.

**Counter-cases.**
- Three candidates and five iterations give at most 15 candidates. Each needs one call per judge line, a probe, an open review and two calls per comparison, so the cost adds up. A project with a small budget should cut the candidates to two and keep the scripts, which are cheap.
- Showing finalists is the slowest step, because it waits for a person. The loop should batch the person's decisions rather than stop for each one.

---

## (d) What is a script, what is AI judgement, and what is the person's call

| Question | Who decides | Why | Counter-case |
|---|---|---|---|
| Contrast, target size, focus, overflow, clipping, overlap, zoom, reflow and text spacing | Script | These can be measured exactly, and models detect overflow poorly: averaged over ten models, UI-Lens found text overflow with an F1 score of 20.36%. [VERIFIED \| cvpr.thecvf.com/virtual/2026/poster/38861 \| abstract; accessed 2026-09-27] | Scripts check only what someone wrote down. The judge's open review catches some of the rest. |
| Conformance to the design system's spacing, type, colour and corner-radius values | Script, on source code and on computed styles | The values are known exactly from the design system. [ASSUMPTION] | Third-party components need an exceptions list. |
| Chart axes, ticks, gridlines, colour counts and contrast | Script, on the chart specification or its SVG | In Misviz, a rule-based linter fed with axis data read back from 2,604 real chart images detected whether a chart misleads 62.9% of the time, but named the exact set of problems only 3.1% of the time. [VERIFIED as read by a sub-agent \| arxiv.org/html/2508.21675v1 \| 2025-08] Reading the chart's specification avoids reading images back. [ASSUMPTION] | Charts drawn on a canvas expose nothing to scripts. |
| Whether an element is needed for understanding, whether a second cue exists, and whether interface text is clear | Judge, with evidence, after a script has listed the cases | These need interpretation. [ASSUMPTION] | Judges tend to be lenient [VERIFIED as read by a sub-agent \| arxiv.org/abs/2406.12624 \| 2025-08-18; abstract], so the person audits a sample. |
| Whether a user can find the primary action and complete the task | Judge, plus the comprehension probe | The probe turns part of this into a checkable answer. [ASSUMPTION] | A model is not a user. Real usability needs real users. |
| Which design is better overall | Judge, comparing in both orders, for ranking; the person for the final choice | Designers agree only about 62% of the time on visual preference. [VERIFIED \| arxiv.org/html/2511.20513v1 \| 2025-11-25] | The person's time is limited, so only two or three finalists reach them. |
| Which design will make users act | Nobody in the loop; it needs real user data | Models picked the winners of real A/B tests barely above chance. [VERIFIED \| arxiv.org/html/2505.05026v5 \| 2026-06-04] | An A/B test needs traffic that an internal tool may not have. |
| The rubric itself, the taste notes and the purpose decisions | The person | Criteria cannot be fully settled before grading [VERIFIED as read by a sub-agent \| arxiv.org/html/2404.12272 \| 2024-04-18], and the rubric's wording steers the generator [VERIFIED \| anthropic.com/engineering/harness-design-long-running-apps \| 2026-03-24]. See `04-ai-evaluation.md`, Part H. | The person can propose rules that conflict. Scope fields and a ceiling on active notes limit this. |

[ASSUMPTION for the allocation]

---

## W1. Worked example: an Atlassian Forge dashboard gadget showing a cycle-time control chart, with a configuration screen

### W1.1 Header

[ASSUMPTION for every value unless a label says otherwise]
- **rubric_version:** 1.
- **purpose:** On a Jira dashboard, show how long completed work items took (cycle time) over a chosen period, so that a team can see the trend and spot unusually slow items. A configuration screen lets the person choose what the chart covers.
- **key_questions,** each with its expected answer and tolerance:
  1. Is cycle time getting longer or shorter over the period? The expected answer is the direction seeded in the fixture, matched exactly.
  2. Which items took unusually long? The expected answer is the number of slow items seeded in the fixture, matched exactly, and each item's date, within one interval between two axis ticks.
  3. What is the typical cycle time? The expected answer is the fixture's median, and the answer passes if it falls in the same interval between two axis ticks.
  - Atlassian's documentation says its own control chart shows the average and the rolling average. [VERIFIED | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27] The page text that could be read does not mention unusually slow items. [PARTIAL | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27; the fetched text may be incomplete] Questions 3 and 1 follow from the average and the rolling average, and question 2 is my addition.
- **primary_tasks:**
  1. Read the chart.
  2. Open or list an unusual item.
  3. Configure the gadget for the first time.
  4. Change its configuration.
  - The configuration fields in this example are invented for illustration: a data source (such as a board or a saved filter), a date range, and the workflow statuses that count as start and finish.
- **decisions:**
  - `spread_statistic`: undecided. The options are the standard deviation, which Atlassian's documentation says its own chart shows; percentile lines, which a Kanban-metrics practitioner recommends for skewed lead times; and process limits computed from moving ranges, as in the NIST handbook. See `03-data-visualisation.md`, section 5.2. [VERIFIED | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27] [VERIFIED as read by a sub-agent | connected-knowledge.com/2014/09/07/inside-lead-time-distribution | 2014-09-07] [VERIFIED as read by a sub-agent | itl.nist.gov/div898/handbook/pmc/section3/pmc322.htm | accessed 2026-09-27]
- **platform:**
  - The Atlassian Design System, with values from `@atlaskit/tokens` version 20.0.0. [VERIFIED as read by a sub-agent | app.unpkg.com/@atlaskit/tokens@20.0.0 | accessed 2026-09-27]
  - Forge Custom UI, because UI Kit has no scatter chart. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components | accessed 2026-09-27]
- **host:**
  - The `dashboards:widget` module became generally available on 22 September 2026. The older `jira:dashboardGadget` module was deprecated on 23 September 2026, with removal on 17 May 2027. [VERIFIED as read by a sub-agent | developer.atlassian.com/changelog | 2026-09-23]
  - The widget's hooks page and its module reference page were still labelled Early Access, which is not for production use, when read in September 2026. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | 2026-09-14] [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/dashboard-widget | 2026-09-08] The harness should record the module's status at every run.
  - The widget's layout context gives its pixel size, a row span from xsmall to large, and a column span of 3, 4, 6, 8 or 12. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | 2026-09-14]
- **weights:** Native fit is high: the gadget should look like part of Jira. Originality is low. Density is moderate.
  - Counter-case: a gadget that looks exactly like Jira's own control chart may be judged redundant. The person may prefer a clearer spread statistic over familiarity; that is the `spread_statistic` decision.
- **approver:** the project owner.
- **candidates_per_iteration:** 3. **max_iterations:** 5. **finalists:** 3.
- **budget:** not set in this example. The project sets it before the first run.
- **judge_model_family:** a different family from the generator's, where available.
- **calibration:** none yet. Step 0 creates the three label sets and records the target.

### W1.2 Render matrix

[ASSUMPTION for the choices]
- **Sizes.** Column spans 3, 6 and 12, each at row spans small and large, giving six size cells.
  - The pixel heights of the row spans are NOT FOUND. The harness therefore reads them from the widget context on a developer site, which is a test Atlassian site where a developer installs an app, and records them.
  - If the older gadget module is used instead, its reference page gives no size guidance [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/jira-dashboard-gadget | 2025-08-12], so the harness uses fixed widths of 300, 600 and 1200 pixels as stand-ins.
- **Themes.** Light and dark. [VERIFIED as read by a sub-agent | atlassian.design/foundations/tokens/design-tokens | accessed 2026-09-27]
- **Chart states, each with its own fixture:**
  - typical: about 60 completed items over 90 days;
  - dense (the dense fixture): about 400 items, with many finishing on the same days;
  - sparse: 3 items;
  - empty: no items in the range;
  - loading: the widget context is not yet available, which the hooks page says happens while it loads [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | 2026-09-14];
  - error: the data request fails, or permission is missing;
  - long text: item summaries and labels lengthened by 40%.
- **Configuration states:** first use, filled in, and with validation errors.

### W1.3 Overrides of universal lines

[ASSUMPTION unless labelled]
- **U-01 uses Atlassian's stricter large-text cut-off.** Atlassian requires 4.5:1 for all text smaller than 24 pixels. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27] That is stricter than WCAG for bold text between about 18.5 and 24 pixels.
- **U-11 is replaced for an embedded component.**
  - The gadget does not control the page, so the check becomes: no horizontal scrolling inside the widget at column span 3, and no loss of content at 200% zoom of the dashboard.
  - Counter-case: at 200% zoom the host dashboard may itself give the widget a different span, so the harness must record which span it actually got.
- **U-12 sets the floor at 12 pixels for chart labels and 14 pixels for body text.**
  - These are Atlassian's small and default body sizes. [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27]
  - The 12-pixel floor for charts also matches Chartability's minimum. [VERIFIED as read by a sub-agent | chartability.github.io/POUR-CAF | accessed 2026-09-27]
- **U-13 does not apply,** because the gadget has no long passages of text.

### W1.4 Platform lines (supplied by this project)

| ID | Rule | Check | Pass when | Severity | Source |
|---|---|---|---|---|---|
| P-01 | Spacing uses Atlassian's scale. | script | Every margin, padding and gap is 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64 or 80 pixels, or one of the negative values −2, −4, −6, −8, −12, −16, −20, −24 or −32 pixels, within half a pixel. | major | [VERIFIED \| atlassian.design/foundations/spacing \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-spacing.js \| accessed 2026-09-27] for the negative values |
| P-02 | Type uses Atlassian's scale. | script | Every size and line-height pair is one of 12/16, 14/20, 16/20, 16/24, 20/24, 24/28, 28/32 or 32/36, and every weight is 400, 500, 600 or 653. Text inside code elements is checked separately, at 0.875 times its parent's font size, because Atlassian's code token is relative (see `02-automated-checks.md`). | major | [VERIFIED \| atlassian.design/foundations/typography \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-typography.js \| accessed 2026-09-27] |
| P-03 | Text is rendered in Atlassian Sans, not a fallback font. | script | The computed font family starts with Atlassian Sans, and the font has actually loaded. | major | [VERIFIED \| atlassian.design/foundations/typography \| accessed 2026-09-27]; [PARTIAL \| community.developer.atlassian.com/t/new-atlassian-fonts-in-forge-apps-with-custom-ui/93747 \| 2025-07-10] for the loading problem in Custom UI |
| P-04 | Every colour is an Atlassian token value in the active theme. | script | Every computed colour equals a resolved token value, in the light theme and in the dark theme. | major | [VERIFIED as read by a sub-agent \| cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-light.js \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-dark.js \| accessed 2026-09-27] |
| P-05 | Chart parts use their assigned tokens. | script | Dots use `color.chart.brand`, and reference lines use `color.chart.neutral`. Tick labels use `color.text.subtle`, and gridlines and axes use `color.border`. The title and legend use `color.text`. | major | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| P-06 | The chart uses at most six categorical colours, in the palette's order. | script | The number of distinct categorical chart colours is six or fewer, and they appear in the palette's order. Atlassian says five to six; this line uses the upper end so that a script has one number. | major | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| P-07 | No text is placed on chart colours. | script | No text box overlaps a chart-coloured fill, because Atlassian says those pairings cannot reach 4.5:1. | major | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| P-08 | Interface text uses sentence case and Atlassian's punctuation rules. | script+judge | A script checks that titles, headings, labels and buttons are in sentence case, that headings, tooltips and field descriptions have no full stops, and that `&`, `e.g.`, `i.e.` and `etc.` are not used. The judge decides only whether a flagged capital belongs to a proper noun. | minor | [VERIFIED as read by a sub-agent \| atlassian.design/foundations/content/language-and-grammar \| accessed 2026-09-27] |
| P-09 | The configuration form follows Atlassian's form pattern. | script+judge | A script checks that labels sit left-aligned above their fields, that errors appear below the field, and that field widths are 75, 150, 250, 350 or 500 pixels. The judge checks that required fields are marked, unless all are required. | major | [VERIFIED as read by a sub-agent \| atlassian.design/patterns/forms \| accessed 2026-09-27] |
| P-10 | Each area has one primary button, and button labels start with a verb. | script+judge | A script counts at most one primary button per area. The judge checks that every label starts with a verb. | minor | [VERIFIED as read by a sub-agent \| atlassian.design/components/button/usage \| accessed 2026-09-27] |
| P-11 | The source code passes Atlassian's design-system lint rules. | script | The ESLint recommended preset and the Stylelint rules report no errors. Source-code linters probably miss chart colours passed to a chart library as properties, so P-05 and P-06 check chart colours on the rendered chart instead. | major | [VERIFIED as read by a sub-agent \| cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md \| accessed 2026-09-27] for the lint rules; [ASSUMPTION] for what linters miss |
| P-12 | The gadget follows Jira's theme. | script | `view.theme.enable()` is called, and P-04 passes in the dark theme. | blocker | [VERIFIED as read by a sub-agent \| developer.atlassian.com/platform/forge/design-tokens-and-theming \| 2024-10-30] |
| P-13 | Error and empty messages follow Atlassian's structure. | script+judge | A script counts the words: an error has a title of 3 to 4 words, a body of 1 to 2 sentences and an action of 1 to 2 words, and an empty state has a short title and 1 to 2 sentences. The judge checks that an error gives the cause and the fix, without the words `sorry` or `please`. | minor | [VERIFIED as read by a sub-agent \| atlassian.design/foundations/content/designing-messages/error-messages \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| atlassian.design/foundations/content/designing-messages/empty-state \| accessed 2026-09-27] |
| P-14 | Corner radius uses Atlassian's radius tokens. | script | Every computed border radius is 2, 4, 6, 8, 12 or 16 pixels, or 999 pixels or more for a fully rounded shape. A radius of 0, meaning no rounding, is also allowed. | minor | [VERIFIED as read by a sub-agent \| atlassian.design/foundations/radius \| accessed 2026-09-27]; the design-tokens page marks radius as Beta [VERIFIED as read by a sub-agent \| atlassian.design/foundations/tokens/design-tokens \| accessed 2026-09-27]; [ASSUMPTION] for allowing 0 |

### W1.5 Taste and purpose lines (supplied by this project and its approving person)

| ID | Rule | Check | Pass when | Severity | Source |
|---|---|---|---|---|---|
| T-01 | The chart answers its key questions at a glance. | probe | At column spans 3 and 12, the judge's answers match the expected answers in the header, within their tolerances. | major | [ASSUMPTION] |
| T-02 | Every band or line names its statistic, and is drawn where that statistic lies. | script | Each line has a label naming its statistic, and a rolling average also names its window. Each line's position is within 1 pixel of the value computed from the fixture. No line or band extends below zero. | blocker | [ASSUMPTION, from `03-data-visualisation.md`, rule 40 and section 5.2] |
| T-03 | Unusual items stand out by shape as well as colour, and can be reached without precise pointing. | script+judge | A script checks that unusual items use a different marker shape; U-03 already requires some second cue, and this line asks specifically for a shape. The judge checks that a list or table of the items is offered as an equivalent to small dots. | major | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/target-size-minimum.html \| 2026-05-11] |
| T-04 | The cycle-time axis starts at zero. | script | The y-axis minimum is 0. Round tick values and the ban on a second y-axis are already checked by U-18, as rules 15 and 7 of `03-data-visualisation.md`, so they are not counted again here. | major | [ASSUMPTION] (see `03-data-visualisation.md`, section 5.4) |
| T-05 | Overlapping points stay visible. | judge | The judge confirms that screenshots of the dense fixture show clusters through transparency or counts. The shuffle test itself, rule 38 of `03-data-visualisation.md`, is part of U-18, so it is not counted again here. | major | [VERIFIED as read by a sub-agent \| clauswilke.com/dataviz/overlapping-points.html \| accessed 2026-09-27]; [VERIFIED as read by a sub-agent \| arxiv.org/pdf/2001.02316 \| 2020] for the shuffle test |
| T-06 | The gadget looks like part of Jira. | judge | Used only inside comparisons: the judge sees a reference screenshot of native Atlassian screens on the same dashboard, and prefers the candidate that fits it better. | ranking | [ASSUMPTION; see `01-benchmark.md`, "Two findings that nearly made this list"] |
| T-07 | A first-time user can configure the gadget without guessing. | judge | Sensible defaults are filled in where possible. Every field has a label and, where needed, helper text. Saving gives visible feedback, and a wrong entry gets a specific message. | major | [ASSUMPTION] |

Each active taste note adds one more line, T-08 onwards. Its rule is the note's statement, its check is `judge`, and its severity is the one recorded in the note. The taste log starts empty; section I8 of `04-ai-evaluation.md` gives an invented example of the format. Counter-case for T-07: a model is not a first-time user, so a short test with real first-time users is still needed before release. [ASSUMPTION]

### W1.6 What the person decides in this example

[ASSUMPTION]
1. The `spread_statistic` decision, because it changes what the chart claims.
2. The unknowns on blocker and major lines, and every comparison whose two orders disagreed.
3. The final choice among the three finalists.
4. Every proposed taste note.

---

## W2. Worked example: a document-heavy business web application

### W2.1 Header

[ASSUMPTION for every value unless a label says otherwise]
- **rubric_version:** 1.
- **purpose:** Let office users find, read, compare and update business documents and their details.
- **key_questions,** each with its expected answer and tolerance:
  1. Which documents changed most recently? The expected answer is the three most recently changed documents in the fixture, in order, matched exactly.
  2. Who owns this document, and what is its status? The expected answer is the owner and the status in the fixture, matched exactly.
  3. What does this section of the document say? The expected answer is the one fact seeded in that section of the fixture.
  4. What changed between these two versions? The expected answer is the list of changes seeded in the two fixture versions, matched exactly.
- **primary_tasks:**
  1. Find a document with search and filters.
  2. Read it comfortably.
  3. Edit its details in a form and save.
  4. Compare two versions.
  - These screens are invented for illustration.
- **decisions:**
  - `density`: undecided, compact or comfortable. Information density was one of the four themes on which designers' written reasons diverged in DesignPref. [VERIFIED as read by a sub-agent | arxiv.org/html/2511.20513v1 | 2025-11-25]
  - `reading_text_size`: undecided, between the 16-pixel default of this example and the 19 to 24 pixels that some sources suggest (see W2.3).
- **platform:** The project names its own design system. For illustration, this example uses IBM Carbon, whose spacing scale and type sizes are public. [VERIFIED as read by a sub-agent | carbondesignsystem.com/elements/spacing/overview and carbondesignsystem.com/elements/typography/type-sets | 2026-09-23]
- **host:** full pages in a desktop or mobile browser.
- **weights:** Clarity and density suited to long working sessions are high. Originality is low. Native fit with the chosen design system is high.
- **approver:** the product owner.
- **candidates_per_iteration:** 2. **max_iterations:** 4. **finalists:** 2.
  - The smaller numbers reflect that the screens are many and the differences are mostly layout and density. Counter-case: fewer candidates explore less.
- **budget:** not set in this example. The project sets it before the first run.
- **judge_model_family:** a different family from the generator's, where available.
- **calibration:** none yet. Step 0 creates the three label sets and records the target.

### W2.2 Render matrix

[ASSUMPTION for the choices]
- **Widths.** 320, 768, 1280 and 1920 CSS pixels. The 320 comes from WCAG's reflow width [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/reflow.html | 2026-08-10], and 1280 is Playwright's default viewport width [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-testoptions | accessed 2026-09-27]. A 200% zoom cell is added at 1280.
- **Themes.** Light, plus dark if the product supports it.
- **States, each with a fixture:**
  - an empty list, one document, and 10,000 documents with paging;
  - very long document titles, lengthened by 40%;
  - a document with 50 headings;
  - the details form with validation errors;
  - loading, error and permission-denied states.

### W2.3 Overrides of universal lines

- **U-11 applies in full, because these are full pages.** Data tables may scroll sideways, but the headings, search fields and paging that belong to a table must still reflow. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/reflow.html | 2026-08-10]
- **U-12 sets the body-text floor at 16 pixels in the reading pane and 14 pixels in dense tables,** until the `reading_text_size` decision is made. [ASSUMPTION]
  - The sources give different sizes. Carbon's and Atlassian's body text is 14 pixels. [VERIFIED as read by a sub-agent | carbondesignsystem.com/elements/typography/type-sets | 2026-09-23] [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27] GOV.UK's body text is 19 pixels. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/type-scale | accessed 2026-09-27]
  - One reading study tracked the eye movements of 104 volunteers, recruited through schools and universities in one city district, as they read at six sizes from 10 to 26 points. Its authors recommend body text of at least 18 points. [VERIFIED as read by a sub-agent | pielot.org/pubs/Rello2016-Fontsize.pdf | 2016] By WCAG's conversion, 18 points is about 24 CSS pixels. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/contrast-minimum.html | 2026-06-01]
  - Counter-case: following GOV.UK would mean 19 pixels, and following the reading study about 24 pixels, at the cost of fewer lines per screen. That is the person's `reading_text_size` decision. [ASSUMPTION]
- **U-13 sets 75 characters per line in the reading pane.** This follows GOV.UK. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/layout | accessed 2026-09-27] WCAG's Level AAA criterion 1.4.8 only asks for a way to limit lines to 80 characters, which a browser may provide. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/visual-presentation.html | 2026-03-09]

### W2.4 Platform lines, with IBM Carbon as the illustration

| ID | Rule | Check | Pass when | Severity | Source |
|---|---|---|---|---|---|
| P-01 | Spacing uses Carbon's scale. | script | Every margin, padding and gap is 2, 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96 or 160 pixels, within half a pixel. | major | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/elements/spacing/overview \| 2026-09-23] |
| P-02 | Type uses Carbon's productive type set, the type styles Carbon provides for product screens. | script | Body text is 14 on 20 at weight 400. Headings are 14 on 20 at 600, 16 on 24 at 600, or 20 on 28 at 400. Larger styles are added from Carbon's documentation. | major | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/elements/typography/type-sets \| 2026-09-23] |
| P-03 | Styles use Carbon's tokens. | script | Carbon's Stylelint plugin reports no errors. | major | [VERIFIED as read by a sub-agent \| github.com/carbon-design-system/stylelint-plugin-carbon-tokens \| accessed 2026-09-27] |
| P-04 | Any chart uses Carbon's categorical palette in its defined order. | script | The colours appear in the listed sequence. | major | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/data-visualization/color-palettes \| accessed 2026-09-27] |

### W2.5 Taste and purpose lines

| ID | Rule | Check | Pass when | Severity | Source |
|---|---|---|---|---|---|
| T-01 | The list and reader screens answer their key questions. | probe | The judge's answers to key questions 1 to 3 match the expected answers. | major | [ASSUMPTION] |
| T-02 | Numbers in tables line up. | script | Numeric columns are right-aligned and use tabular figures. | major | [VERIFIED \| design-system.service.gov.uk/components/table \| accessed 2026-09-27]; [VERIFIED \| developer.mozilla.org/en-US/docs/Web/CSS/font-variant-numeric \| 2026-09-10] |
| T-03 | Tables describe themselves. | script | Every data table has a caption or an equivalent heading. | minor | [VERIFIED \| design-system.service.gov.uk/components/table \| accessed 2026-09-27] |
| T-04 | Shortened titles can still be read in full. | script | Every title cut off with an ellipsis shows its full text on hover, on keyboard focus, and in the reader. | major | [ASSUMPTION, extending U-08] |
| T-05 | Headings in the reader form a clean outline. | script | The reader has one main heading, and no heading level is skipped. | minor | [VERIFIED \| atlassian.design/foundations/typography \| accessed 2026-09-27] for one main heading per page; [ASSUMPTION] for applying it here and for no skipped levels |
| T-06 | Density follows the `density` decision. | judge | Each screen follows the density recorded in the header. | major | [ASSUMPTION] |
| T-07 | The version-comparison screen makes differences findable without reading everything. | probe | The judge's answer to key question 4, given from the screenshots alone, names all the seeded changes. | major | [ASSUMPTION] |

Each active taste note adds one more line, T-08 onwards, as in W1.

### W2.6 What the person decides in this example

[ASSUMPTION]
1. The `density` decision.
2. The `reading_text_size` decision.
3. The final choice between the two finalists.
4. Every proposed taste note.

---

## Negative results for this file

- A published, complete rubric format for automated design evaluation that could be adopted as is: NOT FOUND. The closest are Anthropic's four criteria, ArtifactsBench's per-task checklists, and Rubrics as Rewards' typed items. [VERIFIED | anthropic.com/engineering/harness-design-long-running-apps | 2026-03-24] [VERIFIED as read by a sub-agent | arxiv.org/html/2507.04952 | 2025-09-29] [VERIFIED as read by a sub-agent | arxiv.org/html/2507.17746v2 | 2025-10-03]
- Pixel heights of the Forge widget's row spans: NOT FOUND.
- A validated number of labelled items for design taste specifically: NOT FOUND. The numbers in Step 0 come from general judge-building advice.
- No source reviewed here gives a validated agreement target for a design judge. The 10-point margin in Step 0 is my proposal.
