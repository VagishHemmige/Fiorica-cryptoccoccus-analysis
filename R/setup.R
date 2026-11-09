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
