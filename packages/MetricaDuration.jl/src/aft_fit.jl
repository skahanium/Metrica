# aft_fit.jl — AFT 参数加速失效模型族
# Weibull / Exponential / Log-normal / Log-logistic

struct AFTFitResult
    model::Symbol
    distribution::String
    coef_names::Vector{Symbol}
    beta::Vector{Float64}
    se::Vector{Float64}
    sigma::Float64
    loglik::Float64
    aic::Float64
    bic::Float64
    n::Int
    n_events::Int
    n_censored::Int
    time_ratios::Vector{Float64}
    tr_ci_lower::Vector{Float64}
    tr_ci_upper::Vector{Float64}
    converged::Bool
    iterations::Int
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end

# === AFT 对数似然 =============================================================

function _aft_ll_weibull(beta_sigma::Vector, X::Matrix, log_t::Vector, event::Vector{Int})
    k = size(X, 2); beta = beta_sigma[1:k]; sigma = exp(beta_sigma[k+1]); loc = X * beta
    z = (log_t .- loc) ./ sigma
    ll = 0.0
    for i in eachindex(z)
        vi = z[i]; ei = event[i]
        ll += ei * (vi - log(sigma) + log(pdf(ExtremeValue(), vi))) + (1 - ei) * log(ccdf(ExtremeValue(), vi))
    end
    return ll
end

function _aft_ll_exponential(beta::Vector, X::Matrix, log_t::Vector, event::Vector{Int})
    loc = X * beta
    z = (log_t .- loc); sigma = 1.0
    ll = 0.0
    for i in eachindex(z)
        ei = event[i]; vi = z[i]
        ll += ei * (vi + log(pdf(ExtremeValue(), vi))) + (1 - ei) * log(ccdf(ExtremeValue(), vi))
    end
    return ll
end

function _aft_ll_lognormal(beta_sigma::Vector, X::Matrix, log_t::Vector, event::Vector{Int})
    k = size(X, 2); beta = beta_sigma[1:k]; sigma = exp(beta_sigma[k+1]); loc = X * beta
    z = (log_t .- loc) ./ sigma
    ll = 0.0
    for i in eachindex(z)
        ei = event[i]; vi = z[i]
        ll += ei * (-log(sigma) + log(pdf(Normal(), vi))) + (1 - ei) * log(ccdf(Normal(), vi))
    end
    return ll
end

function _aft_ll_loglogistic(beta_sigma::Vector, X::Matrix, log_t::Vector, event::Vector{Int})
    k = size(X, 2); beta = beta_sigma[1:k]; sigma = exp(beta_sigma[k+1]); loc = X * beta
    z = (log_t .- loc) ./ sigma
    ll = 0.0
    for i in eachindex(z)
        ei = event[i]; vi = z[i]
        fz = pdf(Logistic(), vi); Sz = ccdf(Logistic(), vi)
        ll += ei * (log(fz) - log(sigma)) + (1 - ei) * log(Sz)
    end
    return ll
end

# === AFT 拟合函数 =============================================================

