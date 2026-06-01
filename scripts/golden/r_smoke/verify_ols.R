# L3 smoke: compare R lm coefficients to datasets/golden/linear_ols.json (loose check).
# Run from repository root: Rscript scripts/golden/r_smoke/verify_ols.R
root <- normalizePath(getwd())
csv_path <- file.path(root, "datasets", "golden", "linear_ols.csv")
json_path <- file.path(root, "datasets", "golden", "linear_ols.json")

df <- read.csv(csv_path)
fit <- lm(y ~ x1 + x2, data = df)
coef_r <- coef(fit)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required")
}
spec <- jsonlite::fromJSON(json_path)
expected <- spec$expected$tidy

for (i in seq_len(nrow(expected))) {
  row <- expected[i, ]
  nm <- row$name
  val <- unname(coef_r[[nm]])
  if (is.na(val)) stop("missing coef ", nm)
  if (abs(val - row$estimate) > 1e-6) {
    stop(sprintf("OLS mismatch %s: R=%.12f json=%.12f", nm, val, row$estimate))
  }
}
cat("OK: OLS golden matches R lm within 1e-6\n")
