#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
  library(openxlsx)
})

source("scoring_helpers.R")

audit_dir <- file.path("18_composite_correlations", "raw_scoring_audit")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

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

submission_resolution_expected <- tribble(
  ~source, ~question_block, ~expected, ~straight_line_sensitive,
  "rw",    "Q1",            18L,       TRUE,
  "rw",    "Q7",            20L,       TRUE,
  "rw",    "Q9",             1L,       FALSE,
  "llm",   "Q25",           12L,       TRUE,
  "llm",   "Q2-23",         22L,       TRUE
)

read_raw_inputs <- function() {
  rw_raw <- read_csv(
    "rw-survey-long-040726.csv",
    skip = 9,
    col_names = rw_col_names,
    show_col_types = FALSE,
    col_types = cols(
      pid = col_character(),
      question_block = col_character(),
      item_subnum2 = col_character(),
      score_raw = col_character(),
      submission_status = col_character()
    )
  )

  llm_raw <- read_csv(
    "llm-survey-long-040726.csv",
    skip = 9,
    col_names = llm_col_names,
    show_col_types = FALSE,
    col_types = cols(
      `participant number order` = col_character(),
      pid = col_character(),
      question_block = col_character(),
      item_num = col_character(),
      score_raw = col_character(),
      submission_status = col_character()
    )
  )

  llm_raw <- backfill_missing_pid(
    llm_raw,
    respondent_col = "participant number order",
    pid_col = "pid",
    question_block_col = "question_block",
    score_col = "score_raw",
    primary_pid_block = "Q2",
    fallback_pid_block = "Q3",
    context_label = "llm_raw"
  )

  list(rw = rw_raw, llm = llm_raw)
}

read_cleaned_long <- function(instrument, path, item_col) {
  read_csv(path, show_col_types = FALSE) |>
    transmute(
      instrument,
      participant_id,
      item_id = as.integer(.data[[item_col]]),
      observed_cleaned_score = as.numeric(score)
    )
}

numeric_match <- function(expected, observed, tolerance = 1e-10) {
  both_na <- is.na(expected) & is.na(observed)
  both_na | (!is.na(expected) & !is.na(observed) & abs(expected - observed) <= tolerance)
}

make_raw_expected_scores <- function(raw_inputs) {
  rw_resolution <- resolve_best_submission(
    raw_inputs$rw,
    "rw",
    submission_resolution_expected
  )
  llm_resolution <- resolve_best_submission(
    raw_inputs$llm,
    "llm",
    submission_resolution_expected
  )

  rw_best <- rw_resolution$best_data
  llm_best <- llm_resolution$best_data

  verified_triage_path <- file.path("01_audit_cleaning", "audit", "Triage_Rap_Sheet_Verified.csv")
  verified_triage <- if (file.exists(verified_triage_path)) {
    read_csv(verified_triage_path, show_col_types = FALSE)
  } else {
    tibble(pid = character(), verified_recommendation = character())
  }

  rw_efa_override_pids <- verified_triage |>
    filter(str_detect(verified_recommendation, fixed("manual override to first-dup submission"))) |>
    pull(pid)

  rw_efa_source <- rw_best |>
    filter(!pid %in% rw_efa_override_pids) |>
    bind_rows(
      raw_inputs$rw |>
        filter(
          pid %in% rw_efa_override_pids,
          submission_status == "first-dup"
        )
    )

  strict_expected <- bind_rows(
    rw_best |>
      filter(question_block == "Q1") |>
      transmute(
        instrument = "IMI",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_subnum2, "item_subnum2", "raw IMI"),
        raw_score = as.numeric(score_raw),
        expected_cleaned_score = score_imi_items(item_id, raw_score),
        selected_submission_status = submission_status,
        raw_source_for_expected = "rw_best"
      ),
    rw_best |>
      filter(question_block == "Q7") |>
      transmute(
        instrument = "WritingEfficacy",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_subnum2, "item_subnum2", "raw WritingEfficacy"),
        raw_score = as.numeric(score_raw),
        expected_cleaned_score = raw_score,
        selected_submission_status = submission_status,
        raw_source_for_expected = "rw_best"
      ),
    llm_best |>
      filter(question_block == "Q25") |>
      transmute(
        instrument = "AIReflection",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_num, "item_num", "raw AIReflection"),
        raw_score = parse_number(score_raw),
        expected_cleaned_score = raw_score,
        selected_submission_status = submission_status,
        raw_source_for_expected = "llm_best"
      ),
    llm_best |>
      filter(question_block == "Q2-23") |>
      transmute(
        instrument = "BeliefsAboutAI",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_num, "item_num", "raw BeliefsAboutAI"),
        raw_score = parse_number(score_raw),
        expected_cleaned_score = score_beliefs_items(item_id, raw_score),
        selected_submission_status = submission_status,
        raw_source_for_expected = "llm_best"
      )
  )

  primary_expected <- bind_rows(
    rw_efa_source |>
      filter(question_block == "Q1") |>
      transmute(
        instrument = "IMI",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_subnum2, "item_subnum2", "raw primary IMI"),
        raw_score = as.numeric(score_raw),
        expected_cleaned_score = score_imi_items(item_id, raw_score),
        selected_submission_status = submission_status,
        raw_source_for_expected = if_else(
          participant_id %in% rw_efa_override_pids,
          "rw_first_dup_manual_override",
          "rw_best"
        )
      ),
    rw_efa_source |>
      filter(question_block == "Q7") |>
      transmute(
        instrument = "WritingEfficacy",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_subnum2, "item_subnum2", "raw primary WritingEfficacy"),
        raw_score = as.numeric(score_raw),
        expected_cleaned_score = raw_score,
        selected_submission_status = submission_status,
        raw_source_for_expected = if_else(
          participant_id %in% rw_efa_override_pids,
          "rw_first_dup_manual_override",
          "rw_best"
        )
      ),
    llm_best |>
      filter(question_block == "Q25") |>
      transmute(
        instrument = "AIReflection",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_num, "item_num", "raw primary AIReflection"),
        raw_score = parse_number(score_raw),
        expected_cleaned_score = raw_score,
        selected_submission_status = submission_status,
        raw_source_for_expected = "llm_best"
      ),
    llm_best |>
      filter(question_block == "Q2-23") |>
      transmute(
        instrument = "BeliefsAboutAI",
        participant_id = as.character(pid),
        item_id = parse_integer_item_field(item_num, "item_num", "raw primary BeliefsAboutAI"),
        raw_score = parse_number(score_raw),
        expected_cleaned_score = score_beliefs_items(item_id, raw_score),
        selected_submission_status = submission_status,
        raw_source_for_expected = "llm_best"
      )
  )

  list(
    strict_expected = strict_expected,
    primary_expected = primary_expected,
    submission_resolution_audit = bind_rows(
      rw_resolution$resolution_audit,
      llm_resolution$resolution_audit
    )
  )
}

