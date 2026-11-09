# AGENTS.md

Guidance for everyone working on this repository: the maintainer, collaborators, and any AI agents working for them. It covers how to work here: conventions, data handling, and checks.

| Document | Responsibility |
| --- | --- |
| `analysis-plan.md` | Scientific design, estimands, models, and sensitivity analyses |
| `REPOSITORY-BLUEPRINT.md` | Intended file and directory organization |
| `ARCHITECTURE.md` | Current code structure, data flow, and dependencies (maintained through Posit) |
| `AGENTS.md` | Implementation conventions, permissions, and review checks |
| [GitHub Issues](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues) | Open scientific decisions (decision issues), gaps between code and plan, and known defects |

Read the relevant documents before making changes. Follow `REPOSITORY-BLUEPRINT.md` for intended organization. Refer to [Cryptococcus-cost-analysis](https://github.com/VagishHemmige/Cryptococcus-cost-analysis) for examples of Quarto supporting files, chunk imports, callouts, and formatting—not for scientific methods. The analysis plan governs scientific decisions; `ARCHITECTURE.md` records the current implementation.

## The project

This is an **R analysis project, not an R package**. It rebuilds the analysis of Fiorica et al. 2025 (6-month mortality, and the factors associated with it, among kidney transplant recipients hospitalized with cryptococcosis, USRDS 2006–2016) with the [usRds](https://github.com/VagishHemmige/usRds) package. **The goal is to replicate the analysis as the paper describes it, and in doing so to make sure usRds covers every step.** Each step the package cannot yet do is recorded in `references/usrds-coverage.md` and tracked with the `usRds-gap` label. The code and methods are published as a Quarto website.

- **What counts as done for a step.** A step is done when it runs on synthetic data using usRds functions, or when its gap is recorded with a linked usRds issue (and, if the analysis needs it before the package does, a temporary wrapper in `R/functions.R`). The published counts and odds ratios are a reference point, not a target: the original analysis was run in Stata, that code is no longer available, and the data release may differ. A difference from the paper is investigated, but it is not a defect unless it comes from departing from the paper's methods or from a usRds error.
- **The paper is the specification; the legacy Rmd is secondary evidence.** The 2025-03-25 Rmd is the maintainer's best reconstruction of how the original Stata analysis was done; it did not produce the published results. Where the paper (including its supplement) states a method, the plan follows the paper. Where the paper is silent, the Rmd's choice is a candidate for the deciders, not a default; where the two disagree, the paper wins and the difference is noted (see [#4](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues/4)). Do not introduce package infrastructure or impose CRAN conventions.

- **The analysis plan is the scientific source of truth.** Code implements the plan; it does not redefine it. If implementation needs a different design, open a decision issue, or comment on the existing one, for the deciders. Once a decider has settled it (in the issue, or relayed there in their exact words), the plan change and the code can go in the same pull request, which closes the issue. Track decisions in Git history and issues rather than a change ledger within the plan.
- **Deciders.** Scientific decisions in every area are made by Vagish Hemmige. Anyone may open or contribute to a decision issue; only a decider settles it (see "Working with agents").
- Do not make unresolved scientific decisions implicitly through code. Check relevant open GitHub issues before implementing analyses that depend on them.
- Maintain implementation status and defects in GitHub Issues rather than in a standing list inside this file.
- **Default branch:** `main`. Changes reach it only through pull requests.

## Data sources

Each source this project uses is listed below with the package that accesses it. **Code that touches a source goes through its package.** Do not write project-specific loading, cleaning, or definition code for something the package already does.

| Source | Accessed through | Package documentation | Package maintained by | Access | What AI agents may do |
|---|---|---|---|---|---|
| USRDS standard analysis files, including linked Medicare claims and payer history (release as recorded for each result) | usRds (`load_usrds_file()`, `get_IN_ICD()`, `get_PS_ICD()`) | https://vagishhemmige.github.io/usRds/ | This team | Restricted (USRDS data use agreement) | None: code, documentation and synthetic data only |

To allow more for a source, a person changes its row through a pull request, naming the agreement and section that permit it, the approved AI service, and exactly what agents may do. Agents never propose or make this change themselves, and nothing in personal instructions can grant it.

Add a row when code first loads a new source. The UNOS transplant files (`txunos_trr_ki`, `txunos_trr_kp`, `txfuunos_*`, `txirunos`) are part of the USRDS release and are covered by the row above.

**For every package:**

- **Read its documentation before writing code for a source**, including known issues. Behavior that sets the cohort, an exposure, an outcome, or a denominator is checked in the documentation, not assumed from a function's name.

**For packages this team maintains:** see "Look in usRds first" below.

**For external packages:**

- **Work around problems here.** Wrap the function in `R/functions.R` with a comment explaining the problem and linking any upstream issue. Reporting a bug upstream is an external communication; the person directing the work decides whether to file it.
- **Facts about the source that this project relies on** (definitions, release quirks, suppression rules) go in `references/` with a citation to the provider's documentation, or in the plan when they shape a decision.

**For a source with no package:** one loading script records the download URL, the release or access date, and any processing. Verify its variables against the provider's documentation for that release.

## Exploration and definitive analysis

Exploration is welcome on branches or forks. Experimental scripts need not be sourced from `R/main.R` or have Quarto pages, and their findings are labelled preliminary. A script becomes part of the definitive analysis when it is sourced from `R/main.R`; from then on every rule below applies to it.

## R scripts

- Open the `.Rproj` and run `R/main.R` from the project root. `main.R` sources definitive scripts in dependency order.
- Keep scripts focused on one analytical responsibility. Study-specific scripts may be grouped in stage-specific subdirectories. Include a short header stating the script's role, its required upstream objects, and what it produces.
- When a definitive script is added or structurally reorganized, source it in `main.R` as appropriate and update `ARCHITECTURE.md` in the same pull request **when the change materially affects structure or data flow**. `ARCHITECTURE.md` describes current implementation, not planned work.
- Define shared libraries, paths, configurable analytical constants, and their dependencies in `R/setup.R`. Other scripts do not call `library()`, re-source `setup.R`, or hard-code study parameters. Large, version-controlled code lists may live in separate files sourced by `setup.R`.
- Place reusable helpers in `R/functions.R`, or organized subdirectories when warranted. Prefer explicit function arguments over dependence on global objects.
- Avoid `setwd()`, machine-specific absolute paths, and writes outside designated project outputs. Locate restricted USRDS inputs through `usRds`'s directory configuration.
- **No results in the repository.** No script (exploratory or definitive) or comment, commit message, issue, pull-request text or review report contains results, counts or data values from restricted data unless they are cleared for release. Check before every commit and post, since a public repository publishes everything pushed to it, on any branch.

## Chunk labels

Scripts are divided into labelled sections so Quarto can reuse code without copying it:

```r
## ---- cryptococcus-claims
```

- Label logical steps with descriptive kebab-case identifiers **unique across scripts**; a duplicate silently picks up the wrong code. A label covers code up to the next label.
- Before renaming or removing a label, check the `.qmd` pages that reference it.
- Labels are comments; the underlying R scripts must remain executable through `main.R`.

## Variable labels

- Label analytical variables with human-readable descriptions (for example, `labelled::set_variable_labels()`).
- For USRDS fields, prefer `usRds::apply_usrds_varlabels()` and `usRds::apply_usrds_factors()` rather than duplicating source labels.
- Label derived variables where created, including units and time windows where relevant.

## Quarto website

The site documents the code. It does not run the analysis. Exploratory scripts need no page.

- `_quarto.yml`, `index.qmd`, `404.qmd` (the page GitHub Pages shows for a missing address) and `styles.css` sit at the root; `quarto/` has one page per definitive script, named after it (for example, `quarto/create_cohort.qmd` for `R/create_cohort.R`), plus the Background, Study design and methods, About and project-document pages. The `custom-callout` extension in `_extensions/` provides the `Rcode`, `Results` and `Pending` callouts.
- **Visual cues.** Each kind of page has one sidebar icon, coloured by `styles.css`, and pages mark the same kind of content with the callout of that colour: background `book` (blue); study design and methods `diagram-3` (orange); R code `laptop` (pink, `Rcode` 💻); results `clipboard-data` (green, `Results` 📊); project documents `file-earmark-ruled` (grey). Give every new page the icon of its kind.
- **Provisional content.** `quarto/_pending.lua` highlights in yellow every paragraph that starts with **Decision pending:** or, in the plan, **Open:**, and any `[text]{.pending}`, and adds a ⏳ `Pending` callout to pages that have a mark. Mark only what an open decision could change, link the decision issue, and remove the mark when the decision is settled.
- **Project documents.** `analysis-plan.md`, `ARCHITECTURE.md`, `AGENTS.md` and `REPOSITORY-BLUEPRINT.md` are shown on the site by pages in `quarto/` that only include the root file, which stays the one source: edit the root file, not the page.
- Each script page loads its script with `knitr::read_chunk("../R/<script>.R")` in a hidden chunk and shows each labelled section with `#| eval: false`, with prose explaining what the section does and why, without duplicating source code. Pages link to the script on GitHub and to the scripts it depends on.
- **Never evaluate analysis code in the site.** Pages render without restricted data. Only the `read_chunk()` imports, the Architecture page's chunk that reads `ARCHITECTURE.md`, site helpers that read code or text, and results pages that read cleared outputs run. Review any proposed publication of aggregate results separately for disclosure compliance.
- **Publishing.** The site renders to `docs/`, which is not committed: a GitHub Actions workflow (`.github/workflows/publish.yml`) renders it on every push to `main` and publishes it to the `gh-pages` branch, which GitHub Pages serves. On a pull request the workflow only renders, as a check that every page builds.
- When you add a definitive script, add its page and sidebar entry in the same pull request. **Prose must match the code:** if a change alters what a section does, or its chunk labels, update its explanation and navigation in the same pull request.

## Outputs

- `R/tables.R` and `R/figures.R` may create outputs directly or orchestrate specialized scripts, exporting to `tables/` and `figures/`.
- `tables/` and `figures/` are gitignored until USRDS review before publication clears them for release, because they come from restricted data: agents may not open them (see Restricted data). Commit cleared, nonrestricted results only when intentional. Disclosure rules apply to all outputs.
- Published figures need alt text.
- `README.Rmd` is the source of `README.md`; edit the `.Rmd` and re-knit.

## Restricted data (applies to everyone)

USRDS and Medicare data are governed by a data use agreement (DUA). Applicable DUA requirements take precedence over convenience or automation. The **Access** column of "Data sources" says which sources are restricted. For each restricted source:

- **Never commit data**, extracts, person-level data objects, or saved objects or outputs derived from patient-level records. Keep restricted source data outside the repository, and review output paths and `.gitignore` before adding new output types.
- **AI agents never read restricted data.** Anything an agent opens, prints, or summarizes is sent to the model provider. Agents do not open data files or patient-level objects, print rows, or display identifiers (including USRDS IDs), person-level dates, or ZIP codes. Agents also do not open outputs from restricted data that are not yet cleared for release (for example `tables/` and `figures/` while they are ignored). Agents write code, review it, and run it on **synthetic data**; results on real data are produced by an authorized person in an authorized environment. A request to execute a pipeline does **not** itself provide authorization. The only exception is what the Data sources table explicitly allows for a source, and only within those words.
- **Synthetic data** are built in code, labelled as synthetic, and never derived from real records.
- **Disclosure.** Prevent disclosure of counts 1–10 in tables, figures, flowcharts, or prose, including counts recoverable by subtraction or complementary cells. Follow the applicable DUA's exact dissemination rules. Check every output before it leaves the approved environment, including scripts, comments, commit messages, issues, pull-request text and review reports (see R scripts).
- **Credentials and paid APIs.** Never commit keys, tokens, or `.Renviron`. Ask before paid, bulk, or uncached API calls.

## Look in usRds first

The [usRds](https://github.com/VagishHemmige/usRds) package is the first place to look for USRDS file loading, claims extraction, claim types, diagnosis dates, Medicare coverage, cohort helpers, and costs.

- Check its documentation, known limitations, and open issues before reproducing functionality locally.
- Raise generally reusable defects or enhancements in `usRds`; prefer fixes there. Temporary project-specific wrappers must identify the upstream issue and be reconsidered when resolved.
- When this analysis depends on a pending `usRds` enhancement or correction, track the study-specific implementation task here and link it to the corresponding `usRds` issue.
- Record the `usRds` version or commit used for any result.

## USRDS data facts

Sources: the Researcher's Guide, Appendix B, and Appendix C for the **specific USRDS release being analyzed**. The summary below is a starting point, not a replacement for release-appropriate documentation. Obtain the applicable public documents from the [NIDDK Researcher's Guide page](https://www.niddk.nih.gov/about-niddk/strategic-plans-reports/usrds/for-researchers/researchers-guide). Consult `usRds` for machine-readable variable labels and formats.

**Institutional (IN) claims** include inpatient, outpatient, skilled nursing facility, home health, and hospice services.

- `HCFASAF` historically distinguishes `I` inpatient, `O` outpatient, `N` SNF, `H` home health, and `S` hospice; older data can include `M` for REBUS inpatient stays.
- Since 2002, corresponding file families include `ip_*`, `op_*`, `sn_*`, `hh_*`, and `hs_*`, generally with CLM, DXP, and DET records. Confirm structure for the release.
- Institutional claim identifiers include `USRDS_ID`, `CLM_FROM`, and `SEQ_KEYC`; verify the applicable key in source documentation.

**Physician/supplier (PS) claims** have CLM, LINE, and DX sources.

- Claim lines are not necessarily distinct encounters. Define and validate episode grouping before counting services; distinguish diagnoses, procedures, and claim-level versus line-level records.
- Physician/supplier services are not synonymous with outpatient care.

**Claims year:** claims can be assigned by service end date rather than start date; verify against release documentation and account for claims crossing year boundaries.

**2025-release data currency (illustrative only; re-verify for the release used):** claims complete through 2023-12-31 except the Q1 2024 inpatient file; core files including death dates extend through 2024-12-31. Do not infer contemporaneous coverage of claims and vital status.

**Payer history (`payhist`):** payer categories and Medicare FFS observability must be verified against the release-specific guide. The **primary versus sensitivity coverage definitions are prescribed in `analysis-plan.md`**, not here. Pay attention to Medicare Advantage, Medicare secondary payer categories, uncovered days, and Medicare entitlement transitions after transplantation.

**ICD transition:** ICD-9-CM applies before 2015-10-01; ICD-10-CM and ICD-10-PCS on or after that date. Codes may omit decimals. Establish the date controlling the code system for claims spanning the transition, and verify against official code-set definitions.

**Unclear variables:** consult the relevant Appendix B/C and source code documentation rather than inferring meaning from variable names.

## Coding conventions

- Build descriptive flowchart text from centrally defined parameters so labels cannot become stale when an analysis window changes.
- **Code lists:** maintain code type, coding system, category, and exact/prefix matching; verify against official coding sources. Distinguish outcome from opportunity codes and personal-history from symptom codes. Do not invent clinical definitions or variables. Check category overlaps and clinically justified exceptions rather than assuming all codes are mutually exclusive.
- **Cohort flow:** every patient-level inclusion or exclusion goes through `fc_filter()` in the `flowchart` workflow. Do not drop rows from `$data` outside the flowchart; the diagram must reproduce the cohort exactly.
- **Joins:** specify join keys and expected relationships. Check row multiplication, particularly after interval joins, and define handling of missing or unmatched records explicitly.
- **Dates and windows:** implement the boundaries prespecified in the analysis plan; test boundary cases on synthetic data.
- **Code that turns model output into reported numbers** lives in named functions in `R/functions.R`, tested on synthetic data with a known answer.
- **Package APIs:** read the help page and NEWS for the installed version before calling a package; don't write calls from memory.
- **Style:** use readable tidyverse conventions. Related readability improvements may accompany functional changes; keep unrelated large-scale formatting separate.

## Checks for any change

Before presenting changes for review or seeking commit approval, perform the applicable checks below. Report which checks were completed, which were not, and any limitations.

**Every change**

- **Plan:** does the change implement the plan as written, and does it leave every open decision open?
- **Data sources:** does it use usRds's functions, and does their documented behavior match what the plan needs?
- **Package APIs:** for new or changed calls to a package, does the pull request name the installed version and the help page or NEWS entry relied on?
- **Reported numbers:** does each estimate match the plan's estimand, and do tables, figures, and site prose say what the code actually computes?
- **Disclosure:** search every changed tracked file, and the commit messages and pull-request text, for dates, record IDs, names, absolute paths and numbers that could come from restricted data. Read each hit in context; legitimate ones (plan dates, deciders' names, synthetic examples) stay.

**Cohort construction**

- Do the order, denominator, and labels of flowchart steps reflect the actual conditions?
- Are the cohort counts reproducible from the operations shown?
- Is downstream analysis based on the final flowchart dataset?

**Claims and case definitions**

- Which claim files, claim types, diagnosis fields, and date fields are used?
- Are exact/prefix matching and ICD-9/ICD-10 date transitions handled appropriately?
- Can history codes, rule-out diagnoses, or outcome codes contaminate opportunities?

**Windows and coverage**

- Does index ascertainment agree with the analysis plan?
- Are date-window boundaries correct and inclusive where specified?
- Does eligible Medicare coverage span the **entire** required observation period, with adjacent spans joined without allowing gaps?

**Transplant timing**

- Are first and repeat transplants distinguished where the analysis requires them?
- Are transplant dates and characteristics drawn from the correct episode according to the analysis plan?
- Are graft failure and repeat transplants treated as prespecified?

**Residence and facility**

- Is residence information valid for the relevant date?
- Is facility information aligned to the appropriate year and transplant center?
- Are historical identifiers and changes in identifiers accounted for?

**Structure and documentation**

- Does `ARCHITECTURE.md` describe current scripts and data flow when structural changes warrant an update?
- Are chunk labels unique, and do Quarto pages continue to find the labels they reference?
- Does every definitive script have a Quarto page and sidebar entry, with matching chunk labels? Were affected pages and navigation updated?
- Does any site chunk evaluate analysis code, and are derived variables labeled?

**Execution**

- Does `main.R` run from a clean session, using suitable relative paths?
- Are machine-specific absolute paths or hard-coded restricted-data directories absent?
- Are package versions and saved intermediates documented and checked for staleness?

**Validation on real data** (by an authorized person only; share only permitted, disclosure-reviewed aggregate findings)

- Row counts before and after interval joins.
- Counts of people with multiple matching coverage or residence spans.
- Case counts by ICD-9 versus ICD-10 era and by claim type.

## Working with agents

- **Autonomy.** The person directing an agent sets its working style (review only, step by step, or hands-off) in their own instructions, and may add stricter rules; those take precedence. Without a style, an agent works step by step. At most, an agent may edit code and documentation, add scripts and tests, run code and render the site on synthetic data, and commit to a branch and open a pull request.
- **Decisions.** Anyone, including an agent, may add options and evidence to a decision issue. A decider states the choice in the issue. Agents implement decisions; they never choose among options on their own, in the issue, the plan, or the code.
- **Every agent, under any autonomy:** never merges a pull request; follows the restricted-data rules; asks before running the full pipeline or making expensive external/API calls (approval for these does not override DUA restrictions); shows a person the exact text before posting or sending anything as them, unless that person's own instructions waive this; and proposes another way of writing something already agreed before committing it.
- **Pull requests opened by an agent** are focused. Each says which plan section or issue it addresses, what was checked, and whether by running code on synthetic data or by reading only. Synthetic results are never described as clinical results.
- **Scientific citations:** maintain verified references in root-level `references.bib`; cite methodological sources in `analysis-plan.md` and technical references with the corresponding implementation documentation. Verify bibliographic metadata, source support for claims, and compatibility with the data release being analyzed.
