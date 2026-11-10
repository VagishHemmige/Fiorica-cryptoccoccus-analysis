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
#     cryptococcosis stay admitted on or after the first transplant (NA when
#     there is none). A stay admitted before the first transplant is a
#     cryptococcosis hospitalization claim preceding it, which the paper
#     excludes (decided under issue #4);
#   age_at_index: completed years on the index admission date.
build_cohort_candidates <- function(crypto_stays, first_transplants, patients) {
  index_stays <- crypto_stays %>%
    inner_join(first_transplants, by = "USRDS_ID", relationship = "many-to-one") %>%
    filter(stay_from >= first_transplant_date) %>%
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

## ---- prior-cryptococcosis
# People with any cryptococcosis claim before their first transplant (plan
# §4, step 4; decided under issue #4: hospital and physician/supplier claims
# both count, and one claim is enough). `claims` has one row per claim:
# USRDS_ID and claim_date (the first day of service). A claim on the
# transplant date itself is not before it, matching the rule for hospital
# stays. Returns the USRDS_IDs to exclude.
prior_cryptococcosis_ids <- function(claims, first_transplants) {
  claims %>%
    inner_join(first_transplants, by = "USRDS_ID", relationship = "many-to-one") %>%
    filter(claim_date < first_transplant_date) %>%
    distinct(USRDS_ID) %>%
    pull(USRDS_ID)
}

## ---- flag-concepts
# Add one logical column per concept to hospitalization records: TRUE when any
# of `columns` holds a code from that concept's list. Columns are named
# <concept> (for example, diabetes).
flag_concepts <- function(records, columns, code_lists, concepts) {
  for (concept_name in concepts) {
    records[[concept_name]] <- flag_codes_wide(
      records,
      columns,
      codes_for_concept(code_lists, concept_name)
    )
  }
  records
}

## ---- summarise-index-stay
# Stay-level covariates for the index stay. A record belongs to the index stay
# when it is admitted within the stay's span (true of every record that
# collapse_stays() combined into it). Returns one row per person: each
# concept flag (TRUE if any record of the stay has it) and icu_admission
# (any ICU or CCU days on the stay).
summarise_index_stay <- function(records, cohort_index, concepts) {
  records %>%
    inner_join(
      cohort_index %>% select(USRDS_ID, index_admit_date, index_discharge_date),
      by = "USRDS_ID",
      relationship = "many-to-one"
    ) %>%
    filter(
      CLM_FROM >= index_admit_date,
      CLM_FROM <= index_discharge_date
    ) %>%
    group_by(USRDS_ID) %>%
    summarise(
      across(all_of(concepts), any),
      icu_days = sum(coalesce(ICU_DAYS, 0) + coalesce(CCU_DAYS, 0)),
      .groups = "drop"
    ) %>%
    mutate(icu_admission = icu_days > 0) %>%
    select(-icu_days)
}

## ---- summarise-prior-hospitalizations
# TRUE when any hospitalization record admitted before the index admission has
# `flag_column` set (for example, a transplant-complication code).
summarise_prior_hospitalizations <- function(records, cohort_index, flag_column) {
  prior <- records %>%
    inner_join(
      cohort_index %>% select(USRDS_ID, index_admit_date),
      by = "USRDS_ID",
      relationship = "many-to-one"
    ) %>%
    filter(CLM_FROM < index_admit_date) %>%
    group_by(USRDS_ID) %>%
    summarise(prior = any(.data[[flag_column]]), .groups = "drop")

  cohort_index %>%
    select(USRDS_ID) %>%
    left_join(prior, by = "USRDS_ID", relationship = "one-to-one") %>%
    mutate(prior = coalesce(prior, FALSE))
}

## ---- summarise-transplant-history
# Transplant history at the index admission, from the USRDS transplant file
# (one row per transplant; needs USRDS_ID, TDATE, FAILDATE):
#   transplants_before_index: transplants dated on or before index admission;
#   failures_before_index: graft failures dated before index admission;
#   last_transplant_date, days_since_last_transplant: most recent transplant
#     on or before index admission.
summarise_transplant_history <- function(transplants, cohort_index) {
  transplants %>%
    inner_join(
      cohort_index %>% select(USRDS_ID, index_admit_date),
      by = "USRDS_ID",
      relationship = "many-to-one"
    ) %>%
    filter(!is.na(TDATE), TDATE <= index_admit_date) %>%
    group_by(USRDS_ID) %>%
    summarise(
      transplants_before_index = n(),
      failures_before_index = sum(!is.na(FAILDATE) & FAILDATE < index_admit_date),
      last_transplant_date = max(TDATE),
      days_since_last_transplant = as.numeric(first(index_admit_date) - max(TDATE)),
      .groups = "drop"
    )
}

## ---- select-index-registration
# The UNOS registration of each person's most recent transplant on or before
# the index admission (decided 2026-11-10). `registrations` needs USRDS_ID and
# TDATE; returns one row per person.
select_index_registration <- function(registrations, cohort_index) {
  registrations %>%
    inner_join(
      cohort_index %>% select(USRDS_ID, index_admit_date),
      by = "USRDS_ID",
      relationship = "many-to-one"
    ) %>%
    filter(!is.na(TDATE), TDATE <= index_admit_date) %>%
    group_by(USRDS_ID) %>%
    slice_max(TDATE, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(-index_admit_date)
}

## ---- unos-rejection-any
# UNOS acute rejection (format ACREJEPI): 1 (treated) or 2 (not treated with
# an additional agent) is an episode; 3 is none; blank, 990 and 998 (unknown)
# are missing (decided 2026-11-10).
unos_rejection_any <- function(code) {
  code <- as.character(code)
  case_when(
    code %in% c("1", "2") ~ TRUE,
    code == "3" ~ FALSE,
    .default = NA
  )
}

## ---- classify-immunosuppressants
# One row per key with one logical column per drug class: TRUE when any of the
# key's drug records maps to the class, by drug code (RX_CD) or by free text
# (DRUG_CD_OSTXT). Keys with no records are absent; callers decide whether
# absence means "not on" or missing.
classify_immunosuppressants <- function(drug_records, key, rx_classes, free_text) {
  by_code <- drug_records %>%
    inner_join(
      rx_classes %>% select(rx_cd, drug_class),
      by = c("RX_CD" = "rx_cd"),
      relationship = "many-to-one"
    )
  by_text <- drug_records %>%
    inner_join(
      free_text,
      by = c("DRUG_CD_OSTXT" = "drug_text"),
      relationship = "many-to-one"
    )
  all_classes <- sort(unique(rx_classes$drug_class))

  bind_rows(by_code, by_text) %>%
    distinct(.data[[key]], drug_class) %>%
    mutate(on_drug = TRUE, drug_class = factor(drug_class, levels = all_classes)) %>%
    pivot_wider(
      names_from = drug_class,
      values_from = on_drug,
      values_fill = FALSE,
      names_expand = TRUE
    ) %>%
    right_join(distinct(drug_records, .data[[key]]), by = key) %>%
    mutate(across(all_of(all_classes), \(x) coalesce(x, FALSE)))
}

## ---- recode-demographics
# Sex and race (USRDS transplant file codes) and Hispanic ethnicity (patients
# file, format $YNUFMT: 1 or Y yes, 2 or N no, anything else missing).
recode_sex <- function(code) {
  case_when(code == "1" ~ "Male", code == "2" ~ "Female", .default = NA)
}

recode_race <- function(code) {
  case_when(
    code == "1" ~ "White",
    code == "2" ~ "Black",
    code %in% c("3", "4", "5", "6") ~ "Other",
    .default = NA
  )
}

recode_hispanic <- function(code) {
  case_when(
    code %in% c("1", "Y") ~ "Hispanic",
    code %in% c("2", "N") ~ "Non-Hispanic",
    .default = NA
  )
}

## ---- any-known
# Combine logical values, keeping missing distinct from "no": TRUE if any value
# is TRUE; FALSE if none is TRUE and at least one is FALSE; NA if all are
# missing (or there are none).
any_known <- function(x) {
  case_when(
    any(x %in% TRUE) ~ TRUE,
    any(x %in% FALSE) ~ FALSE,
    .default = NA
  )
}

## ---- load-flagged-hospitalizations
# Load one hospitalization file for a set of people (usRds::load_usrds_file())
# and flag diagnosis and procedure concepts on each record, keeping the key
# fields, ICU/CCU days and the flags. Codes stay character
# (factor_labels = FALSE). Columns are selected after loading because of
# usRds#22. usRds gap (coverage map, steps 4-9).
load_flagged_hospitalizations <- function(file_root, ids, dx_columns, proc_columns,
                                          dx_concepts, proc_concepts, code_lists) {
  key_columns <- c("USRDS_ID", "CLM_FROM", "CLM_THRU", "ICU_DAYS", "CCU_DAYS")

  load_usrds_file(
    file_root,
    factor_labels = FALSE,
    usrds_ids = ids
  ) %>%
    select(all_of(c(key_columns, dx_columns, proc_columns))) %>%
    flag_concepts(dx_columns, code_lists, dx_concepts) %>%
    flag_concepts(proc_columns, code_lists, proc_concepts) %>%
    select(all_of(c(key_columns, dx_concepts, proc_concepts)))
}

## ---- six-month-outcomes
# Mortality outcomes from the index admission (plan §7): days to death;
# died_within_window (death on or before day `window_days`, with the
# admission day as day 0); and survival time and event for Kaplan-Meier,
# censored at `data_end_date`. A death on the admission day has time 0.
# `deaths` needs USRDS_ID and DIED (missing if alive).
six_month_outcomes <- function(cohort_index, deaths, window_days, data_end_date) {
  if (is.na(data_end_date)) {
    stop(
      "death_data_end_date must be set in R/setup.R for the USRDS release in use.",
      call. = FALSE
    )
  }

  cohort_index %>%
    select(USRDS_ID, index_admit_date) %>%
    left_join(deaths %>% select(USRDS_ID, DIED), by = "USRDS_ID", relationship = "one-to-one") %>%
    mutate(
      death_observed = !is.na(DIED) & DIED <= data_end_date,
      days_to_death = if_else(death_observed, as.numeric(DIED - index_admit_date), NA),
      died_within_window = death_observed & days_to_death <= window_days,
      survival_days = if_else(
        death_observed,
        days_to_death,
        as.numeric(data_end_date - index_admit_date)
      ),
      survival_event = as.integer(death_observed)
    ) %>%
    select(-DIED, -index_admit_date, -death_observed)
}

## ---- wald-term-p
# Joint Wald test P value for one term of a fitted glm (all its coefficients
# together, so a factor gets one P value), as Stata's stepwise uses by
# default.
wald_term_p <- function(model, term) {
  term_index <- match(term, attr(terms(model), "term.labels"))
  columns <- which(attr(model.matrix(model), "assign") == term_index)
  estimates <- coef(model)[columns]
  keep <- !is.na(estimates)
  estimates <- estimates[keep]
  if (length(estimates) == 0) {
    # No estimable coefficient (the term does not vary in the sample)
    return(NA_real_)
  }
  covariance <- vcov(model)[names(estimates), names(estimates), drop = FALSE]
  statistic <- as.numeric(t(estimates) %*% solve(covariance) %*% estimates)
  pchisq(statistic, df = length(estimates), lower.tail = FALSE)
}

## ---- bivariable-models
# One logistic model per candidate (outcome ~ candidate), each on the people
# with that candidate known. Returns the term, people used, and Wald P value
# (NA when the candidate does not vary among them).
bivariable_models <- function(data, outcome, candidates) {
  map(candidates, \(candidate) {
    model_data <- data %>%
      select(all_of(c(outcome, candidate))) %>%
      drop_na()
    model <- glm(
      reformulate(candidate, response = outcome),
      family = binomial(),
      data = model_data
    )
    tibble(
      term = candidate,
      n = nrow(model_data),
      p_value = wald_term_p(model, candidate),
      model = list(model)
    )
  }) %>%
    list_rbind()
}

## ---- backward-eliminate
# Backward elimination for a logistic model (plan §8): start from every
# candidate on the complete cases for all of them (the sample stays fixed, as
# in Stata's stepwise), and repeatedly remove the term with the largest Wald
# P value while it is at or above `threshold`. A term with no estimable
# coefficient in that sample (no variation, P value NA) is removed first, as
# Stata omits it. Returns the final model, the fixed sample and the removal
# steps.
backward_eliminate <- function(data, outcome, candidates, threshold) {
  model_data <- data %>%
    select(all_of(c(outcome, candidates))) %>%
    drop_na()
  remaining <- candidates
  steps <- tibble(step = integer(), removed = character(), p_value = numeric())

  repeat {
    model <- glm(reformulate(remaining, response = outcome), family = binomial(), data = model_data)
    p_values <- map_dbl(remaining, \(term) wald_term_p(model, term))
    worst <- if (anyNA(p_values)) which(is.na(p_values))[1] else which.max(p_values)
    if (!is.na(p_values[worst]) && p_values[worst] < threshold) {
      break
    }
    steps <- add_row(steps, step = nrow(steps) + 1L, removed = remaining[worst], p_value = p_values[worst])
    remaining <- remaining[-worst]
    if (length(remaining) == 0) {
      model <- glm(reformulate("1", response = outcome), family = binomial(), data = model_data)
      break
    }
  }

  list(model = model, data = model_data, steps = steps, retained = remaining)
}

## ---- hosmer-lemeshow
# Hosmer-Lemeshow goodness-of-fit test with `groups` groups of predicted risk
# (deciles by default): the statistic compares observed and expected events
# in each group, on groups - 2 degrees of freedom.
hosmer_lemeshow <- function(observed, predicted, groups = 10) {
  breaks <- unique(quantile(predicted, probs = seq(0, 1, length.out = groups + 1)))
  risk_group <- cut(predicted, breaks = breaks, include.lowest = TRUE)
  table <- tibble(observed, predicted, risk_group) %>%
    group_by(risk_group) %>%
    summarise(n = n(), observed = sum(observed), expected = sum(predicted), .groups = "drop")
  statistic <- sum((table$observed - table$expected)^2 / (table$expected * (1 - table$expected / table$n)))
  df <- nrow(table) - 2
  list(
    statistic = statistic,
    df = df,
    p_value = pchisq(statistic, df = df, lower.tail = FALSE),
    table = table
  )
}

## ---- count-table-cells
# The counts behind a descriptive table, one row per variable, level and
# group: every level of a categorical variable, both TRUE and FALSE for a
# logical variable (only TRUE is shown in the table; FALSE can be derived),
# and the missing count. `groups` is the grouping column; an "Overall" group
# is added. Continuous variables contribute only their missing count.
count_table_cells <- function(data, variables, group) {
  long_data <- bind_rows(
    data %>% mutate(.group = as.character(.data[[group]])),
    data %>% mutate(.group = "Overall")
  )

  map(variables, \(variable) {
    values <- long_data[[variable]]
    level <- case_when(
      is.na(values) ~ "(missing)",
      is.numeric(values) ~ "(value)",
      .default = as.character(values)
    )
    tibble(variable = variable, level = level, group = long_data$.group) %>%
      count(variable, level, group) %>%
      complete(variable, level, group, fill = list(n = 0L)) %>%
      mutate(
        shown = case_when(
          level == "(value)" ~ FALSE,
          is.logical(values) & level == "FALSE" ~ FALSE,
          .default = TRUE
        )
      )
  }) %>%
    list_rbind()
}

## ---- flag-small-cells
# Small-cell suppression (plan §10; USRDS rule: no count from 1 to
# `threshold`, including counts recoverable by subtraction). Input: one row
# per variable, level and group, with n and whether the cell is shown
# (FALSE for cells that are only derivable, such as the FALSE count of a
# logical variable, or continuous values). Returns the input with
# `suppress`: TRUE for every shown cell that must be hidden.
#   1. Primary: any cell (shown or derivable) with 1 to `threshold`.
#   2. Within a variable and group, the levels sum to the group size, so if
#      exactly one cell is unknown it can be recovered: hide the smallest
#      other non-zero shown cell.
#   3. Across groups, the groups sum to "Overall", so if exactly one cell of
#      a variable and level is unknown, hide the smallest other non-zero
#      shown cell.
# Rules 2 and 3 repeat until nothing changes. A derivable small cell counts
# as unknown only once another cell in its sum is hidden, which these rules
# ensure.
flag_small_cells <- function(counts, threshold = 10) {
  cells <- counts %>%
    mutate(unknown = n >= 1 & n <= threshold, .row = row_number())

  hide_one_more <- function(cells, by) {
    cells %>%
      group_by(across(all_of(by))) %>%
      mutate(
        .needs = sum(unknown) == 1,
        .candidate = shown & !unknown & n > 0,
        .pick = .needs & .candidate &
          n == suppressWarnings(min(n[.candidate])) &
          .row == suppressWarnings(min(.row[.candidate & n == min(n[.candidate])]))
      ) %>%
      ungroup() %>%
      mutate(unknown = unknown | .pick) %>%
      select(-.needs, -.candidate, -.pick)
  }

  repeat {
    before <- sum(cells$unknown)
    cells <- cells %>%
      hide_one_more(c("variable", "group")) %>%
      hide_one_more(c("variable", "level"))
    if (sum(cells$unknown) == before) {
      break
    }
  }

  unresolved <- cells %>%
    filter(unknown) %>%
    group_by(variable) %>%
    filter(!any(shown & unknown))
  if (nrow(unresolved) > 0) {
    warning(
      "Small derivable cells with no shown cell to hide in: ",
      str_flatten_comma(unique(unresolved$variable)),
      call. = FALSE
    )
  }

  cells %>%
    mutate(suppress = shown & unknown) %>%
    select(-unknown, -.row)
}

## ---- km-reportable-times
# Times at which a Kaplan-Meier curve and risk table can be shown under the
# small-cell rule: more than `threshold` people still at risk (so the curve
# stops before its tail reveals small numbers), cumulative events and
# cumulative censored each 0 or above `threshold`, and every change since the
# previous time shown 0 or above `threshold`. Candidate times are tried in
# order; a time that fails is dropped and the next is compared with the last
# time kept. The curve should be drawn only up to the last time returned.
km_reportable_times <- function(km_fit, candidate_times, threshold = 10) {
  fit_summary <- summary(km_fit, times = candidate_times, extend = TRUE)
  table <- tibble(
    time = fit_summary$time,
    n_risk = fit_summary$n.risk,
    cum_event = cumsum(fit_summary$n.event),
    cum_censor = cumsum(fit_summary$n.censor)
  )
  allowed <- function(x) x == 0 | x > threshold

  kept <- integer()
  for (i in seq_len(nrow(table))) {
    current <- table[i, ]
    ok <- current$n_risk > threshold & allowed(current$cum_event) & allowed(current$cum_censor)
    if (length(kept) > 0) {
      previous <- table[last(kept), ]
      ok <- ok &
        allowed(previous$n_risk - current$n_risk) &
        allowed(current$cum_event - previous$cum_event) &
        allowed(current$cum_censor - previous$cum_censor)
    }
    if (ok) {
      kept <- c(kept, i)
    }
  }
  table$time[kept]
}

## ---- flowchart-small-counts
# Boxes of a flowchart (the tibble from flowchart::fc_view(x, "fc"), with
# columns id, type, label and n) whose count is from 1 to `threshold`. Every
# exclusion is drawn with its own count (show_exc = TRUE), so no count is
# left to be recovered by subtraction; exported diagrams must return no rows.
flowchart_small_counts <- function(fc_boxes, threshold = 10) {
  fc_boxes %>%
    filter(!is.na(n), n >= 1, n <= threshold) %>%
    select(id, type, label, n)
}

## ---- tidy-odds-ratios
# Adjusted odds ratios with 95% Wald confidence intervals (as Stata's
# logistic reports them) from a logistic glm, one row per coefficient, with readable term labels from `labels` (a
# named character vector: variable name -> label) and the level appended for
# factors.
tidy_odds_ratios <- function(model, labels) {
  broom::tidy(model) %>%
    filter(term != "(Intercept)") %>%
    mutate(
      conf.low = exp(estimate - qnorm(0.975) * std.error),
      conf.high = exp(estimate + qnorm(0.975) * std.error),
      estimate = exp(estimate)
    ) %>%
    mutate(
      variable = map_chr(term, \(x) {
        matches <- names(labels)[str_starts(x, fixed(names(labels)))]
        if (length(matches) == 0) x else matches[which.max(nchar(matches))]
      }),
      level = str_remove(term, fixed(variable)),
      level = if_else(level %in% c("", "TRUE"), NA, level),
      term_label = if_else(
        is.na(level),
        unname(labels[variable]),
        str_c(unname(labels[variable]), ": ", level)
      )
    ) %>%
    select(term, term_label, estimate, conf.low, conf.high, p.value)
}

## ---- style-pvalue-ama
# P values in AMA style (the house style of OFID, CID and JID): 2 decimals as
# gtsummary's JAMA theme rounds them, without the leading zero (".040",
# "<.001", ">.99").
style_pvalue_ama <- function(x) {
  gtsummary::style_pvalue(x, digits = 2) %>%
    str_replace("^([<>]?)0\\.", "\\1.")
}

## ---- suppress-table-body
# Apply small-cell flags (flag_small_cells()) to a gtsummary table body: the
# cells to hide are replaced with `mask`, and the P value of any variable
# with a hidden cell is removed (with the margins, a test statistic can
# reveal the hidden counts). `group_columns` maps group names in the flags to
# table columns (for example, c(Overall = "stat_0", ...)). Logical variables
# appear on their "label" row, other levels on "level" rows, and missing
# counts on the "missing" row.
suppress_table_body <- function(table_body, flags, group_columns, mask = "≤10") {
  hidden <- flags %>%
    filter(suppress) %>%
    mutate(
      row_type = case_when(
        level == "(missing)" ~ "missing",
        level == "TRUE" ~ "label",
        .default = "level"
      ),
      column = unname(group_columns[group])
    )

  for (i in seq_len(nrow(hidden))) {
    cell <- hidden[i, ]
    rows <- table_body$variable == cell$variable & table_body$row_type == cell$row_type
    if (cell$row_type == "level") {
      rows <- rows & table_body$label == cell$level
    }
    table_body[[cell$column]][rows] <- mask
  }

  if ("p.value" %in% names(table_body)) {
    table_body$p.value[table_body$variable %in% hidden$variable] <- NA
  }
  table_body
}
