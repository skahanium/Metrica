# 内部：将独立参考实现的 expected 段与已提交 golden JSON 按容差比对。
using JSON3

"""
    golden_tolerance_dict_from_spec(spec) -> Dict{String, Float64}
"""
function golden_tolerance_dict_from_spec(spec)
    return Dict(String(row.name) => Float64(row.atol) for row in spec.tolerances)
end

function _atol_for(tol::Dict{String, Float64}, category::AbstractString, default::Float64=1.0e-8)
    return get(tol, String(category), default)
end

function _float_close(a, b, atol::Real)
    return isapprox(Float64(a), Float64(b); atol = Float64(atol), rtol = 0.0)
end

"""
    compare_expected_values!(committed, fresh; tol)

比对 `expected` 子树（glance、metrics、tidy、first_stage 等），浮点按 `tol` 类别容差。
"""
function compare_expected_values!(
    committed::AbstractDict,
    fresh::AbstractDict;
    tol::Dict{String, Float64},
)
    for key in ("glance", "first_stage")
        haskey(committed, key) || continue
        haskey(fresh, key) || error("fresh expected missing key: $key")
        if key == "glance"
            cg, fg = committed["glance"], fresh["glance"]
            for field in ("model", "nobs", "dof")
                haskey(cg, field) || continue
                cv, fv = cg[field], fg[field]
                if field in ("nobs", "dof")
                    Int(cv) == Int(fv) ||
                        error("glance.$field mismatch: committed=$(cv) fresh=$(fv)")
                else
                    String(cv) == String(fv) ||
                        error("glance.model mismatch: committed=$(cv) fresh=$(fv)")
                end
            end
        elseif key == "first_stage"
            cfs_root = committed["first_stage"]
            ffs_root = fresh["first_stage"]
            for var in keys(cfs_root)
                vname = String(var)
                haskey(ffs_root, vname) || haskey(ffs_root, var) ||
                    error("fresh first_stage missing $vname")
                cfs = haskey(cfs_root, vname) ? cfs_root[vname] : cfs_root[var]
                ffs = haskey(ffs_root, vname) ? ffs_root[vname] : ffs_root[var]
                for metric in keys(cfs)
                    mname = String(metric)
                    fv = haskey(ffs, mname) ? ffs[mname] : ffs[Symbol(mname)]
                    cv = haskey(cfs, mname) ? cfs[mname] : cfs[Symbol(mname)]
                    _float_close(cv, fv, _atol_for(tol, "metric")) ||
                        error("first_stage.$vname.$mname mismatch")
                end
            end
        end
    end

    if haskey(committed, "metrics")
        haskey(fresh, "metrics") || error("fresh expected missing metrics")
        cm = Dict(String(m["name"]) => Float64(m["value"]) for m in committed["metrics"])
        fm = Dict(String(m["name"]) => Float64(m["value"]) for m in fresh["metrics"])
        for name in keys(cm)
            haskey(fm, name) || error("fresh metrics missing $name")
            _float_close(cm[name], fm[name], _atol_for(tol, "metric")) ||
                error("metric $name mismatch: committed=$(cm[name]) fresh=$(fm[name])")
        end
    end

    if haskey(committed, "tidy")
        haskey(fresh, "tidy") || error("fresh expected missing tidy")
        ct = Dict(String(r["name"]) => r for r in committed["tidy"])
        ft = Dict(String(r["name"]) => r for r in fresh["tidy"])
        for name in keys(ct)
            haskey(ft, name) || error("fresh tidy missing $name")
            cr, fr = ct[name], ft[name]
            for field in ("estimate", "stderror", "statistic")
                haskey(cr, field) || continue
                haskey(fr, field) || error("fresh tidy.$name missing $field")
                cat = field == "estimate" ? "coefficient" : field
                _float_close(cr[field], fr[field], _atol_for(tol, cat)) ||
                    error("tidy.$name.$field mismatch: committed=$(cr[field]) fresh=$(fr[field])")
            end
        end
    end
    return nothing
end

function compare_spec_expected_to_fresh!(spec, fresh_expected::AbstractDict)
    tol = golden_tolerance_dict_from_spec(spec)
    committed = spec.expected
    compare_expected_values!(committed, fresh_expected; tol = tol)
end
