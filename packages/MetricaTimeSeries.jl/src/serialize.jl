# serialize.jl - 序列化模块
# 统一序列化入口，各模型类型的 result_to_payload 已在各自模块中实现

# 本文件确保所有序列化函数可从 MetricaTimeSeries 模块统一访问
# 实际实现位于：
#   - unitroot.jl: result_to_payload(::UnitRootFitResult)
#   - arima.jl: result_to_payload(::ARIMAFitResult)
#   - var.jl: result_to_payload(::VARFitResult)
#   - cointegration.jl: result_to_payload(::CointegrationFitResult)