audit_cleaned_exports <- function(expected_scores) {
  cleaned_long <- bind_rows(
    read_cleaned_long("IMI", file.path("01_audit_cleaning", "cleaned", "IMI_cleaned.csv"), "item_code"),
    read_cleaned_long("WritingEfficacy", file.path("01_audit_cleaning", "cleaned", "WritingEfficacy_cleaned.csv"), "item_code"),
    read_cleaned_long("AIReflection", file.path("01_audit_cleaning", "cleaned", "AI_Reflection_cleaned.csv"), "item_num"),
    read_cleaned_long("BeliefsAboutAI", file.path("02_efa_exports", "efa", "BeliefsAboutAI_EFA_Primary.csv"), "item_num")
  )

  expected_scores$primary_expected |>
    semi_join(cleaned_long, by = c("instrument", "participant_id", "item_id")) |>
    right_join(
      cleaned_long,
      by = c("instrument", "participant_id", "item_id")
    ) |>
    mutate(
      audit_status = case_when(
        is.na(expected_cleaned_score) & !is.na(observed_cleaned_score) ~ "missing_raw_expected",
        numeric_match(expected_cleaned_score, observed_cleaned_score) ~ "pass",
        TRUE ~ "score_mismatch"
      ),
      difference = observed_cleaned_score - expected_cleaned_score
    )
}

make_expected_analysis_scores <- function(cleaned_audit) {
  cleaned_audit |>
    filter(audit_status == "pass") |>
    select(
      instrument,
      participant_id,
      item_id,
      raw_score,
      expected_cleaned_score,
      raw_source_for_expected,
      selected_submission_status
    ) |>
    mutate(
      analysis_score = if_else(
        instrument == "WritingEfficacy",
        (expected_cleaned_score / 25) + 1,
        expected_cleaned_score
      )
    )
}

