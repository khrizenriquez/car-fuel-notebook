#!/usr/bin/env bash
set -euo pipefail

threshold="${1:-90}"
swift test --enable-code-coverage

coverage_json="$(swift test --show-codecov-path)"
coverage_percent="$(
  python3 - "$coverage_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    totals = json.load(handle)["data"][0]["totals"]["lines"]

print(totals["percent"])
PY
)"

python3 - "$coverage_percent" "$threshold" <<'PY'
import sys
actual = float(sys.argv[1])
threshold = float(sys.argv[2])
print(f"CartrackCore line coverage: {actual:.2f}% (threshold {threshold:.2f}%)")
if actual + 1e-9 < threshold:
    raise SystemExit(1)
PY
