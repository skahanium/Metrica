# Metrica 开发环境设置

## 前置要求

- Julia 1.12+
- Rust toolchain (rustup)
- Node.js 20+

## 初始化

### 1. 检查本地环境

```bash
bash scripts/dev/doctor.sh
```

### 2. Julia 包

当前仓库包含 18 个 `packages/*.jl` 包。首次开发不需要一次实例化全部包；按你修改的包运行：

```bash
julia --project=packages/MetricaBase.jl -e 'using Pkg; Pkg.instantiate()'
julia --project=packages/MetricaLinear.jl -e 'using Pkg; Pkg.instantiate()'
```

聚合环境：

```bash
julia --project=packages/MetricaRuntime.jl -e 'using Pkg; Pkg.instantiate()'
```

### 3. Runtime

```bash
cargo build --manifest-path runtime/metrica-runtime/Cargo.toml
```

### 4. 桌面应用

```bash
cd apps/metrica-desktop && npm ci && npm run dev
```

## 运行测试

```bash
# Julia
make test-julia-core
bash scripts/dev/test-package.sh MetricaLinear.jl

# Rust
cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml

# 前端
cd apps/metrica-desktop && npm test
```

轻量核心验证：

```bash
bash scripts/dev/test-core.sh
```
