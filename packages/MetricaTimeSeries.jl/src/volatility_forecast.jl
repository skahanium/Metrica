# volatility_forecast.jl — 波动率预测 + VaR + ES + Kupiec 回测

function forecast_garch(result::GARCHFitResult; steps::Int=10)
    T = length(result.conditional_variance)
    h_T = result.conditional_variance[T]
    e_T = result.residuals[T]
    ω = result.omega
    α1 = result.alpha[1]
    persistence = result.persistence
    β1 = length(result.beta) > 0 ? result.beta[1] : 0.0

    h_forecast = Vector{Float64}(undef, steps)
    h_forecast[1] = ω + α1 * e_T^2 + β1 * h_T
    for s in 2:steps
        h_forecast[s] = ω + persistence * h_forecast[s-1]
    end
    return h_forecast
end

function forecast_arch(result::ARCHFitResult; steps::Int=10)
    T = length(result.conditional_variance)
    h_T = result.conditional_variance[T]
    ω = result.omega
    persistence = result.persistence
    q = result.arch_order
    α = result.alpha
    e = result.residuals

    h_forecast = Vector{Float64}(undef, steps)
    h_forecast[1] = ω
    for i in 1:min(q, T)
        h_forecast[1] += α[i] * e[T+1-i]^2
    end
    for s in 2:steps
        h_forecast[s] = ω
        if s <= q
            h_forecast[s] += sum(α[s:end] .* e[end:-1:end-(q-s)] .^ 2)
        end
        h_forecast[s] += persistence * h_forecast[s-1]
    end
    return h_forecast
end

function compute_var(μ::Float64, σ_forecast::Vector{Float64}, α::Float64)
    z = quantile(Normal(), α)
    return μ .+ σ_forecast .* z  # 负值 ⇔ 损失
end

function compute_es_normal(μ::Float64, σ::Vector{Float64}, α::Float64)
    z = quantile(Normal(), α)
    phi_z = pdf(Normal(), z)
    return μ .+ σ .* (-phi_z / α)
end

function kupiec_test(actual_returns::Vector{Float64}, var_forecast::Vector{Float64}, α::Float64)
    N = length(var_forecast)
    actual = actual_returns[(end-N+1):end]
    hits = actual .< var_forecast
    x = sum(hits)
    ratio = x / N
    if x == 0
        LR = 2 * N * log(1 / (1 - α))
    elseif x == N
        LR = 2 * N * log(1 / α)
    else
        LR = 2 * (x * log(ratio / α) + (N - x) * log((1 - ratio) / (1 - α)))
    end
    pv = 1 - cdf(Chisq(1), abs(LR))
    return Dict{Symbol, Any}(:LR_uc => abs(LR), :pvalue => pv, :expected_hits => N * α, :actual_hits => x, :violation_rate => ratio)
end

function compute_volatility_diagnostics(result::Union{ARCHFitResult, GARCHFitResult, GJRFitResult, EGARCHFitResult};
                                        steps::Int=10, var_alpha::Float64=0.05)
    h_forecast = if result isa GARCHFitResult || result isa GJRFitResult
        forecast_garch(result; steps=steps)
    elseif result isa ARCHFitResult
        forecast_arch(result; steps=steps)
    else
        Vector{Float64}()
    end
    σ_forecast = sqrt.(max.(h_forecast, 1e-18))
    μ = result.mu
    VaR = compute_var(μ, σ_forecast, var_alpha)
    ES = compute_es_normal(μ, σ_forecast, var_alpha)

    diag = Dict{Symbol, Any}(
        :volatility_forecast => h_forecast,
        :var_forecast => VaR,
        :es_forecast => ES,
        :var_alpha => var_alpha,
        :forecast_steps => steps,
    )

    if length(result.original_series) > steps
        kp = kupiec_test(result.original_series, VaR, var_alpha)
        diag[:kupiec_test] = kp
    end

    return diag
end
