# === 共享诊断函数 ============================================================
# 本文件包含 julia_bridge_entry.jl 和 julia_daemon.jl 共用的诊断函数。
# ==============================================================================

function diagnostics_to_dict(result)
    bp = breusch_pagan(result)
    white = white_test(result)
    dw = durbin_watson(result)
    bg = breusch_godfrey(result; p=2)
    reset = reset_test(result)
    jb = jarque_bera(result)

    return Dict(
        "vif" => [
            Dict("name" => row.name, "vif" => row.vif)
            for row in vif(result)
        ],
        "breusch_pagan" => Dict(
            "statistic" => bp.statistic,
            "pvalue" => bp.pvalue,
            "dof" => bp.dof,
        ),
        "white_test" => Dict(
            "statistic" => white.statistic,
            "pvalue" => white.pvalue,
            "dof" => white.dof,
        ),
        "durbin_watson" => Dict(
            "statistic" => dw.statistic,
            "pvalue" => dw.pvalue,
            "warnings" => dw.warnings,
        ),
        "breusch_godfrey" => Dict(
            "statistic" => bg.statistic,
            "pvalue" => bg.pvalue,
            "dof" => bg.dof,
        ),
        "reset_test" => Dict(
            "statistic" => reset.statistic,
            "pvalue" => reset.pvalue,
            "df_num" => reset.df_num,
            "df_den" => reset.df_den,
        ),
        "jarque_bera" => Dict(
            "statistic" => jb.statistic,
            "pvalue" => jb.pvalue,
            "skewness" => jb.skewness,
            "kurtosis" => jb.kurtosis,
        ),
    )
end
