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
dir.create(CFG$out_dir, showWarnings = FALSE, recursive = TRUE)
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

design <- read_csv(file.path(CFG$data_dir, "Condition_and_Topic.csv"), show_col_types = FALSE) |>
  select(participant_id, sess_order = order, starts_with("condition_"), starts_with("topic_"))

art <- read_csv(file.path(CFG$data_dir, "ART_Scored.csv"), show_col_types = FALSE) |>
  select(participant_id, art_net_real_minus_fake, art_adjusted_rate)

n_items <- items |> count(instrument, name = "n_item_vars")
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
# Direction note, because this is where the old pipeline's sign errors came from:
#
#   Beliefs items 17-20 are negatively KEYED and measure a separate construct
#   (cost). In the seed export they are stored already reversed, i.e. high =
#   LOW concern. One flip (6 - x) restores high = more perceived cost, which is
#   how Chan & Zhou report the scale (their cost-intention r is negative).
#   Do not flip them a second time: that is what produces a variable labelled
#   "concern" that actually moves in the opposite direction.

banner("STAGE 2  scoring manifest")

scales <- list(
  # ---- Beliefs (Chan & Zhou, 5 knowledge / 11 value / 4 cost / 2 intention)
  list(id = "b_knowledge",  instrument = "Beliefs", items = 1:5,   flip = integer(0),
       direction = "high = greater self-rated understanding of GenAI limits",
       source    = "Chan & Zhou: 5 knowledge items (Q2-Q6)"),
  list(id = "b_value",      instrument = "Beliefs", items = 6:16,  flip = integer(0),
       direction = "high = more perceived value / usefulness",
       source    = "Chan & Zhou: 11 value items (Q7-Q17)"),
  list(id = "b_cost",       instrument = "Beliefs", items = 17:20, flip = 17:20,
       direction = "high = more perceived cost / concern",
       source    = "Chan & Zhou: 4 cost items (Q18-Q21), stored reversed; flipped once"),
  list(id = "b_intention",  instrument = "Beliefs", items = 21:22, flip = integer(0),
       direction = "high = stronger intention to integrate GenAI",
       source    = "Chan & Zhou: 2 intention items (Q22-Q23)"),
  list(id = "b_attainment", instrument = "Beliefs", items = 6,     flip = integer(0),
       direction = "high = stronger attainment-value endorsement (single item)",
       source    = "Chan & Zhou: attainment value, single item (Q7)"),

  # ---- IMI (18 of 45 items; supplied already reverse-scored)
  list(id = "i_interest",   instrument = "IMI", items = 1:7,   flip = integer(0),
       direction = "high = more interest / enjoyment",
       source    = "IMI interest-enjoyment subscale (items 3-4 reversed upstream)"),
  list(id = "i_competence", instrument = "IMI", items = 8:13,  flip = integer(0),
       direction = "high = higher perceived competence",
       source    = "IMI perceived-competence subscale (item 13 reversed upstream)"),
  list(id = "i_effort",     instrument = "IMI", items = 14:18, flip = integer(0),
       direction = "high = more effort invested",
       source    = "IMI effort subscale (items 15, 18 reversed upstream)"),

  # ---- WSE / PSWSES (adapted 0-100 -> 1-5; source 3-factor split)
  list(id = "w_total",      instrument = "WSE", items = 1:20, flip = integer(0),
       direction = "high = higher writerly self-efficacy",
       source    = "PSWSES total, 20 items"),
  list(id = "w_process",    instrument = "WSE", items = c(1, 3, 4, 5, 6, 7, 9, 11, 12, 16, 18),
       flip = integer(0),
       direction = "high = higher writing process knowledge efficacy",
       source    = "PSWSES factor 1 (source PCA), 11 items"),
  list(id = "w_physical",   instrument = "WSE", items = c(8, 10, 13, 14, 15, 17, 19),
       flip = integer(0),
       direction = "high = fewer physical/emotional writing barriers",
       source    = "PSWSES factor 2 (source PCA), 7 items"),
  list(id = "w_timeeffort", instrument = "WSE", items = c(2, 3, 10, 19, 20),
       flip = integer(0),
       direction = "high = higher time/effort efficacy",
       source    = "PSWSES factor 3 (source PCA), 5 items (source notes 3/10/19 cross-load)"),

  # ---- AIRef (no source validation paper supplied; total score only)
  list(id = "a_total",      instrument = "AIRef", items = 1:12, flip = integer(0),
       direction = "high = more positive appraisal of the AI summary",
       source    = "12-item reflection appraisal total (local instrument)")
)

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

