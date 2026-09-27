# 02 — Automated checks: universal quality, design-system conformance, and conformance to an approved design (status on 27 September 2026)

**Sources and how they were selected.** This file cites 170 sources (distinct web pages), all listed in `sources.csv`. It answers research questions 1, 2 and 5.
- **How they were found.** Three research sub-agents covered these questions, running about 90 web searches and about 380 page fetches. Part C4 also draws on the two sub-agents that studied AI judges.
- **Selection order.**
  1. The owning source first: the W3C Recommendation, its "Understanding" and test-rule pages, each tool's own documentation, repository and published package files, and the original papers.
  2. Secondary sources only where no primary page could be read. These are labelled PARTIAL.
- **Pages that could not be read.** Some pages build their content with JavaScript and came back empty: some atlassian.design pages, Material Design 3 and Apple's Human Interface Guidelines. For Atlassian, the sub-agent read the published package files of `@atlaskit/tokens` 20.0.0 instead.
- **What I re-read myself.** The Atlassian spacing, typography and data-visualisation colour pages, the Forge widget context page, the GOV.UK table page, the MDN page on numeric figures, Anthropic's frontend-design skill file, the UI-Lens abstract, and Playwright's ARIA snapshots page.
- **What was actually seen.** No images were viewed; all statements come from page text.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. Definitions, method notes and numbered instructions are not research claims and carry no label. A label on the line that introduces a list or table applies to every item in it.

**Terms used in this file.**
- The **harness** is the set of scripts, agents and rules around an AI model that checks its work. The **plugin** is the reusable package that ships the generic part of it.
- **CI** (continuous integration) is the automated server that builds and tests the code on every change.
- **UI Kit** and **Custom UI** are the two ways to build a screen in Atlassian Forge. In UI Kit, Atlassian's own components draw the screen. In Custom UI, the app's own HTML and JavaScript run in a frame inside Jira.
- The **DOM** (Document Object Model) is the browser's tree of the elements on a page.
- A **computed style** is the final value of a CSS property that the browser applies to an element after all style rules are combined, for example `font-size: 14px`.
- A **bounding box** is the rectangle an element occupies on screen, given by its x and y position, width and height.
- A **CSS pixel** is the browser's unit of layout. On a high-density screen one CSS pixel covers several physical pixels.
- The **viewport** is the visible area of the browser window.
- A **baseline**, also called a golden image, is a stored screenshot that a person approved. A **visual regression test** compares a new screenshot with the baseline.
- A **threshold**, or tolerance, is how much difference a comparison accepts before it fails.
- **Anti-aliasing** is the smoothing of edges with in-between colours. It differs between machines and causes harmless pixel differences.
- A **lint rule** is an automated check that reads source code without running it.
- A **design token** is a named design value, such as `space.200` = 16 pixels, defined once and referenced everywhere.
- An **allow-list** is the set of values a check accepts.
- `00-glossary.md` defines every other term.

---

## Read first: what can be measured, by what, and what it misses

This table summarises Part A. Each row is expanded in the section named in the first column. [ASSUMPTION for the summary; each fact is labelled in its section]

| Check (section) | Default threshold | Off-the-shelf tool | What the tool misses | What the harness should add |
|---|---|---|---|---|
| Text contrast (A1) | At least 4.5:1, or 3:1 for large text. | The axe-core rule `color-contrast`, also inside Lighthouse. | It defers text over images and gradients, and never sees hover or focus states it did not trigger. | Trigger each state and re-run the check, and run it again in the dark theme. |
| Non-text contrast (A2) | At least 3:1 for chart marks, input borders and focus indicators. | No axe-core rule exists. | No rule exists, so the tool misses all of it. | Compute contrast between each SVG stroke or fill, each border, and the background behind it. |
| Colour not the only cue (A3) | A second cue exists. | `link-in-text-block` covers links in text only. | It misses colour-only cues in charts, status badges and form errors. | Ask the model judge, and script the chart part (series differ by marker or dash). |
| Focus visible and not hidden (A4) | A visible change on focus, and not fully covered by other content. | No axe-core rule exists. | No rule exists, so the tool misses all of it. | Tab through the page; compare screenshots before and after focus; test what covers the focused element. |
| Target size (A5) | At least 24 by 24 CSS pixels, or enough spacing. | axe-core `target-size`, which is off by default. | Exceptions that need judgement, such as an equivalent control elsewhere. | Enable the rule explicitly and confirm that it ran. |
| Reflow, zoom and text spacing (A6) | No two-way scrolling at 320 CSS pixels; no loss at 200% zoom; no loss with the WCAG spacing values. | Only indirect rules exist, such as one that fails a page that blocks zoom. | It cannot detect text that is actually clipped or overlapping. | Render at 320 pixels, zoom, and inject the spacing values, then run the overflow checks. |
| Type scale and line length (A7) | Sizes from the project's scale; lines within the project's character limit. | No tool checks this; Lighthouse removed its font-size audit. | No tool checks it, so all of it is missed. | Read computed font sizes; measure characters per line from rendered text. |
| Spacing and alignment (A8) | Values from the project's spacing scale. | No tool checks spacing on the rendered page. | No tool checks it, so all of it is missed. | Read computed margins, paddings and gaps, and cluster element edges into alignment lines. |
| Overflow, clipping and overlap (A9) | None allowed, except deliberate truncation with the full text available. | Only research tools were found, such as ReDeCheck. | No mainstream checker was found for this, so a harness gets nothing here without its own script. | Compare each element's scroll size with its visible size, and test boxes for overlap, at every render size and with longer strings. |

---

## Part A — Universal checks that code can measure (research question 1)

### A1. Text contrast

**The rules.**
- WCAG 2.2 success criterion 1.4.3, level AA, requires a contrast ratio of at least 4.5:1 for text and 3:1 for large-scale text. Text in inactive components, pure decoration and logotypes is exempt. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]
- Large-scale text means at least 18 point, or 14 point bold. The Understanding page converts these to about 24 pixels and about 18.5 pixels. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/contrast-minimum.html | updated 2026-06-01]
- Criterion 1.4.6, level AAA, raises the ratios to 7:1 and 4.5:1. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]

**Three details a script must get right.** [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/contrast-minimum.html | updated 2026-06-01]
- Ratios must not be rounded, so 4.499:1 fails.
- The colours to use are those set by the stylesheets, not the anti-aliased pixels on screen.
- Thin or unusual fonts can look much fainter than their CSS colour suggests. The page gives no measurement method for text over gradients, background images or text shadows.

**The standard tool, axe-core.** axe-core is Deque's open-source accessibility rule engine, used inside many other tools.
- Its `color-contrast` rule checks 1.4.3 and can return either a failure or "needs review", which axe calls incomplete. Its `color-contrast-enhanced` rule checks 1.4.6 but is disabled by default, like all AAA rules. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md | accessed 2026-09-27]
- axe returns "needs review" for contrast in all of these cases. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/locales/_template.json | accessed 2026-09-27]
  - A background image or gradient.
  - An image element inside the text.
  - Overlap by another element.
  - Complex text shadows or semi-transparent text.
  - Text outside the viewport, or text too short to judge.
  - Pseudo-element backgrounds.
  - A colour it cannot parse.
- Deque's rule page describes large text as 24 CSS pixels, or 19 pixels when bold. [VERIFIED as read by a sub-agent | dequeuniversity.com/rules/axe/4.10/color-contrast | accessed 2026-09-27] That rounds WCAG's approximate 18.5 pixels upwards, so the two can disagree on bold text of 18.5 to 19 pixels. [ASSUMPTION]

**The shared test rule.** The W3C test rule for text contrast (ACT rule afw4f7) handles gradients and images by taking the highest possible contrast against the background pixels inside the text's box. [VERIFIED as read by a sub-agent | w3.org/WAI/standards-guidelines/act/rules/afw4f7 | 2023-08-30] Because it takes the highest contrast, it can pass text that has enough contrast over only part of its background. [ASSUMPTION]

**What WAVE misses.** WebAIM says WAVE's contrast check does not account for background images, gradients or transparency, and cannot detect text inside images. [VERIFIED as read by a sub-agent | webaim.org/articles/contrast/evaluating | 2021-01-09]

**How common the failure is.**
- Sample: WebAIM scanned one million home pages from a top-sites list with the WAVE engine. [VERIFIED as read by a sub-agent | webaim.org/projects/million | updated 2026-03-30]
- Result: 95.9% of home pages had detected WCAG 2 failures, and low-contrast text was the most common, on 83.9% of home pages. [VERIFIED as read by a sub-agent | webaim.org/projects/million | updated 2026-03-30]

**What the harness should add.** [ASSUMPTION]
- Run the contrast rule in every state the design has: default, hover, focus, selected, error, and both light and dark themes.
- Send every "needs review" result to the model judge with a cropped screenshot.
- Do not treat an empty violations list as a pass unless the needs-review list is also empty or resolved.
- Counter-case: states multiply the run time. For a small gadget with a handful of controls this is cheap; for a large application the state list should be sampled.

### A2. Non-text contrast (chart marks, input borders, focus indicators)

**The rule.**
- Criterion 1.4.11, level AA, requires 3:1 against adjacent colours in two cases: the visual parts needed to identify controls and their states, and the parts of graphics needed to understand the content. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]
- The Understanding page confirms that 1.4.11 applies to charts and graphs. A graphic need not meet it when text labels and values on the chart carry the same information. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/non-text-contrast.html | updated 2026-06-15]
- A focus indicator must contrast with the adjacent background under 1.4.11. The criterion sets no required contrast between the focused and unfocused states. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/non-text-contrast.html | updated 2026-06-15]

**No automated coverage.**
- No axe-core rule is tagged for 1.4.11. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md | accessed 2026-09-27]
- Deque's 2022 coverage report, a vendor study of audits of its own customers' pages, shows 0% automated coverage for 1.4.11 in its appendix. [VERIFIED as read by a sub-agent | accessibility.deque.com/hubfs/Semi-Automated-Accessibility-Testing-Coverage-Report.pdf | 2022-03-11]

**What the harness should add.** [ASSUMPTION]
- For each SVG path, line, circle or rectangle in a chart, and for each input border, read the computed stroke or fill colour and the colour behind it, and compute the WCAG ratio.
- Flag anything below 3:1. The model judge then decides whether the element is actually needed for understanding, which is the part a script cannot decide.
- A chart drawn on an HTML canvas exposes no computed styles for its marks, so this check needs SVG charts or access to the chart's configuration. Counter-case: canvas charts are faster with thousands of points.

