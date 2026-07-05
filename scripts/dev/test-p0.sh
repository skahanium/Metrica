#!/usr/bin/env bash
# P0 质量门禁：本地发 PR / 合并前建议全量跑。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "=== P0: model_type / params 对齐 ==="
julia scripts/check_model_type_alignment.jl

echo "=== P0: Julia 包 Pkg.test()（18 个）==="
while IFS= read -r pkg; do
  name="$(basename "$pkg")"
  echo "--- ${name} ---"
  julia --project="$pkg" -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
done < <(find packages -maxdepth 1 -type d -name '*.jl' | sort)

echo "=== P0: Rust Runtime ==="
julia --project=packages/MetricaRuntime.jl -e 'using Pkg; Pkg.instantiate()'
cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml
# 集成测试共享 Julia 子进程，须串行避免 HTTP/tokio 用例争用。
cargo test --test vertical_slice --manifest-path runtime/metrica-runtime/Cargo.toml -- --test-threads=1

echo "=== P0: App ==="
(
  cd apps/metrica-desktop
  npm ci
  npm test
)

echo "✅ P0 gate passed"