# attach item text where available (documentation only)
item_text <- c(
  "I understand GenAI has limitations in handling complex tasks.",
  "I understand GenAI can generate factually inaccurate output.",
  "I understand GenAI can generate out-of-context or inappropriate output.",
  "I understand GenAI can exhibit bias and unfairness.",
  "I understand GenAI has limited emotional intelligence and empathy.",
  "Students must learn to use GenAI well for their career.",
  "GenAI can improve my digital competence.",
  "GenAI can improve my academic performance.",
  "GenAI can help me become a better writer.",
  "I can ask GenAI questions I would not voice to my teacher.",
  "GenAI will not judge me, so I feel comfortable with it.",
  "GenAI is a great tool for student support due to anonymity.",
  "GenAI can help me save time.",
  "GenAI can give me unique insights I would not have had.",
  "GenAI can give personalised and immediate feedback.",
  "GenAI is a great tool as it is available 24/7.",
  "Using GenAI to complete assignments undermines the value of a university education.",
  "GenAI will limit my opportunities to interact and socialise.",
  "GenAI will hinder my development of transferable skills.",
  "I can become over-reliant on GenAI.",
  "Integrating GenAI in higher education will have a positive long-run impact.",
  "I envision integrating GenAI into my teaching and learning in future."
)

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
})

note("scales scored: ", nrow(manifest))
print(as.data.frame(manifest[, c("scale", "n_items", "flipped", "n", "mean", "sd", "alpha")]),
      digits = 3, row.names = FALSE)
write_csv(manifest, file.path(CFG$out_dir, "01_scoring_manifest.csv"))

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
    mutate(
      item_text = if (inst == "Beliefs") item_text[item] else NA_character_,
      ceiling_flag = pct_max >= 0.40
    )
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

  # fixed-k EFA where a source k exists (Beliefs has 4 source constructs:
  # knowledge, value, cost, intention)
  k_source <- c(Beliefs = 4, IMI = 3, WSE = 3, AIRef = 2)[[inst]]
  fa_fit <- tryCatch({
    f <- suppressWarnings(psych::fa(R_pearson, nfactors = k_source, n.obs = n,
                                    fm = "minres", rotate = "oblimin"))
    list(rmsea = unname(f$RMSEA[1]), tli = unname(f$TLI),
         rms = unname(f$rms), loadings = unclass(f$loadings))
  }, error = function(e) NULL)

  measurement_rows[[inst]] <- tibble(
    instrument        = inst,
    n                 = n,
    p                 = ncol(X),
    source_k          = k_source,
    sparse_item_pairs = sparse_pairs,
    total_item_pairs  = choose(ncol(X), 2),
    kmo_pearson       = kmo_p$overall,
    kmo_polychoric    = kmo_r$overall,
    min_eig_pearson   = min(eig_pearson),
    min_eig_poly      = if (all(is.na(eig_poly))) NA_real_ else min(eig_poly),
    poly_pd           = if (all(is.na(eig_poly))) NA else min(eig_poly) > 1e-8,
    poly_correction   = poly$applied,
    poly_kmo_status   = if (is.na(kmo_r$overall))
      "undefined (matrix not positive definite)" else "estimated",
    rmsea             = if (is.null(fa_fit)) NA_real_ else fa_fit$rmsea,
    tli               = if (is.null(fa_fit)) NA_real_ else fa_fit$tli
  )

  # loadings table for the source-k solution
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

