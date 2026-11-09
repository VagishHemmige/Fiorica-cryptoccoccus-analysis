# usRds coverage of the Fiorica et al. 2025 analysis

This document maps each step of the published analysis [@fiorica2025], as the paper describes it, to the usRds functions that do it, or records that none does. It is the project's coverage assessment: replicating the paper's methods, how much of the work can usRds do?

- **Package version examined:** usRds 0.1.0, commit `3f63750` (default branch, 2026-11-09). Read from source; not run, because R is not installed in the environment where this was written. Re-check against the installed version before relying on any row.
- **Sources compared:** the paper's Methods and Supplementary Table 1 (code lists), which are the specification; and the legacy Rmd dated 2025-03-25, the maintainer's best reconstruction of the original Stata analysis (secondary evidence only; not in this repository, see "Provenance" below). Where this document says "the legacy Rmd does X", it describes the reconstruction, not necessarily what the published analysis did.
- **Status key.** **Covered:** a usRds function does the step as the plan needs. **Partial:** a function exists but lacks something the step needs. **Gap:** no usRds function; currently done with hand-written code. **To verify:** behaviour that needs checking against the Researcher's Guide or by running the function on synthetic data.

The plan governs what each step must do. This document records only how the package meets it. Open choices are linked to their decision issues.

## Summary

| # | Step | usRds today | Status |
|---|---|---|---|
| 1 | Locate data files | `set_USRDS_wd()` (maps files on load) | Covered |
| 2 | Demographics and death date | `load_usrds_file("patients")`, `apply_usrds_factors()` | Covered |
| 3 | Transplant history (dates, failures, count before index) | `load_usrds_file("tx")` | Partial |
| 4 | Index cryptococcosis hospitalization | `load_usrds_file("hosp_*")`, or `get_IN_ICD()` | Gap / Partial ([#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1)) |
| 5 | Cryptococcal meningitis vs other, on the index stay | depends on step 4 | Gap |
| 6 | Comorbidities on the index stay (AKI, diabetes, cirrhosis) | depends on step 4; no prefix matching | Gap |
| 7 | ICU admission; combining overlapping claims into one stay | none | Gap |
| 8 | Discharge status | `apply_usrds_factors()` on the hospitalization file | To verify |
| 9 | Procedures on the index stay | none for ICD procedure codes | Gap ([#5](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/5)) |
| 10 | Exclude cryptococcosis before first transplant | `get_PS_ICD()`, `get_IN_ICD()` | Covered ([#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4)) |
| 11 | Prior hospitalization for kidney transplant complications | `get_IN_ICD()` | Covered (dates only) |
| 12 | Medicare as primary payer (variation only) | `verify_medicare_primary()` | Covered; not used in the main analysis ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)) |
| 13 | UNOS registration variables (BMI, pretransplant dialysis, HIV, CMV, rejection) | `load_usrds_file("txunos_trr_ki")`, `("txunos_trr_kp")` | Partial |
| 14 | UNOS follow-up rejection | `load_usrds_file("txfuunos_ki")`, `("txfuunos_kp")` | Partial |
| 15 | Immunosuppression from UNOS records | `load_usrds_file("txirunos")` | Partial ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)) |
| 16 | Immunosuppression from HCPCS claims | `get_PS_HCPCS()`, `get_IN_HCPCS()` | Covered ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)) |
| 17 | Age, region and division | none for state to Census region | Gap (small) |
| 18 | 6-month mortality and Kaplan–Meier | `create_usrds_cohort()`, `add_cohort_event()`, `finalize_usrds_cohort()` | Covered |
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

**Gap:** a long-format helper, for example `summarise_transplant_history(df, index_date)`, returning those quantities per patient. It is generally reusable: the missed-diagnosis project needs first transplant date too.

### 4. Index cryptococcosis hospitalization ([#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1))

The legacy Rmd reads the USRDS hospitalization files (`hosp_to2009`, `hosp_2010on`) and flags a stay if `PRIMDIAG` or any `HSDIAG1`–`HSDIAG26` is in the cryptococcosis list.

- **`load_usrds_file("hosp_2010on")`** works, but reads the whole file before any filtering, and the diagnosis search across wide columns is hand-written.
- **`get_IN_ICD(icd_codes, years)`** reads the institutional diagnosis files (file roots `det<year><letter>` in the internal `IN_ICD` table) with filtering pushed down for Parquet. It returns only `USRDS_ID`, `CODE`, `CLM_FROM` and `HCFASAF`: no `CLM_THRU`, no claim key (`SEQ_KEYC`) and no diagnosis position. So a stay found this way cannot be linked to its discharge status, ICU days or procedures, and principal and secondary diagnoses cannot be told apart.
- **`establish_dx_date()`** applies a "first inpatient or second outpatient claim" rule, not the paper's "first hospitalization" rule.

**Gaps:**

