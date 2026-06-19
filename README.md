# Cowriters Survey Analysis

This repository contains the numbered analysis pipeline for the Cowriters crossover study. The code starts from long-format survey exports and a participant tracking sheet, cleans and audits participant records, prepares EFA-ready datasets, evaluates measurement structure, runs order-effect checks, explores ART and AI-use associations, creates participant profiles, and writes reusable tables and figures.

This README is written for a public audience. It explains what each script does, what it depends on, and where its outputs are written. It does not interpret the findings or recommend conclusions.

## Repository Inputs

Keep these source files at the repository root:

- `rw-survey-long-040726.csv`
- `llm-survey-long-040726.csv`
- `Participant Tracking - IDs and Conditions Table.csv`
- `authorkey.csv`

The main helper file is:

- `scoring_helpers.R`

Script `02_efa_exports.qmd` expects a manually reviewed triage file:

- preferred path: `01_audit_cleaning/audit/Triage_Rap_Sheet_Verified.csv`
- fallback path: `inputs/audit/Triage_Rap_Sheet_Verified.csv`

The intended workflow is:

1. Render `01_audit_cleaning.qmd`.
2. Review `01_audit_cleaning/audit/Triage_Rap_Sheet.csv`.
3. Save reviewed triage decisions as `Triage_Rap_Sheet_Verified.csv`.
4. Continue with script `02` onward.

## Study Structure Encoded In The Code

The active scripts assume a 2 x 2 crossover design:

- within-subject factor: `Tool`, comparing Traditional/Alone work with AI/LLM work
- between-subject factor: `Order`, comparing `Traditional_First` and `AI_First`
- counterbalanced topic factor, tracked through `Topic 1`, `Topic 2`, and `first_topic`
- strict paired analysis sample after duplicate resolution and manual triage

The code treats manual salvage differently by stage:

- strict paired crossover analyses use the paired clean sample
- EFA discovery can use approved instrument-specific salvage cases to preserve usable measurement data

## Instruments

| Instrument | Source condition | Role in pipeline | Main scoring note |
| --- | --- | --- | --- |
| `IMI` | RW/traditional session | EFA, composites, order checks, ART analyses, profiles | reverse-scored items `3, 4, 13, 15, 18` with `8 - x` |
| `WritingEfficacy` | RW/traditional session | EFA, composites, order checks, ART analyses, profiles | raw anchors are `0/25/50/75/100`; EFA uses `(x / 25) + 1` |
| `AuthorRecognition` / `ART` | RW survey | external reading-breadth anchor | hits, false alarms, net score, hit rate, false-alarm rate, adjusted rate |
| `AIReflection` | LLM/AI session | EFA, composites, order checks, ART analyses, profiles | no reverse scoring in current pipeline |
| `BeliefsAboutAI` | LLM/AI session | item-level fallback analyses; exploratory items `6-22` factor model in script `16` | original Qualtrics items `17-20` reverse-scored with `6 - x`; full 22-item battery is not factorable in the locked workflow |
| `Q17` AI tool use | LLM side survey | AI-tool familiarity/use analyses | ordered scale from `1 = never heard` to `5 = often use` |

## Render Order

The active numbered scripts are:

1. `01_audit_cleaning.qmd`
2. `02_efa_exports.qmd`
3. `03_efa_analysis.qmd`
4. `04_order_effects.qmd`
5. `05_beliefs_item_analysis.qmd`
6. `06_interesting_findings.qmd`
7. `07_art_vs_all_factors_items.qmd`
8. `08_ai_beliefs_items.qmd`
9. `09_q17_ai_use.qmd`
10. `10_participant_profiles.qmd`
11. `11_profile_external_comparisons.qmd`
12. `12_model_use_vs_factors_items.qmd`
13. `13_results.qmd`
14. `14_q17_deeper_dive.qmd`
15. `15_q17_robustness.qmd`
16. `16_exploratory_beliefs.qmd`

There is also one companion script:

- `11b_continuous_factor_analysis.qmd`, which writes into `11_profile_external_comparisons/` and should be treated as an optional extension to script `11`.

## Output Conventions

Each numbered script writes to a same-named folder, such as `07_art_vs_all_factors_items/`.

Common subfolders:

- `csv/`: analysis tables and manifests
- `plots/`: PNG/PDF figures
- `audit/`: audit and reconciliation files
- `cleaned/`: cleaned instrument exports
- `efa/`: EFA input files
- `efa_diagnostics/`: measurement diagnostics

Quarto support folders such as `07_art_vs_all_factors_items_files/` contain render assets and are not the main analytical outputs.

## Script Reference

### `01_audit_cleaning.qmd`

Purpose:

- Reads the raw RW and LLM long-format survey exports.
- Audits source files, instruments, participant IDs, duplicate submissions, and expected item counts.
- Resolves duplicate or incomplete submissions.
- Builds cleaned long-format instrument files for downstream scripts.
- Defines the strict clean paired sample.

Key methods:

- derives `order` from `condition_1` and `condition_2`
- reverse-scores IMI and Beliefs items using rules in `scoring_helpers.R`
- ranks duplicate submissions by target-block quality, completeness, and straight-lining diagnostics
- preserves manual triage handoff files so questionable cases can be reviewed before EFA export

Output folder:

- `01_audit_cleaning/`

Important outputs:

- `01_audit_cleaning/audit/Triage_Rap_Sheet.csv`
- `01_audit_cleaning/audit/Submission_Resolution_Audit.csv`
- `01_audit_cleaning/audit/Participant_Triage.csv`
- `01_audit_cleaning/audit/InstrumentAudit.csv`
- `01_audit_cleaning/cleaned/IMI_cleaned.csv`
- `01_audit_cleaning/cleaned/WritingEfficacy_cleaned.csv`
- `01_audit_cleaning/cleaned/AuthorRecognition_cleaned.csv`
- `01_audit_cleaning/cleaned/AI_Reflection_cleaned.csv`
- `01_audit_cleaning/cleaned/BeliefsAboutAI_cleaned.csv`
- `01_audit_cleaning/output_manifest.csv`

### `02_efa_exports.qmd`

Purpose:

- Converts cleaned long-format instrument files into EFA-ready exports.
- Builds primary EFA samples and strict sensitivity samples.
- Creates the strict paired wide master dataset used by later crossover analyses.

Key methods:

- primary EFA samples include approved salvage cases
- sensitivity EFA samples use the strict paired sample
- `Final_Master_Wide.csv` joins cleaned instruments at participant level
- manual triage is applied through `Triage_Rap_Sheet_Verified.csv`

Output folder:

- `02_efa_exports/`

Important outputs:

- `02_efa_exports/Final_Master_Wide.csv`
- `02_efa_exports/efa/IMI_EFA_Primary.csv`
- `02_efa_exports/efa/WritingEfficacy_EFA_Primary.csv`
- `02_efa_exports/efa/AI_Reflection_EFA_Primary.csv`
- `02_efa_exports/efa/BeliefsAboutAI_EFA_Primary.csv`
- `02_efa_exports/efa/IMI_EFA_Sensitivity.csv`
- `02_efa_exports/efa/WritingEfficacy_EFA_Sensitivity.csv`
- `02_efa_exports/efa/AI_Reflection_EFA_Sensitivity.csv`
- `02_efa_exports/efa/BeliefsAboutAI_EFA_Sensitivity.csv`
- `02_efa_exports/efa_diagnostics/EFA_Export_Summary.csv`
- `02_efa_exports/audit/Participant_Count_Reconciliation.csv`
- `02_efa_exports/audit/EFA_Exports_Manifest.csv`

### `03_efa_analysis.qmd`

Purpose:

- Evaluates whether each survey instrument is suitable for factor analysis.
- Fits candidate EFA solutions.
- Recommends and locks factor counts.
- Exports final item-to-factor mappings used downstream.

Key methods:

- uses polychoric correlations
- uses KMO as a factorability gate
- fits `psych::fa(..., fm = "minres")`
- uses oblimin rotation when `k > 1`
- tests candidate factor counts and structural cleanliness
- compares primary and sensitivity solutions

Current locked measurement status:

- `IMI`: factorable
- `WritingEfficacy`: factorable
- `AIReflection`: factorable
- `BeliefsAboutAI`: not factorable in this workflow; analyzed item-by-item later

Output folder:

- `03_efa_analysis/`

Important outputs:

- `03_efa_analysis/EFA_Recommended_K.csv`
- `03_efa_analysis/EFA_Final_Item_Map.csv`
- `03_efa_analysis/efa_diagnostics/EFA_Diagnostics_Summary.csv`
- `03_efa_analysis/efa_diagnostics/EFA_Candidate_Solutions.csv`
- `03_efa_analysis/efa_diagnostics/EFA_Final_Loadings.csv`
- `03_efa_analysis/efa_diagnostics/EFA_Sensitivity_Comparison.csv`
- `03_efa_analysis/efa_diagnostics/EFA_Analysis_Manifest.csv`
- `03_efa_analysis/audit/Beliefs_Variance_Ranked.csv`

### `04_order_effects.qmd`

Purpose:

- Tests whether task order or topic order affects the main survey composites.
- Builds analysis-ready participant records with order, topic, and composite scores.
- Produces item-level and composite-level order comparisons.

Key methods:

- creates unit-weighted composite means from `EFA_Final_Item_Map.csv`
- uses Wilcoxon rank-sum tests for order-group comparisons
- reports rank-biserial effect sizes
- runs mixed ANOVA models for tool-by-order checks
- applies BH and Bonferroni corrections
- exports order-stratified correlations for follow-up checks

Output folder:

- `04_order_effects/`

Important outputs:

- `04_order_effects/csv/Order_Effects_Analysis_Ready.csv`
- `04_order_effects/csv/Composite_Item_Membership.csv`
- `04_order_effects/csv/Composite_Specs.csv`
- `04_order_effects/csv/Composite_Score_Summary.csv`
- `04_order_effects/csv/Mann_Whitney_Order_Comparisons.csv`
- `04_order_effects/csv/Item_Level_Order_Comparisons.csv`
- `04_order_effects/csv/Mixed_ANOVA_Tool_Order_Results.csv`
- `04_order_effects/csv/Tool_Order_Interaction_Summary.csv`
- `04_order_effects/csv/Factor_Factor_Order_Stratified_Correlations.csv`
- `04_order_effects/csv/Beliefs_Factor_Order_Stratified_Correlations.csv`
- `04_order_effects/plots/`

### `05_beliefs_item_analysis.qmd`

Purpose:

- Keeps `BeliefsAboutAI` in an item-level analysis path because it did not support a clean factor solution.
- Scores the factorable instruments.
- Correlates Beliefs items with factor scores from IMI, WritingEfficacy, and AIReflection.

Key methods:

- computes tenBerge factor scores for factorable instruments
- keeps Beliefs items separate rather than forcing a composite
- uses Spearman correlations
- reports BH and Bonferroni correction columns

Output folder:

- `05_beliefs_item_analysis/`

Important outputs:

- `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Scores.csv`
- `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Model_Summary.csv`
- `05_beliefs_item_analysis/csv/Other_Instrument_Factor_Correlations.csv`
- `05_beliefs_item_analysis/csv/BeliefsAboutAI_Wide.csv`
- `05_beliefs_item_analysis/csv/Beliefs_Item_vs_Other_Instrument_Factors_Correlations.csv`
- `05_beliefs_item_analysis/csv/Beliefs_Export_Manifest.csv`
- `05_beliefs_item_analysis/plots/Other_Instrument_Factor_Correlation_Heatmap.png`
- `05_beliefs_item_analysis/plots/Beliefs_Items_vs_Other_Instrument_Factors_Heatmap.png`

### `06_interesting_findings.qmd`

Purpose:

- Runs broad exploratory cross-instrument correlation searches.
- Combines factor-level and item-level outputs to find associations across instruments.
- Exports ranked correlation tables and heatmaps.

Key methods:

- uses tenBerge factor scores for factorable instruments
- keeps `BeliefsAboutAI` item-level
- uses Spearman correlations across factor pairs and item pairs
- applies pair-local BH and Bonferroni corrections
- runs order-stratified follow-up checks for selected item pairs

Output folder:

- `06_interesting_findings/`

Important outputs:

- `06_interesting_findings/csv/Factor_Name_Map.csv`
- `06_interesting_findings/csv/Factor_Scores_All_Instruments.csv`
- `06_interesting_findings/csv/Factor_Correlations_Unique.csv`
- `06_interesting_findings/csv/Factor_Correlations_Heatmap_Matrix.csv`
- `06_interesting_findings/csv/Pairwise_Item_Correlation_Summary.csv`
- `06_interesting_findings/csv/Pairwise_Item_Correlation_Top_Hits.csv`
- `06_interesting_findings/csv/All_Pairwise_Correlations_Ranked.csv`
- `06_interesting_findings/csv/Item_Item_Order_Stratified_Correlations.csv`
- `06_interesting_findings/csv/Interesting_Findings_Export_Manifest.csv`
- `06_interesting_findings/plots/`