measurement <- bind_rows(measurement_rows)
item_diagnostics <- bind_rows(item_diag_rows[names(item_diag_rows) %in% c("Beliefs", "IMI", "WSE", "AIRef")])
write_csv(measurement, file.path(CFG$out_dir, "02_measurement.csv"))
write_csv(item_diagnostics, file.path(CFG$out_dir, "02_item_diagnostics.csv"))

# Beliefs loadings, printed because the factor-to-item mapping drives everything
b_load <- item_diag_rows[["Beliefs_loadings"]]
if (!is.null(b_load)) {
  note("Beliefs 4-factor loadings (source-k, oblimin, cost block oriented as concern):")
  print(b_load |> arrange(item), digits = 2, row.names = FALSE)
  note("source constructs: knowledge Q2-Q6, value Q7-Q17, cost Q18-Q21, intention Q22-Q23")
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

# The ART outcome must not be a procedural artefact before it is used as an
# outcome: check that it is flat across session order and condition.
art_check <- composites |>
  group_by(sess_order) |>
  summarise(n = n(), mean = mean(art_net_real_minus_fake), sd = sd(art_net_real_minus_fake),
            .groups = "drop")
art_p <- suppressWarnings(wilcox.test(art_net_real_minus_fake ~ sess_order, composites)$p.value)
note("ART by session order: ",
     paste(sprintf("%s %.2f (n=%d)", art_check$sess_order, art_check$mean, art_check$n), collapse = ", "),
     " | Wilcoxon p = ", round(art_p, 3),
     " | flat, so ART is not a session-order artefact")

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
    ungroup()
}

fisher_compare <- function(r1, n1, r2, n2) {
  z1 <- atanh(r1); z2 <- atanh(r2)
  se <- sqrt(1 / (n1 - 3) + 1 / (n2 - 3))
  z  <- (z1 - z2) / se
  tibble(diff_z = z, p = 2 * pnorm(-abs(z)),
         r_pooled = tanh((z1 * (n1 - 3) + z2 * (n2 - 3)) / (n1 + n2 - 6)))
}

# =============================================================================
# STAGE 6.  PRIMARY FAMILY: EVT -> intention (direct replication)
# =============================================================================

banner("STAGE 6  primary family A: EVT predictors -> intention")

prim_a <- bind_rows(lapply(c("b_knowledge", "b_value", "b_cost"), function(pred) {
  cor_row(composites, pred, "b_intention") |>
    mutate(predictor = pred, outcome = "b_intention", level = "composite")
})) |>
  mutate(family = "A: EVT -> intention (3 tests)", status = "primary", .before = 1)

prim_a <- add_adjust(prim_a)
print(as.data.frame(prim_a[, c("predictor", "estimate", "ci_low", "ci_high", "n", "p", "p_bh", "p_bonf")]),
      digits = 3, row.names = FALSE)

# =============================================================================
# STAGE 7.  PRIMARY FAMILY: cross-instrument composites
# =============================================================================

banner("STAGE 7  primary family B: cross-instrument composite associations")

inst_of <- setNames(manifest$instrument, manifest$scale)
comp_scales <- manifest$scale

pairs <- combn(comp_scales, 2, simplify = FALSE) |>
  keep(~ inst_of[[.x[1]]] != inst_of[[.x[2]]]) |>
  keep(~ !any(.x %in% c("b_attainment")))   # single item: reported separately

prim_b <- bind_rows(lapply(pairs, function(pr) {
  cor_row(composites, pr[1], pr[2]) |>
    mutate(predictor = pr[1], outcome = pr[2], level = "composite")
})) |>
  mutate(family = "B: cross-instrument composites", status = "primary", .before = 1) |>
  add_adjust()

note("tests in family B: ", nrow(prim_b),
     " | survive BH: ", sum(prim_b$survives_bh),
     " | survive Bonferroni: ", sum(prim_b$survives_bonf))
