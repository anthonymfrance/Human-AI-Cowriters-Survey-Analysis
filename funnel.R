#!/usr/bin/env Rscript
# =============================================================================
# funnel.R  --  one script, one funnel, one findings table
#
#   data_raw/*.csv  ->  funnel_out/FINDINGS.csv  +  funnel_out/FUNNEL_SUMMARY.md
#
# Design rules this script enforces (each one fixes a known problem in the
# numbered pipeline):
#
#   1. ONE SAMPLE. Every stage uses the same 82 complete participants. No
#      table mixes n=82 with n=91, so no corrected p-value is ever compared
#      across samples.
#   2. SCORE ONCE. The seed CSVs are ALREADY reverse-scored exports: the IMI
#      interest items correlate positively with each other as supplied (raw
#      alpha .901), and re-reversing them drops alpha to .38. So this script
#      never reverses an item twice. The only transform applied is a single
#      construct-orientation flip on the Beliefs cost block, which is stored in
#      the export as "low concern" and is flipped once here to mean "more
#      concern", matching the source paper's direction.
#   3. MEASURE, DON'T GATE. Factorability diagnostics are reported (Pearson
#      AND polychoric), never used as a hard stop. KMO is computed on the
#      UNSMOOTHED matrix; smoothing is reported but never silently applied.
#   4. FAMILY FIRST. Every test belongs to a declared family before it is run.
#      BH and Bonferroni are applied within family only.
#   5. LEVEL MATCHES CLAIM. Composites answer construct questions, items
#      answer item questions. Neither "trumps" the other.
#   6. NOTHING IS DROPPED. Non-significant results are exported too.
#
# Run:  Rscript funnel.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(psych)
  library(lavaan)
  library(ggplot2)
})

CFG <- list(
  data_dir = "data_raw",
  out_dir  = "funnel_out",
  alpha    = 0.05,
  # metric maxima, used for ceiling/floor and interpretation bands
  metric   = c(Beliefs = 5, IMI = 7, WSE = 5, AIRef = 5)
)

# The seed CSVs are ignored by this repo's *.csv rule, so the data directory is
# resolved here rather than assumed. Point FUNNEL_DATA_DIR at wherever the seed
# exports live if they are not in ./data_raw.
resolve_data_dir <- function() {
  candidates <- c(
    Sys.getenv("FUNNEL_DATA_DIR", unset = NA_character_),
    "data_raw",
    file.path("..", "cowriters_seed_csvs")
  )
  for (cand in candidates[!is.na(candidates)]) {
    if (dir.exists(cand) && file.exists(file.path(cand, "BeliefsAboutAI_Wide.csv"))) return(cand)
  }
  stop("cannot find the seed CSVs. Set FUNNEL_DATA_DIR, or copy the files from\n  cowriters_seed_csvs/ into ./data_raw/ (BeliefsAboutAI_Wide.csv, IMI_Wide.csv,\n  WritingEfficacy_Wide.csv, AI_Reflection_Wide.csv, ART_Scored.csv,\n  Condition_and_Topic.csv).", call. = FALSE)
}

