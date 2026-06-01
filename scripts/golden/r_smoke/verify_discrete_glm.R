# L3 smoke: R glm() vs discrete golden JSON (logit / probit / poisson coefficients).
# Run from repository root: Rscript scripts/golden/r_smoke/verify_discrete_glm.R
root <- normalizePath(getwd())

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required")
}

verify_case <- function(case_id, family, link = NULL) {
  csv_path <- file.path(root, "datasets", "golden", paste0(case_id, ".csv"))
  json_path <- file.path(root, "datasets", "golden", paste0(case_id, ".json"))
  df <- read.csv(csv_path)
  if (is.null(link)) {
    fit <- glm(y ~ x1 + x2, data = df, family = family)
  } else {
    fit <- glm(y ~ x1 + x2, data = df, family = family(link = link))
  }
  coef_r <- coef(fit)
  spec <- jsonlite::fromJSON(json_path)
  expected <- spec$expected$tidy
  atol <- 1e-5
  if (family$family %in% c("binomial")) atol <- 1e-4
  for (i in seq_len(nrow(expected))) {
    row <- expected[i, ]
    nm <- row$name
    val <- unname(coef_r[[nm]])
    if (is.na(val)) stop(case_id, ": missing coef ", nm)
    if (abs(val - row$estimate) > atol) {
      stop(sprintf(
        "%s mismatch %s: R=%.12f json=%.12f (atol=%g)",
        case_id, nm, val, row$estimate, atol
      ))
    }
  }
  cat("OK:", case_id, "matches R glm within tolerance\n")
}

verify_case("discrete_logit", binomial(link = "logit"))
verify_case("discrete_probit", binomial(link = "probit"))
verify_case("discrete_poisson", poisson())
