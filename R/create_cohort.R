# Purpose: build the study cohort (plan §4): one row per person, with their
#   index cryptococcosis hospitalization, through the flowchart.
# Needs: setup.R (packages, study constants, code lists, hospitalization
#   column names) and functions.R. USRDS files are reached through usRds.
# Produces: cohort_flowchart (a flowchart object for Figure 1) and cohort (its
#   final data: one row per person in the study cohort).

## ---- cohort-load-hospitalizations
# Columns are chosen with select() after loading, not with col_select,
# because load_usrds_file() fails on Parquet files when col_select is used
# (usRds#22). Return to col_select once that is fixed.
# Both hospitalization files, with the key fields and diagnosis columns only.
# factor_labels = FALSE keeps diagnosis codes as character (in hosp_to2009,
# PRIMDIAG is a Y/N flag that Appendix C would otherwise turn into a factor).
# usRds gap (coverage map, step 4): no extractor for these files, so each is
# loaded whole and searched here.
hosp_to2009 <- load_usrds_file(
  "hosp_to2009",
  factor_labels = FALSE
) %>%
  select(all_of(c("USRDS_ID", "CLM_FROM", "CLM_THRU", hosp_to2009_dx_columns)))
hosp_2010on <- load_usrds_file(
  "hosp_2010on",
  factor_labels = FALSE
) %>%
  select(all_of(c("USRDS_ID", "CLM_FROM", "CLM_THRU", hosp_2010on_dx_columns)))

## ---- cohort-flag-records
# Flag cryptococcosis on every hospitalization record, using each file's own
# diagnosis columns.
cryptococcosis_codes <- codes_for_concept(code_lists, "cryptococcosis")

hosp_records <- bind_rows(
  flag_cryptococcosis_records(hosp_to2009, hosp_to2009_dx_columns, cryptococcosis_codes),
  flag_cryptococcosis_records(hosp_2010on, hosp_2010on_dx_columns, cryptococcosis_codes)
)

rm(hosp_to2009, hosp_2010on)

## ---- cohort-build-stays
# Combine all hospitalization records of people with any cryptococcosis
# record into stays, so a cryptococcosis code on any record of an overlapping
# stay counts for the whole stay (plan §5). Keep stays admitted in the window.
people_with_cryptococcosis <- hosp_records %>%
  filter(cryptococcosis_record) %>%
  distinct(USRDS_ID)

cryptococcosis_stays <- hosp_records %>%
  semi_join(people_with_cryptococcosis, by = "USRDS_ID") %>%
  summarise_cryptococcosis_stays(study_start_date, study_end_date)

# Every cryptococcosis hospital record, of any year, for the prior-claim
# exclusion below
hospital_cryptococcosis_claims <- hosp_records %>%
  filter(cryptococcosis_record) %>%
  select(USRDS_ID, claim_date = CLM_FROM)

rm(hosp_records)

## ---- cohort-load-transplants-patients
# First transplant date from the transplant file; date of birth from the
# patients file. Only the people with a cryptococcosis stay are kept.
first_transplants <- load_usrds_file(
  "tx",
  usrds_ids = cryptococcosis_stays$USRDS_ID
) %>%
  select(all_of(c("USRDS_ID", "TDATE"))) %>%
  first_transplant_dates()

patients <- load_usrds_file(
  "patients",
  usrds_ids = cryptococcosis_stays$USRDS_ID
) %>%
  select(all_of(c("USRDS_ID", "BORN")))

## ---- cohort-physician-claims
# Physician/supplier claims with a cryptococcosis code, for the people with a
# cryptococcosis stay (plan §4, step 4). usRds::get_PS_ICD() matches exact
# codes, which the cryptococcosis list is. Covered by usRds (coverage map,
# step 10). A prefix code would be silently missed, so the run stops if the
# list ever gains one.
stopifnot(all(cryptococcosis_codes$match == "exact"))

physician_cryptococcosis_claims <- get_PS_ICD(
  icd_codes = cryptococcosis_codes$code,
  years = physician_claim_years,
  usrds_ids = cryptococcosis_stays$USRDS_ID
) %>%
  select(USRDS_ID, claim_date = CLM_FROM)

## ---- cohort-candidates
# One cryptococcosis claim of either kind before the first transplant, or
# before 2006, excludes the person (decided under issue #4).
prior_cryptococcosis <- prior_cryptococcosis_ids(
  bind_rows(hospital_cryptococcosis_claims, physician_cryptococcosis_claims),
  first_transplants,
  study_start_date
)

cohort_candidates <- build_cohort_candidates(
  cryptococcosis_stays,
  first_transplants,
  patients
) %>%
  mutate(no_prior_cryptococcosis = !USRDS_ID %in% prior_cryptococcosis)

## ---- cohort-flowchart
# Every exclusion goes through fc_filter(), so Figure 1 reproduces the cohort
# exactly. Box labels are built from the constants in setup.R.
cohort_flowchart <- cohort_candidates %>%
  as_fc(
    label = str_glue(
      "People with a cryptococcosis hospitalization admitted ",
      "{format(study_start_date, '%Y')}-{format(study_end_date, '%Y')}"
    )
  ) %>%
  fc_filter(
    in_transplant_file,
    label = "In the USRDS transplant file",
    show_exc = TRUE
  ) %>%
  fc_filter(
    !is.na(index_stay_id),
    label = "Cryptococcosis hospitalization admitted on or after first transplant",
    show_exc = TRUE
  ) %>%
  fc_filter(
    no_prior_cryptococcosis,
    label = str_glue(
      "No cryptococcosis claim (hospital or physician) before first transplant ",
      "or before {format(study_start_date, '%Y')}"
    ),
    show_exc = TRUE
  ) %>%
  fc_filter(
    between(age_at_index, age_min, age_max),
    label = str_glue("Aged {age_min}-{age_max} years at index admission"),
    show_exc = TRUE
  )

cohort <- flowchart::fc_view(cohort_flowchart, what = "data")

## ---- cohort-labels
cohort <- cohort %>%
  set_variable_labels(
    first_transplant_date = "Date of first transplant (USRDS transplant file)",
    in_transplant_file = "Has a record in the USRDS transplant file",
    index_stay_id = "Index cryptococcosis stay (person and stay number)",
    index_admit_date = "Admission date of the index stay (time zero)",
    index_discharge_date = "Discharge date of the index stay",
    age_at_index = "Age at index admission (completed years)",
    no_prior_cryptococcosis = "No cryptococcosis claim (hospital or physician/supplier) before first transplant or before the study start"
  )
