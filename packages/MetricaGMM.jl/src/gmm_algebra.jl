# === GMM 数值代数（供 gmm.jl 与 linear_iv_gmm_stack 复用）=======================

function _inv_sym_pd(A::AbstractMatrix{<:Real}, err_code::Symbol, title::String, detail::String, hint::String)
    As = Symmetric(Matrix(Float64.(A)))
    try
        return Matrix(inv(cholesky(As)))
    catch
        try
            return Matrix(inv(As))
        catch err
            return MetricaBase.ModelError(
                err_code,
                title,
                detail * " $(sprint(showerror, err))",
                hint,
            )
        end
    end
end

function _solve_gmm_beta(X::Matrix{Float64}, Z::Matrix{Float64}, y::Vector{Float64}, W::Matrix{Float64})
    ZtX = Z' * X
    Zty = Z' * y
    bread = Symmetric(X' * Z * W * ZtX)
    try
        β = cholesky(bread) \ (X' * Z * W * Zty)
        return β
    catch
        try
            return bread \ (X' * Z * W * Zty)
        catch err
            return MetricaBase.ModelError(
                :singular_gmm_normal,
                "GMM 正规方程奇异",
                "矩阵 X'Z W Z'X 不可逆：$(sprint(showerror, err))",
                "请检查秩条件或改用其他工具变量组合。",
            )
        end
    end
end

function _moment_covariance(Z::Matrix{Float64}, u::Vector{Float64}, n::Int)
    Ω = zeros(Float64, size(Z, 2), size(Z, 2))
    @inbounds for i in 1:n
        zi = view(Z, i, :)
        Ω .+= (zi' * zi) .* (u[i]^2 / n)
    end
    return Ω
end

function _gmm_vcov(X::Matrix{Float64}, Z::Matrix{Float64}, W::Matrix{Float64}, Ω::Matrix{Float64}, n::Int)
    ZtX = Z' * X
    bread = Symmetric(X' * Z * W * ZtX)
    try
        Binv = inv(cholesky(bread))
        meat = (X' * Z * W * Ω * W * ZtX) .* (1.0)  # 已在 Ω 中含 1/n
        V = Symmetric(Binv * meat * Binv)
        scale = n > size(X, 2) ? n / (n - size(X, 2)) : 1.0
        return Matrix(V) .* scale
    catch
        try
            Binv = inv(bread)
            meat = X' * Z * W * Ω * W * ZtX
            scale = n > size(X, 2) ? n / (n - size(X, 2)) : 1.0
            return Symmetric(Binv * meat * Binv) .* scale
        catch err
            return MetricaBase.ModelError(
                :gmm_vcov_failed,
                "GMM 协方差矩阵计算失败",
                "$(sprint(showerror, err))",
                "请检查数据与工具变量设定。",
            )
        end
    end
end
