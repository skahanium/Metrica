# L3 smoke: R survival::coxph vs datasets/golden/duration_cox.json (loose)
# Run from repository root: Rscript scripts/golden/r_smoke/verify_duration_cox.R
root <- normalizePath(getwd())
csv_path <- file.path(root, "datasets", "golden", "duration_cox.csv")
json_path <- file.path(root, "datasets", "golden", "duration_cox.json")

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required")
}
if (!requireNamespace("survival", quietly = TRUE)) {
  stop("survival required")
}

df <- read.csv(csv_path)
fit <- survival::coxph(survival::Surv(time, fail) ~ x1, data = df)
coef_r <- coef(fit)["x1"]

spec <- jsonlite::fromJSON(json_path)
tidy <- spec$expected$tidy
x1_row <- tidy[tidy$name == "x1", , drop = FALSE]
if (nrow(x1_row) != 1) stop("expected x1 tidy row missing")

if (abs(coef_r - x1_row$estimate) > 0.5) {
  stop(sprintf(
    "Cox smoke mismatch: R=%.6f json=%.6f",
    coef_r, x1_row$estimate
  ))
}
cat("OK: duration_cox x1 within loose R survival smoke tolerance\n")