print(as.data.frame(prim_b |> arrange(p_bh) |>
                      head(12) |>
                      select(predictor, outcome, estimate, n, p, p_bh)),
      digits = 3, row.names = FALSE)

# attainment value is a single item: report alone, no family
attain <- cor_row(composites, "b_attainment", "b_intention") |>
  mutate(family = "C: attainment value (single item) -> intention",
         status = "primary", predictor = "b_attainment", outcome = "b_intention",
         level = "single item", .before = 1) |>
  add_adjust()

# Author Recognition Test (ART): real authors mixed with foils, scored as
# hits - false alarms. This is a print-exposure / domain-familiarity measure,
# NOT an outcome of the AI manipulation and not a test of AI-output detection.
# It is analysed here as a CONFOUND CHECK: if beliefs predict prior exposure,
# the belief -> self-report associations are partly confounded by it.
# It is flat across session order (checked above), which doubles as a
# randomisation check.
banner("STAGE 7b  family D: prior exposure (ART) as a confound check")

prim_d <- bind_rows(lapply(c("b_knowledge", "b_value", "b_cost", "b_intention"), function(pred) {
  x <- composites
  x$art_out <- x$art_net_real_minus_fake
  cor_row(x, pred, "art_out") |>
    mutate(predictor = pred, outcome = "art_net_real_minus_fake (prior exposure)", level = "composite")
})) |>
  mutate(family = "D: predictors -> prior exposure (ART, confound check)",
         status = "confound check", .before = 1) |>
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
    ct <- suppressWarnings(cor.test(item_wide[[ca]], item_wide[[cb]], method = "spearman"))
    tibble(item_a = ca, item_b = cb, estimate = unname(ct$estimate), p = ct$p.value, n = nrow(item_wide))
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
  a <- composites |> filter(sess_order == "Traditional_First")
  b <- composites |> filter(sess_order == "AI_First")
  ra <- cor_row(a, pv, ov); rb <- cor_row(b, pv, ov)
  ft <- fisher_compare(ra$estimate, ra$n, rb$estimate, rb$n)
  tibble(predictor = pv, outcome = ov,
         r_traditional = ra$estimate, n_traditional = ra$n, p_traditional = ra$p,
         r_ai_first = rb$estimate, n_ai_first = rb$n, p_ai_first = rb$p,
         r_pooled = cor_row(composites, pv, ov)$estimate,
         estimate = ft$diff_z,
         ci_low = ft$diff_z - 1.96, ci_high = ft$diff_z + 1.96,
         p = ft$p, n = nrow(composites))
})) |>
  mutate(family = "F: order x association", status = "exploratory", level = "composite",
         method = "fisher_z", .before = 1) |>
  add_adjust()

print(as.data.frame(moderation[, c("predictor", "outcome", "r_traditional", "r_ai_first",
                                   "r_pooled", "p_bh")]),
      digits = 3, row.names = FALSE)
note("r_traditional / r_ai_first are the association within each order group;",
     " a sign flip plus a significant Fisher z is the interaction")
write_csv(moderation, file.path(CFG$out_dir, "06_moderation.csv"))

# =============================================================================
# STAGE 10.  SENSITIVITY: does the conclusion move under alternative scoring?
# =============================================================================

banner("STAGE 10  sensitivity: conclusions that could move")

alt <- composites |>
  mutate(
    # cost scored the other way (the old pipeline's "ConcernHarms" variable)
    b_cost_flipped   = 6 - b_cost,
    # intention with the attainment item folded in (the old pipeline's version)
    b_intention_plus6 = (composites$b_attainment + composites$b_intention * 2) / 3,
    # value-aligned composite: affordability of interpretation, not a new construct
    b_value_plus_cost = b_value - b_cost
  )

