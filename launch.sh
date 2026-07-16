#!/usr/bin/env bash
# ============================================================
# launch.sh — interactive launcher for generic-mi-brms-meta
# ============================================================
# Run from the project root:
#   bash launch.sh
# Or make executable and double-click (Mac):
#   chmod +x launch.sh
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f "run_all.R" ]]; then
  echo "ERROR: run_all.R not found. Run launch.sh from the project root folder."
  exit 1
fi

require_rscript() {
  if ! command -v Rscript &>/dev/null; then
    echo "ERROR: Rscript not found. Please install R and ensure it is on your PATH."
    exit 1
  fi
}

run_step() {
  require_rscript
  echo ""
  echo "======== Running $1 ========"
  Rscript "$1"
}

clean_fits() {
  read -rp "Delete results/fits/ and combined draws? Type YES to confirm: " confirm
  if [[ "$confirm" == "YES" ]]; then
    rm -rf results/fits
    rm -f results/combined_draws.rds results/meta_fits.rds
    echo "Done. (Publication outputs in results/publication/ kept.)"
  else
    echo "Cancelled."
  fi
}

while true; do
  echo ""
  echo "========================================================"
  echo "  generic-mi-brms-meta — interactive launcher"
  echo "========================================================"
  echo "  1.  Run full pipeline     (run_all.R)"
  echo "  2.  Validate inputs       (01_validate_inputs.R)"
  echo "  3.  Combine draws         (02_combine_draws.R)"
  echo "  4.  Fit meta-analysis     (03_fit_meta.R)"
  echo "  5.  Posterior summary     (04_meta_summary.R)"
  echo "  6.  Render report         (05_report.R)"
  echo "  7.  Clean fits            (delete results/fits/ and combined draws)"
  echo "  q.  Quit"
  echo "========================================================"
  echo "  Note: Step 4 is checkpointed — already-fitted parameters"
  echo "  are skipped. Delete results/fits/meta_fit_<param>.rds to refit."
  echo "========================================================"
  read -rp "Enter choice: " choice

  case "$choice" in
    1) run_step "run_all.R" ;;
    2) run_step "01_validate_inputs.R" ;;
    3) run_step "02_combine_draws.R" ;;
    4) run_step "03_fit_meta.R" ;;
    5) run_step "04_meta_summary.R" ;;
    6) run_step "05_report.R" ;;
    7) clean_fits ;;
    q|Q) echo "Goodbye."; exit 0 ;;
    *) echo "Unrecognised choice. Please enter a number from the menu or q to quit." ;;
  esac
done