### `07_art_vs_all_factors_items.qmd`

Purpose:

- Scores ART and uses it as an external reading-breadth anchor.
- Correlates ART metrics with factor scores.
- Correlates ART metrics with item-level responses across instruments.

Key methods:

- matches ART selections against `authorkey.csv`
- computes ART hit, false-alarm, net, and adjusted-rate metrics
- computes factor scores for factorable instruments
- builds all-item wide tables across IMI, WritingEfficacy, AIReflection, and Beliefs
- uses Spearman correlations with BH and Bonferroni corrections

Output folder:

- `07_art_vs_all_factors_items/`

Important outputs:

- `07_art_vs_all_factors_items/csv/ART_Scored.csv`
- `07_art_vs_all_factors_items/csv/ART_Unmatched_Names.csv`
- `07_art_vs_all_factors_items/csv/Other_Instrument_Factor_Scores.csv`
- `07_art_vs_all_factors_items/csv/Factor_Lookup.csv`
- `07_art_vs_all_factors_items/csv/ART_Factor_Merged.csv`
- `07_art_vs_all_factors_items/csv/ART_vs_Factors_Correlations.csv`
- `07_art_vs_all_factors_items/csv/ART_Net_vs_Factors_Ranked.csv`
- `07_art_vs_all_factors_items/csv/All_Item_Lookup.csv`
- `07_art_vs_all_factors_items/csv/All_Items_Wide.csv`
- `07_art_vs_all_factors_items/csv/ART_vs_All_Items_Correlations.csv`
- `07_art_vs_all_factors_items/csv/ART_Net_vs_All_Items_Ranked.csv`
- `07_art_vs_all_factors_items/csv/ART_Top_Item_Signals_By_Metric.csv`
- `07_art_vs_all_factors_items/csv/ART_Analysis_Manifest.csv`
- `07_art_vs_all_factors_items/plots/`

### `08_ai_beliefs_items.qmd`

Purpose:

- Runs item-level order-effect analysis for the `BeliefsAboutAI` block.
- Groups Beliefs items into themes.
- Produces item descriptives, inferential comparisons, and a Likert distribution plot.

Key methods:

- reads `02_efa_exports/Final_Master_Wide.csv`
- treats all 22 current Beliefs columns as inferential items
- compares `Traditional_First` and `AI_First` with Wilcoxon rank-sum tests
- reports rank-biserial effect sizes
- applies BH and Bonferroni corrections across Beliefs items

Output folder:

- `08_ai_beliefs_items/`

Important outputs:

- `08_ai_beliefs_items/csv/AIBeliefs_Item_Metadata.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_Long.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_Item_Descriptives.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_MannWhitney_Results.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_Effect_Size_Summary.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_Consolidated_Summary.csv`
- `08_ai_beliefs_items/csv/AIBeliefs_Export_Manifest.csv`
- `08_ai_beliefs_items/plots/AIBeliefs_Diverging_Bar_All_Themes.pdf`

### `09_q17_ai_use.qmd`

Purpose:

- Scores Q17 AI-tool familiarity/use.
- Resolves Q17 duplicate submissions.
- Builds participant-level AI-use indices.
- Tests how AI-tool use relates to ART and factor-score outputs from script `07`.

Key methods:

- maps Q17 responses to ordered use scores from `1` to `5`
- defines regular use as `use_score >= 4`
- exports long-format Q17 responses for scripts `12`, `14`, and `15`
- uses Spearman correlations and OLS summaries for AI-use vs ART checks
- adds Q17-vs-factor correlations using outputs from `07_art_vs_all_factors_items/`

Output folder:

- `09_q17_ai_use/`

Important outputs:

- `09_q17_ai_use/csv/Q17_Submission_Resolution.csv`
- `09_q17_ai_use/csv/Q17_Tool_Popularity.csv`
- `09_q17_ai_use/csv/Q17_Participant_AI_Use_Index.csv`
- `09_q17_ai_use/csv/Q17_Responses_Long.csv`
- `09_q17_ai_use/csv/Q17_AI_Use_vs_ART_Merged.csv`
- `09_q17_ai_use/csv/Q17_AI_Use_vs_ART_Correlations.csv`
- `09_q17_ai_use/csv/Q17_AI_Use_vs_ART_Regressions.csv`
- `09_q17_ai_use/csv/Q17_ART_Factor_Merged.csv`
- `09_q17_ai_use/csv/Q17_ART_vs_Factors_Correlations.csv`
- `09_q17_ai_use/csv/Q17_Tool_RegularUse_vs_ART.csv`
- `09_q17_ai_use/csv/Q17_Export_Manifest.csv`

### `10_participant_profiles.qmd`

Purpose:

- Builds exploratory participant profiles from validated factor scores.
- Describes the resulting profiles using ART, Q17, Beliefs themes, and order labels.

Key methods:

- uses only factor scores from IMI, WritingEfficacy, and AIReflection as clustering inputs
- standardizes factor scores before clustering
- computes Euclidean distances
- uses Ward hierarchical clustering with `method = "ward.D2"`
- evaluates candidate cluster counts from `2` to `5`
- uses Beliefs, ART, Q17, and order only as descriptive overlays

Output folder:

- `10_participant_profiles/`

Important outputs:

- `10_participant_profiles/csv/Cluster_Model_Selection.csv`
- `10_participant_profiles/csv/Cluster_Sizes.csv`
- `10_participant_profiles/csv/Profile_Signatures.csv`
- `10_participant_profiles/csv/Profile_External_Summary.csv`
- `10_participant_profiles/csv/Participant_Profile_Assignments.csv`
- `10_participant_profiles/csv/Profile_Factor_Centroids_Raw.csv`
- `10_participant_profiles/csv/Profile_Factor_Centroids_Z.csv`
- `10_participant_profiles/csv/Participant_Profiles_Manifest.csv`
- `10_participant_profiles/plots/Participant_Profiles_PCA.png`
- `10_participant_profiles/plots/Participant_Profile_Factor_Heatmap.png`

### `11_profile_external_comparisons.qmd`

Purpose:

- Tests whether participant profiles differ on variables that were not used to define the clusters.
- Compares profiles on ART, Q17, Beliefs themes, and individual Beliefs items.

Key methods:

- computes profile-level descriptives
- uses Kruskal-Wallis omnibus tests
- reports epsilon-squared effect sizes
- applies BH correction within variable families
- runs pairwise Wilcoxon follow-ups only for BH-surviving omnibus tests

Output folder:

- `11_profile_external_comparisons/`

Important outputs:

- `11_profile_external_comparisons/csv/ART_Profile_Descriptives.csv`
- `11_profile_external_comparisons/csv/Q17_Profile_Descriptives.csv`
- `11_profile_external_comparisons/csv/Beliefs_Theme_Profile_Descriptives.csv`
- `11_profile_external_comparisons/csv/Beliefs_Item_Profile_Descriptives.csv`
- `11_profile_external_comparisons/csv/ART_Profile_Kruskal_Results.csv`
- `11_profile_external_comparisons/csv/Q17_Profile_Kruskal_Results.csv`
- `11_profile_external_comparisons/csv/Beliefs_Theme_Profile_Kruskal_Results.csv`
- `11_profile_external_comparisons/csv/Beliefs_Item_Profile_Kruskal_Results.csv`
- `11_profile_external_comparisons/csv/Profile_Comparison_Omnibus_Summary.csv`
- `11_profile_external_comparisons/csv/Profile_External_Comparison_Manifest.csv`
- `11_profile_external_comparisons/plots/Profile_External_Medians_Heatmap.png`
- `11_profile_external_comparisons/plots/Profile_Beliefs_Items_Top12_Heatmap.png`

### `11b_continuous_factor_analysis.qmd`

Purpose:

- Provides a continuous-factor companion analysis to script `11`.
- Uses factor scores directly rather than relying only on discrete profile groups.
- Writes outputs into the script `11` output folder.

Key methods:

- runs Spearman correlations between factor scores and external variables
- runs multiple regression summaries for external predictors and factor scores
- optionally attempts latent profile analysis if `tidyLPA` is available
- shares output folders with `11_profile_external_comparisons.qmd`

