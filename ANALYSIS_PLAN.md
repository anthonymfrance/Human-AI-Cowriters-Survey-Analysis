# Analysis plan: measurement checks and exploratory associations

## Purpose and status

This plan organizes a transparent, exploratory analysis of the available survey
data. The analyses are post hoc because the plan is being written after looking
at the data and earlier outputs. Source-paper structures provide hypotheses;
they do not validate the adapted instruments in this sample.

## 1. Sample and scoring

- Use the 82 participants with complete records across the four survey exports,
  condition/order information, and ART. State this as the funnel's complete-case
  analysis sample, not as the only possible sample for every future question.
- Preserve the supplied reverse-scored values. Flip Beliefs items 17-20 once so
  high scores mean greater perceived cost/concern.
- Convert WSE's five observed slider anchors (0, 25, 50, 75, 100) to 1-5.
- Export an item scoring and membership map, descriptives, ceiling/floor rates,
  and internal-consistency estimates for every proposed multi-item score.
- Keep a clean item-statement lookup (`funnel_item_text.csv`) beside the script
  so exported membership tables and visual maps can show the wording behind
  each score without exposing participant responses.

## 2. Measurement questions

For each instrument, show item-level descriptives, Pearson and polychoric
correlation diagnostics, KMO where defined, matrix eigenvalues, EFA loadings,
and reliability for proposed scores. KMO is descriptive context for EFA, not a
universal pass/fail rule and not a CFA requirement. A non-positive-definite or
unavailable polychoric matrix is reported as an estimation limitation; it is
not silently repaired for the primary diagnostics.

- **IMI:** Primary check is a three-factor ordinal CFA of the source subscales;
  the EFA is supplementary. Score the official subscale means. Item 13 is the
  weakest item; keep it and report a with/without sensitivity check.
- **Beliefs about AI:** The administered columns 1-22 correspond to source Q2-23.
  Replicate Chan & Zhou's three separate CFAs (Knowledge 1-5; Value 6-16 as
  three linked facets; Cost 17-20). Also fit combined 4-factor (Knowledge,
  Value, Cost, Intention) and 6-factor (value split into facets) models.
  Cost items are scored as worded (high = more cost). Do not imply that the
  adapted measure has replicated the source CFA.
- **WSE:** The source groups came from an exploratory PCA and the authors scored
  only the total, so there is no CFA. Use EFA to examine structure in this
  sample. The 20-item mean is the headline score; source groups (one group per
  item, authors' reassignments, replacement item 19 placed by our EFA) are
  detail-tier.
- **AI Reflection:** Local scale. EFA only, comparing 1-3 factors: there is no
  source structure, and its groups came from our own EFA on this sample, so a
  CFA would only re-fit that EFA. The
  process (1-3) and product (4-12) parts are headline scores; the 12-item
  total is detail-tier.

Use ordinal/polychoric EFA and ordinal WLSMV CFA when estimable. Also report
Pearson KMO as a sensitivity diagnostic; never select a factor model just
because one KMO is larger. Loading values around .30/.40/.60 are descriptive
heuristics, not universal deletion rules. Retain items based on the complete
pattern, wording, theory, and stability; do not tune the model solely to fit
this sample.

## 3. Composite scoring

Create transparent unit-weighted means after declaring the item maps. No items
are dropped. CFA/EFA check each grouping; scores are item means, not factor
scores. Each score is assigned a tier before any correlations are examined:

- **Headline** (passes all three: defined by the source or item wording,
  separable in this sample with latent r below about .85, reliable): Knowledge,
  Value, Cost, Intention; IMI Interest, Competence, Effort; WSE total; AI
  Reflection process and product.
- **Detail** (fails at least one): Attainment, Intrinsic, Utility (latent r
  .83-.93); WSE process, physical, time/effort; AI Reflection total.

Do not move a score between tiers after seeing its results.

## 4. Exploratory correlations

- Main overview (family B): Spearman correlations among headline scores across
  different instruments, shown as the headline heatmap. Pairs involving any
  detail score form a separate family (C) and a separate detail heatmap.
- Source replication (family A): Pearson correlations of Knowledge, Value, the
  three value facets, and Cost with Intention, compared with Chan & Zhou's
  Table 5.
- ART: correlate ART net with those candidate scores as an exploratory external
  association; report hits and false alarms descriptively so net-score
  interpretation is transparent.
- Q17 AI-tool use (declared Nov 13, 2026, before any funnel Q17 results): two
  scores, correlated with the headline scores as one external family like ART.
  (1) ChatGPT frequency, the single 1-5 item. (2) Breadth: the number of the
  other 27 tools (Grammarly excluded as an editing tool) rated 3 or higher
  ("I rarely use this tool" or more). Exclude straight-line Q17 submissions
  (every tool given the same rating). Means across all tools, bucket counts or
  proportions, and "primary model" groups are not used.
- Order: for selected pre-existing pairs, compare Spearman rho between
  counterbalance groups using permutation p-values and stratified bootstrap
  intervals. Treat these selected comparisons as secondary exploration.
- Secondary exploration: survey item x candidate scale and cross-instrument
  item x item associations, grouped into declared test families. Do not include
  within-instrument item pairs in the main item scan because those are already
  part of the measurement/reliability question.
- Report rho, confidence interval, n, raw p, BH-adjusted p, and Bonferroni
  adjusted p. Sort by absolute rho for strength and use adjusted p-values as
  evidence summaries. BH/Bonferroni do not establish causality or identify
  individual results as noise.
- Mark every correlation result exploratory. A ranked map is a navigation aid,
  not a list of confirmed discoveries.
- Present the cross-instrument candidate-score family as a color heatmap with
  Spearman rho values and correction markers. Pair it with per-instrument
  item-to-score membership maps that show each statement and flag overlapping
  membership (especially the WSE source groups). Keep the plots descriptive;
  use the CSV exports for exact values and scoring rules.

The order comparison uses a label-permutation test for the difference in
Spearman correlations and a stratified bootstrap interval. This is a secondary
analysis of selected pairs, not a complete interaction search.

## 5. Interpretation limits

N=82 is modest for ordinal CFA/EFA with 18-22 items. Report convergence,
standard errors, fit indices, and problematic estimates; treat failure to
converge or unstable matrices as meaningful limits. Do not interpret poor fit
as proof that a source instrument is invalid, or acceptable fit as validation.
Correlations are cross-sectional associations and cannot show that one
construct caused another. Any analysis of paired session outcomes must retain
participant pairing; the current funnel's single-record survey scores do not
substitute for the crossover model.