function fit_aft(df::DataFrame, formula::AbstractString, time_col::AbstractString,
                  event_col::AbstractString; dist::String="weibull")
    nls = MetricaBase.parse_metrica_formula(formula)
    nls isa MetricaBase.ModelError && return nls
    yname, xnames = nls
    isempty(xnames) && return MetricaBase.ModelError(:aft_no_covariates, "AFT 需要至少一个解释变量", "", "")

    needcols = unique(vcat([Symbol(time_col), Symbol(event_col)], Symbol.(xnames)))
    missing_cols = setdiff(needcols, propertynames(df))
    isempty(missing_cols) || return MetricaBase.ModelError(:aft_missing_columns, "缺少列: $(join(missing_cols, ", "))", "", "")

    sub = select(df, needcols); dropmissing!(sub); nrow(sub) > 0 || return ModelError(:aft_empty_sample, "有效样本为空", "", "")
    sub_cols = collect(eachcol(sub))
    timev = Float64.(sub_cols[1]); event_raw = sub_cols[2]
    event = Int[e in (1, true) ? 1 : 0 for e in event_raw]
    ne = sum(event); ne > 0 || return MetricaBase.ModelError(:aft_no_events, "无事件", "", "")
    n = nrow(sub)

    log_t = log.(max.(timev, 1e-12))
    X = [ones(n) Matrix{Float64}(hcat([Float64.(sub[!, Symbol(c)]) for c in xnames]...))]
    p = size(X, 2)

    has_sigma = dist != "exponential"
    x0 = has_sigma ? vcat(zeros(p), log(0.5)) : zeros(p)

    ll_fn = if dist == "weibull"; _aft_ll_weibull
    elseif dist == "exponential"; _aft_ll_exponential
    elseif dist == "lognormal"; _aft_ll_lognormal
    elseif dist == "loglogistic"; _aft_ll_loglogistic
    else; return MetricaBase.ModelError(:aft_unknown_dist, "未知分布: $dist", "", "") end

    obj(x) = -ll_fn(x, X, log_t, event)
    opt = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=5000, f_reltol=1e-6, g_reltol=1e-6))
    xm = Optim.minimizer(opt); converged = Optim.converged(opt); iters = Optim.iterations(opt)
    beta_hat = xm[1:p]; sigma_hat = has_sigma ? exp(xm[p+1]) : 1.0
    ll = -Optim.minimum(opt)

    H = zeros(Float64, length(x0), length(x0))
    FiniteDiff.finite_difference_hessian!(H, obj, xm)
    Hs = Symmetric(H); evmin = minimum(eigvals(Matrix(Hs)))
    evmin < 1e-10 && (Hs = Hs + (1e-8 - evmin) * I)
    covb = try inv(Matrix(Hs)); catch; return MetricaBase.ModelError(:aft_singular_information, "信息矩阵奇异", "", "") end
    se_all = sqrt.(clamp.(diag(covb), 0.0, Inf))
    se_beta = se_all[1:p]

    k_params = p + (has_sigma ? 1 : 0)
    aic = -2 * ll + 2 * k_params; bic = -2 * ll + k_params * log(n)

    time_ratios = exp.(beta_hat)
    z_crit = 1.96
    tr_lo = exp.(beta_hat .- z_crit .* se_beta); tr_hi = exp.(beta_hat .+ z_crit .* se_beta)

    diag = Dict{Symbol, Any}(:n_obs => n, :n_events => ne, :n_censored => n - ne,
        :censoring_fraction => (n - ne) / max(n, 1), :distribution => dist,
        :sigma => sigma_hat, :converged => converged, :iterations => iters,
        :loglikelihood => ll, :aic => aic, :bic => bic)

    return AFTFitResult(:aft, dist, vcat([:intercept], Symbol.(xnames)),
        beta_hat, se_beta, sigma_hat, ll, aic, bic,
        n, ne, n - ne, time_ratios, tr_lo, tr_hi, converged, iters, diag,
        MetricaBase.ModelWarning[])
end

# === 接口 =====================================================================

MetricaBase.glance(r::AFTFitResult) = MetricaBase.ModelGlance(r.model, r.n, length(r.beta),
    Dict{Symbol, MetricaBase.MetricValue}(:loglik => r.loglik, :aic => r.aic, :bic => r.bic,
        :n_events => r.n_events, :n_censored => r.n_censored, :sigma => r.sigma), r.warnings)

MetricaBase.tidy(r::AFTFitResult) = MetricaBase.TidyTable(
    [MetricaBase.CoefRow(r.coef_names[i], r.beta[i], r.se[i], r.se[i] > 0 ? r.beta[i] / r.se[i] : nothing, r.se[i] > 0 ? 2*(1-cdf(Normal(), abs(r.beta[i]/r.se[i]))) : nothing, r.beta[i] - 1.96*r.se[i], r.beta[i] + 1.96*r.se[i]) for i in eachindex(r.coef_names)], "AFT MLE ($(r.distribution))")

function result_to_payload(r::AFTFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(r); tidy_table = MetricaBase.tidy(r)
    glance_dict, warnings = MetricaBase.build_glance_envelope(glance_table)
    tidy_rows = MetricaBase.build_tidy_rows(tidy_table)
    payload = Dict{String, Any}("status" => "success", "messages" => [],
        "result_payload" => Dict{String, Any}(
            "glance" => glance_dict, "tidy" => tidy_rows, "warnings" => warnings,
            "loglikelihood" => r.loglik, "aic" => r.aic, "bic" => r.bic,
            "distribution" => r.distribution, "sigma" => r.sigma,
            "time_ratios" => [Dict("term" => String(r.coef_names[i]), "tr" => r.time_ratios[i], "ci_lower" => r.tr_ci_lower[i], "ci_upper" => r.tr_ci_upper[i]) for i in eachindex(r.coef_names)],
            "diagnostics" => MetricaBase.dict_symbol_to_string(r.diagnostics)))
    return payload
end

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool=true) = MetricaBase.error_to_payload(err)
