# ============================================================
# 00_common_functions.R — shared helpers for the meta-analysis pipeline
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(tibble)
  library(tidyr)
  library(brms)
  library(posterior)
  library(ggplot2)
  library(jsonlite)
  library(glue)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

log_msg <- function(...) {
  message(paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., sep = " ")))
}

# ------------------------------------------------------------------
# Load and validate a cohort draws file (.rds or .csv)
# ------------------------------------------------------------------
load_cohort_draws <- function(file) {
  if (!file.exists(file)) stop("File not found: ", file)
  if (grepl("\\.rds$", file, ignore.case = TRUE)) {
    readRDS(file)
  } else {
    readr::read_csv(file, col_types = readr::cols(
      cohort_id  = "c",
      parameter  = "c",
      imputation = "i",
      draw_index = "i",
      value      = "d"
    ), show_col_types = FALSE)
  }
}

# ------------------------------------------------------------------
# Apply parameter name mapping table to a draws data frame
# ------------------------------------------------------------------
apply_parameter_map <- function(draws, parameter_map) {
  if (length(parameter_map) == 0) return(draws)
  map_df <- dplyr::bind_rows(purrr::map(parameter_map, tibble::as_tibble))
  draws %>%
    dplyr::left_join(map_df, by = c("parameter" = "from")) %>%
    dplyr::mutate(parameter = dplyr::coalesce(to, parameter)) %>%
    dplyr::select(-to)
}

# ------------------------------------------------------------------
# Stack cohort draws, apply mapping, filter to target parameters
# ------------------------------------------------------------------
combine_cohort_draws <- function(cohorts, parameter_map, parameters = NULL) {
  all_draws <- purrr::map_dfr(cohorts, function(cohort) {
    draws <- load_cohort_draws(cohort$file)
    draws$cohort_label <- cohort$label
    draws
  })

  all_draws <- apply_parameter_map(all_draws, parameter_map)

  if (!is.null(parameters)) {
    all_draws <- dplyr::filter(all_draws, parameter %in% parameters)
  } else {
    # Default: intersection of parameters present in every cohort
    param_by_cohort <- all_draws %>%
      dplyr::distinct(cohort_id, parameter) %>%
      dplyr::count(parameter) %>%
      dplyr::filter(n == dplyr::n_distinct(all_draws$cohort_id)) %>%
      dplyr::pull(parameter)
    all_draws <- dplyr::filter(all_draws, parameter %in% param_by_cohort)
    log_msg("Using intersection of parameters across cohorts:", length(param_by_cohort), "parameters")
  }

  all_draws
}

# ------------------------------------------------------------------
# Fit one meta-analysis model for a single parameter
# ------------------------------------------------------------------
fit_meta_one <- function(draws_param, param_name, model_spec, results_dir) {
  log_msg("Fitting meta-analysis model for:", param_name)

  priors <- c(
    brms::set_prior(
      paste0("normal(0, ", model_spec$prior_pooled_sd, ")"),
      class = "Intercept"
    ),
    brms::set_prior(
      paste0("exponential(", model_spec$prior_tau_rate, ")"),
      class = "sd"
    )
  )

  fit <- brms::brm(
    formula   = value ~ 1 + (1 | cohort_id),
    data      = draws_param,
    family    = brms::gaussian(),
    prior     = priors,
    chains    = as.integer(model_spec$chains   %||% 4L),
    iter      = as.integer(model_spec$iter     %||% 2000L),
    warmup    = as.integer(model_spec$warmup   %||% 1000L),
    cores     = as.integer(model_spec$cores    %||% 4L),
    seed      = as.integer(model_spec$seed     %||% 42L),
    control   = list(adapt_delta = model_spec$adapt_delta %||% 0.95),
    silent    = 2,
    refresh   = 0
  )

  safe_name <- gsub("[^A-Za-z0-9_]", "_", param_name)
  fit_path  <- file.path(results_dir, "fits", paste0("meta_fit_", safe_name, ".rds"))
  dir.create(dirname(fit_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(fit, fit_path, compress = FALSE)
  log_msg("  Saved:", fit_path)

  fit
}

# ------------------------------------------------------------------
# Summarise one fitted meta-analysis model
# ------------------------------------------------------------------
summarise_meta_fit <- function(fit, param_name, summary_spec) {
  ci    <- summary_spec$ci %||% 0.89
  alpha <- 1 - ci

  draws_pooled <- posterior::as_draws_df(fit, variable = "b_Intercept") %>%
    tibble::as_tibble() %>%
    dplyr::pull(b_Intercept)

  draws_tau <- posterior::as_draws_df(fit, variable = "sd_cohort_id__Intercept") %>%
    tibble::as_tibble() %>%
    dplyr::pull(sd_cohort_id__Intercept)

  hdi_pooled <- bayestestR::hdi(draws_pooled, ci = ci)
  hdi_tau    <- bayestestR::hdi(draws_tau,    ci = ci)

  pd_val <- bayestestR::p_direction(draws_pooled)$pd

  rope_pct <- NA_real_
  if (!is.null(summary_spec$rope_range)) {
    rope_res <- bayestestR::rope(
      draws_pooled,
      range = summary_spec$rope_range,
      ci    = ci
    )
    rope_pct <- rope_res$ROPE_Percentage * 100
  }

  tibble::tibble(
    parameter       = param_name,
    pooled_median   = median(draws_pooled),
    pooled_ci_low   = hdi_pooled$CI_low,
    pooled_ci_high  = hdi_pooled$CI_high,
    tau_median      = median(draws_tau),
    tau_ci_low      = hdi_tau$CI_low,
    tau_ci_high     = hdi_tau$CI_high,
    pd              = pd_val,
    rope_pct        = rope_pct,
    ci_width        = ci
  )
}

# ------------------------------------------------------------------
# Forest plot for one parameter across cohorts + pooled estimate
# ------------------------------------------------------------------
make_forest_plot <- function(combined_draws, pooled_summary_row, param_name) {
  cohort_summaries <- combined_draws %>%
    dplyr::filter(parameter == param_name) %>%
    dplyr::group_by(cohort_label) %>%
    dplyr::summarise(
      median   = median(value),
      ci_low   = bayestestR::hdi(value, ci = pooled_summary_row$ci_width)$CI_low,
      ci_high  = bayestestR::hdi(value, ci = pooled_summary_row$ci_width)$CI_high,
      .groups  = "drop"
    ) %>%
    dplyr::mutate(type = "Cohort")

  pooled_row <- tibble::tibble(
    cohort_label = "Pooled",
    median       = pooled_summary_row$pooled_median,
    ci_low       = pooled_summary_row$pooled_ci_low,
    ci_high      = pooled_summary_row$pooled_ci_high,
    type         = "Pooled"
  )

  plot_data <- dplyr::bind_rows(cohort_summaries, pooled_row) %>%
    dplyr::mutate(
      cohort_label = factor(cohort_label, levels = rev(c(cohort_summaries$cohort_label, "Pooled")))
    )

  ggplot2::ggplot(plot_data, ggplot2::aes(x = median, y = cohort_label, colour = type)) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    ggplot2::geom_errorbarh(
      ggplot2::aes(xmin = ci_low, xmax = ci_high),
      height = 0.2, linewidth = 0.7
    ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::scale_colour_manual(
      values = c(Cohort = "#2166ac", Pooled = "#d6604d"),
      guide  = "none"
    ) +
    ggplot2::labs(
      title = param_name,
      x     = "Estimate (draw scale)",
      y     = NULL
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
}
