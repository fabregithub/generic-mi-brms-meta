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
                   "tibble", "ggplot2", "glue", "jsonlite",
                   "flextable"))
```

CmdStan must be installed for `brms`:

```r
cmdstanr::install_cmdstan()
```

Quarto CLI must be installed for Step 5 (report rendering):
[https://quarto.org/docs/get-started/](https://quarto.org/docs/get-started/)

> The `quarto` R package is optional — Step 5 falls back to the Quarto CLI automatically if the R package is not installed.

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

#### RStudio (no terminal needed — recommended for Windows users)

Open the project folder in RStudio, open `launch.R`, and click **Source**
(`Ctrl+Shift+S` / `Cmd+Shift+S`). A text menu in the R console lets you
run the full pipeline or individual steps without any terminal.

#### Command line

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
    pooled_summary.csv               pooled median, CrI, tau, sigma, pd, ROPE% per parameter
    cohort_summary.csv               per-cohort median, CrI, sigma, pd, ROPE% per parameter
    forest_plots/forest_<param>.png  forest plot per parameter
    report/
      meta_analysis_report.qmd       Quarto source
      meta_analysis_report.html      rendered HTML report
      meta_analysis_report.docx      rendered Word document
```

`pooled_summary.csv` columns:

| Column | Description |
|---|---|
| `parameter` | Parameter name (canonical, post-mapping) |
| `pooled_median` | Median of the pooled posterior (draw scale) |
| `pooled_ci_low/high` | HDI credible interval for the pooled effect |
| `tau_median` | Between-cohort heterogeneity SD |
| `tau_ci_low/high` | HDI for τ |
| `sigma_median` | Intra-cohort draw-level SD (within-cohort variation: MCMC + imputation uncertainty) |
| `sigma_ci_low/high` | HDI for σ |
| `pd` | Probability of direction (0–1) |
| `rope_pct` | % of pooled posterior in ROPE (NA if not configured) |

`cohort_summary.csv` columns (one row per cohort × parameter):

| Column | Description |
|---|---|
| `cohort_id` | Cohort identifier |
| `cohort_label` | Human-readable cohort label |
| `parameter` | Parameter name |
| `m` | Number of imputations for this cohort |
| `n_draws` | Total draw rows for this cohort × parameter |
| `median` | Median of all draws (collapsed across imputations) |
| `ci_low/high` | HDI credible interval |
| `sigma` | SD of all draws — intra-cohort variation (imputation + MCMC uncertainty) |
| `pd` | Probability of direction (0–1) |
| `rope_pct` | % of draws in ROPE (NA if not configured) |

**Variance decomposition interpretation:**

| Quantity | Source | What it tells you |
|---|---|---|
| `sigma` (cohort_summary) | Within each cohort | Posterior uncertainty given that cohort's data and imputation |
| `tau` (pooled_summary) | Across cohorts | True between-cohort effect heterogeneity |
| `sigma` (pooled_summary) | Pooled within-cohort | Average draw-level SD across all cohorts and imputations |

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
| `05_report.R` | Write and render Quarto report (HTML + DOCX) |
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

---

## Heterogeneity: τ vs I²

The model reports **τ (tau)**, the between-cohort standard deviation, rather than I².

**τ** is an absolute measure on the same scale as the parameter (log-OR, log-HR, z-score). It answers: "by how much do cohort-specific true effects vary around the pooled mean?" A τ of 0.2 on the log-OR scale means cohort effects typically fall within roughly ±0.4 log-OR of the pooled estimate (±2τ).

**I²** is a relative measure (0–100%) of the proportion of total observed variance attributable to between-cohort heterogeneity rather than within-cohort sampling error. It was designed for classical meta-analysis where each study contributes a single point estimate and standard error. That structure does not apply here: within-cohort uncertainty comes from full posterior draws (not a single SE), and varies across cohorts and imputations. Computing I² from this model would require arbitrary averaging of within-cohort variances, making it an approximation.

**Recommendation:** report τ (median and credible interval from `pooled_summary.csv`). If a journal or reviewer requires I², note that it is not directly estimable from a draws-based hierarchical model and report τ as the equivalent heterogeneity quantity.

---

## Reporting templates

### Methods

> We conducted a federated Bayesian meta-analysis of [N] cohorts to estimate the pooled effect of [exposure] on [outcome]. Each cohort independently applied multiple imputation (miceRanger) and fitted a Bayesian [family] regression model (brms/CmdStan) to [m] imputed datasets, retaining all per-imputation posterior draws. Per-imputation draws for the exposure parameter were exported and combined across cohorts. A hierarchical Bayesian model was fitted to the stacked draws, with cohort as a random intercept, yielding a joint posterior for the pooled effect (μ) and between-cohort heterogeneity (τ). Priors were Normal(0, [prior_pooled_sd]) on μ and Exponential([prior_tau_rate]) on τ. Posterior summaries report the median and [ci×100]% highest-density interval (HDI). Analyses used R ([version]) with brms ([version]) and CmdStan ([version]).

### Results

> The pooled [log-OR / log-HR / coefficient] for [exposure] was [pooled_median] (89% HDI [pooled_ci_low, pooled_ci_high]; OR/HR = [exp(pooled_median)], 89% HDI [exp(pooled_ci_low), exp(pooled_ci_high)]), with a probability of direction of [pd×100]%. Between-cohort heterogeneity was τ = [tau_median] (89% HDI [tau_ci_low, tau_ci_high]), indicating [low / moderate / substantial] variability in the exposure effect across cohorts [and can be considered [negligible/significant] with [rope_pct]% of the pooled posterior within the region of practical equivalence].

**Guidance for filling in the template:**

| Placeholder | Source |
|---|---|
| `pooled_median`, `pooled_ci_low/high` | `pooled_summary.csv` |
| `tau_median`, `tau_ci_low/high` | `pooled_summary.csv` |
| `pd` | `pooled_summary.csv` (`pd` column, multiply by 100 for %) |
| `rope_pct` | `pooled_summary.csv` (omit sentence if `rope_range` not set) |
| OR/HR | `exp(pooled_median)` and `exp(pooled_ci_low/high)` for log-link models |

**Characterising τ magnitude** (on log-OR / log-HR scale, for orientation):

| τ | Interpretation |
|---|---|
| < 0.1 | Low heterogeneity |
| 0.1 – 0.3 | Moderate heterogeneity |
| > 0.3 | Substantial heterogeneity |

These thresholds are informal; interpret τ in the context of the parameter scale and the scientific question.
