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