### A3. Colour must not be the only cue

**The rule.** Criterion 1.4.1, level A, says colour must not be the only visual means of conveying information, indicating an action, prompting a response or distinguishing an element. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]

**What is automated.**
- axe-core's `link-in-text-block` rule covers only links inside blocks of text. It asks a person to confirm hover and focus styling when a link differs from the surrounding text by colour alone at 3:1 or more. [VERIFIED as read by a sub-agent | dequeuniversity.com/rules/axe/4.10/link-in-text-block | accessed 2026-09-27]
- Deque's appendix shows 12.17% of 1.4.1 issues found automatically. [VERIFIED as read by a sub-agent | accessibility.deque.com/hubfs/Semi-Automated-Accessibility-Testing-Coverage-Report.pdf | 2022-03-11]
- In the UK Government Digital Service test described in A10, links identified only by colour were missed by every tool. [VERIFIED as read by a sub-agent | accessibility.blog.gov.uk/2017/02/24/what-we-found-when-we-tested-tools-on-the-worlds-least-accessible-webpage | 2017-02-24]

**What the harness should add.** [ASSUMPTION]
- For charts, a script can check that series differ in at least one property other than colour: marker shape, dash pattern, or a direct text label.
- For everything else, such as status badges and form errors, the model judge checks with a greyscale version of the screenshot.
- Counter-case: greyscale judging depends on the model's weak perception of small differences; see `01-benchmark.md`, C7.

### A4. Keyboard focus: visible, not hidden, clearly drawn

**The rules.**
- Criterion 2.4.7 Focus Visible, level AA, requires a mode in which the keyboard focus indicator is visible. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/focus-visible.html | updated 2026-07-12]
- Criterion 2.4.11 Focus Not Obscured (Minimum), level AA, fails only when content the author created, such as a sticky header, cookie banner or non-modal dialog, hides the focused element entirely. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html | updated 2026-06-15]
- Criterion 2.4.13 Focus Appearance, level AAA, has two conditions. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/focus-appearance.html | updated 2026-08-10]
  - The indicator's area must be at least as large as a 2 CSS pixel thick outline around the element. For a rectangle this is 4 × height + 4 × width, so a 90 by 30 pixel button needs 480 square pixels of changed area.
  - The changed pixels must have at least 3:1 contrast between the focused and unfocused states.

**No automated coverage.**
- No axe-core rule is tagged for 2.4.7, 2.4.11 or 2.4.13. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md | accessed 2026-09-27]
- Deque's appendix shows 2.4.7 as 0% automatic and 100% through guided human tests. [VERIFIED as read by a sub-agent | accessibility.deque.com/hubfs/Semi-Automated-Accessibility-Testing-Coverage-Report.pdf | 2022-03-11]
- The approved W3C test rule for visible focus (oj04fd) passes if at least one device pixel changes colour when the element receives focus. The rule page warns that a very subtle change could pass and still be inaccessible. [VERIFIED as read by a sub-agent | w3.org/WAI/standards-guidelines/act/rules/oj04fd | 2023-08-30]

**What the harness should add.** [ASSUMPTION]
1. Press Tab through every focusable element.
2. For each one, take a screenshot of its region before and after focus.
3. Count the changed pixels and compare their area with the 4h + 4w rule.
4. Compute the contrast between the old and new colours of the changed pixels.
5. Test whether another element covers the focused element's box, for example by asking the browser which element sits at its centre and corners.

- The project chooses whether the AAA area rule is a blocker or a warning.
- Counter-case: the changed-pixel method also counts harmless changes, such as a tooltip appearing, so its report needs the model judge to confirm what changed.

### A5. Target size

**The rules.**
- Criterion 2.5.8, level AA, requires pointer targets of at least 24 by 24 CSS pixels. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/target-size-minimum.html | updated 2026-05-11]
  - The exceptions are enough spacing, an equivalent control elsewhere on the page, targets inside a sentence, sizes set by the browser, and presentation that is essential.
  - The spacing test draws a 24 pixel circle centred on each undersized target. The target passes if its circle touches neither another target nor another undersized target's circle.
- Criterion 2.5.5, level AAA, requires 44 by 44 CSS pixels and has no spacing exception. Its Understanding page cites no research for the number. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html | updated 2026-05-11]
- Android's accessibility guidance asks for 48 by 48 dp touch targets, where dp is Android's density-independent pixel. [VERIFIED as read by a sub-agent | developer.android.com/guide/topics/ui/accessibility/apps | updated 2026-09-22] The Atlassian Design System gives no target size in pixels (NOT FOUND after searching its accessibility and button pages).

**The tools.**
- axe-core's `target-size` rule checks 2.5.8 and is the only rule in its WCAG 2.2 table. The documentation says WCAG 2.2 rules stay disabled by default until WCAG 2.2 is more widely adopted. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md | accessed 2026-09-27]
- The rule returns "needs review" in three cases: when an element might or might not be a target, when overflowing content makes the size uncertain, and when too many elements overlap. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/locales/_template.json | accessed 2026-09-27]
- Playwright's accessibility guide shows axe tags up to WCAG 2.1 only (wcag2a, wcag2aa, wcag21a, wcag21aa). [VERIFIED as read by a sub-agent | playwright.dev/docs/accessibility-testing | accessed 2026-09-27] A harness that copies that example never runs `target-size` unless it adds the `wcag22aa` tag. [ASSUMPTION]
- Lighthouse 12.0.0 replaced its own tap-target audit with axe's `target-size`. [VERIFIED as read by a sub-agent | github.com/GoogleChrome/lighthouse/releases/tag/v12.0.0 | 2024-04-22] Lighthouse's current configuration weights that rule at 7, although its documentation's weights table does not list it. [VERIFIED as read by a sub-agent | github.com/GoogleChrome/lighthouse/blob/main/core/config/default-config.js | accessed 2026-09-27]

**What the harness should add.** [ASSUMPTION]
- Enable `target-size` explicitly and assert from the axe output that the rule actually ran.
- In dense charts, where each data point is clickable, 24-pixel targets are usually impossible. The accepted route is the "equivalent control" exception: the same items reachable in a table or list. The model judge, not the script, confirms that the equivalent exists.
- Counter-case: some teams treat chart points as decoration, not targets; then the rule does not apply, but the chart must then offer another way to reach the items.

### A6. Zoom, reflow and text spacing

**The rules.**
- Criterion 1.4.4 Resize Text, level AA, requires text to be resizable to 200% without loss of content or function. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]
- Criterion 1.4.10 Reflow, level AA, forbids two-way scrolling at a width of 320 CSS pixels for vertically scrolling content. The Understanding page equates this to a 1280-pixel window at 400% zoom. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/reflow.html | updated 2026-08-10]
  - The exceptions include maps, diagrams, video, games, presentations and data tables, but not individual table cells. Headings, search fields and pagination that belong to a table must still reflow.
  - Charts and graphs are not named in the exception.
  [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/reflow.html | updated 2026-08-10]
- Criterion 1.4.12 Text Spacing, level AA, requires that nothing is lost when a user sets these four values. [VERIFIED as read by a sub-agent | w3.org/TR/WCAG22 | 2024-12-12]
  - Line height to 1.5 times the font size.
  - Space after paragraphs to 2 times the font size.
  - Letter spacing to 0.12 times the font size.
  - Word spacing to 0.16 times the font size.
- The 1.4.12 Understanding page says authors need not use these values by default. It names clipped, cut-off and overlapping text as the typical failures. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/text-spacing.html | updated 2025-10-01]

**What the tools check.** This is only indirect.
- axe-core's `meta-viewport` rule fails a page whose viewport tag disables zoom or caps it below 2. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/check-options.md | accessed 2026-09-27]
- Its `avoid-inline-spacing` rule only flags spacing forced with `!important` inside a style attribute. [VERIFIED as read by a sub-agent | dequeuniversity.com/rules/axe/4.10/avoid-inline-spacing | accessed 2026-09-27] It therefore cannot tell whether text is actually clipped when spacing grows. [ASSUMPTION]
- A proposed W3C test rule (59br37) renders the page at 640 by 512 pixels, the equivalent of 200% zoom. It then checks that text inside containers with hidden or clipped overflow is not clipped, unless the clipping is deliberate. [VERIFIED as read by a sub-agent | w3.org/WAI/standards-guidelines/act/rules/59br37 | accessed 2026-09-27]
- No axe-core rule is tagged for 1.4.10. [VERIFIED as read by a sub-agent | github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md | accessed 2026-09-27]

**What the harness should add.** [ASSUMPTION]
- Render at 320 CSS pixels wide, at 200% zoom, and with a stylesheet injecting the four spacing values.
- In each case, run the overflow and overlap checks from A9.
- Counter-case: an embedded gadget does not control the page it sits in, so "reflow at 320 pixels" is really a question for the host page. For the gadget itself, the equivalent check is its narrowest allowed size, described in `05-template.md`.

### A7. Typography: sizes, line length and line height

**WCAG sets no minimum font size.**
- The US government's accessibility site says neither WCAG nor Section 508 specifies a minimum font size. [VERIFIED as read by a sub-agent | section508.gov/develop/fonts-typography | 2026-03] As evidence about WCAG itself, it is a secondary statement. [PARTIAL]
- The WCAG 3 draft also sets no fixed minimum. It requires that text can be enlarged to at least 200% of the platform's default body-text size. [VERIFIED as read by a sub-agent | w3.org/TR/wcag-3.0 | 2026-09-10]

**Lighthouse no longer checks font size.**
- Lighthouse 12.0.0 moved the font-size and viewport audits from the SEO category to Best Practices. [VERIFIED as read by a sub-agent | github.com/GoogleChrome/lighthouse/releases/tag/v12.0.0 | 2024-04-22]
- Lighthouse 13.0.0 removed the font-size audit entirely. [VERIFIED as read by a sub-agent | github.com/GoogleChrome/lighthouse/releases/tag/v13.0.0 | 10 October; the page shows no year]
- So no mainstream tool checks text size. [ASSUMPTION]

