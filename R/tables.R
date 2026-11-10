# Purpose: Tables 1 and 2 (characteristics and immunosuppression by 6-month
#   vital status) and the model table (unadjusted and adjusted odds ratios),
#   with small-cell suppression (plan §8, §10).
# Needs: setup.R, functions.R, create_outcomes.R (model_data), fit_models.R
#   (km_fit, bivariable_results, multivariable, hosmer_lemeshow_result); installed:
#   gtsummary, gt, cardx, broom.helpers.
# Produces: report_labels, follow_up_summary, table_1, table_2, table_models (gtsummary tables),
#   disclosure_checks, and HTML and Word copies in tables/ (gitignored until
#   USRDS review; plan §10).

## ---- report-labels
# Readable names for every variable in a table or figure, so no column name
# reaches an output. Drug labels are shared by the at-transplant (tx_) and
# first follow-up (fu_) versions.
drug_labels <- c(
  antithymocyte_globulin = "Antithymocyte globulin",
  alemtuzumab = "Alemtuzumab",
  il2_receptor_antibody = "Anti-IL-2 receptor antibody",
  tacrolimus = "Tacrolimus",
  cyclosporine = "Cyclosporine",
  mycophenolate = "Mycophenolate",
  mtor_inhibitor = "mTOR inhibitor",
  azathioprine = "Azathioprine",
  steroids = "Steroids"
)

report_labels <- c(
  age_at_index = "Age at index admission, years",
  age_60_or_older = "Age 60 years or older",
  sex = "Sex",
  race = "Race",
  hispanic = "Hispanic ethnicity",
  region = "Census region of residence",
  organ = "Transplanted organ",
  bmi = "BMI at registration, kg/m²",
  pretransplant_dialysis = "Dialysis before transplant",
  hiv_status = "HIV serostatus",
  cmv_status = "CMV serostatus",
  more_than_one_transplant = "More than one transplant",
  prior_graft_failure = "Earlier graft failure",
  months_since_last_transplant = "Months since most recent transplant",
  over_cutoff_since_transplant = str_glue("More than {years_since_transplant_cutoff} years since most recent transplant"),
  acute_rejection = "Acute rejection episode",
  prior_transplant_complication = "Earlier hospitalization for a transplant complication",
  cryptococcal_meningitis = "Cryptococcal meningitis",
  acute_kidney_injury = "Acute kidney injury",
  diabetes = "Diabetes",
  cirrhosis = "Cirrhosis",
  icu_admission = "ICU admission",
  lumbar_puncture = "Lumbar puncture",
  spinal_procedure = "Other spinal procedure",
  neurosurgical_procedure = "Neurosurgical procedure",
  lung_procedure = "Lung procedure",
  vp_shunt = "Ventriculoperitoneal shunt",
  no_tacrolimus_at_transplant = "Not on tacrolimus at transplant",
  no_tacrolimus_at_followup = "Not on tacrolimus at first follow-up",
  set_names(str_c(drug_labels, " at transplant"), str_c("tx_", names(drug_labels))),
  set_names(str_c(drug_labels, " at first follow-up"), str_c("fu_", names(drug_labels)))
)

## ---- table-variables
table_1_variables <- c(
  "age_at_index", "age_60_or_older", "sex", "race", "hispanic", "region",
  "organ", "bmi", "pretransplant_dialysis", "hiv_status", "cmv_status",
  "more_than_one_transplant", "prior_graft_failure",
  "months_since_last_transplant", "over_cutoff_since_transplant",
  "acute_rejection", "prior_transplant_complication",
  "cryptococcal_meningitis", "acute_kidney_injury", "diabetes", "cirrhosis",
  "icu_admission", "lumbar_puncture", "spinal_procedure",
  "neurosurgical_procedure", "lung_procedure", "vp_shunt"
)
# Table 2 follows the paper's rows and order: induction agents only at
# transplant, steroids first in both blocks.
table_2_variables <- c(
  str_c("tx_", c(
    "steroids", "antithymocyte_globulin", "alemtuzumab", "il2_receptor_antibody",
    "tacrolimus", "cyclosporine", "mycophenolate", "mtor_inhibitor", "azathioprine"
  )),
  str_c("fu_", c(
    "steroids", "tacrolimus", "cyclosporine", "mycophenolate", "mtor_inhibitor", "azathioprine"
  ))
)

# The grouping column: 6-month vital status, survivors first
table_data <- model_data %>%
  mutate(
    vital_status = factor(
      if_else(died_within_window, "Died", "Survived"),
      levels = c("Survived", "Died")
    )
  )
