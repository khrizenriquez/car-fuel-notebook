#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST="CartrackTests/Fixtures/private-image-scenarios.json"
[[ -f "$MANIFEST" ]] || {
  echo "Missing private fixture manifest: $MANIFEST" >&2
  exit 1
}

destination="${CARTRACK_PRIVATE_DESTINATION:-$(./Scripts/select_ios_simulator.sh)}"
echo "Using private fixture destination: ${destination}"

CARTRACK_REQUIRE_PRIVATE_FIXTURES=1 xcodebuild \
  -project Cartrack.xcodeproj \
  -scheme Cartrack \
  -destination "${destination}" \
  -only-testing:CartrackTests/PrivateImageScenarioManifestTests \
  -only-testing:CartrackTests/LocalExampleImageOCRTests \
  CODE_SIGNING_ALLOWED=NO \
  test
