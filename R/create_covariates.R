# Purpose: build the covariates (plan §5) and join them to the cohort, giving
#   analysis_data: one row per person in the cohort.
# Needs: setup.R, functions.R and create_cohort.R (cohort). USRDS files are
#   reached through usRds.
# Produces: analysis_data.

## ---- covariates-index
# The cohort's index stays, the starting point for every covariate.
cohort_index <- cohort %>%
  select(USRDS_ID, index_admit_date, index_discharge_date)

cohort_ids <- cohort_index$USRDS_ID

## ---- covariates-load-hospitalizations
# All hospitalization records of cohort members, with diagnosis and procedure
# columns and ICU/CCU days. usRds gap (coverage map, steps 4-9): searched here.
dx_concepts <- c(index_stay_dx_concepts, "transplant_complication")

hospitalization_records <- bind_rows(
  load_flagged_hospitalizations(
    "hosp_to2009", cohort_ids, hosp_to2009_dx_columns, hosp_to2009_proc_columns,
    dx_concepts, index_stay_proc_concepts, code_lists
  ),
  load_flagged_hospitalizations(
    "hosp_2010on", cohort_ids, hosp_2010on_dx_columns, hosp_2010on_proc_columns,
    dx_concepts, index_stay_proc_concepts, code_lists
  )
)

## ---- covariates-index-stay
# Meningitis, acute kidney injury, diabetes, cirrhosis and procedures on any
# record of the index stay; ICU admission if any ICU or CCU days.
index_stay_covariates <- summarise_index_stay(
  hospitalization_records,
  cohort_index,
  c(index_stay_dx_concepts, index_stay_proc_concepts)
)

## ---- covariates-prior-hospitalization
# Any hospitalization with a transplant-complication code before the index
# admission.
prior_complication <- summarise_prior_hospitalizations(
  hospitalization_records,
  cohort_index,
  "transplant_complication"
) %>%
  rename(prior_transplant_complication = prior)

rm(hospitalization_records)

## ---- covariates-transplant-history
# Transplants, graft failures and time since the most recent transplant, from
# the USRDS transplant file. Sex and race come from the record of the most
# recent transplant, as in the reconstruction (which took them from this file).
transplants <- load_usrds_file(
  "tx",
  usrds_ids = cohort_ids,
  factor_labels = FALSE,
  col_select = c("USRDS_ID", "TDATE", "FAILDATE", "RSEX", "RACE")
)

transplant_history <- summarise_transplant_history(transplants, cohort_index)

transplant_demographics <- transplants %>%
  inner_join(
    transplant_history %>% select(USRDS_ID, last_transplant_date),
    by = c("USRDS_ID", "TDATE" = "last_transplant_date"),
    relationship = "many-to-one"
  ) %>%
  distinct(USRDS_ID, .keep_all = TRUE) %>%
  transmute(USRDS_ID, sex = recode_sex(RSEX), race = recode_race(RACE))

## ---- covariates-patients
# Hispanic ethnicity and region of residence, from the patients file.
patient_covariates <- load_usrds_file(
  "patients",
  usrds_ids = cohort_ids,
  factor_labels = FALSE,
  col_select = c("USRDS_ID", "HISPANIC", "STATE")
) %>%
  left_join(state_regions, by = "STATE", relationship = "many-to-one") %>%
  transmute(USRDS_ID, hispanic = recode_hispanic(HISPANIC), region, division)

## ---- covariates-unos-registration
# UNOS registration of the most recent transplant on or before the index
# admission (kidney-alone and kidney-pancreas files stacked; the kidney-
# pancreas file names kidney rejection ACUTE_REJ_EPI_KI).
registration_columns <- c(
  "USRDS_ID", unos_registration_id, "TDATE", "BMI", "PRE_TX_DIAL",
  "HIV_SEROSTATUS", "CMV_STATUS"
)

