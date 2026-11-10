# Architecture

This document describes how the code is organised today. What the analysis is meant to do is in `analysis-plan.md`; how each step maps to usRds is in `references/usrds-coverage.md`.

## Data flow

```mermaid
flowchart TD
  setup["R/setup.R<br/>packages, constants,<br/>hospitalization column names"] --> codes["R/code_lists.R<br/>code_lists"]
  setup --> functions["R/functions.R<br/>helpers"]
  hosp[("USRDS hospitalization files<br/>hosp_to2009, hosp_2010on")] -->|"usRds::load_usrds_file()"| cohort["R/create_cohort.R"]
  tx[("USRDS tx, patients")] -->|"usRds::load_usrds_file()"| cohort
  codes --> cohort
  functions --> cohort
  cohort --> flow["cohort_flowchart<br/>(Figure 1)"]
  cohort --> out["cohort<br/>one row per person"]
  out --> covariates["R/create_covariates.R"]
  hosp -->|"usRds::load_usrds_file()"| covariates
  tx -->|"usRds::load_usrds_file()"| covariates
  unos[("USRDS UNOS files<br/>txunos_trr, txfuunos,<br/>txirunos, txifunos")] -->|"usRds::load_usrds_file()"| covariates
  covariates --> analysis["analysis_data<br/>one row per person"]
  analysis --> outcomes["R/create_outcomes.R"]
  tx -->|"usRds::load_usrds_file()"| outcomes
  outcomes --> modeldata["analysis_data + outcomes,<br/>model_data"]
  modeldata --> models["R/fit_models.R"]
  models --> fits["km_fit, bivariable_results,<br/>multivariable, hosmer_lemeshow_result"]
  fits --> tables["R/tables.R"]
  modeldata --> tables
  tables --> tableout[/"tables/ (gitignored)<br/>Tables 1-3"/]
  style["R/plot_style.R<br/>house style (from COHERO)"] --> figures["R/figures.R"]
  fits --> figures
  flow --> figures
  tables --> figures
  figures --> figout[/"figures/ (gitignored)<br/>Figures 1-3, captions, alt text"/]
```

`R/main.R` sources the scripts in this order: `setup.R` (which sources `code_lists.R`), `functions.R`, `create_cohort.R`, `create_covariates.R`, `create_outcomes.R`, `fit_models.R`, `plot_style.R`, `tables.R`, `figures.R`. USRDS files are reached only through usRds, located by `usRds::set_USRDS_wd()` on the machine that holds them.

## Scripts