**Published numbers for text size.**
- **Material Design 3.** It has 15 type styles. Its body styles are 16 on 24, 14 on 20 and 12 on 16 (size on line height, in sp, Android's density-independent unit for text), and its smallest label style is 11 on 16. [VERIFIED as read by a sub-agent | developer.android.com/develop/ui/compose/designsystems/material3 | updated 2026-09-22]
- **GOV.UK.** The type scale is 80, 48, 36, 27, 24, 19 and 16 pixels. Body text is 19 pixels on a 25-pixel line, and 16 pixels is the smallest size. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/type-scale | accessed 2026-09-27]
- **Section508.gov.** It suggests 15 to 16 pixels for body text in electronic documents. [VERIFIED as read by a sub-agent | section508.gov/develop/fonts-typography | 2026-03]
- **Atlassian.** Body text is 14 pixels by default, with 16 and 12 pixel variants. [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27]
- **Apple.** The minimum for iOS apps is reported as 11 points, but only by a secondary blog, because Apple's page could not be read. [PARTIAL | median.co/blog/apples-ui-dos-and-donts-typography | 2024-10-01]
- **Research: Rello and colleagues, CHI 2016.**
  - Sample: 104 volunteers, recruited through announcements to schools and universities in one city district, mostly university-educated frequent readers. They read Wikipedia text in Arial at six sizes from 10 to 26 points while their eye movements were tracked. [VERIFIED as read by a sub-agent | pielot.org/pubs/Rello2016-Fontsize.pdf | 2016]
  - Result: comprehension was better at 18 and 26 points than at 10 and 12, and the authors recommend at least 18-point body text for reading on screen. 18 points is about 24 CSS pixels. [VERIFIED as read by a sub-agent | pielot.org/pubs/Rello2016-Fontsize.pdf | 2016]
  - The authors list their limits: one font, one line length, desktop screens only, and no reading-time measure. [VERIFIED as read by a sub-agent | pielot.org/pubs/Rello2016-Fontsize.pdf | 2016]

**Published numbers for line length.**
- **Bringhurst.** His print rule, as quoted by a secondary site, is that 45 to 75 characters is satisfactory for a single column and 66 is ideal. [PARTIAL | webtypography.net/2.1.2 | undated; secondary]
- **GOV.UK** recommends no more than 75 characters per line. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/layout | accessed 2026-09-27]
- **WCAG.** Criterion 1.4.8, level AAA, asks only that a way exists to make lines 80 characters or less, or 40 for Chinese, Japanese and Korean. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/visual-presentation.html | updated 2026-03-09]
- **Anthropic's frontend-design skill** keeps lines under 80 characters. [VERIFIED | raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md | accessed 2026-09-27]
- **Research: Dyson's 2004 review.**
  - Sample: a review of studies with 18 to 48 participants each. [VERIFIED as read by a sub-agent | stu.westga.edu/~ssynan1/literacy/Dyson.pdf | 2004]
  - Result: lines of about 100 characters were read fastest, but readers preferred moderate lengths, and in one study 55 characters gave better comprehension than 100. [VERIFIED as read by a sub-agent | stu.westga.edu/~ssynan1/literacy/Dyson.pdf | 2004]

**Line height: no consensus.**
- WCAG only requires that content survives a user override to 1.5 (see A6).
- Atlassian's body text uses 20 pixels on 14 and 24 pixels on 16, about 1.43 and 1.5. [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27]
- GOV.UK body text is 25 on 19, about 1.32. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/type-scale | accessed 2026-09-27]
- Rello and colleagues found no significant effect of line spacing on how long the eye rests on each word, while the extremes of 0.8 and 1.8 harmed comprehension. [VERIFIED as read by a sub-agent | pielot.org/pubs/Rello2016-Fontsize.pdf | 2016]
- A rule that fails every line height below 1.5 is therefore not supported. [ASSUMPTION]

**Type scales.**
- A modular scale is a series of sizes related by a fixed ratio. An A List Apart article argues for it on grounds of harmony, without empirical evidence. [VERIFIED as read by a sub-agent | alistapart.com/article/more-meaningful-typography | 2011-05-03]
- Atlassian's scale steps by a factor of 1.2 from a 16-pixel base, rounded to multiples of 4. [VERIFIED as read by a sub-agent | atlassian.design/foundations/typography/product-typefaces-and-scale | accessed 2026-09-27] Its default body size of 14 pixels is not a multiple of 4, so the rounding rule does not describe every size. [ASSUMPTION]
- Evidence for any maximum number of distinct font sizes is NOT FOUND.

**Numbers in tables.**
- GOV.UK tells designers to right-align numbers in table columns that are compared. [VERIFIED | design-system.service.gov.uk/components/table | accessed 2026-09-27]
- CSS offers tabular figures, `font-variant-numeric: tabular-nums`, in which every digit has the same width so that columns line up. [VERIFIED | developer.mozilla.org/en-US/docs/Web/CSS/font-variant-numeric | 2026-09-10]

**What the harness should check.** [ASSUMPTION]
- Every computed font size, weight and line height belongs to the project's type scale.
- Body text is at or above the project's declared floor.
- Long passages stay within the project's declared character limit per line, measured from the rendered text boxes.
- Numeric table columns are right-aligned and use tabular figures.
- Counter-case: the floor and the limit are project decisions, because the sources disagree. The plugin should ship no default floor, only the rule that one must be declared.

### A8. Spacing and alignment

**Spacing scales differ between systems.**
- The archived Material Design 1 guidance aligned components to an 8 dp grid, type and icons to a 4 dp grid, and asked for 48 by 48 dp touch targets with 8 dp between them. The page is marked as no longer maintained. [VERIFIED as read by a sub-agent | m1.material.io/layout/metrics-keylines.html | accessed 2026-09-27]
- GOV.UK uses 5-pixel steps: 5, 10, 15, 20, 25, 30, 40, 50 and 60 pixels on large screens. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/spacing | accessed 2026-09-27]
- Atlassian uses an 8-pixel base with 2, 4 and 6 pixel sub-steps (listed in B1). [VERIFIED | atlassian.design/foundations/spacing | accessed 2026-09-27]
- IBM Carbon uses 2, 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96 and 160 pixels. [VERIFIED as read by a sub-agent | carbondesignsystem.com/elements/spacing/overview | 2026-09-23]
- So spacing must be checked against the project's own scale, not against a fixed 8-point grid. [ASSUMPTION]

**Measuring alignment from the rendered page.** A method in three steps; no validated pass thresholds were found. [ASSUMPTION]
1. Collect every visible element's bounding box. Playwright's `boundingBox()` returns x, y, width and height relative to the viewport, and returns nothing for invisible elements. [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-locator | accessed 2026-09-27]
2. Group left, right, top and bottom edges that lie within a small tolerance of each other into alignment lines. A near-miss (two edges 1 to 3 pixels apart) is a likely defect.
3. Measure the gaps between neighbouring boxes and flag gaps that are not on the spacing scale.

**Existing layout tools.**
- **Galen Framework** checks layout with a specification language of relative positions, such as `below`, `inside` and `aligned`, driven through Selenium, an older browser-automation tool. Its last release, 2.4.4, is dated 15 March on GitHub, with no year shown. [VERIFIED as read by a sub-agent | github.com/galenframework/galen | accessed 2026-09-27] Wikipedia gives the year as 2019. [PARTIAL | en.wikipedia.org/wiki/Galen_Framework | accessed 2026-09-27]
- **Galen's approximation tolerance.** Its documentation gives a default of 3 pixels for "approximately", but its source code sets 2. [VERIFIED as read by a sub-agent | galenframework.com/docs/getting-started-configuration and raw.githubusercontent.com/galenframework/galen/master/galen-core/src/main/java/com/galenframework/config/GalenProperty.java | accessed 2026-09-27]
- **Quixote** tests CSS through `getComputedStyle()` and element positions, relative to other elements and the viewport. The repository shows no dated release. [VERIFIED as read by a sub-agent | github.com/jamesshore/quixote | accessed 2026-09-27]

**Computed aesthetic metrics (research).** These predict first-impression ratings, or search performance, only partly. [ASSUMPTION] Sample sizes come first below.
- **Aalto Interface Metrics (AIM)** offers 17 metrics from a URL or a screenshot, including seven colour-perception metrics, edge density, contour congestion, symmetry, grid quality, white space and a colour-blindness check. The paper reports no new validation of its own. [VERIFIED as read by a sub-agent | interfacemetrics.aalto.fi/static/publications/oulasvirta_et_al_2018.pdf | 2018]
- **Ngo, Teo and Byrne (2003).**
  - Sample: 79 undergraduates rated 5 abstract layouts, and 180 others rated 5 real screens, all IT students at one university. [VERIFIED as read by a sub-agent | academia.edu/11749849/Modelling_interface_aesthetics | 2003]
  - Result: their 14 layout measures broadly matched the median ratings, but no correlation coefficient is reported. [VERIFIED as read by a sub-agent | academia.edu/11749849/Modelling_interface_aesthetics | 2003]
- **Miniukovich and De Angeli (CHI 2015).**
  - Sample: 62 participants from one university rated 300 screenshots of 75 websites for beauty. The websites were chosen at random from crowd-worker submissions, after excluding the 500 most popular sites. A further 53 participants rated 300 screenshots of 75 iPhone apps. [VERIFIED as read by a sub-agent | researchgate.net/profile/Aliaksei-Miniukovich/publication/300726008_Computation_of_Interface_Aesthetics/links/57d7e0b108ae5f03b49812c7/Computation-of-Interface-Aesthetics.pdf | 2015]
  - Result: the metrics explained 49% or 43% of the variance in website ratings, depending on the viewing time, but only 13% to 18% for iPhone apps. Clutter and colour range were the strongest predictors. [VERIFIED as read by a sub-agent | researchgate.net/profile/Aliaksei-Miniukovich/publication/300726008_Computation_of_Interface_Aesthetics/links/57d7e0b108ae5f03b49812c7/Computation-of-Interface-Aesthetics.pdf | 2015]
- **Reinecke and colleagues (CHI 2013).**
  - Sample: 450 websites, each shown for half a second to online volunteers; 184 rated colourfulness, 122 rated complexity and 242 rated appeal. [VERIFIED as read by a sub-agent | kgajos.seas.harvard.edu/papers/reinecke13aesthetics.pdf | 2013]
  - Result: image metrics predicted perceived colourfulness with R² = 0.78 and complexity with R² = 0.65, where R² is the share of the variation explained, from 0 to 1. Together with age, education and gender they explained 48% of appeal. [VERIFIED as read by a sub-agent | kgajos.seas.harvard.edu/papers/reinecke13aesthetics.pdf | 2013]
