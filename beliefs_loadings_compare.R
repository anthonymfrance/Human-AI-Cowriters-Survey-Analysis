# Side-by-side comparison of the two BeliefsAboutAI factor solutions.
#
#   old  : 16_exploratory_beliefs, k = 3, items 6-22 only (knowledge block absent)
#   new  : funnel.R, source-k = 4, items 1-22, KMO computed on the Pearson matrix
#
# Reads the two loadings CSVs that already exist and writes one figure. It does
# not re-fit anything, so the panels cannot drift from the analyses they report.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(patchwork)
})

root     <- getwd()
out_dir  <- file.path(root, "funnel_out", "plots")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

old_path <- file.path(root, "16_exploratory_beliefs", "csv", "Beliefs_Exploratory_Loadings.csv")
new_path <- file.path(root, "funnel_out", "08_beliefs_loadings.csv")
stopifnot(file.exists(old_path), file.exists(new_path))

# source-paper construct boundaries, on the 1-22 item numbering used downstream
construct_of <- function(item) {
  dplyr::case_when(
    item <= 5  ~ "Knowledge",
    item <= 16 ~ "Value",
    item <= 20 ~ "Cost",
    TRUE       ~ "Intention"
  )
}

clean_text <- function(x) {
  x |>
    str_replace_all("generative AI technologies such as ChatGPT", "GenAI") |>
    str_replace_all("Generative AI technologies such as ChatGPT", "GenAI") |>
    str_replace_all("AI technologies such as ChatGPT", "GenAI") |>
    str_squish() |>
    str_trunc(38)
}

# ---------------------------------------------------------------- old solution
old_raw <- read_csv(old_path, show_col_types = FALSE)

old_long <- old_raw |>
  select(item = item_id, starts_with("MR")) |>
  pivot_longer(-item, names_to = "factor", values_to = "loading") |>
  mutate(solution = "old")

# ---------------------------------------------------------------- new solution
new_raw <- read_csv(new_path, show_col_types = FALSE)

new_long <- new_raw |>
  select(item, starts_with("MR")) |>
  pivot_longer(-item, names_to = "factor", values_to = "loading") |>
  mutate(solution = "new")

# ------------------------------------------------- label factors by dominant block
# Derived from the salient loadings rather than hand-written, so a label cannot
# claim a construct the matrix does not show. A factor whose salient items come
# from more than one source block is labelled "mixed", which is the whole point
# of the old panel.
compress_items <- function(x) {
  x <- sort(unique(x))
  if (!length(x)) return("-")
  runs <- split(x, cumsum(c(1L, diff(x) != 1L)))
  paste(
    vapply(runs, function(r) {
      if (length(r) == 1L) as.character(r) else paste0(min(r), "-", max(r))
    }, character(1)),
    collapse = ", "
  )
}

top_construct <- function(item, loading) {
  w <- tapply(abs(loading), construct_of(item), sum)
  names(w)[which.max(w)]
}

label_factors <- function(d) {
  d |>
    filter(abs(loading) >= 0.40) |>
    mutate(construct = construct_of(item)) |>
    group_by(solution, factor) |>
    summarise(
      n_salient    = n(),
      items        = compress_items(item),
      top          = top_construct(item, loading),
      n_constructs = n_distinct(construct),
      .groups      = "drop"
    ) |>
    mutate(
      name  = if_else(n_constructs > 1L, "mixed", top),
      label = sprintf("%s \u00b7 %s\nitems %s", factor, name, items)
    )
}

all_long <- bind_rows(old_long, new_long)
labs     <- label_factors(all_long)

message("factor -> dominant construct:")
print(labs |> select(solution, factor, top, n_constructs, items, n_salient) |>
        as.data.frame(), row.names = FALSE)

# ---------------------------------------------------------------- shared rows
# Items 1-5 exist only in the new solution; keeping them as empty rows in the
# old panel is what makes the "the knowledge block was never entered" visible.
texts <- new_raw |>
  transmute(item, item_text = clean_text(item_text))

