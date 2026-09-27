# 03 — Data-visualisation quality: principles, checkable rules, and the cycle-time control chart (status on 27 September 2026)

**Sources and how they were selected.** This file cites 63 sources (distinct web pages), all listed in `sources.csv`. It answers research question 3.
- **How they were found.** One research sub-agent ran about 50 web searches and about 125 page fetches for this question. Atlassian's chart rules come from a second sub-agent.
- **Selection order.** The original paper came first, as an author or institutional copy. Then official government and vendor guidance. Secondary sources were used only where the primary could not be read.
  - Tufte's book is not online, so his definitions are taken from secondary summaries and labelled PARTIAL.
  - Vacanti's own argument for percentile lines on cycle-time charts could not be read, so the argument is taken from another Kanban-metrics practitioner.
- **A check on the fetch tool.** The sub-agent re-fetched key numbers asking for verbatim text. That caught two invented details in first-pass extractions, a palette table and a threshold, which were dropped.
- **What I re-read myself.** Atlassian's control chart documentation and Atlassian's data-visualisation colour page. My first summary of the control chart page added details the page does not contain; section 5.1 keeps only what the page says.
- **What was actually seen.** No images were viewed. In particular, I have not seen the Jira control chart; its description comes from Atlassian's documentation text.
- URLs omit "https://".

**Labels.** [VERIFIED | page | date] means I read the primary page and it says this. [VERIFIED as read by a sub-agent | page | date] means a research sub-agent read the primary page and I did not re-read it. [PARTIAL] means a secondary source, or partial support, including an abstract when the claim needs more than the abstract states. [ASSUMPTION] means my own inference or proposal. NOT FOUND means searched for and not found. NOT SEARCHED means the question was not searched, for example because the session's search limit was reached. NOT READABLE means a page could not be read by the fetch tool. Definitions, method notes and numbered instructions are not research claims and carry no label. A label on the line that introduces a list or table applies to every item in it.

**Terms used in this file.**
- An **encoding** (or visual channel) is the visual property that carries a data value, such as position, length, angle, area or colour.
- A **mark** is the drawn shape that represents a data item, such as a dot, a bar or a line.
- A **categorical palette** is a set of distinct colours for unordered groups. A **sequential palette** runs from light to dark for ordered values.
- A **baseline** here is the value where a chart's axis starts. A **truncated axis** starts above zero.
- **Overplotting** is when marks cover each other so that some data cannot be seen.
- **Cycle time** is the time between when a work item started and when it finished. [VERIFIED as read by a sub-agent | kanbanguides.org/english | version 2025.5]
- A **control chart** plots a process measure over time against lines that show its usual range, so that unusual points stand out.
- A **percentile** is the value below which a given share of observations fall; the 85th percentile of cycle time is the time within which 85% of items finished.
- The **standard deviation** measures how widely values spread around their mean. **Sigma** (σ) is its usual symbol, so "3 sigma" means three standard deviations from the centre line of a control chart.
- A **normal** (or **Gaussian**) distribution is the symmetric bell-shaped one. A **right-skewed** distribution has a long tail of large values, such as a few very slow work items.
- **Amazon Mechanical Turk** and **Prolific** are websites where researchers pay members of the public to do short online tasks, including experiments. The people who do the tasks are called **crowdworkers**.
- A **linter** is a program that checks a specification or code against written rules and reports violations.
- `00-glossary.md` defines every other term.

---

## Read first: widely repeated chart rules that the evidence does not support

Each of these is often treated as settled. The reader may hold some of them.

1. **"Line charts may start above zero; only bars must start at zero" is weaker than it sounds.**
   - Sample: 40 participants were recruited on Prolific, of whom one was excluded. They rated how severe the change was in 48 bar or line charts whose y-axis started at 0%, 25% or 50%. [VERIFIED as read by a sub-agent | arxiv.org/pdf/1907.02035 | 2020]
   - Result: more truncation raised perceived severity, and bar and line charts did not differ. [VERIFIED as read by a sub-agent | arxiv.org/pdf/1907.02035 | 2020]
   - In two further experiments, with 32 and 25 participants, explicit broken-axis symbols did not significantly reduce the effect. [VERIFIED as read by a sub-agent | arxiv.org/pdf/1907.02035 | 2020]
2. **"Bank the slopes of a line chart to 45 degrees" is not supported by the direct test.**
   - Sample: pilots with 148 Mechanical Turk workers, then experiments with 8 and with 20 people, mostly PhD students and staff in visualization or graphics. [VERIFIED as read by a sub-agent | justintalbot.com/research/slope-ratio-comparisons.pdf | 2012]
   - Result: errors in comparing slopes were generally not smallest near 45 degrees, and a visible baseline greatly reduced errors at shallow angles. [VERIFIED as read by a sub-agent | justintalbot.com/research/slope-ratio-comparisons.pdf | 2012]
3. **"People read pie charts by angle" is not what the data show.**
   - Sample: 102 Mechanical Turk workers were recruited and 92 analysed, estimating percentages on six pie and donut variants. [VERIFIED as read by a sub-agent | media.eagereyes.org/papers/2016/Skau-EuroVis-2016.pdf | 2016]
   - Result: charts that kept only the angle had much larger errors than normal pies or charts that kept only arc length or area. So people seem to read pies by area or arc, not angle. [VERIFIED as read by a sub-agent | media.eagereyes.org/papers/2016/Skau-EuroVis-2016.pdf | 2016]
