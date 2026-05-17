#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
make test-julia-core
cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml

cd "$ROOT/apps/metrica-desktop"
npm test
