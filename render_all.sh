#!/bin/bash
# render_all.sh — run inside your repo root

set -euo pipefail

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/quarto-cache}"

SCRIPTS=(
  "01_audit_cleaning.qmd"
  "02_efa_exports.qmd"
  "03_efa_analysis.qmd"
  "04_beliefs_item_analysis.qmd"
  "05_interesting_findings.qmd"
  "06_order_effects.qmd"
  "07_art_vs_all_factors_items.qmd"
  "08_ai_beliefs_items.qmd"
  "09_q17_ai_use.qmd"
  "10_participant_profiles.qmd"
  "11_profile_external_comparisons.qmd"
  "12_continuous_factor_analysis.qmd"
  "13_model_use_vs_factors_items.qmd"
  "14_q17_deeper_dive.qmd"
  "15_q17_robustness.qmd"
  "16_exploratory_beliefs.qmd"
  "17_composite_scoring.qmd"
  "18_composite_correlations.qmd"
  "results.qmd"
)

for script in "${SCRIPTS[@]}"; do
  echo "=== Rendering $script ===" 
  quarto render "$script" || { echo "FAILED at $script"; exit 1; }
done

echo "=== All scripts rendered successfully ==="
