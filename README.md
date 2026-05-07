# Cowriters Survey Analysis

This repository is the current numbered analysis pipeline for the Cowriters crossover study. The active workflow starts from two long-format Qualtrics exports plus the participant tracking sheet, cleans and audits them, builds EFA-ready datasets, locks measurement structure, tests order effects, runs several ART-centered and beliefs-centered exploratory analyses, clusters participants into profiles, and ends with a final figure report.

This README is meant to be the working reference for:

- what the study design is in the current codebase
- what each numbered script does
- what math or statistical test each script uses
- why each method was chosen
- what files each script produces
- which outputs are most useful when you are building a slideshow

## What This Pipeline Does

- Cleans and deduplicates raw RW and LLM survey exports.
- Preserves as much data as possible in a small-N study by combining automated duplicate resolution with manual triage.
- Builds a strict paired analysis sample of `N = 82`.
- Builds larger instrument-specific EFA samples for structure discovery (`N = 88` for RW-side instruments and `N = 91` for LLM-side instruments).
- Uses empirical factor extraction because the adapted survey blocks do not have a fully locked scoring key in this repo.
- Converts locked EFA item sets into unit-weighted composite means for order-effect analyses.
- Uses nonparametric tests where the data are ordinal, small-sample, or likely non-normal.
- Uses ART as an external anchor for reading breadth / print exposure in multiple side analyses.
- Creates a final figure report in `13_results.qmd`.

## What This Pipeline Does Not Yet Do

- The active numbered scripts do **not** currently analyze direct comprehension / retention test scores from the study design.
- The active numbered scripts do **not** currently score notes, summaries, or article-test performance as primary outcomes.
- Files such as `accuracycheckFAtaskandreadingscores.r` exist, but they are not part of the current `01` through `13` numbered workflow.

That distinction matters for interpretation: the current numbered pipeline is strongest on survey structure, order effects, reading-breadth correlates, and participant profiling. It is not yet the full end-to-end learning-outcomes analysis.

## Study Design In The Current Repo

The code assumes a 2 x 2 crossover design:

- Within-subject factor: `Tool` (`Traditional` / `Alone` vs `AI` / `LLM`)
- Between-subject factor: `Order` (`Traditional_First` vs `AI_First`)
- Counterbalanced content factor: article topic (`Metaphor` vs `Category`), tracked through `Topic 1` and `Topic 2`
- Strict paired analysis sample: participants with clean RW and clean LLM data after duplicate resolution

The main logic is:

- Every participant contributes both a traditional-session block and an AI-session block.
- `Order` is derived from `condition_1` and `condition_2`, not inferred informally.
- `first_topic` is used as a between-subject covariate in the topic-controlled mixed ANOVAs.
- Manual salvage is allowed for EFA structure discovery, but **not** for the strict paired crossover analyses.

## Instruments And Scoring Rules

| Instrument | Condition / timing in current pipeline | Raw scale | Current role | Scoring notes |
| --- | --- | --- | --- | --- |
| `IMI` | RW / traditional session | 1-7 Likert | Cleaned, EFA, composites, order tests, ART analyses, profiles | Reverse-scored items: `3, 4, 13, 15, 18` using `8 - x` |
| `WritingEfficacy` | RW / traditional session | 0/25/50/75/100 slider | Cleaned, EFA, composites, order tests, ART analyses, profiles | No reverse scoring; rescaled to `1:5` **for EFA only** via `(x / 25) + 1` |
| `AuthorRecognition` / `ART` | RW | checklist / text selections | Scored downstream in Scripts `07` and `09` | Hits, false alarms, net score, and adjusted rate derived after matching against `authorkey.csv` |
| `AIReflection` | LLM / AI session | 1-5 Likert | Cleaned, EFA, composites, order tests, ART analyses, profiles | No reverse scoring in current pipeline |
| `BeliefsAboutAI` | LLM / AI session | 1-5 Likert | Cleaned, EFA attempted, item-level fallbacks, order tests, ART analyses, profile comparisons | Reverse-scored original Qualtrics items `17-20` using `6 - x`; not factorable in final workflow |
| `Q17` AI tool use | LLM side survey | 5 ordered use levels | Side analysis only | Response map: `1 = never heard`, `2 = heard but never used`, `3 = rarely`, `4 = sometimes`, `5 = often` |

## Canonical Inputs

Keep these files at the repository root:

- `rw-survey-long-040726.csv`
- `llm-survey-long-040726.csv`
- `Participant Tracking - IDs and Conditions Table.csv`
- `authorkey.csv`

Important manual handoff:

- `02_efa_exports.qmd` expects `01_audit_cleaning/audit/Triage_Rap_Sheet_Verified.csv`
- if that file is not in the numbered output folder, the script falls back to `inputs/audit/Triage_Rap_Sheet_Verified.csv`

So the real workflow is:

1. Render `01_audit_cleaning.qmd`
2. Review `Triage_Rap_Sheet.csv`
3. Save the reviewed decisions as `Triage_Rap_Sheet_Verified.csv`
4. Continue with `02` onward

## Output Conventions

- Each numbered script renders into a same-named folder, for example `04_order_effects/`.
- Each rendered report creates an HTML file in that folder.
- Most reports also create a Quarto support directory such as `04_order_effects/04_order_effects_files/`. Those folders contain render assets and inline figure files and are not the main analytical deliverables.
- The canonical analytical outputs are the `csv/`, `plots/`, `audit/`, `cleaned/`, `efa/`, and `efa_diagnostics/` files inside the numbered output folders.
- `13_results.qmd` uses `embed-resources: true`, so its output is mainly the single self-contained file `13_results/13_results.html`.

## Render Order

The active order is:

1. `01_audit_cleaning.qmd`
2. `02_efa_exports.qmd`
3. `03_efa_analysis.qmd`
4. `04_order_effects.qmd`
5. `05_beliefs_item_analysis.qmd`
6. `06_interesting_findings.qmd`
7. `07_q17_ai_use.qmd`
8. `08_ai_beliefs_items.qmd`
9. `09_art_vs_all_factors_items.qmd`
10. `10_participant_profiles.qmd`
11. `11_profile_external_comparisons.qmd`
12. `13_results.qmd`

Render helper:

- Full pipeline: `.\render_numbered_qmds.ps1`
- Single step: `.\render_numbered_qmds.ps1 04_order_effects.qmd`

## Core Statistical Choices And Why

### 1. Empirical factor discovery instead of pre-locked scale scoring

Why:

- The adapted instrument blocks in this project do not have a single final scoring key already encoded in the repo.
- A data-driven EFA is safer than forcing unsupported subscales.

How:

- Use polychoric item correlations.
- Use `psych::fa(..., fm = "minres", rotate = "oblimin")` when `k > 1`.
- Use no rotation when `k = 1`.

### 2. Ordinal treatment of Likert-style instruments

Why:

- IMI, AIReflection, and Beliefs are ordinal Likert data.
- WritingEfficacy is stored as a `0/25/50/75/100` slider, but the observed data use only five anchors, so the code treats it as ordered after rescaling.

How:

- WritingEfficacy EFA transformation: `score_1_to_5 = (score_0_100 / 25) + 1`
- This rescaling is used for factor modeling only, not for the raw cleaned export.

### 3. KMO as the gatekeeper for whether a factor solution is allowed

Why:

- A mathematically possible factor solution is not enough if the items do not share enough common variance.
- This is especially important in a small sample.

How:

- `KMO < 0.50` => not suitable
- `0.50 <= KMO < 0.60` => marginal
- otherwise => adequate
- In the current locked workflow, `BeliefsAboutAI` fails this gate and stays item-level.

### 4. Unit-weighted composite means instead of regression-weighted factor scores for the main crossover tests

Why:

- The project explicitly wants interpretable scale-level scores.
- Regression-weighted factor scores would move everything onto a latent-score metric that is less intuitive for presentation.

How:

- `rowMeans(item_set, na.rm = FALSE)` on the locked clean item sets from `EFA_Final_Item_Map.csv`
- `na.rm = FALSE` prevents partial composites from silently entering the inferential models

### 5. Mostly nonparametric group comparisons

Why:

- The order groups are relatively small (`about 45` vs `37`)
- Many outcomes are ordinal or composite summaries of ordinal items
- The repo is prioritizing robustness over parametric elegance for exploratory comparisons

How:

- Mann-Whitney / Wilcoxon rank-sum for two-group order comparisons
- Kruskal-Wallis for profile omnibus tests
- Pairwise Wilcoxon follow-up tests only when omnibus profile tests survive correction

### 6. Multiple-comparison correction is built into nearly every exploratory pass

Why:

- This repo intentionally runs many correlations and item-level comparisons.
- Without correction, the final slide deck would overstate noise.

How:

- `BH` is used to control false discovery rate
- `Bonferroni` is also reported where a stricter family-wise threshold is useful
- The correction family depends on the script and is documented below script by script

### 7. Fisher z is used for correlation intervals and subgroup-difference tests

Why:

- The repo repeatedly asks whether one correlation differs by order group.
- Fisher z is the standard way to compare two independent correlations.

How:

- Correlation CI in `13_results.qmd`: transform `rho` with `atanh(rho)`, use `SE = 1 / sqrt(n - 3)`, then back-transform with `tanh()`
- Subgroup difference tests in `04` and `06`: `psych::r.test()`

### 8. Participant profiles are defined only from validated factor scores

Why:

- The profile solution should not be driven by the unstable `BeliefsAboutAI` block.
- Profiles should be built from the part of the measurement model the repo currently trusts.

How:

- Standardize factor-score columns with `scale()`
- Compute Euclidean distances
- Run Ward hierarchical clustering with `method = "ward.D2"`
- Choose the best `k` from `2:5` using average silhouette, with a minimum cluster-size floor of `8`

## Script-By-Script Reference

### `01_audit_cleaning.qmd`

Main job:

- Read the raw RW and LLM Qualtrics long files.
- Audit expected item counts by instrument and source file.
- Resolve duplicate submissions.
- Define the strict clean paired sample.
- Export clean long-format instrument files.

Math / logic used:

- IMI reverse scoring: `score = 8 - raw_score` for items `3, 4, 13, 15, 18`
- Beliefs reverse scoring: `score = 6 - raw_score` for original Qualtrics items `17-20`
- AI scores are extracted from labeled strings with `parse_number()`
- Duplicate resolution favors the submission with the best target-block quality, penalizes straight-lining, and uses Qualtrics submission status only as a fallback ranking
- `order` is derived from `condition_1` and `condition_2`

Why this approach:

- The sample is small, so the pipeline tries to preserve usable data rather than naively dropping every duplicate or incomplete case.
- The duplicate resolver is stricter than raw Qualtrics labels and explicitly punishes complete straight-lined blocks.
- This is the gatekeeping stage that protects every downstream result.

Outputs:

- Report files: `01_audit_cleaning/01_audit_cleaning.html`, `01_audit_cleaning/01_audit_cleaning_files/`, `01_audit_cleaning/output_manifest.csv`
- Audit files: `01_audit_cleaning/audit/All_PIDs_Rap_Sheet.csv`, `01_audit_cleaning/audit/Diagnostic_Audit_Full.csv`, `01_audit_cleaning/audit/InstrumentAudit.csv`, `01_audit_cleaning/audit/Participant_Triage.csv`, `01_audit_cleaning/audit/Salvage_Candidates.csv`, `01_audit_cleaning/audit/Submission_Resolution_Audit.csv`, `01_audit_cleaning/audit/Sus_Participants_Rap_Sheet.csv`, `01_audit_cleaning/audit/Triage_Rap_Sheet.csv`
- Clean long-format files: `01_audit_cleaning/cleaned/AI_Reflection_cleaned.csv`, `01_audit_cleaning/cleaned/AuthorRecognition_cleaned.csv`, `01_audit_cleaning/cleaned/BeliefsAboutAI_cleaned.csv`, `01_audit_cleaning/cleaned/IMI_cleaned.csv`, `01_audit_cleaning/cleaned/WritingEfficacy_cleaned.csv`

Important manual dependency:

- `Triage_Rap_Sheet_Verified.csv` is a reviewed handoff file used by Script `02`; it is referenced in the manifest but not auto-created by the current render.

### `02_efa_exports.qmd`

Main job:

- Build the long-format EFA inputs for each instrument.
- Separate `primary` EFA samples from `sensitivity` EFA samples.
- Create the strict paired wide dataset used by crossover analyses.

Math / logic used:

- `primary` EFA samples add approved salvage participants to maximize usable `N`
- `sensitivity` EFA samples stay on the strict paired `N = 82`
- IMI and Beliefs are already reverse-scored before export
- `Final_Master_Wide.csv` is created by pivoting each cleaned instrument wide and joining them on `participant_id`

Current locked sample sizes:

- `IMI` primary: `N = 88`
- `WritingEfficacy` primary: `N = 88`
- `AIReflection` primary: `N = 91`
- `BeliefsAboutAI` primary: `N = 91`
- Sensitivity sample for all four instruments: `N = 82`

Why this approach:

- Factor discovery benefits from a larger instrument-specific sample.
- The inferential crossover analyses still need a strict paired dataset so the within-subject comparison stays clean.

Outputs:

- Report files: `02_efa_exports/02_efa_exports.html`, `02_efa_exports/02_efa_exports_files/`
- EFA summary and manifest: `02_efa_exports/efa_diagnostics/EFA_Export_Summary.csv`, `02_efa_exports/audit/EFA_Exports_Manifest.csv`
- Primary EFA exports: `02_efa_exports/efa/IMI_EFA_Primary.csv`, `02_efa_exports/efa/WritingEfficacy_EFA_Primary.csv`, `02_efa_exports/efa/AI_Reflection_EFA_Primary.csv`, `02_efa_exports/efa/BeliefsAboutAI_EFA_Primary.csv`
- Sensitivity EFA exports: `02_efa_exports/efa/IMI_EFA_Sensitivity.csv`, `02_efa_exports/efa/WritingEfficacy_EFA_Sensitivity.csv`, `02_efa_exports/efa/AI_Reflection_EFA_Sensitivity.csv`, `02_efa_exports/efa/BeliefsAboutAI_EFA_Sensitivity.csv`
- Strict paired master file: `02_efa_exports/Final_Master_Wide.csv`
- Reconciliation file: `02_efa_exports/audit/Participant_Count_Reconciliation.csv`

### `03_efa_analysis.qmd`

Main job:

- Diagnose whether each instrument is factorable.
- Fit candidate EFA solutions.
- Recommend and lock `k`.
- Export the final item-to-factor map used downstream.

Math / logic used:

- WritingEfficacy is rescaled for EFA only: `(0,25,50,75,100) -> (1,2,3,4,5)`
- Items with zero variance or fewer than two observed levels are removed before EFA
- Polychoric correlations are used, with smoothing only when the unsmoothed matrix is not usable
- `psych::fa(..., fm = "minres", rotate = "oblimin")` is used when `k > 1`; `rotate = "none"` when `k = 1`
- Candidate `k` values run from `1` to `min(6, floor(retained_items / 3))`
- A candidate solution is considered structurally clean only if:
  - no Heywood problem appears
  - every factor has at least `3` clean items
  - a clean item has `|primary loading| >= 0.40`
  - cross-loading is flagged when `secondary |loading| >= 0.30` and `loading gap < 0.15`
- `recommend_k()` prefers the parallel-analysis suggestion if it is structurally clean; otherwise it chooses the nearest simpler clean solution below it, then the nearest clean solution above it, then the smallest clean solution if parallel analysis is unavailable
- Sensitivity stability is checked with:
  - Tucker congruence cutoff `>= 0.85`
  - shared core-item proportion cutoff `>= 0.50`

Locked values in the current repo:

- `IMI = 3`
- `WritingEfficacy = 3`
- `AIReflection = 2`
- `BeliefsAboutAI = NA` (not locked because the instrument is not suitable for factor extraction)

Why this approach:

- This script is the measurement backbone of the repo.
- The KMO gate prevents forcing a weak latent model.
- Structural-cleanliness rules make the factor map presentation-ready and keep downstream composites interpretable.
- The primary vs sensitivity comparison checks whether salvage cases change the underlying structure.

Outputs:

- Report files: `03_efa_analysis/03_efa_analysis.html`, `03_efa_analysis/03_efa_analysis_files/`
- Final locked outputs: `03_efa_analysis/EFA_Recommended_K.csv`, `03_efa_analysis/EFA_Final_Item_Map.csv`
- Diagnostics files: `03_efa_analysis/efa_diagnostics/EFA_Diagnostics_Summary.csv`, `03_efa_analysis/efa_diagnostics/EFA_Candidate_Solutions.csv`, `03_efa_analysis/efa_diagnostics/EFA_Final_Loadings.csv`, `03_efa_analysis/efa_diagnostics/EFA_Sensitivity_Comparison.csv`, `03_efa_analysis/efa_diagnostics/EFA_Analysis_Manifest.csv`
- Audit file: `03_efa_analysis/audit/Beliefs_Variance_Ranked.csv`

