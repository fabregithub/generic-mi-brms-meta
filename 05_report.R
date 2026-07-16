source("00_config.R")
source("00_common_functions.R")

log_msg("============================================================")
log_msg("STEP 5: Write and render meta-analysis report")
log_msg("============================================================")

results_dir <- meta_spec$output$results_dir %||% "results"
pub_dir     <- file.path(results_dir, "publication")
report_dir  <- file.path(pub_dir, "report")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# Check required inputs exist
# ------------------------------------------------------------
pooled_csv <- file.path(pub_dir, "pooled_summary.csv")
cohort_csv <- file.path(pub_dir, "cohort_summary.csv")
plot_dir   <- file.path(pub_dir, "forest_plots")

for (f in c(pooled_csv, cohort_csv)) {
  if (!file.exists(f)) stop(f, " not found. Run Step 4 first.")
}

# ------------------------------------------------------------
# Collect metadata for the methods section
# ------------------------------------------------------------
n_cohorts    <- length(meta_spec$cohorts)
cohort_labels <- paste(
  sapply(meta_spec$cohorts, function(x) x$label %||% x$file),
  collapse = ", "
)
ci_pct       <- round((meta_spec$summary$ci %||% 0.89) * 100)
rope_str     <- if (!is.null(meta_spec$summary$rope_range)) {
  paste0("ROPE = [", paste(round(meta_spec$summary$rope_range, 3), collapse = ", "), "]")
} else {
  "not specified"
}

prior_pooled_sd <- meta_spec$model$prior_pooled_sd %||% 1.0
prior_tau_rate  <- meta_spec$model$prior_tau_rate  %||% 1.0
chains          <- meta_spec$model$chains  %||% 4L
iter            <- meta_spec$model$iter    %||% 2000L
warmup          <- meta_spec$model$warmup  %||% 1000L

# Relative path from report_dir to forest_plots/
forest_rel <- file.path("..", "forest_plots")

# Discover forest plot files
forest_files <- list.files(plot_dir, pattern = "^forest_.*\\.png$", full.names = FALSE)
forest_params <- sub("^forest_(.+)\\.png$", "\\1", forest_files)

# Build one Quarto chunk per forest plot
forest_chunks <- if (length(forest_files) > 0) {
  paste(
    sapply(seq_along(forest_files), function(i) {
      param_clean <- gsub("_", " ", forest_params[i])
      glue::glue(
        '\n## {param_clean}\n\n',
        '![]({forest_rel}/{forest_files[i]}){{width=90%}}\n'
      )
    }),
    collapse = "\n"
  )
} else {
  "_No forest plots found. Run Step 4 first._\n"
}

# ------------------------------------------------------------
# Write .qmd — built with paste() to avoid glue interpreting {r ...} chunks
# ------------------------------------------------------------
qmd_path <- file.path(report_dir, "meta_analysis_report.qmd")

hdi_col_name <- paste0(ci_pct, "% HDI")

