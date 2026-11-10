# Purpose: attach packages and define the constants shared by every script.
# Needs: nothing. Produces: attached packages, study constants and code_lists.
# USRDS files are located only through usRds (set_USRDS_wd() is run once,
# outside this repository, on the machine that holds the data).

## ---- load-packages
library(tidyverse)  # dplyr, tidyr, stringr, lubridate and friends
library(usRds)      # USRDS file loading and claims extraction
library(flowchart)  # cohort flow diagram (Figure 1)
library(survival)   # Kaplan-Meier (Figure 2)
library(labelled)   # variable labels

## ---- define-constants
# Study window for the index hospitalization admission date (plan §3)
study_start_date <- as.Date("2006-01-01")
study_end_date <- as.Date("2016-12-31")

# Calendar years of physician/supplier claims searched for cryptococcosis
# before the first transplant (plan §4, step 4): the study years, which is
# where the data begin (coverage map, step 10).
physician_claim_years <- seq(
  lubridate::year(study_start_date),
  lubridate::year(study_end_date)
)

# Age at index admission, in years, inclusive (plan §4, step 6)
age_min <- 18
age_max <- 90

# Primary outcome window: death within this many days of index admission;
# a death on day 180 counts (plan §7)
mortality_window_days <- 180

# ICD-9-CM before this date, ICD-10-CM/PCS on or after (plan §5)
icd10_start_date <- as.Date("2015-10-01")

# Time since most recent transplant is dichotomized at this many years for the
# multivariable model (plan §5)
years_since_transplant_cutoff <- 2

## ---- code-lists-source
source("R/code_lists.R")

## ---- define-hospitalization-columns
# Diagnosis code columns in the two USRDS hospitalization files (Researcher's
# Guide 2024, Appendix B). In hosp_to2009, PRIMDIAG is a Y/N flag ("first
# diagnosis is primary"), not a code, so only HSDIAG1-HSDIAG10 hold codes; in
# hosp_2010on, PRIMDIAG is the principal diagnosis code.
hosp_to2009_dx_columns <- str_c("HSDIAG", 1:10)
hosp_2010on_dx_columns <- c("PRIMDIAG", str_c("HSDIAG", 1:26))
hosp_to2009_proc_columns <- str_c("HSSURG", 1:10)
hosp_2010on_proc_columns <- str_c("HSSURG", 1:25)

## ---- define-unos-keys
# Keys linking the UNOS files. The registration key is the one the
# reconstruction uses (TRR_ID), matching the maintainer's release. The
# follow-up key is NOT VERIFIED: the 2024 layout names it TRRFU_ID_CODE
# (and the registration key TRR_ID_CODE); check both against Appendix B for
# the release in use before running.
unos_registration_id <- "TRR_ID"
unos_followup_id <- "TRRFU_ID"

# Concepts flagged on the index stay (diagnoses and procedures) and on earlier
# hospitalizations (plan §5)
index_stay_dx_concepts <- c(
  "cryptococcal_meningitis", "acute_kidney_injury", "diabetes", "cirrhosis"
)
index_stay_proc_concepts <- c(
  "lumbar_puncture", "spinal_procedure", "neurosurgical_procedure",
  "lung_procedure", "vp_shunt"
)

## ---- define-outcome-constants
# End of death ascertainment for the USRDS release in use: deaths after this
# date are not observed, and survival time is censored here (plan §7). It
# depends on the release, so it is set by whoever runs the analysis; the
# outcome script stops while it is missing.
death_data_end_date <- as.Date(NA)

# Age cut-off used in the paper's model ("age >= 60 years"; plan §8)
age_model_cutoff <- 60

# Significance level for backward elimination (plan §8)
elimination_threshold <- 0.05

# Candidate variables for the bivariable and multivariable models: every
# characteristic in Tables 1 and 2, in model-ready form (plan §8). The paper
# examined "each variable" and entered them all, so there is no entry
# threshold. Drug classes at follow-up are entered as "not on" for
# tacrolimus, as the paper reports it.
model_candidates <- c(
  "age_60_or_older", "sex", "race", "hispanic", "region",
  "cryptococcal_meningitis", "acute_kidney_injury", "diabetes", "cirrhosis",
  "icu_admission", "lumbar_puncture", "spinal_procedure",
  "neurosurgical_procedure", "lung_procedure", "vp_shunt",
  "prior_transplant_complication", "more_than_one_transplant",
  "prior_graft_failure", "over_cutoff_since_transplant", "bmi",
  "pretransplant_dialysis", "hiv_status", "cmv_status", "acute_rejection",
  "tx_antithymocyte_globulin", "tx_alemtuzumab", "tx_il2_receptor_antibody",
  "no_tacrolimus_at_transplant", "tx_cyclosporine", "tx_mycophenolate",
  "tx_mtor_inhibitor", "tx_azathioprine", "tx_steroids",
  "no_tacrolimus_at_followup", "fu_cyclosporine", "fu_mycophenolate",
  "fu_mtor_inhibitor", "fu_azathioprine", "fu_steroids"
)

# The paper's final model: its eight terms with the adjusted odds ratios and
# 95% CIs it reports, in the paper's order (Fiorica et al. 2025, Results;
# plan §8). Fitted as given, beside the backward elimination, to compare
# estimates separately from which variables the selection keeps.
published_model <- tibble::tribble(
  ~term,                            ~published_or, ~published_low, ~published_high,
  "cirrhosis",                       3.1,           1.2,            7.7,
  "icu_admission",                   2.9,           2.0,            4.0,
  "pretransplant_dialysis",          2.7,           1.5,            4.9,
  "no_tacrolimus_at_followup",       2.2,           1.4,            3.3,
  "age_60_or_older",                 2.0,           1.4,            2.8,
  "acute_kidney_injury",             1.7,           1.2,            2.4,
  "over_cutoff_since_transplant",    1.7,           1.1,            2.4,
  "prior_transplant_complication",   1.5,           1.1,            2.2
)
stopifnot(all(published_model$term %in% model_candidates))
