# Purpose: add the mortality outcomes (plan §7) and the model-ready variables
#   (plan §8) to analysis_data.
# Needs: setup.R, functions.R, create_covariates.R (analysis_data). Death
#   dates come from the USRDS patients file through usRds.
# Produces: analysis_data with outcome columns; model_data (analysis_data
#   plus model-ready variables).

## ---- outcomes-deaths
# Date of death from the patients file. The usRds cohort functions are not
# used: every covariate is fixed and death is the only event, so one row per
# person is enough (coverage map, step 18).
deaths <- load_usrds_file(
  "patients",
  usrds_ids = analysis_data$USRDS_ID,
  factor_labels = FALSE,
  col_select = c("USRDS_ID", "DIED")
)

## ---- outcomes-mortality
mortality <- six_month_outcomes(
  analysis_data,
  deaths,
  window_days = mortality_window_days,
  data_end_date = death_data_end_date
)

analysis_data <- analysis_data %>%
  left_join(mortality, by = "USRDS_ID", relationship = "one-to-one")

stopifnot(nrow(analysis_data) == nrow(cohort))

## ---- outcomes-model-variables
# Variables in the form the paper's model reports them: age 60 or older, more
# than one transplant, any graft failure, and not being on tacrolimus.
model_data <- analysis_data %>%
  mutate(
    age_60_or_older = age_at_index >= age_model_cutoff,
    more_than_one_transplant = transplants_before_index > 1,
    prior_graft_failure = failures_before_index > 0,
    no_tacrolimus_at_transplant = !tx_tacrolimus,
    no_tacrolimus_at_followup = !fu_tacrolimus,
    across(c(sex, race, hispanic, region, organ, hiv_status, cmv_status), factor)
  )

## ---- outcomes-labels
analysis_data <- analysis_data %>%
  set_variable_labels(
    days_to_death = "Days from index admission to death",
    died_within_window = str_glue("Died within {mortality_window_days} days of index admission"),
    survival_days = "Days from index admission to death or end of death data",
    survival_event = "Died before the end of death data (1) or censored (0)"
  )
