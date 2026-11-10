# Purpose: run the whole analysis, in R/main.R's order, on a synthetic USRDS
#   folder (tests/make_synthetic_usrds.R), so every script is exercised with
#   the real usRds, flowchart and gtsummary without restricted data.
# Run from the project root: Rscript tests/run_synthetic.R
# The death-data end date, which the real run sets for its release, is set
# here for the synthetic data only.

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr)
})
source("tests/make_synthetic_usrds.R")
synthetic_path <- make_synthetic_usrds()
usRds::set_USRDS_wd(synthetic_path, permanent = FALSE)

scripts <- str_match(readLines("R/main.R"), '^source\\("(R/[^"]+)"\\)')[, 2]
scripts <- scripts[!is.na(scripts)]
for (script in scripts) {
  message("Running ", script)
  source(script)
  if (script == "R/setup.R") {
    death_data_end_date <- as.Date("2017-12-31")  # synthetic run only
  }
}