Output folder:

- `11_profile_external_comparisons/`

Important outputs:

- additional CSV files in `11_profile_external_comparisons/csv/`
- additional plots in `11_profile_external_comparisons/plots/`

### `12_model_use_vs_factors_items.qmd`

Purpose:

- Examines whether use of specific AI tools is associated with factor scores or item-level responses.
- Focuses on ChatGPT, Claude, Gemini, and Copilot.

Key methods:

- reads long-format Q17 responses from `09_q17_ai_use/csv/Q17_Responses_Long.csv`
- runs per-model Spearman correlations between model use scores and factors/items
- classifies each participant by their primary model when possible
- runs Kruskal-Wallis tests across primary-model groups
- applies correction columns to exploratory correlation tables

Output folder:

- `12_model_use_vs_factors_items/`

Important outputs:

- `12_model_use_vs_factors_items/csv/Model_Use_Factor_Item_Merged.csv`
- `12_model_use_vs_factors_items/csv/Model_Use_vs_Factors_Correlations.csv`
- `12_model_use_vs_factors_items/csv/Model_Use_vs_Items_Correlations.csv`
- `12_model_use_vs_factors_items/csv/Model_Use_vs_Items_Top10_Per_Model.csv`
- `12_model_use_vs_factors_items/csv/PrimaryModel_KW_Factors.csv`
- `12_model_use_vs_factors_items/csv/Manifest.csv`
- `12_model_use_vs_factors_items/plots/Model_Use_vs_Factors_Heatmap.png`
- `12_model_use_vs_factors_items/plots/Model_Use_vs_Items_BH_Signal.png`
- `12_model_use_vs_factors_items/plots/PrimaryModel_Factor_Distributions.png`

### `13_results.qmd`

Purpose:

- Builds a compiled visual report from upstream outputs.
- Uses already-created CSV files and plots them in a consolidated Quarto document.
- Serves as the final human-facing synthesis pass when the full pipeline is being rendered.

Key methods:

- reads ranked ART, item-correlation, order-effect, and profile outputs
- uses Fisher-z intervals for selected correlation displays
- creates figures from existing upstream outputs rather than replacing the upstream analyses
- renders with embedded resources for a self-contained HTML report

Render note:

- Although it keeps the script number `13` for continuity, render it after scripts `14`, `15`, and `16` when building the full final report because it may consume those downstream exploratory/robustness outputs.

Output folder:

- `13_results/`

Important outputs:

- `13_results/13_results.html`

### `14_q17_deeper_dive.qmd`

Purpose:

- Re-expresses Q17 AI-tool familiarity/use as per-participant Likert bucket counts and proportions.
- Tests whether these bucket metrics correlate with factor scores and item-level responses.

Key methods:

- uses `09_q17_ai_use/csv/Q17_Responses_Long.csv`
- computes participant-level counts for each Q17 response bucket
- computes participant-level proportions for each Q17 response bucket
- correlates Q17 bucket metrics with factor scores and all-item tables from `07_art_vs_all_factors_items/`
- applies BH correction within each Q17 metric family
- creates heatmaps and ranked item/factor correlation tables

Output folder:

- `14_q17_deeper_dive/`

Important outputs:

- `14_q17_deeper_dive/csv/Q17_Likert_Buckets_PerParticipant.csv`
- `14_q17_deeper_dive/csv/Q17_Proportions_vs_Factors_Correlations.csv`
- `14_q17_deeper_dive/csv/Q17_Counts_vs_Factors_Correlations.csv`
- `14_q17_deeper_dive/csv/Q17_Proportions_vs_All_Items_Correlations.csv`
- `14_q17_deeper_dive/csv/Q17_Counts_vs_All_Items_Correlations.csv`
- `14_q17_deeper_dive/csv/Q17_AllBuckets_AllItems_RankedByStrength.csv`
- `14_q17_deeper_dive/csv/Q17_Proportions_Top_Item_Signals_By_Q17_Metric.csv`
- `14_q17_deeper_dive/csv/Manifest.csv`
- `14_q17_deeper_dive/plots/Q17_Proportions_vs_Factors_Heatmap.png`
- `14_q17_deeper_dive/plots/Q17_Counts_vs_Factors_Heatmap.png`
- `14_q17_deeper_dive/plots/Q17_AllBuckets_TopCorr_Unified_Ranked.png`
- `14_q17_deeper_dive/plots/`