row_key <- texts |>
  mutate(
    construct = construct_of(item),
    label = sprintf("%2d. %-9s %s", item, construct, item_text)
  ) |>
  arrange(desc(item))

y_levels <- row_key$label
names(y_levels) <- row_key$item

# cross items with every factor present in each solution, so the items the old
# pipeline never entered appear as empty cells in every column of its panel
grid <- tidyr::crossing(
  item      = sort(unique(all_long$item)),
  all_long |> distinct(solution, factor)
) |>
  left_join(all_long, by = c("item", "solution", "factor")) |>
  mutate(
    construct = construct_of(item),
    y         = factor(y_levels[as.character(item)], levels = y_levels)
  )

# ---------------------------------------------------------------- the figure
factor_line <- function(sol) {
  labs |>
    filter(solution == sol) |>
    arrange(factor) |>
    mutate(s = sprintf("%s  %-10s items %s", factor, name, items)) |>
    pull(s) |>
    paste(collapse = "\n")
}

panel <- function(sol, title, subtitle, factor_levels, show_y = TRUE) {
  d <- grid |>
    filter(solution == sol) |>
    mutate(flabel = factor(factor, levels = factor_levels))

  subtitle <- paste(c(strsplit(subtitle, "\n")[[1]], factor_line(sol)), collapse = "\n")

  ggplot(d, aes(x = flabel, y = y, fill = loading)) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_text(
      aes(label = if_else(is.na(loading), "", sprintf("%.2f", loading))),
      size = 2.9, colour = "grey15"
    ) +
    scale_fill_gradient2(
      low = "#c0504d", mid = "white", high = "#4f81bd",
      midpoint = 0, limits = c(-1, 1), na.value = "grey92",
      name = "loading"
    ) +
    scale_x_discrete() +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL) +
    theme_minimal(base_size = 9) +
    theme(
      panel.grid       = element_blank(),
      axis.text.x      = element_text(size = 8.5, face = "bold"),
      axis.text.y      = if (show_y) element_text(size = 6.3, family = "mono", hjust = 0) else element_blank(),
      axis.ticks.y     = element_blank(),
      plot.title       = element_text(size = 11, face = "bold"),
      plot.subtitle    = element_text(size = 7.6, colour = "grey30",
                                      family = "mono", lineheight = 1.15),
      legend.key.width = unit(2.2, "lines"),
      plot.margin      = margin(6, 16, 6, 6)
    )
}

old_levels <- labs |> filter(solution == "old") |> arrange(factor) |> pull(factor) |> as.character()
new_levels <- labs |> filter(solution == "new") |> arrange(factor) |> pull(factor) |> as.character()

p_old <- panel(
  "old",
  "Old pipeline: k = 3, 17 items",
  "KMO .240, reported 'not factorable';\nitems 1-5 never entered",
  old_levels,
  show_y = TRUE
)

p_new <- panel(
  "new",
  "Funnel: k = 4, 22 items",
  "KMO .807 on the Pearson matrix;\nsource-paper structure recovered",
  new_levels,
  show_y = FALSE
)

fig <- p_old + p_new +
  plot_layout(widths = c(3, 4), guides = "collect")

fig <- fig + plot_annotation(
  title    = "BeliefsAboutAI factor structure, before and after the factorability fix",
  subtitle = "Same colour scale. Empty rows in the left panel are items the old pipeline dropped."
)

png_path <- file.path(out_dir, "Beliefs_Loadings_Old_vs_New.png")
pdf_path <- file.path(out_dir, "Beliefs_Loadings_Old_vs_New.pdf")

ggsave(png_path, fig, width = 13.8, height = 8.4, dpi = 220, bg = "white")
ggsave(pdf_path, fig, width = 13.8, height = 8.4, bg = "white")

message("wrote ", png_path)
message("wrote ", pdf_path)
