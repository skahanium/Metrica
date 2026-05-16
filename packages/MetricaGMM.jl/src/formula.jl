# === 公式解析（与 MetricaLinear 口径对齐，避免对 MetricaLinear 的依赖）==========

function parse_formula_term(formula::AbstractString)
    expr = try
        Meta.parse("@formula($(formula))")
    catch err
        return MetricaBase.ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "无法解析公式字符串：$(sprint(showerror, err))",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end

    try
        return Core.eval(@__MODULE__, expr)
    catch err
        return MetricaBase.ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "无法构造公式对象：$(sprint(showerror, err))",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end
end

function collect_term_symbols(term)
    symbols = Symbol[]
    append_term_symbols!(symbols, term)
    return unique(symbols)
end

function append_term_symbols!(symbols::Vector{Symbol}, term)
    if term isa StatsModels.Term
        push!(symbols, term.sym)
        return symbols
    end

    if term isa Tuple
        for item in term
            append_term_symbols!(symbols, item)
        end
        return symbols
    end

    if hasproperty(term, :lhs)
        append_term_symbols!(symbols, getproperty(term, :lhs))
    end

    if hasproperty(term, :rhs)
        append_term_symbols!(symbols, getproperty(term, :rhs))
    end

    return symbols
end

function build_rows_dropped_warning(dropped_rows::Int)
    return MetricaBase.ModelWarning(
        :rows_dropped,
        "缺失值删样",
        "因模型相关列存在缺失值，已删除 $(dropped_rows) 行观测。",
        "请检查模型变量中的缺失分布。",
        MetricaBase.warning,
    )
end
