# Old pipeline (script 17/18 composites) vs funnel headline scores, for
# explaining the change. Reads existing outputs; the only new computation is
# reliability for the candidate WSE group versions.
#
#   Rscript explain/old_vs_headline.R      (run from the repo root, after funnel.R)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(patchwork)
})

out_dir <- "explain"
img <- function(path) wrap_elements(full = grid::rasterGrob(png::readPNG(path), interpolate = TRUE))

inst_rename <- c(AIReflection = "AIRef", BeliefsAboutAI = "Beliefs",
                 WritingEfficacy = "WSE", IMI = "IMI")
inst_order <- c("Beliefs", "IMI", "WSE", "AIRef")

text_map <- read_csv("funnel_item_text.csv", show_col_types = FALSE)

old <- read_csv("17_composite_scoring/csv/Composite_Item_Membership.csv", show_col_types = FALSE) |>
  transmute(instrument = inst_rename[instrument], item = as.integer(item_id),
            old_group = paste(factor_id, proposed_name))

new <- read_csv("funnel_out/01_score_membership.csv", show_col_types = FALSE) |>
  select(instrument, item, tier, display_label)

collapse <- function(x) if (length(x) == 0) NA_character_ else paste(sort(unique(x)), collapse = " + ")
crosswalk <- text_map |>
  left_join(old, by = c("instrument", "item")) |>
  left_join(new |> filter(tier == "headline") |> summarise(headline_score = collapse(display_label),
                                                           .by = c(instrument, item)),
            by = c("instrument", "item")) |>
  left_join(new |> filter(tier == "detail") |> summarise(detail_score = collapse(display_label),
                                                         .by = c(instrument, item)),
            by = c("instrument", "item"))

# An item "moved" if its headline score differs from where most of its old
# group's items went.
modal_new <- crosswalk |>
  filter(!is.na(old_group)) |>
  count(instrument, old_group, headline_score) |>
  slice_max(n, n = 1, by = c(instrument, old_group), with_ties = FALSE) |>
  select(instrument, old_group, modal_headline = headline_score)
crosswalk <- crosswalk |>
  left_join(modal_new, by = c("instrument", "old_group")) |>
  mutate(change = case_when(
    is.na(old_group) ~ "not used in old composites; included now",
    headline_score != modal_headline ~ "moved to a different score",
    TRUE ~ "same group"
  )) |>
  select(-modal_headline) |>
  arrange(match(instrument, inst_order), item)

item_ranges <- function(x) {
  x <- sort(unique(x)); runs <- split(x, cumsum(c(1, diff(x) != 1)))
  paste(vapply(runs, function(r) if (length(r) > 2) paste0(r[1], "-", r[length(r)])
               else paste(r, collapse = ", "), ""), collapse = ", ")
}

# WSE detail groups: four candidate versions. Only reliability and
# between-group correlations are computed here.
wse_versions <- list(
  `Source PCA as published` = list(Process = c(1, 3, 4, 5, 6, 7, 9, 11, 12, 16, 18),
                                   Physical = c(8, 10, 13, 14, 15, 17, 19), `Time/Effort` = c(2, 3, 10, 19, 20)),
  `Funnel detail (chosen)` = list(Process = c(1, 3, 4, 5, 6, 7, 9, 11, 12, 13, 15, 16, 18),
                                  Physical = c(8, 14, 17), `Time/Effort` = c(2, 3, 10, 19, 20)),
  `Old pipeline EFA` = list(`F1 Writing Competence` = c(1, 3, 5, 9, 11, 12, 18),
                            `F2 Self-Regulation` = c(8, 10, 14, 15, 17), `F3 Resource & Planning` = c(2, 19, 20)),
  `Funnel EFA, k = 3, every item assigned` = list(Process = c(1, 3, 5, 6, 11, 12, 13, 18),
                                                  Mixed = c(4, 7, 8, 9, 10, 14, 15, 16, 17), `Time/Effort` = c(2, 19, 20))
)
W <- read_csv("data_raw/WritingEfficacy_Wide.csv", show_col_types = FALSE)[, -1] / 25 + 1
names(W) <- as.character(1:20)
wse_table <- bind_rows(lapply(names(wse_versions), function(v) {
  g <- wse_versions[[v]]
  M <- sapply(g, function(it) rowMeans(W[, as.character(it)]))
  r <- cor(M, method = "spearman")[lower.tri(diag(length(g)))]
  tibble(version = v, group = names(g),
         items = vapply(g, item_ranges, ""),
         alpha = round(vapply(g, function(it) psych::alpha(W[, as.character(it)], warnings = FALSE)$total$raw_alpha, 0), 2),
         items_used = length(unique(unlist(g))),
         items_in_two_groups = sum(table(unlist(g)) > 1),
         between_group_r = sprintf("%.2f to %.2f", min(r), max(r)))
}))
write_csv(wse_table, file.path(out_dir, "WSE_Group_Versions.csv"))