registrations <- bind_rows(
  load_usrds_file(
    "txunos_trr_ki",
    usrds_ids = cohort_ids,
    factor_labels = FALSE,
    col_select = all_of(c(registration_columns, "ACUTE_REJ_EPI"))
  ) %>%
    mutate(organ = "Kidney"),
  load_usrds_file(
    "txunos_trr_kp",
    usrds_ids = cohort_ids,
    factor_labels = FALSE,
    col_select = all_of(c(registration_columns, "ACUTE_REJ_EPI_KI"))
  ) %>%
    rename(ACUTE_REJ_EPI = ACUTE_REJ_EPI_KI) %>%
    mutate(organ = "Kidney-pancreas")
)

index_registration <- select_index_registration(registrations, cohort_index)

## ---- covariates-unos-follow-up
# Follow-up reports of the index registration. A missing FUDATE falls back to
# the kidney graft failure date (FUKIFAIL), as in the reconstruction.
followup_columns <- c(
  "USRDS_ID", unos_registration_id, unos_followup_id, "FUDATE", "FUKIFAIL"
)

followups <- bind_rows(
  load_usrds_file(
    "txfuunos_ki",
    usrds_ids = cohort_ids,
    factor_labels = FALSE,
    col_select = all_of(c(followup_columns, "ACUTE_REJ_EPI"))
  ),
  load_usrds_file(
    "txfuunos_kp",
    usrds_ids = cohort_ids,
    factor_labels = FALSE,
    col_select = all_of(c(followup_columns, "ACUTE_REJ_EPI_KI"))
  ) %>%
    rename(ACUTE_REJ_EPI = ACUTE_REJ_EPI_KI)
) %>%
  mutate(FUDATE = coalesce(FUDATE, FUKIFAIL)) %>%
  semi_join(index_registration, by = c("USRDS_ID", unos_registration_id)) %>%
  inner_join(cohort_index %>% select(USRDS_ID, index_admit_date), by = "USRDS_ID", relationship = "many-to-one")

## ---- covariates-rejection
# Acute rejection: any episode (ACREJEPI 1 or 2) at the index registration or
# on a follow-up report of that transplant dated before the index admission
# (decided 2026-11-10). An ICD claims definition (T86.11) is the alternative
# (plan §9); it is not built here.
followup_rejection <- followups %>%
  filter(FUDATE < index_admit_date) %>%
  group_by(USRDS_ID) %>%
  summarise(rejection_followup = any_known(unos_rejection_any(ACUTE_REJ_EPI)), .groups = "drop")

registration_covariates <- index_registration %>%
  left_join(followup_rejection, by = "USRDS_ID", relationship = "one-to-one") %>%
  rowwise() %>%
  mutate(
    acute_rejection = any_known(c(unos_rejection_any(ACUTE_REJ_EPI), rejection_followup))
  ) %>%
  ungroup() %>%
  transmute(
    USRDS_ID,
    organ,
    bmi = BMI,
    pretransplant_dialysis = case_when(
      PRE_TX_DIAL == "Y" ~ TRUE,
      PRE_TX_DIAL == "N" ~ FALSE,
      .default = NA
    ),
    hiv_status = case_when(HIV_SEROSTATUS == "P" ~ "Positive", HIV_SEROSTATUS == "N" ~ "Negative", .default = NA),
    cmv_status = case_when(CMV_STATUS == "P" ~ "Positive", CMV_STATUS == "N" ~ "Negative", .default = NA),
    acute_rejection
  )

## ---- covariates-immunosuppression-transplant
# Immunosuppression at transplant: the index registration's drug records
# (TXIRUNOS), any drug in each class. A registration with no drug records is
# missing, not "not on".
transplant_drugs <- load_usrds_file(
  "txirunos",
  usrds_ids = cohort_ids,
  factor_labels = FALSE,
  col_select = all_of(c("USRDS_ID", unos_registration_id, "RX_CD", "DRUG_CD_OSTXT"))
) %>%
  semi_join(index_registration, by = c("USRDS_ID", unos_registration_id))

immunosuppression_transplant <- classify_immunosuppressants(
  transplant_drugs,
  unos_registration_id,
  immunosuppressant_classes,
  immunosuppressant_free_text
) %>%
  inner_join(
    index_registration %>% select(USRDS_ID, all_of(unos_registration_id)),
    by = unos_registration_id,
    relationship = "one-to-one"
  ) %>%
  select(-all_of(unos_registration_id)) %>%
  rename_with(\(x) str_c("tx_", x), -USRDS_ID)

