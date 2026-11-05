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
# Labels carry the old factor names over. Verified: every old factor's clean-item
# set nests inside exactly one of these composites (IMI F1 = 7/7, F2 = 5/5,
# F3 = 5/6; WSE F1 = 7/11, F2 = 5/7, F3 = 3/5), so the name still describes the
# same items plus whatever the clean-item rule had discarded. Beliefs F1-F3 keep
# their names too, with the item-6 move noted. Knowledge has no counterpart.
new_labels <- c(
  i_interest   = "IMI F1 - Interest & Enjoyment (7)",
  i_effort     = "IMI F2 - Effort & Importance (5)",
  i_competence = "IMI F3 - Perceived Competence (6)",
  w_process    = "WSE F1 - Writing Competence (11)",
  w_physical   = "WSE F2 - Self-Regulation (7)",
  w_timeeffort = "WSE F3 - Resource & Planning (5)",
  a_total      = "AIRef F1+F2 - Appraisal total (12)",
  b_value      = "Beliefs F1 - Utility & Comfort (11)",
  b_intention  = "Beliefs F2 - Future AI Orientation (2)",
  b_cost       = "Beliefs F3 - Concern & Harms (4)",
  b_knowledge  = "Beliefs - Knowledge (5)  [no old counterpart]"
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
# Build the lower triangle from the canonical order rather than trusting the
# row order of the CSV, so both panels use the same layout: first variable at
# top-left, each cell below the diagonal.
to_tiles <- function(d, labels_wide, order_vec) {
  lab  <- setNames(labels_wide$label[match(order_vec, labels_wide$var)], order_vec)
  n    <- length(order_vec)
  pick <- function(a, b, col) {
    hit <- which((d$var1 == a & d$var2 == b) | (d$var1 == b & d$var2 == a))
    if (length(hit) == 0) return(NA)
    d[[col]][hit[1]]
  }
  grid <- expand.grid(row_i = seq_len(n), col_i = seq_len(n)) |>
    filter(row_i > col_i) |>
    mutate(
      a = order_vec[col_i],
      b = order_vec[row_i],
      rho  = mapply(pick, a, b, MoreArgs = list(col = "rho")),
      bh   = mapply(pick, a, b, MoreArgs = list(col = "bh")),
      bonf = mapply(pick, a, b, MoreArgs = list(col = "bonf")),
      n_obs = mapply(pick, a, b, MoreArgs = list(col = "n")),
      n = n_obs,
      lab1 = lab[a],
      lab2 = lab[b],
      x = factor(lab1, levels = unname(lab)),
      y = factor(lab2, levels = rev(unname(lab))),
      star = case_when(bonf ~ "**", bh ~ "*", TRUE ~ ""),
      cell = paste0(sprintf("%.2f", rho), star)
    )
  attr(grid, "n_vars") <- n
  grid
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

# every cell must be populated: an NA here would mean the pair is missing
stopifnot(!anyNA(old_tiles$rho), !anyNA(new_tiles$rho))

p_old <- tile_plot(old_tiles, "Old pipeline: 11 composites",
                   "Beliefs enters as three factors from items 6-22; no knowledge block")
p_new <- tile_plot(new_tiles, "Funnel: 11 composites, same names",
                   "Brackets are item counts. Same items as the old factor, plus what the clean-item rule had dropped")

fig <- p_old / p_new +
  plot_layout(guides = "collect") +
  plot_annotation(
    title    = "Cross-instrument composite correlations, old pipeline vs funnel",
    subtitle = "* BH < .05; ** Bonferroni < .05. Diagonal omitted. Labels are the pipeline's own.",
    caption  = paste0(
      "Old matrix: 3 pairs at n = 91 (Beliefs block), 52 at n = 82.  New matrix: all pairs at n = 82.\n",
      "Every old factor nests inside exactly one new composite. Added items: WSE F1 4/6/7/16, WSE F2 13/19, ",
      "WSE F3 3/10, IMI F3 13, Beliefs F1 item 6.\n",
      "AIRef's two factors are now one 12-item total. WSE total and the single attainment item are in ",
      "09_composite_correlations.csv but not plotted: each duplicates a composite already shown."
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