CFG$data_dir <- resolve_data_dir()
CFG$plot_dir <- file.path(CFG$out_dir, "plots")
dir.create(CFG$out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(CFG$plot_dir, showWarnings = FALSE, recursive = TRUE)
cat("reading seed CSVs from: ", CFG$data_dir, "\n", sep = "")

banner <- function(...) cat("\n", strrep("=", 74), "\n", ..., "\n", strrep("=", 74), "\n", sep = "")
note   <- function(...) cat("  ", ..., "\n", sep = "")

# =============================================================================
# STAGE 0.  READ
# =============================================================================

banner("STAGE 0  read raw wide files")

read_items <- function(file, prefix, instrument) {
  path <- file.path(CFG$data_dir, file)
  if (!file.exists(path)) stop("missing input: ", path, call. = FALSE)
  d <- read_csv(path, show_col_types = FALSE)
  item_cols <- names(d)[str_detect(names(d), paste0("^", prefix, "_?[0-9]+$"))]
  if (length(item_cols) == 0) stop("no item columns in ", path, call. = FALSE)
  d |>
    select(participant_id, all_of(item_cols)) |>
    pivot_longer(-participant_id, names_to = "item_col", values_to = "score_raw") |>
    mutate(
      instrument = instrument,
      item = as.integer(str_extract(item_col, "[0-9]+$")),
      score_raw = as.numeric(score_raw)
    ) |>
    select(participant_id, instrument, item, score_raw)
}

items <- bind_rows(
  read_items("BeliefsAboutAI_Wide.csv",  "BeliefsAboutAI", "Beliefs"),
  read_items("IMI_Wide.csv",             "IMI",            "IMI"),
  read_items("WritingEfficacy_Wide.csv", "WritingEfficacy", "WSE"),
  read_items("AI_Reflection_Wide.csv",   "AIReflection",   "AIRef")
)

item_text_file <- "funnel_item_text.csv"
if (!file.exists(item_text_file)) {
  stop("missing item text map: funnel_item_text.csv", call. = FALSE)
}
item_text_map <- read_csv(item_text_file, show_col_types = FALSE) |>
  mutate(item = as.integer(item)) |>
  distinct(instrument, item, .keep_all = TRUE)
item_keys <- items |> distinct(instrument, item)
stopifnot(nrow(anti_join(item_keys, item_text_map, by = c("instrument", "item"))) == 0L)

design <- read_csv(file.path(CFG$data_dir, "Condition_and_Topic.csv"), show_col_types = FALSE) |>
  select(participant_id, sess_order = order, starts_with("condition_"), starts_with("topic_"))

art <- read_csv(file.path(CFG$data_dir, "ART_Scored.csv"), show_col_types = FALSE) |>
  select(participant_id, art_real_hits, art_fake_false_alarms,
         art_net_real_minus_fake, art_adjusted_rate)

n_items <- items |> summarise(n_item_vars = n_distinct(item), .by = instrument)
note("items read:"); print(as.data.frame(n_items), row.names = FALSE)

# The WSE instrument was administered 0-100 and adapted to 5 anchors.
# 0/25/50/75/100 -> 1/2/3/4/5 is exact and lossless; assert that.
wse_vals <- items |> filter(instrument == "WSE") |> pull(score_raw) |> unique() |> sort()
stopifnot(all(wse_vals %in% c(0, 25, 50, 75, 100)))
items <- items |>
  mutate(score_raw = if_else(instrument == "WSE", score_raw / 25 + 1, score_raw))

# =============================================================================
# STAGE 1.  SAMPLE
# =============================================================================

banner("STAGE 1  sample definition")

ids <- items |> distinct(participant_id) |> pull(participant_id)
stopifnot(length(ids) == 82)
stopifnot(setequal(ids, design$participant_id))
stopifnot(setequal(ids, art$participant_id))

completeness <- items |>
  group_by(participant_id, instrument) |>
  summarise(n_valid = sum(!is.na(score_raw)), .groups = "drop") |>
  pivot_wider(names_from = instrument, values_from = n_valid)

stopifnot(all(completeness$Beliefs == 22),
          all(completeness$IMI == 18),
          all(completeness$WSE == 20))

note("analysis sample: n = ", length(ids), " complete cases, identical across instruments")
note("order balance: ", paste(names(table(design$sess_order)), table(design$sess_order), sep = "=", collapse = ", "))
note("no participant is dropped anywhere downstream: n = 82 in every family")

# =============================================================================
# STAGE 2.  SCORING (declared once)
# =============================================================================
#
# Direction note (the old item-level scans used the stored, reversed cost items):
#
#   Beliefs items 17-20 are negatively KEYED and measure a separate construct
#   (cost). In the seed export they are stored already reversed, i.e. high =
#   LOW concern. One flip (6 - x) restores high = more perceived cost, which is
#   how Chan & Zhou report the scale (their cost-intention r is negative).
#   Do not flip them a second time: that is what produces a variable labelled
#   "concern" that actually moves in the opposite direction.

banner("STAGE 2  scoring manifest")

# Tiers are fixed by measurement quality (source definition, separable in this
# sample, reliable), never by which correlations turn out significant.
#   headline = passes all three checks; detail = fails at least one.
# total = TRUE marks a score that is the sum of other scores in its instrument.
scales <- list(
  # ---- Beliefs columns 1-22 correspond to source Q2-Q23.
  list(id = "b_knowledge",  instrument = "Beliefs", items = 1:5,   flip = integer(0), tier = "headline",
       direction = "high = greater self-rated understanding of GenAI limits",
       source    = "Chan & Zhou: 5 knowledge items (Q2-Q6)"),
  list(id = "b_value",      instrument = "Beliefs", items = 6:16,  flip = integer(0), tier = "headline",
       direction = "high = more perceived value / usefulness",
       source    = "Chan & Zhou: perceived value, 11 items (Q7-Q17)"),
  list(id = "b_cost",       instrument = "Beliefs", items = 17:20, flip = 17:20, tier = "headline",
       direction = "high = more perceived cost / concern",
       source    = "Chan & Zhou: 4 cost items (Q18-Q21), stored reversed; flipped once"),
  list(id = "b_intention",  instrument = "Beliefs", items = 21:22, flip = integer(0), tier = "headline",
       direction = "high = stronger intention to integrate GenAI",
       source    = "Chan & Zhou: 2 intention items (Q22-Q23)"),
  # value parts: latent r .83-.93 in this sample, so they are not separable here
  list(id = "b_attainment", instrument = "Beliefs", items = 6:9, flip = integer(0), tier = "detail",
       direction = "high = greater attainment value",
       source = "Chan & Zhou: attainment value (Q7-Q10)"),
  list(id = "b_intrinsic", instrument = "Beliefs", items = 10:12, flip = integer(0), tier = "detail",
       direction = "high = greater intrinsic value",
       source = "Chan & Zhou: intrinsic value (Q11-Q13)"),
  list(id = "b_utility", instrument = "Beliefs", items = 13:16, flip = integer(0), tier = "detail",
       direction = "high = greater utility value",
       source = "Chan & Zhou: utility value (Q14-Q17)"),

  # ---- IMI (18 of 45 items; supplied already reverse-scored)
  list(id = "i_interest",   instrument = "IMI", items = 1:7,   flip = integer(0), tier = "headline",
       direction = "high = more interest / enjoyment",
       source    = "IMI interest-enjoyment subscale (items 3-4 reversed upstream)"),
  list(id = "i_competence", instrument = "IMI", items = 8:13,  flip = integer(0), tier = "headline",
       direction = "high = higher perceived competence",
       source    = "IMI perceived-competence subscale (item 13 reversed upstream)"),
  list(id = "i_effort",     instrument = "IMI", items = 14:18, flip = integer(0), tier = "headline",
       direction = "high = more effort invested",
       source    = "IMI effort subscale (items 15, 18 reversed upstream)"),

  # ---- WSE / PSWSES (adapted 0-100 -> 1-5). The authors scored only the total;
  # their PCA groups were descriptive, so the subscales are detail only.
  list(id = "w_total",      instrument = "WSE", items = 1:20, flip = integer(0), tier = "headline",
       total = TRUE,
       direction = "high = higher writerly self-efficacy",
       source    = "PSWSES total, 20 items (authors scored the overall mean)"),
  # Source PCA groups, one group per item using the authors' own reassignments
  # (10 -> time/effort; 13, 15 -> process). Item 3 is listed in both groups by
  # the authors and is kept in both. Item 19 is the replacement "resources"
  # item, absent from the source PCA; our EFA places it with time/effort.
  list(id = "w_process",    instrument = "WSE", items = c(1, 3, 4, 5, 6, 7, 9, 11, 12, 13, 15, 16, 18),
       flip = integer(0), tier = "detail",
       direction = "high = higher writing process knowledge efficacy",
       source    = "PSWSES PCA factor 1 with authors' reassignments of 13 and 15"),
  list(id = "w_physical",   instrument = "WSE", items = c(8, 14, 17),
       flip = integer(0), tier = "detail",
       direction = "high = fewer physical/emotional writing barriers",
       source    = "PSWSES PCA factor 2 minus items the authors reassigned (10, 13, 15) and old item 19"),
  list(id = "w_timeeffort", instrument = "WSE", items = c(2, 3, 10, 19, 20),
       flip = integer(0), tier = "detail",
       direction = "high = higher time/effort efficacy",
       source    = "PSWSES PCA factor 3; replacement item 19 placed here by our EFA"),

  # ---- AIRef (local instrument): process vs final-summary wording; latent r = .73
  list(id = "a_process",    instrument = "AIRef", items = 1:3, flip = integer(0), tier = "headline",
       direction = "high = more positive appraisal of the summarization process",
       source    = "Local items 1-3: satisfied with, enjoyed, and found the process easy"),
  list(id = "a_product",    instrument = "AIRef", items = 4:12, flip = integer(0), tier = "headline",
       direction = "high = more positive appraisal of learning and the final summary",
       source    = "Local items 4-12: learning, reuse, expression, and the final summary"),
  list(id = "a_total",      instrument = "AIRef", items = 1:12, flip = integer(0), tier = "detail",
       total = TRUE,
       direction = "high = more positive appraisal of the AI summary",
       source    = "12-item reflection appraisal total (local instrument)")
)

scale_labels <- c(
  b_knowledge = "Knowledge", b_attainment = "Attainment Value",
  b_intrinsic = "Intrinsic Value", b_utility = "Utility Value",
  # source names first; old pipeline names in parentheses
  b_value = "Perceived Value (Utility & Comfort)", b_cost = "Perceived Cost (Concern & Harms)",
  b_intention = "Intention (Future AI Orientation)", i_interest = "Interest/Enjoyment",
  i_competence = "Perceived Competence", i_effort = "Effort/Importance",
  w_total = "WSE Total", w_process = "Process Knowledge",
  w_physical = "Physical/Emotional Barriers", w_timeeffort = "Time/Effort",
  a_process = "Enjoyment & Satisfaction", a_product = "Ownership & Usefulness",
  a_total = "AI Reflection Total"
)
tier_of  <- setNames(map_chr(scales, "tier"), map_chr(scales, "id"))
total_of <- setNames(map_lgl(scales, ~ isTRUE(.x$total)), map_chr(scales, "id"))

# One orientation flip, declared above, applied exactly once.
flip_lookup <- bind_rows(lapply(scales, function(sc) {
  if (length(sc$flip) == 0) return(tibble(instrument = character(), item = integer()))
  tibble(instrument = sc$instrument, item = as.integer(sc$flip))
})) |> distinct()

score_long <- items |>
  mutate(metric_max_raw = CFG$metric[instrument]) |>
  left_join(flip_lookup |> mutate(flagged = TRUE), by = c("instrument", "item")) |>
  mutate(
    is_flipped = !is.na(flagged),
    scored = if_else(is_flipped, (metric_max_raw + 1) - score_raw, score_raw)
  ) |>
  select(-flagged, -metric_max_raw)

stopifnot(all(!is.na(score_long$scored)))

score_one <- function(sc) {
  sub <- score_long |> filter(instrument == sc$instrument, item %in% sc$items)
  sub |>
    group_by(participant_id) |>
    summarise(!!sc$id := mean(scored), .groups = "drop")
}

composites <- reduce(map(scales, score_one), left_join, by = "participant_id") |>
  left_join(design, by = "participant_id") |>
  left_join(art, by = "participant_id")

alpha_one <- function(sc) {
  sub <- score_long |>
    filter(instrument == sc$instrument, item %in% sc$items) |>
    select(participant_id, item, scored) |>
    pivot_wider(names_from = item, values_from = scored) |>
    select(-participant_id)
  if (ncol(sub) < 2) return(NA_real_)
  suppressWarnings(psych::alpha(sub, check.keys = FALSE, warnings = FALSE)$total$raw_alpha)
}

metric_max <- function(sc) CFG$metric[[sc$instrument]]

manifest <- map_dfr(scales, function(sc) {
  x <- composites[[sc$id]]
  tibble(
    scale        = sc$id,
    instrument   = sc$instrument,
    n_items      = length(sc$items),
    items        = paste(sc$items, collapse = ","),
    flipped      = if (length(sc$flip)) paste(sc$flip, collapse = ",") else "-",
    direction    = sc$direction,
    source       = sc$source,
    metric_max   = metric_max(sc),
    n            = sum(!is.na(x)),
    mean         = mean(x, na.rm = TRUE),
    sd           = sd(x, na.rm = TRUE),
    alpha        = alpha_one(sc),
    pct_items_at_max = mean(score_long$scored[
      score_long$instrument == sc$instrument & score_long$item %in% sc$items] == metric_max(sc))
  )
}) |>
  mutate(display_label = unname(scale_labels[scale]), tier = unname(tier_of[scale]),
         .after = scale)

score_membership <- map_dfr(scales, function(sc) {
  tibble(
    scale = sc$id,
    display_label = unname(scale_labels[sc$id]),
    tier = sc$tier,
    instrument = sc$instrument,
    item = as.integer(sc$items),
    direction = sc$direction,
    source_rule = sc$source
  )
}) |>
  left_join(item_text_map, by = c("instrument", "item")) |>
  group_by(instrument, item, tier) |>
  mutate(membership_count = n_distinct(scale[!total_of[scale]]),
         shared_item = membership_count > 1L) |>
  ungroup() |>
  arrange(match(instrument, c("Beliefs", "IMI", "WSE", "AIRef")), item, tier, scale)
write_csv(score_membership, file.path(CFG$out_dir, "01_score_membership.csv"))

note("scales scored: ", nrow(manifest))
print(as.data.frame(manifest[, c("scale", "n_items", "flipped", "n", "mean", "sd", "alpha")]),
      digits = 3, row.names = FALSE)
write_csv(manifest, file.path(CFG$out_dir, "01_scoring_manifest.csv"))
write_csv(composites, file.path(CFG$out_dir, "01_participant_scores.csv"))

# =============================================================================
# STAGE 3.  MEASUREMENT DIAGNOSTICS  (report, do not gate)
# =============================================================================

banner("STAGE 3  measurement diagnostics (reported, never used as a gate)")

item_matrix <- function(instrument) {
  score_long |>
    filter(instrument == !!instrument) |>
    select(participant_id, item, scored) |>
    pivot_wider(names_from = item, values_from = scored) |>
    select(-participant_id) |>
    as.data.frame()
}

# polychoric WITHOUT silent smoothing; the correction fallback is recorded so the
# reader knows which matrix produced the KMO. Smoothing is never hidden.
polychoric_robust <- function(X) {
  attempts <- list(
    list(correct = 0.5, smooth = FALSE, label = "none (correct=0.5)"),
    list(correct = 0,   smooth = FALSE, label = "none (correct=0)"),
    list(correct = 0,   smooth = TRUE,  label = "smoothed")
  )
  for (a in attempts) {
    out <- tryCatch(
      suppressWarnings(psych::polychoric(X, global = FALSE, smooth = a$smooth, correct = a$correct)),
      error = function(e) NULL
    )
    if (!is.null(out) && is.matrix(out$rho) && all(is.finite(out$rho))) {
      return(list(rho = out$rho, applied = a$label))
    }
  }
  list(rho = NULL, applied = "failed")
}

kmo_of <- function(R) {
  tryCatch({
    k <- suppressWarnings(psych::KMO(R))
    list(overall = unname(k$MSA), msa = k$MSAi)
  }, error = function(e) list(overall = NA_real_, msa = NULL))
}

measurement_rows <- list()
item_diag_rows   <- list()

for (inst in c("Beliefs", "IMI", "WSE", "AIRef")) {
  X <- item_matrix(inst)
  n <- nrow(X)
  m <- metric_max(list(instrument = inst))

  idg <- tibble(
    instrument = inst,
    item       = as.integer(names(X)),
    mean       = map_dbl(X, mean, na.rm = TRUE),
    sd         = map_dbl(X, sd, na.rm = TRUE),
    n_distinct = map_int(X, ~ length(unique(.x))),
    pct_max    = map_dbl(X, ~ mean(.x == m)),
    pct_min    = map_dbl(X, ~ mean(.x == min(.x)))
  ) |>
    left_join(item_text_map, by = c("instrument", "item")) |>
    mutate(ceiling_flag = pct_max >= 0.40)
  item_diag_rows[[inst]] <- idg

  R_pearson <- cor(X, use = "pairwise.complete.obs")
  poly      <- polychoric_robust(X)
  R_poly    <- poly$rho

  eig_pearson <- eigen(R_pearson, symmetric = TRUE, only.values = TRUE)$values
  eig_poly    <- if (!is.null(R_poly)) eigen(R_poly, symmetric = TRUE, only.values = TRUE)$values else NA_real_

  kmo_p <- kmo_of(R_pearson)
  kmo_r <- if (!is.null(R_poly)) kmo_of(R_poly) else list(overall = NA_real_)

  # sparse-cell audit: how many item pairs have an empty cell?
  sparse_pairs <- sum(map_lgl(combn(ncol(X), 2, simplify = FALSE), function(pr) {
    any(table(X[[pr[1]]], X[[pr[2]]]) == 0)
  }))

  # Reference-k exploratory EFA. Source-defined structures guide k where
  # available; AIRef uses the prior exploratory 2-factor reference. Beliefs
  # excludes the two-item intention block from EFA.
  efa_X <- if (inst == "Beliefs") X[, as.character(1:20), drop = FALSE] else X
  efa_poly <- polychoric_robust(efa_X)
  efa_pearson <- cor(efa_X, use = "pairwise.complete.obs")
  efa_poly_min <- if (!is.null(efa_poly$rho))
    min(eigen(efa_poly$rho, symmetric = TRUE, only.values = TRUE)$values) else NA_real_
  efa_poly_pd <- !is.na(efa_poly_min) && efa_poly_min > 1e-8
  efa_r <- if (efa_poly_pd) efa_poly$rho else efa_pearson
  efa_basis <- if (efa_poly_pd) "polychoric" else "Pearson fallback (polychoric not positive definite)"
  efa_eigen <- eigen(efa_r, symmetric = TRUE, only.values = TRUE)$values
  efa_kmo <- if (efa_poly_pd) kmo_of(efa_poly$rho)$overall else NA_real_
  k_source <- c(Beliefs = 5, IMI = 3, WSE = 3, AIRef = 2)[[inst]]
  fa_fit <- tryCatch({
    f <- suppressWarnings(psych::fa(efa_r, nfactors = k_source, n.obs = nrow(efa_X),
                                    fm = "minres", rotate = "oblimin", smooth = FALSE))
    list(rmsea = unname(f$RMSEA[1]), tli = unname(f$TLI),
         rms = unname(f$rms), loadings = unclass(f$loadings))
  }, error = function(e) NULL)

  measurement_rows[[inst]] <- tibble(
    instrument        = inst,
    n                 = n,
    p                 = ncol(X),
    reference_k       = k_source,
    sparse_item_pairs = sparse_pairs,
    total_item_pairs  = choose(ncol(X), 2),
    kmo_pearson       = kmo_p$overall,
    kmo_polychoric    = kmo_r$overall,
    min_eig_pearson   = min(eig_pearson),
    min_eig_poly      = if (all(is.na(eig_poly))) NA_real_ else min(eig_poly),
    poly_pd           = if (all(is.na(eig_poly))) NA else min(eig_poly) > 1e-8,
    poly_correction   = poly$applied,
    poly_kmo_status   = if (is.na(kmo_r$overall))
      "unavailable (polychoric matrix failed / KMO undefined)" else "estimated",
    efa_item_count    = ncol(efa_X),
    efa_correlation_basis = efa_basis,
    efa_kmo_polychoric = efa_kmo,
    efa_min_eigen_polychoric = efa_poly_min,
    rmsea             = if (is.null(fa_fit)) NA_real_ else fa_fit$rmsea,
    tli               = if (is.null(fa_fit)) NA_real_ else fa_fit$tli
  )

  # loadings table for the reference-k solution
  if (!is.null(fa_fit)) {
    ld <- as.data.frame(fa_fit$loadings)
    ld$item <- as.integer(rownames(ld))
    ld$instrument <- inst
    item_diag_rows[[paste0(inst, "_loadings")]] <- ld
  }

  note(sprintf("%-8s p=%2d n=%d  KMO pearson=%.3f polychoric=%s  minEig pearson=%.3f poly=%s  [%s]",
               inst, ncol(X), n, kmo_p$overall,
               ifelse(is.na(kmo_r$overall), "NA", sprintf("%.3f", kmo_r$overall)),
               min(eig_pearson),
               ifelse(all(is.na(eig_poly)), "NA", sprintf("%.3f", min(eig_poly))),
               poly$applied))
}

# Parallel analysis is a factor-count aid for exploration, not an automatic
# decision rule. Record errors (common with sparse ordinal cells) explicitly.
parallel_rows <- list()
for (inst in c("Beliefs", "IMI", "WSE", "AIRef")) {
  X <- item_matrix(inst)
  if (inst == "Beliefs") X <- X[, as.character(1:20), drop = FALSE]
  poly <- polychoric_robust(X)
  poly_pd <- !is.null(poly$rho) &&
    min(eigen(poly$rho, symmetric = TRUE, only.values = TRUE)$values) > 1e-8
  R <- if (poly_pd) poly$rho else cor(X, use = "pairwise.complete.obs")
  pa <- tryCatch({
    capture.output(pa_fit <- psych::fa.parallel(
      R, n.obs = nrow(X), fm = "minres", fa = "fa", plot = FALSE,
      n.iter = 100
    ))
    tibble(instrument = inst, n = nrow(X), p = ncol(X),
           parallel_k = as.integer(pa_fit$nfact), status = "estimated",
           correlation_basis = if (poly_pd) "polychoric" else "Pearson fallback (polychoric not positive definite)")
  }, error = function(e) {
    tibble(instrument = inst, n = nrow(X), p = ncol(X), parallel_k = NA_integer_,
           status = paste("failed:", conditionMessage(e)),
           correlation_basis = if (poly_pd) "polychoric" else "Pearson fallback (polychoric not positive definite)")
  })
  parallel_rows[[inst]] <- pa
}
parallel_summary <- bind_rows(parallel_rows)
write_csv(parallel_summary, file.path(CFG$out_dir, "02b_parallel_analysis.csv"))

parallel_loading_rows <- list()
parallel_efa <- imap_dfr(parallel_rows, function(pa, inst) {
  k <- pa$parallel_k[[1]]
  X <- item_matrix(inst)
  if (inst == "Beliefs") X <- X[, as.character(1:20), drop = FALSE]
  poly <- polychoric_robust(X)
  poly_pd <- !is.null(poly$rho) &&
    min(eigen(poly$rho, symmetric = TRUE, only.values = TRUE)$values) > 1e-8
  R <- if (poly_pd) poly$rho else cor(X, use = "pairwise.complete.obs")
  fit <- tryCatch(suppressWarnings(psych::fa(
    R, nfactors = k, n.obs = nrow(X), fm = "minres",
    rotate = if (k == 1L) "none" else "oblimin", smooth = FALSE
  )), error = function(e) e)
  if (inherits(fit, "error")) {
    return(tibble(instrument = inst, n = nrow(X), p = ncol(X), k = k,
                  status = paste("failed:", conditionMessage(fit)),
                  rmsea = NA_real_, tli = NA_real_, rmsr = NA_real_))
  }
  ld <- as.data.frame(unclass(fit$loadings)) |>
    rownames_to_column("item") |>
    mutate(instrument = inst, k = k, .before = 1)
  parallel_loading_rows[[inst]] <<- ld
  tibble(instrument = inst, n = nrow(X), p = ncol(X), k = k,
         status = "estimated", rmsea = unname(fit$RMSEA[1]),
         tli = unname(fit$TLI), rmsr = unname(fit$rms),
         correlation_basis = if (poly_pd) "polychoric" else "Pearson fallback (polychoric not positive definite)")
})
write_csv(parallel_efa, file.path(CFG$out_dir, "02f_parallel_efa_fit.csv"))
parallel_loadings <- bind_rows(parallel_loading_rows)
write_csv(parallel_loadings, file.path(CFG$out_dir, "02g_parallel_efa_loadings.csv"))

# Theory-based ordinal CFA comparisons. Same-sample EFA/CFA is model
# exploration, not independent validation. WSE's source PCA memberships are
# represented with the reported cross-loadings; AI Reflection remains custom.
# WLSMV treats items as ordered categories (primary). MLR treats them as numbers
# (robust sensitivity); with N=82 and many thresholds, WLSMV CFI/TLI run high.
# Expect a "vcov not positive definite" warning: WLSMV estimates more sample
# statistics (thresholds + polychoric r) than there are participants, so SEs
# are approximate. Loadings and fit are still reported.
fit_cfa <- function(spec) {
  X <- item_matrix(spec$instrument)
  used_items <- sort(unique(unlist(spec$groups)))
  X <- X[, as.character(used_items), drop = FALSE]
  names(X) <- paste0("i", names(X))
  syntax <- paste(vapply(names(spec$groups), function(g) {
    paste0(g, " =~ ", paste0("i", spec$groups[[g]], collapse = " + "))
  }, character(1)), collapse = "\n")
  warnings <- character()
  quiet <- function(expr) tryCatch(withCallingHandlers(expr, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) e)
  fit <- quiet(lavaan::cfa(syntax, data = X, ordered = names(X), estimator = "WLSMV", std.lv = TRUE))
  fit_mlr <- quiet(lavaan::cfa(syntax, data = X, estimator = "MLR", std.lv = TRUE))
  base <- tibble(model = spec$id, instrument = spec$instrument, n = nrow(X), p = ncol(X),
                 factors = length(spec$groups), note = spec$note)
  if (inherits(fit, "error")) {
    return(list(fit = NULL, loadings = tibble(), factor_cors = tibble(),
                summary = base |> mutate(converged = FALSE, status = paste("failed:", conditionMessage(fit)),
                                         warning = paste(unique(warnings), collapse = " | "))))
  }
  pick <- function(f, m) tryCatch(unname(lavaan::fitMeasures(f, m)), error = function(e) rep(NA_real_, length(m)))
  w <- pick(fit, c("chisq.scaled", "df", "cfi.scaled", "tli.scaled", "rmsea.scaled", "srmr"))
  r <- if (inherits(fit_mlr, "error")) rep(NA_real_, 3) else
    pick(fit_mlr, c("cfi.robust", "rmsea.robust", "srmr"))
  ss <- lavaan::standardizedSolution(fit)
  list(
    fit = fit,
    summary = base |> mutate(
      converged = lavInspect(fit, "converged"),
      status = if (lavInspect(fit, "converged")) "estimated" else "did not converge",
      chisq = w[1], df = w[2], cfi = w[3], tli = w[4], rmsea = w[5], srmr = w[6],
      mlr_cfi = r[1], mlr_rmsea = r[2], mlr_srmr = r[3],
      warning = paste(unique(warnings), collapse = " | ")),
    loadings = ss |> filter(op == "=~") |>
      transmute(model = spec$id, factor = lhs, item = rhs, std_loading = est.std, se, pvalue),
    factor_cors = ss |> filter(op == "~~", lhs != rhs) |>
      transmute(model = spec$id, factor_1 = lhs, factor_2 = rhs, r = est.std,
                ci_low = ci.lower, ci_high = ci.upper)
  )
}

# Chan & Zhou ran three separate CFAs (knowledge, value with three facets, cost;
# their df = 5, 41, 2) and no CFA for two-item intention. The combined models
# add intention and test whether the constructs are distinct from each other.
# WSE has no CFA: its source groups came from an exploratory PCA, so there is
# no tested structure to confirm; WSE structure is examined with EFA above.
cfa_specs <- list(
  list(id = "imi_3", instrument = "IMI", note = "IMI source subscales",
       groups = list(interest = 1:7, competence = 8:13, effort = 14:18)),
  list(id = "beliefs_knowledge", instrument = "Beliefs", note = "Chan & Zhou separate CFA (source df = 5)",
       groups = list(knowledge = 1:5)),
  list(id = "beliefs_value", instrument = "Beliefs", note = "Chan & Zhou separate CFA (source df = 41)",
       groups = list(attainment = 6:9, intrinsic = 10:12, utility = 13:16)),
  list(id = "beliefs_cost", instrument = "Beliefs", note = "Chan & Zhou separate CFA (source df = 2)",
       groups = list(cost = 17:20)),
  list(id = "beliefs_4", instrument = "Beliefs", note = "Combined headline structure",
       groups = list(knowledge = 1:5, value = 6:16, cost = 17:20, intention = 21:22)),
  list(id = "beliefs_6", instrument = "Beliefs", note = "Combined, value split into source facets",
       groups = list(knowledge = 1:5, attainment = 6:9, intrinsic = 10:12,
                     utility = 13:16, cost = 17:20, intention = 21:22)),
  list(id = "airef_1", instrument = "AIRef", note = "One general appraisal factor",
       groups = list(general = 1:12)),
  list(id = "airef_2", instrument = "AIRef", note = "Process (1-3) vs product (4-12) wording",
       groups = list(process = 1:3, product = 4:12))
)
cfa_results <- set_names(map(cfa_specs, fit_cfa), map_chr(cfa_specs, "id"))
cfa_summary <- map_dfr(cfa_results, "summary")
cfa_loadings <- map_dfr(cfa_results, "loadings")
cfa_factor_cors <- map_dfr(cfa_results, "factor_cors")

# Nested comparisons: does splitting into more factors earn its keep?
cfa_comparisons <- map_dfr(list(c("beliefs_4", "beliefs_6"), c("airef_1", "airef_2")), function(pr) {
  a <- cfa_results[[pr[1]]]$fit; b <- cfa_results[[pr[2]]]$fit
  t <- if (is.null(a) || is.null(b)) NULL else
    tryCatch(suppressWarnings(lavaan::lavTestLRT(a, b)), error = function(e) NULL)
  tibble(simpler = pr[1], more_factors = pr[2],
         chisq_diff = if (is.null(t)) NA_real_ else t[2, "Chisq diff"],
         df_diff = if (is.null(t)) NA_real_ else t[2, "Df diff"],
         p = if (is.null(t)) NA_real_ else t[2, "Pr(>Chisq)"])
})
write_csv(cfa_summary, file.path(CFG$out_dir, "02c_cfa_model_summary.csv"))
write_csv(cfa_loadings, file.path(CFG$out_dir, "02d_cfa_loadings.csv"))
write_csv(cfa_factor_cors, file.path(CFG$out_dir, "02h_cfa_factor_correlations.csv"))
write_csv(cfa_comparisons, file.path(CFG$out_dir, "02i_cfa_model_comparisons.csv"))
print(as.data.frame(cfa_summary[, c("model", "df", "cfi", "rmsea", "srmr", "mlr_cfi", "mlr_rmsea")]),
      digits = 3, row.names = FALSE)
print(as.data.frame(cfa_comparisons), digits = 3, row.names = FALSE)

measurement <- bind_rows(measurement_rows)
item_diagnostics <- bind_rows(item_diag_rows[names(item_diag_rows) %in% c("Beliefs", "IMI", "WSE", "AIRef")])
write_csv(measurement, file.path(CFG$out_dir, "02_measurement.csv"))
write_csv(item_diagnostics, file.path(CFG$out_dir, "02_item_diagnostics.csv"))
efa_loadings <- bind_rows(lapply(c("Beliefs", "IMI", "WSE", "AIRef"), function(inst) {
  ld <- item_diag_rows[[paste0(inst, "_loadings")]]
  if (is.null(ld)) return(tibble())
  as_tibble(ld) |> mutate(instrument = inst, .before = 1)
})) |>
  left_join(item_text_map, by = c("instrument", "item"))
write_csv(efa_loadings, file.path(CFG$out_dir, "02e_efa_loadings.csv"))

# Beliefs loadings, printed because the factor-to-item mapping drives everything
b_load <- item_diag_rows[["Beliefs_loadings"]]
if (!is.null(b_load)) {
  # persist the matrix: the factor-to-item map is the object every downstream
  # stage depends on, so it has to be inspectable outside the console log.
  b_load <- b_load |>
    left_join(
      item_diagnostics |> filter(instrument == "Beliefs") |> select(item, item_text),
      by = "item"
    ) |>
    relocate(item, item_text) |>
    arrange(item)
  note("Beliefs 5-factor exploratory loadings (oblimin; cost oriented as concern):")
  print(b_load, digits = 2, row.names = FALSE)
  note("source facets: knowledge Q2-Q6, attainment Q7-Q10, intrinsic Q11-Q13, utility Q14-Q17, cost Q18-Q21; intention Q22-Q23 scored separately")
  write_csv(b_load, file.path(CFG$out_dir, "08_beliefs_loadings.csv"))
}

# =============================================================================
# STAGE 4.  DESCRIPTIVES WITH CORRECT BANDS
# =============================================================================

banner("STAGE 4  descriptives")

band <- function(m, mx) {
  p <- (m - 1) / (mx - 1)          # position on the scale, 0-1
  dplyr::case_when(
    is.na(p)      ~ NA_character_,
    p <= 0.20     ~ "lowest fifth",
    p <= 0.40     ~ "low",
    p <= 0.60     ~ "midpoint",
    p <= 0.80     ~ "high",
    TRUE          ~ "highest fifth"
  )
}

desc <- manifest |>
  mutate(band = band(mean, metric_max)) |>
  select(scale, instrument, n_items, metric_max, n, mean, sd, alpha, band,
         pct_items_at_max, direction)

print(as.data.frame(desc[, c("scale", "mean", "sd", "alpha", "band", "pct_items_at_max")]),
      digits = 3, row.names = FALSE)
write_csv(desc, file.path(CFG$out_dir, "03_descriptives.csv"))

art_desc <- tibble(
  scale = c("art_net", "art_adjusted_rate"),
  n     = nrow(art),
  mean  = c(mean(art$art_net_real_minus_fake), mean(art$art_adjusted_rate)),
  sd    = c(sd(art$art_net_real_minus_fake), sd(art$art_adjusted_rate))
)
note("Author Recognition Test (print exposure, not self-report): net = ",
     round(art_desc$mean[1], 3), " (SD ", round(art_desc$sd[1], 3), ")")
# The intended guessing correction is inert here: false alarms average well
# under one, most participants record none, and net correlates ~1.0 with raw
# hits. Report the score as a count of recognised authors, not as a corrected
# detection measure.
note("ART hits mean ", round(mean(art$art_real_hits, na.rm = TRUE), 2),
     ", false alarms mean ", round(mean(art$art_fake_false_alarms, na.rm = TRUE), 2),
     ", r(hits, net) = ",
     round(suppressWarnings(cor(art$art_real_hits, art$art_net_real_minus_fake,
                                use = "complete.obs")), 3))

# The ART outcome must not be a procedural artefact before it is used as an
# outcome: describe the order groups as a limited randomisation check.
art_check <- composites |>
  group_by(sess_order) |>
  summarise(n = n(), mean = mean(art_net_real_minus_fake), sd = sd(art_net_real_minus_fake),
            .groups = "drop")
art_p <- suppressWarnings(wilcox.test(art_net_real_minus_fake ~ sess_order, composites)$p.value)
note("ART by session order: ",
     paste(sprintf("%s %.2f (n=%d)", art_check$sess_order, art_check$mean, art_check$n), collapse = ", "),
     " | Wilcoxon p = ", round(art_p, 3),
     " | no detectable order-group difference in this sample")

# =============================================================================
# STAGE 5.  TEST HELPERS
# =============================================================================

cor_row <- function(df, x, y, method = "spearman") {
  ok <- complete.cases(df[[x]], df[[y]])
  n  <- sum(ok)
  ct <- suppressWarnings(cor.test(df[[x]][ok], df[[y]][ok], method = method))
  r  <- unname(ct$estimate)
  z  <- atanh(r)
  se <- 1 / sqrt(n - 3)
  tibble(estimate = r, ci_low = tanh(z - 1.96 * se), ci_high = tanh(z + 1.96 * se),
         n = n, p = ct$p.value, method = method)
}

add_adjust <- function(d) {
  d |>
    group_by(family) |>
    mutate(
      family_size = n(),
      p_bh        = p.adjust(p, "BH"),
      p_bonf      = p.adjust(p, "bonferroni"),
      survives_bh   = p_bh   < CFG$alpha,
      survives_bonf = p_bonf < CFG$alpha
    ) |>
    mutate(abs_estimate = abs(estimate),
           rank_strength = min_rank(desc(abs_estimate)),
           rank_evidence = min_rank(p_bh)) |>
    ungroup()
}

spearman_order_permutation <- function(df, x, y, group = "sess_order",
                                       permutations = 1999L, bootstraps = 1000L) {
  d <- df |> select(all_of(c(x, y, group))) |> drop_na()
  g <- as.character(d[[group]])
  group_levels <- c("Traditional_First", "AI_First")
  if (!all(group_levels %in% g)) {
    return(tibble(rho_traditional = NA_real_, rho_ai_first = NA_real_,
                  estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
                  p = NA_real_, n = nrow(d)))
  }
  rho <- function(ii) {
    if (length(ii) < 4L || n_distinct(d[[x]][ii]) < 2L || n_distinct(d[[y]][ii]) < 2L) return(NA_real_)
    suppressWarnings(cor(d[[x]][ii], d[[y]][ii], method = "spearman"))
  }
  ia <- which(g == group_levels[1]); ib <- which(g == group_levels[2])
  rho_a <- rho(ia); rho_b <- rho(ib); observed <- rho_a - rho_b
  permuted <- replicate(permutations, {
    gp <- sample(g, replace = FALSE)
    rho(which(gp == group_levels[1])) - rho(which(gp == group_levels[2]))
  })
  p_perm <- (1 + sum(abs(permuted) >= abs(observed), na.rm = TRUE)) /
    (1 + sum(!is.na(permuted)))
  boot <- replicate(bootstraps, {
    ba <- sample(ia, length(ia), replace = TRUE)
    bb <- sample(ib, length(ib), replace = TRUE)
    rho(ba) - rho(bb)
  })
  ci <- quantile(boot[is.finite(boot)], c(.025, .975), names = FALSE)
  tibble(rho_traditional = rho_a, rho_ai_first = rho_b,
         estimate = observed, ci_low = ci[1], ci_high = ci[2],
         p = p_perm, n = nrow(d))
}

# =============================================================================
# STAGE 6.  EXPLORATORY FAMILY: source-defined Beliefs constructs -> intention
# =============================================================================

banner("STAGE 6  exploratory family A: Chan & Zhou Table 5 replication")

# Pearson, because the source table is Pearson; their N = 405.
source_r <- c(b_knowledge = .179, b_value = .603, b_attainment = .587,
              b_intrinsic = .456, b_utility = .502, b_cost = -.301)
prim_a <- bind_rows(lapply(names(source_r), function(pred) {
  cor_row(composites, pred, "b_intention", method = "pearson") |>
    mutate(predictor = pred, outcome = "b_intention", level = "composite",
           source_r = source_r[[pred]])
})) |>
  mutate(family = "A: Chan & Zhou Table 5 replication -> intention (6 tests, Pearson)",
         status = "exploratory", .before = 1)

prim_a <- add_adjust(prim_a)
print(as.data.frame(prim_a[, c("predictor", "estimate", "source_r", "ci_low", "ci_high", "p", "p_bh")]),
      digits = 3, row.names = FALSE)

# =============================================================================
# STAGE 7.  EXPLORATORY FAMILY: cross-instrument candidate scores
# =============================================================================

banner("STAGE 7  families B (headline) and C (detail): cross-instrument scores")

inst_of <- setNames(manifest$instrument, manifest$scale)
headline_scales <- manifest$scale[manifest$tier == "headline"]
comp_scales <- manifest$scale

# Cross-instrument pairs only, so no score is ever correlated with its own items.
# B = both scores headline; C = any pair involving a detail score.
comp_cors <- bind_rows(lapply(combn(comp_scales, 2, simplify = FALSE), function(pr) {
  if (inst_of[[pr[1]]] == inst_of[[pr[2]]]) return(NULL)
  cor_row(composites, pr[1], pr[2]) |>
    mutate(var1 = pr[1], var2 = pr[2],
           instrument_1 = inst_of[[pr[1]]], instrument_2 = inst_of[[pr[2]]],
           predictor = pr[1], outcome = pr[2], level = "composite", .before = 1)
})) |>
  mutate(family = if_else(var1 %in% headline_scales & var2 %in% headline_scales,
                          "B: headline cross-instrument scores",
                          "C: detail cross-instrument scores"),
         status = "exploratory") |>
  add_adjust()
prim_b <- comp_cors |> filter(startsWith(family, "B"))
prim_c <- comp_cors |> filter(startsWith(family, "C"))

note("family B (headline): ", nrow(prim_b), " tests | BH: ", sum(prim_b$survives_bh),
     " | Bonferroni: ", sum(prim_b$survives_bonf))
note("family C (detail):   ", nrow(prim_c), " tests | BH: ", sum(prim_c$survives_bh),
     " | Bonferroni: ", sum(prim_c$survives_bonf))
print(as.data.frame(prim_b |> arrange(p_bh) |>
                      head(12) |>
                      select(predictor, outcome, estimate, n, p, p_bh)),
      digits = 3, row.names = FALSE)

# Author Recognition Test (ART): real authors mixed with foils, scored as
# hits - false alarms. This is a print-exposure / domain-familiarity measure,
# NOT an outcome of the AI manipulation and not a test of AI-output detection.
# It is analysed here as a CONFOUND CHECK: if beliefs predict prior exposure,
# the belief -> self-report associations are partly confounded by it.
# It is flat across session order (checked above), which doubles as a
# randomisation check.
banner("STAGE 7b  family D: candidate scores vs ART external measure")

prim_d <- bind_rows(lapply(comp_scales, function(pred) {
  cor_row(composites, pred, "art_net_real_minus_fake") |>
    mutate(predictor = pred, outcome = "art_net_real_minus_fake (prior exposure)", level = "composite",
           family = if (tier_of[[pred]] == "headline") "D: headline scores vs ART net"
                    else "D2: detail scores vs ART net")
})) |>
  mutate(status = "exploratory", .before = 1) |>
  add_adjust()

print(as.data.frame(prim_d[, c("predictor", "estimate", "ci_low", "ci_high", "p", "p_bh")]),
      digits = 3, row.names = FALSE)

# =============================================================================
# STAGE 8.  EXPLORATORY: item-level scans, one family per instrument pair
# =============================================================================

banner("STAGE 8  exploratory item-level scans (one family per instrument pair)")

inst_sets <- list(
  Beliefs = 1:22, IMI = 1:18, WSE = 1:20, AIRef = 1:12
)

item_wide <- score_long |>
  mutate(col = paste0(instrument, "_", item)) |>
  select(participant_id, col, scored) |>
  pivot_wider(names_from = col, values_from = scored)

inst_pairs <- combn(names(inst_sets), 2, simplify = FALSE)

item_tests <- bind_rows(lapply(inst_pairs, function(pr) {
  a <- inst_sets[[pr[1]]]; b <- inst_sets[[pr[2]]]
  grid <- expand.grid(ia = a, ib = b)
  out <- bind_rows(lapply(seq_len(nrow(grid)), function(i) {
    ca <- paste0(pr[1], "_", grid$ia[i]); cb <- paste0(pr[2], "_", grid$ib[i])
    cor_row(item_wide, ca, cb) |>
      mutate(item_a = ca, item_b = cb, .before = 1)
  }))
  out |> mutate(family = paste0("E: ", pr[1], " x ", pr[2], " items"))
}))

item_tests <- item_tests |>
  mutate(status = "exploratory", level = "item", method = "spearman",
         predictor = item_a, outcome = item_b) |>
  add_adjust()

item_family_summary <- item_tests |>
  group_by(family) |>
  summarise(tests = n(), bh = sum(survives_bh), bonf = sum(survives_bonf),
            min_p = min(p), min_p_bh = min(p_bh), .groups = "drop")

print(as.data.frame(item_family_summary), digits = 3, row.names = FALSE)
write_csv(item_tests, file.path(CFG$out_dir, "05_item_level_tests.csv"))
write_csv(item_tests |> arrange(family, rank_strength),
          file.path(CFG$out_dir, "05_item_level_tests_ranked.csv"))

# Cross-instrument item x headline-score exploration. Scores from the same
# instrument are excluded to avoid turning item-total overlap into a discovery.
scale_ids <- manifest |>
  filter(tier == "headline") |>
  select(scale, instrument)
scale_item_data <- composites |>
  select(participant_id, all_of(scale_ids$scale)) |>
  inner_join(item_wide, by = "participant_id")
scale_item_tests <- bind_rows(lapply(seq_len(nrow(scale_ids)), function(i) {
  sc <- scale_ids$scale[i]
  source_inst <- scale_ids$instrument[i]
  target_insts <- setdiff(names(inst_sets), source_inst)
  bind_rows(lapply(target_insts, function(target_inst) {
    target_items <- inst_sets[[target_inst]]
    bind_rows(lapply(target_items, function(it) {
      col <- paste0(target_inst, "_", it)
      cr <- cor_row(scale_item_data, sc, col)
      cr |> mutate(scale = sc, scale_instrument = source_inst,
                   item = col, item_instrument = target_inst,
                   family = paste0("scale x items: ", source_inst, " x ", target_inst),
                   .before = 1)
    }))
  }))
})) |>
  mutate(status = "exploratory", level = "scale x item", method = "spearman") |>
  add_adjust()
write_csv(scale_item_tests, file.path(CFG$out_dir, "06_scale_item_tests.csv"))
write_csv(scale_item_tests |> arrange(family, rank_strength),
          file.path(CFG$out_dir, "06_scale_item_tests_ranked.csv"))
# Navigation lists: survivors first (Bonferroni, then BH only), then pairs that
# cross the two sessions (AI: Beliefs, AIRef; writing alone: IMI, WSE), then
# |rho|. Corrections stay within each family; this ordering only aids reading.
session_of <- c(Beliefs = "AI", AIRef = "AI", IMI = "writing alone", WSE = "writing alone")
reversed_items <- c("IMI_3", "IMI_4", "IMI_13", "IMI_15", "IMI_18")
item_label <- function(col) {
  inst <- sub("_[0-9]+$", "", col); it <- as.integer(sub(".*_", "", col))
  txt <- item_text_map$item_text[match(paste(inst, it), paste(item_text_map$instrument, item_text_map$item))]
  paste0(col, if_else(col %in% reversed_items, " (R)", ""), ": ", txt)
}
rank_for_reading <- function(d, inst_a, inst_b) {
  d |>
    mutate(evidence = case_when(survives_bonf ~ "survives Bonferroni",
                                survives_bh ~ "survives BH only", TRUE ~ "not significant"),
           session_relation = if_else(session_of[inst_a] != session_of[inst_b],
                                      "cross-session (AI x writing alone)",
                                      paste0("within ", session_of[inst_a], " session"))) |>
    arrange(match(evidence, c("survives Bonferroni", "survives BH only", "not significant")),
            !startsWith(session_relation, "cross"), desc(abs(estimate))) |>
    mutate(reading_rank = row_number(), .before = 1)
}
item_score_ranked <- scale_item_tests |>
  rank_for_reading(scale_item_tests$scale_instrument, scale_item_tests$item_instrument) |>
  transmute(reading_rank, evidence, session_relation, family,
            score = scale_labels[scale], item = item_label(item),
            rho = round(estimate, 3), ci_low = round(ci_low, 3), ci_high = round(ci_high, 3),
            n, p = signif(p, 3), p_bh = signif(p_bh, 3), p_bonf = signif(p_bonf, 3))
write_csv(item_score_ranked, file.path(CFG$out_dir, "10_item_x_score_ranked.csv"))
item_item_ranked <- item_tests |>
  rank_for_reading(sub("_[0-9]+$", "", item_tests$item_a), sub("_[0-9]+$", "", item_tests$item_b)) |>
  transmute(reading_rank, evidence, session_relation, family,
            item_a = item_label(item_a), item_b = item_label(item_b),
            rho = round(estimate, 3), ci_low = round(ci_low, 3), ci_high = round(ci_high, 3),
            n, p = signif(p, 3), p_bh = signif(p_bh, 3), p_bonf = signif(p_bonf, 3))
write_csv(item_item_ranked, file.path(CFG$out_dir, "11_item_x_item_ranked.csv"))

scale_item_family_summary <- scale_item_tests |>
  group_by(family) |>
  summarise(tests = n(), bh = sum(survives_bh), bonf = sum(survives_bonf),
            min_p = min(p), .groups = "drop")
write_csv(scale_item_family_summary, file.path(CFG$out_dir, "06_scale_item_family_summary.csv"))

# =============================================================================
# STAGE 9.  MODERATION BY ORDER (declared family)
# =============================================================================

banner("STAGE 9  moderation: does session order change the association?")

mod_pairs <- tribble(
  ~predictor,     ~outcome,
  "b_value",      "b_intention",
  "b_cost",       "b_intention",
  "b_knowledge",  "b_intention",
  "b_value",      "i_interest",
  "b_cost",       "i_interest",
  "b_intention",  "i_interest",
  "b_value",      "a_total",
  "b_cost",       "a_total",
  "b_intention",  "a_total",
  "b_value",      "w_total",
  "b_cost",       "w_total"
)

moderation <- bind_rows(lapply(seq_len(nrow(mod_pairs)), function(i) {
  pv <- mod_pairs$predictor[i]; ov <- mod_pairs$outcome[i]
  spearman_order_permutation(composites, pv, ov) |>
    mutate(predictor = pv, outcome = ov,
           r_pooled = cor_row(composites, pv, ov)$estimate,
           .before = 1)
})) |>
  mutate(family = "F: order x association", status = "exploratory", level = "composite",
         method = "permutation difference in Spearman rho", .before = 1) |>
  add_adjust()

print(as.data.frame(moderation[, c("predictor", "outcome", "rho_traditional", "rho_ai_first",
                                   "r_pooled", "p_bh")]),
      digits = 3, row.names = FALSE)
note("estimate is rho(Traditional_First) - rho(AI_First); p is permutation-based,",
     " and the interval is stratified-bootstrap. Treat selected pairs as exploratory.")
write_csv(moderation, file.path(CFG$out_dir, "06_moderation.csv"))

# Full order-stratified scans at three levels. Fisher z on Spearman rho with the
# Fieller variance factor 1.06 (as in the old 06_order_effects script, minus the
# factor). Each test asks: does the correlation differ between Traditional_First
# (writing alone first) and AI_First? Groups are small (45 vs 37), so only large
# differences can survive correction.
order_data <- composites |>
  select(participant_id, sess_order, all_of(comp_scales)) |>
  inner_join(item_wide, by = "participant_id")
order_cols <- setdiff(names(order_data), c("participant_id", "sess_order"))
order_mat <- function(g) {
  X <- as.matrix(order_data[order_data$sess_order == g, order_cols])
  suppressWarnings(cor(X, method = "spearman", use = "pairwise.complete.obs"))
}
R_trad <- order_mat("Traditional_First"); R_ai <- order_mat("AI_First")
R_all <- suppressWarnings(cor(as.matrix(order_data[, order_cols]), method = "spearman",
                              use = "pairwise.complete.obs"))
n_trad <- sum(order_data$sess_order == "Traditional_First")
n_ai   <- sum(order_data$sess_order == "AI_First")

order_scan <- function(a, b, family) {
  rt <- R_trad[cbind(a, b)]; ra <- R_ai[cbind(a, b)]
  se <- sqrt(1.06 / (n_trad - 3) + 1.06 / (n_ai - 3))
  tibble(a = a, b = b, family = family,
         rho_traditional_first = rt, rho_ai_first = ra, rho_pooled = R_all[cbind(a, b)],
         estimate = rt - ra,
         p = 2 * pnorm(-abs(atanh(rt) - atanh(ra)) / se),
         n = n_trad + n_ai) |>
    mutate(pattern = case_when(
      sign(rho_traditional_first) != sign(rho_ai_first) &
        pmin(abs(rho_traditional_first), abs(rho_ai_first)) >= 0.20 ~ "opposite signs (can cancel when pooled)",
      TRUE ~ "same direction, different size"))
}
order_rank <- function(d, inst_a, inst_b) {
  d |> filter(!is.na(p)) |> add_adjust() |> rank_for_reading(inst_a[!is.na(d$p)], inst_b[!is.na(d$p)])
}
order_cols_out <- function(d) {
  d |> transmute(reading_rank, evidence, session_relation, pattern, family, a_label, b_label,
                 rho_traditional_first = round(rho_traditional_first, 3),
                 rho_ai_first = round(rho_ai_first, 3), rho_pooled = round(rho_pooled, 3),
                 difference = round(estimate, 3), p = signif(p, 3),
                 p_bh = signif(p_bh, 3), p_bonf = signif(p_bonf, 3))
}

hp <- combn(headline_scales, 2, simplify = FALSE)
order_scores <- order_scan(map_chr(hp, 1), map_chr(hp, 2), "G: order x headline score pairs")
order_scores <- order_scores |>
  order_rank(inst_of[order_scores$a], inst_of[order_scores$b]) |>
  mutate(a_label = scale_labels[a], b_label = scale_labels[b])
write_csv(order_cols_out(order_scores), file.path(CFG$out_dir, "12_order_score_x_score_ranked.csv"))

order_item_score <- order_scan(scale_item_tests$scale, scale_item_tests$item,
                               paste0("H: order x ", scale_item_tests$family))
order_item_score <- order_item_score |>
  order_rank(inst_of[order_item_score$a], sub("_[0-9]+$", "", order_item_score$b)) |>
  mutate(a_label = scale_labels[a], b_label = item_label(b))
write_csv(order_cols_out(order_item_score), file.path(CFG$out_dir, "13_order_item_x_score_ranked.csv"))

order_items <- order_scan(item_tests$item_a, item_tests$item_b,
                          sub("^E:", "I: order x", item_tests$family))
order_items <- order_items |>
  order_rank(sub("_[0-9]+$", "", order_items$a), sub("_[0-9]+$", "", order_items$b)) |>
  mutate(a_label = item_label(a), b_label = item_label(b))
write_csv(order_cols_out(order_items), file.path(CFG$out_dir, "14_order_item_x_item_ranked.csv"))

order_summary <- map_dfr(list(`score x score` = order_scores, `item x score` = order_item_score,
                              `item x item` = order_items), function(d) {
  tibble(tests = nrow(d), survive_bh = sum(d$survives_bh), survive_bonf = sum(d$survives_bonf),
         opposite_sign_pairs = sum(startsWith(d$pattern, "opposite")),
         opposite_sign_survive_bh = sum(startsWith(d$pattern, "opposite") & d$survives_bh))
}, .id = "level")
print(as.data.frame(order_summary), row.names = FALSE)

# =============================================================================
# STAGE 10.  SENSITIVITY: does the conclusion move under alternative scoring?
# =============================================================================

banner("STAGE 10  sensitivity: conclusions that could move")

alt <- composites |>
  mutate(
    # cost scored the other way (as stored in the export)
    b_cost_flipped = 6 - b_cost
  )

sens <- bind_rows(
  cor_row(alt, "b_cost", "b_intention") |>
    mutate(variant = "cost high = more concern (scored direction)", .before = 1),
  cor_row(alt, "b_cost_flipped", "b_intention") |>
    mutate(variant = "cost high = less concern (reverse direction)", .before = 1),
  cor_row(alt, "b_value", "b_intention", method = "pearson") |>
    mutate(variant = "broad value x intention (Pearson)", .before = 1),
  cor_row(alt, "b_value", "b_intention", method = "spearman") |>
    mutate(variant = "broad value x intention (Spearman)", .before = 1)
)

# IMI item 13 is the weakest competence item (CFA loading ~.54, split EFA
# loading). The official scoring keeps it; this checks that nothing depends on it.
alt <- alt |>
  left_join(score_long |> filter(instrument == "IMI", item %in% 8:12) |>
              summarise(i_competence_no13 = mean(scored), .by = participant_id),
            by = "participant_id")
sens_13 <- bind_rows(lapply(setdiff(headline_scales, c("i_interest", "i_competence", "i_effort")), function(o) {
  bind_rows(
    cor_row(alt, "i_competence", o) |> mutate(variant = paste("competence with item 13 x", o), .before = 1),
    cor_row(alt, "i_competence_no13", o) |> mutate(variant = paste("competence without item 13 x", o), .before = 1)
  )
}))
alpha_13 <- c(with = alpha_one(list(instrument = "IMI", items = 8:13)),
              without = alpha_one(list(instrument = "IMI", items = 8:12)))
r_13 <- cor(alt$i_competence, alt$i_competence_no13, method = "spearman")
sens <- bind_rows(sens, sens_13)
note(sprintf("item 13 check: alpha %.3f with vs %.3f without; scores correlate %.3f; max |change| in r = %.3f",
             alpha_13[["with"]], alpha_13[["without"]], r_13,
             max(abs(sens_13$estimate[c(TRUE, FALSE)] - sens_13$estimate[c(FALSE, TRUE)]))))

print(as.data.frame(sens), digits = 3, row.names = FALSE)
write_csv(sens, file.path(CFG$out_dir, "07_sensitivity.csv"))

# =============================================================================
# STAGE 11.  ONE FINDINGS TABLE
# =============================================================================

banner("STAGE 11  findings table")

keep_cols <- function(d, kind) {
  d |> select(family, status, level, predictor, outcome, method, estimate, ci_low, ci_high,
              n, p, family_size, p_bh, p_bonf, survives_bh, survives_bonf) |>
    mutate(estimate_kind = kind)
}

findings <- bind_rows(
  keep_cols(prim_a, "correlation (Pearson r)"),
  keep_cols(prim_b, "correlation (Spearman r)"),
  keep_cols(prim_c, "correlation (Spearman r)"),
  keep_cols(prim_d, "correlation (Spearman r)"),
  keep_cols(moderation, "difference in Spearman rho (permutation test)"),
  keep_cols(order_scores |> mutate(predictor = a, outcome = b, level = "composite",
                                   ci_low = NA_real_, ci_high = NA_real_,
                                   status = "exploratory", method = "Fisher z, Spearman rho by order"),
            "difference in Spearman rho (Traditional_First - AI_First)")
) |>
  mutate(
    estimate = round(estimate, 3),
    ci_low   = round(ci_low, 3),
    ci_high  = round(ci_high, 3),
    p        = signif(p, 3),
    p_bh     = signif(p_bh, 3),
    p_bonf   = signif(p_bonf, 3),
    verdict  = case_when(
      survives_bonf ~ "survives Bonferroni",
      survives_bh   ~ "survives BH only",
      TRUE          ~ "not significant after correction"
    )
  ) |>
  arrange(family, p_bh)

write_csv(findings, file.path(CFG$out_dir, "FINDINGS.csv"))
write_csv(item_family_summary, file.path(CFG$out_dir, "04_item_family_summary.csv"))

# =============================================================================
# STAGE 11b.  COMPOSITE x COMPOSITE MATRIX
# Cross-instrument subscale map; within-instrument item associations belong in
# measurement/reliability checks, not this discovery family.
# =============================================================================

banner("STAGE 11b  composite x composite matrix")

comp_df <- composites |> select(all_of(comp_scales))
comp_mat <- cor(comp_df, method = "spearman", use = "pairwise.complete.obs")

write_csv(comp_cors, file.path(CFG$out_dir, "09_composite_correlations.csv"))
write_csv(comp_cors |> arrange(family, rank_strength),
          file.path(CFG$out_dir, "09_composite_correlations_ranked.csv"))

# Blank cells are same-instrument pairs, which are measurement questions, not
# tests. Markers come from each pair's own family (B or C).
plot_map <- function(plot_scores, file_stem, title, subtitle, size) {
  plot_labels <- setNames(paste0(inst_of[plot_scores], ": ", scale_labels[plot_scores],
                                 ifelse(tier_of[plot_scores] == "detail", " (detail)", "")),
                          plot_scores)
  # Lower triangle: earlier score in plot order on x, later score on y.
  # Within-survey cells come from the full matrix for context; they are not
  # tests, so they are faded and carry no marker.
  tests <- comp_cors |>
    filter(var1 %in% plot_scores, var2 %in% plot_scores) |>
    transmute(var1, var2, estimate, p_bh, p_bonf, within = FALSE)
  within <- expand.grid(var1 = plot_scores, var2 = plot_scores, stringsAsFactors = FALSE) |>
    filter(var1 != var2, inst_of[var1] == inst_of[var2]) |>
    mutate(estimate = comp_mat[cbind(var1, var2)], p_bh = NA_real_, p_bonf = NA_real_, within = TRUE)
  heat_data <- bind_rows(tests, within) |>
    mutate(first = match(var1, plot_scores) < match(var2, plot_scores),
           a = if_else(first, var1, var2), b = if_else(first, var2, var1),
           var1 = a, var2 = b) |>
    distinct(var1, var2, .keep_all = TRUE) |>
    mutate(diag = FALSE) |>
    bind_rows(tibble(var1 = plot_scores, var2 = plot_scores, estimate = 1,
                     within = FALSE, diag = TRUE)) |>
    mutate(
      sig = case_when(within | diag ~ "", p_bonf < CFG$alpha ~ "**", p_bh < CFG$alpha ~ "*", TRUE ~ ""),
      cell_label = if_else(diag, "", sprintf("%.2f%s", estimate, sig)),
      var1 = factor(var1, levels = plot_scores),
      var2 = factor(var2, levels = rev(plot_scores))
    )
  p <- ggplot(heat_data, aes(var1, var2, fill = estimate)) +
    geom_tile(aes(alpha = if_else(within, 0.35, 1)), color = "white", linewidth = 0.6) +
    geom_text(aes(label = cell_label, color = within), size = 3.1) +
    scale_alpha_identity() +
    scale_color_manual(values = c(`FALSE` = "#17212b", `TRUE` = "#8a8f96"), guide = "none") +
    scale_fill_gradient2(low = "#3b73a8", mid = "white", high = "#bd4b3a",
                         midpoint = 0, limits = c(-1, 1), name = "Spearman\nrho") +
    scale_x_discrete(labels = unname(plot_labels[plot_scores])) +
    scale_y_discrete(labels = unname(plot_labels[rev(plot_scores)])) +
    coord_fixed() +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL,
         caption = "Exploratory, same-sample associations (n = 82); significance markers do not imply causality.") +
    theme_minimal(base_size = 10) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(angle = 55, hjust = 1),
          axis.text.y = element_text(size = 8), plot.title = element_text(face = "bold"),
          plot.caption = element_text(hjust = 0))
  ggsave(file.path(CFG$plot_dir, paste0(file_stem, ".png")), p,
         width = size[1], height = size[2], dpi = 220, bg = "white")
  ggsave(file.path(CFG$plot_dir, paste0(file_stem, ".pdf")), p,
         width = size[1], height = size[2], bg = "white")
}
plot_map(headline_scales, "Headline_Correlation_Map",
         "Headline scores: cross-survey correlations",
         "Spearman rho between headline scores. Faded cells are within-survey pairs, shown for context and not tested.\n* survives BH; ** survives Bonferroni within family B (headline).",
         c(11, 9))