table_group_columns <- c(Overall = "stat_0", Survived = "stat_1", Died = "stat_2")

## ---- descriptive-table
# One descriptive table by vital status (plan §8): mean (SD) for continuous
# variables, median (IQR) for time since transplant, n (%) otherwise, with
# missing counts always shown. Student t test for continuous variables; for
# categorical ones, the chi-squared test without continuity correction, or
# Fisher's exact test when an expected count is under 5 (gtsummary's
# default rule). Small cells are then hidden (plan §10).
describe_by_vital_status <- function(data, variables, labels, medians = character()) {
  counts <- count_table_cells(data, variables, group = "vital_status")
  flags <- flag_small_cells(counts)

  table <- data %>%
    select(all_of(c("vital_status", variables))) %>%
    gtsummary::tbl_summary(
      by = vital_status,
      label = as.list(labels[variables]),
      statistic = c(
        list(
          gtsummary::all_continuous() ~ "{mean} ({sd})",
          gtsummary::all_categorical() ~ "{n} ({p}%)"
        ),
        as.list(set_names(rep("{median} ({p25}, {p75})", length(medians)), medians))
      ),
      digits = list(gtsummary::all_categorical() ~ c(0, 1)),
      missing = "always",
      missing_text = "Unknown"
    ) %>%
    gtsummary::add_overall(last = FALSE) %>%
    gtsummary::add_p(
      test = list(gtsummary::all_continuous() ~ "t.test"),
      test.args = list(gtsummary::all_continuous() ~ list(var.equal = TRUE)),
      pvalue_fun = gtsummary::label_style_pvalue(digits = 2)
    ) %>%
    gtsummary::modify_table_body(
      \(body) suppress_table_body(body, flags, table_group_columns)
    ) %>%
    gtsummary::modify_footnote_header(
      "Cells with 1 to 10 people, and cells from which they could be recovered, are shown as ≤10, and their P values are removed (USRDS data use agreement).",
      columns = gtsummary::all_stat_cols(),
      replace = FALSE
    )

  list(table = table, flags = flags)
}

## ---- table-1
table_1_result <- describe_by_vital_status(
  table_data, table_1_variables, report_labels,
  medians = "months_since_last_transplant"
)
table_1 <- table_1_result$table %>%
  gtsummary::modify_caption("**Table 1.** Characteristics of kidney transplant recipients hospitalized with cryptococcosis, by vital status 6 months after admission")

## ---- table-2
# Immunosuppression at transplant and at the first follow-up visit, from the
# UNOS records (plan §5), as two blocks of one table.
table_2_result <- describe_by_vital_status(table_data, table_2_variables, report_labels)
table_2 <- table_2_result$table %>%
  gtsummary::modify_caption("**Table 2.** Immunosuppression at transplant and at the first follow-up visit, by vital status 6 months after admission")

## ---- follow-up
# Follow-up before any model (time to event): deaths, censoring, and median
# follow-up by the reverse Kaplan-Meier method (censoring treated as the
# event). Counts here pass the same small-count rule as the tables.
reverse_km <- survival::survfit(
  survival::Surv(survival_days, 1 - survival_event) ~ 1,
  data = analysis_data
)
follow_up_summary <- tibble(
  measure = c(
    "People", "Deaths", "Censored",
    "Deaths within 6 months", "Median follow-up, days (95% CI)"
  ),
  value = c(
    nrow(analysis_data),
    sum(analysis_data$survival_event),
    sum(analysis_data$survival_event == 0),
    sum(model_data$died_within_window),
    str_glue(
      "{summary(reverse_km)$table[['median']]} ",
      "({summary(reverse_km)$table[['0.95LCL']]}, {summary(reverse_km)$table[['0.95UCL']]})"
    )
  ) %>%
    as.character()
)

## ---- table-models
# Unadjusted (each candidate alone) and adjusted (final backward-elimination
# model) odds ratios with 95% Wald confidence intervals. P values are the
# joint Wald P per term that the selection used (plan §8), one per variable,
# not one per factor level. Candidates with no estimable coefficient (no
# variation among the people with them known) are listed in a footnote.
replace_term_p <- function(body, term_p) {
  body %>%
    left_join(term_p, by = "variable") %>%
    mutate(p.value = if_else(row_type == "label", term_p_value, NA_real_)) %>%
    select(-term_p_value)
}

