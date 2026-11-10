# Purpose: run the definitive analysis in dependency order.
# Run from the project root in a fresh session, on a machine where
# usRds::set_USRDS_wd() points to the USRDS files.

source("R/setup.R")
source("R/functions.R")

# Cohort (plan §4)
source("R/create_cohort.R")

# Covariates (plan §5)
source("R/create_covariates.R")

# Outcomes (plan §7) and models (plan §8)
source("R/create_outcomes.R")
source("R/fit_models.R")

# Tables and figures (plan §8, §10); outputs go to the gitignored tables/
# and figures/ folders until USRDS review clears them
source("R/plot_style.R")
source("R/tables.R")
source("R/figures.R")
# Further analysis scripts are added here as they join the definitive analysis.