src <- wse_versions[["Source PCA as published"]]
crosswalk <- crosswalk |>
  left_join(tibble(item = unlist(src), g = rep(names(src), lengths(src))) |>
              summarise(source_published = paste(g, collapse = " + "), .by = item) |>
              mutate(instrument = "WSE"),
            by = c("instrument", "item"))
write_csv(crosswalk, file.path(out_dir, "Item_Crosswalk.csv"))

# One figure per instrument: every statement, where it sat before, where it sits now.
for (inst in inst_order) {
  cols <- c(old_group = "Old (script 17/18)", source_published = "Source PCA (published)",
            headline_score = "New headline", detail_score = "New detail")
  if (inst != "WSE") cols <- cols[names(cols) != "source_published"]
  d <- crosswalk |>
    filter(instrument == inst) |>
    mutate(statement = paste0(item, ". ", str_trunc(item_text, 95)),
           statement = factor(statement, levels = rev(statement))) |>
    tidyr::pivot_longer(all_of(names(cols)), names_to = "column", values_to = "group") |>
    mutate(column = factor(column, levels = names(cols), labels = unname(cols)),
           group = coalesce(group, "-"))
  p <- ggplot(d, aes(column, statement, fill = group)) +
    geom_tile(color = "white", linewidth = 0.8, show.legend = FALSE) +
    geom_text(aes(label = str_wrap(group, 26)), size = 2.7, lineheight = 0.85) +
    scale_fill_manual(values = setNames(c("grey92", scales::hue_pal(l = 85, c = 45)(n_distinct(d$group) - 1)),
                                        c("-", setdiff(sort(unique(d$group)), "-")))) +
    scale_x_discrete(position = "top") +
    labs(title = paste0(inst, ": every statement, old group vs new scores"),
         subtitle = "'-' = not in any score of that kind. Full text and change flags in Item_Crosswalk.csv.",
         x = NULL, y = NULL) +
    theme_minimal(base_size = 10) +
    theme(panel.grid = element_blank(), plot.title = element_text(face = "bold"),
          axis.text.x = element_text(face = "bold", size = 10), axis.text.y = element_text(size = 8))
  ggsave(file.path(out_dir, paste0("Crosswalk_", inst, ".png")), p,
         width = 3 + 3.3 * length(cols), height = 0.33 * n_distinct(d$item) + 1.8, dpi = 200, bg = "white")
}

# Side-by-side maps redrawn from the stored correlations in one shared order, so
# an old group and its closest headline score sit in the same row. Blue =
# positive, red = negative on both. Each map gets a key with the full statements.
short_old <- function(x) str_replace_all(x, c("^WritingEfficacy" = "WSE", "^AIReflection" = "AIRef", " -> " = " "))
old_order <- c("IMI F1 Interest & Enjoyment", "IMI F2 Effort & Importance", "IMI F3 Perceived Competence",
               "WSE F1 Writing Competence", "WSE F2 Self-Regulation", "WSE F3 Resource & Planning",
               "AIRef F1 Ownership & Usefulness", "AIRef F2 Enjoyment & Satisfaction",
               "Beliefs F1 Utility & Comfort", "Beliefs F2 Future AI Orientation", "Beliefs F3 Concern & Harms")
new_order <- c("i_interest", "i_effort", "i_competence", "w_total", "a_product", "a_process",
               "b_value", "b_intention", "b_cost", "b_knowledge")
reversed <- c("IMI_3", "IMI_4", "IMI_13", "IMI_15", "IMI_18")

old_cells <- read_csv("18_composite_correlations/csv/Composite_Cross_Factor_Heatmap_Matrix.csv", show_col_types = FALSE) |>
  transmute(x = short_old(label_x), y = short_old(label_y), rho, p_bh, p_bonf, within = FALSE)
