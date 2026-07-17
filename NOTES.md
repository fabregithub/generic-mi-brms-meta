# Development Notes — generic-mi-brms-meta

Running log of features added, design decisions, and ideas for future development.

---

## v0.2.0 (2026-07-17)

### Added: interactive launchers
- `launch.R` — RStudio menu launcher (no terminal needed; recommended for Windows users)
- `launch.sh` — Bash menu launcher for Mac/Linux

---

## v0.1.0 (2026-07-17) — initial release

### Design decisions

**Why per-imputation draws instead of pooled summaries?**
Cohorts may have different `m`. Summary-based meta-analysis (pooled median + CI) requires a
consistent Rubin's-rule variance correction that depends on `m`, making cross-cohort comparison
imprecise. Per-imputation draws sidestep this: a cohort with more imputations contributes more
rows and thus more information naturally, with no reweighting logic needed.

**Why one model per parameter instead of a joint model?**
For causal inference with a common DAG, only 1–3 exposure parameters need meta-analysis.
A joint model's main advantage — estimating cross-parameter heterogeneity correlation — is
irrelevant with so few parameters. One model per parameter is simpler, more robust, and
parallelisable. The joint model would be worth revisiting if the use case shifts to
exploratory analyses with many parameters.

**Why τ instead of I²?**
I² was designed for classical meta-analysis where each study contributes one point estimate
and one SE. Within-cohort uncertainty here comes from full posterior draws and varies across
cohorts and imputations. Computing I² would require arbitrary averaging of within-cohort
variances. τ (between-cohort SD) is reported as the primary heterogeneity measure; an
approximate I² = τ²/(τ² + σ²) is included in the report's variance decomposition table
with an explicit caveat.

**Variable name harmonisation**
The coordinating site distributes a common `00_variable_dictionary.csv` template. Because
parameter names are derived from the `var` column, sharing the template is sufficient to
align exported parameter names across cohorts — the `parameter_map` in `00_config.R` is a
fallback for cohorts that cannot rename variables.

### Statistical model (per parameter)

```
value[i] ~ Normal(mu + u_cohort[c[i]], sigma)
mu        ~ Normal(0, prior_pooled_sd)     # pooled effect
u_cohort  ~ Normal(0, tau)                 # between-cohort deviation
tau        ~ Exponential(prior_tau_rate)
sigma      ~ student_t(3, 0, 2.5)          # brms default residual SD prior
```

`value[i]` is one posterior draw from cohort `c[i]`, imputation `k`, draw `j`.

### Variance measures

| Quantity | Source | Meaning |
|---|---|---|
| `sigma` in `cohort_summary.csv` | Within each cohort | SD of all draws for that cohort × parameter (imputation + MCMC uncertainty) |
| `tau` in `pooled_summary.csv` | Across cohorts | Between-cohort heterogeneity SD |
| `sigma` in `pooled_summary.csv` | Pooled within-cohort | Average draw-level SD from the fitted hierarchical model |

### Pipeline scripts

| Script | Purpose |
|---|---|
| `01_validate_inputs.R` | Check files, required columns, parameter overlap |
| `02_combine_draws.R` | Stack cohorts, apply name mapping |
| `03_fit_meta.R` | Fit `value ~ 1 + (1|cohort_id)` per parameter; checkpointed |
| `04_meta_summary.R` | Pooled summary, per-cohort summary, forest plots |
| `05_report.R` | Write + render Quarto report (HTML + DOCX) |

### Key bugs fixed during development

- `brms::gaussian()` does not exist — use `gaussian()` from base R
- Leftover draft prior block in `fit_meta_one()` crashed on `$` operator before the correct
  block ran; removed
- `glue()` interpreted `{r setup}` Quarto chunk headers as expressions; rewrote QMD generation
  using `paste()`/`writeLines()` instead of `glue()`
- QMD date field used `` `r format(Sys.Date(), ...)` `` which renders as literal text via
  Quarto CLI; replaced with `paste0('date: "', format(Sys.Date(), ...), '"')`
- `if (...) ... else ...` split across lines without braces caused parse error when sourced
  via `source()`; wrapped in `{ }`
- Step 3 re-fit all models on every `run_all.R` invocation; added checkpoint — skips if
  `results/fits/meta_fit_<param>.rds` already exists

---

## Ideas for future development

### Core pipeline
- [ ] **Parallel fitting across parameters** (Step 3): when there are many exposure parameters,
      use `furrr`/`future` to fit models in parallel rather than sequentially
- [ ] **Credible interval type choice**: currently HDI; offer equal-tailed interval (ETI) as
      an option in `meta_spec$summary`
- [ ] **Sensitivity analysis**: re-run with alternative priors and compare pooled posteriors
- [ ] **Leave-one-cohort-out diagnostics**: refit excluding each cohort in turn to detect
      outlier cohorts driving the pooled estimate

### Heterogeneity
- [ ] **Prediction interval**: report the 89% prediction interval for a new cohort's effect,
      derived from `mu ± tau` — more informative than τ alone for communicating heterogeneity
      to clinical audiences
- [ ] **Covariate-adjusted heterogeneity**: if cohort-level covariates are available
      (e.g. mean age, country), add them as fixed effects on `u_cohort` to explain τ

### Report (Step 5)
- [ ] **Exposure back-transformation table**: when `family` is `"bernoulli"` or `"cox"`,
      add a column with OR or HR (exp of pooled estimate) to the pooled summary table
- [ ] **Multi-parameter forest plot**: single plot with all parameters on the y-axis,
      coloured by cohort, instead of one plot per parameter

### Federated workflow
- [ ] **Differential privacy**: optional noise injection on draws before export from the
      pipeline repo
- [ ] **Centralised parameter registry**: a shared CSV (distributed by coordinating site)
      that maps canonical parameter names to human-readable labels, used in reports and plots
      across all cohorts
- [ ] **Automated cohort file validation webhook**: coordinating site runs a lightweight
      check script when a cohort uploads their `cohort_draws.rds`, before accepting it
