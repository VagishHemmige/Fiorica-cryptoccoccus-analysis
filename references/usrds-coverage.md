# usRds coverage of the Fiorica et al. 2025 analysis

This document maps each step of the published analysis [@fiorica2025], as the paper describes it, to the usRds functions that do it, or records that none does. It is the project's coverage assessment: replicating the paper's methods, how much of the work can usRds do?

- **Package version examined:** usRds 0.1.0, commit `3f63750` (default branch, 2026-11-09). Read from source; not run, because R is not installed in the environment where this was written. Re-check against the installed version before relying on any row.
- **Sources compared:** the paper's Methods and Supplementary Table 1, which are the specification (except that the code lists come from the reconstruction, by decision; plan §5); and the legacy Rmd dated 2025-03-25, the maintainer's best reconstruction of the original Stata analysis (secondary evidence only; not in this repository, see "Provenance" below). Where this document says "the legacy Rmd does X", it describes the reconstruction, not necessarily what the published analysis did.
- **Status key.** **Covered:** a usRds function does the step as the plan needs. **Partial:** a function exists but lacks something the step needs. **Gap:** no usRds function; currently done with hand-written code. **To verify:** behaviour that needs checking against the Researcher's Guide or by running the function on synthetic data.

The plan governs what each step must do. This document records only how the package meets it. Open choices are linked to their decision issues.

## Summary

| # | Step | usRds today | Status |
|---|---|---|---|
| 1 | Locate data files | `set_USRDS_wd()` (maps files on load) | Covered |
| 2 | Demographics and death date | `load_usrds_file("patients")`, `apply_usrds_factors()` | Covered |
| 3 | Transplant history (dates, failures, count before index) | `load_usrds_file("tx")` | Partial |
| 4 | Index cryptococcosis hospitalization (hospitalization files) | `load_usrds_file("hosp_*")` only | Gap ([#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1)) |
| 5 | Cryptococcal meningitis vs other, on the index stay | depends on step 4 | Gap |
| 6 | Comorbidities on the index stay (AKI, diabetes, cirrhosis) | depends on step 4; no prefix matching | Gap |
| 7 | ICU admission; combining overlapping claims into one stay | none | Gap |
| 8 | Discharge status | `apply_usrds_factors()` on the hospitalization file | To verify |
| 9 | Procedures on the index stay | none for ICD procedure codes | Gap ([#5](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/5)) |
| 10 | Exclude cryptococcosis before first transplant | `get_PS_ICD()`, `get_IN_ICD()` | Covered ([#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4)) |
| 11 | Prior hospitalization for kidney transplant complications | `get_IN_ICD()` could; the analysis uses the hospitalization files | Covered (dates only); project code used |
| 12 | Medicare as primary payer (variation only) | `verify_medicare_primary()` | Covered; not used in the main analysis ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)) |
| 13 | UNOS registration variables (BMI, pretransplant dialysis, HIV, CMV, rejection) | `load_usrds_file("txunos_trr_ki")`, `("txunos_trr_kp")` | Partial |
| 13a | Acute rejection: UNOS (used) and ICD claims (alternative) | UNOS: `load_usrds_file()`; claims: `get_IN_ICD()` or the hospitalization files | Partial / Partial |
| 14 | UNOS follow-up rejection | `load_usrds_file("txfuunos_ki")`, `("txfuunos_kp")` | Partial |
| 15 | Immunosuppression from UNOS records (at transplant and first follow-up) | `load_usrds_file("txirunos")`, `("txifunos")` | Partial ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)) |
| 16 | Immunosuppression from HCPCS claims (not used) | `get_PS_HCPCS()`, `get_IN_HCPCS()` | Covered; not used in the main analysis ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)) |
| 17 | Age, sex, race, ethnicity, region and division | `load_usrds_file()`; no recoding or state-to-region crosswalk | Gap (small) |
| — | Cohort selection: index event, exclusions, flowchart | none (`create_usrds_cohort()` needs the selected cohort as input) | Gap |
| 18 | 6-month mortality and Kaplan–Meier | `load_usrds_file("patients")` for death dates; cohort functions not needed | Covered; cohort functions not used, and defects found |
| 19 | Logistic regression, Table 1, figures | outside usRds's scope | Not applicable |
| — | Infectious diseases specialist claims (legacy Rmd only, not in the paper) | `get_PS_specialty()` | Covered, with defects |

