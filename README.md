# generic-mi-brms-meta

Federated Bayesian meta-analysis pipeline for combining results from
[generic-mi-brms-pipeline](https://github.com/fabregithub/generic-mi-brms-pipeline)
cohorts.

Each cohort runs the main pipeline independently and exports
per-imputation posterior draws (`results/export/cohort_draws.rds`).
This repo collects those files and fits a hierarchical Bayesian
meta-analysis model — one model per exposure parameter — using `brms`.

## Why per-imputation draws?

Cohorts may have different numbers of imputations (`m`). Summary-based
meta-analysis requires a consistent variance correction that depends on
`m`; per-imputation draws sidestep this entirely. A cohort with more
imputations contributes more rows and thus more information naturally,
with no reweighting logic needed.

## Requirements

```r
install.packages(c("brms", "posterior", "bayestestR",
                   "dplyr", "purrr", "tidyr", "readr",
                   "tibble", "ggplot2", "glue", "jsonlite"))
```

CmdStan must be installed for `brms`:

```r
cmdstanr::install_cmdstan()
```

## Workflow

### 1. Each cohort exports draws

In `00_config.R` of the main pipeline, set:

```r
export = list(
  cohort_id = "cohort_japan_2024",   # unique short ID
  scope     = "exposure_only"        # recommended for causal inference
)
```

Then run (or re-run Step 12 only):

```bash
Rscript 12_export_draws.R
```

This writes `results/export/cohort_draws.rds` and
`results/export/cohort_metadata.json`. Each cohort ships these two files
to the coordinating site.

### 2. Place cohort files in `data/`

```
data/
  cohort_japan_2024_draws.rds
  cohort_korea_2023_draws.rds
  ...
```

### 3. Edit `00_config.R`

```r
cohorts = list(
  list(file = "data/cohort_japan_2024_draws.rds", label = "Japan 2024"),
  list(file = "data/cohort_korea_2023_draws.rds", label = "Korea 2023")
),
parameter_map = list(
  # if cohorts used different variable names for the same exposure:
  # list(from = "b_smoke_z", to = "b_exposure_z")
)
```

### 4. Run the pipeline

```bash
Rscript 01_validate_inputs.R   # check files, parameter overlap
Rscript run_all.R              # validate + combine + fit + summarise
```

### Outputs

```
results/
  combined_draws.rds               stacked long-format draws from all cohorts
  meta_fits.rds                    list of brms fit objects (one per parameter)
  fits/meta_fit_<param>.rds        individual fit files (checkpointed)
  publication/
    pooled_summary.csv             pooled median, CrI, tau, pd, ROPE% per parameter
    forest_plots/forest_<param>.png  forest plot per parameter
```

`pooled_summary.csv` columns:

| Column | Description |
|---|---|
| `parameter` | Parameter name (canonical, post-mapping) |
| `pooled_median` | Median of the pooled posterior (draw scale) |
| `pooled_ci_low/high` | HDI credible interval |
| `tau_median` | Between-cohort heterogeneity (SD) |
| `tau_ci_low/high` | HDI for tau |
| `pd` | Probability of direction (0–1) |
| `rope_pct` | % of pooled posterior in ROPE (NA if not configured) |

## Example: two synthetic cohorts

```bash
# Generate synthetic draws (no pipeline run needed)
Rscript examples/two_cohort_synthetic/00_create_synthetic_draws.R

# Copy example config
cp examples/two_cohort_synthetic/00_config_two_cohort_synthetic.R 00_config.R

# Run meta-analysis
Rscript run_all.R
```

## Pipeline scripts

| Script | Purpose |
|---|---|
| `01_validate_inputs.R` | Check files exist, required columns present, report parameter overlap |
| `02_combine_draws.R` | Stack draws, apply parameter name mapping, save `combined_draws.rds` |
| `03_fit_meta.R` | Fit `value ~ 1 + (1 | cohort_id)` per parameter, checkpoint fits |
| `04_meta_summary.R` | Posterior summary + forest plots |
| `run_all.R` | Runs all steps in order |

## Statistical model

For each exposure parameter `p` independently:

```
value[i] ~ Normal(mu_p + u_cohort[c[i]], sigma)
mu_p      ~ Normal(0, prior_pooled_sd)          # pooled effect
u_cohort  ~ Normal(0, tau)                       # between-cohort deviation
tau        ~ Exponential(prior_tau_rate)
```

where `value[i]` is one posterior draw from cohort `c[i]`, imputation
`k`, draw `j`. Cohorts with more imputations or more draws contribute
proportionally more rows; no explicit weighting is applied.
