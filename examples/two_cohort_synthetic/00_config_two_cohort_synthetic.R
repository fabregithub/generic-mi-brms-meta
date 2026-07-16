meta_spec <- list(

  cohorts = list(
    list(
      file  = "examples/two_cohort_synthetic/data/cohort_a_draws.rds",
      label = "Cohort A (m=10)"
    ),
    list(
      file  = "examples/two_cohort_synthetic/data/cohort_b_draws.rds",
      label = "Cohort B (m=6)"
    )
  ),

  parameter_map = list(),

  parameters = NULL,   # use intersection (b_exposure_z is present in both)

  model = list(
    prior_pooled_sd = 1.0,
    prior_tau_rate  = 1.0,
    chains          = 2L,
    iter            = 1000L,
    warmup          = 500L,
    cores           = 2L,
    seed            = 42L,
    adapt_delta     = 0.95
  ),

  summary = list(
    ci         = 0.89,
    rope_range = c(-0.1, 0.1)   # on log-OR scale ≈ OR 0.90–1.11
  ),

  output = list(
    results_dir = "examples/two_cohort_synthetic/results"
  )
)

options(brms.backend = "cmdstanr")
