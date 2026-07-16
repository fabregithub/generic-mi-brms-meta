source("00_config.R")
source("00_common_functions.R")

log_msg("============================================================")
log_msg("STEP 2: Combine cohort draws")
log_msg("============================================================")

combined <- combine_cohort_draws(
  cohorts       = meta_spec$cohorts,
  parameter_map = meta_spec$parameter_map,
  parameters    = meta_spec$parameters
)

n_cohorts <- dplyr::n_distinct(combined$cohort_id)
n_params  <- dplyr::n_distinct(combined$parameter)
n_rows    <- nrow(combined)

log_msg(sprintf("Combined: %d cohorts × %d parameters = %d rows", n_cohorts, n_params, n_rows))

combined %>%
  dplyr::count(cohort_id, cohort_label, parameter, imputation) %>%
  dplyr::group_by(cohort_id, parameter) %>%
  dplyr::summarise(
    m        = dplyr::n_distinct(imputation),
    n_draws  = sum(n),
    .groups  = "drop"
  ) %>%
  dplyr::arrange(parameter, cohort_id) %>%
  print(n = Inf)

dir.create(meta_spec$output$results_dir %||% "results", recursive = TRUE, showWarnings = FALSE)

saveRDS(
  combined,
  file.path(meta_spec$output$results_dir %||% "results", "combined_draws.rds"),
  compress = FALSE
)
log_msg("Saved combined_draws.rds")

log_msg("SUCCESS: STEP 2: Combine cohort draws")
