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
    files = json.load(handle)["data"][0]["files"]

source_files = [
    item for item in files
    if "/CartrackCore/Sources/CartrackCore/" in item["filename"]
]
if not source_files:
    raise SystemExit("No CartrackCore source files found in coverage data")
covered = sum(item["summary"]["lines"]["covered"] for item in source_files)
count = sum(item["summary"]["lines"]["count"] for item in source_files)
if count == 0:
    raise SystemExit("CartrackCore source coverage has no executable lines")
print(covered / count * 100)
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