- **Rosenholtz and colleagues' clutter measure (2007).**
  - Sample: 6 observers searched for targets on 19 maps, and 4 experienced observers gave contrast thresholds on 20 maps. [VERIFIED as read by a sub-agent | pdfs.semanticscholar.org/c831/8039383ab2963c3b7778db5f71fcb4a00f32.pdf | 2007]
  - Result: feature congestion correlated 0.74 to 0.76 with search performance. [VERIFIED as read by a sub-agent | pdfs.semanticscholar.org/c831/8039383ab2963c3b7778db5f71fcb4a00f32.pdf | 2007]
- **Conclusion.** These metrics explain at most about half the variance for web pages, on small or single-institution samples, so they can inform a judgement but not replace one. [ASSUMPTION]

### A9. Overflow, clipping, truncation and overlap

**The basic test.** MDN says an element's `scrollWidth` equals its `clientWidth` when its content fits without a horizontal scrollbar. It treats `scrollWidth` greater than `clientWidth` as overflow. [VERIFIED as read by a sub-agent | developer.mozilla.org/en-US/docs/Web/API/Element/scrollWidth | 2025-04-19] The same comparison works vertically with `scrollHeight` and `clientHeight`. [ASSUMPTION]

**Research tools.**
- **ReDeCheck** detects five responsive layout failures: overlapping elements, elements spilling out of their container, elements pushed outside the viewport, layouts that appear only in a narrow range of widths, and elements wrapping onto a new line. [VERIFIED as read by a sub-agent | github.com/redecheck/redecheck | accessed 2026-09-27]
- **ReDeCheck's 2017 study.**
  - Sample: 25 pages taken from a random-website directory and checked by hand to be responsive, plus one motivating example, rendered at widths from 320 to 1400 pixels in steps of 60. [VERIFIED as read by a sub-agent | gregorykapfhammer.com/download/research/papers/key/Walsh2017-paper.pdf | 2017]
  - Result: 197 true failures, 48 false alarms and 83 issues with no visible effect, reducing to 33 distinct failures on 16 pages. [VERIFIED as read by a sub-agent | gregorykapfhammer.com/download/research/papers/key/Walsh2017-paper.pdf | 2017]
  - Per failure type, written as true failures / false alarms / invisible issues: overlapping elements 8 / 0 / 24; spilling out of a container 3 / 0 / 36; pushed outside the viewport 24 / 0 / 23; narrow-range layouts 152 / 43 / 0; wrapping 10 / 5 / 0. [VERIFIED as read by a sub-agent | gregorykapfhammer.com/download/research/papers/key/Walsh2017-paper.pdf | 2017]
  - By my arithmetic, 197 of 245 reports were true failures, a precision of 80.4%. [ASSUMPTION]
- **Viser, a follow-up tool.** Sample: 20 pages with 117 reported failures. It classified all of them automatically by hiding elements and checking for a visible difference, and disagreed with an earlier manual classification on 28. [VERIFIED as read by a sub-agent | gregorykapfhammer.com/research/papers/althomali2019/index.html | 2019]
- **Consequence.** A large share of what the element tree calls overlap has no visible effect. So the harness should confirm each geometric finding with a cropped screenshot before blocking. [ASSUMPTION]

**Longer text from translation.**
- The W3C internationalisation article reproduces an IBM table of expected text growth when translating from English. Strings of up to 10 characters can grow by 200–300%, strings of 11–20 characters by 180–200%, and strings over 70 characters by 130%. [VERIFIED as read by a sub-agent | w3.org/International/articles/article-text-size | accessed 2026-09-27]
- Microsoft's guidance on pseudo-localisation, which means replacing strings with longer accented versions to expose layout faults, says to lengthen English text by about 40%. It notes that real translations can be 200–400% longer in extreme cases. [VERIFIED as read by a sub-agent | learn.microsoft.com/en-us/globalization/methodology/pseudolocalization | 2022-08-12]

**Models are poor at this.** In UI-Lens, on 4,759 expert-annotated pages, ten models found text overflow with an F1 score averaging 20.36% (see `01-benchmark.md`, C7). [VERIFIED | cvpr.thecvf.com/virtual/2026/poster/38861 | abstract; accessed 2026-09-27]

**What the harness should add.** [ASSUMPTION]
- At every render size, for every visible element, compare scroll size with visible size. Accept a difference only where the element deliberately truncates with an ellipsis and the full text is available on hover, on focus or in an expanded view.
- Test text boxes for overlap with other text and controls.
- Test whether any element extends beyond its container or the viewport.
- Repeat with strings lengthened by 40%.
- Counter-case: pseudo-localised strings are ugly, so screenshots taken in this mode should not be shown to the model judge for taste; they are for geometry only.

### A10. How much do accessibility tools find? The evidence

- **UK Government Digital Service, 2017.**
  - Sample: one deliberately inaccessible page with 143 failures in 19 categories, tested with 10 tools. [VERIFIED as read by a sub-agent | accessibility.blog.gov.uk/2017/02/24/what-we-found-when-we-tested-tools-on-the-worlds-least-accessible-webpage | 2017-02-24]
  - Result: all 10 tools together found 71% of the failures, and 29% were found by no tool. The tool called Tenon found the most, 37%, and the tool called Asqatasun found 41% when its prompts for manual inspection were counted. [VERIFIED as read by a sub-agent | accessibility.blog.gov.uk/2017/02/24/what-we-found-when-we-tested-tools-on-the-worlds-least-accessible-webpage | 2017-02-24]
- **The same project's updated results page, 2018.**
  - Sample: 142 failures, 13 tools. [VERIFIED as read by a sub-agent | alphagov.github.io/accessibility-tool-audit/index.html | 2018-04-13]
  - Result: the best tool found 40%, axe found 29% and WAVE 30%. [VERIFIED as read by a sub-agent | alphagov.github.io/accessibility-tool-audit/index.html | 2018-04-13]
- **Vigo and colleagues, 2013.**
  - Sample: 6 tools benchmarked against WCAG 2.0; the abstract, which is all that was read, does not state the number of pages. [VERIFIED as read by a sub-agent | ro.ecu.edu.au/ecuworks2013/236 | 2013; abstract]
  - Result: at most 50% of success criteria were covered, and completeness ranged from 14% to 38%. [VERIFIED as read by a sub-agent | ro.ecu.edu.au/ecuworks2013/236 | 2013]
- **A 2024 doctoral symposium paper from Tampere University.**
  - Sample: 3 browser extensions on 6 e-commerce pages plus a test suite of 140 issues. [VERIFIED as read by a sub-agent | ceur-ws.org/Vol-3776/paper05.pdf | 2024]
  - Result: together the tools covered 37 of 78 WCAG success criteria, which is 47%. [VERIFIED as read by a sub-agent | ceur-ws.org/Vol-3776/paper05.pdf | 2024]
- **Deque, the maker of axe-core.**
  - Sample: over 2,000 first-time audits of customers' pages, covering over 13,000 pages and 294,958 issues, scoped to WCAG 2.0 and 2.1 levels A and AA. [VERIFIED as read by a sub-agent | deque.com/automated-accessibility-coverage-report | modified 2026-07-10]
  - Result: axe-core rules found 57.38% of the issues. This is measured by issue count, not by the share of criteria covered, and contrast alone was 30.08% of all issues. [VERIFIED as read by a sub-agent | deque.com/automated-accessibility-coverage-report | modified 2026-07-10]
  - This is a vendor measuring its own tool on its own customers' pages. [ASSUMPTION]
- **Conclusion.** Tools find most of the common, countable failures but less than half of the success criteria, and almost nothing of the visual layer (non-text contrast, focus). Scripts written by the harness itself must fill that gap. [ASSUMPTION]

**The tools compared.**

| Tool | What it is | What it covers | What it says it misses |
|---|---|---|---|
| axe-core | It is Deque's open-source rule engine. | WCAG rules including contrast, target size (off by default) and viewport zoom. It aims for zero false positives and returns "needs review" when unsure. | Non-text contrast, focus visibility, reflow and hover content have no rule. [VERIFIED as read by a sub-agent \| github.com/dequelabs/axe-core \| accessed 2026-09-27] |
| Lighthouse | It is Google's page audit tool. | A weighted average of pass-or-fail axe audits, with weights from axe's impact ratings. [VERIFIED as read by a sub-agent \| developer.chrome.com/docs/lighthouse/accessibility/scoring \| 2025-10-22] | It lists ten manual audits, such as logical tab order and focus traps, that do not affect the score. [VERIFIED as read by a sub-agent \| github.com/GoogleChrome/lighthouse/blob/main/core/config/default-config.js \| accessed 2026-09-27] |
| Playwright with `@axe-core/playwright` | It runs axe inside Playwright tests. | It covers whatever axe covers, for the tags chosen. | Playwright's guide says many problems can only be found through manual testing. [VERIFIED as read by a sub-agent \| playwright.dev/docs/accessibility-testing \| accessed 2026-09-27] |
| IBM Equal Access Checker | It is IBM's rule engine and browser extension, with WCAG 2.2 rule sets. [VERIFIED as read by a sub-agent \| github.com/IBMa/equal-access \| accessed 2026-09-27] | It reports violations and items that need review. | IBM says automated checks cover only a subset and must be followed by manual and screen-reader tests. [VERIFIED as read by a sub-agent \| ibm.com/able/toolkit/verify/automated \| 2026-08-20] |
| Accessibility Insights (Microsoft) | Its FastPass runs axe checks plus an assisted tab-stop test in under five minutes. | Its full assessment has 24 tests for WCAG 2.2 level AA. [VERIFIED as read by a sub-agent \| accessibilityinsights.io/docs/web/getstarted/assessment \| accessed 2026-09-27] | It says most accessibility problems can only be found by manual testing. [VERIFIED as read by a sub-agent \| accessibilityinsights.io/docs/web/getstarted/fastpass \| accessed 2026-09-27] |
| Pa11y | It is a command-line program that runs an accessibility engine on a page. | Its default engine is HTML_CodeSniffer, and axe can be added. [VERIFIED as read by a sub-agent \| github.com/pa11y/pa11y \| accessed 2026-09-27] | HTML_CodeSniffer's own README does not mention WCAG 2.2 [VERIFIED as read by a sub-agent \| github.com/squizlabs/HTML_CodeSniffer \| accessed 2026-09-27], so the default engine may lag behind it. [ASSUMPTION] |
| WAVE (WebAIM) | It is WebAIM's browser extension and checking engine. | It checks against WCAG 2.2 and Section 508, the US federal accessibility requirement. | It never reports a pass, and says only a human can judge accessibility. [VERIFIED as read by a sub-agent \| wave.webaim.org/help \| accessed 2026-09-27] |
| Siteimprove Alfa | It is an open-source engine built on the W3C test-rule format. [VERIFIED as read by a sub-agent \| github.com/Siteimprove/alfa \| accessed 2026-09-27] | It reports passed, failed, not applicable or "can't tell", and lets a person answer its questions. | Its fully automatic mode is only partly consistent with the visible-focus test rule. [VERIFIED as read by a sub-agent \| w3.org/WAI/standards-guidelines/act/rules/oj04fd \| 2023-08-30] |

