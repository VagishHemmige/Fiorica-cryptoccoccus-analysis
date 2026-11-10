# Purpose: Figure 1 (cohort flowchart), Figure 2 (Kaplan-Meier survival with
#   risk table) and Figure 3 (forest plot of adjusted odds ratios), in the
#   house style (plot_style.R), with captions and alt text (plan §4, §8, §10).
# Needs: setup.R, functions.R, plot_style.R, create_cohort.R
#   (cohort_flowchart), fit_models.R (km_fit, multivariable), report_tables.R
#   (report_labels, disclosure_checks); installed: ggsurvfit, ragg, svglite.
# Produces: figure_2, figure_3 (ggplot objects), figure_text (caption and
#   alt text per figure), disclosure_checks (with the figure checks added),
#   and files in figures/ (gitignored until USRDS review; plan §10).

## ---- figure-defaults
ggplot2::theme_set(theme_publication())
dir.create("figures", showWarnings = FALSE)

## ---- figure-1
# The flowchart from the same object that built the cohort, so the diagram
# and the analytic data cannot disagree. A box with 1 to 10 people is not
# exported: the run warns and the check is left for review.
flowchart_boxes <- flowchart::fc_view(cohort_flowchart, what = "fc")
flowchart_small <- flowchart_small_counts(flowchart_boxes)

if (nrow(flowchart_small) == 0) {
  cohort_flowchart %>%
    flowchart::fc_draw(big.mark = ",", box_corners = "sharp") %>%
    flowchart::fc_export("figure_1.png", path = "figures", width = 180, height = 240, units = "mm", res = 600) %>%
    flowchart::fc_export("figure_1.pdf", path = "figures", width = 180, height = 240, units = "mm")
} else {
  warning(
    "Figure 1 not exported: ", nrow(flowchart_small),
    " box(es) with 1 to 10 people (see flowchart_small).",
    call. = FALSE
  )
}

## ---- figure-2
# Kaplan-Meier survival from the index admission (KMunicate style: curve with
# its 95% CI, and at risk, deaths and censored below). The risk table shows
# only times that pass the small-count rule, and the curve stops at the last
# of them (plan §10). Time 0 stays on the axis even when the table cannot
# show it (for example, 1 to 10 deaths on the admission day). A dashed line
# marks 6 months.
days_per_month <- 365.25 / 12
km_candidate_times <- c(0, mortality_window_days, seq(365, 10 * 365, by = 365))
km_times <- km_reportable_times(km_fit, km_candidate_times)
months_label <- \(days) round(days / days_per_month)

figure_2 <- ggsurvfit::ggsurvfit(
  km_fit,
  theme = theme_publication(),
  color = publication_colors[2],
  linewidth = 0.5
) +
  ggsurvfit::add_confidence_interval(fill = publication_colors[2], alpha = 0.15) +
  ggplot2::geom_vline(
    xintercept = mortality_window_days,
    linetype = "22", color = "gray40", linewidth = 0.3
  ) +
  ggsurvfit::add_risktable(
    times = km_times,
    risktable_stats = c("n.risk", "cum.event", "cum.censor"),
    stats_label = list(n.risk = "At risk", cum.event = "Deaths", cum.censor = "Censored"),
    theme = ggsurvfit::theme_risktable_default(axis.text.y.size = 8, plot.title.size = 8),
    size = 2.4
  ) +
  ggplot2::scale_x_continuous(
    breaks = union(0, km_times),
    labels = months_label,
    limits = c(0, max(km_times)),
    expand = ggplot2::expansion(add = c(60, 200))
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_percent(),
    limits = c(0, 1),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(x = "Months since index admission", y = "Overall survival")

save_figure(figure_2, file.path("figures", "figure_2"), width = 170, height = 120)

## ---- figure-3
# Adjusted odds ratios from the final model, with 95% Wald CIs, on a log
# scale; the estimate and interval are printed beside each row.
odds_ratios <- tidy_odds_ratios(multivariable$model, report_labels) %>%
  mutate(
    term_label = fct_rev(fct_inorder(term_label)),
    or_text = str_glue(
      "{style_or(estimate)} ({style_or(conf.low)}–{style_or(conf.high)})",
      style_or = \(x) formatC(x, format = "f", digits = 2)
    )
  )
or_text_x <- max(odds_ratios$conf.high) * 1.6

figure_3 <- ggplot2::ggplot(odds_ratios, ggplot2::aes(x = estimate, y = term_label)) +
  ggplot2::geom_vline(xintercept = 1, linetype = "22", color = "gray40", linewidth = 0.3) +
  ggplot2::geom_pointrange(
    ggplot2::aes(xmin = conf.low, xmax = conf.high),
    color = publication_colors[2], size = 0.3, linewidth = 0.4
  ) +
  ggplot2::geom_text(
    ggplot2::aes(x = or_text_x, label = or_text),
    hjust = 0, size = 2.6, color = "gray20"
  ) +
  ggplot2::scale_x_log10(expand = ggplot2::expansion(mult = c(0.05, 0.45))) +
  ggplot2::coord_cartesian(clip = "off") +
  ggplot2::labs(x = "Adjusted odds ratio (95% CI), log scale", y = NULL) +
  ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())

