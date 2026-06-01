# L3 smoke: compare R ivreg to datasets/golden/linear_iv.json (loose check).
# Run from repository root: Rscript scripts/golden/r_smoke/verify_iv.R
root <- normalizePath(getwd())
csv_path <- file.path(root, "datasets", "golden", "linear_iv.csv")
json_path <- file.path(root, "datasets", "golden", "linear_iv.json")

df <- read.csv(csv_path)
if (!requireNamespace("ivreg", quietly = TRUE)) {
  stop("ivreg package required")
}
library(ivreg)
fit <- ivreg(y ~ x1 + x2 | x1 + z1 + z2, data = df)
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
  if (abs(val - row$estimate) > 1e-5) {
    stop(sprintf("IV mismatch %s: R=%.12f json=%.12f", nm, val, row$estimate))
  }
}
cat("OK: IV golden matches R ivreg within 1e-5\n")
