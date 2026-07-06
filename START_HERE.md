# Cowriters Survey Analysis Folder Guide

## Current Workflow

Start with:

- `01_audit_cleaning.qmd`
- `02_efa_exports.qmd`
- `03_efa_analysis.qmd`
- `04_beliefs_item_analysis.qmd`
- `05_interesting_findings.qmd`
- `06_order_effects.qmd`
- `07_art_vs_all_factors_items.qmd`
- `08_ai_beliefs_items.qmd`
- `09_q17_ai_use.qmd`
- `10_participant_profiles.qmd`
- `11_profile_external_comparisons.qmd`
- `12_continuous_factor_analysis.qmd`
- `13_model_use_vs_factors_items.qmd`
- `14_q17_deeper_dive.qmd`
- `15_q17_robustness.qmd`
- `16_exploratory_beliefs.qmd`
- `17_results.qmd`

These are the active Quarto files for the current audit, cleaning, triage, EFA export, EFA analysis, order-effects inference, interesting-findings exploratory plotting, the Q17 side analysis against Author Recognition, the ART-wide follow-up, participant profiling, the external profile-comparison pass, and the final results visualizer.

## Raw Inputs

Keep these in the top-level folder because the active QMDs read them from here:

- `rw-survey-long-040726.csv`
- `llm-survey-long-040726.csv`
- `Participant Tracking - IDs and Conditions Table.csv`
- `Scheduling Tracking - SS2.csv`
- `Scheduling Tracking - Stevenson.csv`

The scheduling files are sanitized for repo use and only support the lab
sensitivity section in `06_order_effects.qmd`.

## Current Outputs

Each numbered script now renders into a same-named top-level folder and keeps its downstream artifacts there.

Key locations:

- `01_audit_cleaning/` contains the rendered report plus `audit/` and `cleaned/` CSVs.
- `02_efa_exports/` contains the rendered report plus `efa/`, `efa_diagnostics/`, `audit/`, and `Final_Master_Wide.csv`.
- `03_efa_analysis/` contains the rendered report plus `efa_diagnostics/`, `audit/`, `EFA_Recommended_K.csv`, and `EFA_Final_Item_Map.csv`.
- `04_beliefs_item_analysis/` through `16_exploratory_beliefs/` each contain their rendered report plus script-specific `csv/` and `plots/` outputs.
- `17_results/` contains the final results report.

Important handoff files in the ordered pipeline:

- `01_audit_cleaning/audit/Triage_Rap_Sheet_Verified.csv`
- `02_efa_exports/Final_Master_Wide.csv`
- `03_efa_analysis/EFA_Recommended_K.csv`
- `03_efa_analysis/EFA_Final_Item_Map.csv`
- `09_q17_ai_use/csv/Q17_Participant_AI_Use_Index.csv`
- `07_art_vs_all_factors_items/csv/ART_Factor_Merged.csv`
- `10_participant_profiles/csv/Participant_Profile_Assignments.csv`

## Archived Files

Older drafts and legacy outputs were moved here:

- `archive/legacy_qmd/`
- `archive/legacy_reports/`

Presentation material is here:

- `presentations/`

## Quarto Note

Use the PowerShell wrapper to keep each rendered report and its support files inside the matching numbered folder:

- `.\render_numbered_qmds.ps1` renders the full ordered pipeline.
- `.\render_numbered_qmds.ps1 06_order_effects.qmd` renders a specific step into `06_order_effects/`.

If rendering inside this sandboxed environment, this cache setting has been reliable:

```bash
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 01_audit_cleaning.qmd --output-dir 01_audit_cleaning
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 02_efa_exports.qmd --output-dir 02_efa_exports
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 03_efa_analysis.qmd --output-dir 03_efa_analysis
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 04_beliefs_item_analysis.qmd --output-dir 04_beliefs_item_analysis
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 05_interesting_findings.qmd --output-dir 05_interesting_findings
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 06_order_effects.qmd --output-dir 06_order_effects
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 07_art_vs_all_factors_items.qmd --output-dir 07_art_vs_all_factors_items
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 08_ai_beliefs_items.qmd --output-dir 08_ai_beliefs_items
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 09_q17_ai_use.qmd --output-dir 09_q17_ai_use
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 10_participant_profiles.qmd --output-dir 10_participant_profiles
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 11_profile_external_comparisons.qmd --output-dir 11_profile_external_comparisons
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 12_continuous_factor_analysis.qmd --output-dir 12_continuous_factor_analysis
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 13_model_use_vs_factors_items.qmd --output-dir 13_model_use_vs_factors_items
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 14_q17_deeper_dive.qmd --output-dir 14_q17_deeper_dive
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 15_q17_robustness.qmd --output-dir 15_q17_robustness
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 16_exploratory_beliefs.qmd --output-dir 16_exploratory_beliefs
XDG_CACHE_HOME=/tmp/quarto-cache ~/.local/bin/quarto render 17_results.qmd --output-dir 17_results
```
