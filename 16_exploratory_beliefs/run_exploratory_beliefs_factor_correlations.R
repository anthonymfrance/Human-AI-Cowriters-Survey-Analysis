library(tidyverse)
library(psych)

source("scoring_helpers.R")

set.seed(42L)

csv_dir <- file.path("16_exploratory_beliefs", "csv")
dir.create(csv_dir, recursive = TRUE, showWarnings = FALSE)

factor_score_method <- "tenBerge"

safe_cor <- function(df, x, y) {
  d <- df |>
    select(all_of(c(x, y))) |>
    mutate(across(everything(), as.numeric)) |>
    drop_na()

  if (nrow(d) < 5 || sd(d[[x]]) == 0 || sd(d[[y]]) == 0) {
    return(tibble(n = nrow(d), rho = NA_real_, p = NA_real_))
  }

  ct <- suppressWarnings(cor.test(d[[x]], d[[y]], method = "spearman", exact = FALSE))
  tibble(n = nrow(d), rho = unname(ct$estimate), p = ct$p.value)
}

mk_corrs <- function(df, xs, ys, family) {
  crossing(x = xs, y = ys) |>
    mutate(res = map2(x, y, ~ safe_cor(df, .x, .y))) |>
    unnest(res) |>
    mutate(
      abs_rho = abs(rho),
      p_bh = p.adjust(p, "BH"),
      p_bonf = p.adjust(p, "bonferroni"),
      family = family
    ) |>
    arrange(p_bh, desc(abs_rho))
}

score_exploratory_beliefs <- function() {
  bel <- read_csv(
    file.path("02_efa_exports", "efa", "BeliefsAboutAI_EFA_Primary.csv"),
    show_col_types = FALSE
  ) |>
    mutate(score = as.numeric(score), item_id = as.integer(item_num))

  item_text <- bel |>
    distinct(item_id, item_text)

  wide <- bel |>
    filter(item_id %in% 6:22) |>
    select(participant_id, item_id, score) |>
    mutate(item_id = as.character(item_id)) |>
    pivot_wider(names_from = item_id, values_from = score) |>
    arrange(participant_id)

  X <- wide |>
    select(-participant_id) |>
    mutate(across(everything(), as.integer)) |>
    as.data.frame()

  poly <- compute_polychoric_safe(X)

  fa_fit <- suppressWarnings(
    psych::fa(
      r = poly$rho,
      nfactors = 3,
      n.obs = nrow(X),
      fm = "minres",
      rotate = "oblimin"
    )
  )

  factor_order <- factor_order_by_variance(
    fa_fit$loadings,
    context_label = "Beliefs 6-22 factor ordering"
  )

  L_ordered <- unclass(fa_fit$loadings)[, factor_order, drop = FALSE]
  colnames(L_ordered) <- paste0("MR", seq_len(3))

  fa_fit_ordered <- fa_fit
  fa_fit_ordered$loadings <- L_ordered
  class(fa_fit_ordered$loadings) <- c("loadings")

  score_matrix <- psych::factor.scores(
    x = as.matrix(X),
    f = fa_fit_ordered,
    rho = poly$rho,
    method = factor_score_method
  )

  belief_scores <- bind_scores_with_ids(
    participant_ids = wide$participant_id,
    score_matrix = score_matrix$scores,
    context_label = "Beliefs 6-22 factor scores"
  ) |>
    rename(
      Beliefs_UtilityComfort = MR1,
      Beliefs_FutureAIIntent = MR2,
      Beliefs_LowConcern = MR3
    ) |>
    # Items 17-20 were already reverse-scored upstream. Flip this factor so
    # positive correlations read as more concern/harms endorsement.
    mutate(Beliefs_ConcernHarms = -Beliefs_LowConcern) |>
    select(
      participant_id,
      Beliefs_UtilityComfort,
      Beliefs_FutureAIIntent,
      Beliefs_ConcernHarms,
      Beliefs_LowConcern
    )

  loadings_tbl <- as_tibble(L_ordered, rownames = "item_id") |>
    mutate(item_id = as.integer(item_id)) |>
    left_join(item_text, by = "item_id") |>
    relocate(item_id, item_text)

  kmo <- psych::KMO(poly$rho)
  model_summary <- tibble(
    model = "BeliefsAboutAI items 6-22, 3-factor polychoric minres oblimin",
    n = nrow(X),
    kmo = as.numeric(kmo$MSA),
    rmsea = as.numeric(fa_fit$RMSEA[1]),
    tli = as.numeric(fa_fit$TLI),
    rmsr = as.numeric(fa_fit$rms),
    factor_correlation_12 = as.numeric(fa_fit_ordered$Phi[1, 2]),
    factor_correlation_13 = as.numeric(fa_fit_ordered$Phi[1, 3]),
    factor_correlation_23 = as.numeric(fa_fit_ordered$Phi[2, 3]),
    note = "Beliefs_ConcernHarms is sign-flipped from reversed items 17-20 so higher means more concern/harms endorsement."
  )

  write_csv(belief_scores, file.path(csv_dir, "Beliefs_Exploratory_Factor_Scores.csv"))
  write_csv(loadings_tbl, file.path(csv_dir, "Beliefs_Exploratory_Loadings.csv"))
  write_csv(model_summary, file.path(csv_dir, "Beliefs_Exploratory_Model_Summary.csv"))

  list(scores = belief_scores, summary = model_summary, loadings = loadings_tbl)
}

