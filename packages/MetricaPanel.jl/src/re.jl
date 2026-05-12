# === 随机效应估计器（Mundlak/CRE 参数化）======================================
# `:re` 方法实际实现为 Mundlak/CRE：在 pooled 回归中加入组均值，
# 控制个体效应与解释变量的相关性。
#
# **这不是 Swamy-Arora、Wallace-Hussain 等传统 GLS 随机效应估计量。**
#
# 向后兼容：`fit_panel(...; method=:re)` 仍可用，但结果语义为 Mundlak/CRE。
# 推荐使用 `method=:cre` 以明确语义。

"""
    fit_re(panel_data, formula)

Mundlak/CRE 方法的向后兼容入口。委托给 `fit_crea`，结果 `method` 字段为 `:re`。

**语义说明：** 此实现不是传统 GLS 随机效应（Swamy-Arora 等），
而是 Mundlak/Correlated Random Effects 方法。`method=:re` 仅为向后兼容保留，
推荐使用 `method=:cre`。

另见: [`fit_crea`](@ref)
"""
function fit_re(panel_data::MetricaBase.PanelData, formula::String)
    return fit_crea(panel_data, formula; method_override=:re)
end