---

## Part B — Conformance to a platform design system (research question 2)

### B1. What the Atlassian Design System provides as a benchmark

**Tokens and names.**
- A token name has three parts: a foundation (such as color or space), a property (such as background) and modifiers (role, emphasis, state), for example `color.background.danger.bold.hovered`. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27]
- In code, `token('space.200')` resolves to the CSS variable `var(--ds-space-200)`. [VERIFIED as read by a sub-agent | atlassian.design/foundations/tokens/use-tokens-in-code | accessed 2026-09-27]
- The current `@atlaskit/tokens` package, version 20.0.0, was published about 24 September 2026. [VERIFIED as read by a sub-agent | app.unpkg.com/@atlaskit/tokens@20.0.0 | accessed 2026-09-27]

**Spacing.** The system is built on an 8-pixel base unit, and these are all of its spacing values. [VERIFIED | atlassian.design/foundations/spacing | accessed 2026-09-27]
- 0, 2, 4, 6 and 8 pixels (`space.0` to `space.100`), for small gaps such as between an icon and its text.
- 12, 16, 20 and 24 pixels (`space.150` to `space.300`), for component padding and gaps between sections.
- 32, 40, 48, 64 and 80 pixels (`space.400` to `space.1000`), for page layout.
- Negative values from −2 to −32 pixels, for breaking out of a container's padding.
- There is no `space.700` or `space.900`.

**Typography.** Sizes and line heights, from the typography page. [VERIFIED | atlassian.design/foundations/typography | accessed 2026-09-27]
- Headings from the largest to the smallest are 32 on 36, 28 on 32, 24 on 28, 20 on 24, 16 on 20, 14 on 20 and 12 on 16 pixels.
- Body text is 16 on 24, 14 on 20 (the default) and 12 on 16 pixels.
- Metric text, used for emphasised numbers, is 28 on 32, 24 on 28 and 16 on 20 pixels.
- The code style is 12 on 20 pixels on this page.
- Only one main heading should appear per page, and heading levels should not be skipped.

**Weights, fonts and the code-style conflict.**
- The compiled token files give heading and metric text a weight of 653 and body text 400, and list the weights 400, 500, 600 and 653. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-typography.js | accessed 2026-09-27]
- An override theme called "typography-finesse" sets the four smaller heading sizes to weight 500. So a rendered heading can legitimately have either weight. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-typography-finesse.js | accessed 2026-09-27]
- The token files give the code style as 0.875em on a line height of 1, which disagrees with the page's 12 on 20. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-typography.js | accessed 2026-09-27] A harness should treat the compiled token value as authoritative. [ASSUMPTION]
- The font families are "Atlassian Sans" for text and "Atlassian Mono" for code, each followed by system fonts as fallbacks. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-typography.js | accessed 2026-09-27]
- Atlassian Sans is derived from Inter, and Atlassian Mono from JetBrains Mono. [VERIFIED as read by a sub-agent | atlassian.design/foundations/typography/product-typefaces-and-scale | accessed 2026-09-27]
- The new typography became generally available on 9 September 2025. The older systems were deprecated but supported until January 2026. [VERIFIED as read by a sub-agent | atlassian.design/whats-new/new-typography-in-general-availability | 2025-09-09]

**Colour.**
- **Roles.** The colour roles are neutral, brand, information, success, warning, danger, discovery, accent, inverse (for use on bold backgrounds) and input. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27]
- **Themes.** The design-tokens overview names light, dark and high-contrast colour themes. [VERIFIED as read by a sub-agent | atlassian.design/foundations/tokens/design-tokens | accessed 2026-09-27]
- **Example values, light theme then dark theme.** [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-light.js and cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-dark.js | accessed 2026-09-27]
  - Default text `color.text` is #292A2E and #CECFD2.
  - The page surface `elevation.surface` is #FFFFFF and #1F1F21.
  - The focus border `color.border.focused` is #4688EC and #8FB8F6.
- **Contrast.** Atlassian requires 4.5:1 for text smaller than 24 pixels, and 3:1 for larger text and for interface parts needed to understand the content. [VERIFIED as read by a sub-agent | atlassian.design/foundations/color | accessed 2026-09-27] This is stricter than WCAG for bold text between about 18.5 and 24 pixels. [ASSUMPTION]

**Elevation, radius, borders and grid.**
- **Elevation.** Raised and overlay surfaces must be paired with their own shadow tokens, and elevation levels must not be mixed. [VERIFIED as read by a sub-agent | atlassian.design/foundations/elevation | accessed 2026-09-27]
- **Radius, marked Beta.** The values are 2 pixels (badges, checkboxes), 4 (labels, tags), 6 (buttons, inputs), 8 (cards, menus), 12 (modals, tables) and 16 (video containers). [VERIFIED as read by a sub-agent | atlassian.design/foundations/radius | accessed 2026-09-27]
- **Borders.** The widths are 1 pixel, and 2 pixels for selected and focused states. The 2-pixel focus width must be paired with the focus colour. [VERIFIED as read by a sub-agent | atlassian.design/foundations/border | accessed 2026-09-27]
- **Grid.** It has 2 columns from 320 to 479 pixels, 6 columns from 480 to 1023, and 12 columns from 1024 upwards. Gutters are 12 or 16 pixels, and content must not overflow into gutters or margins. [VERIFIED as read by a sub-agent | atlassian.design/foundations/grid | accessed 2026-09-27]

**Chart colours and rules.** [VERIFIED | atlassian.design/foundations/color/data-visualization-color | accessed 2026-09-27]
- Categorical chart colours must be used in their numbered order, from 1 to 8, so that neighbouring colours stay distinct for people with colour-vision deficiencies.
- A chart should show no more than 5 to 6 colours, with further categories grouped together.
- Sequential and diverging chart palettes are not currently supported.
- Chart colours meet 3:1 contrast against Atlassian's surfaces but not against each other, so adjacent chart colours need a border or a gap.
- Text must not sit on chart colours, because those pairs cannot reach 4.5:1.
- Colour must be backed by shapes, line textures, patterns or direct labels.
- The assigned tokens are:
  - `color.text` for the title and legend;
  - `color.text.subtle` for tick labels;
  - `color.border` for gridlines;
  - `color.chart.brand` for data marks in a one-colour chart;
  - `color.chart.neutral` for reference and threshold lines.

**Content rules.**
- **Language and grammar.** [VERIFIED as read by a sub-agent | atlassian.design/foundations/content/language-and-grammar | accessed 2026-09-27]
  - Sentence case is required for all titles, headings, menu items, labels and buttons.
  - Headers, titles, tooltips and field descriptions have no full stops.
  - A page may have at most one exclamation mark.
  - The symbol "&" and the abbreviations "e.g.", "i.e." and "etc." are not used.
  - Spelling is US English.
- **Buttons.** Labels start with a verb and name what is acted on, and an area should have only one primary button. [VERIFIED as read by a sub-agent | atlassian.design/components/button/usage | accessed 2026-09-27]
- **Forms.** Labels sit left-aligned above the field. Required fields get an asterisk. Errors appear below the field. Field widths come from a fixed set of 75, 150, 250, 350 and 500 pixels. [VERIFIED as read by a sub-agent | atlassian.design/patterns/forms | accessed 2026-09-27]

**Inconsistencies inside Atlassian's own sources that a harness must settle.** [VERIFIED as read by a sub-agent | atlassian.design/foundations/radius, atlassian.design/patterns/forms, atlassian.design/foundations/color, cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md and the cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0 package files | accessed 2026-09-27]
- The code style is 12 on 20 pixels on the page but 0.875em on 1 in the tokens.
- The full radius is 999 pixels on the page but 9999 in the tokens.
- The forms pattern styles placeholder text, while the recommended lint rule `no-placeholder` says placeholders should not be used.
- The large-text threshold is 24 pixels in Atlassian's rules but 18.5 pixels bold in WCAG.

### B2. Forge limits that shape the design

**UI Kit charts.**
- UI Kit, the option where Atlassian's own components draw the screen, has seven chart components: bar, stacked bar, horizontal bar, horizontal stacked bar, line, pie and donut. There is no scatter plot and no control chart. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components | accessed 2026-09-27]
- The line chart takes data, x and y accessors, an optional colour palette, a height (400 pixels by default), a width, a title and a subtitle. Its page documents no reference lines, annotations, tooltips or dual axes. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components/line-chart | 2026-08-20]
- The bar chart page's colour-palette examples are hard-coded hexadecimal colours rather than tokens. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components/bar-chart | 2026-08-20]
- A faithful cycle-time control chart therefore probably needs Custom UI with a third-party chart library coloured from the chart token variables. [ASSUMPTION]

**Styling and theming.**
- UI Kit's `xcss` styling allows only design-token values for colour, spacing, radius and shadow. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/ui-kit/components/xcss | 2025-11-24] UI Kit apps are therefore largely token-conformant by construction. [ASSUMPTION]
- Custom UI, the option where the app's own HTML and JavaScript run in a frame, must opt in to theming by calling `view.theme.enable()`. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/design-tokens-and-theming | 2024-10-30]
  - The call sets the colour mode and a `data-theme` attribute on the page.
  - The Forge page's example attribute contains no typography theme entry, and Atlassian's typography theme applies only when that entry is present. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/design-tokens-and-theming and cdn.jsdelivr.net/npm/@atlaskit/tokens@20.0.0/dist/esm/artifacts/themes/atlassian-typography.js | accessed 2026-09-27; the conclusion combines the two pages]
  - A community member reported that the Atlassian fonts loaded only after adding the typography theme by hand. [PARTIAL | community.developer.atlassian.com/t/new-atlassian-fonts-in-forge-apps-with-custom-ui/93747 | 2025-07-10; community report]
  - A harness should therefore check the computed font family of rendered text, because a Custom UI gadget may silently fall back to system fonts. [ASSUMPTION]

