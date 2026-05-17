.PHONY: test test-julia test-rust test-app check lint clean

# 全栈测试
test:
	@echo "=== Julia Core ===" && $(MAKE) test-julia
	@echo "=== Rust Runtime ===" && $(MAKE) test-rust
	@echo "=== App ===" && $(MAKE) test-app

# Julia 包测试（全部 20 个包）
test-julia:
	@for pkg in packages/*.jl; do \
		echo "Testing $$(basename $$pkg)..."; \
		julia --project="$$pkg" -e 'using Pkg; Pkg.test()' 2>&1 | tail -1; \
	done

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