### `04_order_effects.qmd`

Main job:

- Build analysis-ready participant records with order and topic labels.
- Convert locked item maps into unit-weighted composites.
- Test whether order or topic threatens the crossover interpretation.

Math / logic used:

- `traditional_topic` and `ai_topic` are derived from the tracking sheet
- `first_topic` is the session-1 article type and enters the topic-controlled ANOVA as a between-subject covariate
- Composite score formula: `rowMeans(locked_item_columns, na.rm = FALSE)`
- Composite-level order tests use Mann-Whitney / Wilcoxon rank-sum
- Rank-biserial effect size from U:
  - `r_rb = (2 * U / (n1 * n2)) - 1`
- Item-level order tests use the same Wilcoxon logic per item
- Composite-level multiple testing:
  - one BH family across all composites
  - one Bonferroni family across all composites
- Item-level multiple testing:
  - BH within each instrument
  - Bonferroni globally across all items
- Mixed ANOVA formulas:
  - primary: `score ~ Tool * Order + Error(participant_id / Tool)`
  - topic-controlled: `score ~ Tool * Order + first_topic + Error(participant_id / Tool)`
- Order-stratified correlations use Spearman rho and compare subgroup correlations with Fisher z via `psych::r.test()`

Why this approach:

- This is the main check that counterbalancing worked.
- Unit-weighted means keep the composites on familiar response metrics.
- Nonparametric order comparisons are safer for small groups and ordinal-style composite distributions.
- The paired ANOVA directly tests whether the AI vs Traditional difference depends on starting order.

Outputs:

- Report files: `04_order_effects/04_order_effects.html`, `04_order_effects/04_order_effects_files/`
- Core CSV files: `04_order_effects/csv/Participant_Topic_Summary.csv`, `04_order_effects/csv/Composite_Item_Membership.csv`, `04_order_effects/csv/Composite_Specs.csv`, `04_order_effects/csv/Composite_Score_Summary.csv`, `04_order_effects/csv/Composite_Long.csv`, `04_order_effects/csv/Order_Descriptives_By_Composite.csv`, `04_order_effects/csv/Mann_Whitney_Order_Comparisons.csv`, `04_order_effects/csv/Item_Level_Order_Comparisons.csv`, `04_order_effects/csv/Tool_Comparable_Pair_Specs.csv`, `04_order_effects/csv/Mixed_ANOVA_Tool_Order_Results.csv`, `04_order_effects/csv/Tool_Order_Interaction_Summary.csv`, `04_order_effects/csv/Order_Effects_Analysis_Ready.csv`, `04_order_effects/csv/Order_Effects_Export_Manifest.csv`, `04_order_effects/csv/Factor_Factor_Order_Stratified_Correlations.csv`, `04_order_effects/csv/Beliefs_Factor_Order_Stratified_Correlations.csv`, `04_order_effects/csv/Order_Stratified_Export_Manifest.csv`
- Plot files in `04_order_effects/plots/`: `AIReflection_F1_order_violin_box.png/.pdf`, `AIReflection_F2_order_violin_box.png/.pdf`, `IMI_F1_order_violin_box.png/.pdf`, `IMI_F2_order_violin_box.png/.pdf`, `IMI_F3_order_violin_box.png/.pdf`, `WritingEfficacy_F1_order_violin_box.png/.pdf`, `WritingEfficacy_F2_order_violin_box.png/.pdf`, `WritingEfficacy_F3_order_violin_box.png/.pdf`

### `05_beliefs_item_analysis.qmd`

Main job:

- Build a factor map across the three factorable instruments.
- Treat `BeliefsAboutAI` as item-level because the block is not factorable.
- Correlate each Beliefs item with every valid factor score.

Math / logic used:

- Factor scores are built from the current primary EFA solutions with `method = "tenBerge"`
- WritingEfficacy is rescaled to `1:5` for factor modeling only
- Factor-factor associations use Spearman correlations
- Beliefs-item to factor associations also use Spearman correlations
- Both BH and Bonferroni corrections are reported

Why this approach:

- `BeliefsAboutAI` had to be rescued analytically without pretending it has a stable latent structure.
- A factor map across IMI, WritingEfficacy, and AIReflection helps show whether the validated factors are coherent before using them in the item-level fallback.

Outputs:

- Report files: `05_beliefs_item_analysis/05_beliefs_item_analysis.html`, `05_beliefs_item_analysis/05_beliefs_item_analysis_files/`
- CSV files: `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Scores.csv`, `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Model_Summary.csv`, `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Correlations.csv`, `05_beliefs_item_analysis/csv/BeliefsAboutAI_Wide.csv`, `05_beliefs_item_analysis/csv/Beliefs_Item_vs_Other_Instrument_Factors_Correlations.csv`, `05_beliefs_item_analysis/csv/Beliefs_Export_Manifest.csv`
- Plot files: `05_beliefs_item_analysis/plots/Other_Instrument_Factor_Correlation_Heatmap.png`, `05_beliefs_item_analysis/plots/Other_Instrument_Factor_Correlation_Heatmap.pdf`, `05_beliefs_item_analysis/plots/Beliefs_Items_vs_Other_Instrument_Factors_Heatmap.png`, `05_beliefs_item_analysis/plots/Beliefs_Items_vs_Other_Instrument_Factors_Heatmap.pdf`

### `06_interesting_findings.qmd`

Main job:

- Build an exploratory cross-instrument correlation finder.
- Combine factorable instruments and item-only Beliefs into one broad search space.
- Surface the strongest factor-factor and item-item links.

Math / logic used:

- Factorable instruments (`IMI`, `WritingEfficacy`, `AIReflection`) get tenBerge factor scores from primary EFA datasets
- `BeliefsAboutAI` remains item-only
- Factor heatmap uses Spearman correlations among factor scores
- Pairwise item correlations are run across every instrument pair
- Pair-local BH and Bonferroni corrections are applied within each instrument-pair comparison set
- The combined ranked table sorts by `abs(rho)` because pair-local adjusted p-values are not directly comparable across pairs with different test counts
- Order-stratified item-item correlations are run only for full-sample Bonferroni survivors, then compared with Fisher z

Why this approach:

- This script is the broadest signal-finder in the repo.
- Restricting stratified follow-up to already-strong full-sample item pairs keeps the moderation pass focused and avoids a combinatorial explosion.

Outputs:

- Report files: `06_interesting_findings/06_interesting_findings.html`, `06_interesting_findings/06_interesting_findings_files/`
- Core CSV files: `06_interesting_findings/csv/Factor_Name_Map.csv`, `06_interesting_findings/csv/Factor_Scores_All_Instruments.csv`, `06_interesting_findings/csv/Factor_Correlations_Unique.csv`, `06_interesting_findings/csv/Factor_Correlations_Heatmap_Matrix.csv`, `06_interesting_findings/csv/Pairwise_Item_Correlation_Summary.csv`, `06_interesting_findings/csv/Pairwise_Item_Correlation_Top_Hits.csv`, `06_interesting_findings/csv/All_Pairwise_Correlations_Ranked.csv`, `06_interesting_findings/csv/Interesting_Findings_Export_Manifest.csv`, `06_interesting_findings/csv/Item_Item_Order_Stratified_Correlations.csv`, `06_interesting_findings/csv/Item_Item_Order_Stratified_Manifest.csv`
- Pairwise item-correlation CSVs: `06_interesting_findings/csv/AIReflection_vs_BeliefsAboutAI_Item_Correlations.csv`, `06_interesting_findings/csv/IMI_vs_AIReflection_Item_Correlations.csv`, `06_interesting_findings/csv/IMI_vs_BeliefsAboutAI_Item_Correlations.csv`, `06_interesting_findings/csv/IMI_vs_WritingEfficacy_Item_Correlations.csv`, `06_interesting_findings/csv/WritingEfficacy_vs_AIReflection_Item_Correlations.csv`, `06_interesting_findings/csv/WritingEfficacy_vs_BeliefsAboutAI_Item_Correlations.csv`
- Plot files: `06_interesting_findings/plots/Factor_Heatmap_Across_3_Instruments.png`, `06_interesting_findings/plots/Factor_Heatmap_Across_3_Instruments.pdf`, `06_interesting_findings/plots/AIReflection_vs_BeliefsAboutAI_Item_Correlation_Heatmap.png`, `06_interesting_findings/plots/IMI_vs_AIReflection_Item_Correlation_Heatmap.png`, `06_interesting_findings/plots/IMI_vs_BeliefsAboutAI_Item_Correlation_Heatmap.png`, `06_interesting_findings/plots/IMI_vs_WritingEfficacy_Item_Correlation_Heatmap.png`, `06_interesting_findings/plots/WritingEfficacy_vs_AIReflection_Item_Correlation_Heatmap.png`, `06_interesting_findings/plots/WritingEfficacy_vs_BeliefsAboutAI_Item_Correlation_Heatmap.png`

### `07_q17_ai_use.qmd`

Main job:

- Score ART.
- Resolve Q17 duplicate submissions.
- Build participant-level AI-use indices.
- Test how broader or tool-specific AI use relates to ART reading-breadth metrics.

Math / logic used:

- Q17 use score mapping:
  - `1 = never heard`
  - `2 = heard, never used`
  - `3 = rarely`
  - `4 = sometimes`
  - `5 = often`
- Regular use is defined as `use_score >= 4`
- ART scoring:
  - `art_real_hits`
  - `art_fake_false_alarms`
  - `art_net_real_minus_fake = hits - false_alarms`
  - `art_hit_rate = hits / number_of_real_authors`
  - `art_false_alarm_rate = false_alarms / number_of_fake_authors`
  - `art_adjusted_rate = hit_rate - false_alarm_rate`
- Overall AI-use predictors vs ART outcomes:
  - Spearman correlations
  - OLS regressions
- Tool-specific regular-use analyses:
  - Spearman association between ordinal use score and ART
  - Wilcoxon comparison between regular users and everyone else
- Both BH and Bonferroni corrections are reported on the exploratory tables

Why this approach:

- ART is used here as a proxy for reading breadth / print exposure.
- Q17 provides a plausible external habit measure for whether people who already use more AI tools look different on that reading proxy.
- The script stays exploratory and explicitly avoids calling this a direct learning outcome.

Outputs:

- Report files: `07_q17_ai_use/07_q17_ai_use.html`, `07_q17_ai_use/07_q17_ai_use_files/`
- CSV files: `07_q17_ai_use/csv/ART_Scored.csv`, `07_q17_ai_use/csv/ART_Unmatched_Names.csv`, `07_q17_ai_use/csv/Q17_Submission_Resolution.csv`, `07_q17_ai_use/csv/Q17_Tool_Popularity.csv`, `07_q17_ai_use/csv/Q17_Participant_AI_Use_Index.csv`, `07_q17_ai_use/csv/Q17_AI_Use_vs_ART_Merged.csv`, `07_q17_ai_use/csv/Q17_AI_Use_vs_ART_Summary.csv`, `07_q17_ai_use/csv/Q17_AI_Use_vs_ART_Correlations.csv`, `07_q17_ai_use/csv/Q17_AI_Use_vs_ART_Regressions.csv`, `07_q17_ai_use/csv/Q17_Tool_RegularUse_vs_ART.csv`, `07_q17_ai_use/csv/Q17_Tool_RegularUse_vs_AdjustedART.csv`, `07_q17_ai_use/csv/Q17_Export_Manifest.csv`

