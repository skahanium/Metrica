#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local version
    if version="$("$name" --version 2>&1 | head -n 1)"; then
      printf "[ok] %s: %s\n" "$name" "$version"
    else
      printf "[error] %s exists but version check failed: %s\n" "$name" "$version"
      status=1
    fi
  else
    printf "[missing] %s\n" "$name"
    status=1
  fi
}

check_path() {
  local path="$1"
  if [[ -e "$ROOT/$path" ]]; then
    printf "[ok] %s\n" "$path"
  else
    printf "[missing] %s\n" "$path"
    status=1
  fi
}

echo "Metrica developer environment"
echo "root: $ROOT"
echo

check_command julia
check_command cargo
check_command node
check_command npm
echo

check_path packages/MetricaBase.jl/Project.toml
check_path packages/MetricaLinear.jl/Project.toml
check_path packages/MetricaRuntime.jl/Project.toml
check_path runtime/metrica-runtime/Cargo.toml
check_path apps/metrica-desktop/package.json
check_path apps/metrica-desktop/package-lock.json
check_path docs/quality/package-status.md

exit "$status"