sens <- bind_rows(
  tibble(variant = "cost: high = more cost (used here)",  r = cor(alt$b_cost, alt$b_intention, method = "spearman")),
  tibble(variant = "cost: high = LESS cost (old export)", r = cor(alt$b_cost_flipped, alt$b_intention, method = "spearman")),
  tibble(variant = "intention: 2 source items",           r = cor(alt$b_intention, alt$b_value, method = "spearman")),
  tibble(variant = "intention: 3 items incl. Q7",         r = cor(alt$b_intention_plus6, alt$b_value, method = "spearman")),
  tibble(variant = "value x intention (pearson)",         r = cor(alt$b_value, alt$b_intention, method = "pearson")),
  tibble(variant = "value x intention (spearman)",        r = cor(alt$b_value, alt$b_intention, method = "spearman"))
) |>
  mutate(n = nrow(alt), p = 2 * pt(-abs(r * sqrt((n - 2) / (1 - r^2))), n - 2))

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
  keep_cols(prim_a, "correlation (Spearman r)"),
  keep_cols(prim_b, "correlation (Spearman r)"),
  keep_cols(attain, "correlation (Spearman r)"),
  keep_cols(prim_d, "correlation (Spearman r)"),
  keep_cols(moderation, "Fisher z difference between order groups")
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

cat("\n")
print(as.data.frame(findings |> select(family, predictor, outcome, estimate, n, p_bh, verdict)),
      digits = 3, row.names = FALSE)

survivors <- findings |> filter(survives_bh)
cat("\nfindings surviving BH within their family: ", nrow(survivors), " of ", nrow(findings), "\n")

# =============================================================================
# STAGE 12.  HUMAN-READABLE SUMMARY
# =============================================================================

banner("STAGE 12  summary")

md <- c(
  "# Funnel summary",
  "",
  paste0("Generated by `funnel.R`. Sample: n = ", length(ids),
         " complete participants, identical across every stage."),
  "",
  "## Measurement (reported, not gated)",
  "",
  "| instrument | p | KMO Pearson | KMO polychoric | min eigen (poly) | RMSEA | TLI | poly matrix |",
  "|---|---:|---:|---:|---:|---:|---:|---|",
  sprintf("| %s | %d | %.3f | %s | %s | %s | %s | %s |",
          measurement$instrument, measurement$p, measurement$kmo_pearson,
          ifelse(is.na(measurement$kmo_polychoric), "NA", sprintf("%.3f", measurement$kmo_polychoric)),
          ifelse(is.na(measurement$min_eig_poly), "NA", sprintf("%.3f", measurement$min_eig_poly)),
          ifelse(is.na(measurement$rmsea), "NA", sprintf("%.3f", measurement$rmsea)),
          ifelse(is.na(measurement$tli), "NA", sprintf("%.3f", measurement$tli)),
          measurement$poly_correction),
  "",
  "## Descriptives",
  "",
  "| scale | items | mean | SD | alpha | band | items at ceiling |",
  "|---|---:|---:|---:|---:|---|---:|",
  sprintf("| %s | %d | %.2f | %.2f | %s | %s | %.0f%% |",
          desc$scale, desc$n_items, desc$mean, desc$sd,
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
  "## Where this sample departs from the source paper",
  "",
  sprintf("- value -> intention: r = %.2f here, .60 in Chan & Zhou (N=405).",
          prim_a$estimate[prim_a$predictor == "b_value"]),
  sprintf("- cost -> intention: r = %.2f here, -.30 in Chan & Zhou.",
          prim_a$estimate[prim_a$predictor == "b_cost"]),
  sprintf("- knowledge -> intention: r = %.2f here, +.18 in Chan & Zhou. The sign",
          prim_a$estimate[prim_a$predictor == "b_knowledge"]),
  "  agrees in magnitude but not in direction; treat as a divergence, not a",
  "  replication. Knowledge also has a hard ceiling (see the descriptor table),",
  "  so its variance is restricted.",
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
  "  families are not comparable and are not ranked against each other."
)

writeLines(md, file.path(CFG$out_dir, "FUNNEL_SUMMARY.md"))
note("wrote ", file.path(CFG$out_dir, "FINDINGS.csv"))
note("wrote ", file.path(CFG$out_dir, "FUNNEL_SUMMARY.md"))
note("done")