### `08_ai_beliefs_items.qmd`

Main job:

- Run item-level order comparisons for the `BeliefsAboutAI` block.
- Group items into substantive themes.
- Produce descriptive Likert plots and per-item Mann-Whitney tests.

Math / logic used:

- All `22` current `Beliefs_` columns are treated as inferential because the earlier screening item was excluded upstream
- Long-format item matrix is built from `Final_Master_Wide.csv`
- Descriptive summaries: `n`, mean, SD, median, IQR by order group
- Diverging stacked bar chart uses the 1-5 Likert response distribution by theme
- Per-item Mann-Whitney / Wilcoxon tests compare `Traditional_First` vs `AI_First`
- Rank-biserial from W:
  - `U = W - n1(n1 + 1)/2`
  - `r_rb = (2U / (n1 * n2)) - 1`
- All 22 inferential items are treated as one correction family:
  - BH across items
  - Bonferroni across items
- Effect-size labels:
  - `|r_rb| >= 0.5` large
  - `|r_rb| >= 0.3` medium
  - `|r_rb| >= 0.1` small

Why this approach:

- The block failed the factorability test, so the repo intentionally avoids inventing a bad composite.
- Theme grouping plus item-level tests gives a defensible fallback that still surfaces where order-group differences do or do not exist.

Outputs:

- Report files: `08_ai_beliefs_items/08_ai_beliefs_items.html`, `08_ai_beliefs_items/08_ai_beliefs_items_files/`
- CSV files: `08_ai_beliefs_items/csv/AIBeliefs_Item_Metadata.csv`, `08_ai_beliefs_items/csv/AIBeliefs_Long.csv`, `08_ai_beliefs_items/csv/AIBeliefs_Item_Descriptives.csv`, `08_ai_beliefs_items/csv/AIBeliefs_MannWhitney_Results.csv`, `08_ai_beliefs_items/csv/AIBeliefs_Effect_Size_Summary.csv`, `08_ai_beliefs_items/csv/AIBeliefs_Consolidated_Summary.csv`, `08_ai_beliefs_items/csv/AIBeliefs_Export_Manifest.csv`
- Plot file: `08_ai_beliefs_items/plots/AIBeliefs_Diverging_Bar_All_Themes.pdf`

### `09_art_vs_all_factors_items.qmd`

Main job:

- Use ART as the anchor variable across the rest of the survey.
- Correlate ART metrics with factor scores from the factorable instruments.
- Correlate ART metrics with every cleaned item statement across all instruments.

Math / logic used:

- ART scoring is the same as in Script `07`
- Factor scores are rebuilt from the primary EFA instrument files using tenBerge
- Factor labels used in output:
  - IMI: `Effort/Importance`, `Perceived Competence`, `Interest/Enjoyment`
  - WritingEfficacy: `Writing Confidence`, `Process & Strategy`, `Writing Self-Regulation`
  - AIReflection: `Perceived Learning Utility`, `Voice, Ownership, and Comfort`
- Spearman correlations are run between each ART metric and:
  - every factor score
  - every item statement
- Both BH and Bonferroni corrections are reported

Why this approach:

- ART is the cleanest external anchor currently available in the active numbered pipeline.
- This script is one of the strongest places to look for interpretable, presentation-ready findings because it connects reading breadth to both factor-level and item-level outcomes.

Outputs:

- Report files: `09_art_vs_all_factors_items/09_art_vs_all_factors_items.html`, `09_art_vs_all_factors_items/09_art_vs_all_factors_items_files/`
- CSV files: `09_art_vs_all_factors_items/csv/ART_Scored.csv`, `09_art_vs_all_factors_items/csv/ART_Unmatched_Names.csv`, `09_art_vs_all_factors_items/csv/Other_Instrument_Factor_Scores.csv`, `09_art_vs_all_factors_items/csv/Factor_Lookup.csv`, `09_art_vs_all_factors_items/csv/ART_Factor_Overlap_Summary.csv`, `09_art_vs_all_factors_items/csv/ART_Factor_Merged.csv`, `09_art_vs_all_factors_items/csv/ART_vs_Factors_Correlations.csv`, `09_art_vs_all_factors_items/csv/ART_Net_vs_Factors_Ranked.csv`, `09_art_vs_all_factors_items/csv/All_Item_Lookup.csv`, `09_art_vs_all_factors_items/csv/All_Items_Wide.csv`, `09_art_vs_all_factors_items/csv/ART_Item_Merged.csv`, `09_art_vs_all_factors_items/csv/ART_vs_All_Items_Correlations.csv`, `09_art_vs_all_factors_items/csv/ART_Net_vs_All_Items_Ranked.csv`, `09_art_vs_all_factors_items/csv/ART_Top_Item_Signals_By_Metric.csv`, `09_art_vs_all_factors_items/csv/ART_Analysis_Manifest.csv`
- Plot files: `09_art_vs_all_factors_items/plots/ART_vs_Factors_Heatmap.png`, `09_art_vs_all_factors_items/plots/ART_vs_Factors_Heatmap.pdf`, `09_art_vs_all_factors_items/plots/ART_Net_vs_All_Items_Top30.png`, `09_art_vs_all_factors_items/plots/ART_Net_vs_All_Items_Top30.pdf`

### `10_participant_profiles.qmd`

Main job:

- Build participant profiles from validated factor scores only.
- Describe those profiles using ART, Q17, order, and Beliefs theme overlays.

Math / logic used:

