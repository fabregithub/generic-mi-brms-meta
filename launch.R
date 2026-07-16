# ============================================================
# launch.R — interactive launcher for generic-mi-brms-meta
# ============================================================
# Open this file in RStudio and click Source (or press Ctrl+Shift+S).
# No terminal or command line needed.
# ============================================================

if (!file.exists("launch.R")) {
  stop(
    "Please open launch.R from the project root folder ",
    "(the folder that contains run_all.R and 00_config.R)."
  )
}

.run_clean <- function(script) {
  e <- new.env(parent = globalenv())
  source(script, local = e)
  invisible(NULL)
}

.clean_outputs <- function() {
  targets <- list(
    dirs  = c("results/fits"),
    files = c("results/combined_draws.rds", "results/meta_fits.rds")
  )
  for (d in targets$dirs)  if (dir.exists(d))  unlink(d, recursive = TRUE)
  for (f in targets$files) if (file.exists(f)) file.remove(f)
  cat("Done. (Publication outputs in results/publication/ kept.)\n")
}

repeat {
  cat("
========================================================
  generic-mi-brms-meta — interactive launcher
========================================================
  1. Run full pipeline     (run_all.R)
  2. Validate inputs       (01_validate_inputs.R)
  3. Combine draws         (02_combine_draws.R)
  4. Fit meta-analysis     (03_fit_meta.R)
  5. Posterior summary     (04_meta_summary.R)
  6. Render report         (05_report.R)
  7. Clean fits            (delete results/fits/ and combined draws)
  q. Quit
========================================================
  Note: Step 4 is checkpointed — already-fitted parameters
  are skipped automatically. Delete results/fits/meta_fit_<param>.rds
  to force a refit for a specific parameter.
========================================================
")

  choice <- trimws(readline("Enter choice: "))

  if (choice == "q" || choice == "Q") {
    cat("Goodbye.\n")
    break
  }

  if      (choice == "1") { cat("Running full pipeline...\n");    .run_clean("run_all.R") }
  else if (choice == "2") { cat("Validating inputs...\n");        .run_clean("01_validate_inputs.R") }
  else if (choice == "3") { cat("Combining draws...\n");          .run_clean("02_combine_draws.R") }
  else if (choice == "4") { cat("Fitting meta-analysis...\n");    .run_clean("03_fit_meta.R") }
  else if (choice == "5") { cat("Posterior summary...\n");        .run_clean("04_meta_summary.R") }
  else if (choice == "6") { cat("Rendering report...\n");         .run_clean("05_report.R") }
  else if (choice == "7") {
    confirm <- trimws(readline("Delete results/fits/ and combined draws? Type YES to confirm: "))
    if (confirm == "YES") { cat("Cleaning...\n"); .clean_outputs() }
    else cat("Cancelled.\n")
  }
  else {
    cat("Unrecognised choice. Please enter a number from the menu or q to quit.\n")
  }
}