4. **The standard evidence against dual-axis charts does not test two different variables.**
   - Sample: 15 participants from the authors' research institute judged one variable drawn at two magnifications on one axis. [VERIFIED as read by a sub-agent | swmprats.net/_isenberg/publications/papers/Isenberg_2011_ASO.pdf | 2011]
   - Using it against charts of two different variables on two y-axes is an extrapolation. [ASSUMPTION]
   - Datawrapper's guidance argues that the two scales of a dual-axis chart are arbitrary and can suggest false relationships. [VERIFIED as read by a sub-agent | datawrapper.de/blog/dualaxis | 2018-05-08]
   - That most guidance against dual axes rests on this argument, rather than on experiments with two variables, is my reading of the sources in this file. [ASSUMPTION]
5. **Decoration ("chartjunk") is not simply harmful.**
   - Sample: 20 university participants, of whom 10 were retested two to three weeks later. [VERIFIED as read by a sub-agent | sites.stat.columbia.edu/gelman/communication/Bateman2010.pdf | 2010]
   - Result: embellished charts were read as accurately as plain ones and were remembered better in the long term. [VERIFIED as read by a sub-agent | sites.stat.columbia.edu/gelman/communication/Bateman2010.pdf | 2010]
   - Stephen Few's rebuttal says 20 students are too few and some plain charts were badly designed. He concedes embellishment can help memory when it does not distract or distort. [VERIFIED as read by a sub-agent | perceptualedge.com/articles/visual_business_intelligence/the_chartjunk_debate.pdf | 2011]
6. **Jira's control chart shows the average and the standard deviation of cycle time, while a Kanban-metrics practitioner argues that lead-time distributions are never normal.**
   - Jira's documentation says the chart shows the average, the rolling average and the standard deviation. [VERIFIED | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27]
   - The practitioner argues that adding three standard deviations to the mean is wrong for lead times, because their distribution is never Gaussian. [VERIFIED as read by a sub-agent | connected-knowledge.com/2014/09/07/inside-lead-time-distribution | 2014-09-07]
   - Cycle time is part of lead time, so the argument probably applies to cycle time too, and then a spread based on the standard deviation misdescribes the data. Applying it to cycle time is my extrapolation. [ASSUMPTION]
   - Section 5 gives both sides.

---

## 1. The established principles, with their evidence

### 1.1 Which visual encodings people read most accurately

**Cleveland and McGill (1984).**
- **The ranking**, from most to least accurate: position along a common scale; positions along scales that are not aligned; length, direction and angle; area; volume and curvature; shading and colour saturation. [VERIFIED as read by a sub-agent | math.pku.edu.cn/teachers/xirb/Courses/biostatistics/Biostatistics2016/GraphicalPerception_Jasa1984.pdf | 1984]
- **Sample.** In the position–length experiment, 55 people made 50 judgements each and 51 were analysed. In the position–angle experiment, 54 people made 80 judgements each and 51 were analysed. They were a group of women without technical training plus a group with technical training, not a random sample. [VERIFIED as read by a sub-agent | math.pku.edu.cn/teachers/xirb/Courses/biostatistics/Biostatistics2016/GraphicalPerception_Jasa1984.pdf | 1984]
- **Result.** Position judgements were 1.4 to 2.5 times as accurate as length judgements, and about twice as accurate as angle judgements. Only position, length and angle were tested; the rest of the ranking comes from theory. [VERIFIED as read by a sub-agent | math.pku.edu.cn/teachers/xirb/Courses/biostatistics/Biostatistics2016/GraphicalPerception_Jasa1984.pdf | 1984]

**Heer and Bostock (2010), a crowdsourced replication.**
- **Sample.** Amazon Mechanical Turk workers who passed a short qualification test. There were 50 people per chart for ten charts of each of seven judgement types, giving 3,481 judgements, and 186 different workers across the paper's experiments. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2010-MTurk-CHI.pdf | 2010]
- **Results.** [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2010-MTurk-CHI.pdf | 2010]
  - The ranking by accuracy matched Cleveland and McGill's, and area judgements were worse than angle judgements.
  - A separate experiment on chart size and gridlines collected 2,880 responses over two runs, with 24 assignments per task. It found that charts 40 pixels tall produced significantly more error, with little benefit above 80 pixels.
  - The authors conclude that gridlines should be at least 8 pixels apart.

**Mackinlay (1986).**
- **His two tests.** A chart is expressive if it shows all the facts in the data and only those. It is effective if people read it accurately. His example of a failure is bar length used for unordered categories, which wrongly suggests an order. [VERIFIED as read by a sub-agent | courses.ischool.berkeley.edu/i247/f05/readings/Mackinlay_APT_TOG86.pdf | 1986]
- **His extended ranking** covers ordinal and nominal data as well. He states that it has not been empirically verified. [VERIFIED as read by a sub-agent | courses.ischool.berkeley.edu/i247/f05/readings/Mackinlay_APT_TOG86.pdf | 1986]

### 1.2 Tufte: data-ink, chartjunk and the lie factor

- **Data-ink.** Tufte's data-ink ratio is the ink that shows data, divided by all the ink in the graphic. He recommends maximising it and erasing ink that is not data or that repeats data. [PARTIAL | guypursey.com/blog/202001041530-tufte-principles-visual-display-quantitative-information | undated; secondary summary quoting the book]
- **The lie factor** is the size of an effect shown in the graphic divided by the size of the effect in the data. Values between 0.95 and 1.05 are acceptable. [PARTIAL | infovis-wiki.net/wiki/Lie_Factor | accessed 2026-09-27; secondary, citing the book's pages 57–69]
  - Tufte measured each effect as a percentage change. In 2001 a contributor on Tufte's own forum proposed a ratio of change factors instead, so a checker must state which definition it uses. [PARTIAL | edwardtufte.com/notebook/computing-lie-factor-by-dividing-percentages | 2001-07-30; forum contribution, not Tufte's text]
