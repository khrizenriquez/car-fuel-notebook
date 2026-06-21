# Cartrack

Cartrack is a local-first iPhone fuel logbook for tracking real fuel usage with invoice, odometer, and fuel-level evidence.

## Architecture
- `Cartrack/`: iPhone app shell, SwiftUI screens, capture services, image storage, location, reminders, and reset flows.
- `CartrackCore/`: domain module with SwiftData models, unit conversion, OCR text parsing, fuel-level rules, and analytics.
- `CartrackCore/Tests/`: strict unit tests for the domain logic.
- `docs/adr/`: architecture decision records.
- `.github/workflows/ios-ci.yml`: GitHub Actions quality gate for core coverage and iPhone app tests.

The app target compiles the shared core sources directly so the iOS app and Swift package tests exercise the same domain code.

## Test Commands
Run fast unit tests with coverage:

```bash
Scripts/check_core_coverage.sh 90
```

Run the same tests without enforcing coverage:

```bash
swift test --enable-code-coverage
```

Current verified core line coverage: `93.75%`.

Run the full local quality gate:

```bash
Scripts/verify_local.sh
```

`Scripts/verify_local.sh` selects an available iPhone simulator dynamically, preferring `iPhone Air` when installed.

## iOS Verification
The iOS app typechecks against the installed iPhoneOS SDK with:

```bash
swiftc -typecheck -target arm64-apple-ios17.0 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk $(find CartrackCore/Sources/CartrackCore Cartrack -name '*.swift' | sort)
```

Run the full iOS app, integration, and UI test suite on the selected simulator target:

```bash
destination="$(Scripts/select_ios_simulator.sh)"
xcodebuild -project Cartrack.xcodeproj -scheme Cartrack -destination "$destination" -enableCodeCoverage YES test
```

Latest local result: `TEST SUCCEEDED`.

Current smoke UI coverage includes creating a vehicle, opening capture, saving a fill-up, saving a snapshot with exact `6.5` fuel spaces through quarter-step correction, editing a fill-up, creating/deleting a monthly manual adjustment, and confirming full Settings reset.

Fuel-level capture supports exact correction with a text field, `0.25` step buttons, and a slider. The canonical stored value remains `spaces remaining`.

Vehicle deletion is explicit in app data semantics: deleting a vehicle also removes its fill-ups, snapshots, monthly manual adjustments, image asset records, and owned image files.

## GitHub Actions
The repository includes a CI workflow for GitHub-hosted `macos-26` runners:

- `Core Coverage`: runs `Scripts/check_core_coverage.sh 90`.
- `iPhone App Tests`: selects an available iPhone simulator and runs the app, integration, and UI tests with code coverage.

The workflow is ready to run after pushing the repository to GitHub. It intentionally avoids signing, secrets, distribution certificates, and cloud credentials.

## Current V1 Focus
- Continue adding OCR fixtures from real photos/invoices as they become available.
- Push the initialized local git repository to a private remote when ready.
- Review the first GitHub Actions run after pushing and adjust only if the hosted runner image differs from the local Xcode environment.
- Keep improving dashboard insights after real driving data accumulates.

## Security Notes
- No cloud sync or backend exists in v1.
- No secrets, API keys, tokens, or private credentials are required by the codebase.
- Captured images are stored locally under application support.
- Local image files use iOS file protection where available.
- Build outputs, coverage artifacts, user Xcode state, and SwiftPM build directories are ignored by git.
- Local database files, capture-export folders, and common `.env` files are ignored by git.
- See `SECURITY.md` before publishing or attaching real evidence images to issues.
