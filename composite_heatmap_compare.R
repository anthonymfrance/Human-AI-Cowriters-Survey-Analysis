# Composite x composite correlation matrices, old pipeline vs funnel.
#
#   old : 18_composite_correlations/csv/Composite_Cross_Factor_Heatmap_Matrix.csv
#         11 composites, labels exactly as the original figure prints them
#   new : funnel_out/09_composite_correlations.csv
#         13 composites; the two part-whole composites are dropped from the
#         figure so the two panels contain the same kind of cell
#
# Nothing is re-estimated here. Both matrices are read from the analyses that
# produced them, so the figure cannot disagree with the tables.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
  library(stringr)
})

root    <- getwd()
out_dir <- file.path(root, "funnel_out", "plots")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

old_path <- file.path(root, "18_composite_correlations", "csv",
                      "Composite_Cross_Factor_Heatmap_Matrix.csv")
new_path <- file.path(root, "funnel_out", "09_composite_correlations.csv")
stopifnot(file.exists(old_path), file.exists(new_path))

# ---------------------------------------------------------------- old matrix
old_raw <- read_csv(old_path, show_col_types = FALSE)

# display labels come from the pipeline itself, not from a table written here
old_labels <- old_raw |>
  select(var = factor_x, label = label_x) |>
  bind_rows(old_raw |> select(var = factor_y, label = label_y)) |>
  distinct(var, .keep_all = TRUE)

old_order <- c(
  "IMI_MR1", "IMI_MR2", "IMI_MR3",
  "WSE_MR1", "WSE_MR2", "WSE_MR3",
  "AIRefl_MR1", "AIRefl_MR2",
  "Beliefs_UtilityComfort", "Beliefs_FutureAIIntent", "Beliefs_ConcernHarms"
)

old_tidy <- old_raw |>
  filter(factor_x != factor_y) |>
  transmute(var1 = factor_x, var2 = factor_y, rho = rho,
            bh = survives_bh, bonf = survives_bonferroni, n = n)

# ---------------------------------------------------------------- new matrix
# Wording is taken from the `source` and `direction` columns of
# funnel_out/01_scoring_manifest.csv, so these are the instrument's own
# subscale names and not a relabelling of the old EFA factors.
new_labels <- c(
  b_knowledge  = "Beliefs - knowledge (5 items)",
  b_value      = "Beliefs - value (11 items)",
  b_cost       = "Beliefs - cost / concern (4 items)",
  b_intention  = "Beliefs - intention (2 items)",
  i_interest   = "IMI - interest / enjoyment (7 items)",
  i_competence = "IMI - perceived competence (6 items)",
  i_effort     = "IMI - effort (5 items)",
  w_process    = "WritingEfficacy - process knowledge (11)",
  w_physical   = "WritingEfficacy - fewer barriers (7)",
  w_timeeffort = "WritingEfficacy - time / effort (5)",
  a_total      = "AIReflection - appraisal total (12)"
)

# w_total is the sum of the three WSE subscales and b_attainment is item 6,
# which is already one of the 11 value items. Both are real numbers but in a
# correlation matrix they produce part-whole cells, so they stay out of the
# figure (and stay in 09_composite_correlations.csv).
part_whole <- c("w_total", "b_attainment")

new_tidy <- read_csv(new_path, show_col_types = FALSE) |>
  filter(!var1 %in% part_whole, !var2 %in% part_whole) |>
  transmute(var1, var2, rho = estimate,
            bh = survives_bh, bonf = survives_bonf, n = n)

# ---------------------------------------------------------------- plotting
to_tiles <- function(d, labels_wide, order_vec) {
  lab <- setNames(labels_wide$label[match(order_vec, labels_wide$var)], order_vec)
  d |>
    mutate(
      lab1 = lab[var1],
      lab2 = lab[var2],
      x = factor(lab2, levels = rev(unname(lab))),
      y = factor(lab1, levels = unname(lab)),
      star = case_when(bonf  ~ "**", bh ~ "*", TRUE ~ ""),
      cell = paste0(sprintf("%.2f", rho), star)
    )
}