- **Graphical integrity.** His principles include making physical sizes proportional to the numbers, labelling clearly, and using no more dimensions than the data has. [PARTIAL | users.wpi.edu/~jdp/ma2611_18D/lecture_notes/graphics/Tufte/Tufte_on_graphics.pdf | undated course notes]
- **Memorability, not accuracy.** Borkin and colleagues studied what makes charts memorable.
  - Sample: 410 target charts drawn from 5,693 collected from news, government, science and infographic sources, shown in 276 Mechanical Turk tasks to workers with over 95% approval, of whom 261 passed the practice round. [VERIFIED as read by a sub-agent | vcg.seas.harvard.edu/publications/20130101-what-makes-a-visualization-memorable/paper | 2013]
  - Result: charts with pictures, colour and recognisable objects were more memorable, and ordinary bar and line charts less so. The authors state they did not test whether people understood the data. [VERIFIED as read by a sub-agent | vcg.seas.harvard.edu/publications/20130101-what-makes-a-visualization-memorable/paper | 2013]

### 1.3 Stephen Few: dashboards, colour, pies and baselines

**Few's thirteen dashboard pitfalls (2006).** Few names thirteen common mistakes in dashboard design. Their names, in his order, are listed below. [VERIFIED as read by a sub-agent | perceptualedge.com/articles/Whitepapers/Common_Pitfalls.pdf | 2006-02]
1. Exceeding a single screen.
2. Giving too little context.
3. Showing too much detail or precision.
4. Expressing measures indirectly.
5. Choosing the wrong kind of display.
6. Adding meaningless variety.
7. Using poorly designed displays.
8. Encoding quantities inaccurately.
9. Arranging data poorly.
10. Highlighting ineffectively.
11. Adding useless decoration.
12. Misusing or overusing colour.
13. Making the display unattractive.

**Few's nine colour rules (2008).** Few gives nine rules for using colour in charts and dashboards. In his order, they are listed below. [VERIFIED as read by a sub-agent | perceptualedge.com/articles/visual_business_intelligence/rules_for_using_color.pdf | 2008-02]
1. Keep the background consistent.
2. Make the background contrast with the objects on it.
3. Use colour only when it serves communication.
4. Use different colours only for different meanings.
5. Use soft colours for most data, and bright or dark colours only for highlights.
6. Show ordered values with one hue from pale to dark.
7. Make non-data elements just visible enough.
8. Avoid red with green.
9. Avoid visual effects.

**Pies and baselines.**
- Few argues that people judge angles and areas poorly, so bar graphs usually beat pies. [VERIFIED as read by a sub-agent | perceptualedge.com/articles/visual_business_intelligence/save_the_pies_for_dessert.pdf | 2007-08]
- A bar's length carries its value, so bars need a zero baseline, while lines and dots carry value by position and may start elsewhere. [VERIFIED as read by a sub-agent | perceptualedge.com/example14.php | accessed 2026-09-27] The truncation study in "Read first", item 1, qualifies this for lines.

### 1.4 Colour and colour-vision deficiency

- **How common colour-vision deficiency is.** A review of large population surveys puts inherited red–green deficiency at about 8% of men and 0.4% of women of European descent, and 4% to 6.5% of Chinese and Japanese men. [VERIFIED as read by a sub-agent | opg.optica.org/josaa/abstract.cfm?uri=josaa-29-3-313 | 2012; abstract]
- The US National Eye Institute says about 1 in 12 men have a colour-vision deficiency. [VERIFIED as read by a sub-agent | nei.nih.gov/learn-about-eye-health/eye-conditions-and-diseases/color-blindness | 2025-11-05]
- **Okabe and Ito** advise coding information redundantly, with shapes, line types and direct labels, and avoiding red with green. [VERIFIED as read by a sub-agent | jfly.uni-koeln.de/color | 2002, modified 2008-09-24] Their palette values appear only in an image on their page. A widely used implementation gives them as #E69F00, #56B4E9, #009E73, #F0E442, #0072B2, #D55E00, #CC79A7 and #000000. [PARTIAL | github.com/easystats/see/blob/main/R/scale_color_okabeito.R | accessed 2026-09-27; secondary implementation]
- **Simulation.** Machado, Oliveira and Fernandes published matrices that simulate red-weak, green-weak and blue-weak vision at severities from 0 to 1, which a script can apply to a palette. [VERIFIED as read by a sub-agent | inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html | 2009]
- **ColorBrewer** offers sequential, diverging and categorical schemes for 3 to 12 classes, with a filter for colour-blind-safe schemes. [VERIFIED as read by a sub-agent | colorbrewer2.org | accessed 2026-09-27]

**How many categorical colours people can use.**
- **Healey (1996).**
  - Sample: 38 observers with normal or corrected vision; recruitment not stated. They searched for a target colour among up to 49 coloured squares. [VERIFIED as read by a sub-agent | csc2.ncsu.edu/faculty/healey/download/viz.96.pdf | 1996]
  - Result: seven colours of equal brightness was the maximum that still allowed rapid, accurate identification of any one of them. [VERIFIED as read by a sub-agent | csc2.ncsu.edu/faculty/healey/download/viz.96.pdf | 1996]
- **Tseng and colleagues (2023).**
  - Sample: 95 Mechanical Turk workers from the US and Canada, 91 analysed, each judging 45 scatterplots coloured with ten common palettes. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2303.15583 | 2023]
  - Result: accuracy at finding the category with the highest mean fell from 96.4% with 2 categories to 86.6% with 10. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2303.15583 | 2023]