qmd_lines <- c(
  '---',
  'title: "Federated Bayesian Meta-Analysis Report"',
  'date: "`r format(Sys.Date(), \'%B %d, %Y\')`"',
  'format:',
  '  html:',
  '    toc: true',
  '    toc-depth: 3',
  '    number-sections: true',
  '    theme: cosmo',
  '    embed-resources: true',
  '    code-fold: true',
  '  docx:',
  '    toc: true',
  '    number-sections: true',
  'execute:',
  '  echo: false',
  '  warning: false',
  '  message: false',
  '---',
  '',
  '```{r setup}',
  'library(dplyr)',
  'library(readr)',
  'library(knitr)',
  'library(flextable)',
  '',
  'pooled <- readr::read_csv("../pooled_summary.csv", show_col_types = FALSE)',
  'cohort <- readr::read_csv("../cohort_summary.csv",  show_col_types = FALSE)',
  paste0('ci_pct <- ', ci_pct),
  paste0('hdi_col <- "', hdi_col_name, '"'),
  '```',
  '',
  '# Methods',
  '',
  paste0(
    'This report summarises a federated Bayesian meta-analysis combining ',
    'posterior draws from ', n_cohorts, ' cohort(s): ', cohort_labels, '.'
  ),
  '',
  'Each cohort independently applied multiple imputation (miceRanger) and',
  'fitted a Bayesian regression model (brms/CmdStan), retaining',
  'per-imputation posterior draws for the pre-specified exposure parameter(s).',
  'Draws were exported using `generic-mi-brms-pipeline` Step 12 and combined',
  'here without sharing individual-level data.',
  '',
  'A hierarchical Bayesian model was fitted to the stacked draws for each',
  'parameter independently:',
  '',
  '$$',
  '\\text{value}_i \\sim \\mathcal{N}(\\mu + u_{\\text{cohort}[i]},\\, \\sigma)',
  '$$',
  '$$',
  paste0(
    '\\mu \\sim \\mathcal{N}(0,\\, ', prior_pooled_sd, '), \\quad',
    ' u_{\\text{cohort}} \\sim \\mathcal{N}(0,\\, \\tau), \\quad',
    ' \\tau \\sim \\text{Exponential}(', prior_tau_rate, ')'
  ),
  '$$',
  '',
  paste0(
    'where $\\mu$ is the pooled effect, $\\tau$ is between-cohort heterogeneity, ',
    'and $\\sigma$ captures intra-cohort draw-level variation (imputation and ',
    'MCMC uncertainty). MCMC settings: ', chains, ' chains, ', iter, ' iterations (',
    warmup, ' warmup). Posterior summaries report the median and ', ci_pct,
    '% highest-density interval (HDI). ', rope_str, '.'
  ),
  '',
  '# Pooled results',
  '',
  '## Pooled posterior summary',
  '',
  '```{r pooled-table}',
  'pooled %>%',
  '  dplyr::mutate(',
  '    Parameter        = parameter,',
  '    `Pooled median`  = round(pooled_median,  3),',
  paste0('    `', hdi_col_name, '` = paste0("[", round(pooled_ci_low,  3), ", ", round(pooled_ci_high, 3), "]"),'),
  '    `tau (median)`   = round(tau_median,   3),',
  '    `tau HDI`        = paste0("[", round(tau_ci_low,  3), ", ", round(tau_ci_high, 3), "]"),',
  '    `sigma (median)` = round(sigma_median, 3),',
  '    `pd (%)`         = round(pd * 100, 1),',
  '    `ROPE (%)`       = ifelse(is.na(rope_pct), "—", round(rope_pct, 1))',
  '  ) %>%',
  paste0('  dplyr::select(Parameter, `Pooled median`, `', hdi_col_name,
         '`, `tau (median)`, `tau HDI`, `sigma (median)`, `pd (%)`, `ROPE (%)`) %>%'),
  '  flextable::flextable() %>%',
  '  flextable::autofit() %>%',
  '  flextable::theme_zebra()',
  '```',
  '',
  '**Column guide:**',
  '- **Pooled median** — meta-analytic estimate on the link scale (log-OR, log-HR, or unstandardised coefficient).',
  '- **tau** — between-cohort heterogeneity SD. Values < 0.1 indicate low, 0.1–0.3 moderate, > 0.3 substantial heterogeneity.',
  '- **sigma** — pooled intra-cohort draw SD (imputation + MCMC uncertainty).',
  '- **pd** — probability of direction: the probability that the effect is positive (or negative).',
  '- **ROPE** — % of the pooled posterior within the region of practical equivalence (if specified).',
  '',
  '## Forest plots',
  '',
  forest_chunks,
  '',
  '# Per-cohort results',
  '',
  '## Per-cohort posterior summary',
  '',
  '```{r cohort-table}',
  'cohort %>%',
  '  dplyr::mutate(',
  '    Cohort    = cohort_label,',
  '    Parameter = parameter,',
  '    m         = m,',
  '    Median    = round(median, 3),',
  paste0('    `', hdi_col_name, '` = paste0("[", round(ci_low, 3), ", ", round(ci_high, 3), "]"),'),
  '    sigma     = round(sigma, 3),',
  '    `pd (%)`  = round(pd * 100, 1),',
  '    `ROPE (%)`= ifelse(is.na(rope_pct), "—", round(rope_pct, 1))',
  '  ) %>%',
  paste0('  dplyr::select(Cohort, Parameter, m, Median, `', hdi_col_name,
         '`, sigma, `pd (%)`, `ROPE (%)`) %>%'),
  '  flextable::flextable() %>%',
  '  flextable::autofit() %>%',
  '  flextable::theme_zebra()',
  '```',
  '',
  '**sigma** here is the SD of all draws within that cohort (collapsed across',
  'imputations), reflecting within-cohort posterior uncertainty. Compare with',
  '**tau** in the pooled table to decompose total variance into within- vs',
  'between-cohort sources.',
  '',
  '# Variance decomposition',
  '',
  '```{r variance-decomp}',
  'decomp <- pooled %>%',
  '  dplyr::select(parameter, sigma_median, tau_median) %>%',
  '  dplyr::mutate(',
  '    `sigma^2 (within)`       = round(sigma_median^2, 4),',
  '    `tau^2 (between)`        = round(tau_median^2,   4),',
  '    `total variance`         = round(sigma_median^2 + tau_median^2, 4),',
  '    `% between (approx I^2)` = round(100 * tau_median^2 / (sigma_median^2 + tau_median^2), 1)',
  '  ) %>%',
  '  dplyr::select(parameter, `sigma^2 (within)`, `tau^2 (between)`,',
  '                `total variance`, `% between (approx I^2)`)',
  '',
  'flextable::flextable(decomp) %>%',
  '  flextable::autofit() %>%',
  '  flextable::theme_zebra()',
  '```',
  '',
  '> **Note:** the "% between" column is an approximation of I² computed as',
  '> $\\tau^2 / (\\tau^2 + \\sigma^2)$. Because $\\sigma$ is estimated from',
  '> pooled draws rather than a single per-study standard error, this value',
  '> is an approximation; report $\\tau$ as the primary heterogeneity measure.',
  '',
  '# Settings',
  '',
  '```{r settings}',
  'tibble::tibble(',
  '  Setting = c("Cohorts", "N cohorts", "CI width", "ROPE range",',
  '              "Prior pooled SD", "Prior tau rate",',
  '              "Chains", "Iterations", "Warmup"),',
  paste0('  Value   = c(', paste(
    paste0('"', c(cohort_labels, n_cohorts, paste0(ci_pct, "%"), rope_str,
                  prior_pooled_sd, prior_tau_rate, chains, iter, warmup), '"'),
    collapse = ", "
  ), ')'),
  ') %>%',
  '  flextable::flextable() %>%',
  '  flextable::autofit() %>%',
  '  flextable::theme_zebra()',
  '```'
)

