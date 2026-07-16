# Creates synthetic per-imputation draws mimicking two cohorts that ran the
# generic_mi_brms_pipeline, without needing to actually run that pipeline.
#
# Scenario: both cohorts studied the effect of a continuous exposure (log-OR
# scale) on a binary outcome.  Cohort A has m=10 imputations; Cohort B has m=6.
# The true pooled log-OR is 0.4; between-cohort heterogeneity tau=0.15.
#
# Run from the repo root:
#   Rscript examples/two_cohort_synthetic/00_create_synthetic_draws.R

set.seed(42)

library(tibble)
library(dplyr)
library(readr)

out_dir <- "examples/two_cohort_synthetic/data"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

make_cohort_draws <- function(cohort_id, true_effect, m, n_draws_per_imp,
                              within_sd = 0.12) {
  purrr::map_dfr(seq_len(m), function(imp) {
    # Each imputation has a slightly different posterior centre
    imp_centre <- rnorm(1, mean = true_effect, sd = 0.05)
    tibble::tibble(
      cohort_id  = cohort_id,
      parameter  = "b_exposure_z",
      imputation = imp,
      draw_index = seq_len(n_draws_per_imp),
      value      = rnorm(n_draws_per_imp, mean = imp_centre, sd = within_sd)
    )
  })
}

# Cohort-specific true effects drawn from N(0.4, 0.15^2)
true_a <- rnorm(1, 0.4, 0.15)
true_b <- rnorm(1, 0.4, 0.15)

cat("True effect cohort A:", round(true_a, 3), "\n")
cat("True effect cohort B:", round(true_b, 3), "\n")

draws_a <- make_cohort_draws("cohort_a", true_a, m = 10, n_draws_per_imp = 1000)
draws_b <- make_cohort_draws("cohort_b", true_b, m =  6, n_draws_per_imp = 1000)

saveRDS(draws_a, file.path(out_dir, "cohort_a_draws.rds"), compress = TRUE)
saveRDS(draws_b, file.path(out_dir, "cohort_b_draws.rds"), compress = TRUE)

readr::write_csv(draws_a, file.path(out_dir, "cohort_a_draws.csv"))
readr::write_csv(draws_b, file.path(out_dir, "cohort_b_draws.csv"))

cat("Wrote", file.path(out_dir, "cohort_a_draws.rds"), "\n")
cat("Wrote", file.path(out_dir, "cohort_b_draws.rds"), "\n")
cat("Cohort A: m =", dplyr::n_distinct(draws_a$imputation),
    " | rows =", nrow(draws_a), "\n")
cat("Cohort B: m =", dplyr::n_distinct(draws_b$imputation),
    " | rows =", nrow(draws_b), "\n")