## Step details

### 1. Locate data files

`set_USRDS_wd(path)` stores the path and maps the files; the map is rebuilt on package load when `USRDS_WD` is set. The legacy Rmd calls `map_USRDS_files()` directly, which is now internal (`.map_USRDS_files()`); scripts should call only `set_USRDS_wd()`, once, outside the repository (the path is machine-specific).

The mapper recognises six folder names: "ESRD Core", "ESRD transplant", "ESRD hospital", "ESRD PartD", "ESRD Institution" and "Physician supplier". The legacy Rmd's local folders are prefixed with a number ("1) ESRD core"); **to verify** that the case-sensitive `str_detect()` matches "ESRD core" (lower-case c) as well as "ESRD Core".

### 2. Demographics and death date

`load_usrds_file("patients", col_select = c(USRDS_ID, BORN, DIED, STATE, HISPANIC))`. `apply_usrds_factors()` labels coded variables from Appendix C, replacing the legacy Rmd's hand-written recodes for Hispanic ethnicity. Race and sex in the legacy Rmd come from the `tx` file (`RACE`, `RSEX`), not `patients`; the plan should name which file each comes from.

### 3. Transplant history

`load_usrds_file("tx", col_select = c(USRDS_ID, TDATE, FAILDATE, TOTTX))` loads one row per transplant. The paper needs, for each patient at the index date: first transplant date, number of transplants and graft failures before the index admission, and time since the most recent transplant. The legacy Rmd pivots to wide format (`TDATE_1`… `TDATE_5`) and loops over positions.

The `patients` file also has `TX1DATE` (date of first transplant; Appendix B 2024), which could replace the minimum of `TDATE`; the cohort script uses the `tx` file, which it needs for transplant history anyway. **Gap:** a long-format helper, for example `summarise_transplant_history(df, index_date)`, returning those quantities per patient. It is generally reusable: the missed-diagnosis project needs first transplant date too.

### 4. Index cryptococcosis hospitalization ([#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1))