stopifnot(setequal(old_cells$x, old_order))

headline_items <- read_csv("funnel_out/01_score_membership.csv", show_col_types = FALSE) |>
  filter(tier == "headline") |>
  mutate(group = paste0(instrument, ": ", display_label))
new_label <- with(distinct(headline_items, scale, group), setNames(group, scale))
inst_of <- with(distinct(headline_items, scale, instrument), setNames(instrument, scale))
stopifnot(setequal(names(new_label), new_order))

new_tests <- read_csv("funnel_out/09_composite_correlations.csv", show_col_types = FALSE) |>
  filter(startsWith(family, "B")) |>
  select(x = var1, y = var2, p_bh, p_bonf)
new_cells <- read_csv("funnel_out/09_composite_matrix.csv", show_col_types = FALSE) |>
  tidyr::pivot_longer(-composite, names_to = "y", values_to = "rho") |>
  rename(x = composite) |>
  filter(x %in% new_order, y %in% new_order) |>
  left_join(bind_rows(new_tests, rename(new_tests, x = y, y = x)), by = c("x", "y")) |>
  mutate(within = x != y & inst_of[x] == inst_of[y])
stopifnot(with(new_cells, all(within | x == y | !is.na(p_bh))))
new_cells <- mutate(new_cells, x = new_label[x], y = new_label[y])

heat <- function(cells, order, title, subtitle) {
  d <- cells |>
    filter(match(x, order) <= match(y, order)) |>
    mutate(label = case_when(x == y ~ "", within ~ sprintf("%.2f", rho),
                             p_bonf < .05 ~ sprintf("%.2f**", rho), p_bh < .05 ~ sprintf("%.2f*", rho),
                             TRUE ~ sprintf("%.2f", rho)),
           x = factor(x, order), y = factor(y, rev(order)))
  ggplot(d, aes(x, y, fill = rho)) +
    geom_tile(aes(alpha = if_else(within, 0.35, 1)), color = "white", linewidth = 0.6) +
    geom_text(aes(label = label, color = within), size = 3.6) +
    scale_alpha_identity() +
    scale_color_manual(values = c(`FALSE` = "#17212b", `TRUE` = "#8a8f96"), guide = "none") +
    scale_fill_gradient2(low = "#bd4b3a", mid = "white", high = "#3b73a8",
                         midpoint = 0, limits = c(-1, 1), name = "Spearman\nrho") +
    coord_fixed() +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL) +
    theme_minimal(base_size = 12) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 50, hjust = 1),
          plot.title = element_text(face = "bold"))
}

# One block per group (bold name, then its statements), flowed into columns.
key_lines <- function(items, groups, ncol = 3, width = 62) {
  blocks <- lapply(groups, function(g) {
    d <- items |> filter(group == g) |> arrange(item)
    stmt <- paste0(d$item, ". ", d$item_text,
                   if_else(paste0(d$instrument, "_", d$item) %in% reversed, " (R)", ""))
    lines <- unlist(strsplit(str_wrap(stmt, width, exdent = 5), "\n"))
    tibble(text = c(paste0(g, "  (items ", item_ranges(d$item), ")"), lines, ""),
           face = c("bold", rep("plain", length(lines) + 1)))
  })
  sizes <- vapply(blocks, nrow, 0L)
  col <- pmin(ncol, floor((cumsum(sizes) - sizes) / (sum(sizes) / ncol)) + 1)
  bind_rows(Map(function(b, k) mutate(b, col = k), blocks, col)) |>
    mutate(row = seq_along(text), .by = col)
}
key_plot <- function(d, title, subtitle, n_rows, ncol = 3) {
  ggplot(d, aes(col - 1, -row, label = text, fontface = face)) +
    geom_text(hjust = 0, vjust = 1, size = 3) +
    scale_x_continuous(limits = c(0, ncol), expand = c(0, 0)) +
    scale_y_continuous(limits = c(-n_rows - 1, 0), expand = c(0, 0)) +
    labs(title = title, subtitle = subtitle) + theme_void() +
    theme(plot.title = element_text(face = "bold", size = 13), plot.subtitle = element_text(size = 10))
}