- Clustering inputs are only the validated factor-score columns from `IMI`, `WritingEfficacy`, and `AIReflection`
- Beliefs themes are participant-level means of the grouped Beliefs items and are descriptive overlays only
- Factor score matrix is standardized with `scale()`
- Distances: Euclidean distance on standardized factor scores
- Clustering: Ward hierarchical clustering with `method = "ward.D2"`
- Candidate `k`: `2:5`
- Selection rule:
  - prefer solutions with minimum cluster size `>= 8`
  - among those, choose the highest average silhouette
  - if none meet the size floor, choose the overall highest silhouette
- Profiles are re-ordered by mean `PC1` and then assigned preferred labels
- Profile signature heatmap uses z-scored factor centroids across profiles

Why this approach:

- The script tries to detect interpretable participant subgroups without letting unstable Beliefs items define the clustering geometry.
- Ward clustering on standardized factor space is a pragmatic exploratory choice for a small sample.

Outputs:

- Report files: `10_participant_profiles/10_participant_profiles.html`, `10_participant_profiles/10_participant_profiles_files/`
- CSV files: `10_participant_profiles/csv/Cluster_Model_Selection.csv`, `10_participant_profiles/csv/Cluster_Sizes.csv`, `10_participant_profiles/csv/Profile_Signatures.csv`, `10_participant_profiles/csv/Profile_External_Summary.csv`, `10_participant_profiles/csv/Participant_Profile_Assignments.csv`, `10_participant_profiles/csv/Profile_Factor_Centroids_Raw.csv`, `10_participant_profiles/csv/Profile_Factor_Centroids_Z.csv`, `10_participant_profiles/csv/Participant_Profiles_Manifest.csv`
- Plot files: `10_participant_profiles/plots/Participant_Profiles_PCA.png`, `10_participant_profiles/plots/Participant_Profiles_PCA.pdf`, `10_participant_profiles/plots/Participant_Profile_Factor_Heatmap.png`, `10_participant_profiles/plots/Participant_Profile_Factor_Heatmap.pdf`

### `11_profile_external_comparisons.qmd`

Main job:

- Test whether the participant profiles differ on variables that were **not** used to define the clusters.

Variable families:

- ART metrics
- Q17 AI-use indices
- Beliefs theme averages
- all 22 individual Beliefs items

Math / logic used:

- Family descriptives report `n`, mean, median, and SD by profile
- Omnibus tests use Kruskal-Wallis for every variable
- Omnibus effect size uses epsilon-squared:
  - `epsilon_sq = max((H - k + 1) / (n - k), 0)`
- BH correction is applied within each family
- Pairwise follow-up Wilcoxon tests are run only for variables whose omnibus test survives BH correction
- Pairwise BH correction is then applied across the three profile contrasts within each variable
- Heatmaps standardize profile medians within each variable using `scale_or_zero()`

Why this approach:

- These profiles are exploratory and need external validation.
- Kruskal-Wallis plus selective Wilcoxon follow-up is a sensible small-sample strategy for comparing clusters on ordinal and skewed variables.
- Keeping validation variables separate from clustering variables reduces circularity.

Outputs:

- Report files: `11_profile_external_comparisons/11_profile_external_comparisons.html`, `11_profile_external_comparisons/11_profile_external_comparisons_files/`
- Descriptive CSVs: `11_profile_external_comparisons/csv/ART_Profile_Descriptives.csv`, `11_profile_external_comparisons/csv/Q17_Profile_Descriptives.csv`, `11_profile_external_comparisons/csv/Beliefs_Theme_Profile_Descriptives.csv`, `11_profile_external_comparisons/csv/Beliefs_Item_Profile_Descriptives.csv`
- Omnibus CSVs: `11_profile_external_comparisons/csv/ART_Profile_Kruskal_Results.csv`, `11_profile_external_comparisons/csv/Q17_Profile_Kruskal_Results.csv`, `11_profile_external_comparisons/csv/Beliefs_Theme_Profile_Kruskal_Results.csv`, `11_profile_external_comparisons/csv/Beliefs_Item_Profile_Kruskal_Results.csv`, `11_profile_external_comparisons/csv/Profile_Comparison_Omnibus_Summary.csv`
- Pairwise follow-up CSVs: `11_profile_external_comparisons/csv/ART_Profile_Pairwise_Wilcoxon_Results.csv`, `11_profile_external_comparisons/csv/Q17_Profile_Pairwise_Wilcoxon_Results.csv`, `11_profile_external_comparisons/csv/Beliefs_Theme_Profile_Pairwise_Wilcoxon_Results.csv`, `11_profile_external_comparisons/csv/Beliefs_Item_Profile_Pairwise_Wilcoxon_Results.csv`, `11_profile_external_comparisons/csv/Profile_External_Comparison_Manifest.csv`
- Plot files: `11_profile_external_comparisons/plots/Profile_External_Medians_Heatmap.png`, `11_profile_external_comparisons/plots/Profile_External_Medians_Heatmap.pdf`, `11_profile_external_comparisons/plots/Profile_Beliefs_Items_Top12_Heatmap.png`, `11_profile_external_comparisons/plots/Profile_Beliefs_Items_Top12_Heatmap.pdf`

### `13_results.qmd`

Main job:

- Turn the strongest upstream outputs into a coherent figure-driven narrative.

Math / logic used:

- Figure 1 adds a Fisher-z 95% CI to the ART-factor Spearman results:
  - `z = atanh(rho)`
  - `SE = 1 / sqrt(n - 3)`
  - CI on z, then back-transform with `tanh()`
- Figures 2 and 3 are display plots using linear smooths / subgroup facets, not new inferential tests
- Figure 4 visualizes Bonferroni-surviving item pairs from Script `06`
- Figure 5 visualizes the strongest IMI x WritingEfficacy item links
- Figure 6 visualizes the top BH-surviving ART item correlates from Script `09`
- Figure 7 visualizes the null order-comparison results from Script `04`
- Figure 8 is a narrative summary panel built from already-estimated upstream effects

