# Why the analysis changed: old pipeline vs funnel

Regenerate with `Rscript explain/old_vs_headline.R` after running `funnel.R`.

## Files

- `Old_vs_Headline_Maps.png`: the old script 18 heatmap beside the new headline map, redrawn in a shared row order and color scale, each with a key listing every statement in each group.
- `Crosswalk_Beliefs.png`, `Crosswalk_IMI.png`, `Crosswalk_WSE.png`, `Crosswalk_AIRef.png`: every survey statement, its old group, and its new headline and detail scores.
- `Item_Crosswalk.csv`: the same crosswalk with full statement text and a change flag.
- `ART_Old_vs_New.png`: the old script 18 ART scatter plots (top) and the same three relationships with the new scores (bottom), each labeled with its BH p-value and whether it survives BH or Bonferroni. All three still survive Bonferroni.
- `WSE_Group_Versions.csv`: four candidate WSE groupings with reliability (see below).

## The short version

The old pipeline grouped items with EFA on our own data. The funnel scores each
survey the way its source paper does, then checks those groupings in our data
(CFA for Beliefs and IMI, EFA for WSE and AI Reflection, plus reliability).
Most old findings survive the change, which means they do not depend on the
grouping method.

| Decision | Old pipeline | Funnel | Evidence |
|---|---|---|---|
| Sample | 82-91 depending on the table | 82 everywhere | One sample makes every table comparable |
| Beliefs Knowledge (items 1-5) | Dropped after a failed KMO gate | Kept | The KMO failure came from a broken polychoric matrix (negative eigenvalue); Pearson KMO = .81. Knowledge now has four significant cross-survey correlations |
| Beliefs structure | 3 EFA clusters (items 6-22) | Chan & Zhou's constructs: Knowledge, Value, Cost, Intention | Their three CFAs reproduce on our data (same df); the three value facets correlate .83-.93, so Value is one headline score |
| Item 6 ("Students must learn...") | Future AI Orientation | Value | The source places it in attainment value |
| IMI | 3 EFA clusters, item 13 dropped | 3 official subscales, item 13 kept | EFA matched the subscales for 17 of 18 items; dropping item 13 changes no correlation by more than .04 |
| WSE | 3 EFA clusters, 5 items dropped | 20-item total as headline score; groups as detail | Authors scored only the total; BIC and MAP prefer 1 factor; omega hierarchical = .63 (one dominant factor) |
| AI Reflection | 2 EFA clusters, items 5 and 8 dropped | Same 2 groups, all items kept | Groups correlate .73 (separable) and follow the wording: process vs final summary |
| Cost item direction | Stored reverse-coded in item scans | Scored as worded (high = more concern) | Matches Chan & Zhou |

## Where the "New detail" groups come from

- **Beliefs** (Attainment, Intrinsic, Utility): Chan & Zhou's own value facets,
  unchanged. They are detail rather than headline because they correlate
  .83-.93 at the latent level in our data.
- **WSE** (Process, Physical, Time/Effort): Schmidt & Alexander's published PCA
  groups, adjusted so each item sits in one group, using the authors' own
  notes (item 10 goes to Time/Effort, 13 and 15 go to Process). The authors
  list item 3 in two groups, so it stays in both. Our item 19 is the
  replacement "resources" item, which was not in their PCA; our EFA puts it
  with Time/Effort. These groups are **not** from our EFA.
- **AI Reflection**: the 12-item total (the two parts are headline).

`WSE_Group_Versions.csv` compares four candidate WSE groupings:

| Version | Items used | Alphas | Between-group r |
|---|---:|---|---|
| Source PCA as published | 20 (3 shared) | .88 / .79 / .61 | .70-.76 |
| Funnel detail (chosen) | 20 (1 shared) | .89 / .74 / .61 | .49-.73 |
| Old pipeline EFA | 15 (5 dropped) | .87 / .79 / .69 | .30-.57 |
| Our EFA, k = 3, every item assigned | 20 | .86 / .83 / .69 | .38-.70 |

The EFA versions look a little cleaner, with more distinct groups and a better
Time/Effort alpha. That is expected, because they were fitted to this same
sample. To show they "hold up better" they would have to replicate in new
data. The old EFA version also drops 5 items, and our full EFA produces a
"Mixed" group without a clear meaning (audience, evidence, feedback,
structure, and physical items). We chose the published groups for
comparability. Because WSE subscales are detail-tier either way, this choice
does not affect the headline map.

## Do the old findings hold up?

| Old finding | Old r | New | New r |
|---|---|---|---|
| Utility & Comfort x Ownership & Usefulness | .61 | Value x Ownership & Usefulness | .56 |
| Future AI Orientation x Ownership & Usefulness | .53 | Intention x Ownership & Usefulness | .52 |
| Concern & Harms x Ownership & Usefulness | -.38 | Cost x Ownership & Usefulness | -.34 |
| Utility & Comfort x Perceived Competence | -.28 | Value x Perceived Competence | -.24 (no longer significant) |
| ART x Utility & Comfort / Future AI / Ownership | -.39 / -.35 / -.38 | ART x Value / Intention / Ownership | -.37 / -.40 / -.40 |
| ART x Perceived Competence | .32 | same | .36 |

Old names are kept in parentheses on the new labels so the two maps can be read side by side.