tile_plot <- function(d, title, subtitle) {
  ggplot(d, aes(x = x, y = y, fill = rho)) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_text(aes(label = cell), size = 3.0, colour = "grey10") +
    scale_fill_gradient2(
      low = "#c0504d", mid = "white", high = "#4f81bd",
      midpoint = 0, limits = c(-0.7, 0.7), oob = scales::squish,
      na.value = "grey93", name = "Spearman rho"
    ) +
    coord_fixed() +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL) +
    theme_minimal(base_size = 9) +
    theme(
      panel.grid    = element_blank(),
      axis.text.x   = element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y   = element_text(size = 8),
      panel.border  = element_rect(colour = "grey70", fill = NA, linewidth = 0.3),
      plot.title    = element_text(size = 11, face = "bold"),
      plot.subtitle = element_text(size = 8, colour = "grey30"),
      legend.position = "bottom"
    )
}

old_tiles <- to_tiles(old_tidy, old_labels, old_order)
new_tiles <- to_tiles(
  new_tidy,
  tibble(var = names(new_labels), label = unname(new_labels)),
  names(new_labels)
)

p_old <- tile_plot(old_tiles, "Old pipeline: 11 composites",
                   "Beliefs enters as three factors from items 6-22; no knowledge block")
p_new <- tile_plot(new_tiles, "Funnel: 11 composites",
                   "Beliefs enters as the four source scales; IMI and WritingEfficacy as source subscales")

fig <- p_old / p_new +
  plot_layout(guides = "collect") +
  plot_annotation(
    title    = "Cross-instrument composite correlations, old pipeline vs funnel",
    subtitle = "* BH < .05; ** Bonferroni < .05. Diagonal omitted. Labels are the pipeline's own.",
    caption  = paste0(
      "Old matrix: 3 pairs at n = 91 (Beliefs block), 52 at n = 82.  ",
      "New matrix: all pairs at n = 82.\n",
      "WSE total and the single attainment item are omitted here because each ",
      "duplicates a composite already shown; both are in 09_composite_correlations.csv."
    ),
    theme = theme(
      plot.title    = element_text(size = 13, face = "bold"),
      plot.subtitle = element_text(size = 9, colour = "grey25"),
      plot.caption  = element_text(size = 7.5, colour = "grey35", hjust = 0)
    )
  )

png_path <- file.path(out_dir, "Composite_Correlations_Old_vs_New.png")
pdf_path <- file.path(out_dir, "Composite_Correlations_Old_vs_New.pdf")
ggsave(png_path, fig, width = 11.5, height = 14.5, dpi = 200, bg = "white")
ggsave(pdf_path, fig, width = 11.5, height = 14.5, bg = "white")

message("wrote ", png_path)

# ---------------------------------------------------------------- audit note
counts <- function(d, nm) {
  tibble(
    matrix       = nm,
    pairs        = nrow(d),
    abs_r_ge_30  = sum(abs(d$rho) >= 0.30),
    bh           = sum(d$bh),
    bonferroni   = sum(d$bonf),
    n_range      = paste(range(d$n), collapse = "-")
  )
}

old_all <- old_raw |>
  filter(factor_x != factor_y) |>
  transmute(rho, bh = survives_bh, bonf = survives_bonferroni, n)

new_all <- read_csv(new_path, show_col_types = FALSE) |>
  transmute(rho = estimate, bh = survives_bh, bonf = survives_bonf, n)

cat("\n")
print(as.data.frame(bind_rows(
  counts(old_all, "old, 11 composites"),
  counts(new_all, "new, 13 composites"),
  counts(old_tiles, "old, as plotted"),
  counts(new_tiles, "new, as plotted")
)))

cat("\nnew composites retained in the figure:", nrow(new_tiles), "pairs,",
    length(unique(c(new_tidy$var1, new_tidy$var2))), "composites\n")

# where do the two matrices disagree on pairs they share conceptually?
cat("\nold starred pairs:\n")
old_tiles |> filter(bh) |>
  transmute(pair = paste0(lab1, "  x  ", lab2), rho = round(rho, 2), n) |>
  arrange(desc(abs(rho))) |> as.data.frame() |> print(row.names = FALSE)

cat("\nnew starred pairs:\n")
new_tiles |> filter(bh) |>
  transmute(pair = paste0(lab1, "  x  ", lab2), rho = round(rho, 2), n) |>
  arrange(desc(abs(rho))) |> as.data.frame() |> print(row.names = FALSE)
