# Purpose: test the helpers in R/functions.R on small synthetic data with known
# answers. Run from the project root: testthat::test_file("tests/test-functions.R")
# All data here are synthetic, built in code, and not derived from any records.

library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(purrr)
library(testthat)
# testthat runs this file from tests/, so find the project root either way
project_root <- if (file.exists("R/functions.R")) "." else ".."
source(file.path(project_root, "R", "code_lists.R"))
source(file.path(project_root, "R", "functions.R"))

test_that("code_matches handles exact and prefix codes", {
  codes <- tibble(code = c("1175", "250"), match = c("exact", "prefix"))
  values <- c("1175", "11750", "25000", "250", "2500", "E1100", NA)
  expect_equal(
    code_matches(values, codes),
    c(TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE)
  )
})

test_that("diabetes stems match as open prefixes, including long ICD-10 codes", {
  diabetes <- codes_for_concept(code_lists, "diabetes")
  expect_true(all(code_matches(
    c("E11", "E1122", "E11649", "E113291", "E0800", "25040", "3572", "36641"),
    diabetes
  )))
  expect_false(any(code_matches(c("E12", "E1", "2410", "E1500"), diabetes)))
})

test_that("cirrhosis includes 456.20 and 456.21", {
  cirrhosis <- codes_for_concept(code_lists, "cirrhosis")
  expect_true(all(code_matches(c("45620", "45621"), cirrhosis)))
})

test_that("VP shunt codes are the ten official placement codes, inside the neurosurgical list", {
  vp <- code_lists$code[code_lists$concept == "vp_shunt"]
  expect_setequal(
    vp,
    c("0234", "0016076", "00160J6", "00160K6", "0016376", "00163J6",
      "00163K6", "0016476", "00164J6", "00164K6")
  )
  expect_true(all(vp %in% code_lists$code[code_lists$concept == "neurosurgical_procedure"]))
})

test_that("each code list has its recorded source", {
  sources <- code_lists %>%
    distinct(concept, source)
  expect_setequal(
    sources$source[sources$concept == "diabetes"],
    c("reconstruction", "supplement")
  )
  expect_setequal(
    unique(code_lists$source[!code_lists$concept %in% c("cyclosporine", "tacrolimus", "vp_shunt", "diabetes", "cirrhosis")]),
    "reconstruction"
  )
  expect_equal(sum(code_lists$concept == "diabetes" & code_lists$match == "prefix"), 6)
})

test_that("codes_for_concept stops on an unknown concept", {
  expect_error(codes_for_concept(code_lists, "not_a_concept"), "No codes found")
})

test_that("flag_codes_wide searches every present column and skips missing ones", {
  synthetic_stays <- tibble(
    PRIMDIAG = c("B451", "4019", "4019", NA),
    HSDIAG1 = c(NA, "1175", "4280", "4019"),
    HSDIAG2 = c(NA, NA, NA, "B459")
  )
  crypto <- codes_for_concept(code_lists, "cryptococcosis")
  expect_equal(
    flag_codes_wide(synthetic_stays, c("PRIMDIAG", str_c("HSDIAG", 1:26)), crypto),
    c(TRUE, TRUE, FALSE, TRUE)
  )
  expect_error(flag_codes_wide(synthetic_stays, "HSSURG1", crypto), "None of the")
})

test_that("collapse_stays joins overlapping and same-day records, not later ones", {
  d <- as.Date
  synthetic_records <- tibble(
    USRDS_ID = c(1, 1, 1, 1, 2, 2),
    CLM_FROM = d(c("2010-01-01", "2010-01-05", "2010-01-20", "2010-03-01",
                   "2011-05-01", "2011-05-02")),
    CLM_THRU = d(c("2010-01-10", "2010-01-20", "2010-01-25", "2010-03-04",
                   "2011-05-10", "2011-05-03"))
  )
  result <- collapse_stays(synthetic_records)

  # Person 1: records 1-3 chain into one stay (record 3 starts on record 2's
  # discharge day); record 4 is a new stay. Person 2: record 2 lies inside
  # record 1.
  expect_equal(
    result$stay_id,
    c("1-1", "1-1", "1-1", "1-2", "2-1", "2-1")
  )
  expect_equal(result$stay_from[1:3], rep(d("2010-01-01"), 3))
  expect_equal(result$stay_thru[1:3], rep(d("2010-01-25"), 3))
  expect_equal(result$stay_thru[5:6], rep(d("2011-05-10"), 2))
})

