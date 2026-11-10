# Analysis plan: Cryptococcosis in kidney transplant recipients, rebuilt with usRds

Status: draft. Not locked.

## Scope and reporting framework

This document is the authoritative specification of the study's scientific objectives, population, definitions, estimands and statistical methods. `ARCHITECTURE.md` documents the implementation, `AGENTS.md` the working conventions, and GitHub Issues the open decisions and implementation status. Neither file supersedes this plan.

The analysis replicates a published study [@fiorica2025] as the paper describes it, using the usRds package wherever it can do a step, to assess the package's coverage. **The paper and its Supplementary Table 1 are the specification.** The original analysis was run in Stata, and that code is no longer available; a later R Markdown reconstruction (2025-03-25) is used only as secondary evidence of how a step may have been done. Where the paper is silent, the plan records an open decision rather than adopting the reconstruction's choice unexamined. The published estimates are a reference point, not a target. How each step maps to usRds is in `references/usrds-coverage.md`.

Reporting will follow STROBE [@vonelm2007strobe] and RECORD [@benchimol2015record]. The reporting map in §12 links each checklist item to a section of this plan.

## 1. Objective

- **Primary:** estimate all-cause mortality within 6 months of the index cryptococcosis hospitalization among adult kidney transplant recipients hospitalized under Medicare, 2006–2016.
- **Secondary:**
  - describe time from kidney transplant to the index hospitalization;
  - estimate the association of clinical, transplant and immunosuppression characteristics with 6-month mortality.
- **Methodological (this project):** assess, step by step, whether usRds does what the paper's methods require (covered, partial or gap).

All analyses are exploratory, as in the paper. No hypotheses are tested confirmatorily.

## 2. Design

Retrospective cohort of kidney transplant recipients, entering at their first post-transplant cryptococcosis hospitalization (the index hospitalization). The question is predictive and descriptive (which factors are associated with death), not causal. Target-trial emulation is not used.

## 3. Data source

- **Database:** United States Renal Data System standard analysis files, with linked Medicare claims and UNOS transplant records. The release is recorded with each result. The paper used a release covering 2006–2016 claims.
- **Files:**
  - core: `patients`, `tx`, payer history;
  - hospitalization: `hosp_to2009`, `hosp_2010on`;
  - institutional and physician/supplier claims;
  - UNOS: `txunos_trr_ki`, `txunos_trr_kp`, `txfuunos_ki`, `txfuunos_kp`, `txirunos`.
- **Observation window:** index hospitalizations admitted 2006-01-01 to 2016-12-31. Deaths are ascertained through the release's death-date currency.
- **Linkage:** by `USRDS_ID`, as provided by USRDS. Transplant status comes from USRDS core and UNOS files, not diagnosis codes.
- **Secondary-data declaration:** the investigators have analysed these data before (the published study). Results from this reconstruction will be compared with the paper only to check package behaviour.