### `15_q17_robustness.qmd`

Purpose:

- Runs robustness checks for the Q17 bucket correlations from script `14`.
- Tests whether selected Q17 associations depend on individual tools or alternative model specifications.

Key methods:

- recomputes Q17 bucket correlations under four variants:
  - all tools
  - excluding Grammarly
  - excluding ChatGPT
  - excluding both Grammarly and ChatGPT
- computes a breadth score based on the number of tools with `use_score >= 3`
- fits mixed models with tool and participant random effects where possible
- compares robustness variants against script `14` Bonferroni-surviving results

Output folder:

- `15_q17_robustness/`

Important outputs:

- `15_q17_robustness/csv/Robustness_Factor_Corrs_AllVariants.csv`
- `15_q17_robustness/csv/Robustness_Rho_Comparison_Factors.csv`
- `15_q17_robustness/csv/Breadth_Scores_PerParticipant.csv`
- `15_q17_robustness/csv/Breadth_vs_Factors_Correlations.csv`
- `15_q17_robustness/csv/MixedModel_Factor_Results.csv`
- `15_q17_robustness/csv/Master_Robustness_Summary.csv`
- `15_q17_robustness/csv/Manifest.csv`
- `15_q17_robustness/plots/Robustness_Rho_Shift_Factors.png`
- `15_q17_robustness/plots/Breadth_vs_Factors_DotPlot.png`
- `15_q17_robustness/plots/MixedModel_Factor_Coefficients.png`

### `16_exploratory_beliefs.qmd`

Purpose:

- Tests an exploratory `BeliefsAboutAI` factor-scoring path using items `6-22`.
- Treats items `1-5` as awareness/literacy items rather than belief items for this secondary model.
- Creates factor-level validity checks against the same families used elsewhere in the pipeline.

Key methods:

- reads `02_efa_exports/efa/BeliefsAboutAI_EFA_Primary.csv`
- fits a three-factor ordinal EFA with polychoric correlations, `minres` extraction, and `oblimin` rotation
- scores exploratory factors with tenBerge scores
- labels the factors as Utility & Comfort, Future AI Intent, and Concern & Harms
- correlates exploratory Beliefs factors with existing factor scores, ART metrics, Q17 participant-level use profiles, and named model use
- includes concern-focused follow-ups for aggregate Q17 use and individual Q17 tool frequency

Output folder:

- `16_exploratory_beliefs/`

Important outputs:

- `16_exploratory_beliefs/csv/Beliefs_Exploratory_Model_Summary.csv`
- `16_exploratory_beliefs/csv/Beliefs_Exploratory_Factor_Scores.csv`
- `16_exploratory_beliefs/csv/Beliefs_Exploratory_Loadings.csv`
- `16_exploratory_beliefs/csv/Beliefs_Exploratory_Cross_Factor_Correlations_Unique.csv`
- `16_exploratory_beliefs/csv/ART_vs_Beliefs_Exploratory_Factors.csv`
- `16_exploratory_beliefs/csv/Q17_Buckets_vs_Beliefs_Exploratory_Factors.csv`
- `16_exploratory_beliefs/csv/Q17_Aggregate_Metrics_vs_Beliefs_ConcernHarms.csv`
- `16_exploratory_beliefs/csv/Named_Model_Use_vs_Beliefs_Exploratory_Factors.csv`
- `16_exploratory_beliefs/plots/Beliefs_Exploratory_Loadings_Heatmap.png`
- `16_exploratory_beliefs/plots/ART_vs_Beliefs_Exploratory_Factors_Heatmap.png`
- `16_exploratory_beliefs/plots/Q17_vs_Beliefs_Exploratory_Factors_Heatmap.png`
- `16_exploratory_beliefs/plots/Q17_ChatGPT_Use_Bucket_vs_Beliefs_ConcernHarms.png`

## Legacy And Non-Active Files

The active public pipeline is the numbered sequence listed above. Legacy or preserved files are kept outside the active numbering, including:

- `legacy_q17_ai_use.qmd`
- `legacy_q17_ai_use/`
- `legacy_10_model_use_vs_factors_items/`

Those files are retained for provenance but are not part of the current ordered workflow.
