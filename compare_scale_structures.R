#!/usr/bin/env Rscript
# Compare the historical Script 18 scoring maps with the current funnel's
# EFA/CFA evidence and candidate item-mean scores. This produces item maps,
# not new inferential analyses.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(purrr)
})

OUT <- "18_composite_correlations/plots"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
inst_map <- c(
  IMI = "IMI", WritingEfficacy = "WSE",
  AIReflection = "AIRef", BeliefsAboutAI = "Beliefs"
)
inst_order <- c("IMI", "WSE", "AIRef", "Beliefs")
inst_labels <- c(IMI = "IMI", WSE = "Writing Self-Efficacy",
                 AIRef = "AI Reflection", Beliefs = "Beliefs about AI")

item_text <- read_csv("funnel_item_text.csv", show_col_types = FALSE) |>
  mutate(instrument = recode(instrument, !!!as.list(inst_map)), item = as.integer(item)) |>
  distinct(instrument, item, .keep_all = TRUE)

# Historical EFA: full old EFA loading matrices for IMI/WSE/AI Reflection,
# plus Script 16's separate three-factor beliefs EFA on items 6-22.
old_factor_names <- read_csv("05_interesting_findings/csv/Factor_Name_Map.csv",
                             show_col_types = FALSE) |>
  transmute(instrument = recode(instrument, !!!as.list(inst_map)),
            factor = short_factor, label = proposed_name)
old_general <- read_csv("03_efa_analysis/efa_diagnostics/EFA_Final_Loadings.csv",
                        show_col_types = FALSE) |>
  filter(efa_sample == "primary") |>
  transmute(instrument = recode(instrument, !!!as.list(inst_map)),
            item = as.integer(item_id), factor = as.character(factor_id),
            loading = as.numeric(loading), method = "Script 18: old EFA") |>
  left_join(old_factor_names, by = c("instrument", "factor")) |>
  mutate(label = coalesce(label, factor), group = paste0(factor, ": ", label))

old_belief_lookup <- read_csv("16_exploratory_beliefs/csv/Beliefs_Exploratory_Factor_Lookup.csv",
                              show_col_types = FALSE) |>
  transmute(factor = paste0("F", factor_num), label = proposed_name)
old_beliefs <- read_csv("16_exploratory_beliefs/csv/Beliefs_Exploratory_Loadings.csv",
                        show_col_types = FALSE) |>
  pivot_longer(starts_with("MR"), names_to = "mr", values_to = "loading") |>
  mutate(factor = paste0("F", str_remove(mr, "MR")), instrument = "Beliefs",
         item = as.integer(item_id), method = "Script 18: old EFA") |>
  left_join(old_belief_lookup, by = "factor") |>
  transmute(instrument, item, factor, loading, method, label,
            group = paste0(factor, ": ", label))
old_efa <- bind_rows(old_general, old_beliefs)

# Script 18 unit-weighted means were built from these item memberships.
old_comp <- read_csv("17_composite_scoring/csv/Composite_Item_Membership.csv",
                     show_col_types = FALSE) |>
  mutate(instrument = recode(instrument, !!!as.list(inst_map))) |>
  transmute(instrument, item = as.integer(item_id), group = as.character(display_label),
            label = as.character(display_label), method = "Script 18: mean composites",
            loading = NA_real_,
            direction = case_when(
              instrument == "Beliefs" & factor == "Beliefs_ConcernHarms" ~
                "High = more concern/harms; Script 18 flips these items as 6 - score",
              instrument == "IMI" ~ "Source direction; reverse-keyed items were reversed upstream",
              instrument == "WSE" ~ "High = greater writing efficacy; slider mapped to 1-5",
              instrument == "AIRef" ~ "High = stronger appraisal/endorsement",
              TRUE ~ "See Script 18 scoring code"
            ), scoring_rule = "Equal-weight arithmetic mean of listed items")

# Current EFA uses parallel-analysis k (item 1-20 for Beliefs; item 21-22
# remain a transparent observed intention mean). Keep the rotated factor labels
# neutral because EFA factor numbers can rotate/reorder across runs.
cur_efa_raw <- read_csv("funnel_out/02g_parallel_efa_loadings.csv", show_col_types = FALSE) |>
  pivot_longer(matches("^MR[0-9]+$"), names_to = "factor", values_to = "loading") |>
  filter(!is.na(loading)) |>
  transmute(instrument = as.character(instrument), item = as.integer(item),
            factor = str_remove(factor, "MR"), loading,
            method = "Current: parallel-analysis EFA") |>
  mutate(group = paste0("EFA F", factor))

# Current source-informed/transparent item-mean candidates, including the broad
# totals (explicitly labeled secondary) and local AI Reflection total.
cur_means <- read_csv("funnel_out/01_score_membership.csv", show_col_types = FALSE) |>
  transmute(instrument, item = as.integer(item),
            label = paste0(display_label,
              if_else(score_role == "broad total (secondary)", " (secondary total)", "")),
            group = label,
            method = "Current: candidate item means", loading = NA_real_,
            direction = direction, scoring_rule = source_rule)

