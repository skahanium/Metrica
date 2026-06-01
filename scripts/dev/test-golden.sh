#!/usr/bin/env bash
# Golden 快路径：标准 JSON schema + 含 golden 测试的包（较 P0 更短）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "=== Golden: JSON schema ==="
julia --project=scripts/golden -e 'using Pkg; Pkg.instantiate()'
julia --project=scripts/golden scripts/golden/check_golden_json.jl

GOLDEN_PACKAGES=(
  MetricaBase.jl
  MetricaLinear.jl
  MetricaDiscrete.jl
  MetricaPanel.jl
  MetricaDuration.jl
  MetricaCausal.jl
  MetricaSystem.jl
  MetricaGMM.jl
  MetricaTimeSeries.jl
)

echo "=== Golden: package tests ==="
for pkg in "${GOLDEN_PACKAGES[@]}"; do
  echo "--- ${pkg} ---"
  julia --project="packages/${pkg}" -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
done

echo "✅ Golden gate passed"
