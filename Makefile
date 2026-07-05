.PHONY: test test-julia test-julia-core test-julia-credibility test-golden test-rust test-app test-p0 check lint clean

# 全栈测试
test:
	@echo "=== Julia Core ===" && $(MAKE) test-julia
	@echo "=== Rust Runtime ===" && $(MAKE) test-rust
	@echo "=== App ===" && $(MAKE) test-app

# Julia 包测试（当前仓库全部 18 个 packages/*.jl 包）
test-julia:
	@status=0; \
	for pkg in packages/*.jl; do \
		echo "Testing $$(basename $$pkg)..."; \
		julia --project="$$pkg" -e 'using Pkg; Pkg.test()' || status=$$?; \
	done; \
	exit $$status

# PR 阻塞 Julia 核心链路
test-julia-core:
	julia --project=packages/MetricaBase.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaLinear.jl -e 'using Pkg; Pkg.test()'

# Rust 编译检查 + 单元测试 + 串行 vertical_slice
test-rust:
	cargo check --manifest-path runtime/metrica-runtime/Cargo.toml
	cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml
	cargo test --test vertical_slice --manifest-path runtime/metrica-runtime/Cargo.toml -- --test-threads=1

# 完整 P0 本地门禁（耗时较长，合并前建议跑）
test-p0:
	bash scripts/dev/test-p0.sh

# 手动验证输入 CSV 检查（当前不保留未经交叉验证的 JSON golden）
test-golden:
	bash scripts/dev/test-golden.sh

# 核心实证链（可信度 P1 本地子集）
test-julia-credibility:
	julia --project=packages/MetricaBase.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaLinear.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaDiscrete.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaPanel.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaCausal.jl -e 'using Pkg; Pkg.test()'
	julia --project=packages/MetricaRuntime.jl -e 'using Pkg; Pkg.instantiate(); Pkg.test()'

test-credibility: test-golden test-julia-credibility test-rust

# App 测试
test-app:
	cd apps/metrica-desktop && npm test

# Rust 编译检查
check-rust:
	cargo check --manifest-path runtime/metrica-runtime/Cargo.toml

# Rust lint
lint-rust:
	cargo clippy --manifest-path runtime/metrica-runtime/Cargo.toml -- -D warnings

# App 类型检查（仓库无 ESLint 配置，使用 npm run build）
lint-app:
	cd apps/metrica-desktop && npm ci && npm run build

# 全量 lint
lint: lint-rust lint-app

# 清理构建产物
clean:
	rm -rf runtime/metrica-runtime/target
	rm -rf apps/metrica-desktop/node_modules/.vite
