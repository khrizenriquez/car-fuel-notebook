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

CARTRACK_REQUIRE_PRIVATE_FIXTURES=1 xcodebuild \
  -project Cartrack.xcodeproj \
  -scheme Cartrack \
  -destination "${destination}" \
  -parallel-testing-enabled NO \
  -only-testing:CartrackTests/PrivateImageScenarioManifestTests \
  -only-testing:CartrackTests/LocalExampleImageOCRTests \
  CODE_SIGNING_ALLOWED=NO \
  test

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