## ---- covariates-immunosuppression-followup
# Immunosuppression at the first follow-up report of the index transplant
# (earliest FUDATE, whatever its date relative to the index admission; #2):
# a class counts if one of its drugs is current maintenance (RXMNTCUR = 1).
first_followup <- followups %>%
  filter(!is.na(FUDATE)) %>%
  group_by(USRDS_ID) %>%
  slice_min(FUDATE, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(USRDS_ID, all_of(unos_followup_id))

followup_drugs <- load_usrds_file(
  "txifunos",
  usrds_ids = cohort_ids,
  factor_labels = FALSE,
  col_select = all_of(c("USRDS_ID", unos_followup_id, "RX_CD", "DRUG_CD_OSTXT", "RXMNTCUR"))
) %>%
  semi_join(first_followup, by = c("USRDS_ID", unos_followup_id)) %>%
  # Drugs not current at the visit keep the follow-up's key but match no class
  mutate(
    RX_CD = if_else(RXMNTCUR %in% 1, RX_CD, NA),
    DRUG_CD_OSTXT = if_else(RXMNTCUR %in% 1, DRUG_CD_OSTXT, NA)
  )

immunosuppression_followup <- classify_immunosuppressants(
  followup_drugs,
  unos_followup_id,
  immunosuppressant_classes,
  immunosuppressant_free_text
) %>%
  inner_join(first_followup, by = unos_followup_id, relationship = "one-to-one") %>%
  select(-all_of(unos_followup_id)) %>%
  rename_with(\(x) str_c("fu_", x), -USRDS_ID)

## ---- covariates-assemble
# One row per cohort member. Joins are one-to-one, so a duplicate stops the run.
analysis_data <- cohort %>%
  left_join(index_stay_covariates, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(prior_complication, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(transplant_history, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(transplant_demographics, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(patient_covariates, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(registration_covariates, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(immunosuppression_transplant, by = "USRDS_ID", relationship = "one-to-one") %>%
  left_join(immunosuppression_followup, by = "USRDS_ID", relationship = "one-to-one") %>%
  mutate(
    months_since_last_transplant = days_since_last_transplant / (365.25 / 12),
    over_cutoff_since_transplant = days_since_last_transplant > years_since_transplant_cutoff * 365.25
  )

stopifnot(nrow(analysis_data) == nrow(cohort))

## ---- covariates-labels
analysis_data <- analysis_data %>%
  set_variable_labels(
    cryptococcal_meningitis = "Cryptococcal meningitis on the index stay",
    acute_kidney_injury = "Acute kidney injury on the index stay",
    diabetes = "Diabetes on the index stay",
    cirrhosis = "Cirrhosis on the index stay",
    icu_admission = "ICU or CCU days on the index stay",
    lumbar_puncture = "Lumbar puncture on the index stay",
    spinal_procedure = "Other spinal procedure on the index stay",
    neurosurgical_procedure = "Neurosurgical procedure on the index stay",
    lung_procedure = "Lung procedure on the index stay",
    vp_shunt = "Ventriculoperitoneal shunt on the index stay",
    prior_transplant_complication = "Earlier hospitalization with a transplant-complication code",
    transplants_before_index = "Transplants on or before index admission",
    failures_before_index = "Graft failures before index admission",
    months_since_last_transplant = "Months since most recent transplant",
    over_cutoff_since_transplant = str_glue("More than {years_since_transplant_cutoff} years since most recent transplant"),
    sex = "Sex",
    race = "Race",
    hispanic = "Hispanic ethnicity",
    region = "Census region of residence",
    organ = "Most recent transplant: kidney or kidney-pancreas",
    bmi = "BMI at registration",
    pretransplant_dialysis = "Dialysis before transplant",
    hiv_status = "HIV serostatus at registration",
    cmv_status = "CMV serostatus at registration",
    acute_rejection = "Acute rejection episode (UNOS registration or follow-up before index)"
  )