**Gadget and widget modules.**
- Atlassian's changelog declared `dashboards:widget` generally available on 22 September 2026, and deprecated `jira:dashboardGadget`, with removal on 17 May 2027. [VERIFIED as read by a sub-agent | developer.atlassian.com/changelog | entries of 2026-09-22 and 2026-09-23]
- The old gadget module saves configuration with `view.submit()`, and its page gives no size guidance. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/manifest-reference/modules/jira-dashboard-gadget | 2025-08-12]
- The new widget module's context gives the widget's width and height in pixels. [VERIFIED | developer.atlassian.com/platform/forge/ui-kit/hooks/use-widget-context | 2026-09-14]
  - The row span is one of xsmall, small, medium or large.
  - The column span is one of 3, 4, 6, 8 or 12 on a 12-column grid.
  - The context is undefined while it loads, so the app needs a loading state.
  - The page is labelled Early Access.
- Pixel heights for each row span: NOT FOUND.

**Configuration screens.**
- Atlassian's guidance for Forge automation-action configuration panels says to use only Atlassian components, to avoid tabs and accordions, and to use radio buttons for 2 to 3 options and dropdowns for 5 or more. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/action-components-guidelines | 2025-11-01] This guidance is written for automation actions and applies to gadget configuration only by analogy. [ASSUMPTION]
- A formal design-requirements page for Marketplace apps: NOT FOUND. Atlassian's page for Marketplace partners points to its foundations, components and content guidelines without stating requirements. [VERIFIED as read by a sub-agent | atlassian.design/get-started/design/marketplace-partners | accessed 2026-09-27]

### B3. How conformance to a design system is checked automatically

There are three places to check: the source code, the design file, and the rendered page.

**Source code: Atlassian's lint rules.**
- The ESLint plugin `@atlaskit/eslint-plugin-design-system`, version 16.13.2, includes these rules. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md and the plugin's recommended preset file | accessed 2026-09-27]
  - `ensure-design-token-usage` flags hard-coded colours and spacing where a token should be used, and radius too when its shape option is switched on. It can fix them automatically.
  - `no-unsafe-design-token-usage` flags token names that do not exist, removed or experimental tokens, and token names that are not written as plain strings.
  - `no-deprecated-design-token-usage` flags deprecated tokens.
  - `use-tokens-typography` flags raw font weights, families, line heights and letter spacing, and text written in all capitals.
  - `use-tokens-space` enforces space tokens, but is not in the recommended set.
  - `use-heading` pushes native headings towards Atlassian's Heading component.
  - A group of `no-html-*` rules discourages native buttons, inputs and similar elements in favour of Atlassian components.
- The plugin failed under ESLint 9 in 2024, when Atlassian staff said support was not on the roadmap. [PARTIAL | community.developer.atlassian.com/t/atlassian-eslint-plugins-fail-with-eslint-9-x/82141 | 2024-07-27] The package now ships a preset, a ready-made set of rules, in ESLint 9's configuration format, but its README still shows only the older setup. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/dist/cjs/presets/recommended-flat.codegen.js and cdn.jsdelivr.net/npm/@atlaskit/eslint-plugin-design-system/README.md | accessed 2026-09-27] Whether it now works was not tested.
- The Stylelint plugin `@atlaskit/stylelint-design-system`, version 5.1.4, has three rules for plain CSS: ensure token usage, no deprecated tokens, and no unsafe tokens. [VERIFIED as read by a sub-agent | cdn.jsdelivr.net/npm/@atlaskit/stylelint-design-system/README.md | accessed 2026-09-27]
- Forge's theming page recommends the ESLint plugin for styles written in JavaScript and the Stylelint plugin for CSS files. [VERIFIED as read by a sub-agent | developer.atlassian.com/platform/forge/design-tokens-and-theming | 2024-10-30]
- Each raw token record lists the raw values it replaces; for example, the 2-pixel radius token lists "2px". [VERIFIED as read by a sub-agent | unpkg.com/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-shape.js | accessed 2026-09-27] This gives a harness a ready-made map from a wrong raw value back to the token it should have been. [ASSUMPTION]

**Source code: general tools.**
- **The token file format standard.** The W3C Design Tokens Community Group published its first stable format, "2025.10", on 28 October 2025. It is a community group report, not a W3C Standard, and its files use the `.tokens` or `.tokens.json` extension. [VERIFIED as read by a sub-agent | designtokens.org/tr/2025.10/format and w3.org/community/design-tokens/2025/10/28/design-tokens-specification-reaches-first-stable-version | 2025-10-28]
- **Atlassian's raw files do not follow it.** They use the key `value` rather than the standard's `$value`, and an official export in the standard format was NOT FOUND. [VERIFIED as read by a sub-agent | unpkg.com/@atlaskit/tokens@20.0.0/dist/esm/artifacts/tokens-raw/atlassian-shape.js | accessed 2026-09-27]
- **Style Dictionary**, a tool that converts one token file into CSS and platform formats, has supported the community format since version 4. It calls full support for 2025.10 work in progress. [VERIFIED as read by a sub-agent | styledictionary.com/info/dtcg | accessed 2026-09-27]
- **`stylelint-declaration-strict-value`** forces chosen CSS properties to use variables or functions rather than raw values. [VERIFIED as read by a sub-agent | github.com/AndyOGo/stylelint-declaration-strict-value | accessed 2026-09-27] It checks that a variable is used, not that the correct variable is used. [ASSUMPTION]
- **Carbon.** IBM publishes a comparable Stylelint plugin for Carbon's tokens. [VERIFIED as read by a sub-agent | github.com/carbon-design-system/stylelint-plugin-carbon-tokens | accessed 2026-09-27]
- **Project Wallace's `css-analyzer`** reports over 200 metrics from a CSS file, including counts of unique colours, font sizes and line heights. [VERIFIED as read by a sub-agent | github.com/projectwallace/css-analyzer | accessed 2026-09-27]
- **`react-scanner`** counts which components are used and with which properties, by reading React source code. [VERIFIED as read by a sub-agent | github.com/moroshko/react-scanner | accessed 2026-09-27]

**Design files.**
- The Figma plugin Design Lint flags layers without styles, and corner radii outside a configurable list. [VERIFIED as read by a sub-agent | github.com/destefanis/design-lint | accessed 2026-09-27]
- Figma's built-in "Check designs" flags hard-coded values that could be variables, on Organization and Enterprise plans only. [VERIFIED as read by a sub-agent | help.figma.com/hc/en-us/articles/39592284074263-Check-designs-in-Figma | accessed 2026-09-27]

**The rendered page.**
- `getComputedStyle` returns the resolved values after all style rules apply. [VERIFIED as read by a sub-agent | developer.mozilla.org/en-US/docs/Web/API/Window/getComputedStyle | 2026-05-11] A rendered-page check therefore sees "14px" or "rgb(41, 42, 46)" and cannot tell whether a token or an identical hard-coded value produced it. [ASSUMPTION]
- Playwright's `toHaveCSS` asserts one computed property of one element. [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-locatorassertions | accessed 2026-09-27]
- Chrome's CSS Overview panel lists all colours, fonts and sizes used on a page, but it is a manual panel, not an automated check. [VERIFIED as read by a sub-agent | developer.chrome.com/docs/devtools/css-overview | accessed 2026-09-27]
- A mature off-the-shelf tool that compares a page's computed styles with a token set: NOT FOUND.

**What each place misses.** [ASSUMPTION]

| Where the check runs | What it catches | What it misses |
|---|---|---|
| Source code (lint) | Hard-coded values, unknown or deprecated tokens, native elements used instead of components. | Values set at run time, third-party components, chart colours passed as data, and the final layout. |
| Stylesheet statistics | How many distinct colours and sizes the CSS declares. | Inline styles, styles set by JavaScript, and anything drawn on a canvas. |
| Design file (Figma) | Unstyled layers and off-scale values in the design. | Whether the code matches the design. |
| Rendered page (computed styles) | What the user actually gets, in every theme and state. | Whether a correct-looking value came from a token; anything drawn on a canvas. |

The harness needs both the lint rules and the rendered check. The lint catches the cause, and the rendered check catches the effect. [ASSUMPTION]

### B4. A rendered-page allow-list built from the Atlassian values

[ASSUMPTION for the method; the values are from B1]

1. Render each screen in the light theme and the dark theme.
2. For every visible element, read these computed properties: margin, padding, gap, font size, line height, font weight, font family, colour, background colour, border colour, border width and corner radius.
3. Compare each value with the allowed set:
   - spacing: 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64 and 80 pixels, and their negatives;
   - font sizes: 12, 14, 16, 20, 24, 28 and 32 pixels;
   - line heights: 16, 20, 24, 28, 32 and 36 pixels;
   - weights: 400, 500, 600 and 653;
   - radii: 2, 4, 6, 8, 12 and 16 pixels, plus the full and 25% values;
   - border widths: 1 and 2 pixels;
   - colours: the resolved values of every colour token in the active theme.
4. Report each violation with the element's selector, the property, the value found, and the nearest allowed value.
5. Check text inside code elements separately, against 0.875 times its parent's font size, because Atlassian's code token is relative.

- Allow half a pixel of rounding, because browsers can produce fractional computed values. [ASSUMPTION]
- Counter-case: third-party components inside the page, such as a chart library's tooltip, may legitimately use other values. The project needs an exceptions list with a reason for each entry, or the check becomes noise.

### B5. Numbers from other systems, for comparison only

- Android asks for touch targets of at least 48 by 48 dp, separated by 8 dp or more. [VERIFIED as read by a sub-agent | support.google.com/accessibility/android/answer/7101858 | accessed 2026-09-27]
- IBM Carbon's productive body text is 14 pixels on 20, and its headings are 14 on 20 at weight 600, 16 on 24 at weight 600, and 20 on 28 at weight 400. [VERIFIED as read by a sub-agent | carbondesignsystem.com/elements/typography/type-sets | 2026-09-23]
- GOV.UK's spacing on small screens is 0, 5, 10, 15, 15, 15, 20, 25, 30 and 40 pixels, switching to the large-screen scale at 640 pixels. [VERIFIED as read by a sub-agent | design-system.service.gov.uk/styles/spacing | accessed 2026-09-27]

---

## Part C — Conformance to an approved design (research question 5)

### C1. Three ways to compare a rendered page with an approved design