# Current ordinal CFA memberships and standardized loadings. Beliefs intention
# remains a two-item observed mean; no latent two-indicator CFA was fit.
cur_cfa <- read_csv("funnel_out/02d_cfa_loadings.csv", show_col_types = FALSE) |>
  mutate(instrument = case_when(
    str_starts(model, "Beliefs") ~ "Beliefs",
    str_starts(model, "IMI") ~ "IMI",
    str_starts(model, "WSE") ~ "WSE",
    TRUE ~ NA_character_
  ), item = as.integer(str_remove(item, "^i"))) |>
  filter(!is.na(instrument)) |>
  transmute(instrument, item, group = paste0("CFA: ", factor),
            label = paste0(factor), method = "Current: ordinal CFA",
            loading = as.numeric(std_loading), direction = NA_character_,
            scoring_rule = "Model loading; not used as an item-mean weight")

all_groups <- bind_rows(old_comp, cur_means, old_efa, cur_efa_raw, cur_cfa) |>
  left_join(item_text, by = c("instrument", "item")) |>
  filter(!is.na(item_text)) |>
  mutate(instrument = factor(instrument, levels = inst_order))

# Loading values are shown for factors when |loading| >= .30. This is a
# display threshold that makes cross-loadings visible, not an automatic item
# retention rule. Membership-only score definitions show a filled dot.
loading_groups <- all_groups |>
  filter(method %in% c("Script 18: old EFA", "Current: parallel-analysis EFA",
                       "Current: ordinal CFA")) |>
  mutate(present = abs(loading) >= 0.30,
         cell = if_else(present, sprintf("%.2f", loading), ""))
membership_groups <- all_groups |>
  filter(method %in% c("Script 18: mean composites", "Current: candidate item means")) |>
  mutate(present = TRUE, cell = "x")
plot_data <- bind_rows(loading_groups, membership_groups) |>
  filter(present) |>
  mutate(
    item_label = paste0(item, ". ", str_wrap(item_text, 63)),
    method = factor(method, levels = c("Script 18: old EFA",
                                      "Script 18: mean composites",
                                      "Current: parallel-analysis EFA",
                                      "Current: candidate item means",
                                      "Current: ordinal CFA"))
  )

# The exact membership-to-statement key is exported as a browseable CSV.
key <- all_groups |>
  mutate(item_statement = item_text,
         loading_displayed = if_else(
           method %in% c("Script 18: old EFA", "Current: parallel-analysis EFA",
                         "Current: ordinal CFA"),
           abs(loading) >= .30, NA)) |>
  select(instrument, method, group, label, item, item_statement, loading,
         direction, scoring_rule, loading_displayed) |>
  arrange(instrument, method, group, item)
write_csv(key, file.path(OUT, "Script18_vs_Current_Scale_Item_Key.csv"))

for (inst in inst_order) {
  d <- plot_data |> filter(instrument == inst)
  if (nrow(d) == 0L) next
  item_levels <- item_text |>
    filter(instrument == inst) |>
    arrange(desc(item)) |>
    transmute(item_label = paste0(item, ". ", str_wrap(item_text, 63))) |>
    pull(item_label)
  d <- d |> mutate(item_label = factor(item_label, levels = item_levels))
  # Per-score item lists belong in the dedicated key CSV; brief factor names
  # keep the plot legible while the item rows show the actual wording.
  group_order <- d |>
    distinct(method, group, label) |>
    arrange(method, group)
  d <- d |>
    mutate(score_label = factor(group, levels = group_order$group))
  p <- ggplot(d, aes(score_label, item_label)) +
    geom_tile(fill = "#447fa3", color = "white", linewidth = 0.45,
              width = 0.94, height = 0.94) +
    geom_text(aes(label = cell), color = "white", size = 2.6) +
    facet_grid(. ~ method, scales = "free_x", space = "free_x", drop = TRUE) +
    labs(
      title = paste0(unname(inst_labels[inst]), ": historical and current item groupings"),
      subtitle = "EFA/CFA tiles show signed loading values when |loading| >= .30; x = included in the unit-weighted mean.",
      x = NULL, y = NULL,
      caption = "Rows are the actual item statements. Empty cells mean no mean-score membership or |loading| < .30. See Script18_vs_Current_Scale_Item_Key.csv for exact item lists. Current CFA was not fit for AI Reflection; current candidate means remain provisional."
    ) +
    theme_minimal(base_size = 9) +
    theme(panel.grid = element_blank(),
          strip.text = element_text(face = "bold", size = 8),
          axis.text.x = element_text(angle = 55, hjust = 1, vjust = 1, size = 7),
          axis.text.y = element_text(size = 7),
          plot.title = element_text(face = "bold"),
          plot.caption = element_text(hjust = 0, size = 7))
  stem <- file.path(OUT, paste0("Script18_vs_Current_Item_Map_", inst))
  ggsave(paste0(stem, ".png"), p, width = 20, height = 12, dpi = 220, bg = "white")
  ggsave(paste0(stem, ".pdf"), p, width = 20, height = 12, bg = "white")
}

message("Wrote instrument comparison maps and Script18_vs_Current_Scale_Item_Key.csv to ", OUT)