plot_map(comp_scales, "Detail_Correlation_Map",
         "All scores, including detail-tier subscales and totals",
         "Spearman rho. Faded cells are within-survey pairs, shown for context and not tested (a total vs its own parts is a part-whole overlap).\nMarkers use each pair's own family: B (both headline) or C (any detail score).",
         c(15, 12))

# Item membership maps show the exact statement text behind each candidate
# score. Multiple tiles on a row expose source-defined overlaps (notably WSE).
make_membership_plot <- function(inst) {
  d <- score_membership |>
    filter(instrument == inst) |>
    mutate(item_label = paste0("", item, ". ", str_wrap(item_text, width = 62)))
  item_levels <- d |>
    distinct(item, item_label) |>
    arrange(item) |>
    pull(item_label)
  scale_levels <- scales |>
    keep(~ .x$instrument == inst) |>
    map_chr("id")
  d <- d |>
    mutate(item_label = factor(item_label, levels = rev(item_levels)),
           display_label = factor(display_label, levels = unname(scale_labels[scale_levels])))
  ggplot(d, aes(display_label, item_label)) +
    geom_tile(fill = "#4c83a8", color = "white", linewidth = 0.8, width = 0.95, height = 0.95) +
    geom_text(aes(label = if_else(shared_item, "shared", "✓")), color = "white", size = 3) +
    scale_x_discrete(position = "top", drop = FALSE) +
    labs(title = paste0(inst, ": statements included in each score"),
         subtitle = "A marked cell means the statement contributes to that score; ‘shared’ marks membership in multiple scores.",
         x = NULL, y = NULL,
         caption = "Statement wording is shown verbatim from the cleaned survey item labels; score definitions are listed in 01_score_membership.csv.") +
    theme_minimal(base_size = 10) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(size = 9, face = "bold"),
          axis.text.y = element_text(size = 8), plot.title = element_text(face = "bold"),
          plot.caption = element_text(hjust = 0))
}
membership_heights <- c(Beliefs = 11, IMI = 8, WSE = 10, AIRef = 8)
for (inst in names(membership_heights)) {
  p <- make_membership_plot(inst)
  ggsave(file.path(CFG$plot_dir, paste0("Membership_", inst, ".png")), p,
         width = 12, height = membership_heights[[inst]], dpi = 220, bg = "white")
  ggsave(file.path(CFG$plot_dir, paste0("Membership_", inst, ".pdf")), p,
         width = 12, height = membership_heights[[inst]], bg = "white")
}