test_that("collapse_stays gap_days joins records starting soon after discharge", {
  d <- as.Date
  synthetic_records <- tibble(
    USRDS_ID = c(1, 1),
    CLM_FROM = d(c("2010-01-01", "2010-01-12")),
    CLM_THRU = d(c("2010-01-10", "2010-01-15"))
  )
  expect_equal(n_distinct(collapse_stays(synthetic_records)$stay_id), 2)
  expect_equal(n_distinct(collapse_stays(synthetic_records, gap_days = 2)$stay_id), 1)
})

# ---- Cohort helpers ---------------------------------------------------------
# One synthetic person per scenario; IDs are invented integers.

test_that("age_in_years gives completed years, with birthdays counted on the day", {
  born <- as.Date(c("1998-03-15", "1998-03-15", "1926-01-01"))
  on <- as.Date(c("2016-03-14", "2016-03-15", "2016-12-31"))
  expect_equal(age_in_years(born, on), c(17, 18, 90))
})

test_that("first_transplant_dates takes the earliest transplant and skips missing dates", {
  synthetic_tx <- tibble(
    USRDS_ID = c(1, 1, 2, 3),
    TDATE = as.Date(c("2008-05-01", "2003-02-01", NA, "2010-01-01"))
  )
  result <- first_transplant_dates(synthetic_tx)
  expect_equal(result$USRDS_ID, c(1, 3))
  expect_equal(result$first_transplant_date, as.Date(c("2003-02-01", "2010-01-01")))
})

test_that("flag_cryptococcosis_records ignores the pre-2010 PRIMDIAG Y/N flag", {
  crypto <- codes_for_concept(code_lists, "cryptococcosis")
  synthetic_old <- tibble(
    USRDS_ID = c(1, 2),
    CLM_FROM = as.Date(c("2008-01-01", "2008-02-01")),
    CLM_THRU = as.Date(c("2008-01-05", "2008-02-03")),
    PRIMDIAG = c("Y", "Y"),
    HSDIAG1 = c("1175", "4019"),
    HSDIAG10 = c(NA, "3210")
  )
  result <- flag_cryptococcosis_records(
    synthetic_old, str_c("HSDIAG", 1:10), crypto
  )
  expect_equal(result$cryptococcosis_record, c(TRUE, TRUE))
  expect_named(result, c("USRDS_ID", "CLM_FROM", "CLM_THRU", "cryptococcosis_record"))
})

test_that("summarise_cryptococcosis_stays flags whole stays and applies the window inclusively", {
  d <- as.Date
  synthetic_records <- tibble(
    USRDS_ID = c(1, 1, 2, 3, 4),
    CLM_FROM = d(c("2006-01-01", "2006-01-03", "2016-12-31", "2005-12-31", "2017-01-01")),
    CLM_THRU = d(c("2006-01-04", "2006-01-09", "2017-01-04", "2006-01-02", "2017-01-02")),
    # Person 1: crypto code on the second record only, which overlaps the
    # first, so the stay admitted 2006-01-01 counts.
    cryptococcosis_record = c(FALSE, TRUE, TRUE, TRUE, TRUE)
  )
  result <- summarise_cryptococcosis_stays(
    synthetic_records, d("2006-01-01"), d("2016-12-31")
  )
  # Person 3 admitted the day before the window, person 4 the day after
  expect_equal(result$USRDS_ID, c(1, 2))
  expect_equal(result$stay_from, d(c("2006-01-01", "2016-12-31")))
  expect_equal(result$stay_thru, d(c("2006-01-09", "2017-01-04")))
})

