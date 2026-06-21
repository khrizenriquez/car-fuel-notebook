#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./Scripts/check_core_coverage.sh 90

destination="$(./Scripts/select_ios_simulator.sh)"
echo "Using simulator destination: ${destination}"

xcodebuild \
  -project Cartrack.xcodeproj \
  -scheme Cartrack \
  -destination "${destination}" \
  -enableCodeCoverage YES \
  test