Why this approach:

- This file is the slide-deck bridge. It is not trying to re-estimate the full model stack; it is packaging the strongest outputs into a readable visual story.

Outputs:

- Report file: `13_results/13_results.html`

## Where To Look First For Meaningful Results

If the goal is to pull out the strongest findings fast, prioritize these files:

1. `04_order_effects/csv/Mixed_ANOVA_Tool_Order_Results.csv`
   - This tells you whether the crossover interpretation is defensible and whether `Tool x Order` interactions exist.
2. `04_order_effects/csv/Mann_Whitney_Order_Comparisons.csv`
   - This gives the cleanest "did order matter?" table at the composite level.
3. `09_art_vs_all_factors_items/csv/ART_Net_vs_Factors_Ranked.csv`
   - This is one of the best single tables for substantive interpretation because it anchors the factor scores to reading breadth.
4. `09_art_vs_all_factors_items/csv/ART_Net_vs_All_Items_Ranked.csv`
   - Useful when you want the exact item statements driving the factor-level story.
5. `06_interesting_findings/csv/All_Pairwise_Correlations_Ranked.csv`
   - Broad exploratory signal finder across all instrument pairs.
6. `10_participant_profiles/csv/Profile_Signatures.csv`
   - Fastest way to understand the profile solution.
7. `11_profile_external_comparisons/csv/Profile_Comparison_Omnibus_Summary.csv`
   - Fastest way to see whether the profiles differ on ART, Q17, themes, or individual beliefs items.
8. `13_results/13_results.html`
   - Best all-in-one figure report once the upstream scripts have been rendered.

## Recommended Slide Deck Logic

If you want the clearest slideshow from the current pipeline, use this order:

1. Study design and counterbalancing
   - Use the design summary from this README and the topic/order outputs from Script `04`
2. Data quality and sample definition
   - Pull from `01_audit_cleaning` and `02_efa_exports/audit/Participant_Count_Reconciliation.csv`
3. Measurement structure
   - Use `03_efa_analysis/EFA_Recommended_K.csv` and `03_efa_analysis/EFA_Final_Item_Map.csv`
4. Counterbalancing worked or did not work
   - Use `04_order_effects/csv/Mixed_ANOVA_Tool_Order_Results.csv`, `04_order_effects/csv/Mann_Whitney_Order_Comparisons.csv`, and Figure 7 in `13_results.html`
5. ART-centered substantive story
   - Use `09_art_vs_all_factors_items/csv/ART_Net_vs_Factors_Ranked.csv`, `09_art_vs_all_factors_items/csv/ART_Top_Item_Signals_By_Metric.csv`, and Figures 1, 2, 3, and 6 in `13_results.html`
6. Cross-instrument item story
   - Use `06_interesting_findings/csv/Pairwise_Item_Correlation_Top_Hits.csv` and Figure 4 in `13_results.html`
7. Participant heterogeneity
   - Use `10_participant_profiles/csv/Profile_Signatures.csv`, `10_participant_profiles/plots/Participant_Profile_Factor_Heatmap.png`, and `11_profile_external_comparisons/csv/Profile_Comparison_Omnibus_Summary.csv`
8. Final takeaway
   - Use Figure 8 in `13_results.html` as the conceptual summary

## Best Current Storylines To Test In The Slide Deck

Based on the current numbered pipeline, the strongest candidate narratives are:

- Counterbalancing integrity: the first thing the audience needs to trust is that order did not swamp the results. Script `04` is the gatekeeper here.
- Reading breadth as an anchor variable: ART is the most consistent external anchor in the active workflow. Scripts `07`, `09`, and `13` are the best places to mine this.
- AI utility is not uniformly perceived: the negative ART x AIReflection relationship is one of the most presentation-worthy results in the current figure report.
- BeliefsAboutAI is analytically important but structurally unstable: do not oversell it as a clean latent scale. Treat Scripts `05` and `08` as item-level or theme-level follow-up, not proof of a validated beliefs factor.
- Profile heterogeneity is useful for storytelling: Scripts `10` and `11` give you audience segmentation language when a single mean-difference story feels too thin.

## Practical Interpretation Notes

- `BeliefsAboutAI` is currently more trustworthy at the item or theme level than as a factor score.
- `Q17` is exploratory and habit-oriented. It is useful context, not the main outcome.
- The clean paired crossover sample is `N = 82`; whenever a table uses a bigger `N`, it is almost always an EFA structure file, not a main inferential comparison.
- The strongest "null" outputs are substantively useful. They support the claim that order and topic counterbalancing did their job.
- Because this repo currently does not analyze direct learning test scores in the numbered pipeline, avoid claiming that these scripts already prove learning or retention gains.

## Canonical Files To Hand Off With A Slide Deck

If you need one compact handoff bundle, prioritize:

- `README.md`
- `START_HERE.md`
- `03_efa_analysis/EFA_Recommended_K.csv`
- `03_efa_analysis/EFA_Final_Item_Map.csv`
- `04_order_effects/csv/Mixed_ANOVA_Tool_Order_Results.csv`
- `04_order_effects/csv/Mann_Whitney_Order_Comparisons.csv`
- `06_interesting_findings/csv/All_Pairwise_Correlations_Ranked.csv`
- `09_art_vs_all_factors_items/csv/ART_Net_vs_Factors_Ranked.csv`
- `09_art_vs_all_factors_items/csv/ART_Net_vs_All_Items_Ranked.csv`
- `10_participant_profiles/csv/Profile_Signatures.csv`
- `11_profile_external_comparisons/csv/Profile_Comparison_Omnibus_Summary.csv`
- `13_results/13_results.html`

