.PHONY: test test-julia test-julia-core test-rust test-app check lint clean

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

# Rust 编译检查 + 测试
test-rust:
	cargo check --manifest-path runtime/metrica-runtime/Cargo.toml
	cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml

# App 测试
test-app:
	cd apps/metrica-desktop && npm test

# Rust 编译检查
check-rust:
	cargo check --manifest-path runtime/metrica-runtime/Cargo.toml

# Rust lint
lint-rust:
	cargo clippy --manifest-path runtime/metrica-runtime/Cargo.toml

# App lint
lint-app:
	cd apps/metrica-desktop && npx eslint src-react/

# 全量 lint
lint: lint-rust lint-app

# 清理构建产物
clean:
	rm -rf runtime/metrica-runtime/target
	rm -rf apps/metrica-desktop/node_modules/.vite
