# Shared reverse-scoring rules for analysis-ready survey outputs.
# NOTE: item numbers here are original Qualtrics numbers (including screening item).
# Screening item excluded upstream in 01_audit_cleaning.qmd before Final_Master_Wide.csv
# is written — Qualtrics items 17-20 map to analysis columns Beliefs_16 through Beliefs_19.
# Reversal is applied once in 01_audit_cleaning.qmd. Do NOT re-reverse in downstream scripts.

imi_reverse_items <- c(3L, 4L, 13L, 15L, 18L)
beliefs_reverse_items <- c(17L, 18L, 19L, 20L)

score_imi_items <- function(item_code, score_raw_num) {
  ifelse(item_code %in% imi_reverse_items, 8 - score_raw_num, score_raw_num)
}

score_beliefs_items <- function(item_num, score_raw_num) {
  ifelse(item_num %in% beliefs_reverse_items, 6 - score_raw_num, score_raw_num)
}

compute_polychoric_safe <- function(X_int_df) {
  unsmoothed <- tryCatch(
    suppressWarnings(
      psych::polychoric(X_int_df, global = FALSE, smooth = FALSE, correct = 0)
    ),
    error = function(e) NULL
  )

  unsmoothed_ok <- !is.null(unsmoothed) &&
    is.matrix(unsmoothed$rho) &&
    all(is.finite(unsmoothed$rho))

  min_eigen_unsmoothed <- if (unsmoothed_ok) {
    min(eigen(unsmoothed$rho, symmetric = TRUE, only.values = TRUE)$values)
  } else {
    NA_real_
  }

  repair_needed <- !unsmoothed_ok ||
    is.na(min_eigen_unsmoothed) ||
    min_eigen_unsmoothed <= 1e-8

  if (!repair_needed) {
    return(list(
      rho                  = unsmoothed$rho,
      repair_needed        = FALSE,
      min_eigen_unsmoothed = min_eigen_unsmoothed
    ))
  }

  smoothed <- suppressWarnings(
    psych::polychoric(X_int_df, global = FALSE, smooth = TRUE, correct = 0)
  )

  list(
    rho                  = smoothed$rho,
    repair_needed        = TRUE,
    min_eigen_unsmoothed = min_eigen_unsmoothed
  )
}

status_fallback_rank <- function(status) {
  dplyr::case_when(
    status == "unique"     ~ 1L,
    status == "second-dup" ~ 2L,
    status == "first-dup"  ~ 3L,
    status == "incomplete" ~ 4L,
    TRUE                   ~ 5L
  )
}