Decided in [#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1): the hospitalization files (`hosp_to2009`, `hosp_2010on`), as the legacy Rmd uses. A stay is flagged if `PRIMDIAG` or any `HSDIAG` position (10 before 2010, 26 from 2010) is in the cryptococcosis list. The Researcher's Guide (2024, Appendix B) describes both files as "a subset of the data in the Institutional Claims file", inpatient stays only and without payment variables, so the institutional-claims route below is noted for completeness, not used.

- **`load_usrds_file("hosp_2010on")`** works, but reads the whole file before any filtering, and the diagnosis search across wide columns is hand-written.
- **`get_IN_ICD(icd_codes, years)`** reads the institutional diagnosis files (file roots `det<year><letter>` in the internal `IN_ICD` table) with filtering pushed down for Parquet. It returns only `USRDS_ID`, `CODE`, `CLM_FROM` and `HCFASAF`: no `CLM_THRU`, no claim key (`SEQ_KEYC`) and no diagnosis position. So a stay found this way cannot be linked to its discharge status, ICU days or procedures, and principal and secondary diagnoses cannot be told apart.
- **`establish_dx_date()`** applies a "first inpatient or second outpatient claim" rule, not the paper's "first hospitalization" rule.

**Gaps:**

- (a) `get_HOSP_ICD(icd_codes, years, positions = "any")`: searches `PRIMDIAG`/`HSDIAG*` with pushdown, and returns one row per stay with its key, dates, `DISCSTAT`, `ICU_DAYS` and `CCU_DAYS`.
- (b) Alternatively, an option on `get_IN_ICD()` to return `CLM_THRU`, `SEQ_KEYC` and the diagnosis position, plus a companion that loads the claim header for a set of keys.

**Found while writing the cohort script:** the two hospitalization files use `PRIMDIAG` differently (Appendix B 2024). In `hosp_to2009` it is a Y/N flag ("first diagnosis is primary") and the codes are in `HSDIAG1`–`HSDIAG10`. In `hosp_2010on` it is the principal diagnosis code. Searching `PRIMDIAG` in both, as the legacy Rmd does, is harmless but wrong in meaning. An extractor for these files (gap (a)) should hide that difference; this project handles it with per-file column lists in `R/setup.R`. Loading with default `factor_labels = TRUE` would also turn the pre-2010 flag into a factor, so the cohort script loads with `factor_labels = FALSE`.

**To verify:**

- whether the `det` files contain procedure codes as well as diagnosis codes in `CODE`, and if so how they are distinguished;
- the SAS branch of `.load_individual_file_IN_ICD()` omits `HCFASAF`, so `establish_dx_date()` would misclassify SAS-sourced claims;
- hospitalization file names differ by release; Appendix B for the release in use governs;
- which files hold institutional diagnosis codes: in the 2024 layout (Appendix B), inpatient diagnosis and procedure codes are in `ip_dxp_<year>` ("Diagnosis and Procedure Details"), while `get_IN_ICD()` reads files with roots `det<year><letter>`, the name the 2024 layout uses for revenue-line details. Older releases may name files differently.

### 5. Cryptococcal meningitis on the index stay

B45.1 or 321.0 in any diagnosis position of the index stay, including stays merged with it (step 7). This depends on the stay-level output of step 4. No separate gap.

### 6. Comorbidities on the index stay

AKI and cirrhosis use exact code lists. Diabetes uses open prefixes (`250*`, `E08*`–`E13*`; plan §5). The reconstruction enumerated stems plus at most two digits instead, which misses most ICD-10-CM diabetes codes; an exact-only matcher pushes code toward that kind of enumeration error. The project matches prefixes with `code_matches()` in `R/functions.R`.

**Gap:** the `get_*_ICD()` functions match exactly (`CODE %in% icd_codes`). The package builds an `icd_reference` table "so that the get_*_ICD functions can use wildcards" (`data-raw/DATASET.R`), but no exported function uses it yet. A `prefix = TRUE` option, or an `expand_icd_codes("E11", type = "dx")` helper backed by `icd_reference`, would close this.

### 7. ICU admission and overlapping claims

The legacy Rmd treats hospitalization records whose `CLM_FROM` falls on or before the previous record's `CLM_THRU` as one continuing stay. It sums `ICU_DAYS`, `CCU_DAYS` and the procedure and diagnosis flags across up to seven records, and defines ICU admission as any ICU or CCU days.

**Gap:** `collapse_stays(df, gap_days = 0)`: groups contiguous or overlapping institutional records into episodes, with an episode ID, start and end. It is reusable for readmission and length-of-stay work.

### 8. Discharge status

The legacy Rmd recodes `DISCSTAT` by hand into home, other facility, death and still inpatient. **To verify:** whether Appendix B gives `DISCSTAT` a format in the hospitalization file, so that `apply_usrds_factors()` labels it. The grouping into four categories is a study choice, and stays in this project.

### 9. Procedures on the index stay ([#5](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/5))

The legacy Rmd counts `HSSURG1`–`HSSURG25` matches against the supplement's lists. usRds has HCPCS extractors (`get_IN_HCPCS()`, `get_PS_HCPCS()`), which cover CPT codes if [#5](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/5) chooses them. It has no ICD procedure-code extractor. **Gap:** `get_HOSP_procedure()`, or a `code_type = "procedure"` route in step 4(a).

### 10. Exclude cryptococcosis before first transplant ([#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4))

`get_PS_ICD(cryptococcus_codes, years)` and `get_IN_ICD(...)` give every claim date, to compare with the first transplant date from step 3. Covered.

The legacy Rmd's filter appears to keep the opposite group from the one the paper describes; the paper's rule governs ([#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4)). **Limit:** claims are searched only for the years mapped; pre-2006 claims are not in the paper's window.

### 11. Prior hospitalization for transplant complications

T86.10–T86.12 or 996.81 on a hospitalization before the index admission. Only a date is needed, so `get_IN_ICD()` filtered to inpatient claims would cover it. Following [#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1), the analysis uses the hospitalization files, which it already loads for the index stay (`R/create_covariates.R`), so this route is project code.

### 12. Medicare as primary payer ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3))

The main analysis applies no Medicare-primary restriction: the paper gives no window or method, the legacy Rmd applies none, and the index stay is itself a Medicare-paid record ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)). The explicit restriction is a variation (plan §9): `verify_medicare_primary(df, index_date = "index_admit_date", lookback_days = ...)` adds `medicare_primary_TF`. Covered, so the function is exercised only if the variation is run.

### 13–14. UNOS registration and follow-up

These load with `load_usrds_file()`. Kidney-alone and kidney–pancreas recipients are in separate files with different variable names (`ACUTE_REJ_EPI` vs `ACUTE_REJ_EPI_KI`), stacked and renamed in project code, as in the legacy Rmd. The follow-up date falls back to `FUKIFAIL` when `FUDATE` is missing.

Appendix C (2024, format `ACREJEPI`): 1 = yes, at least one episode treated; 2 = yes, none treated with an additional agent; 3 = no; 990 and 998 = episodes unknown (carried over from before 2005). The analysis counts 1 or 2 as an episode and 990/998 as missing; the legacy Rmd dropped only 998.

The analysis takes the registration of the most recent transplant on or before the index admission, and that registration's follow-up reports, linked by the registration key (`TRR_ID` in the maintainer's release, from the legacy Rmd; `TRR_ID_CODE` in 2024).

**Gap (small):** `load_usrds_unos(c("trr", "fu"), organs = c("ki", "kp"))`, returning stacked, harmonised kidney variables with an organ indicator. **To verify:** whether `apply_usrds_factors()` labels `ACUTE_REJ_EPI`; the scripts load with `factor_labels = FALSE` and recode from the raw codes.

### 13a. Acute rejection from UNOS and from claims

The package should support both routes, and this replication assesses both. **UNOS (used):** loading is covered by `load_usrds_file()`; choosing the transplant's registration and follow-up reports relative to an index date, and recoding `ACREJEPI`, are project code (gap, as step 13). **ICD claims (alternative, plan §9; not built):** a hospitalization with ICD-10-CM T86.11 could be found with `get_IN_ICD()` (dates only, inpatient claims; covered) or from the hospitalization files (gap, step 4). ICD-9-CM has no rejection-specific kidney code, so a claims definition works only from October 2015.

### 15. Immunosuppression from UNOS records ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2))

Decided in [#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2): immunosuppression at transplant from `TXIRUNOS` and at the first follow-up from `TXIFUNOS` ("Immunosuppression at Follow-up – UNOS", Appendix B 2024), which the legacy Rmd never loads. Both should load with `load_usrds_file()`. **To verify:**

- that the file mapper finds `txifunos`;
- the join keys: the legacy Rmd joins `TXIRUNOS` to the registration on `TRR_ID`, but the 2024 layout has encrypted keys (`TRR_ID_CODE`; `TRRFU_ID_CODE` linking `TXIFUNOS` to the follow-up reports), so key names depend on the release. The scripts take both names from constants in `R/setup.R`; the follow-up key `TRRFU_ID` is a guess for the maintainer's release and must be checked before running.

The legacy Rmd maps `RX_CD` codes and misspelled free text (`DRUG_CD_OSTXT`) to drug classes. Checked against Appendix C (format `DRUG`), every code it maps is labelled correctly, but it misses 57 (generic Myfortic), 58 (generic sirolimus) and 59 (Envarsus XR), which are added (`R/code_lists.R`). **Gap:** a verified `RX_CD`-to-class crosswalk shipped as package data, from Appendix C, so projects don't re-derive it. The free-text clean-up is study-specific and stays here.

### 16. Immunosuppression from HCPCS claims ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2))

Not used in the main analysis ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)), but kept in the assessment because the maintainer may revisit it (billing data may be the gold standard). `get_PS_HCPCS(c("J7502", "J7515", "J7516", "J7503", "J7507", "J7508", "J7525"), years)`, plus `get_IN_HCPCS()` for institutional lines. Covered. The package maps Part D files (a `PDE` file list exists internally) but has no Part D extractor. Part D is out of scope ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)); if oral tacrolimus from Part D is ever brought in, that is a gap.