- (a) `get_HOSP_ICD(icd_codes, years, positions = "any")`: searches `PRIMDIAG`/`HSDIAG*` with pushdown, and returns one row per stay with its key, dates, `DISCSTAT`, `ICU_DAYS` and `CCU_DAYS`.
- (b) Alternatively, an option on `get_IN_ICD()` to return `CLM_THRU`, `SEQ_KEYC` and the diagnosis position, plus a companion that loads the claim header for a set of keys.

**To verify:**

- whether the `det` files contain procedure codes as well as diagnosis codes in `CODE`, and if so how they are distinguished;
- the SAS branch of `.load_individual_file_IN_ICD()` omits `HCFASAF`, so `establish_dx_date()` would misclassify SAS-sourced claims;
- hospitalization file names differ by release; Appendix B for the release in use governs.

### 5. Cryptococcal meningitis on the index stay

B45.1 or 321.0 in any diagnosis position of the index stay, including stays merged with it (step 7). This depends on the stay-level output of step 4. No separate gap.

### 6. Comorbidities on the index stay

AKI and cirrhosis use exact code lists. Diabetes uses prefixes (`250*`, `E08*`–`E13*`); the legacy Rmd enumerates them by loop.

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

T86.10–T86.12 or 996.81 on a hospitalization before the index admission. Only a date is needed, so `get_IN_ICD()` filtered to inpatient claims covers it. The legacy Rmd used the hospitalization file. The two sources may differ, and the choice follows [#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1).

### 12. Medicare as primary payer ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3))

The main analysis applies no Medicare-primary restriction: the paper gives no window or method, the legacy Rmd applies none, and the index stay is itself a Medicare-paid record ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)). The explicit restriction is a variation (plan §9): `verify_medicare_primary(df, index_date = "index_admit_date", lookback_days = ...)` adds `medicare_primary_TF`. Covered, so the function is exercised only if the variation is run.

### 13–14. UNOS registration and follow-up

These load with `load_usrds_file()`. Kidney-alone and kidney–pancreas recipients are in separate files with different variable names (`ACUTE_REJ_EPI` vs `ACUTE_REJ_EPI_KI`), and the legacy Rmd stacks and renames them by hand. The follow-up date falls back to `FUKIFAIL` when `FUDATE` is missing, and code 998 is dropped.

**Gap (small):** `load_usrds_unos(c("trr", "fu"), organs = c("ki", "kp"))`, returning stacked, harmonised kidney variables with an organ indicator. **To verify:** the meaning of 998 and of the `ACUTE_REJ_EPI` codes in Appendix C, and whether `apply_usrds_factors()` labels them.

### 15. Immunosuppression from UNOS records ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2))

`txirunos` loads with `load_usrds_file()`. The legacy Rmd maps `RX_CD` codes and misspelled free text (`DRUG_CD_OSTXT`) to drug classes. **Gap:** a verified `RX_CD`-to-class crosswalk shipped as package data, from Appendix C, so projects don't re-derive it. The free-text clean-up is study-specific and stays here.

### 16. Immunosuppression from HCPCS claims ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2))

`get_PS_HCPCS(c("J7502", "J7515", "J7516", "J7503", "J7507", "J7508", "J7525"), years)`, plus `get_IN_HCPCS()` for institutional lines. Covered. The package maps Part D files (a `PDE` file list exists internally) but has no Part D extractor. If [#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2) brings oral tacrolimus from Part D into scope, that is a gap.

### 17. Age, region and division

Age comes from `BORN`. The legacy Rmd maps USRDS `STATE` codes to Census regions and divisions by hand. **To verify:** whether USRDS `STATE` codes are FIPS codes (the legacy map treats "72" as outside, consistent with FIPS Puerto Rico, but also uses "03" and "43", which are not FIPS). **Gap (small):** a state-code crosswalk as package data.

### 18. Mortality and survival

`create_usrds_cohort(df, start_date = index_admit_date, end_date = censor_date)`, then `add_cohort_event(cohort, deaths, "DIED", "death")` and `finalize_usrds_cohort(cohort)` give a counting-process data set for `survival::survfit()`. Covered. This analysis exercises these functions on a simple one-row-per-person cohort. **To verify:** that a death on the cohort stop date is counted (`tmerge` event at `tstop`).

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
10. Defects: `get_PS_specialty()` (debug prints, SAS branch); SAS branch of `get_IN_ICD()` dropping `HCFASAF`; `load_usrds_file()` format priority; `apply_usrds_varlabels()` global-environment check.

## Provenance

- Fiorica et al. 2025 [@fiorica2025], Methods, Tables 1–2, Figures 1–3, and Supplementary Table 1 (open access, PMC12089938).
- Legacy analysis Rmd, "Cryptococcus 2025-2-25", file dated 2025-03-25, supplied by Vagish Hemmige on 2026-11-09. It is his best reconstruction in R of the original analysis, which was run in Stata; the Stata code is no longer available. By the maintainer's decision it is not kept in this repository, because of its provenance; this document describes it only where it bears on a step.
- usRds source at commit `3f63750`.
