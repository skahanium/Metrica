#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/dev/test-package.sh <PackageName.jl>" >&2
  echo "Example: bash scripts/dev/test-package.sh MetricaLinear.jl" >&2
  exit 2
fi

pkg="$1"
pkg_path="$ROOT/packages/$pkg"

if [[ ! -d "$pkg_path" || ! -f "$pkg_path/Project.toml" ]]; then
  echo "Package not found: packages/$pkg" >&2
  exit 2
fi

julia --project="$pkg_path" -e 'using Pkg; Pkg.test()'
