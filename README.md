
<!-- README.md is generated from README.Rmd. Please edit that file -->

<!-- badges: start -->
[![Status](https://img.shields.io/badge/status-preliminary_analysis-yellow)](#)
[![Methods](https://img.shields.io/badge/methods-under_development-blue)](#)
[![Not for Citation](https://img.shields.io/badge/use-not_for_citation-lightgrey)](#)
<!-- badges: end -->

# Cryptococcosis in kidney transplant recipients: a usRds reconstruction

This repository rebuilds the analysis in Fiorica et al. (*Open Forum Infectious Diseases* 2025; [doi:10.1093/ofid/ofaf263](https://doi.org/10.1093/ofid/ofaf263)) using the [usRds](https://github.com/VagishHemmige/usRds) package. The paper reported 6-month mortality, and the factors associated with it, among kidney transplant recipients hospitalized with cryptococcosis in USRDS data from 2006 to 2016.

The goal is **package coverage, not replication of the published numbers**. Each step of the published analysis is rebuilt with usRds functions where they exist. Steps the package cannot yet do are recorded as gaps, so they can be added to usRds.

This analysis is currently in progress.

The analysis website, which explains the code step by step, will be at:
https://vagishhemmige.github.io/fiorica-cryptoccoccus-analysis/

## Documentation

- [`analysis-plan.md`](analysis-plan.md): what the analysis is meant to do
- [`references/usrds-coverage.md`](references/usrds-coverage.md): each step of the paper mapped to usRds functions, with gaps
- [`ARCHITECTURE.md`](ARCHITECTURE.md): how the code is organized (not yet written)
- [`AGENTS.md`](AGENTS.md): how to work in this repository
- [Issues](https://github.com/VagishHemmige/fiorica-cryptoccoccus-analysis/issues): open decisions and known gaps

## Running the analysis

Run `R/main.R` from the project root. This requires authorized access to the USRDS files, which are located through the usRds package (`usRds::set_USRDS_wd()`).

<!-- Results: add only when the figures and tables are cleared for public release. -->