### 17. Age, region and division

Age comes from `BORN`. `STATE` uses FIPS codes (Appendix C format `STATFIP`, which also lists 03 American Samoa and 43 Puerto Rico, older codes). The legacy Rmd maps them to Census regions by hand; territory codes it does not list (for example 66 Guam, 78 Virgin Islands) fall through to missing, which `R/code_lists.R` corrects by mapping every valid non-state code to "Outside". It also groups Alaska and Hawaii with the territories, unlike the Census Bureau; the analysis keeps that grouping ([#12](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/12)).

Hispanic ethnicity (format `$YNUFMT`) codes "no" as 2 or N. The legacy Rmd recoded 0 or N as non-Hispanic, so code 2 would have become missing; the analysis follows the format. Sex and race (`$SEXFMT`, `$RACEFMT`) are recoded as in the legacy Rmd.

**Gap (small):** a state-code crosswalk as package data; and recoding is project code because the scripts load with `factor_labels = FALSE`. Whether `apply_usrds_factors()` would label these correctly is **to verify**.

### 18. Mortality and survival

Death dates load with `load_usrds_file("patients")`. Every covariate is fixed and death is the only event, so the survival data needs one row per person (time to death or end of death data, and whether death occurred), which `survival::survfit()` takes directly. The usRds cohort functions (`create_usrds_cohort()`, `add_cohort_event()`, `finalize_usrds_cohort()`, `add_cohort_covariate()`) are built for follow-up split by time-varying covariates or repeated events, and the analysis does not use them.

They were probed on synthetic data (sourced from the usRds clone at `3f63750`, four people followed 180 days), because a survival analysis with time-varying covariates would rely on them:

| Behaviour | Result |
|---|---|
| Dates passed as a column-name string | Works. A bare column name fails, although the internal helper's comment says either works. |
| Death on the start date | **Not counted:** `tmerge` events fall in (tstart, tstop], so an event at time 0 is dropped. |
| Death during follow-up | **Follow-up continues after death:** `add_cohort_event()` uses `cumevent()`, so a second interval from the death to the end keeps the person at risk. A Kaplan–Meier estimate from this overstates survival. |
| Death on the end date | Counted. |
| Ending follow-up at death (`end_date` = earlier of death and end) | Fixes continued follow-up, but stops with "tstart must be < tstop" for a death on the start date. |

For death as an outcome, `add_cohort_event()` therefore needs a terminal-event option (stop follow-up at the event, using `event()` rather than `cumevent()`), and same-day events need a convention (for example, half a day). These are listed as follow-ups below.

### Cohort selection

The usRds cohort functions handle follow-up time, not entry: `create_usrds_cohort()` requires a data frame that already has one row per person (it stops on a repeated `USRDS_ID`), with start and end dates. Finding each person's index event and applying the exclusions is done in project code: `R/create_cohort.R`, with helpers in `R/functions.R` and every exclusion through `flowchart`. That part is a **gap**, but a mostly study-specific one. The reusable pieces (searching the hospitalization files, combining records into stays, first transplant date) are already listed as gaps at steps 3, 4 and 7, so no separate usRds follow-up is proposed.

### Infectious diseases specialist claims (legacy Rmd only)

`get_PS_specialty("44", 2006:2016, DIAG = TRUE, HCPCS = TRUE)` works, but has these defects:

- leftover `print()` debugging calls;
- the SAS branch pipes into `return(temp)` before `temp` exists;
- the SAS branch reads by `col_select` but never converts dates;
- the Parquet branch reads the whole file before filtering.

The paper does not use these claims, so they are out of scope for the plan unless a decider adds them.

## Package-wide observations

These are not tied to one step, but affect several.

- **Which copy `load_usrds_file()` reads.** It takes the first registry match (`slice(1)`). The registry is built CSV first, then SAS, then Parquet. So when a file exists in more than one format, it appears to read the CSV, contradicting the vignette's statement that Parquet is preferred. **To verify** on synthetic files.
- **`apply_usrds_varlabels()`** stops unless `metadata_b` exists in the global environment. The data are internal to the package, so with `var_labels = TRUE` it may always fail. `apply_usrds_factors()` has the same check commented out. **To verify.**
- **`load_usrds_file()` with `col_select` on Parquet always fails.** It reads the column names with `arrow::open_dataset(full_path)$head(1)`. A Dataset is an R6 object, and `$head` looks for a method of that name on it; there is none, so `$head` returns `NULL` and calling it gives "attempt to apply non-function". `head()` for a Dataset exists only as an S3 method (`head(dataset, 1)`). No arrow release has had a `$head()` method on Dataset (checked all 63 CRAN releases in the cran/arrow mirror, 0.14.1 to 26.0.1), so this branch has never run; it is not a change in arrow. `head(arrow::open_dataset(full_path), 1)` works, and `names(arrow::open_dataset(full_path)$schema)` gets the names without reading rows. Found in the synthetic end-to-end run (2026-11-10) and reported as [usRds#22](https://github.com/VagishHemmige/usRds/issues/22). **Temporary workaround here:** until it is fixed, the scripts load through `load_usrds_columns()` in `R/functions.R`. For a Parquet file it reads the columns with arrow from the path usRds registered (read from the package's internal registry), then repeats the package's steps (upper-case names, `usrds_ids` filter, `apply_usrds_factors()`); other formats go straight to `load_usrds_file()`. When the fix lands, each call goes back to `load_usrds_file(col_select = all_of(...))` and the wrapper is deleted. The package itself was not modified.
- **`load_usrds_file()` forces `col_select` early.** `is.null(col_select)` evaluates the argument outside a selecting function, so `col_select = all_of(x)` gives tidyselect's deprecation warning. Capturing it with `rlang::enquo()` and testing `rlang::quo_is_null()` would avoid that.
- **Documentation.** Facts this project relies on are not yet in the package documentation: claim-year assignment, ICD transition handling, and hospitalization file structure by release. Where these shape this analysis they are noted in `AGENTS.md` ("USRDS data facts"); they belong in usRds.

## Proposed usRds issues

Possible follow-ups for usRds, listed so the assessment is actionable. Acting on them is outside this project's scope, and none is opened without the usRds maintainer's approval.

1. Hospitalization-file diagnosis extractor with stay-level fields (step 4a).
2. Claim key, end date and diagnosis position from `get_IN_ICD()` (step 4b).
3. Prefix or wildcard matching for ICD codes using `icd_reference` (step 6).
4. Combine overlapping or contiguous stays into episodes (step 7).
5. ICD procedure-code extractor (step 9).
6. Transplant history relative to an index date (step 3).
7. Stacked, harmonised UNOS kidney and kidney–pancreas loaders (steps 13–14).
8. `RX_CD` immunosuppression crosswalk as package data (step 15).
9. State code to Census region and division crosswalk (step 17).
10. Cohort functions for a terminal event (step 18): `add_cohort_event()` keeps follow-up after death (`cumevent()`), drops events on the start date, and fails when follow-up ends at a same-day death; the date helper's comment says bare column names work, but they fail.
11. Defects: `get_PS_specialty()` (debug prints, SAS branch); SAS branch of `get_IN_ICD()` dropping `HCFASAF`; `load_usrds_file()` format priority; `apply_usrds_varlabels()` global-environment check; `load_usrds_file()` column lookup on Parquet (`$head(1)`, never valid) and early evaluation of `col_select` ([usRds#22](https://github.com/VagishHemmige/usRds/issues/22)).

## Provenance

- Fiorica et al. 2025 [@fiorica2025], Methods, Tables 1–2, Figures 1–3, and Supplementary Table 1 (open access, PMC12089938).
- Legacy analysis Rmd, "Cryptococcus 2025-2-25", file dated 2025-03-25, supplied by Vagish Hemmige on 2026-11-09. It is his best reconstruction in R of the original analysis, which was run in Stata; the Stata code is no longer available. By the maintainer's decision it is not kept in this repository, because of its provenance; this document describes it only where it bears on a step.
- usRds source at commit `3f63750`.
