using Pkg
const ROOT = dirname(dirname(@__FILE__))
Pkg.activate(ROOT)
specs = [
    PackageSpec(path=joinpath(ROOT, "packages", "MetricaBase.jl")),
    PackageSpec(path=joinpath(ROOT, "packages", "MetricaLinear.jl")),
    PackageSpec(path=joinpath(ROOT, "packages", "MetricaOutput.jl")),
]
Pkg.develop(specs)
Pkg.resolve()
Pkg.instantiate()
Pkg.precompile()
println("Julia env ready at: ", ROOT)
