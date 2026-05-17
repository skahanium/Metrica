using Dates
using CSV
using DataFrames
using MetricaBase
using MetricaDiscrete
using MetricaGMM
using MetricaLinear
using MetricaSpatial

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULTS_DIR = joinpath(@__DIR__, "results")

function timed_median(f; repetitions::Int=5)
    times = Float64[]
    for _ in 1:repetitions
        elapsed = @elapsed f()
        push!(times, elapsed)
    end
    return sort(times)[cld(length(times), 2)]
end

function run_ols()
    data_path = joinpath(ROOT, "datasets", "golden", "linear_ols.csv")
    result = MetricaBase.fit(OLSModel, "y ~ x1 + x2", data_path)
    result isa OLSFitResult || error("OLS benchmark failed: $(result)")
    return MetricaBase.glance(result).nobs
end

function run_iv()
    data_path = joinpath(ROOT, "datasets", "demo", "gmm_linear_demo.csv")
    result = MetricaBase.fit(
        IVModel,
        "y ~ x1 + x2",
        data_path;
        instruments = ["z1", "z2"],
        endog = ["x1"],
    )
    result isa IVFitResult || error("IV benchmark failed: $(result)")
    return MetricaBase.glance(result).nobs
end

function run_logit()
    df = DataFrame(
        y = [0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1],
        x1 = [-2.0, -1.5, -1.0, -0.4, 0.0, 0.5, 0.8, 1.1, 1.6, 2.0, 2.4, 2.8],
        x2 = [1.0, 0.7, -0.6, 1.2, -0.2, 0.5, 1.5, -0.8, 0.3, -1.1, 1.8, -0.4],
    )
    result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)
    result isa LogitFitResult || error("Logit benchmark failed: $(result)")
    return MetricaBase.glance(result).nobs
end

function run_gmm()
    data_path = joinpath(ROOT, "datasets", "demo", "gmm_linear_demo.csv")
    result = MetricaBase.fit(
        GMMLinearModel,
        "y ~ x1 + x2",
        data_path;
        instruments = ["z1", "z2"],
        endog = ["x1"],
        gmm_weight = "two_step",
    )
    result isa GMMLinearFitResult || error("GMM benchmark failed: $(result)")
    return MetricaBase.glance(result).nobs
end

function run_spatial_lag()
    data_path = joinpath(ROOT, "datasets", "demo", "spatial_demo.csv")
    weights_path = joinpath(ROOT, "datasets", "demo", "spatial_demo_W.csv")
    df = CSV.read(data_path, DataFrame)
    spec = Dict{String, Any}(
        "spatial_weights_path" => weights_path,
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
        "vcov" => "classical",
    )
    result = fit_spatial("spatial_lag", "y ~ x1", df, spec, ROOT)
    result isa SpatialFitResult || error("Spatial lag benchmark failed: $(result)")
    return MetricaBase.glance(result).nobs
end

function write_report(rows)
    mkpath(RESULTS_DIR)
    output = joinpath(RESULTS_DIR, "core-benchmarks.md")
    open(output, "w") do io
        println(io, "# Core Benchmarks")
        println(io)
        println(io, "- Generated: $(Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS"))")
        println(io, "- Julia: $(VERSION)")
        println(io, "- Command: `julia --project=packages/MetricaRuntime.jl benchmarks/run_core_benchmarks.jl`")
        println(io)
        println(io, "| Case | Status | Median seconds | N | Notes |")
        println(io, "|---|---:|---:|---:|---|")
        for row in rows
            println(io, "| $(row.case) | $(row.status) | $(row.seconds) | $(row.nobs) | $(row.notes) |")
        end
    end
    return output
end

const CASES = [
    (case = "OLS", runner = run_ols, notes = "datasets/golden/linear_ols.csv"),
    (case = "IV", runner = run_iv, notes = "datasets/demo/gmm_linear_demo.csv"),
    (case = "Logit", runner = run_logit, notes = "deterministic in-script DataFrame"),
    (case = "GMM", runner = run_gmm, notes = "datasets/demo/gmm_linear_demo.csv"),
    (case = "Spatial lag", runner = run_spatial_lag, notes = "datasets/demo/spatial_demo.csv"),
]

rows = [
    (
        case = item.case,
        status = "covered",
        seconds = round(timed_median(item.runner); sigdigits=4),
        nobs = item.runner(),
        notes = item.notes,
    )
    for item in CASES
]

report = write_report(rows)
println("Wrote benchmark report: $(report)")
