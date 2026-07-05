#!/usr/bin/env bash
# 手动验证输入数据快路径：确认当前不再保留未经交叉验证的 JSON golden，
# 并检查 datasets/golden 下 CSV 可被标准 CSV 解析器读取。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "=== Manual validation inputs: no JSON expectations ==="
if find datasets/golden -maxdepth 1 -name '*.json' -print -quit | grep -q .; then
  echo "Unexpected JSON expectation files remain in datasets/golden." >&2
  find datasets/golden -maxdepth 1 -name '*.json' -print >&2
  exit 1
fi

echo "=== Manual validation inputs: CSV parse check ==="
python3 - <<'PY'
import csv
import glob
import sys

files = sorted(glob.glob("datasets/golden/*.csv"))
if not files:
    print("No CSV inputs found in datasets/golden.", file=sys.stderr)
    sys.exit(1)

for path in files:
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
    if not reader.fieldnames:
        print(f"{path}: missing header", file=sys.stderr)
        sys.exit(1)
    if not rows:
        print(f"{path}: no data rows", file=sys.stderr)
        sys.exit(1)
    print(f"{path}: {len(rows)} rows")
PY

echo "Manual validation input check passed"
