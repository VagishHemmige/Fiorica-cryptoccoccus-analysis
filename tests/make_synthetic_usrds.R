# Purpose: write a small synthetic USRDS folder (Parquet files in the folder
#   layout usRds maps) so the whole analysis can run without restricted data.
#   Every value is invented; nothing is derived from USRDS records.
# Needs: dplyr, tidyr, purrr, stringr, arrow.
# Produces: make_synthetic_usrds(path, n_people, seed), which writes the
#   folder and returns its path.
#
# The data are built to exercise the analysis, not to resemble the cohort:
# some cryptococcosis stays fall before the first transplant, some people
# with cryptococcosis are not in the transplant file, a few are outside the
# age range, and 6-month mortality depends on ICU admission, cirrhosis, acute
# kidney injury and age 60 or older.

make_synthetic_usrds <- function(path = file.path(tempdir(), "synthetic_usrds"),
                                 n_people = 4000, seed = 20261110) {
  set.seed(seed)
  d <- function(x) as.Date(x)
  draw <- function(x, n, prob = NULL) sample(x, n, replace = TRUE, prob = prob)
  folders <- c(core = "ESRD Core", transplant = "ESRD transplant", hospital = "ESRD hospital")
  for (folder in folders) dir.create(file.path(path, folder), recursive = TRUE, showWarnings = FALSE)
  write <- function(df, folder, file) arrow::write_parquet(df, file.path(path, folders[[folder]], paste0(file, ".parquet")))

  ids <- seq_len(n_people) + 100000
  # Most people have a transplant; 5% do not (so they leave the cohort)
  has_tx <- runif(n_people) > 0.05
  first_tx <- d("2001-01-01") + draw(0:5000, n_people)
  born <- first_tx - round(365.25 * draw(c(16:85, 92:95), n_people))

  ## Transplants: first, and a second for 12%
  second <- has_tx & runif(n_people) < 0.12
  tx <- bind_rows(
    tibble(USRDS_ID = ids[has_tx], TDATE = first_tx[has_tx], n = 1L),
    tibble(USRDS_ID = ids[second], TDATE = first_tx[second] + draw(400:2500, sum(second)), n = 2L)
  ) %>%
    mutate(
      FAILDATE = if_else(n == 1 & USRDS_ID %in% ids[second], TDATE + draw(200:390, n()), as.Date(NA)),
      RSEX = draw(c("1", "2"), n()),
      RACE = draw(c("1", "2", "4", "6", "9"), n(), prob = c(.6, .3, .05, .03, .02))
    ) %>%
    arrange(USRDS_ID, TDATE)
  write(tx %>% select(-n), "core", "tx")

  ## Cryptococcosis hospitalization: one per person, after the most relevant
  ## transplant for 92%, before the first transplant for 8%
  last_tx <- tx %>% group_by(USRDS_ID) %>% summarise(last_tx = max(TDATE))
  people <- tibble(USRDS_ID = ids, first_tx, born, has_tx) %>%
    left_join(last_tx, by = "USRDS_ID") %>%
    mutate(
      before_tx = runif(n()) < 0.08,
      admit = case_when(
        before_tx ~ first_tx - draw(30:900, n()),
        !is.na(last_tx) ~ last_tx + draw(20:2500, n()),
        .default = first_tx + draw(20:2500, n())
      ),
      admit = pmin(pmax(admit, d("2006-01-01")), d("2016-12-31")),
      stay_days = draw(3:25, n()),
      icu = runif(n()) < 0.3,
      cirrhosis = runif(n()) < 0.05,
      aki = runif(n()) < 0.4,
      meningitis = runif(n()) < 0.5,
      diabetes = runif(n()) < 0.4
    )

  ## Hospitalization records: the index stay (sometimes split in two
  ## overlapping records), plus an earlier stay with a transplant
  ## complication for 30%
  dx_old <- str_c("HSDIAG", 1:10); dx_new <- str_c("HSDIAG", 1:26)
  sg_old <- str_c("HSSURG", 1:10); sg_new <- str_c("HSSURG", 1:25)
  crypto_code <- function(date, meningitis) if_else(date < d("2015-10-01"), if_else(meningitis, "3210", "1175"), if_else(meningitis, "B451", "B459"))
  index_records <- people %>%
    mutate(
      split = runif(n()) < 0.25,
      CLM_FROM = admit,
      CLM_THRU = admit + stay_days
    )
  records <- bind_rows(
    index_records %>% transmute(USRDS_ID, CLM_FROM, CLM_THRU = if_else(split, CLM_FROM + 3, CLM_THRU),
      d1 = crypto_code(CLM_THRU, meningitis), d2 = if_else(diabetes, if_else(CLM_THRU < d("2015-10-01"), "25000", "E11649"), NA),
      d3 = NA_character_, proc = if_else(meningitis & runif(n()) < 0.7, if_else(CLM_THRU < d("2015-10-01"), "0331", "009U3ZX"), NA),
      ICU_DAYS = if_else(icu & !split, draw(1:6, n()), 0L), CCU_DAYS = 0L),
    index_records %>% filter(split) %>% transmute(USRDS_ID, CLM_FROM = CLM_FROM + 3, CLM_THRU,
      d1 = if_else(aki, if_else(CLM_THRU < d("2015-10-01"), "5849", "N179"), "4019"),
      d2 = if_else(cirrhosis, if_else(CLM_THRU < d("2015-10-01"), "5715", "K7469"), NA), d3 = NA_character_,
      proc = NA_character_, ICU_DAYS = if_else(icu, draw(1:6, n()), 0L), CCU_DAYS = 0L),
    index_records %>% filter(!split) %>% transmute(USRDS_ID, CLM_FROM, CLM_THRU,
      d1 = "4019", d2 = if_else(aki, if_else(CLM_THRU < d("2015-10-01"), "5849", "N179"), NA),
      d3 = if_else(cirrhosis, if_else(CLM_THRU < d("2015-10-01"), "5715", "K7469"), NA), proc = NA_character_,
      ICU_DAYS = 0L, CCU_DAYS = 0L) %>%
      mutate(CLM_FROM = CLM_FROM + 1, CLM_THRU = CLM_FROM + 1),
    people %>% filter(runif(n()) < 0.3) %>% transmute(USRDS_ID, CLM_FROM = admit - draw(60:500, n()), CLM_THRU = CLM_FROM + 4,
      d1 = if_else(CLM_THRU < d("2015-10-01"), "99681", "T8612"), d2 = NA_character_, d3 = NA_character_,
      proc = NA_character_, ICU_DAYS = 0L, CCU_DAYS = 0L)
  )

  widen <- function(df, dx_cols, sg_cols, old) {
    out <- df %>% transmute(USRDS_ID, CLM_FROM, CLM_THRU, ICU_DAYS, CCU_DAYS)
    for (col in c(dx_cols, sg_cols)) out[[col]] <- NA_character_
    if (old) {
      out$PRIMDIAG <- "Y"
      out$HSDIAG1 <- df$d1; out$HSDIAG2 <- df$d2; out$HSDIAG10 <- df$d3
    } else {
      out$PRIMDIAG <- df$d1; out$HSDIAG1 <- df$d2; out$HSDIAG26 <- df$d3
    }
    out$HSSURG1 <- df$proc
    out
  }
  write(widen(filter(records, CLM_FROM < d("2010-01-01")), dx_old, sg_old, TRUE), "hospital", "hosp_to2009")
  write(widen(filter(records, CLM_FROM >= d("2010-01-01")), dx_new, sg_new, FALSE), "hospital", "hosp_2010on")

  ## Patients: deaths depend on ICU, cirrhosis, AKI and age 60 or older
  age_at_admit <- as.numeric(people$admit - people$born) / 365.25
  risk <- plogis(-2.4 + 1.0 * people$icu + 1.1 * people$cirrhosis + 0.5 * people$aki + 0.7 * (age_at_admit >= 60))
  dies <- runif(n_people) < risk
  patients <- tibble(
    USRDS_ID = ids, BORN = people$born,
    DIED = if_else(dies, people$admit + draw(0:179, n_people), if_else(runif(n_people) < 0.3, people$admit + draw(181:1500, n_people), as.Date(NA))),
    HISPANIC = draw(c("1", "2", "N", "Y", "9"), n_people, prob = c(.05, .7, .15, .05, .05)),
    STATE = draw(c("36", "06", "48", "17", "12", "15", "02", "72", "99"), n_people, prob = c(.15, .15, .2, .15, .2, .03, .02, .05, .05))
  )
  write(patients, "core", "patients")

  ## UNOS registration (kidney 95%, kidney-pancreas 5%), follow-up and drugs
  trr <- tx %>% mutate(TRR_ID = str_c("R", row_number()), kp = runif(n()) < 0.05,
    BMI = round(rnorm(n(), 27, 5), 1), PRE_TX_DIAL = draw(c("Y", "N", "U"), n(), prob = c(.85, .13, .02)),
    HIV_SEROSTATUS = draw(c("N", "P", "U", "ND"), n(), prob = c(.9, .02, .05, .03)),
    CMV_STATUS = draw(c("N", "P", "U"), n(), prob = c(.4, .55, .05)),
    REJ = draw(c(1, 2, 3, 998, NA), n(), prob = c(.06, .03, .8, .03, .08)))
  write(trr %>% filter(!kp) %>% select(USRDS_ID, TRR_ID, TDATE, BMI, PRE_TX_DIAL, HIV_SEROSTATUS, CMV_STATUS, ACUTE_REJ_EPI = REJ), "transplant", "txunos_trr_ki")
  write(trr %>% filter(kp) %>% select(USRDS_ID, TRR_ID, TDATE, BMI, PRE_TX_DIAL, HIV_SEROSTATUS, CMV_STATUS, ACUTE_REJ_EPI_KI = REJ), "transplant", "txunos_trr_kp")

  fu <- trr %>% select(USRDS_ID, TRR_ID, TDATE, kp) %>% crossing(visit = 1:4) %>%
    mutate(FUDATE = TDATE + if_else(visit == 1, 183, 365 * (visit - 1)), TRRFU_ID = str_c("F", row_number()),
      FUKIFAIL = as.Date(NA), REJ = draw(c(1, 2, 3, NA), n(), prob = c(.05, .03, .85, .07)))
  fu$FUDATE[sample(nrow(fu), 30)] <- NA
  write(fu %>% filter(!kp) %>% select(USRDS_ID, TRR_ID, TRRFU_ID, FUDATE, FUKIFAIL, ACUTE_REJ_EPI = REJ), "transplant", "txfuunos_ki")
  write(fu %>% filter(kp) %>% select(USRDS_ID, TRR_ID, TRRFU_ID, FUDATE, FUKIFAIL, ACUTE_REJ_EPI_KI = REJ), "transplant", "txfuunos_kp")

  ir <- trr %>% select(USRDS_ID, TRR_ID) %>% filter(runif(n()) < 0.95) %>%
    rowwise() %>% reframe(USRDS_ID, TRR_ID, RX_CD = c(if (runif(1) < 0.8) draw(c(5, 54, 53), 1) else draw(c(4, 44), 1), draw(c(9, 47, 55), 1), 1, if (runif(1) < 0.4) 41 else NULL)) %>%
    mutate(DRUG_CD_OSTXT = NA_character_)
  write(ir, "transplant", "txirunos")
  ifu <- fu %>% select(USRDS_ID, TRRFU_ID) %>% filter(runif(n()) < 0.9) %>%
    rowwise() %>% reframe(USRDS_ID, TRRFU_ID, RX_CD = c(if (runif(1) < 0.75) draw(c(5, 54), 1) else 4, draw(c(9, 47), 1), 1)) %>%
    mutate(DRUG_CD_OSTXT = NA_character_, RXMNTCUR = draw(c(1, 1, 1, 0), n()))
  write(ifu, "transplant", "txifunos")

  invisible(path)
}