- **Guidance.** The recommended maximum number of categorical colours ranges widely.
  - The UK Government Analysis Function limits basic charts to four categories. [VERIFIED as read by a sub-agent | analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-colours-in-charts | updated 2026-02-12]
  - Atlassian says a chart should show no more than five to six colours. [VERIFIED | atlassian.design/foundations/color/data-visualization-color | accessed 2026-09-27]
  - Datawrapper suggests another chart type, or grouping categories, when more than seven colours are needed. [VERIFIED as read by a sub-agent | datawrapper.de/blog/colors | updated 2025-02-21]
  - The EU's data visualisation guide calls seven a good maximum. [VERIFIED as read by a sub-agent | data.europa.eu/apps/data-visualisation-guide/colour-for-categories | undated; accessed 2026-09-27]
  - IBM Carbon's categorical palette has 14 colours, which must be used strictly in their listed order. [VERIFIED as read by a sub-agent | carbondesignsystem.com/data-visualization/color-palettes | accessed 2026-09-27]
  - The VizLinter tool allows up to 20 categorical colours. [VERIFIED as read by a sub-agent | idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf | 2021]
  - The limit is therefore a platform setting, not a universal number. [ASSUMPTION]

### 1.5 Accessibility of charts

- **WCAG 1.4.11 applies to charts.** Graphical parts needed to understand the content must have 3:1 contrast against adjacent colours. [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/non-text-contrast.html | 2026-06-15]
  - In the Understanding page's line-chart example, each line needs 3:1 against the background but not against the other lines.
  - Its pie-chart example fails when adjacent slices lack 3:1 and passes once a darker border is added.
  - The criterion does not apply when visible labels and values carry the same information.
  [VERIFIED as read by a sub-agent | w3.org/WAI/WCAG22/Understanding/non-text-contrast.html | 2026-06-15]
- **Chartability.** Chartability is a set of heuristics for auditing chart accessibility.
  - The 2022 paper groups its 50 heuristics under WCAG's four principles plus three of its own: compromising, assistive and flexible. It marks 10 as critical. [VERIFIED as read by a sub-agent | domoritz.de/papers/2022-Chartability.pdf | 2022]
    - The ten are low contrast, small text, content that is only visual, interaction with only one input method, no interaction cues, and no explanation of how to read the chart.
    - They also include no title, summary or caption; no data table; inappropriate data density; and ignoring the user's style settings.
  - The paper's evaluation was small. Of 19 people across 8 projects, only 6 participants' results could be published. [VERIFIED as read by a sub-agent | domoritz.de/papers/2022-Chartability.pdf | 2022]
  - The current online workbook marks 14 heuristics critical. Its tests include more than 3:1 contrast for chart shapes and large text, more than 4.5:1 for other text, no text smaller than 12 pixels (9 points), and a second cue wherever colour is used. [VERIFIED as read by a sub-agent | chartability.github.io/POUR-CAF | accessed 2026-09-27]

### 1.6 Axes, ticks and aspect ratio

- **Tick values.** Talbot, Lin and Hanrahan's labelling algorithm scores candidate tick sets on four things: simplicity, coverage, density and legibility.
  - It prefers steps of 1, 5, 2, 2.5, 4 or 3 times a power of ten.
  - It forbids overlapping labels.
  - It was tested on 10,000 random labelling tasks, not with users.
  [VERIFIED as read by a sub-agent | justintalbot.com/research/extension-of-wilkinson.pdf | 2010]
- **Aspect ratio.**
  - Heer and Agrawala describe methods for choosing a chart's aspect ratio, the ratio of its width to its height. They note that the most perceptually effective method remains unclear, and they ran no user study. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2006-Banking-InfoVis.pdf | 2006]
  - The arc-length method of Talbot, Gerth and Hanrahan (2011) also had no user study. [VERIFIED as read by a sub-agent | researchgate.net/profile/John-Gerth/publication/221700115_Arc_Length-Based_Aspect_Ratio_Selection/links/02e7e524d83da5da94000000/Arc-Length-Based-Aspect-Ratio-Selection.pdf | 2011]

### 1.7 Vendor and government guidance with numbers

- **UK Government Analysis Function.** Its chart guidance says: [VERIFIED as read by a sub-agent | analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts | 2022-05-19]
  - Use at most ten gridlines.
  - More than four lines usually clutter a line chart.
  - Use pies only for five or fewer categories.
  - Do not use dual axes or 3-D.
  - Rank bars by value unless there is a natural order.
  - Keep axis text horizontal.
- **Its colour guidance.** [VERIFIED as read by a sub-agent | analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-colours-in-charts | updated 2026-02-12]
  - Basic charts are limited to four categories.
  - Every palette colour has at least 3:1 contrast against white.
  - Adjacent palette colours have at least 3:1 against each other, and stay distinct in greyscale.
- **Office for National Statistics.** [VERIFIED as read by a sub-agent | service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines | accessed 2026-09-27]
  - Charts that fill an area must start at zero.
  - A cropped axis needs a gap of about a quarter to a third of the chart before the first data point.
  - Use 6 to 10 gridlines on desktop and 3 to 6 on mobile, at labelled round numbers.
  - Time axes get tick marks but no gridlines.
  - Avoid dual axes and log scales unless nothing else shows the data clearly.
- **IBM Carbon.** [VERIFIED as read by a sub-agent | carbondesignsystem.com/data-visualization/axes-and-labels | accessed 2026-09-27]
  - Bar and area charts always start at zero.
  - Tick steps must not be changed to fit the data available.
  - Periods with no data must not be filled in by interpolation.