write_csv(
  as.data.frame(comp_mat) |> tibble::rownames_to_column("composite"),
  file.path(CFG$out_dir, "09_composite_matrix.csv")
)

note("composite matrix: ", nrow(comp_cors), " pairs; ",
     sum(comp_cors$survives_bh), " survive BH; ",
     sum(comp_cors$survives_bonf), " survive Bonferroni")

cat("\n")
print(as.data.frame(findings |> select(family, predictor, outcome, estimate, n, p_bh, verdict)),
      digits = 3, row.names = FALSE)

survivors <- findings |> filter(survives_bh)
cat("\nfindings surviving BH within their family: ", nrow(survivors), " of ", nrow(findings), "\n")

# =============================================================================
# STAGE 12.  HUMAN-READABLE SUMMARY
# =============================================================================

banner("STAGE 12  summary")

cfa_fit <- function(model, col) cfa_summary[[col]][cfa_summary$model == model]
fc_range <- function(model) {
  r <- cfa_factor_cors$r[cfa_factor_cors$model == model]
  if (length(r) == 1) sprintf("%.2f", r) else sprintf("%.2f to %.2f", min(r), max(r))
}
alpha_range <- function(ids) {
  a <- manifest$alpha[match(ids, manifest$scale)]
  if (length(a) == 1) sprintf("%.2f", a) else sprintf("%.2f-%.2f", min(a), max(a))
}
facets <- c("attainment", "intrinsic", "utility")
vf <- cfa_factor_cors |> filter(model == "beliefs_6", factor_1 %in% facets, factor_2 %in% facets)
value_facet_r <- sprintf("%.2f to %.2f", min(vf$r), max(vf$r))