| Method | What it compares | What it catches | What it misses | Stability across machines |
|---|---|---|---|---|
| Structured comparison | Element positions, sizes, computed styles and text, read from the DOM. | Moved, resized, recoloured or missing elements, and changed text, with the element named. | Anything drawn as pixels, such as images and canvas charts, and elements that are present in the DOM but hidden. | High, because fonts and anti-aliasing affect it only through text size. |
| Pixel comparison | Screenshots, pixel by pixel, within a tolerance. | Any visible change, including ones nobody thought to specify. | Why something changed. It also raises false alarms from fonts, anti-aliasing and the hardware. | Low, unless the rendering environment is fixed. |
| AI judge | Screenshots, and sometimes code, interpreted by a model. | Changes in meaning, such as a chart that now tells a different story. | Small offsets and colour shifts; see `01-benchmark.md`, C7. | Its verdicts vary between runs. |

[ASSUMPTION for the comparison; the evidence is in C2 to C5]

### C2. Pixel comparison tools and their default tolerances

**Playwright.** [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-pageassertions | accessed 2026-09-27]
- **What the threshold means.** The `toHaveScreenshot` threshold is the acceptable perceived colour difference between the same pixel in two images, measured in the YIQ colour space, a colour model that separates brightness from colour. It runs from 0 (strict) to 1 (lax), and the default is 0.2.
- **How many pixels may differ.** `maxDiffPixels` is an absolute count of differing pixels, and `maxDiffPixelRatio` is a share of all pixels between 0 and 1. The reference shows no default for either.
- **Other defaults.**
  - The text cursor is hidden by default.
  - Masked areas are painted #FF00FF.
  - `scale` defaults to one screenshot pixel per CSS pixel.
  - `stylePath` applies a stylesheet while the screenshot is taken, which is useful for hiding dynamic content.
- **What else the documentation says.** Animations are disabled by default, and baselines must be made in the same environment they are checked in. [VERIFIED as read by a sub-agent | playwright.dev/docs/test-snapshots | accessed 2026-09-27]

**pixelmatch, the comparison library Playwright uses.**
- In the published version 7.2.0, the default threshold is 0.1. It becomes a maximum allowed colour difference through the formula 35215 × threshold × threshold, where 35215 is the largest possible YIQ difference. [VERIFIED as read by a sub-agent | unpkg.com/pixelmatch@7.2.0/index.js | accessed 2026-09-27]
- Anti-aliased pixels are detected and ignored by default, using a 2009 method. [VERIFIED as read by a sub-agent | unpkg.com/pixelmatch@7.2.0/README.md | accessed 2026-09-27]
- If Playwright uses the same formula, its 0.2 accepts four times the colour difference that pixelmatch's own 0.1 accepts. Playwright's comparison source could not be fetched to confirm. [ASSUMPTION]
- The project's main branch has replaced the YIQ measure with the OKLab colour space and a different distance, and uses the threshold directly. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/mapbox/pixelmatch/main/index.js | accessed 2026-09-27] This change appears unreleased, but a future release would change what a given threshold number means, so the version should be pinned. [ASSUMPTION]

**Other tools.**

| Tool | Default tolerance | What the number means |
|---|---|---|
| jest-image-snapshot | A pixelmatch threshold of 0.01, and a failure threshold of 0 differing pixels. | Its README recommends a 1% failure threshold when using structural similarity (SSIM), a comparison of local patterns rather than single pixels, and a 1–2 pixel blur to absorb scaling noise. [VERIFIED as read by a sub-agent \| raw.githubusercontent.com/americanexpress/jest-image-snapshot/main/README.md \| accessed 2026-09-27] |
| BackstopJS | A mismatch threshold of 0.1 percent of pixels. | Any change in the captured element's size fails by default. The README recommends running in Docker because text renders differently between environments. [VERIFIED as read by a sub-agent \| raw.githubusercontent.com/garris/BackstopJS/master/README.md \| accessed 2026-09-27] |
| Chromatic | A diff threshold of 0.063, in YIQ. | The documentation gives 0.2 as an example and warns that 0.8 may miss changes in position. Anti-aliased pixels are ignored unless switched on. [VERIFIED as read by a sub-agent \| chromatic.com/docs/threshold \| accessed 2026-09-27] |
| Percy | Three levels, Strict, Recommended and Relaxed, with no numbers published. | Strict flags every pixel difference including font smoothing, and Relaxed flags only prominent colour shifts. [VERIFIED as read by a sub-agent \| browserstack.com/docs/percy/project-settings/diff-sensitivity \| accessed 2026-09-27] |
| Applitools Eyes | The Strict match level. | Strict is meant to flag what a human eye would see, ignoring platform rendering differences. Layout compares only relative positions, and Exact, a pixel-by-pixel match, is not recommended for ordinary use. [VERIFIED as read by a sub-agent \| applitools.com/docs/eyes/concepts/best-practices/match-levels \| accessed 2026-09-27] |
| looks-same | A CIEDE2000 tolerance of 2.3. | CIEDE2000 is the modern standard formula for the perceived difference between two colours, written ΔE. The source code calls 2.3 the just-noticeable difference. [VERIFIED as read by a sub-agent \| raw.githubusercontent.com/gemini-testing/looks-same/master/lib/constants.js \| accessed 2026-09-27] |
| Argos | A threshold of 0.5, with full-page screenshots and hover disabled. | It can auto-ignore a change that appeared at least 3 times in auto-approved builds within 7 days. [VERIFIED as read by a sub-agent \| argos-ci.com/docs/reference/playwright and argos-ci.com/docs/learn/reliability-and-flakiness/flaky-test-detection \| accessed 2026-09-27] |

### C3. Structured comparison

**Design2Code's metrics.** Design2Code is a benchmark that asks models to rebuild a web page from its screenshot.
- **The sample.** 484 pages were chosen by hand from web links in a public web-text dataset, after automatic filtering to 14,000 candidates. [VERIFIED as read by a sub-agent | arxiv.org/html/2403.03163 | 2025-02-09]
- **How the metrics work.** Text blocks and their boxes are found by recolouring text in the page's HTML and taking extra screenshots. Blocks in the reference and in the rebuild are then paired by text similarity. [VERIFIED as read by a sub-agent | arxiv.org/html/2403.03163 | 2025-02-09]
  - Block-Match measures how much of the text survived.
  - Text similarity compares characters.
  - Position similarity is 1 minus the larger of the horizontal and vertical offsets, on coordinates scaled to between 0 and 1.
  - Colour similarity uses CIEDE2000 on text colours.
  - An overall visual score uses the CLIP image model on screenshots with the text removed.
- **Validation against people.**
  - Sample: 100 examples, each judged by 5 annotators recruited on Prolific, a paid survey platform. [VERIFIED as read by a sub-agent | arxiv.org/html/2403.03163 | 2025-02-09]
  - A model combining the metrics predicted the annotators' pairwise preference with 79.9% accuracy. Position and Block-Match carried the most weight, and text similarity had a negative weight. The annotators themselves agreed only moderately, with Fleiss' kappa 0.46, a chance-corrected agreement score for three or more raters. [VERIFIED as read by a sub-agent | arxiv.org/html/2403.03163 | 2025-02-09]

**An Android example with explicit tolerances: GVT (ICSE 2018).** [VERIFIED as read by a sub-agent | arxiv.org/pdf/1802.04732 | 2018-02-13]
- **The sample.** 200 design violations were deliberately injected into 100 app screens. [VERIFIED as read by a sub-agent | arxiv.org/pdf/1802.04732 | 2018-02-13]
- **How it works.** GVT compares design mock-ups with screenshots and element trees of the built app.
- **Its tolerances.** A layout threshold of 5 pixels, a colour threshold of 85%, an image-difference threshold of 20%, and component matching within one-eighth of the screen width.
- **Results.** Detection precision was 99.4%, and classification precision 98.4% with recall 96.5%. For comparison, 10 developers with at least 5 years of Android experience reached roughly 60% precision and 50% recall on the same task.

**The DOM alone, with no reference design.** The 2017 layout study in A9 found failures from the element tree without any approved design. It also produced 83 issues with no visible effect, which shows the main weakness of pure DOM comparison. [VERIFIED as read by a sub-agent | eprints.whiterose.ac.uk/id/eprint/116989/10/c50-3.pdf | 2017]

**Accessibility-tree snapshots.** Playwright's ARIA snapshots record the roles, attributes, values and text of a page's accessible elements and compare them with a stored text template. They do not compare appearance. [VERIFIED | playwright.dev/docs/aria-snapshots | accessed 2026-09-27]

**Figma-linked tools.**
- **The Figma MCP server** returns design data: design context, variables, screenshots and metadata. None of its read tools compares an implementation with the design. [VERIFIED as read by a sub-agent | developers.figma.com/docs/figma-mcp-server/tools-and-prompts | accessed 2026-09-27]
- **Code Connect** links code components to Figma components so that designers see real code snippets. It does no automated comparison. [VERIFIED as read by a sub-agent | developers.figma.com/docs/code-connect | accessed 2026-09-27]
- **Applitools' Figma plugin** exports Figma frames to Applitools as baselines, and Applitools says it will be deprecated. [VERIFIED as read by a sub-agent | applitools.com/docs/eyes/integrations/design-validation/figma-plugin | accessed 2026-09-27]
- **Applitools "Figma Design Baselines."** On 15 September 2026 Applitools announced this feature, which uses a Figma frame directly as the baseline. The announcement gives no accuracy figures. [PARTIAL | globenewswire.com/news-release/2026/09/15/3361865/0/en/applitools-introduces-visual-ai-guardrails-to-prevent-quality-degradation-and-reduce-review-burden-in-agentic-coding.html | 2026-09-15; vendor press release]
- **Other tools.** Any other tool that automatically compares a rendered page with a Figma file: NOT FOUND.

### C4. An AI judge for conformance

