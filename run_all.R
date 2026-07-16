source("00_config.R")
source("00_common_functions.R")

run_step <- function(s) {
  cat("\n\n================ RUNNING", s, "================\n\n")
  source(s)
}

run_step("01_validate_inputs.R")
run_step("02_combine_draws.R")
run_step("03_fit_meta.R")
run_step("04_meta_summary.R")
run_step("05_report.R")

cat("\nMeta-analysis pipeline completed successfully.\n")