resolve_best_submission <- function(df, source_label, submission_resolution_expected) {
  target_config <- submission_resolution_expected |>
    dplyr::filter(source == source_label) |>
    dplyr::select(question_block, expected, straight_line_sensitive)

  candidate_block_audit <- df |>
    dplyr::filter(!is.na(pid), !is.na(submission_status)) |>
    dplyr::group_by(pid, submission_status, question_block) |>
    dplyr::summarise(
      total_rows       = dplyr::n(),
      valid_responses  = sum(!is.na(score_raw)),
      n_distinct_vals  = dplyr::n_distinct(score_raw, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::left_join(target_config, by = "question_block") |>
    dplyr::mutate(
      is_target_block = !is.na(expected),
      straight_line = is_target_block &
        straight_line_sensitive &
        valid_responses == expected &
        n_distinct_vals == 1L,
      complete_target_block = is_target_block & valid_responses == expected,
      clean_target_block = complete_target_block & !straight_line,
      fallback_rank = status_fallback_rank(submission_status)
    )

  candidate_summary <- candidate_block_audit |>
    dplyr::group_by(pid, submission_status) |>
    dplyr::summarise(
      clean_target_blocks    = sum(clean_target_block, na.rm = TRUE),
      complete_target_blocks = sum(complete_target_block, na.rm = TRUE),
      straight_target_blocks = sum(straight_line, na.rm = TRUE),
      valid_target_total     = sum(dplyr::if_else(is_target_block, valid_responses, 0L)),
      total_valid_all        = sum(valid_responses),
      fallback_rank          = dplyr::first(fallback_rank),
      .groups = "drop"
    ) |>
    dplyr::group_by(pid) |>
    dplyr::mutate(
      observed_submission_count = dplyr::n(),
      observed_status_pattern = stringr::str_c(sort(submission_status), collapse = "; ")
    ) |>
    dplyr::arrange(
      dplyr::desc(clean_target_blocks),
      dplyr::desc(valid_target_total),
      straight_target_blocks,
      dplyr::desc(complete_target_blocks),
      dplyr::desc(total_valid_all),
      fallback_rank,
      .by_group = TRUE
    ) |>
    dplyr::mutate(selection_rank = dplyr::row_number()) |>
    dplyr::ungroup()

  selected_statuses <- candidate_summary |>
    dplyr::filter(selection_rank == 1L) |>
    dplyr::transmute(
      pid,
      selected_submission_status = submission_status
    )

  best_data <- df |>
    dplyr::inner_join(selected_statuses, by = "pid") |>
    dplyr::filter(submission_status == selected_submission_status) |>
    dplyr::select(-selected_submission_status)

  resolution_audit <- candidate_summary |>
    dplyr::mutate(
      source = source_label,
      selected = selection_rank == 1L
    ) |>
    dplyr::relocate(
      source, pid, submission_status, selected, selection_rank,
      observed_submission_count, observed_status_pattern
    ) |>
    dplyr::arrange(source, dplyr::desc(selected), pid, fallback_rank)

  list(
    best_data = best_data,
    resolution_audit = resolution_audit
  )
}

parse_integer_item_field <- function(x, field_name, context_label) {
  x_chr <- as.character(x)
  out <- suppressWarnings(as.integer(x_chr))

  invalid_mask <- !is.na(x_chr) & !grepl("^-?\\d+$", trimws(x_chr))
  if (any(invalid_mask)) {
    bad_vals <- unique(x_chr[invalid_mask])
    stop(
      sprintf(
        "%s: non-integer values found in %s: %s",
        context_label,
        field_name,
        paste(head(bad_vals, 10), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  introduced_na_mask <- !is.na(x_chr) & is.na(out)
  if (any(introduced_na_mask)) {
    bad_vals <- unique(x_chr[introduced_na_mask])
    stop(
      sprintf(
        "%s: integer parsing introduced NA in %s for values: %s",
        context_label,
        field_name,
        paste(head(bad_vals, 10), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out
}

assert_unique_pid_rows <- function(df, pid_col = "pid", context_label = "Data") {
  pid_sym <- rlang::sym(pid_col)
  dupes <- df |>
    dplyr::filter(!is.na(!!pid_sym)) |>
    dplyr::count(!!pid_sym, name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(dupes) > 0) {
    stop(
      sprintf(
        "%s: duplicate %s values found (%d duplicates): %s",
        context_label,
        pid_col,
        nrow(dupes),
        paste(head(dupes[[pid_col]], 10), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_required_columns <- function(df, required_cols, context_label = "Data") {
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop(
      sprintf(
        "%s: missing required columns: %s",
        context_label,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

normalize_missing_text <- function(x) {
  out <- as.character(x)
  out <- stringr::str_replace_all(out, "\\u00A0", " ")
  out <- stringr::str_squish(out)
  out[out == ""] <- NA_character_
  out
}

backfill_missing_pid <- function(
  df,
  respondent_col,
  pid_col = "pid",
  question_block_col = "question_block",
  score_col = "score_raw",
  primary_pid_block = "Q2",
  fallback_pid_block = "Q3",
  context_label = "Data"
) {
  assert_required_columns(
    df,
    c(respondent_col, pid_col, question_block_col, score_col),
    context_label
  )

  pid_sym <- rlang::sym(pid_col)

  normalized <- df |>
    dplyr::mutate(
      !!pid_sym := normalize_missing_text(.data[[pid_col]]),
      `..respondent_key` = .data[[respondent_col]],
      `..question_block` = .data[[question_block_col]],
      `..score_raw` = normalize_missing_text(.data[[score_col]])
    )

  pid_candidates <- normalized |>
    dplyr::filter(
      `..question_block` %in% c(primary_pid_block, fallback_pid_block),
      !is.na(`..score_raw`)
    ) |>
    dplyr::mutate(
      `..candidate_rank` = dplyr::case_when(
        `..question_block` == primary_pid_block ~ 1L,
        `..question_block` == fallback_pid_block ~ 2L,
        TRUE ~ 3L
      )
    )

  conflicting_candidates <- pid_candidates |>
    dplyr::distinct(`..respondent_key`, `..question_block`, `..score_raw`) |>
    dplyr::count(`..respondent_key`, `..question_block`, name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(conflicting_candidates) > 0) {
    stop(
      sprintf(
        "%s: conflicting pid backfill candidates detected in %s/%s rows.",
        context_label,
        respondent_col,
        question_block_col
      ),
      call. = FALSE
    )
  }

  pid_lookup <- pid_candidates |>
    dplyr::arrange(`..respondent_key`, `..candidate_rank`) |>
    dplyr::group_by(`..respondent_key`) |>
    dplyr::summarise(`..pid_backfill` = dplyr::first(`..score_raw`), .groups = "drop")

  missing_before <- sum(is.na(normalized[[pid_col]]))

  out <- normalized |>
    dplyr::left_join(pid_lookup, by = "..respondent_key") |>
    dplyr::mutate(
      !!pid_sym := dplyr::coalesce(.data[[pid_col]], `..pid_backfill`)
    ) |>
    dplyr::select(-`..respondent_key`, -`..question_block`, -`..score_raw`, -`..pid_backfill`)

  attr(out, "pid_backfill_recovered") <- missing_before - sum(is.na(out[[pid_col]]))
  attr(out, "pid_backfill_remaining_missing") <- sum(is.na(out[[pid_col]]))
  out
}

assert_no_missing_values <- function(df, cols, context_label = "Data") {
  assert_required_columns(df, cols, context_label)
  missing_cols <- cols[purrr::map_lgl(cols, ~ any(is.na(df[[.x]])))]
  if (length(missing_cols) > 0) {
    stop(
      sprintf(
        "%s: missing values detected in columns: %s",
        context_label,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_unique_key_rows <- function(df, key_cols, context_label = "Data") {
  assert_required_columns(df, key_cols, context_label)
  dupes <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(key_cols)), name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(dupes) > 0) {
    stop(
      sprintf(
        "%s: duplicate key rows detected for %s",
        context_label,
        paste(key_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_expected_count <- function(actual, expected, context_label = "Count check") {
  if (!identical(as.integer(actual), as.integer(expected))) {
    stop(
      sprintf("%s: expected %s, observed %s", context_label, expected, actual),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_row_count_unchanged <- function(before_n, after_n, context_label = "Row count check") {
  if (!identical(as.integer(before_n), as.integer(after_n))) {
    stop(
      sprintf("%s: row count changed from %s to %s", context_label, before_n, after_n),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_identical_pid_sets <- function(pid_sets, context_label = "PID set check") {
  if (length(pid_sets) < 2L) {
    return(invisible(TRUE))
  }

  base_name <- names(pid_sets)[1]
  base_vals <- sort(unique(as.character(pid_sets[[1]])))

  for (nm in names(pid_sets)[-1]) {
    cur_vals <- sort(unique(as.character(pid_sets[[nm]])))
    missing_from_cur <- setdiff(base_vals, cur_vals)
    extra_in_cur <- setdiff(cur_vals, base_vals)

    if (length(missing_from_cur) > 0 || length(extra_in_cur) > 0) {
      stop(
        sprintf(
          "%s: %s vs %s mismatch. Missing in %s: %s | Extra in %s: %s",
          context_label,
          base_name,
          nm,
          nm,
          paste(head(missing_from_cur, 20), collapse = ", "),
          nm,
          paste(head(extra_in_cur, 20), collapse = ", ")
        ),
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

assert_expected_counts <- function(observed_tbl, expected_tbl, key_col = "instrument", context_label = "Count check") {
  observed <- observed_tbl |>
    dplyr::arrange(.data[[key_col]])
  expected <- expected_tbl |>
    dplyr::arrange(.data[[key_col]])

  joined <- observed |>
    dplyr::full_join(expected, by = key_col, suffix = c("_observed", "_expected"))

  count_cols <- setdiff(names(observed), key_col)
  mismatch <- purrr::map_lgl(seq_len(nrow(joined)), function(i) {
    row <- joined[i, ]
    any(purrr::map_lgl(count_cols, function(col) {
      obs <- row[[paste0(col, "_observed")]]
      exp <- row[[paste0(col, "_expected")]]
      is.na(obs) || is.na(exp) || as.numeric(obs) != as.numeric(exp)
    }))
  })

  if (any(mismatch)) {
    mismatch_rows <- joined[mismatch, ]
    stop(
      sprintf(
        "%s failed. Mismatched rows:\n%s",
        context_label,
        paste(capture.output(print(mismatch_rows)), collapse = "\n")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_nonempty_df <- function(df, context_label = "Data") {
  if (nrow(df) == 0L) {
    stop(sprintf("%s: object has 0 rows", context_label), call. = FALSE)
  }

  invisible(TRUE)
}

assert_allowed_values <- function(x, allowed_values, context_label = "Value check", allow_na = FALSE) {
  observed <- unique(as.character(x))
  observed <- observed[!is.na(observed)]
  invalid <- setdiff(observed, as.character(allowed_values))

  if (length(invalid) > 0L) {
    stop(
      sprintf(
        "%s: unexpected values found: %s",
        context_label,
        paste(head(invalid, 20), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (!allow_na && any(is.na(x))) {
    stop(sprintf("%s: missing values are not allowed", context_label), call. = FALSE)
  }

  invisible(TRUE)
}

derive_order_from_conditions <- function(condition_1, condition_2, context_label = "Order derivation") {
  bad_mask <- !(
    (condition_1 == "Alone" & condition_2 == "LLM") |
      (condition_1 == "LLM" & condition_2 == "Alone")
  )

  if (any(bad_mask, na.rm = TRUE) || any(is.na(condition_1)) || any(is.na(condition_2))) {
    stop(
      sprintf(
        "%s: invalid condition_1/condition_2 combinations detected",
        context_label
      ),
      call. = FALSE
    )
  }

  factor(
    dplyr::if_else(condition_1 == "Alone", "Traditional_First", "AI_First"),
    levels = c("Traditional_First", "AI_First")
  )
}

bind_scores_with_ids <- function(participant_ids, score_matrix, context_label = "Score binding") {
  id_tbl <- tibble::tibble(
    participant_id = as.character(participant_ids),
    .row_id = seq_along(participant_ids)
  )
  score_tbl <- tibble::as_tibble(score_matrix, .name_repair = "minimal") |>
    dplyr::mutate(.row_id = seq_len(dplyr::n()))

  assert_row_count_unchanged(
    nrow(id_tbl),
    nrow(score_tbl),
    paste0(context_label, ": participant/score row count")
  )

  out <- id_tbl |>
    dplyr::inner_join(score_tbl, by = ".row_id") |>
    dplyr::select(-.row_id)

  assert_row_count_unchanged(
    nrow(id_tbl),
    nrow(out),
    paste0(context_label, ": explicit row-index join")
  )
  assert_unique_pid_rows(out, "participant_id", paste0(context_label, ": participant_id"))

  out
}

assert_factor_id_format <- function(x, context_label = "factor_id check") {
  x_chr <- as.character(x)
  invalid <- unique(x_chr[!is.na(x_chr) & !grepl("^F\\d+$", x_chr)])

  if (length(invalid) > 0L) {
    stop(
      sprintf(
        "%s: invalid factor_id values found: %s",
        context_label,
        paste(head(invalid, 20), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

factor_order_by_variance <- function(loadings_matrix, context_label = "Factor ordering") {
  L <- as.matrix(loadings_matrix)

  if (is.null(dim(L))) {
    L <- matrix(L, ncol = 1L)
  }

  if (!is.numeric(L) || ncol(L) == 0L) {
    stop(sprintf("%s: loadings matrix must have at least one numeric factor column", context_label), call. = FALSE)
  }

  order(colSums(L^2, na.rm = TRUE), decreasing = TRUE)
}

assert_complete_factor_name_map <- function(factor_lookup, factor_name_map, context_label = "Factor name map") {
  assert_required_columns(
    factor_lookup,
    c("instrument", "factor_num"),
    paste0(context_label, " factor_lookup")
  )
  assert_required_columns(
    factor_name_map,
    c("instrument", "factor_num", "proposed_name"),
    paste0(context_label, " factor_name_map")
  )

  dupes <- factor_name_map |>
    dplyr::count(instrument, factor_num, name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(dupes) > 0L) {
    stop(
      sprintf(
        "%s: duplicate instrument/factor_num rows found: %s",
        context_label,
        paste(sprintf("%s F%d", dupes$instrument, dupes$factor_num), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  bad_names <- factor_name_map |>
    dplyr::filter(is.na(proposed_name) | trimws(proposed_name) == "")

  if (nrow(bad_names) > 0L) {
    stop(
      sprintf(
        "%s: blank proposed_name values found for %s",
        context_label,
        paste(sprintf("%s F%d", bad_names$instrument, bad_names$factor_num), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  missing_rows <- factor_lookup |>
    dplyr::distinct(instrument, factor_num) |>
    dplyr::anti_join(
      factor_name_map |> dplyr::distinct(instrument, factor_num),
      by = c("instrument", "factor_num")
    )

  if (nrow(missing_rows) > 0L) {
    stop(
      sprintf(
        "%s: missing factor_name_map rows for %s",
        context_label,
        paste(sprintf("%s F%d", missing_rows$instrument, missing_rows$factor_num), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_lookup_covers_factor_columns <- function(factor_lookup, factor_cols, context_label = "Factor lookup coverage") {
  assert_required_columns(
    factor_lookup,
    c("factor", "display_label"),
    context_label
  )

  dupes <- factor_lookup |>
    dplyr::count(factor, name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(dupes) > 0L) {
    stop(
      sprintf(
        "%s: duplicate factor rows found: %s",
        context_label,
        paste(dupes$factor, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  missing_cols <- setdiff(factor_cols, factor_lookup$factor)
  if (length(missing_cols) > 0L) {
    stop(
      sprintf(
        "%s: missing lookup rows for factor columns: %s",
        context_label,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  blank_labels <- factor_lookup |>
    dplyr::filter(is.na(display_label) | trimws(display_label) == "")

  if (nrow(blank_labels) > 0L) {
    stop(
      sprintf(
        "%s: blank display_label values found for factors: %s",
        context_label,
        paste(blank_labels$factor, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}
