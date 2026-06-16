# L3 smoke: loose DID interaction check against datasets/golden/causal_did.json
# Run from repository root: Rscript scripts/golden/r_smoke/verify_causal_did.R
root <- normalizePath(getwd())
csv_path <- file.path(root, "datasets", "golden", "causal_did.csv")
json_path <- file.path(root, "datasets", "golden", "causal_did.json")

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required")
}

df <- read.csv(csv_path)
fit <- lm(y ~ treated * post + x1, data = df)
coef_r <- coef(fit)
interaction <- coef_r[["treated:post"]]
if (is.na(interaction)) interaction <- coef_r[["post:treated"]]

spec <- jsonlite::fromJSON(json_path)
metrics <- spec$expected$metrics
te_row <- metrics[metrics$name == "treat_effect", , drop = FALSE]
if (nrow(te_row) != 1) stop("expected treat_effect metric missing")
te_json <- te_row$value

if (abs(interaction - te_json) > 0.25) {
  stop(sprintf(
    "DID smoke mismatch: R interaction=%.6f json treat_effect=%.6f",
    interaction, te_json
  ))
}
cat("OK: causal_did treat_effect within loose R lm smoke tolerance\n")