md <- c(
  "# Funnel summary",
  "",
  paste0("Generated by `funnel.R`. Sample: n = ", length(ids),
         " complete participants, identical across every stage."),
  "",
  "## Measurement (reported, not gated)",
  "",
  "| instrument | items in diagnostic | Pearson KMO | polychoric KMO | min eigen (poly) | EFA items | EFA basis | subset KMO | subset min eigen | reference-k EFA RMSEA/TLI |",
  "|---|---:|---:|---:|---:|---:|---|---:|---:|---|",
  sprintf("| %s | %d | %.3f | %s | %s | %d | %s | %s | %s | %s / %s |",
          measurement$instrument, measurement$p, measurement$kmo_pearson,
          ifelse(is.na(measurement$kmo_polychoric), "NA", sprintf("%.3f", measurement$kmo_polychoric)),
          ifelse(is.na(measurement$min_eig_poly), "NA", sprintf("%.3f", measurement$min_eig_poly)),
          measurement$efa_item_count,
          measurement$efa_correlation_basis,
          ifelse(is.na(measurement$efa_kmo_polychoric), "NA", sprintf("%.3f", measurement$efa_kmo_polychoric)),
          ifelse(is.na(measurement$efa_min_eigen_polychoric), "NA", sprintf("%.3f", measurement$efa_min_eigen_polychoric)),
          ifelse(is.na(measurement$rmsea), "NA", sprintf("%.3f", measurement$rmsea)),
          ifelse(is.na(measurement$tli), "NA", sprintf("%.3f", measurement$tli))),
  "",
  "Polychoric KMO is unavailable for the full Beliefs set because its estimated",
  "matrix is not positive definite. The 20-item EFA subset is also indefinite, so",
  "EFA falls back to the explicitly labeled Pearson matrix for that instrument.",
  "It excludes the two-item Intention score (source Q22-Q23), scored as an observed mean.",
  "CFA and EFA comparisons use this same sample and are exploratory, not validation.",
  "",
  "## Factor count (parallel analysis, exploratory)",
  "",
  "| instrument | parallel factors | EFA at that k RMSEA/TLI |",
  "|---|---:|---|",
  sprintf("| %s | %s | %.3f / %.3f |", parallel_summary$instrument, parallel_summary$parallel_k,
          parallel_efa$rmsea[match(parallel_summary$instrument, parallel_efa$instrument)],
          parallel_efa$tli[match(parallel_summary$instrument, parallel_efa$instrument)]),
  "",
  "## CFA models",
  "",
  "| model | factors | items | df | CFI | TLI | RMSEA | SRMR | MLR CFI | MLR RMSEA | note |",
  "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
  sprintf("| %s | %d | %d | %s | %.3f | %.3f | %.3f | %.3f | %s | %s | %s |",
          cfa_summary$model, cfa_summary$factors, cfa_summary$p, cfa_summary$df,
          cfa_summary$cfi, cfa_summary$tli, cfa_summary$rmsea, cfa_summary$srmr,
          ifelse(is.na(cfa_summary$mlr_cfi), "NA", sprintf("%.3f", cfa_summary$mlr_cfi)),
          ifelse(is.na(cfa_summary$mlr_rmsea), "NA", sprintf("%.3f", cfa_summary$mlr_rmsea)),
          cfa_summary$note),
  "",
  "| simpler model | model with more factors | chi-square diff | df diff | p |",
  "|---|---|---:|---:|---:|",
  sprintf("| %s | %s | %.2f | %s | %.2g |", cfa_comparisons$simpler, cfa_comparisons$more_factors,
          cfa_comparisons$chisq_diff, cfa_comparisons$df_diff, cfa_comparisons$p),
  "",
  "WLSMV (ordinal) is primary; CFI/TLI/RMSEA are the scaled versions. MLR treats",
  "items as numeric and is shown as a sensitivity check; WLSMV CFI runs high at",
  "N = 82. A nested chi-square difference almost always favors more factors, so",
  "read it together with the factor correlations in 02h_cfa_factor_correlations.csv",
  "(above ~.85 suggests two factors are not separable in this sample).",
  "All WLSMV models warn that the parameter covariance matrix is not positive",
  "definite: there are more sample statistics (thresholds + polychoric r) than",
  "participants, so standard errors are approximate. KMO is an EFA screen only.",
  "WSE has no CFA: its source groups came from an exploratory PCA.",
  "",
  "## Score tiers",
  "",
  sprintf("- Headline (%d): %s.", length(headline_scales),
          paste(scale_labels[headline_scales], collapse = ", ")),
  sprintf("- Detail (%d): %s.", sum(manifest$tier == "detail"),
          paste(scale_labels[manifest$scale[manifest$tier == "detail"]], collapse = ", ")),
  "- Headline scores pass all three checks: defined by the source (or by item",
  "  wording for the local AI Reflection scale), separable in this sample, and",
  "  reliable. Detail scores fail at least one. Tiers were fixed before looking",
  "  at the correlations below; do not move a score between tiers after the fact.",
  "",
  "## Visual summaries",
  "",
  "- `plots/Headline_Correlation_Map.png`: cross-instrument Spearman correlations among headline scores (family B).",
  "- `plots/Detail_Correlation_Map.png`: every score, including detail subscales and totals (families B and C).",
  "- `plots/Membership_Beliefs.png`, `Membership_IMI.png`, `Membership_WSE.png`, and `Membership_AIRef.png` show the exact item statements included in each scored scale. ‘Shared’ marks an item in more than one non-total score within the same tier.",
  "- The exact row-level membership, tier, direction, and scoring source are also in `01_score_membership.csv`.",
  "",
  "## Descriptives",
  "",
  "| scale | tier | items | mean | SD | alpha | band | items at ceiling |",
  "|---|---|---:|---:|---:|---:|---|---:|",
  sprintf("| %s | %s | %d | %.2f | %.2f | %s | %s | %.0f%% |",
          desc$scale, tier_of[desc$scale], desc$n_items, desc$mean, desc$sd,
          ifelse(is.na(desc$alpha), "NA", sprintf("%.3f", desc$alpha)),
          desc$band, 100 * desc$pct_items_at_max),
  "",
  "## Findings surviving correction within their declared family",
  "",
  if (nrow(survivors) == 0) "None." else
    c(  "| family | predictor | outcome | estimate | kind | n | p (BH) | verdict |",
      "|---|---|---|---:|---|---:|---:|---|",
      sprintf("| %s | %s | %s | %.3f | %s | %d | %.4f | %s |",
              survivors$family, survivors$predictor, survivors$outcome,
              survivors$estimate, survivors$estimate_kind, survivors$n,
              survivors$p_bh, survivors$verdict)),
  "",
  "## Item-level family sizes",
  "",
  "| family | tests | survive BH | survive Bonferroni | smallest p |",
  "|---|---:|---:|---:|---:|",
  sprintf("| %s | %d | %d | %d | %.2e |",
          item_family_summary$family, item_family_summary$tests,
          item_family_summary$bh, item_family_summary$bonf, item_family_summary$min_p),
  "",
  "## Scale x item family sizes",
  "",
  "| family | tests | survive BH | survive Bonferroni |",
  "|---|---:|---:|---:|",
  sprintf("| %s | %d | %d | %d |",
          scale_item_family_summary$family, scale_item_family_summary$tests,
          scale_item_family_summary$bh, scale_item_family_summary$bonf),
  "",
  "Reading lists with full item text: 10_item_x_score_ranked.csv (items x headline",
  "scores) and 11_item_x_item_ranked.csv. Order: Bonferroni survivors, then BH-only,",
  "then the rest; within each, cross-session pairs (AI x writing alone) first, then",
  "by |rho|. (R) marks reverse-scored IMI items: a high score means the opposite of the wording.",
  "",
  "## Order effects: does a correlation change with session order?",
  "",
  sprintf("Traditional_First n = %d, AI_First n = %d. Fisher z on Spearman rho (variance factor 1.06).",
          n_trad, n_ai),
  "",
  "| level | tests | survive BH | survive Bonferroni | opposite-sign pairs | opposite-sign surviving BH |",
  "|---|---:|---:|---:|---:|---:|",
  sprintf("| %s | %d | %d | %d | %d | %d |", order_summary$level, order_summary$tests,
          order_summary$survive_bh, order_summary$survive_bonf,
          order_summary$opposite_sign_pairs, order_summary$opposite_sign_survive_bh),
  "",
  "Ranked lists: 12_order_score_x_score_ranked.csv, 13_order_item_x_score_ranked.csv,",
  "14_order_item_x_item_ranked.csv. Opposite-sign pairs can look like zero when pooled.",
  "",
  "Scale x item tests are in 06_scale_item_tests_ranked.csv. Ranked files sort",
  "by absolute association strength within each declared family; rank_evidence",
  "orders by BH-adjusted p-value. Confidence intervals for Spearman rho use a",
  "Fisher-z approximation and are descriptive. Selected order-stratified rho",
  "differences use a label permutation test and stratified bootstrap interval.",
  "",
  "## Interpretation notes",
  "",
  sprintf("- IMI: subscale alphas %s. Three-factor CFA CFI %.3f, SRMR %.3f. Item 13",
          alpha_range(c("i_interest", "i_competence", "i_effort")),
          cfa_fit("imi_3", "cfi"), cfa_fit("imi_3", "srmr")),
  sprintf("  check: competence alpha %.3f with vs %.3f without; the two scores correlate %.3f, so item 13 is kept.",
          alpha_13[["with"]], alpha_13[["without"]], r_13),
  sprintf("- Beliefs: Chan & Zhou's three separate CFAs give SRMR %.3f (knowledge),",
          cfa_fit("beliefs_knowledge", "srmr")),
  sprintf("  %.3f (value), %.3f (cost). Combined 4 vs 6 factors: CFI %.3f vs %.3f; the",
          cfa_fit("beliefs_value", "srmr"), cfa_fit("beliefs_cost", "srmr"),
          cfa_fit("beliefs_4", "cfi"), cfa_fit("beliefs_6", "cfi")),
  sprintf("  three value facets correlate %s at the latent level, so they are detail only.",
          value_facet_r),
  sprintf("  Knowledge has a strong ceiling (%.0f%% of answers at the top), which limits its correlations.",
          100 * manifest$pct_items_at_max[manifest$scale == "b_knowledge"]),
  sprintf("- WSE: total alpha %s; detail subscale alphas %s. Parallel analysis suggests",
          alpha_range("w_total"), alpha_range(c("w_process", "w_physical", "w_timeeffort"))),
  sprintf("  %s factors, but fit indices disagree on k and several items load weakly, so the total is the headline score.",
          parallel_summary$parallel_k[parallel_summary$instrument == "WSE"]),
  sprintf("- AI Reflection: 1 vs 2 factors CFI %.3f vs %.3f; process and product correlate %s",
          cfa_fit("airef_1", "cfi"), cfa_fit("airef_2", "cfi"), fc_range("airef_2")),
  sprintf("  (alphas %s), so both parts are headline. Both models fit modestly.",
          alpha_range(c("a_process", "a_product"))),
  sprintf("- Family B (headline): %d of %d cross-instrument correlations survive BH, %d survive Bonferroni.",
          sum(prim_b$survives_bh), nrow(prim_b), sum(prim_b$survives_bonf)),
  sprintf("  Strongest: %s. These are associations, not effects.",
          paste(head(with(arrange(prim_b, p_bh), sprintf("%s x %s (rho=%.2f)",
                scale_labels[predictor], scale_labels[outcome], estimate)), 3), collapse = "; ")),
  "- Some scores correlate with ART net, but these bivariate correlations do not",
  "  establish confounding.",
  "- The order x association pairs (family F) were selected post hoc; they do not",
  "  establish an order effect and need replication with a planned model.",
  "- Item-level hits concentrate in same-session pairs (Beliefs x AI Reflection,",
  "  IMI x WSE). Part of that may be shared mood or response style within one sitting.",
  "",
  "## Comparison with Chan & Zhou Table 5 (Pearson r with intention)",
  "",
  "| score | this sample (n = 82) | Chan & Zhou (N = 405) |",
  "|---|---:|---:|",
  sprintf("| %s | %.2f | %.2f |", scale_labels[prim_a$predictor], prim_a$estimate, prim_a$source_r),
  "",
  "Knowledge runs in the opposite direction from the source; treat it as a",
  "divergence, not a replication, and note its ceiling.",
  "",
  "## Notes",
  "",
  "- The seed exports are already reverse-scored. This script never reverses an",
  "  item twice; re-reversing the IMI interest items drops alpha from .901 to .38.",
  "- Cost items are stored in the export as low concern. They are flipped once",
  "  here so high = more perceived cost, which is the source paper's direction.",
  "- The WSE instrument was administered on five anchors (0/25/50/75/100) and",
  "  mapped losslessly to 1-5. Reliability is on the 5-point metric.",
  "- Every p-value is adjusted within its own family only. Values in different",
  "  families are not comparable and are not ranked against each other.",
  "- All analyses are post hoc and exploratory; adjusted p-values do not turn",
  "  these associations into confirmatory or causal findings."
)

writeLines(md, file.path(CFG$out_dir, "FUNNEL_SUMMARY.md"))
note("wrote ", file.path(CFG$out_dir, "FINDINGS.csv"))
note("wrote ", file.path(CFG$out_dir, "FUNNEL_SUMMARY.md"))
note("done")
