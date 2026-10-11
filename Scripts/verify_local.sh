#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./Scripts/check_core_coverage.sh 90

if [[ -n "${CARTRACK_SIMULATOR_UDID:-}" ]]; then
  destination="platform=iOS Simulator,id=${CARTRACK_SIMULATOR_UDID}"
else
  destination="$(./Scripts/select_ios_simulator.sh)"
fi
echo "Using simulator destination: ${destination}"

xcodebuild \
  -project Cartrack.xcodeproj \
  -scheme Cartrack \
  -destination "${destination}" \
  -enableCodeCoverage YES \
  test

if [[ "${CARTRACK_REQUIRE_PRIVATE_FIXTURES:-0}" == "1" ]]; then
  CARTRACK_PRIVATE_DESTINATION="${destination}" \
    ./Scripts/verify_private_image_scenarios.sh
fi
