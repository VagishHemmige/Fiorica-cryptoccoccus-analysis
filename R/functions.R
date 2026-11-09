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
