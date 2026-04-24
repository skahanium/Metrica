# 在仓库根目录激活环境，并以 develop 方式链接三个本地包后解析、实例化与预编译。
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
println("Julia 环境已就绪，根目录：", ROOT)
