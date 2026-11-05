# Composite x composite correlation matrices, old pipeline vs funnel.
#
#   old : 18_composite_correlations, 11 composites (Beliefs = 3 EFA factors on items 6-22)
#   new : funnel_out/09_composite_matrix.csv, 13 composites (Beliefs = 4 source scales)
#
# Nothing is re-estimated here. Both matrices are read from the analyses that
# produced them, so the figure cannot disagree with the tables.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
  library(tibble)
})

root    <- getwd()
out_dir <- file.path(root, "funnel_out", "plots")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

old_path <- file.path(root, "18_composite_correlations", "csv",
                      "Composite_Cross_Factor_Heatmap_Matrix.csv")
new_path <- file.path(root, "funnel_out", "09_composite_matrix.csv")
stopifnot(file.exists(old_path), file.exists(new_path))

# display names, in the order they should appear (grouped by instrument)
old_labels <- c(
  Beliefs_UtilityComfort   = "Beliefs  utility & comfort",
  Beliefs_FutureAIIntent   = "Beliefs  future AI intent",
  Beliefs_ConcernHarms     = "Beliefs  concern / harms",
  IMI_MR1                  = "IMI  MR1",
  IMI_MR2                  = "IMI  MR2",
  IMI_MR3                  = "IMI  MR3",
  WSE_MR1                  = "WSE  MR1",
  WSE_MR2                  = "WSE  MR2",
  WSE_MR3                  = "WSE  MR3",
  AIRefl_MR1               = "AIRef  MR1",
  AIRefl_MR2               = "AIRef  MR2"
)

new_labels <- c(
  b_knowledge   = "Beliefs  knowledge",
  b_value       = "Beliefs  value",
  b_cost        = "Beliefs  cost",
  b_intention   = "Beliefs  intention",
  b_attainment  = "Beliefs  attainment (1 item)",
  i_interest    = "IMI  interest",
  i_competence  = "IMI  competence",
  i_effort      = "IMI  effort",
  w_total       = "WSE  total",
  w_process     = "WSE  process",
  w_physical    = "WSE  physical",
  w_timeeffort  = "WSE  time / effort",
  a_total       = "AIRef  total"
)

# ---------------------------------------------------------------- old matrix
old_long <- read_csv(old_path, show_col_types = FALSE) |>
  select(var1 = factor_x, var2 = factor_y, rho)

# ---------------------------------------------------------------- new matrix
new_wide <- read_csv(new_path, show_col_types = FALSE)
new_long <- new_wide |>
  pivot_longer(-composite, names_to = "var2", values_to = "rho") |>
  rename(var1 = composite)

# ---------------------------------------------------------------- to tiles
to_tiles <- function(d, labs) {
  keep <- names(labs)
  d |>
    filter(var1 %in% keep, var2 %in% keep) |>
    mutate(
      x = factor(labs[var2], levels = unname(labs)),
      y = factor(labs[var1], levels = rev(unname(labs))),
      rho = if_else(var1 == var2, NA_real_, rho)
    )
}

tile_plot <- function(d, title, subtitle) {
  ggplot(d, aes(x = x, y = y, fill = rho)) +
    geom_tile(colour = "white", linewidth = 0.5) +
    geom_text(aes(label = if_else(is.na(rho), "", sprintf("%.2f", rho))),
              size = 2.6, colour = "grey15") +
    scale_fill_gradient2(
      low = "#c0504d", mid = "white", high = "#4f81bd",
      midpoint = 0, limits = c(-1, 1), na.value = "grey93",
      name = "Spearman rho"
    ) +
    coord_fixed() +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL) +
    theme_minimal(base_size = 9) +
    theme(
      panel.grid  = element_blank(),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 6.8),
      axis.text.y = element_text(size = 6.8),
      panel.border = element_rect(colour = "grey70", fill = NA, linewidth = 0.3),
      plot.title    = element_text(size = 10.5, face = "bold"),
      plot.subtitle = element_text(size = 7.6, colour = "grey30")
    )
}

old_tiles <- to_tiles(old_long, old_labels)
new_tiles <- to_tiles(new_long, new_labels)

p_old <- tile_plot(
  old_tiles,
  "Old pipeline: 11 composites",
  "Beliefs enters as three items-6-22 EFA factors; the knowledge block is absent"
)

p_new <- tile_plot(
  new_tiles,
  "Funnel: 13 composites",
  "Beliefs enters as four source-defined scales plus the single attainment item"
)

n_old <- length(unique(old_tiles$var1))
n_new <- length(unique(new_tiles$var1))

fig <- p_old / p_new +
  plot_layout(heights = c(n_old, n_new), guides = "collect") +
  plot_annotation(
    title    = "Composite x composite Spearman correlations, old pipeline vs funnel",
    subtitle = "Diagonal blanked. WSE total is the sum of the three WSE subscales, so that block is structural, not a finding."
  )

png_path <- file.path(out_dir, "Composite_Correlations_Old_vs_New.png")
pdf_path <- file.path(out_dir, "Composite_Correlations_Old_vs_New.pdf")

ggsave(png_path, fig, width = 8.6, height = 12.4, dpi = 210, bg = "white")
ggsave(pdf_path, fig, width = 8.6, height = 12.4, bg = "white")

message("wrote ", png_path)
message("wrote ", pdf_path)

# ---------------------------------------------------------------- audit note
cat("\npairs plotted: old ", nrow(old_tiles), ", new ", nrow(new_tiles), "\n")
cat("range old: ", sprintf("%.2f", range(old_tiles$rho, na.rm = TRUE)), "\n")
cat("range new: ", sprintf("%.2f", range(new_tiles$rho, na.rm = TRUE)), "\n")
