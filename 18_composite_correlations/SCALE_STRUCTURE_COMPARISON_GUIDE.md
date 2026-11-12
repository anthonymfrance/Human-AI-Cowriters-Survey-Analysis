# Reading the Script 18 vs current scale maps

## What the figures show

The existing `plots/EFA_vs_Composite_Cross_Factor_Heatmap.png` compares
correlations among old EFA factor scores with correlations among Script 18's
simple mean composites. It does not show item membership. The four
`plots/Script18_vs_Current_Item_Map_*.png` figures supply that missing key:
rows are the full item statements and columns are old or current factors and
scores.

- EFA/CFA tiles print signed loadings where absolute loading is at least .30.
- An `x` means the item is included in a unit-weighted mean score.
- Blank cells mean no mean-score membership or an EFA/CFA loading below the
  display threshold. The .30 display threshold is not a deletion rule.
- `plots/Script18_vs_Current_Scale_Item_Key.csv` gives the full item-level
  lookup, factor loadings, item statements, scoring direction/rule where
  applicable, and whether each loading appears in the plot. Filter
  `loading_displayed = TRUE` to see the plotted factor cells.

The maps combine related evidence but do not make every column equivalent.
EFA discovers possible groupings, CFA estimates a structure specified in
advance, and a composite is a scoring recipe. Dots in an item-mean column do
not mean that an EFA or CFA validated that score.

## What changed between pipelines

The earlier factor analyses were not all the same analysis. Script 03 used
primary samples of 91 participants for Beliefs, 88 for IMI and WSE, and 91 for
AI Reflection. Script 18's composites include 91 participants. The current
funnel uses the same 82 complete participants throughout. In addition:

- The earlier Beliefs diagnostic used all 22 items and a repaired polychoric
  matrix; it reported KMO = .126 and stopped the recommendation. The separate
  Script 16 analysis used items 6-22, 91 participants, and a 3-factor
  polychoric EFA (KMO = .705, RMSEA = .162, TLI = .640).
- The current Beliefs 20-item polychoric matrix is also not positive definite,
  so the current EFA falls back to Pearson correlations. Pearson KMO is .807
  for all 22 items, but that does not determine the number of factors. Current
  parallel analysis suggests 3 factors for items 1-20.
- Historical factor-score correlations and composite-score correlations can
  use different participants and item sets. The old heatmap is useful for
  seeing whether broad conclusions shift with score construction; it is not a
  controlled scoring-method experiment.

## Instrument-by-instrument interpretation

### IMI

The old three EFA factors and Script 18's three means map closely onto the
three recognizable IMI areas: Interest/Enjoyment (items 1-7), Perceived
Competence (8-13), and Effort/Importance (14-18). Current source-rule means
also have good internal consistency (alpha .901, .873, .874), and the
three-factor ordinal CFA fit is encouraging (CFI .993, TLI .992, RMSEA .079,
SRMR .089). Its parameter-covariance warning and current four-factor parallel
analysis result keep this from being independent validation. The source
subscales remain the clearest primary scores; keep the four-factor EFA as a
sensitivity question.

### Beliefs about AI

The old full 22-item polychoric KMO gate failed because the repaired
polychoric correlation matrix yielded KMO .126. The unsmoothed matrix was not
positive definite. The current Pearson KMO of .807 says the Pearson
correlations share common variance; it neither repairs the polychoric problem
nor says “four factors.” Current parallel analysis suggests 3 factors, not 4,
on the 20-item EFA subset. A five-factor source CFA has encouraging CFI/TLI
(.979/.975) and RMSEA (.078), but elevated SRMR (.117), a parameter-covariance
warning, and a very weak cost item 20 loading (.102, p = .398). It is more
promising than the separate old 3-factor EFA by those global fit summaries,
but the comparisons use different samples/item sets and are not a fair
same-model contest. Retain source-defined Knowledge, Attainment, Intrinsic,
Utility, and Cost as transparent candidate means; treat Intention (items
21-22) as a two-item observed mean. Keep broad Value as secondary. Describe
the factor structure as unresolved in this sample.

### Writing Self-Efficacy (WSE)

The old EFA parallel analysis suggested 4 factors, but the workflow manually
locked 3 because the four-factor pattern was messy. Its retained clean-item
map and Script 18 composites each omit 5 of the 20 items. The current
parallel-analysis EFA also suggests 4 factors; its fit is unusually good, but
N = 82 for 20 items makes a same-sample exploratory pattern fragile. The
source-informed three-factor CFA fits well by common descriptive indices
(CFI .987, TLI .985, RMSEA .061, SRMR .099), yet carries a covariance warning;
item 19 loads negatively on Physical/Emotional Barriers (-.196) and very
strongly on Time/Effort (.982). The source Time/Effort mean has alpha .607,
and the source groups intentionally overlap on items 3, 10, and 19. A total
score has alpha .906. Use the total as the simplest descriptive summary if the
research question concerns overall writing self-efficacy; show the source
facets as exploratory sensitivity scores when the facet meanings matter. Do
not present the overlapping source facets as a settled factor structure.

### AI Reflection

Both old and current parallel analysis suggest 2 factors. The old map and
current EFA broadly separate enjoyment/satisfaction from ownership/usefulness.
However, the current two-factor EFA fit is poor (RMSEA .174, TLI .685); item 5
has a weak loading (.275) and item 8 cross-loads (.36/.57). The 12-item total
has alpha .863, which is not evidence of unidimensionality. Keep the total as
a provisional descriptive score and describe the two domains as exploratory.

## Loading and weighting rules

The older EFA workflow assigned an item's primary factor by its largest
absolute loading. It called a primary loading of at least .40 salient, flagged
a cross-loading when a secondary absolute loading was at least .30 and the
gap between first and second loadings was under .15, and called an item “clean”
only if it was salient and not cross-loading. These are project rules and
heuristics, not universal laws. IMI subscales come from the source scoring
structure, not from a universal loading cutoff.

The current funnel does not drop items using those cutoffs. The comparison
plots only suppress loading cells below |.30| to stay readable. Source-based
means give each included item equal weight after the declared scoring
direction/reversal. CFA loadings describe item-factor relationships; they are
not automatically used as weights in a mean. Historical EFA factor scores
used model-based Ten Berge scores, which differ from equal-weight item means.

Factor count is not chosen by KMO. The older EFA workflow used parallel
analysis, scree/candidate solutions, item clarity, KMO as a gate, and manual
review. A “K-means elbow” is a clustering tool, not the EFA factor-retention
method used here.

## Working recommendation for the exploratory report

Use source-defined IMI means as the main IMI scores. For Beliefs, show the
source facets and intention mean, with the factor evidence clearly marked as
mixed. For WSE, make the total the simplest headline score and source facets a
sensitivity/exploratory analysis. For AI Reflection, report a provisional
total and show its two-domain EFA as exploratory. Present all post-hoc
correlations as exploratory, even when their p-values survive BH or
Bonferroni correction.