belief_obj <- score_exploratory_beliefs()
belief_scores <- belief_obj$scores
belief_cols <- c(
  "Beliefs_UtilityComfort",
  "Beliefs_FutureAIIntent",
  "Beliefs_ConcernHarms"
)

existing <- read_csv(
  file.path("06_interesting_findings", "csv", "Factor_Scores_All_Instruments.csv"),
  show_col_types = FALSE
)
factor_cols <- setdiff(names(existing), "participant_id")
factor_df <- inner_join(
  existing,
  belief_scores |> select(participant_id, all_of(belief_cols)),
  by = "participant_id"
)
factor_corrs <- mk_corrs(
  factor_df,
  belief_cols,
  factor_cols,
  "beliefs_vs_existing_factors"
) |>
  rename(beliefs_factor = x, other_factor = y)
write_csv(factor_corrs, file.path(csv_dir, "Beliefs_Exploratory_vs_Existing_Factors.csv"))

art <- read_csv(file.path("07_art_vs_all_factors_items", "csv", "ART_Scored.csv"), show_col_types = FALSE)
art_cols <- c(
  "art_total_selected",
  "art_real_hits",
  "art_fake_false_alarms",
  "art_neutral_selected",
  "art_unknown_selected",
  "art_net_real_minus_fake",
  "art_hit_rate",
  "art_false_alarm_rate"
)
art_df <- inner_join(
  art,
  belief_scores |> select(participant_id, all_of(belief_cols)),
  by = "participant_id"
)
art_corrs <- mk_corrs(art_df, art_cols, belief_cols, "art_vs_beliefs_factors") |>
  rename(art_metric = x, beliefs_factor = y)
write_csv(art_corrs, file.path(csv_dir, "ART_vs_Beliefs_Exploratory_Factors.csv"))

q17 <- read_csv(file.path("09_q17_ai_use", "csv", "Q17_Participant_AI_Use_Index.csv"), show_col_types = FALSE)
q17_cols <- c(
  "ai_tools_never_heard_n",
  "ai_tools_heard_n",
  "ai_tools_used_n",
  "ai_tools_regular_n",
  "ai_tools_often_n",
  "ai_use_mean",
  "ai_use_mean_heard_only"
)
q17_df <- inner_join(
  q17,
  belief_scores |> select(participant_id, all_of(belief_cols)),
  by = "participant_id"
)
q17_corrs <- mk_corrs(q17_df, q17_cols, belief_cols, "q17_index_vs_beliefs_factors") |>
  rename(q17_metric = x, beliefs_factor = y)
write_csv(q17_corrs, file.path(csv_dir, "Q17_Index_vs_Beliefs_Exploratory_Factors.csv"))