old_key <- crosswalk |>
  filter(!is.na(old_group)) |>
  mutate(group = paste(instrument, old_group)) |>
  key_lines(old_order)
new_key <- key_lines(headline_items, unname(new_label[new_order]))
n_rows <- max(old_key$row, new_key$row)
paren_note <- "Beliefs names in parentheses are the old pipeline's names for that group, kept from our earlier naming."

fig <- (heat(old_cells, old_order, "Old: script 18 composite heatmap",
             "Every pair tested, within-survey included. * survives BH; ** survives Bonferroni (55 pairs).") |
          heat(new_cells, unname(new_label[new_order]), "New: funnel headline scores",
               paste0("Faded cells are within-survey pairs, shown for context and not tested.\n",
                      "* survives BH; ** survives Bonferroni within family B (headline).\n", paren_note))) /
  (key_plot(old_key, "Old groups: data-driven EFA clusters (Knowledge block dropped)",
            "Each item placed by its highest EFA loading. Score = mean of the listed items.", n_rows) |
     key_plot(new_key, "Headline scores: published scoring, checked by CFA/EFA and reliability",
              paste("Groups as published by the source authors. Score = mean of the listed items.", paren_note), n_rows)) +
  plot_layout(heights = c(1.1, 1)) +
  plot_annotation(title = "Before and after: old script 18 heatmap vs funnel headline map",
                  caption = paste("Same row order and colors on both maps (blue = positive, red = negative). Rows line up where an old group",
                                  "has a headline counterpart: the three old WSE factors collapse into WSE Total, and Knowledge is new.",
                                  "(R) = reverse-scored IMI item: a high score means the opposite of the wording."),
                  theme = theme(plot.title = element_text(face = "bold", size = 18),
                                plot.caption = element_text(size = 11, hjust = 0)))
ggsave(file.path(out_dir, "Old_vs_Headline_Maps.png"), fig, width = 30, height = 27, dpi = 170, bg = "white")
# Old ART scatter (script 18) vs the same three relationships with the new scores.
findings <- read_csv("funnel_out/FINDINGS.csv", show_col_types = FALSE) |>
  filter(startsWith(family, "D:"))
scores <- read_csv("funnel_out/01_participant_scores.csv", show_col_types = FALSE)
art_pairs <- c(b_value = "Perceived Value (was Utility & Comfort)",
               a_product = "Ownership & Usefulness (AI Reflection)",
               b_intention = "Intention (was Future AI Orientation)")
new_art <- scores |>
  select(art_net_real_minus_fake, all_of(names(art_pairs))) |>
  tidyr::pivot_longer(-art_net_real_minus_fake, names_to = "scale", values_to = "score") |>
  left_join(findings |> select(scale = predictor, estimate, p_bh, verdict), by = "scale") |>
  mutate(panel = factor(sprintf("%s\nrho = %.2f, BH p = %.3f, %s", art_pairs[scale], estimate, p_bh, verdict),
                        levels = unique(sprintf("%s\nrho = %.2f, BH p = %.3f, %s", art_pairs[scale],
                                                estimate, p_bh, verdict))[match(names(art_pairs), unique(scale))]))
p_new_art <- ggplot(new_art, aes(score, art_net_real_minus_fake)) +
  geom_point(alpha = 0.6, color = "#8a6fb0") +
  geom_smooth(method = "lm", se = FALSE, color = "#c0603a", formula = y ~ x) +
  facet_wrap(~ panel) +
  scale_x_continuous(limits = c(1, 5)) +
  labs(title = "Funnel headline scores (n = 82; 10 tests corrected with BH and Bonferroni)",
       x = "Score (higher = more of the attitude or reflection)", y = "ART net score") +
  theme_minimal(base_size = 11) + theme(plot.title = element_text(face = "bold"))
art_fig <- img("18_composite_correlations/plots/ART_Net_vs_Attitude_Reflection_Composites_Scatter.png") /
  p_new_art +
  plot_layout(heights = c(1, 1)) +
  plot_annotation(title = "ART net vs AI attitudes: old script 18 (top) vs funnel (bottom)",
                  theme = theme(plot.title = element_text(face = "bold", size = 14)))
ggsave(file.path(out_dir, "ART_Old_vs_New.png"), art_fig, width = 13, height = 10, dpi = 170, bg = "white")

cat("wrote", out_dir, "\n")
