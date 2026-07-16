source("00_config.R")
source("00_common_functions.R")

log_msg("============================================================")
log_msg("STEP 1: Validate cohort draw files")
log_msg("============================================================")

if (length(meta_spec$cohorts) == 0) {
  stop("meta_spec$cohorts is empty. Add cohort entries to 00_config.R.")
}

required_cols <- c("cohort_id", "parameter", "imputation", "draw_index", "value")

errors   <- character()
warnings <- character()

all_params <- vector("list", length(meta_spec$cohorts))

for (i in seq_along(meta_spec$cohorts)) {
  cohort <- meta_spec$cohorts[[i]]
  label  <- cohort$label %||% paste0("cohort_", i)

  log_msg(sprintf("Checking cohort %d: %s (%s)", i, label, cohort$file))

  if (!file.exists(cohort$file)) {
    errors <- c(errors, sprintf("  [%s] File not found: %s", label, cohort$file))
    next
  }

  draws <- tryCatch(
    load_cohort_draws(cohort$file),
    error = function(e) {
      errors <<- c(errors, sprintf("  [%s] Failed to read: %s", label, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(draws)) next

  missing_cols <- setdiff(required_cols, names(draws))
  if (length(missing_cols) > 0) {
    errors <- c(errors, sprintf("  [%s] Missing columns: %s", label, paste(missing_cols, collapse = ", ")))
    next
  }

  if (anyNA(draws$value)) {
    n_na <- sum(is.na(draws$value))
    warnings <- c(warnings, sprintf("  [%s] %d NA values in 'value' column", label, n_na))
  }

  n_params <- dplyr::n_distinct(draws$parameter)
  n_imp    <- dplyr::n_distinct(draws$imputation)
  n_rows   <- nrow(draws)
  params   <- sort(unique(draws$parameter))

  log_msg(sprintf("  OK: %d parameters, m = %d, %d rows", n_params, n_imp, n_rows))
  log_msg("  Parameters:", paste(params, collapse = ", "))

  # Check metadata sidecar if present
  meta_file <- file.path(dirname(cohort$file), "cohort_metadata.json")
  if (file.exists(meta_file)) {
    meta <- jsonlite::read_json(meta_file)
    log_msg("  Cohort ID in file:", meta$cohort_id, "| family:", meta$family %||% "unknown")
    if (meta$cohort_id != unique(draws$cohort_id)) {
      warnings <- c(warnings, sprintf(
        "  [%s] cohort_id in metadata (%s) differs from draws (%s)",
        label, meta$cohort_id, unique(draws$cohort_id)
      ))
    }
  }

  all_params[[i]] <- params
}

if (length(errors) > 0) {
  cat("\nErrors:\n")
  cat(paste(errors, collapse = "\n"), "\n")
  stop("Validation failed. Fix the errors above before proceeding.")
}

if (length(warnings) > 0) {
  cat("\nWarnings:\n")
  cat(paste(warnings, collapse = "\n"), "\n")
}

# Report parameter overlap
valid_params <- all_params[!sapply(all_params, is.null)]
if (length(valid_params) > 1) {
  intersection <- Reduce(intersect, valid_params)
  union_params <- Reduce(union,     valid_params)
  only_in_some <- setdiff(union_params, intersection)

  log_msg(sprintf(
    "Parameter intersection across %d cohorts: %d of %d",
    length(valid_params), length(intersection), length(union_params)
  ))

  if (length(only_in_some) > 0) {
    log_msg("Parameters not present in all cohorts (will be excluded unless meta_spec$parameters is set):")
    log_msg(" ", paste(only_in_some, collapse = ", "))
  }
}

log_msg("SUCCESS: STEP 1: Validate cohort draw files")
