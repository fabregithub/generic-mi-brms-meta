source("00_config.R")
source("00_common_functions.R")

log_msg("============================================================")
log_msg("STEP 4: Posterior summary and forest plots")
log_msg("============================================================")

results_dir  <- meta_spec$output$results_dir %||% "results"
combined     <- readRDS(file.path(results_dir, "combined_draws.rds"))
fit_results  <- readRDS(file.path(results_dir, "meta_fits.rds"))
summary_spec <- meta_spec$summary

valid_fits <- fit_results[!sapply(fit_results, is.null)]
if (length(valid_fits) == 0) stop("No valid fitted models found. Run Step 3 first.")

log_msg("Summarising", length(valid_fits), "model(s).")

pooled_summary <- purrr::map_dfr(
  names(valid_fits),
  function(param) {
    tryCatch(
      summarise_meta_fit(valid_fits[[param]], param, summary_spec),
      error = function(e) {
        log_msg("ERROR summarising", param, ":", conditionMessage(e))
        NULL
      }
    )
  }
)

pub_dir <- file.path(results_dir, "publication")
dir.create(pub_dir, recursive = TRUE, showWarnings = FALSE)

readr::write_csv(pooled_summary, file.path(pub_dir, "pooled_summary.csv"))
log_msg("Wrote pooled_summary.csv")
print(pooled_summary, n = Inf)

# Forest plots
plot_dir <- file.path(pub_dir, "forest_plots")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

purrr::walk(names(valid_fits), function(param) {
  row <- dplyr::filter(pooled_summary, parameter == param)
  if (nrow(row) == 0) return(invisible(NULL))

  p <- make_forest_plot(combined, row, param)

  safe_name <- gsub("[^A-Za-z0-9_]", "_", param)
  plot_path <- file.path(plot_dir, paste0("forest_", safe_name, ".png"))
  ggplot2::ggsave(plot_path, p, width = 7, height = 4, dpi = 150)
  log_msg("  Saved:", plot_path)
})

log_msg("SUCCESS: STEP 4: Posterior summary and forest plots")