- **Urban Institute.** Keep pies under five slices, avoid dual axes and 3-D, and make bars about twice as wide as the gaps between them. [VERIFIED as read by a sub-agent | urbaninstitute.github.io/graphics-styleguide | 2025-08-27]
- **The EU's data visualisation guide.** A numerical or date axis should carry at least 2 and at most 8 labels, gridlines should be muted, and direct labels are preferred to legends. [VERIFIED as read by a sub-agent | data.europa.eu/apps/data-visualisation-guide/axes-grids-and-legends | 2023]
- **Microsoft.** Its guidance for Office add-ins says to avoid 3-D unless a real value is bound to the third dimension, and to make legend markers match the shape of the marks. [VERIFIED as read by a sub-agent | learn.microsoft.com/en-us/office/dev/add-ins/design/data-visualization-guidelines | 2025-10-29]
- **The Atlassian Design System.** It gives colour rules for charts (section 4, rules 22, 23, 30 and 31, and one of the two sources for rule 25) but no rules on chart types, axes or gridlines; those rules are NOT FOUND in ADS. [VERIFIED | atlassian.design/foundations/color/data-visualization-color | accessed 2026-09-27]

---

## 2. Rules that have already been turned into software

- **Draco** writes chart design knowledge as hard constraints, which must always hold, and soft constraints, which add a weighted penalty when broken. It uses Answer Set Programming, a logic-programming language. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf | 2019]
  - **Examples of hard constraints.** Shape may be used only with point marks; a bar or area mark with a continuous y value must include zero; size must not encode unordered categories.
  - **How the weights were learned.** They were learned from about 1,100 ranked pairs of charts from earlier perception studies. The learned weights ranked held-out pairs correctly 93% of the time, against 65% for hand-tuned weights.
  [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf | 2019]
- **Draco 2** defines 147 soft constraints, such as preferring dates on the horizontal axis. On the same kind of ranked pairs it agreed with the first version 86% of the time. [VERIFIED as read by a sub-agent | idl.cs.washington.edu/files/2023-Draco2-VIS.pdf | 2023]
- **VizLinter** checks chart specifications written in Vega-Lite, a declarative chart language, against 41 rules refined from Draco. [VERIFIED as read by a sub-agent | idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf | 2021]
  - Its rules include a limit of 20 categorical colours, and a rule that size should not encode negative values. It explicitly does not cover dual axes, legends or ineffective colours. [VERIFIED as read by a sub-agent | idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf | 2021]
  - Sample: 20 invited participants with visualization experience corrected 15 flawed charts with it. [VERIFIED as read by a sub-agent | idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf | 2021]
  - Result: they reached a 77% correction rate and accepted 90% of its suggestions. [VERIFIED as read by a sub-agent | idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf | 2021]
- **vislint_mpl**, a prototype linter for Python's matplotlib charts, checks both the chart objects and the rendered image. It names rules such as legible text, a maximum number of colours, a maximum number of pie slices, colour-blind-friendly colours, required axis labels, and no lines connecting unordered categories. It gives no numeric thresholds. [VERIFIED as read by a sub-agent | c4pgv.dbvis.de/McNutt_Kindlmann_2018.pdf | 2018]
- **Metamorphic tests for charts.** A metamorphic test changes the input in a known way and checks that the output changes, or does not change, as expected. McNutt, Kindlmann and Correll adapt it to charts. [VERIFIED as read by a sub-agent | arxiv.org/pdf/2001.02316 | 2020]
  - Shuffling the input rows should not change the image; if it does, marks are hiding each other.
  - Resampling the rows or randomising the category labels tests whether a pattern is robust.
- **Misviz, a 2025 benchmark of misleading charts.**
  - Sample: 2,604 real-world charts from a research corpus, a gallery of bad charts and two Reddit communities. Three crowdworkers from Prolific labelled 12 kinds of misleader, such as truncated, dual or inverted axes and 3-D, with Fleiss' kappa 0.53. [VERIFIED as read by a sub-agent | arxiv.org/html/2508.21675v1 | 2025-08]
  - Result, models: the best model detected whether a chart misleads 84.9% of the time, but named the exact set of misleaders only 59.4% of the time. [VERIFIED as read by a sub-agent | arxiv.org/html/2508.21675v1 | 2025-08]
  - Result, a rule-based linter: fed axis data extracted from the images, it scored 62.9% accuracy and only 3.1% exact matches. [VERIFIED as read by a sub-agent | arxiv.org/html/2508.21675v1 | 2025-08]
- **A catalogue of guidelines.** Gyarmati and colleagues catalogue 744 visualization guidelines. Each is split into advice, reason, context, exceptions, costs, mistakes, a check and a fix. They ground a model's feedback in that catalogue plus the VizLinter and Draco checks. [VERIFIED as read by a sub-agent | arxiv.org/html/2512.20306v2 | date not shown on page]
- **Consequence.** Rules should be checked against the chart's specification or its rendered SVG elements, not against pixels, because reading axes back from images fails. A model can add a second opinion on whether a chart misleads. [ASSUMPTION]

---

## 3. What can be checked by a script, and what needs judgement