test_that("build_cohort_candidates picks the first stay admitted on or after first transplant", {
  d <- as.Date
  synthetic_stays <- tibble(
    USRDS_ID = c(1, 1, 2, 3, 4),
    stay_id = c("1-1", "1-2", "2-1", "3-1", "4-1"),
    stay_from = d(c("2007-01-01", "2009-06-01", "2010-01-01", "2011-01-01", "2012-01-01")),
    stay_thru = d(c("2007-01-10", "2009-06-10", "2010-01-05", "2011-01-09", "2012-01-03"))
  )
  synthetic_first_tx <- tibble(
    USRDS_ID = c(1, 2, 3),
    # Person 1: transplant between the two stays; person 2: stay admitted on
    # the transplant date; person 3: transplant during the stay (admitted the
    # day before), so the stay does not count
    first_transplant_date = d(c("2008-01-01", "2010-01-01", "2011-01-02"))
  )
  synthetic_patients <- tibble(
    USRDS_ID = c(1, 2, 3, 4),
    BORN = d(c("1950-06-01", "1992-01-02", "1960-01-01", "1970-01-01"))
  )
  result <- build_cohort_candidates(synthetic_stays, synthetic_first_tx, synthetic_patients) %>%
    arrange(USRDS_ID)

  expect_equal(nrow(result), 4)
  expect_equal(result$in_transplant_file, c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(result$index_stay_id, c("1-2", "2-1", NA, NA))
  expect_equal(result$index_admit_date, d(c("2009-06-01", "2010-01-01", NA, NA)))
  expect_equal(result$first_transplant_date[3], d("2011-01-02"))
  # Person 2 turns 18 the day after admission
  expect_equal(result$age_at_index, c(59, 17, NA, NA))
})

test_that("a stay spanning the first transplant is not an index stay", {
  d <- as.Date
  result <- build_cohort_candidates(
    tibble(USRDS_ID = 1, stay_id = "1-1", stay_from = d("2010-01-01"), stay_thru = d("2010-01-05")),
    tibble(USRDS_ID = 1, first_transplant_date = d("2010-01-02")),
    tibble(USRDS_ID = 1, BORN = d("1960-01-01"))
  )
  expect_true(is.na(result$index_stay_id))
  expect_true(result$in_transplant_file)
})

# ---- Covariate helpers -------------------------------------------------------

test_that("summarise_index_stay uses only records within the index stay", {
  d <- as.Date
  synthetic_records <- tibble(
    USRDS_ID = c(1, 1, 1, 2),
    CLM_FROM = d(c("2010-01-01", "2010-01-04", "2010-03-01", "2012-05-01")),
    CLM_THRU = d(c("2010-01-05", "2010-01-08", "2010-03-02", "2012-05-03")),
    HSDIAG1 = c("B451", "5849", "25000", NA),
    ICU_DAYS = c(0, 2, 5, NA),
    CCU_DAYS = c(NA, 0, 0, 0)
  ) %>%
    flag_concepts("HSDIAG1", code_lists, c("cryptococcal_meningitis", "acute_kidney_injury", "diabetes"))
  synthetic_index <- tibble(
    USRDS_ID = c(1, 2),
    index_admit_date = d(c("2010-01-01", "2012-05-01")),
    index_discharge_date = d(c("2010-01-08", "2012-05-03"))
  )
  result <- summarise_index_stay(
    synthetic_records, synthetic_index,
    c("cryptococcal_meningitis", "acute_kidney_injury", "diabetes")
  )
  # Person 1: the March record (diabetes, ICU) is a later stay and is ignored
  expect_equal(result$cryptococcal_meningitis, c(TRUE, FALSE))
  expect_equal(result$acute_kidney_injury, c(TRUE, FALSE))
  expect_equal(result$diabetes, c(FALSE, FALSE))
  expect_equal(result$icu_admission, c(TRUE, FALSE))
})

test_that("summarise_prior_hospitalizations looks only before the index admission", {
  d <- as.Date
  synthetic_records <- tibble(
    USRDS_ID = c(1, 1, 2),
    CLM_FROM = d(c("2009-01-01", "2010-01-01", "2010-02-01")),
    complication = c(TRUE, FALSE, TRUE)
  )
  synthetic_index <- tibble(
    USRDS_ID = c(1, 2, 3),
    index_admit_date = d(c("2010-01-01", "2010-02-01", "2010-03-01"))
  )
  result <- summarise_prior_hospitalizations(synthetic_records, synthetic_index, "complication")
  # Person 2's complication record is the index admission itself, not prior;
  # person 3 has no hospitalization records at all
  expect_equal(result$prior, c(TRUE, FALSE, FALSE))
})

test_that("summarise_transplant_history counts transplants and failures before index", {
  d <- as.Date
  synthetic_tx <- tibble(
    USRDS_ID = c(1, 1, 1, 2),
    TDATE = d(c("2001-01-01", "2005-06-01", "2012-01-01", "2010-03-01")),
    FAILDATE = d(c("2005-01-01", "2010-03-01", NA, NA))
  )
  synthetic_index <- tibble(
    USRDS_ID = c(1, 2),
    index_admit_date = d(c("2010-03-01", "2010-03-01"))
  )
  result <- summarise_transplant_history(synthetic_tx, synthetic_index)
  # Person 1: the 2012 transplant is after index; the second graft failed on
  # the index date, which is not before it
  expect_equal(result$transplants_before_index, c(2, 1))
  expect_equal(result$failures_before_index, c(1, 0))
  expect_equal(result$last_transplant_date, d(c("2005-06-01", "2010-03-01")))
  expect_equal(result$days_since_last_transplant, c(1734, 0))
})

test_that("select_index_registration picks the most recent registration on or before index", {
  d <- as.Date
  synthetic_trr <- tibble(
    USRDS_ID = c(1, 1, 1),
    TRR_ID = c("a", "b", "c"),
    TDATE = d(c("2001-01-01", "2005-06-01", "2012-01-01"))
  )
  result <- select_index_registration(
    synthetic_trr, tibble(USRDS_ID = 1, index_admit_date = d("2010-03-01"))
  )
  expect_equal(result$TRR_ID, "b")
})

test_that("unos_rejection_any follows the ACREJEPI format", {
  expect_equal(
    unos_rejection_any(c(1, 2, 3, 990, 998, NA)),
    c(TRUE, TRUE, FALSE, NA, NA, NA)
  )
})

test_that("classify_immunosuppressants maps codes and free text to classes", {
  synthetic_drugs <- tibble(
    TRR_ID = c("a", "a", "a", "b", "c"),
    RX_CD = c(5, 47, 98, 59, 98),
    DRUG_CD_OSTXT = c(NA, NA, "Methylprednisolone", NA, "something else")
  )
  result <- classify_immunosuppressants(
    synthetic_drugs, "TRR_ID", immunosuppressant_classes, immunosuppressant_free_text
  ) %>%
    arrange(TRR_ID)
  expect_equal(result$TRR_ID, c("a", "b", "c"))
  expect_equal(result$tacrolimus, c(TRUE, TRUE, FALSE))
  expect_equal(result$mycophenolate, c(TRUE, FALSE, FALSE))
  expect_equal(result$steroids, c(TRUE, FALSE, FALSE))
  expect_equal(result$cyclosporine, c(FALSE, FALSE, FALSE))
  expect_setequal(
    setdiff(names(result), "TRR_ID"),
    unique(immunosuppressant_classes$drug_class)
  )
})

test_that("demographic recodes follow the Appendix C formats", {
  expect_equal(recode_sex(c("1", "2", "9")), c("Male", "Female", NA))
  expect_equal(recode_race(c("1", "2", "4", "9")), c("White", "Black", "Other", NA))
  # Hispanic: 2 is "No" in $YNUFMT (the reconstruction treated it as missing)
  expect_equal(
    recode_hispanic(c("1", "Y", "2", "N", "3", "9", "U", NA)),
    c("Hispanic", "Hispanic", "Non-Hispanic", "Non-Hispanic", NA, NA, NA, NA)
  )
})

test_that("state_regions places every state and DC once, and AK and HI outside", {
  regions <- state_regions %>% filter(region != "Outside")
  expect_equal(nrow(regions), 49)
  expect_equal(state_regions$region[state_regions$STATE %in% c("02", "15")], c("Outside", "Outside"))
  expect_equal(state_regions$division[state_regions$STATE == "06"], "Pacific (not Alaska or Hawaii)")
})

test_that("any_known keeps missing distinct from no", {
  expect_true(any_known(c(NA, FALSE, TRUE)))
  expect_false(any_known(c(NA, FALSE)))
  expect_true(is.na(any_known(c(NA, NA))))
  expect_true(is.na(any_known(logical(0))))
})

# ---- Outcome and model helpers -----------------------------------------------

test_that("six_month_outcomes counts day 180, day 0, and censors at the data end", {
  d <- as.Date
  synthetic_index <- tibble(USRDS_ID = 1:5, index_admit_date = d(rep("2016-01-01", 5)))
  synthetic_deaths <- tibble(
    USRDS_ID = 1:5,
    # Day 0, day 180, day 181, alive, death after the data end
    DIED = d(c("2016-01-01", "2016-06-29", "2016-06-30", NA, "2018-01-01"))
  )
  result <- six_month_outcomes(synthetic_index, synthetic_deaths, 180, d("2017-12-31"))
  expect_equal(result$days_to_death, c(0, 180, 181, NA, NA))
  expect_equal(result$died_within_window, c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(result$survival_days, c(0, 180, 181, 730, 730))
  expect_equal(result$survival_event, c(1L, 1L, 1L, 0L, 0L))
})

test_that("six_month_outcomes stops while the data end date is unset", {
  expect_error(
    six_month_outcomes(tibble(USRDS_ID = 1, index_admit_date = as.Date("2016-01-01")),
                       tibble(USRDS_ID = 1, DIED = as.Date(NA)), 180, as.Date(NA)),
    "death_data_end_date must be set"
  )
})

test_that("wald_term_p matches summary() for a one-coefficient term and gives one P for a factor", {
  set.seed(20261110)
  synthetic <- tibble(
    x = rnorm(300),
    group = factor(sample(c("a", "b", "c"), 300, replace = TRUE)),
    y = rbinom(300, 1, plogis(-0.5 + 0.8 * x))
  )
  model <- glm(y ~ x + group, family = binomial(), data = synthetic)
  expect_equal(wald_term_p(model, "x"), coef(summary(model))["x", "Pr(>|z|)"])
  expect_length(wald_term_p(model, "group"), 1)
})

test_that("backward_eliminate keeps a strong predictor, drops noise, and fixes the sample", {
  set.seed(20261110)
  n <- 2000
  synthetic <- tibble(
    strong = rbinom(n, 1, 0.4),
    noise_1 = rbinom(n, 1, 0.5),
    noise_2 = rnorm(n),
    y = rbinom(n, 1, plogis(-1.5 + 1.5 * strong))
  )
  synthetic$noise_2[1:50] <- NA
  result <- backward_eliminate(synthetic, "y", c("strong", "noise_1", "noise_2"), 0.05)
  expect_equal(result$retained, "strong")
  expect_setequal(result$steps$removed, c("noise_1", "noise_2"))
  # The complete-case sample is fixed by all candidates, even after noise_2 is removed
  expect_equal(nrow(result$data), n - 50)
  expect_equal(nobs(result$model), n - 50)
})

test_that("a term that does not vary gives an NA P value and is removed first", {
  set.seed(20261110)
  n <- 1000
  synthetic <- tibble(
    strong = rbinom(n, 1, 0.4),
    never = FALSE,
    y = rbinom(n, 1, plogis(-1.5 + 1.5 * strong))
  )
  model <- glm(y ~ strong + never, family = binomial(), data = synthetic)
  expect_true(is.na(wald_term_p(model, "never")))
  result <- backward_eliminate(synthetic, "y", c("never", "strong"), 0.05)
  expect_equal(result$retained, "strong")
  expect_equal(result$steps$removed, "never")
  expect_true(is.na(result$steps$p_value))
})

test_that("hosmer_lemeshow reproduces the statistic by hand", {
  observed <- c(0, 0, 1, 0, 1, 1, 0, 1, 1, 1)
  predicted <- c(0.1, 0.2, 0.3, 0.3, 0.5, 0.6, 0.4, 0.8, 0.9, 0.7)
  result <- hosmer_lemeshow(observed, predicted, groups = 2)
  # Two groups split at the median predicted risk (0.45):
  # low (0.1, 0.2, 0.3, 0.3, 0.4): observed 1, expected 1.3, n 5
  # high (0.5, 0.6, 0.8, 0.9, 0.7): observed 5, expected 3.5, n 5
  by_hand <- (1 - 1.3)^2 / (1.3 * (1 - 1.3 / 5)) + (5 - 3.5)^2 / (3.5 * (1 - 3.5 / 5))
  expect_equal(result$statistic, by_hand)
  expect_equal(result$df, 0)
})

# ---- Reporting helpers ---------------------------------------------------------

test_that("count_table_cells counts levels, hidden FALSE cells and missing, with Overall", {
  synthetic <- tibble(
    status = c("A", "A", "B", "B", "B"),
    flag = c(TRUE, FALSE, TRUE, NA, TRUE),
    bmi = c(20, NA, 25, 30, 22)
  )
  result <- count_table_cells(synthetic, c("flag", "bmi"), "status")
  flag_b <- result %>% filter(variable == "flag", group == "B")
  expect_equal(flag_b$n[flag_b$level == "TRUE"], 2)
  expect_equal(flag_b$n[flag_b$level == "(missing)"], 1)
  expect_false(flag_b$shown[flag_b$level == "FALSE"])
  expect_equal(result$n[result$variable == "flag" & result$group == "Overall" & result$level == "TRUE"], 3)
  expect_false(any(result$shown[result$variable == "bmi" & result$level == "(value)"]))
})

test_that("flag_small_cells hides a small cell and a second cell in its column and row", {
  # One categorical variable, three levels, two groups plus Overall
  counts <- tribble(
    ~variable, ~level, ~group, ~n, ~shown,
    "race", "White", "Alive", 500, TRUE,
    "race", "Black", "Alive", 300, TRUE,
    "race", "Other", "Alive", 5, TRUE,
    "race", "White", "Died", 100, TRUE,
    "race", "Black", "Died", 60, TRUE,
    "race", "Other", "Died", 40, TRUE,
    "race", "White", "Overall", 600, TRUE,
    "race", "Black", "Overall", 360, TRUE,
    "race", "Other", "Overall", 45, TRUE
  )
  result <- flag_small_cells(counts)
  hidden <- result %>% filter(suppress) %>% arrange(group, level)
  # Alive/Other (5) is small; in its column the next smallest, Alive/Black,
  # is hidden; in its row, Died/Other (smaller than Overall) is hidden; then
  # Died needs a second hidden cell (Died/Black), and the Black row is then
  # covered by Alive/Black and Died/Black
  expect_true(all(c("Alive|Other", "Alive|Black", "Died|Other") %in% str_c(hidden$group, "|", hidden$level)))
  # No column or row is left with exactly one hidden cell
  expect_true(all(count(hidden, group)$n != 1))
  expect_true(all(count(hidden, level)$n != 1))
})

test_that("flag_small_cells protects a small derivable FALSE cell by hiding the TRUE cell", {
  counts <- tribble(
    ~variable, ~level, ~group, ~n, ~shown,
    "dialysis", "TRUE", "Alive", 495, TRUE,
    "dialysis", "FALSE", "Alive", 5, FALSE,
    "dialysis", "(missing)", "Alive", 0, TRUE,
    "dialysis", "TRUE", "Died", 200, TRUE,
    "dialysis", "FALSE", "Died", 50, FALSE,
    "dialysis", "(missing)", "Died", 0, TRUE,
    "dialysis", "TRUE", "Overall", 695, TRUE,
    "dialysis", "FALSE", "Overall", 55, FALSE,
    "dialysis", "(missing)", "Overall", 0, TRUE
  )
  result <- flag_small_cells(counts)
  expect_true(result$suppress[result$level == "TRUE" & result$group == "Alive"])
  # Hiding Alive/TRUE leaves the TRUE row with one hidden cell, so another goes
  expect_equal(sum(result$suppress & result$level == "TRUE"), 2)
  expect_false(any(result$suppress[!result$shown]))
})

test_that("flag_small_cells leaves a table with no small cells alone", {
  counts <- tibble(
    variable = "x", level = c("a", "b", "a", "b", "a", "b"),
    group = rep(c("Alive", "Died", "Overall"), each = 2),
    n = c(100, 200, 30, 40, 130, 240), shown = TRUE
  )
  expect_false(any(flag_small_cells(counts)$suppress))
})

test_that("km_reportable_times drops times with small counts or small changes", {
  library(survival)
  # 30 people: 25 die on day 1 (so the early risk table is fine), then 5
  # deaths spread later leave fewer than 11 at risk
  synthetic <- tibble(time = c(rep(1, 25), 50, 60, 70, 80, 90), event = 1)
  fit <- survfit(Surv(time, event) ~ 1, data = synthetic)
  times <- km_reportable_times(fit, c(0, 30, 60, 100))
  # Day 0: 30 at risk, nothing yet. Days 30, 60 and 100 have 10 or fewer at
  # risk, so the curve must stop at day 0
  expect_equal(times, 0)
  # With more people the curve continues while more than 10 remain at risk
  bigger <- tibble(time = c(rep(10, 40), rep(200, 60)), event = c(rep(1, 40), rep(0, 60)))
  fit_bigger <- survfit(Surv(time, event) ~ 1, data = bigger)
  expect_equal(km_reportable_times(fit_bigger, c(0, 5, 20, 100, 250)), c(0, 5, 20, 100))
})

test_that("flowchart_small_counts finds boxes with 1 to 10 people", {
  boxes <- tibble(
    id = 1:5, type = c("init", "filter", "exclude", "filter", "exclude"),
    label = c("Start", "Kept", "Dropped", "Kept", "Dropped"),
    n = c(1000, 995, 5, 995, 0)
  )
  result <- flowchart_small_counts(boxes)
  expect_equal(result$id, 3)
})

test_that("tidy_odds_ratios gives Wald intervals and readable labels", {
  set.seed(20261110)
  synthetic <- tibble(
    icu_admission = rbinom(500, 1, 0.3) == 1,
    region = factor(sample(c("South", "West", "Midwest"), 500, TRUE)),
    y = rbinom(500, 1, plogis(-1 + 1 * icu_admission))
  )
  model <- glm(y ~ icu_admission + region, family = binomial(), data = synthetic)
  result <- tidy_odds_ratios(model, c(icu_admission = "ICU admission", region = "Region"))
  icu <- result %>% filter(term == "icu_admissionTRUE")
  se <- coef(summary(model))["icu_admissionTRUE", "Std. Error"]
  expect_equal(icu$conf.low, exp(coef(model)[["icu_admissionTRUE"]] - qnorm(0.975) * se))
  expect_equal(icu$term_label, "ICU admission")
  expect_setequal(result$term_label[str_starts(result$term, "region")], c("Region: South", "Region: West"))
})

test_that("suppress_table_body masks the right rows and drops the variable's P value", {
  # A table body shaped like gtsummary's (variable, row_type, label, stat_*)
  body <- tribble(
    ~variable, ~row_type, ~label, ~stat_0, ~stat_1, ~stat_2, ~p.value,
    "cirrhosis", "label", "Cirrhosis", "60 (5%)", "5 (0.5%)", "55 (20%)", 0.001,
    "cirrhosis", "missing", "Unknown", "0", "0", "0", NA,
    "race", "label", "Race", NA, NA, NA, 0.4,
    "race", "level", "White", "600", "500", "100", NA,
    "race", "level", "Other", "45", "5", "40", NA
  )
  flags <- tribble(
    ~variable, ~level, ~group, ~suppress,
    "cirrhosis", "TRUE", "Alive", TRUE,
    "cirrhosis", "TRUE", "Died", TRUE,
    "race", "Other", "Alive", TRUE,
    "race", "White", "Alive", FALSE
  )
  result <- suppress_table_body(body, flags, c(Overall = "stat_0", Alive = "stat_1", Died = "stat_2"))
  expect_equal(result$stat_1[1], "≤10")
  expect_equal(result$stat_2[1], "≤10")
  expect_equal(result$stat_0[1], "60 (5%)")
  expect_equal(result$stat_1[5], "≤10")
  expect_equal(result$stat_1[4], "500")
  expect_true(all(is.na(result$p.value)))
})

test_that("style_pvalue_ama drops the leading zero and keeps the bounds", {
  expect_equal(
    style_pvalue_ama(c(0.0004, 0.0123, 0.04, 0.5, 0.999, NA)),
    c("<.001", ".012", ".040", ".50", ">.99", NA)
  )
})
