# === NIG 共轭贝叶斯线性回归 =======================================================

function fit_bayes_linear(
    df::DataFrame,
    formula::AbstractString;
    bayes_seed::Union{Nothing, Int}=nothing,
    bayes_prior_scale::Float64=1.0,
    bayes_sigma2_known::Bool=false,
    bayes_sigma2_value::Float64=NaN,
    bayes_ig_alpha::Float64=2.0,
    bayes_ig_beta::Float64=1.0,
)
    isnothing(bayes_seed) || Random.seed!(bayes_seed)

    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    isempty(xnames) && return MetricaBase.ModelError(:bayes_no_covariates, "至少需要一个协变量", "", "")

    needcols = unique(vcat([yname], xnames))
    missingcols = setdiff(Symbol.(needcols), propertynames(df))
    isempty(missingcols) || return MetricaBase.ModelError(:bayes_missing_columns, "缺少列: $(join(missingcols, ", "))", "", "")

    sub = select(df, Symbol.(needcols)); dropmissing!(sub)
    nrow(sub) > 0 || return MetricaBase.ModelError(:bayes_empty_sample, "有效样本为空", "", "")
    n = nrow(sub)
    y = Float64.(sub[!, Symbol(yname)])
    X = hcat(ones(n), [Float64.(sub[!, Symbol(c)]) for c in xnames]...)
    p = size(X, 2)

    τ² = bayes_prior_scale^2
    prior_prec = 1.0 / τ² * I(p)

    # 后验精度: Σ_n⁻¹ = X'X + τ⁻²I
    post_prec = X' * X + prior_prec
    Σ_n = Symmetric(post_prec) \ I
    μ_n = Σ_n * (X' * y)

    if bayes_sigma2_known
        σ² = bayes_sigma2_value
        σ² <= 0 && return MetricaBase.ModelError(:bayes_invalid_sigma2, "bayes_sigma2_value 须为正数", "收到 $σ²", "")
        # β|y ~ N(μ_n, σ²·Σ_n)
        post_sd = sqrt.(σ² .* diag(Σ_n))
        # Log marginal likelihood (精确)
        rss = dot(y - X * μ_n, y - X * μ_n) + dot(μ_n, prior_prec * μ_n)
        log_ml = -n/2 * log(2π * σ²) - rss/(2σ²) + p/2 * log(τ²) - 0.5 * logdet(post_prec)
        inference_mode = "analytical"
        sigma2_val = σ²
    else
        # σ² ~ InvGamma(α, β)
        α_n = bayes_ig_alpha + n / 2
        rss = dot(y - X * μ_n, y - X * μ_n) + dot(μ_n, prior_prec * μ_n)
        β_n = bayes_ig_beta + rss / 2
        # β|y ~ t_2α_n(μ_n, (β_n/α_n)·Σ_n)
        t_scale = (β_n / α_n) .* Σ_n
        post_sd = sqrt.(diag(t_scale)) .* sqrt(2α_n / (2α_n - 2))  # SD = scale * sqrt(ν/(ν-2))
        for k in eachindex(post_sd)
            post_sd[k] = isfinite(post_sd[k]) ? post_sd[k] : Inf
        end
        log_ml = nothing
        inference_mode = "analytical"
        sigma2_val = β_n / (α_n - 1)  # 后验均值
    end

    # 95% credible interval
    t_crit = if bayes_sigma2_known
        quantile(Normal(), 0.975)
    else
        quantile(TDist(2α_n), 0.975)
    end
    ci_lower = μ_n .- t_crit .* post_sd
    ci_upper = μ_n .+ t_crit .* post_sd

    coef_names = vcat([:intercept], Symbol.(xnames))

    diag = Dict{Symbol, Any}(
        :inference_mode => inference_mode,
        :seed_used => bayes_seed,
        :sigma2_known => bayes_sigma2_known,
        :sigma2_posterior_mean => sigma2_val,
        :prior_scale => bayes_prior_scale,
        :alpha_n => bayes_sigma2_known ? 0.0 : (bayes_ig_alpha + n / 2),
        :beta_n => bayes_sigma2_known ? 0.0 : (bayes_ig_beta + (dot(y - X * μ_n, y - X * μ_n) + dot(μ_n, prior_prec * μ_n)) / 2),
        :Sigma_n => Σ_n,
        :post_prec => post_prec,
    )

    warnings = MetricaBase.ModelWarning[]
    if n < 20
        push!(warnings, MetricaBase.ModelWarning(:small_sample, "样本量偏小",
            "n=$n，后验分布可能受先验主导。", "建议增加观测或检查先验设置。", MetricaBase.info))
    end

    return BayesFitResult(
        formula, μ_n, post_sd, ci_lower, ci_upper, coef_names,
        inference_mode, "normal_independent",
        bayes_sigma2_known, sigma2_val,
        bayes_sigma2_known ? log_ml : nothing,
        n, p, bayes_seed, diag, warnings,
    )
end
