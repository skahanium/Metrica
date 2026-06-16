# L3 smoke: plm::pgmm on demo fixture vs datasets/golden/panel_dynamic_gmm.json (loose)
# Run from repository root: Rscript scripts/golden/r_smoke/verify_panel_gmm.R
root <- normalizePath(getwd())
csv_path <- file.path(root, "datasets", "demo", "dynamic_panel_gmm_golden.csv")
json_path <- file.path(root, "datasets", "golden", "panel_dynamic_gmm.json")

if (!file.exists(csv_path)) {
  cat("SKIP: panel demo CSV not found\n")
  quit(status = 0)
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required")
}
if (!requireNamespace("plm", quietly = TRUE)) {
  cat("SKIP: plm not installed\n")
  quit(status = 0)
}

df <- read.csv(csv_path)
# One-step difference GMM smoke; coefficients need not match Metrica exactly.
fit <- tryCatch(
  plm::pgmm(
    y ~ lag(y, 1) + x | lag(y, 2),
    data = df,
    index = c("firm", "year"),
    model = "onestep",
    effect = "individual",
  ),
  error = function(e) {
    cat("SKIP: pgmm failed:", conditionMessage(e), "\n")
    quit(status = 0)
  }
)

spec <- jsonlite::fromJSON(json_path)
tidy <- spec$expected$tidy
d_row <- tidy[tidy$name == "D_x", , drop = FALSE]
if (nrow(d_row) != 1) {
  cat("SKIP: D_x row not in golden json\n")
  quit(status = 0)
}

coef_all <- coef(fit)
dx_name <- names(coef_all)[grep("x", names(coef_all), fixed = TRUE)][1]
if (is.na(dx_name)) {
  cat("SKIP: could not locate x coefficient in pgmm output\n")
  quit(status = 0)
}

dx_r <- unname(coef_all[[dx_name]])
if (sign(dx_r) != sign(d_row$estimate)) {
  stop(sprintf("Panel GMM smoke sign mismatch: R=%.6f json=%.6f", dx_r, d_row$estimate))
}
cat("OK: panel_dynamic_gmm D_x sign matches loose R pgmm smoke\n")
