#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
make test-julia-core
julia scripts/check_model_type_alignment.jl
julia --project=packages/MetricaRuntime.jl -e 'using Pkg; Pkg.instantiate()'
cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml

cd "$ROOT/apps/metrica-desktop"
npm test
