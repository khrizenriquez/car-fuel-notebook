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
ocr_udid="${destination#*id=}"
ui_udid=""

cleanup_private_verification() {
  xcrun simctl spawn "${ocr_udid}" launchctl unsetenv CARTRACK_REQUIRE_PRIVATE_FIXTURES >/dev/null 2>&1 || true
  xcrun simctl shutdown "${ocr_udid}" >/dev/null 2>&1 || true
  if [[ -n "${ui_udid}" ]]; then
    xcrun simctl spawn "${ui_udid}" launchctl unsetenv CARTRACK_RUN_PRIVATE_PHOTOS_UI >/dev/null 2>&1 || true
    xcrun simctl shutdown "${ui_udid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_private_verification EXIT

xcrun simctl boot "${ocr_udid}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${ocr_udid}" -b
xcrun simctl spawn "${ocr_udid}" launchctl setenv CARTRACK_REQUIRE_PRIVATE_FIXTURES 1

run_private_test() {
  local test_identifier="$1"
  CARTRACK_REQUIRE_PRIVATE_FIXTURES=1 \
    CARTRACK_PRIVATE_SCENARIO_ID="${CARTRACK_PRIVATE_SCENARIO_ID:-}" \
    xcodebuild \
    -project Cartrack.xcodeproj \
    -scheme Cartrack \
    -destination "${destination}" \
    -parallel-testing-enabled NO \
    "-only-testing:${test_identifier}" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

# Vision keeps image resources alive for the life of a test host. Running the
# real-photo matrix scenario-by-scenario gives each high-resolution capture a
# clean host, while still failing this script on the first incorrect output.
xcrun simctl spawn "${ocr_udid}" launchctl unsetenv CARTRACK_PRIVATE_SCENARIO_ID >/dev/null 2>&1 || true
run_private_test "CartrackTests/PrivateImageScenarioManifestTests"
run_private_test "CartrackTests/LocalExampleImageOCRTests/testPrivateManifestCoversEveryAvailableImage"

while IFS= read -r scenario_id; do
  export CARTRACK_PRIVATE_SCENARIO_ID="${scenario_id}"
  xcrun simctl spawn "${ocr_udid}" launchctl setenv CARTRACK_PRIVATE_SCENARIO_ID "${scenario_id}"
  run_private_test "CartrackTests/LocalExampleImageOCRTests/testAllPrivateImageScenariosMatchExpectedOCR"
  run_private_test "CartrackTests/LocalExampleImageOCRTests/testPrivateImagePreparationKeepsDeclaredEvidenceAndVariantsLocal"
  case "${scenario_id}" in
    z4-2026-07-23-1941|z4-2026-07-24-1351|z4-2026-07-24-2255)
      run_private_test "CartrackTests/LocalExampleImageOCRTests/testPriorityDigitalScenariosDoNotDependOnExactFileSignature"
      ;;
  esac
done < <(jq -r '.scenarios[] | select(.excluded | not) | .id' "${MANIFEST}")

unset CARTRACK_PRIVATE_SCENARIO_ID
xcrun simctl spawn "${ocr_udid}" launchctl unsetenv CARTRACK_PRIVATE_SCENARIO_ID >/dev/null 2>&1 || true
run_private_test "CartrackTests/LocalExampleImageOCRTests/testPrivateOriginalOdometerRemainsLegibleAfterLocalOptimization"
run_private_test "CartrackTests/LocalExampleImageOCRTests/testPrivateSnapshotWorkflowPrefillsFromRealPhotos"
run_private_test "CartrackTests/LocalExampleImageOCRTests/testPrivateFillUpWorkflowPrefillsFromRealPhotos"

if [[ "${CARTRACK_RUN_PRIVATE_PHOTOS_UI:-0}" != "1" ]]; then
  exit 0
fi

# The Photos picker requires its fixture in the simulator's photo library. Keep
# this opt-in so the normal private OCR suite remains headless and lightweight.
# Shut down the OCR device before booting the dedicated Photos fixture device.
xcrun simctl shutdown "${ocr_udid}" >/dev/null 2>&1 || true
ui_destination="$(
  CARTRACK_PRIVATE_SCENARIO_ID="z4-2026-07-24-2255" \
  CARTRACK_PRIVATE_MEDIA_ROLE="odometerImage" \
  CARTRACK_PRIVATE_SIMULATOR_UDID="${CARTRACK_PRIVATE_SIMULATOR_UDID:-}" \
  ./Scripts/prepare_private_fixture_simulator.sh --reset | tail -n 1
)"
ui_udid="${ui_destination#*id=}"

echo "Running private Photos UI test on: ${ui_destination}"
xcrun simctl spawn "${ui_udid}" launchctl setenv CARTRACK_RUN_PRIVATE_PHOTOS_UI 1

xcodebuild \
  -project Cartrack.xcodeproj \
  -scheme Cartrack \
  -destination "${ui_destination}" \
  -parallel-testing-enabled NO \
  -only-testing:CartrackUITests/CartrackSmokeUITests/testPrivatePhotoSnapshotPrefillsAndSavesExpectedReading \
  CODE_SIGNING_ALLOWED=NO \
  test