writeLines(qmd_lines, qmd_path)
log_msg("Wrote", qmd_path)

# ------------------------------------------------------------
# Render — try quarto R package first, fall back to CLI
# ------------------------------------------------------------
render_format <- function(fmt) {
  ok <- FALSE
  if (requireNamespace("quarto", quietly = TRUE)) {
    ok <- tryCatch({
      quarto::quarto_render(qmd_path, output_format = fmt)
      TRUE
    }, error = function(e) {
      log_msg(fmt, "render via R package failed:", conditionMessage(e))
      FALSE
    })
  }
  if (!ok) {
    cli <- Sys.which("quarto")
    if (nzchar(cli)) {
      ret <- system2(cli, c("render", shQuote(qmd_path), "--to", fmt), stdout = FALSE)
      ok  <- (ret == 0)
      if (!ok) log_msg(fmt, "render via CLI failed (exit code", ret, ")")
    } else {
      log_msg(fmt, "render skipped: neither 'quarto' R package nor quarto CLI found.")
    }
  }
  ok
}

if (render_format("html")) {
  log_msg("Rendered HTML:", sub("\\.qmd$", ".html", qmd_path))
}
render_format("docx")
if (file.exists(sub("\\.qmd$", ".docx", qmd_path))) {
  log_msg("Rendered DOCX:", sub("\\.qmd$", ".docx", qmd_path))
}

log_msg("SUCCESS: STEP 5: Write and render meta-analysis report")
