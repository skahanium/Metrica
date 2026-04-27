using Pkg

const ROOT = dirname(dirname(@__FILE__))
const LINEAR_PROJECT = joinpath(ROOT, "packages", "MetricaLinear.jl")
Pkg.activate(LINEAR_PROJECT)

using JSON3
using MetricaLinear

function usage()
    println("用法：julia /Users/skahanium/Metrica/scripts/run_minimal_ols.jl <csv_path> <formula>")
    println("示例：julia /Users/skahanium/Metrica/scripts/run_minimal_ols.jl /Users/skahanium/Metrica/apps/metrica-desktop/data/demo.csv \"y ~ x1 + x2\"")
end

if length(ARGS) < 2
    usage()
    exit(1)
end

dataset_path = ARGS[1]
formula = ARGS[2]
result = fit_ols_file(dataset_path, formula)
payload = result_to_payload(result)

JSON3.pretty(stdout, payload)
println()