| Script | Role | Needs | Produces |
|---|---|---|---|
| `R/setup.R` | Packages; study constants (window, ages, mortality window, ICD-10 date); the hospitalization files' diagnosis and procedure column names | — | constants; `code_lists` via `code_lists.R` |
| `R/code_lists.R` | Every code list, one row per code, with code type, system, exact or prefix match and source | dplyr, tidyr, stringr | `code_lists` |
| `R/functions.R` | Helpers. Those marked "usRds gap" do work usRds does not yet do | `setup.R` | functions |
| `R/create_cohort.R` | Builds the cohort (plan §4): flags cryptococcosis on hospitalization records, combines records into stays, picks each person's index stay, and applies every exclusion through `flowchart` | `setup.R`, `functions.R`, USRDS files | `cohort_flowchart`, `cohort` |
| `R/create_outcomes.R` | Adds 6-month mortality and survival time from the patients file's death dates, censored at `death_data_end_date`; derives the model-ready variables (age 60 or older, not on tacrolimus, and so on) | `analysis_data`, USRDS patients file | `analysis_data` with outcomes, `model_data` |
| `R/fit_models.R` | Kaplan–Meier fit; one logistic model per candidate; all candidates with backward elimination (joint Wald P, fixed complete-case sample); Hosmer–Lemeshow test | `analysis_data`, `model_data` | `km_fit`, `bivariable_results`, `multivariable`, `hosmer_lemeshow_result` |
| `R/plot_style.R` | The maintainer's house style for figures, copied unchanged from the COHERO RCT analysis (commit `e8c4fa5`): `theme_publication()`, Okabe-Ito palettes, `save_figure()` in millimetres | ggplot2 ≥ 4.0, scales, svglite, ragg | functions, `publication_colors` |
| `R/tables.R` | Follow-up summary (deaths, censored, reverse Kaplan–Meier median); Tables 1 and 2 by 6-month vital status in the paper's row order (gtsummary; t, χ² or Fisher tests; missing counts; small cells hidden with `flag_small_cells()` and `suppress_table_body()`); Table 3, unadjusted and adjusted odds ratios with the joint Wald P values the selection used; disclosure checks | `analysis_data`, `model_data`, `km_fit`, `bivariable_results`, `multivariable`, `hosmer_lemeshow_result` | `report_labels`, `follow_up_summary`, `table_1`, `table_2`, `table_models`, `disclosure_checks`; `tables/*.html`, `*.docx` |
| `R/figures.R` | Figure 1 from `cohort_flowchart` (not exported if a box has 1–10 people); Figure 2, Kaplan–Meier with ggsurvfit's risk table at times passing `km_reportable_times()`; Figure 3, forest plot of adjusted odds ratios; captions and alt text from the fitted objects | `cohort_flowchart`, `km_fit`, `multivariable`, `report_labels` | `figure_2`, `figure_3`, `figure_text`; `figures/*` |
| `R/create_covariates.R` | Builds the covariates (plan §5): index-stay diagnoses, procedures and ICU; earlier transplant-complication hospitalizations; transplant history; demographics and region; UNOS registration and follow-up of the most recent transplant (rejection, serostatus, BMI, dialysis); immunosuppression at transplant and first follow-up | `cohort`, USRDS hospitalization, transplant, patients and UNOS files | `analysis_data` |

## Design choices in the code

- **Stays, not records.** All hospitalization records of a person with any cryptococcosis record are combined into stays (`collapse_stays()`) before anything else, so a code on one record of an overlapping stay counts for the whole stay.
- **Exclusions only in the flowchart.** `build_cohort_candidates()` computes flags but drops no one; every exclusion is an `fc_filter()` step, so Figure 1 reproduces the cohort exactly. Box labels are built from the constants in `setup.R`.
- **One person, one row** from the candidates step on. Joins declare their expected relationships, so an unexpected duplicate stops the run.
- **Release-dependent names in one place.** The UNOS key names differ between USRDS releases; the scripts take them from `unos_registration_id` and `unos_followup_id` in `setup.R`.
- **Missing is not "no".** Combining yes/no values uses `any_known()`, so a person with only unknown rejection codes is missing rather than "no", and a registration with no drug records is missing rather than "not on".
- **One row per person for survival.** All covariates are fixed and death is the only event, so `survfit()` takes one row per person; the usRds cohort functions, built for time-varying data, are not used.
- **Logic in tested functions, loading in scripts.** The scripts load data through usRds and call functions from `functions.R`; the functions are tested on synthetic data in `tests/test-functions.R`.

## Tests

`tests/test-functions.R` tests every helper on synthetic data with known answers, including boundary dates (window edges, a stay admitted on or spanning the transplant date, birthdays). Run with `testthat::test_file("tests/test-functions.R")` from the project root. The scripts themselves need usRds and the USRDS files and are not run by the unit tests.

`tests/run_synthetic.R` runs the whole of `R/main.R` end to end on an invented USRDS folder written by `tests/make_synthetic_usrds.R` (Parquet files in the layout usRds maps; every value made up, none derived from records). It points usRds at that folder for the session only and sets `death_data_end_date` for the synthetic run. Its tables and figures land in the gitignored `tables/` and `figures/` folders like real ones; they contain no restricted data but are not committed either.

## Website

One page per script in `quarto/`, importing labelled sections with `knitr::read_chunk()`; the site never runs analysis code. Published by `.github/workflows/publish.yml` to `gh-pages`.
