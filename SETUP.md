# Metrica 开发环境设置

## 前置要求

- Julia 1.10+
- Rust toolchain (rustup)
- Node.js 20+

## 初始化

### 1. Julia 包

```bash
cd packages/MetricaBase.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaDiagnostics.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaLinear.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaPanel.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaOutput.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 2. Runtime

```bash
cd runtime/metrica-runtime && cargo build
```

### 3. 桌面应用

```bash
cd apps/metrica-desktop && npm install && npm run dev
```

## 运行测试

```bash
# Julia
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'

# Rust
cd runtime/metrica-runtime && cargo test

# 前端
cd apps/metrica-desktop && npm test
```