- **Design2Code's self-revision.** When the model saw the reference screenshot, a screenshot of its own page and its code, one revision round gave GPT-4V only minor gains, for example a Block-Match score of 88.8 against 85.8. It did not help Gemini Pro Vision. [VERIFIED as read by a sub-agent | arxiv.org/html/2403.03163v1 | 2024-03-05]
- **Screenshots help a judge that has a checklist.** ArtifactsBench's sample was 280 randomly selected tasks with outputs from six models, rated double-blind by an unstated number of engineers. A Gemini-2.5-Pro judge's agreement with the engineers rose from 79.06% with no images, to 87.10% with one screenshot, to 90.95% with several screenshots taken over time. [VERIFIED as read by a sub-agent | arxiv.org/html/2507.04952 | 2025-09-29]
- **Chart comparisons.** In ChartJudgeBench, sample 1,003 pairwise instances and 650 accept-or-reject instances, judges comparing rendered charts showed position bias and a strong tendency to answer "accept". [VERIFIED as read by a sub-agent | arxiv.org/abs/2609.24210 | 2026-09-21; abstract]
- **Anthropic's advice on screenshot sizes.** The computer-use documentation recommends 1280 by 800 or 1366 by 768 screenshots for web applications, advises staying below 1920 by 1080, and offers a zoom action to inspect small regions at full resolution. [VERIFIED as read by a sub-agent | platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool | accessed 2026-09-27]
- **Claude Code's advice.** Claude Code's best-practices page lists a browser screenshot compared against a design as a valid check, with a sample prompt that asks Claude to list the differences and fix them. [VERIFIED as read by a sub-agent | code.claude.com/docs/en/best-practices | accessed 2026-09-27]
- **A product that warns against it.** Lovable says its browser testing is not reliable for subtle visual details or colour differences. [VERIFIED as read by a sub-agent | docs.lovable.dev/features/browser-testing | accessed 2026-09-27]
- **Small deviations.** Any study testing whether a judge catches small deviations, such as a 4-pixel offset or a slightly wrong colour: NOT FOUND.

### C5. Tolerance values

**Published recommendations, as opposed to defaults.**
- jest-image-snapshot recommends 1% for comparisons with structural similarity. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/americanexpress/jest-image-snapshot/main/README.md | accessed 2026-09-27]
- Chromatic warns against high values such as 0.8. [VERIFIED as read by a sub-agent | chromatic.com/docs/threshold | accessed 2026-09-27]
- For positions, Galen's default "approximately" is 2 or 3 pixels (see A8), and GVT used 5 pixels (see C3).

**Colour differences.**
- A just-noticeable difference (JND) is the smallest difference an average viewer can see.
- A ΔE of 2.3 under the older CIE76 formula is commonly cited as one JND. [PARTIAL | en.wikipedia.org/wiki/Color_difference | accessed 2026-09-27; secondary, citing a 2003 handbook]
- In a study of photographs of natural scenes on a calibrated monitor, the sample was 9 images; the number of observers is not stated. Telling originals from altered images needed about 2.2 ΔE on average, measured with the older CIE76 formula. [VERIFIED as read by a sub-agent | cambridge.org/core/journals/visual-neuroscience/article/visual-sensitivity-to-color-errors-in-images-of-natural-scenes/D5109E53ECB9C49C90C45B7C5CD92513 | 2006-05]
- Dentistry uses CIEDE2000 thresholds of 0.8 for perceptible and 1.8 for acceptable, but these were measured on physical ceramic samples, not screens. [PARTIAL | pmc.ncbi.nlm.nih.gov/articles/PMC11733899 | 2024-12-01; secondary citation]
- looks-same applies 2.3 to the newer CIEDE2000 formula, while the source of the 2.3 figure describes the older formula. [ASSUMPTION]

**Proposed defaults for the harness.** [ASSUMPTION]
- **Structured comparison of token colours:** exact equality. The same token should give identical computed colours, so any difference means a wrong token.
- **Structured comparison of positions and sizes:** 2 CSS pixels, which matches Galen's source default.
- **Pixel comparison:** Playwright's default threshold of 0.2, with `maxDiffPixelRatio` set per screen after measuring the noise in 5 to 10 unchanged runs.
- Counter-case: these are starting values, not evidence-based limits. A project should record the noise it measured and set its thresholds just above it.

### C6. Keeping results stable across machines and fonts

**Fonts.**
- Chromatic explains that browsers render in several passes when custom fonts load, so a snapshot can show no custom font, or different fonts on different runs. Its fixes are: [VERIFIED as read by a sub-agent | chromatic.com/docs/font-loading | accessed 2026-09-27]
  - web-safe fallbacks;
  - preloading fonts;
  - serving fonts as static files;
  - waiting for the page's font set to finish;
  - as a last resort, `font-display: optional`.
- `document.fonts.ready` resolves only when the document has finished loading fonts and layout is complete. [VERIFIED as read by a sub-agent | developer.mozilla.org/en-US/docs/Web/API/FontFaceSet/ready | 2024-10-08] A font that the page has not requested yet, for example one used only on hover, is not covered at that moment. [ASSUMPTION]
- With `font-display: optional` the fallback font is kept if the web font does not arrive almost immediately. [VERIFIED as read by a sub-agent | developer.mozilla.org/en-US/docs/Web/CSS/@font-face/font-display | 2026-09-10] This can make screenshots differ between runs unless the font is preloaded. [ASSUMPTION]

**Browser flags.**
- Playwright passes `--force-color-profile=srgb` to Chromium by default, and in headless mode it also hides scrollbars. Its default list includes no font-hinting, subpixel-positioning or GPU flags. [VERIFIED as read by a sub-agent | raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/src/server/chromium/chromiumSwitches.ts | accessed 2026-09-27]
- A third-party visual-testing plugin merged a preset of six Chromium flags to make text rendering the same on macOS and Linux: `--font-render-hinting=none`, `--disable-font-subpixel-positioning`, `--disable-lcd-text`, `--force-color-profile=srgb`, `--disable-gpu` and `--hide-scrollbars`. [PARTIAL | github.com/FRSOURCE/cypress-plugin-visual-regression-diff/pull/421 | merged 2026-09-22; third-party]
- A Playwright user reported that adding `--disable-gpu` made headless screenshots match. [PARTIAL | github.com/microsoft/playwright/issues/23559 | 2023-06-07; user report]

**Emulation, time and data.**
- **Playwright's defaults.** [VERIFIED as read by a sub-agent | playwright.dev/docs/api/class-testoptions | accessed 2026-09-27]
  - The device scale factor is 1.
  - The locale is en-US.
  - The timezone is the host's own.
  - Reduced motion is "no-preference", the colour scheme is light, and the viewport is 1280 by 720.
  - Because the timezone comes from the host, a laptop and a CI server will show different dates unless it is set explicitly. [ASSUMPTION]
- **Playwright's clock.** It can fix the date and time that the page sees. [VERIFIED as read by a sub-agent | playwright.dev/docs/clock | accessed 2026-09-27]
- **Chromatic's advice.** Hard-code or seed random data, fix the date, mock network data, and mark regions to ignore. [VERIFIED as read by a sub-agent | chromatic.com/docs/unstable-tests | accessed 2026-09-27]
- **Argos's defaults.** Before each screenshot it waits for fonts, images and busy indicators, hides carets and scrollbars, forces font anti-aliasing, and switches sticky and fixed elements to absolute positioning. [VERIFIED as read by a sub-agent | argos-ci.com/docs/reference/playwright | accessed 2026-09-27]
- **Percy.** It serialises the page, then re-renders it in its own browsers with JavaScript disabled and CSS animations frozen. [VERIFIED as read by a sub-agent | browserstack.com/docs/percy/integrate/percy-sdk-workflow | accessed 2026-09-27]

**How often UI tests are flaky, and why.**
- **Sample.** A 2021 study examined 235 flaky UI tests from 62 projects. The web tests were found in 7,037 GitHub repositories through commit messages mentioning flaky or intermittent tests, and the Android tests through keyword-filtered commits and issues. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2103.02669 | 2021-03-03]
- **Causes.** 19 tests waited for network resources, 61 for rendering and 26 for animations. 34 were platform issues and 10 were layout differences. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2103.02669 | 2021-03-03]
- By my arithmetic, 106 of the 235 tests, about 45%, were caused by waiting for asynchronous work. [ASSUMPTION]

**A recipe for the harness.** [ASSUMPTION]
1. Generate and check baselines only in CI (the automated build server), in a pinned browser image on one processor architecture.
2. Bundle the fonts with the app and preload them, then wait for the font set to be ready before every capture.
3. Set the viewport, device scale factor, locale, timezone, colour scheme and reduced motion explicitly.
4. Fix the clock and seed all test data.
5. Mask or hide regions that must vary, such as the current date.
6. Before trusting any comparison, render the same page twice and require a zero difference. This self-difference test detects flakiness before it is mistaken for a design change.
- Counter-case: a fully pinned environment tests one configuration only. Real users see other fonts, zoom levels and operating systems, which is why the structured and accessibility checks, which do not depend on pixels, stay the primary gate.

### C7. Which method to use when

[ASSUMPTION; each step has its counter-case]
1. **No approved design exists.** Use the universal and platform checks from Parts A and B, and the model judge for taste; see `05-template.md`.
   - Counter-case: without a reference, drift between iterations is invisible, so keep each approved finalist as a baseline for the next round.
2. **An approved design exists as a rendered page.** Use structured comparison as the gate: element positions and sizes within 2 pixels, token colours exact, text identical. Use pixel comparison in CI as a safety net for anything the structured check does not model.
   - Counter-case: structured comparison needs stable element identifiers. Without test identifiers in the code, elements are hard to pair between versions.
3. **An approved design exists only as a Figma frame.** Read the frame's values through the Figma MCP server, compare them with computed styles, and use the model judge for the overall match.
   - Counter-case: no mature tool does this, so the harness would own the comparison code and its errors.
4. **The question is "does it still say the same thing?"**, for example after a chart library upgrade. Use the model judge on paired screenshots, in both orders.
   - Counter-case: models miss small shifts, so a judge's "same" is never a pass by itself.

---

## Negative results

- An axe-core rule or Lighthouse audit for non-text contrast, reflow, hover content, focus visibility or focus appearance: NOT FOUND.
- Empirical evidence for modular scales, for a maximum number of font sizes, or for the 8-point grid: NOT FOUND.
- A target size in the Atlassian Design System: NOT FOUND.
- Pixel heights for the widget row spans: NOT FOUND.
- An official Atlassian statement on loading Atlassian Sans in Custom UI: NOT FOUND.
- An official export of Atlassian tokens in the community token format: NOT FOUND.
- A mature tool that checks computed styles against a token set: NOT FOUND.
- Percy's default sensitivity level or numeric thresholds: NOT FOUND.
- odiff's default threshold: NOT FOUND.
- Playwright's comparison source code: NOT FOUND (two paths returned 404).
- A screen-specific CIEDE2000 just-noticeable difference from a colour-science primary source: NOT FOUND.
- Independent false-positive rates for Applitools, Percy, Chromatic or Argos: NOT FOUND. The vendors' own accuracy claims come with no sample or method, so they are not used here.
- Apple's Human Interface Guidelines and Material Design 3 pages: NOT READABLE by the fetch tool, because they require JavaScript.
