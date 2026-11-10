# Purpose: survival curve and logistic models for 6-month mortality (plan §8).
# Needs: setup.R, functions.R, create_outcomes.R (analysis_data, model_data).
# Produces: km_fit, bivariable_results, multivariable (list: model, data,
#   steps, retained), hosmer_lemeshow_result, published_fit.

## ---- models-kaplan-meier
# Kaplan-Meier estimate of survival from the index admission (Figure 2).
km_fit <- survfit(
  Surv(survival_days, survival_event) ~ 1,
  data = analysis_data
)

## ---- models-bivariable
# Each candidate alone, on the people with it known.
bivariable_results <- bivariable_models(
  model_data,
  outcome = "died_within_window",
  candidates = model_candidates
)

## ---- models-multivariable
# Every candidate entered, then backward elimination at P < .05, on the
# complete cases for all candidates (plan §8).
multivariable <- backward_eliminate(
  model_data,
  outcome = "died_within_window",
  candidates = model_candidates,
  threshold = elimination_threshold
)

## ---- models-published
# The paper's final model, fitted as published: its eight terms on the same
# people as the backward elimination (complete cases for every candidate),
# because the paper's estimates come from the end of that selection
# (plan §8). Compared with the published odds ratios in Table 4.
published_fit <- glm(
  reformulate(published_model$term, response = "died_within_window"),
  family = binomial(),
  data = multivariable$data
)

## ---- models-goodness-of-fit
# Hosmer-Lemeshow goodness of fit of the final model, with deciles of risk.
hosmer_lemeshow_result <- hosmer_lemeshow(
  observed = multivariable$data$died_within_window,
  predicted = fitted(multivariable$model)
)
