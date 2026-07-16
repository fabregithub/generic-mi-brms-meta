# ============================================================
# 00_config.R — federated Bayesian meta-analysis
# ============================================================
# Edit this file to configure your meta-analysis.
# Each cohort must have run the generic_mi_brms_pipeline with a
# cohort_id set in analysis_spec$export and produced:
#   results/export/cohort_draws.rds
#   results/export/cohort_metadata.json
# ============================================================

meta_spec <- list(

  # ------------------------------------------------------------
  # Cohort draw files
  # ------------------------------------------------------------
  # List one entry per cohort. Each entry needs:
  #   file  — path to cohort_draws.rds (or .csv)
  #   label — human-readable cohort name for plots/tables
  cohorts = list(
    # list(file = "data/cohort_a_draws.rds", label = "Cohort A"),
    # list(file = "data/cohort_b_draws.rds", label = "Cohort B")
  ),

  # ------------------------------------------------------------
  # Parameter name mapping
  # ------------------------------------------------------------
  # If cohorts use different variable names for the same construct,
  # map them to a common canonical name here.
  # Each entry: list(from = "original_name", to = "canonical_name")
  # Leave as empty list() if all cohorts use identical parameter names.
  parameter_map = list(
    # list(from = "b_smoke_z",    to = "b_exposure_z"),
    # list(from = "b_smoking_z",  to = "b_exposure_z")
  ),

  # ------------------------------------------------------------
  # Parameters to meta-analyse
  # ------------------------------------------------------------
  # NULL = all parameters present in all cohorts (intersection)
  # or a character vector of canonical parameter names
  parameters = NULL,

  # ------------------------------------------------------------
  # Model settings
  # ------------------------------------------------------------
  model = list(
    # Prior on pooled effect (on the draw scale — log-OR, log-HR, z-score, etc.)
    prior_pooled_sd  = 1.0,
    # Prior on between-cohort heterogeneity (tau); exponential rate
    prior_tau_rate   = 1.0,
    # brms/cmdstanr settings
    chains           = 4L,
    iter             = 2000L,
    warmup           = 1000L,
    cores            = 4L,
    seed             = 42L,
    adapt_delta      = 0.95
  ),

  # ------------------------------------------------------------
  # Posterior summary settings
  # ------------------------------------------------------------
  summary = list(
    ci         = 0.89,   # credible interval width
    rope_range = NULL    # c(low, high) on draw scale; NULL = skip ROPE
  ),

  # ------------------------------------------------------------
  # Output settings
  # ------------------------------------------------------------
  output = list(
    results_dir = "results"
  )
)

options(brms.backend = "cmdstanr")