**Checkable by a script from the chart specification or the rendered SVG.** [ASSUMPTION for the grouping; each rule's source is in section 4]
- Whether axis ranges, tick values, and the number and spacing of gridlines follow the rules.
- Whether the number of colours, their order and their contrast follow the rules.
- Whether the palette stays distinguishable under simulated colour-vision deficiency.
- Whether any labels overlap.
- Whether a legend is present only when needed, and whether it matches the data.
- Whether chart-type rules hold, such as the number of pie slices.
- Whether the chart has a title and a text alternative.
- Whether shuffling the rows changes the image.

**Checkable in part: a script flags candidates, and a model or person confirms.**
- Whether series differ by more than colour.
- Whether the most important comparison uses position.
- Whether density is appropriate.
- Whether the categories have a natural order, which decides whether bars must be sorted by value.
- Whether small multiples are comparable, which decides whether they must share a scale.
- Whether there is space for direct labels instead of a legend.
- Whether the lie factor is within range, where the size of a mark can be measured.

**Judgement only.**
- Whether the chart answers the question it exists for.
- Whether its explanation is clear.
- Whether its emphasis matches what matters.

---

## 4. Candidate rules, written as checkable sentences

**How to read this table.**
- **Layer** says which layer of `01-benchmark.md` the rule belongs to: U is universal, P is platform (the value comes from the design system), and T is taste and purpose.
- **Script** says whether a script can check the rule:
  - "yes" means from the chart specification or rendered SVG alone;
  - "partly" means a script can flag candidates for a model or person to confirm;
  - "no" means judgement is needed.

| # | Rule | Layer | Script | Source |
|---|---|---|---|---|
| 1 | The most important comparison is shown by position along a common scale, not by angle, area or colour. | U | partly | [VERIFIED as read by a sub-agent \| math.pku.edu.cn/teachers/xirb/Courses/biostatistics/Biostatistics2016/GraphicalPerception_Jasa1984.pdf \| 1984] |
| 2 | A bar or area chart's value axis includes zero. | U | yes | [VERIFIED as read by a sub-agent \| idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf \| 2019] |
| 3 | When a line or scatter chart's axis does not start at zero, the plot leaves a gap of about a quarter to a third before the first data point. | U | yes | [VERIFIED as read by a sub-agent \| service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines \| accessed 2026-09-27] |
| 4 | Size does not encode unordered categories or negative values. | U | yes | [VERIFIED as read by a sub-agent \| idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf \| 2019] for unordered categories; [VERIFIED as read by a sub-agent \| idvxlab.com/papers/2021VIS_VizLinter_Chen.pdf \| 2021] for negative values |
| 5 | Shape is used only with point marks. | U | yes | [VERIFIED as read by a sub-agent \| idl.cs.washington.edu/files/2019-Draco-InfoVis.pdf \| 2019] |
| 6 | Unordered categories are not joined by lines. | U | yes | [VERIFIED as read by a sub-agent \| c4pgv.dbvis.de/McNutt_Kindlmann_2018.pdf \| 2018] |
| 7 | The chart has no second y-axis unless the project records why. | U | yes | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts \| 2022-05-19] for the rule; [ASSUMPTION] for the exception when a reason is recorded |
| 8 | The chart has no 3-D effects. | U | yes | [VERIFIED as read by a sub-agent \| learn.microsoft.com/en-us/office/dev/add-ins/design/data-visualization-guidelines \| 2025-10-29] |
| 9 | A pie chart has at most five slices, is not used for parts of similar size, and starts at 12 o'clock sorted by size. | U | yes | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts \| 2022-05-19] for five slices; [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/charts-a-checklist \| 2023-05-02] for the rest |
| 10 | A pie slice under 3 degrees gets a callout, and a slice under 1 degree is not drawn. | U | yes | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/data-visualization/chart-anatomy \| accessed 2026-09-27] |
| 11 | A line chart shows no more than about four lines. | U | yes | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts \| 2022-05-19] |
| 12 | Bars are sorted by value unless the categories have a natural order, and the gaps between bars are narrower than the bars. | U | partly | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/charts-a-checklist \| 2023-05-02] |
| 13 | Comparable small multiples share the same axis scale. | U | partly | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/charts-a-checklist \| 2023-05-02] |
| 14 | A log scale is used only when no other scale shows the data clearly. | U | partly | [VERIFIED as read by a sub-agent \| service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines \| accessed 2026-09-27] |
| 15 | Tick steps are 1, 2, 2.5, 3, 4 or 5 times a power of ten, and tick labels do not overlap. | U | yes | [VERIFIED as read by a sub-agent \| justintalbot.com/research/extension-of-wilkinson.pdf \| 2010] |
| 16 | A numerical or date axis carries between 2 and 8 labels. | U | yes | [VERIFIED as read by a sub-agent \| data.europa.eu/apps/data-visualisation-guide/axes-grids-and-legends \| 2023] |
| 17 | The chart shows 3 to 6 gridlines on small screens and 6 to 10 on large screens, never more than ten, at labelled round values. | U | yes | [VERIFIED as read by a sub-agent \| service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines \| accessed 2026-09-27] |
| 18 | Gridlines are at least 8 pixels apart. | U | yes | [VERIFIED as read by a sub-agent \| idl.cs.washington.edu/files/2010-MTurk-CHI.pdf \| 2010] |
| 19 | A time axis has tick marks but no gridlines, a category axis has neither, and there are no minor gridlines. | U | yes | [VERIFIED as read by a sub-agent \| service-manual.ons.gov.uk/data-visualisation/guidance/axes-and-gridlines \| accessed 2026-09-27] |
| 20 | Axis text is horizontal. | U | yes | [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts \| 2022-05-19] |
| 21 | Tick steps are not changed to fit the data available, and periods with no data are not filled in by interpolation. | U | partly | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/data-visualization/axes-and-labels \| accessed 2026-09-27] |
| 22 | The number of categorical colours does not exceed the platform's limit, which is 5 to 6 for Atlassian. | P | yes | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| 23 | Categorical colours are used in the palette's defined order. | P | yes | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| 24 | Marks needed for understanding have at least 3:1 contrast with the background. | U | yes | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/non-text-contrast.html \| 2026-06-15] |
| 25 | Adjacent filled areas either have 3:1 contrast with each other or are separated by a border or gap. | U | yes | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/non-text-contrast.html \| 2026-06-15]; [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| 26 | Series and categories differ by more than colour, through direct labels, marker shape or dash pattern. | U | partly | [VERIFIED as read by a sub-agent \| w3.org/WAI/WCAG22/Understanding/use-of-color.html \| 2025-09-16] |
| 27 | The palette stays distinguishable under simulated red-weak, green-weak and blue-weak vision, and does not rely on red against green. | U | yes | [VERIFIED as read by a sub-agent \| inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html \| 2009] for the simulation; [VERIFIED as read by a sub-agent \| perceptualedge.com/articles/visual_business_intelligence/rules_for_using_color.pdf \| 2008-02] for red against green |
| 28 | Ordered values use one hue that runs from light for low values to dark for high values. | U | partly | [VERIFIED as read by a sub-agent \| perceptualedge.com/articles/visual_business_intelligence/rules_for_using_color.pdf \| 2008-02] |
| 29 | Gridlines and axes are visibly quieter than the data. | U | partly | [VERIFIED as read by a sub-agent \| perceptualedge.com/articles/visual_business_intelligence/rules_for_using_color.pdf \| 2008-02] |
| 30 | Strong colour is kept for emphasis; when one item is highlighted, the rest use the neutral chart colour. | P | partly | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| 31 | No text is placed on a chart colour, because Atlassian's chart colours cannot reach 4.5:1 contrast with text. | P | yes | [VERIFIED \| atlassian.design/foundations/color/data-visualization-color \| accessed 2026-09-27] |
| 32 | The chart has a title in real text, not inside an image. | U | yes | [VERIFIED as read by a sub-agent \| domoritz.de/papers/2022-Chartability.pdf \| 2022] |
| 33 | The chart has a text alternative and a way to reach its data as a table. | U | yes | [VERIFIED as read by a sub-agent \| domoritz.de/papers/2022-Chartability.pdf \| 2022] |
| 34 | Text in the chart is at least 12 pixels and has more than 4.5:1 contrast, or more than 3:1 if large. | U | yes | [VERIFIED as read by a sub-agent \| chartability.github.io/POUR-CAF \| accessed 2026-09-27] |
| 35 | A chart with one series has no legend; where a legend exists, its order matches the data order, its markers match the marks, and direct labels are used where space allows. | U | partly | [VERIFIED as read by a sub-agent \| carbondesignsystem.com/data-visualization/legends \| accessed 2026-09-27] and [VERIFIED as read by a sub-agent \| analysisfunction.civilservice.gov.uk/policy-store/data-visualisation-charts \| 2022-05-19] for the legend and its order; [VERIFIED as read by a sub-agent \| learn.microsoft.com/en-us/office/dev/add-ins/design/data-visualization-guidelines \| 2025-10-29] for matching markers |
| 36 | An unfamiliar chart form comes with a short explanation of how to read it. | U | no | [VERIFIED as read by a sub-agent \| domoritz.de/papers/2022-Chartability.pdf \| 2022] |
| 37 | For bars and areas, the effect shown divided by the effect in the data stays between 0.95 and 1.05. | U | partly | [PARTIAL \| infovis-wiki.net/wiki/Lie_Factor \| accessed 2026-09-27] |
| 38 | Shuffling the input rows does not change the rendered chart. | U | yes | [VERIFIED as read by a sub-agent \| arxiv.org/pdf/2001.02316 \| 2020] |
| 39 | A dense scatterplot uses transparency, careful jitter or binning so that overlapping points stay visible. | U | partly | [VERIFIED as read by a sub-agent \| clauswilke.com/dataviz/overlapping-points.html \| accessed 2026-09-27] |
| 40 | Any band or limit lines name their statistic (standard deviation, percentile or process limits), and any rolling average names its window. | T | partly | [ASSUMPTION, built on the Jira, Kanban and NIST sources in section 5] |

---

## 5. The cycle-time control chart

This section applies the rules above to the first worked example: a dashboard gadget that shows a cycle-time control chart and has a configuration screen.

### 5.1 What Jira's own control chart shows

I read the documentation's text, not the chart itself. My first summary of this page added three details that the page does not contain: a shaded band, dots placed by completion date, and rules for clusters and outliers. I re-read the page, and only what it says is kept below. [VERIFIED | support.atlassian.com/jira-software-cloud/docs/view-and-understand-the-control-chart | accessed 2026-09-27]
- **What it measures.** The chart shows the cycle time, or the lead time, for a product, a version or a sprint.
- **What it draws.** It shows the average, the rolling average and the standard deviation for that data. Each dot is one work item, and selecting a dot shows that item's data.
- **What the documentation says the chart is for.** Less variance in cycle time means more confidence in using the mean or median to predict future performance.
- **What the user can change.** The user can zoom in, and can refine the chart by columns, filters and swimlanes.
- **What the page does not say.** Four things are NOT FOUND on this page: which date each dot is placed against; whether the standard deviation is drawn as lines or as a shaded band; how clusters of items and outliers are drawn; and how the rolling window is chosen. A linked article covers the rolling-average calculation, but its text was cut off when fetched. [PARTIAL | support.atlassian.com/jira-software-cloud/docs/methods-of-calculating-rolling-average-on-the-control-chart | accessed 2026-09-27]

### 5.2 The disagreement about how to show the spread

- **The Kanban Guide's framing.** It defines a service level expectation as a forecast with two parts, an elapsed time and a probability. Its example is 85% of items finishing in eight days or less. [VERIFIED as read by a sub-agent | kanbanguides.org/english | version 2025.5]
- **The argument against mean plus standard deviation.** A Kanban-metrics practitioner describes lead-time distributions in knowledge work as right-skewed, meaning a long tail of slow items.
  - He says adding three standard deviations to the mean is incorrect, because the distribution is never Gaussian.
  - He lists the 80th, 85th, 90th, 95th, 98th and 99th percentiles as usual choices.
  - The post describes no dataset.
  [VERIFIED as read by a sub-agent | connected-knowledge.com/2014/09/07/inside-lead-time-distribution | 2014-09-07]
  - The post is about lead time. That the same skew holds for cycle time, which is part of lead time, is my extrapolation. [ASSUMPTION]
- **The classic control-chart alternative.** The NIST/SEMATECH handbook, published by the US National Institute of Standards and Technology, builds an individuals chart from moving ranges, the differences between consecutive values. Its limits are the mean plus or minus 3 × (average moving range ÷ 1.128). [VERIFIED as read by a sub-agent | itl.nist.gov/div898/handbook/pmc/section3/pmc322.htm | accessed 2026-09-27]
  - Since 3 ÷ 1.128 is about 2.66, these are the "natural process limits" associated with Donald Wheeler. [ASSUMPTION: my arithmetic; Wheeler's own article was behind a login]
  - A secondary source reports Wheeler's view that such limits do not assume a normal distribution. [PARTIAL | en.wikipedia.org/wiki/Shewhart_individuals_control_chart | accessed 2026-09-27]
- **Signal rules.** NIST lists the Western Electric rules for signals: one point beyond 3 sigma; two of three beyond 2 sigma; four of five beyond 1 sigma; eight in a row on one side; six in a row rising or falling. [VERIFIED as read by a sub-agent | itl.nist.gov/div898/handbook/pmc/section3/pmc32.htm | accessed 2026-09-27]
  - The 3-sigma rule alone gives a false alarm about once every 371 points on average.
  - Adding the other rules raises that to about once every 91.75 points.
  [VERIFIED as read by a sub-agent | itl.nist.gov/div898/handbook/pmc/section3/pmc32.htm | accessed 2026-09-27]
- **Vacanti.** Daniel Vacanti's own argument for percentile lines on cycle-time scatterplots: NOT FOUND. His product and book pages returned marketing text or nothing readable.

**What this means for the gadget.** [ASSUMPTION]
- Which spread to show is a purpose decision for the person who owns the gadget, not a universal rule. The three options are the standard deviation (as lines or a band), percentile lines, and process limits.
- The rubric should record the choice and its reason, as the `spread_statistic` decision in `05-template.md`, section W1.1.
- The checker can then verify three things:
  - that the chart names its statistic;
  - that the drawn line sits where the statistic computed from the same data says it should, within one pixel;
  - that no line or band extends below zero, since cycle time cannot be negative.
- Counter-case: Jira users already know a chart that shows the standard deviation. Replacing it may confuse them, even if percentiles describe skewed data better.

### 5.3 Overplotting

- Claus Wilke recommends partial transparency, so that overlapping points look darker. He warns that jittering (nudging points slightly) changes the data and must be used with care. For large data he recommends two-dimensional histograms or hexagonal bins. [VERIFIED as read by a sub-agent | clauswilke.com/dataviz/overlapping-points.html | accessed 2026-09-27]
- If the gadget places each item by its completion date, items finished on the same day with similar cycle times will overlap. [ASSUMPTION]
  - The candidate remedies are transparency, a small jitter along the date axis only, or a count shown on clustered points.
  - The shuffle test (rule 38) confirms that no mark hides another in a way that depends on row order.
  - Counter-case: jitter along the date axis moves a point off its true completion date, which matters if people read dates from the chart.

### 5.4 Rules applied to the gadget

[ASSUMPTION for the application; the rules and values come from the sources cited above]
- **Colours.** Use Atlassian's chart tokens:
  - `color.chart.brand` for the item dots;
  - `color.chart.neutral` for the average, percentile or limit lines;
  - `color.text.subtle` for tick labels and `color.border` for gridlines.
- **Lines need a second cue.** The average, rolling-average and percentile lines must differ by dash pattern or a direct text label, not only by colour. Unusual items must differ by marker shape as well as colour.
- **The y-axis starts at zero.** Cycle time cannot be negative. Also, the truncation study in "Read first", item 1, found that truncation inflated perceived differences equally in bar and line charts. That study did not test charts of dots, so applying it to this chart is an extrapolation.
- **Text size.** Tick labels are at least 12 pixels, which matches both Atlassian's small body size and Chartability's minimum.
- **Legibility at every size.** Every rule must hold at each widget width the dashboard allows (see `05-template.md`). At the smallest width, fewer gridlines and ticks are expected (3 to 6).
- **Accessibility.** The chart offers a text summary and a table of the items, which also serves as the "equivalent control" for points too small to be 24-pixel targets.
- **UI Kit limits.** UI Kit has no scatter chart, so this chart likely needs Custom UI with an SVG chart library, which also keeps it checkable by script. See `02-automated-checks.md`, B2.

---

## Negative results

- Tufte's own text on data-ink, chartjunk, the 0.95–1.05 range or small multiples: NOT FOUND online. The book is in print only.
- Colin Ware's recommended number of categorical colours: NOT FOUND.
- Material Design's data-visualisation rules: NOT READABLE, because the page requires JavaScript.
- The Financial Times Visual Vocabulary: NOT READABLE. GitHub disallowed the fetch, and ft.com was blocked.
- The Jira control chart's date axis, the form of its standard-deviation display, its rolling window, and its treatment of clusters and outliers: NOT FOUND on the documentation page.
- Wheeler's own XmR formulas: NOT FOUND, because the article is behind a login.
- Vacanti's own argument for percentile lines: NOT FOUND.
- Numeric error values per judgement type in Heer and Bostock's text: NOT FOUND.
- The text of Cleveland, McGill and McGill (1988) on banking: NOT FOUND, because the publisher returned an error.
- The size of the user study behind the colour-vision simulation matrices: NOT FOUND.
- Atlassian rules on chart types, axes, legends or gridline density: NOT FOUND.
