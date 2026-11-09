# Purpose: test the helpers in R/functions.R on small synthetic data with known
# answers. Run from the project root: testthat::test_file("tests/test-functions.R")
# All data here are synthetic, built in code, and not derived from any records.

library(dplyr)
library(tidyr)
library(stringr)
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