estimable <- bivariable_results %>% filter(!is.na(p_value))
not_estimable <- bivariable_results %>% filter(is.na(p_value))
# Yes/no variables are shown on one row (the odds ratio for yes)
logical_terms <- estimable$term[map_lgl(model_data[estimable$term], is.logical)]

table_unadjusted <- model_data %>%
  select(all_of(c("died_within_window", estimable$term))) %>%
  gtsummary::tbl_uvregression(
    method = glm,
    y = died_within_window,
    method.args = list(family = binomial),
    exponentiate = TRUE,
    label = as.list(report_labels[estimable$term]),
    show_single_row = all_of(logical_terms),
    pvalue_fun = gtsummary::label_style_pvalue(digits = 2),
    hide_n = TRUE
  ) %>%
  gtsummary::modify_table_body(
    \(body) replace_term_p(body, tibble(variable = estimable$term, term_p_value = estimable$p_value))
  )

adjusted_p <- tibble(
  variable = multivariable$retained,
  term_p_value = map_dbl(multivariable$retained, \(term) wald_term_p(multivariable$model, term))
)
table_adjusted <- multivariable$model %>%
  gtsummary::tbl_regression(
    exponentiate = TRUE,
    label = as.list(report_labels[multivariable$retained]),
    show_single_row = all_of(intersect(logical_terms, multivariable$retained)),
    pvalue_fun = gtsummary::label_style_pvalue(digits = 2)
  ) %>%
  gtsummary::modify_table_body(\(body) replace_term_p(body, adjusted_p))

model_n <- nobs(multivariable$model)
model_events <- sum(multivariable$data$died_within_window)
model_excluded <- nrow(model_data) - model_n

table_models <- gtsummary::tbl_merge(
  list(table_unadjusted, table_adjusted),
  tab_spanner = c("**Unadjusted**", "**Adjusted**")
) %>%
  gtsummary::modify_caption("**Table 3.** Odds ratios for death within 6 months of admission") %>%
  gtsummary::modify_source_note(
    str_glue(
      "Unadjusted: one logistic model per variable, on the people with it known. ",
      "Adjusted: backward elimination from all candidates (removed while P ≥ {elimination_threshold}), ",
      "on the {model_n} people with every candidate known ({model_events} deaths; {model_excluded} excluded for missing data). ",
      "P values are joint Wald tests, one per variable. ",
      "Hosmer-Lemeshow test of the adjusted model: χ² = {round(hosmer_lemeshow_result$statistic, 2)}, ",
      "df = {hosmer_lemeshow_result$df}, P = {gtsummary::style_pvalue(hosmer_lemeshow_result$p_value, digits = 2)}."
    )
  )
if (nrow(not_estimable) > 0) {
  table_models <- table_models %>%
    gtsummary::modify_source_note(
      str_c("Not estimable (no variation): ", str_flatten_comma(report_labels[not_estimable$term]), ".")
    )
}

## ---- disclosure-checks
# What a reviewer needs before release (plan §10): cells hidden in each
# table, and counts the tables cannot hide themselves. Rows with
# needs_review = TRUE must be resolved before anything leaves the approved
# environment.
group_sizes <- table(table_data$vital_status)
disclosure_checks <- tibble(
  check = c(
    "Table 1: cells hidden",
    "Table 2: cells hidden",
    "Smallest vital-status group",
    "People excluded from the adjusted model for missing data",
    "Deaths in the adjusted model",
    "Smallest of deaths and censored in follow-up"
  ),
  value = c(
    sum(table_1_result$flags$suppress),
    sum(table_2_result$flags$suppress),
    min(group_sizes),
    model_excluded,
    model_events,
    min(sum(analysis_data$survival_event), sum(analysis_data$survival_event == 0))
  ),
  needs_review = c(
    FALSE,
    FALSE,
    min(group_sizes) <= 10,
    between(model_excluded, 1, 10),
    between(model_events, 1, 10),
    between(min(sum(analysis_data$survival_event), sum(analysis_data$survival_event == 0)), 1, 10)
  )
)

## ---- save-tables
dir.create("tables", showWarnings = FALSE)
walk2(
  list(table_1, table_2, table_models),
  c("table_1", "table_2", "table_models"),
  \(table, name) {
    gt_table <- gtsummary::as_gt(table)
    gt::gtsave(gt_table, file.path("tables", str_c(name, ".html")))
    gt::gtsave(gt_table, file.path("tables", str_c(name, ".docx")))
  }
)
