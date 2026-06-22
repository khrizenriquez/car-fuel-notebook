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

Current verified core line coverage: `94.21%`.

Run the full local quality gate:

```bash
Scripts/verify_local.sh
```

`Scripts/verify_local.sh` selects an available iPhone simulator dynamically, preferring `iPhone Air` when installed.

Run the publish safety preflight before pushing to a remote:

```bash
Scripts/preflight_publish.sh
```

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

Current smoke UI coverage includes creating a vehicle, opening capture, saving a fill-up, saving a snapshot with exact `6.5` fuel spaces through quarter-step correction, switching between multiple vehicles across dashboard/capture/history, editing a fill-up, creating/deleting a monthly manual adjustment, and confirming full Settings reset.

Fuel-level capture supports exact correction with a text field, `0.25` step buttons, and a slider. The canonical stored value remains `spaces remaining`.

OCR prefill coverage uses an injectable text recognizer so parser behavior is tested without depending on real camera/Vision output.

Sanitized OCR fixtures live in `CartrackCore/Tests/CartrackCoreTests/Fixtures/OCR/ocr-fixtures.json`. Add only redacted OCR transcript text there, not private receipt or vehicle photos; see `docs/testing/ocr-fixtures.md`.

Current-tank analytics only use snapshots captured on or after the latest fill-up, so stale fuel-level photos from the previous tank cannot override a fresh full-tank reading.

Core analytics and smoke UI coverage verify that monthly summaries, manual monthly adjustments, current tank status, tank cycles, dashboard filtering, capture vehicle selection, and history filtering stay separated by vehicle when more than one car has data.

Event location updates preserve an existing saved coordinate when editing without a fresh location reading, preventing accidental loss of captured context.

Reminder unit coverage verifies inactivity scheduling, cancellation when disabled, and reset after a new capture without touching real notification state.

Event and vehicle deletion are explicit in app data semantics: deleting a fill-up, snapshot, or vehicle also removes owned image asset records and local evidence image files. Missing image files are treated as already-cleaned no-ops, while real file removal errors propagate to the UI.

Vehicle and history row deletion now require explicit confirmation from the UI and surface deletion errors instead of silently ignoring them.

Vehicle and monthly adjustment forms surface persistence errors and only dismiss after a successful save or delete.

Full Settings reset is covered by integration tests that verify domain records, image asset records, and local image files are removed. The Settings reset flow also cancels pending inactivity reminders after the local reset succeeds.

## GitHub Actions
The repository includes a CI workflow for GitHub-hosted `macos-26` runners:

- `Core Coverage`: runs `Scripts/check_core_coverage.sh 90`.
- `iPhone App Tests`: selects an available iPhone simulator and runs the app, integration, and UI tests with code coverage.

The workflow is ready to run after pushing the repository to GitHub. It intentionally avoids signing, secrets, distribution certificates, and cloud credentials.

First-time private GitHub publishing steps are documented in `docs/release/private-github-publish.md`.

## Current V1 Focus
- Continue adding sanitized OCR transcript fixtures from real photos/invoices as they become available.
- Push the initialized local git repository to a private remote when ready, using `Scripts/preflight_publish.sh --require-remote` after adding `origin`.
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
