# Purpose: reusable helpers. Each takes its inputs as arguments.
# Needs: setup.R. Produces: functions only.
#
# usRds gap code: functions marked "usRds gap" do work that usRds does not yet
# do (references/usrds-coverage.md). They are kept here, not in usRds, because
# this project assesses coverage rather than closing gaps.

## ---- codes-for-concept
# Return the code list for one concept as a tibble with columns code and
# match ("exact" or "prefix"), optionally limited to one code type.
codes_for_concept <- function(code_lists, concept_name, type = NULL) {
  selected <- code_lists %>%
    filter(concept == concept_name)

  if (!is.null(type)) {
    selected <- selected %>%
      filter(code_type == type)
  }

  if (nrow(selected) == 0) {
    stop(str_glue("No codes found for concept '{concept_name}'."), call. = FALSE)
  }

  selected %>%
    select(code, match)
}

## ---- code-matches
# usRds gap (coverage map, step 6): the get_*_ICD() functions match codes
# exactly; this also handles prefix matching ("250" matches "25000").
# Returns TRUE where a code in `values` matches any code in `codes`.
code_matches <- function(values, codes) {
  exact_codes <- codes %>%
    filter(match == "exact") %>%
    pull(code)
  prefix_codes <- codes %>%
    filter(match == "prefix") %>%
    pull(code)

  matched <- !is.na(values) & values %in% exact_codes
  for (prefix in prefix_codes) {
    matched <- matched | (!is.na(values) & str_starts(values, fixed(prefix)))
  }
  matched
}

## ---- flag-codes-wide
# usRds gap (coverage map, steps 4-6 and 9): the hospitalization files hold
# diagnoses and procedures in wide columns (PRIMDIAG, HSDIAG1-HSDIAG26,
# HSSURG1-HSSURG25). Returns TRUE for each row where any of `columns` matches
# `codes`. Columns that do not exist (HSDIAG11+ before 2010) are skipped.
flag_codes_wide <- function(df, columns, codes) {
  present_columns <- intersect(columns, names(df))

  if (length(present_columns) == 0) {
    stop("None of the requested code columns are in the data.", call. = FALSE)
  }

  any_match <- rep(FALSE, nrow(df))
  for (column in present_columns) {
    any_match <- any_match | code_matches(df[[column]], codes)
  }
  any_match
}

## ---- collapse-stays
# usRds gap (coverage map, step 7): hospitalization records whose admission
# date falls on or before the latest discharge date so far for the same person
# (plus `gap_days`) belong to the same stay. Adds stay_id (unique across
# people), stay_from and stay_thru. Input needs USRDS_ID, CLM_FROM, CLM_THRU.
collapse_stays <- function(records, gap_days = 0) {
  records %>%
    arrange(USRDS_ID, CLM_FROM, CLM_THRU) %>%
    group_by(USRDS_ID) %>%
    mutate(
      latest_thru_before = lag(cummax(as.numeric(CLM_THRU))),
      starts_new_stay = case_when(
        is.na(latest_thru_before) ~ TRUE,
        as.numeric(CLM_FROM) > latest_thru_before + gap_days ~ TRUE,
        .default = FALSE
      ),
      stay_number = cumsum(starts_new_stay)
    ) %>%
    group_by(USRDS_ID, stay_number) %>%
    mutate(
      stay_from = min(CLM_FROM),
      stay_thru = max(CLM_THRU)
    ) %>%
    ungroup() %>%
    mutate(stay_id = str_c(USRDS_ID, "-", stay_number)) %>%
    select(-latest_thru_before, -starts_new_stay, -stay_number)
}

## ---- age-in-years
# Completed years of age on a date (age at last birthday).
age_in_years <- function(born, on) {
  floor(time_length(interval(born, on), unit = "years"))
}

## ---- first-transplant-dates
# One row per person: the date of their first transplant in the USRDS
# transplant file. Input needs USRDS_ID and TDATE.
first_transplant_dates <- function(transplants) {
  transplants %>%
    filter(!is.na(TDATE)) %>%
    group_by(USRDS_ID) %>%
    summarise(first_transplant_date = min(TDATE), .groups = "drop")
}

## ---- flag-cryptococcosis-records
# Keep each hospitalization record's key fields and flag whether any of its
# diagnosis columns holds a cryptococcosis code. `dx_columns` differs by file
# (see setup.R).
flag_cryptococcosis_records <- function(records, dx_columns, crypto_codes) {
  records %>%
    mutate(
      cryptococcosis_record = flag_codes_wide(records, dx_columns, crypto_codes)
    ) %>%
    select(USRDS_ID, CLM_FROM, CLM_THRU, cryptococcosis_record)
}

## ---- summarise-cryptococcosis-stays
# Combine records into stays (collapse_stays()) and keep the stays with a
# cryptococcosis code on any of their records, admitted in the study window.
# Returns one row per stay: USRDS_ID, stay_id, stay_from, stay_thru.
summarise_cryptococcosis_stays <- function(records, window_start, window_end) {
  records %>%
    collapse_stays() %>%
    group_by(USRDS_ID, stay_id, stay_from, stay_thru) %>%
    summarise(
      cryptococcosis_stay = any(cryptococcosis_record),
      .groups = "drop"
    ) %>%
    filter(
      cryptococcosis_stay,
      stay_from >= window_start,
      stay_from <= window_end
    ) %>%
    select(-cryptococcosis_stay)
}

## ---- build-cohort-candidates
# One row per person with at least one cryptococcosis stay in the window,
# with the flags the cohort flowchart filters on (plan §4):
#   in_transplant_file: has a record in the USRDS transplant file;
#   index_stay_id, index_admit_date, index_discharge_date: the first
#     cryptococcosis stay that did not end before the first transplant
#     (NA when there is none);
#   age_at_index: completed years on the index admission date.
build_cohort_candidates <- function(crypto_stays, first_transplants, patients) {
  index_stays <- crypto_stays %>%
    inner_join(first_transplants, by = "USRDS_ID", relationship = "many-to-one") %>%
    filter(stay_thru >= first_transplant_date) %>%
    group_by(USRDS_ID) %>%
    slice_min(stay_from, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(
      USRDS_ID,
      index_stay_id = stay_id,
      index_admit_date = stay_from,
      index_discharge_date = stay_thru
    )

  crypto_stays %>%
    distinct(USRDS_ID) %>%
    left_join(first_transplants, by = "USRDS_ID", relationship = "one-to-one") %>%
    mutate(in_transplant_file = !is.na(first_transplant_date)) %>%
    left_join(index_stays, by = "USRDS_ID", relationship = "one-to-one") %>%
    left_join(
      patients %>% select(USRDS_ID, BORN),
      by = "USRDS_ID",
      relationship = "one-to-one"
    ) %>%
    mutate(age_at_index = age_in_years(BORN, index_admit_date)) %>%
    select(-BORN)
}
