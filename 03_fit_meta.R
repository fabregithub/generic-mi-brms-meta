source("00_config.R")
source("00_common_functions.R")

log_msg("============================================================")
log_msg("STEP 3: Fit per-parameter meta-analysis models")
log_msg("============================================================")

results_dir <- meta_spec$output$results_dir %||% "results"
combined    <- readRDS(file.path(results_dir, "combined_draws.rds"))

parameters <- sort(unique(combined$parameter))
log_msg("Parameters to meta-analyse:", paste(parameters, collapse = ", "))

fit_results <- purrr::map(parameters, function(param) {
  draws_param <- dplyr::filter(combined, parameter == param)
  tryCatch(
    fit_meta_one(
      draws_param  = draws_param,
      param_name   = param,
      model_spec   = meta_spec$model,
      results_dir  = results_dir
    ),
    error = function(e) {
      log_msg("ERROR fitting", param, ":", conditionMessage(e))
      NULL
    }
  )
})
names(fit_results) <- parameters

n_ok   <- sum(!sapply(fit_results, is.null))
n_fail <- sum( sapply(fit_results, is.null))
log_msg(sprintf("Fitted %d / %d models successfully", n_ok, length(parameters)))
if (n_fail > 0) log_msg("Failed:", paste(parameters[sapply(fit_results, is.null)], collapse = ", "))

saveRDS(
  fit_results,
  file.path(results_dir, "meta_fits.rds"),
  compress = FALSE
)
log_msg("Saved meta_fits.rds")

log_msg("SUCCESS: STEP 3: Fit per-parameter meta-analysis models")