q17_long <- read_csv(file.path("09_q17_ai_use", "csv", "Q17_Responses_Long.csv"), show_col_types = FALSE) |>
  mutate(use_score = as.numeric(use_score))
q17_bucket <- q17_long |>
  group_by(participant_id) |>
  summarise(
    q17_mean = mean(use_score, na.rm = TRUE),
    q17_p_never = mean(use_score == 1, na.rm = TRUE),
    q17_p_heard_never = mean(use_score == 2, na.rm = TRUE),
    q17_p_rarely = mean(use_score == 3, na.rm = TRUE),
    q17_p_regular = mean(use_score == 4, na.rm = TRUE),
    q17_p_often = mean(use_score == 5, na.rm = TRUE),
    q17_breadth_ge3 = sum(use_score >= 3, na.rm = TRUE),
    q17_breadth_ge4 = sum(use_score >= 4, na.rm = TRUE),
    .groups = "drop"
  )
bucket_cols <- setdiff(names(q17_bucket), "participant_id")
bucket_df <- inner_join(
  q17_bucket,
  belief_scores |> select(participant_id, all_of(belief_cols)),
  by = "participant_id"
)
bucket_corrs <- mk_corrs(bucket_df, bucket_cols, belief_cols, "q17_buckets_vs_beliefs_factors") |>
  rename(q17_metric = x, beliefs_factor = y)
write_csv(bucket_corrs, file.path(csv_dir, "Q17_Buckets_vs_Beliefs_Exploratory_Factors.csv"))

models <- c(
  "ChatGPT (including DALL-E) by OpenAI",
  "Claude by Anthropic",
  "Gemini (formerly Bard) by Google",
  "Copilot (Bing Chat) by Microsoft"
)
model_wide <- q17_long |>
  filter(tool %in% models) |>
  mutate(
    tool_key = case_when(
      str_detect(tool, "ChatGPT") ~ "model_ChatGPT",
      str_detect(tool, "Claude") ~ "model_Claude",
      str_detect(tool, "Gemini") ~ "model_Gemini",
      str_detect(tool, "Copilot") ~ "model_Copilot",
      TRUE ~ tool
    )
  ) |>
  select(participant_id, tool_key, use_score) |>
  pivot_wider(names_from = tool_key, values_from = use_score)
model_cols <- setdiff(names(model_wide), "participant_id")
model_df <- inner_join(
  model_wide,
  belief_scores |> select(participant_id, all_of(belief_cols)),
  by = "participant_id"
)
model_corrs <- mk_corrs(model_df, model_cols, belief_cols, "named_model_use_vs_beliefs_factors") |>
  rename(model = x, beliefs_factor = y)
write_csv(model_corrs, file.path(csv_dir, "Named_Model_Use_vs_Beliefs_Exploratory_Factors.csv"))

top_all <- bind_rows(
  factor_corrs |>
    transmute(source = "existing_factor", predictor = other_factor, beliefs_factor, n, rho, p, p_bh, p_bonf),
  art_corrs |>
    transmute(source = "ART", predictor = art_metric, beliefs_factor, n, rho, p, p_bh, p_bonf),
  q17_corrs |>
    transmute(source = "Q17_index", predictor = q17_metric, beliefs_factor, n, rho, p, p_bh, p_bonf),
  bucket_corrs |>
    transmute(source = "Q17_bucket", predictor = q17_metric, beliefs_factor, n, rho, p, p_bh, p_bonf),
  model_corrs |>
    transmute(source = "named_model", predictor = model, beliefs_factor, n, rho, p, p_bh, p_bonf)
) |>
  mutate(abs_rho = abs(rho)) |>
  arrange(p_bh, desc(abs_rho))
write_csv(top_all, file.path(csv_dir, "Beliefs_Exploratory_All_Correlations_Ranked.csv"))

cat("Wrote exploratory outputs to ", csv_dir, "\n", sep = "")
print(belief_obj$summary)
cat("\nTop correlations by within-family BH:\n")
print(head(top_all, 25), width = Inf)
