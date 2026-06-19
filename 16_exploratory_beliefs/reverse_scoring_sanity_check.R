library(tidyverse)

safe_cor <- function(df, x, y) {
  d <- df |>
    select(all_of(c(x, y))) |>
    drop_na()

  ct <- suppressWarnings(cor.test(d[[x]], d[[y]], method = "spearman", exact = FALSE))
  tibble(x = x, y = y, n = nrow(d), rho = unname(ct$estimate), p = ct$p.value)
}

belief_scores <- read_csv(
  "16_exploratory_beliefs/csv/Beliefs_Exploratory_Factor_Scores.csv",
  show_col_types = FALSE
)
factor_scores <- read_csv(
  "06_interesting_findings/csv/Factor_Scores_All_Instruments.csv",
  show_col_types = FALSE
)

beliefs_long <- read_csv(
  "02_efa_exports/efa/BeliefsAboutAI_EFA_Primary.csv",
  show_col_types = FALSE
) |>
  mutate(score = as.numeric(score), item_num = as.integer(item_num))

beliefs_utility_mean <- beliefs_long |>
  filter(item_num %in% 7:16) |>
  group_by(participant_id) |>
  summarise(Beliefs_UtilityComfort_mean_7_16 = mean(score), .groups = "drop")

imi_long <- read_csv(
  "02_efa_exports/efa/IMI_EFA_Primary.csv",
  show_col_types = FALSE
) |>
  mutate(score = as.numeric(score), item_code = as.integer(item_code))

imi_competence_mean <- imi_long |>
  filter(item_code %in% 8:12) |>
  group_by(participant_id) |>
  summarise(IMI_competence_mean_8_12 = mean(score), .groups = "drop")

sanity_df <- factor_scores |>
  select(participant_id, IMI_MR3) |>
  inner_join(
    belief_scores |> select(participant_id, Beliefs_UtilityComfort),
    by = "participant_id"
  ) |>
  inner_join(beliefs_utility_mean, by = "participant_id") |>
  inner_join(imi_competence_mean, by = "participant_id")

cor_sanity <- bind_rows(
  safe_cor(sanity_df, "Beliefs_UtilityComfort", "Beliefs_UtilityComfort_mean_7_16"),
  safe_cor(sanity_df, "IMI_MR3", "IMI_competence_mean_8_12"),
  safe_cor(sanity_df, "Beliefs_UtilityComfort", "IMI_MR3"),
  safe_cor(sanity_df, "Beliefs_UtilityComfort_mean_7_16", "IMI_competence_mean_8_12"),
  safe_cor(sanity_df, "Beliefs_UtilityComfort", "IMI_competence_mean_8_12"),
  safe_cor(sanity_df, "Beliefs_UtilityComfort_mean_7_16", "IMI_MR3")
)

write_csv(cor_sanity, "16_exploratory_beliefs/csv/Reverse_Scoring_Sanity_Correlations.csv")
print(cor_sanity, n = 20)

rw_col_names <- c(
  "participant number order", "pid", "item_code", "score_raw",
  "qualtrics_qid", "item_subnum", "question_stem",
  "input_type", "input_subtype", "answer_type",
  "question_block", "item_subnum2", "item_text",
  "item_text_full", "submission_status"
)

llm_col_names <- c(
  "participant number order", "pid", "topic", "item_code", "score_raw",
  "qualtrics_qid", "item_subnum", "question_stem",
  "input_type", "input_subtype", "answer_type",
  "question_block", "item_num", "item_text",
  "item_text_full", "response_labeled", "response_label_short",
  "score_numeric", "response_label2", "response_html",
  "question_stem2", "item_text2", "submission_status"
)

raw_beliefs <- read_csv(
  "llm-survey-long-040726.csv",
  skip = 9,
  col_names = llm_col_names,
  show_col_types = FALSE,
  col_types = cols(pid = col_character(), item_num = col_character(), score_raw = col_character())
)

raw_imi <- read_csv(
  "rw-survey-long-040726.csv",
  skip = 9,
  col_names = rw_col_names,
  show_col_types = FALSE,
  col_types = cols(pid = col_character(), item_subnum2 = col_character(), score_raw = col_character())
)

cat("\nKnown participant pi5ub2 Beliefs raw Q2-23 items 17-20:\n")
raw_beliefs |>
  filter(pid == "pi5ub2", question_block == "Q2-23", as.integer(item_num) %in% 17:20) |>
  select(pid, item_num, item_text, score_raw) |>
  head(10) |>
  print(width = Inf)

cat("\nExported scored pi5ub2 Beliefs items 17-20:\n")
beliefs_long |>
  filter(participant_id == "pi5ub2", item_num %in% 17:20) |>
  select(participant_id, item_num, item_text, score) |>
  print(width = Inf)

cat("\nKnown participant pi5ub2 IMI raw reverse items:\n")
raw_imi |>
  filter(pid == "pi5ub2", question_block == "Q1", as.integer(item_subnum2) %in% c(3, 4, 13, 15, 18)) |>
  select(pid, item_subnum2, item_text, score_raw) |>
  head(10) |>
  print(width = Inf)

cat("\nExported scored pi5ub2 IMI reverse items:\n")
imi_long |>
  filter(participant_id == "pi5ub2", item_code %in% c(3, 4, 13, 15, 18)) |>
  select(participant_id, item_code, item_text, score) |>
  print(width = Inf)