The index hospitalization and its stay-level variables (diagnoses, procedures, ICU and CCU days, discharge status) come from the USRDS hospitalization files, `hosp_to2009` and `hosp_2010on` (decided in [#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1)). These files are a subset of the institutional claims, restricted to inpatient stays without payment variables (Researcher's Guide 2024, Appendix B), so institutional claims are not used as a second source for the index stay.

## 4. Study population

Source population: recipients of a kidney or kidney–pancreas transplant in the USRDS `tx` file. Exclusions are applied in this order, and each becomes one flowchart step (Figure 1):

1. Hospitalizations with a cryptococcosis diagnosis code (§5) in any diagnosis position, admitted 2006-01-01 to 2016-12-31.
2. Restrict to people in the transplant file.
3. Exclude hospitalizations admitted before the patient's first kidney transplant. A hospitalization admitted before the transplant is a cryptococcosis hospitalization claim preceding it, which the paper excludes; this includes stays that begin before the transplant and end after it (decided under [#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4); the reconstruction kept such stays with time since transplant set to 0).
4. Exclude people with any cryptococcosis claim before their first kidney transplant or before 2006-01-01. **Open:** which claim sources count and how many claims are required ([#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4)).
5. Keep each person's first remaining cryptococcosis hospitalization (the index hospitalization).
6. Restrict to age 18–90 years on the index admission date.

No separate Medicare-primary restriction is applied. The paper describes the cohort as recipients "with Medicare as their primary insurance coverage" but gives no window or method, and the index hospitalization is itself a Medicare-paid record. The plan therefore treats Medicare-primary status as a consequence of the data source rather than an applied exclusion (decided in [#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)). An explicit restriction is described as a variation in §9.

The paper does not state the order of step 6 relative to the others. The order above puts claim-based exclusions first, so each later step's denominator is a set of people with an index hospitalization.

## 5. Exposure, index event and covariates

**Index event and time zero:** admission date (`CLM_FROM`) of the index hospitalization. Overlapping or contiguous hospitalization records are one stay; the stay ends at the last record's `CLM_THRU`.

**Code lists:** from the 2025-03-25 reconstruction of the original analysis, by the maintainer's decision (2026-11-09, [#8](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/8)), rather than from Supplementary Table 1 [@fiorica2025]. The two are identical except for diabetes and the cyclosporine and tacrolimus HCPCS codes, which only the supplement lists and which are not used, because immunosuppression comes from the UNOS records ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)). After checking every code against the official code sets, three corrections were made (maintainer's decision, 2026-11-09): diabetes stems match as open prefixes, as in the supplement, because the reconstruction's enumeration (stem plus at most two digits) misses most ICD-10-CM diabetes codes; ICD-9-CM 456.20 is added to cirrhosis, missing from both sources; and a ventriculoperitoneal shunt list is rebuilt (below). Codes are written without decimals and match exactly, except the diabetes prefixes. ICD-9-CM applies to inpatient stays discharged before 2015-10-01 and ICD-10-CM/PCS to those discharged on or after it, following CMS's discharge-date rule; for the hospitalization files the discharge date is `CLM_THRU`. Lists are kept in code with their provenance (`references/usrds-coverage.md`).

| Concept | Codes |
|---|---|
| Cryptococcosis | 117.5, 321.0, B45, B45.0–B45.3, B45.7–B45.9 |
| Cryptococcal meningitis (CM) | 321.0, B45.1 |
| Transplant complication | 996.81, T86.10–T86.12 |
| Acute kidney injury | 584.5–584.9, N17.0–N17.2, N17.8, N17.9 |
| Diabetes (prefix) | 250\*, E08\*, E09\*, E10\*, E11\*, E13\*; 357.2, 362.0, 362.02, 366.41 |
| Cirrhosis | the 31 codes in the reconstruction and Supplementary Table 1 (identical), plus 456.20 |

**Covariates measured on the index stay:**

- CM vs non-CM;
- AKI, diabetes and cirrhosis, from any diagnosis on the stay;
- ICU admission (any ICU or CCU days);
- procedures: lumbar puncture, other spinal, neurosurgical and lung procedures, and ventriculoperitoneal shunt. The shunt list is missing from both the supplement and the reconstruction (a copy/paste loss, in the maintainer's judgment), so it is rebuilt from the official code sets: ICD-9-CM 02.34 and the nine ICD-10-PCS codes for bypass of a cerebral ventricle to the peritoneal cavity. **Open:** whether CPT codes, which the paper's text names, are used as well as ICD procedure codes ([#5](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/5)).

**Covariates measured at or before time zero:**

- age, sex, race, Hispanic ethnicity, region;
- BMI, pretransplant dialysis, HIV and CMV serostatus (UNOS registration);
- number of transplants and graft failures before the index stay;
- time since last transplant (also dichotomised at 2 years, as in the paper's model);
- acute rejection (UNOS registration or follow-up);
- any prior hospitalization with a transplant-complication code.

**Immunosuppression:**

- antithymocyte globulin, alemtuzumab, anti-IL-2 receptor antibody, tacrolimus, cyclosporine, mycophenolate, mTOR inhibitors, azathioprine, steroids;
- measured from the UNOS records in the USRDS transplant files, not Medicare drug claims (decided in [#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)):
  - **at transplant:** `TXIRUNOS`, linked to the recipient registration (`TXUNOS_TRR_KI`/`_KP`);
  - **at first follow-up:** `TXIFUNOS`, from the earliest follow-up report (`TXFUUNOS_KI`/`_KP`, earliest `FUDATE`), whether or not it precedes the index admission, as the paper's Methods describe ("the first post-transplant visit"). Under OPTN rules this is normally the 6-month report. A drug counts at follow-up if it is current maintenance at that visit (`RXMNTCUR`);
- drug classes come from `RX_CD` and `DRUG_CD_OSTXT`, using the reconstruction's mapping.

The paper's Discussion refers to a "1-year follow-up", and its Methods and Limitations say the drugs came from "billing codes"; the plan follows the Methods' time point and the UNOS records. The maintainer notes that billing data may be the gold standard, so this choice may be revisited ([#2](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/2)).

## 6. Comparator or matching

Not applicable. Comparisons are between people who died within 6 months and those who survived.

## 7. Outcomes

- **Primary:** death from any cause within 180 days of the index admission date (`DIED` from the `patients` file). A death on day 180 counts.
- **Secondary:**
  - time from index admission to death, censored at the release's death-date currency;
  - time from most recent kidney transplant to index admission.

## 8. Statistical analysis

- **Descriptive:**
  - Table 1: characteristics by 6-month vital status;
  - Table 2: immunosuppression by 6-month vital status;
  - continuous variables as mean (SD), and median (IQR) for time since transplant;
  - categorical variables as n (%), with small cells suppressed (§10);
  - missingness reported per variable.
- **Tests:** Student t test for continuous variables; χ² test, or Fisher exact test for sparse tables. Two-sided α = 0.05, with no adjustment for multiple comparisons [@fiorica2025].
- **Survival:** Kaplan–Meier curve of time to death from the index admission, with a 6-month reference line (Figure 2).
- **Model:** logistic regression for 6-month mortality.
  - Variables are first tested in bivariable models, then entered into a multivariable model with backward elimination (retain P < .05).
  - Fit is assessed by the Hosmer–Lemeshow test.
  - Adjusted odds ratios with 95% CIs are shown as a forest plot (Figure 3).
  - Backward elimination is kept to mirror the paper. Its limitations are noted in §11.
- **Missing data:** complete-case, as in the paper. The number excluded from the model is reported.
- **Software:** R, with usRds (version and commit recorded with each result), survival, and flowchart for Figure 1.

## 9. Sensitivity analyses

**Variation: explicit Medicare-primary restriction.** One way the study could have been done differently is to require Medicare as primary payer from the payer history file (for example on the index admission date, for 365 days before it, or from first transplant to admission), with `usRds::verify_medicare_primary()`. This tests whether recipients with another primary payer, but a Medicare-paid index stay, change the estimates; it adds a flowchart step the paper does not show ([#3](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/3)).

No other sensitivity analyses are prespecified. A comparison of the hospitalization files with institutional claims was considered and not adopted, because the former are a subset of the latter (§3, [#1](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/1)).

## 10. Disclosure control

The USRDS data use agreement governs. No cell, count or percentage that discloses 1–10 people is published, including counts recoverable by subtraction. Figures, tables and the flowchart stay out of the repository until USRDS review before publication clears them.

## 11. Limitations to address in reporting

- Case and CM definitions use diagnosis codes, without microbiological confirmation.
- Immunosuppression during the index stay is not captured.
- Stepwise selection gives optimistic P values and unstable selection; the results are exploratory.
- Restriction to Medicare-paid hospitalizations limits generalisability, and Medicare-primary status is assumed rather than verified (§4).
- Differences from the published estimates may come from the data release, the order of exclusions, the open decisions above, or details of the original Stata code that the paper does not report. They are reported as such, not as corrections to the paper.

## 12. Reporting map

| Checklist item | Topic | Plan section |
|---|---|---|
| STROBE 1 / RECORD 1.1–1.3 | Title, abstract, data sources named | Scope, 3 |
| STROBE 2–3 | Background, objectives | 1 |
| STROBE 4 | Study design | 2 |
| STROBE 5 | Setting, dates | 3 |
| STROBE 6 / RECORD 6.1–6.3 | Eligibility, selection codes, linkage | 4, 5 |
| STROBE 7 / RECORD 7.1 | Variables, code lists | 5, 7 |
| STROBE 8 | Measurement | 5, 7 |
| STROBE 9 | Bias | 11 |
| STROBE 10 | Study size | 4 |
| STROBE 11 | Quantitative variables | 5, 8 |
| STROBE 12 / RECORD 12.1–12.2 | Statistical methods, data cleaning, linkage | 8, 3 |
| STROBE 13 / RECORD 13.1 | Participants, flowchart | 4 |
| STROBE 14–17 | Descriptive data, outcomes, main and other results | 8 |
| STROBE 19 / RECORD 19.1 | Limitations, including data not collected for research | 11 |
| STROBE 22 / RECORD 22.1 | Funding; data access and code availability | Scope, 10 |

## References

::: {#refs}
:::
