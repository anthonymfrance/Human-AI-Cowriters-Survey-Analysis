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
old_map_png <- "18_composite_correlations/plots/Composite_Cross_Factor_Heatmap.png"
new_map_png <- "funnel_out/plots/Headline_Correlation_Map.png"
stopifnot(file.exists(old_map_png), file.exists(new_map_png))

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

# Side-by-side maps, each with a key of which items make up each group.
key_text <- function(d, group_col) {
  d |>
    filter(!is.na(.data[[group_col]])) |>
    summarise(items = item_ranges(item), .by = c(instrument, all_of(group_col))) |>
    arrange(match(instrument, inst_order)) |>
    mutate(line = paste0(instrument, " ", .data[[group_col]], ": items ", items)) |>
    pull(line) |>
    paste(collapse = "\n")
}
key_plot <- function(txt, title) {
  ggplot() +
    annotate("text", x = 0, y = 1, label = txt, hjust = 0, vjust = 1, size = 3.3, lineheight = 1.05) +
    labs(title = title) + xlim(0, 1) + ylim(0, 1) + theme_void() +
    theme(plot.title = element_text(face = "bold", size = 11))
}
img <- function(path) wrap_elements(full = grid::rasterGrob(png::readPNG(path), interpolate = TRUE))

headline_key <- crosswalk |>
  filter(!is.na(headline_score)) |>
  mutate(headline_score = str_split(headline_score, " \\+ ")) |>
  tidyr::unnest(headline_score) |>
  key_text("headline_score")

fig <- (img(old_map_png) | img(new_map_png)) /
  (key_plot(key_text(crosswalk, "old_group"), "Old groups: data-driven EFA clusters (Knowledge block dropped)") |
     key_plot(headline_key, "Headline scores: published scoring, checked by CFA/EFA and reliability")) +
  plot_layout(heights = c(3, 1.25)) +
  plot_annotation(title = "Before and after: old script 18 heatmap vs funnel headline map",
                  caption = "Left keeps within-survey cells at full strength; right fades them because they are not tests. Colors run in opposite directions between the two maps.",
                  theme = theme(plot.title = element_text(face = "bold", size = 15)))
ggsave(file.path(out_dir, "Old_vs_Headline_Maps.png"), fig, width = 22, height = 13, dpi = 170, bg = "white")
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