save_figure(
  figure_3, file.path("figures", "figure_3"),
  width = 160, height = 30 + 8 * nrow(odds_ratios)
)

## ---- figure-text
# Captions and alt text, built from the fitted objects so no number is
# retyped.
list_or_none <- \(x) if (length(x) == 0) "none" else str_flatten_comma(as.character(x), ", and ")
six_month_survival <- summary(km_fit, times = mortality_window_days)$surv
reference_levels <- multivariable$model$xlevels %>%
  imap_chr(\(levels, variable) str_c(report_labels[[variable]], ": ", levels[1]))
figure_text <- tibble(
  figure = c("figure_1", "figure_2", "figure_3"),
  caption = c(
    "Figure 1. Selection of kidney transplant recipients hospitalized with cryptococcosis, USRDS 2006-2016.",
    str_glue(
      "Figure 2. Kaplan-Meier estimate of overall survival from the index admission, with 95% confidence interval. ",
      "The dashed line marks 6 months. Numbers below are people at risk and cumulative deaths and censored; ",
      "the curve stops at the last time with more than 10 people at risk (USRDS data use agreement)."
    ),
    str_c(
      "Figure 3. Adjusted odds ratios for death within 6 months of admission, from the final logistic model after backward elimination, with 95% confidence intervals (log scale).",
      if (length(reference_levels) > 0) str_c(" Reference categories: ", str_flatten(reference_levels, "; "), ".") else ""
    )
  ),
  alt_text = c(
    str_glue(
      "Flowchart of {nrow(flowchart_boxes %>% filter(type == 'exclude'))} exclusion steps, from people with a cryptococcosis ",
      "hospitalization to the {scales::label_comma()(nrow(cohort))} recipients in the analysis."
    ),
    str_glue(
      "Single Kaplan-Meier survival curve over {months_label(max(km_times))} months after admission; ",
      "survival at 6 months is {scales::label_percent(accuracy = 0.1)(six_month_survival)}."
    ),
    str_glue(
      "Forest plot of {nrow(odds_ratios)} adjusted odds ratios. ",
      "Confidence intervals entirely above 1: ",
      "{list_or_none(odds_ratios$term_label[odds_ratios$conf.low > 1])}; ",
      "entirely below 1: ",
      "{list_or_none(odds_ratios$term_label[odds_ratios$conf.high < 1])}."
    )
  )
)
write_csv(figure_text, file.path("figures", "figure_text.csv"))

## ---- figure-disclosure-checks
disclosure_checks <- disclosure_checks %>%
  add_row(
    check = "Figure 1: boxes with 1 to 10 people",
    value = nrow(flowchart_small),
    needs_review = nrow(flowchart_small) > 0
  ) %>%
  add_row(
    check = "Figure 2: last time shown (days)",
    value = max(km_times),
    needs_review = FALSE
  )