audit_composite_scores <- function(cleaned_audit) {
  membership <- read_csv(
    file.path("17_composite_scoring", "csv", "Composite_Item_Membership.csv"),
    show_col_types = FALSE
  ) |>
    transmute(
      instrument,
      item_id = as.integer(item_id),
      factor
    )

  expected_analysis <- make_expected_analysis_scores(cleaned_audit)

  expected_composites <- expected_analysis |>
    inner_join(membership, by = c("instrument", "item_id")) |>
    group_by(participant_id, factor) |>
    summarise(
      expected_composite_score = mean(analysis_score, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      expected_composite_score = if_else(
        factor == "Beliefs_ConcernHarms",
        6 - expected_composite_score,
        expected_composite_score
      )
    )

  observed_composites <- read_csv(
    file.path("17_composite_scoring", "csv", "Composite_Scores_Wide.csv"),
    show_col_types = FALSE
  ) |>
    pivot_longer(-participant_id, names_to = "factor", values_to = "observed_composite_score")

  expected_composites |>
    right_join(observed_composites, by = c("participant_id", "factor")) |>
    mutate(
      audit_status = case_when(
        is.na(expected_composite_score) & !is.na(observed_composite_score) ~ "missing_raw_expected",
        numeric_match(expected_composite_score, observed_composite_score) ~ "pass",
        TRUE ~ "score_mismatch"
      ),
      difference = observed_composite_score - expected_composite_score
    )
}

audit_workbook_items <- function(cleaned_audit) {
  workbook_path <- file.path("18_composite_workbook", "Composite_Workbook.xlsx")
  if (!file.exists(workbook_path)) {
    return(tibble(
      instrument = character(),
      participant_id = character(),
      item_id = integer(),
      raw_score = numeric(),
      expected_workbook_score = numeric(),
      observed_workbook_score = numeric(),
      audit_status = character(),
      difference = numeric()
    ))
  }

  membership <- read_csv(
    file.path("17_composite_scoring", "csv", "Composite_Item_Membership.csv"),
    show_col_types = FALSE
  ) |>
    transmute(
      instrument,
      item_id = as.integer(item_id),
      factor,
      item_text = str_squish(item_text),
      item_reference = paste0(instrument, " Q", item_id)
    )

  workbook <- openxlsx::read.xlsx(workbook_path, sheet = "Participant Scores", sep.names = " ")

  workbook_long <- workbook |>
    pivot_longer(
      -participant_id,
      names_to = "workbook_column",
      values_to = "observed_workbook_score"
    ) |>
    mutate(
      observed_workbook_score = suppressWarnings(as.numeric(observed_workbook_score))
    )

  item_columns <- membership |>
    rowwise() |>
    mutate(
      workbook_column = list(names(workbook)[
        str_detect(names(workbook), fixed(item_text)) &
          str_detect(names(workbook), fixed(item_reference))
      ]),
      n_matching_workbook_columns = length(workbook_column)
    ) |>
    unnest_longer(workbook_column, values_to = "workbook_column", keep_empty = TRUE) |>
    ungroup()

  expected_workbook <- make_expected_analysis_scores(cleaned_audit) |>
    inner_join(item_columns, by = c("instrument", "item_id")) |>
    mutate(
      expected_workbook_score = case_when(
        factor == "Beliefs_ConcernHarms" ~ 6 - expected_cleaned_score,
        TRUE ~ analysis_score
      )
    )

  expected_workbook |>
    right_join(
      workbook_long,
      by = c("participant_id", "workbook_column")
    ) |>
    filter(!is.na(instrument)) |>
    mutate(
      audit_status = case_when(
        is.na(workbook_column) ~ "missing_workbook_column",
        n_matching_workbook_columns != 1L ~ "ambiguous_workbook_column",
        is.na(expected_workbook_score) & !is.na(observed_workbook_score) ~ "missing_raw_expected",
        numeric_match(expected_workbook_score, observed_workbook_score) ~ "pass",
        TRUE ~ "score_mismatch"
      ),
      difference = observed_workbook_score - expected_workbook_score
    ) |>
    select(
      instrument,
      participant_id,
      item_id,
      item_text,
      factor,
      raw_score,
      expected_cleaned_score,
      expected_workbook_score,
      observed_workbook_score,
      workbook_column,
      audit_status,
      difference,
      raw_source_for_expected,
      selected_submission_status
    )
}

summarise_audit <- function(df, audit_name) {
  df |>
    count(audit_status, name = "n") |>
    mutate(audit = audit_name, .before = 1)
}

raw_inputs <- read_raw_inputs()
expected_scores <- make_raw_expected_scores(raw_inputs)

cleaned_audit <- audit_cleaned_exports(expected_scores)
composite_audit <- audit_composite_scores(cleaned_audit)
workbook_audit <- audit_workbook_items(cleaned_audit)

summary_audit <- bind_rows(
  summarise_audit(cleaned_audit, "raw_to_cleaned_item_exports"),
  summarise_audit(composite_audit, "raw_to_composite_scores"),
  summarise_audit(workbook_audit, "raw_to_workbook_item_cells")
)

write_csv(
  expected_scores$submission_resolution_audit,
  file.path(audit_dir, "Submission_Resolution_Audit_From_Raw.csv")
)
write_csv(
  cleaned_audit |> filter(audit_status != "pass"),
  file.path(audit_dir, "Raw_To_Cleaned_Item_Mismatches.csv")
)
write_csv(
  composite_audit |> filter(audit_status != "pass"),
  file.path(audit_dir, "Raw_To_Composite_Score_Mismatches.csv")
)
write_csv(
  workbook_audit |> filter(audit_status != "pass"),
  file.path(audit_dir, "Raw_To_Workbook_Item_Mismatches.csv")
)
write_csv(
  summary_audit,
  file.path(audit_dir, "Raw_Scoring_Audit_Summary.csv")
)

print(summary_audit)

failed <- summary_audit |>
  filter(audit_status != "pass", n > 0)

if (nrow(failed) > 0) {
  stop(
    paste0(
      "Raw scoring audit found mismatches. See ",
      file.path(audit_dir, "Raw_Scoring_Audit_Summary.csv")
    ),
    call. = FALSE
  )
}

message("Raw scoring audit passed. Outputs written to ", audit_dir)
