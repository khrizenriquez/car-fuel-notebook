# Car Fuel Notebook

Car Fuel Notebook is a local-first iPhone app for keeping a real-world fuel log. It is designed for drivers who want to understand how much they spend on fuel, how far they drive, and how efficient each tank really is.

The app was built around a BMW Z4 workflow, but the data model supports multiple vehicles from day one.

## What It Does

- Records fuel fill-ups with invoice, odometer, and fuel-level evidence.
- Records intermediate snapshots with odometer and fuel-level photos.
- Uses on-device OCR to prefill values from readable text.
- Lets the user review and edit all captured values before saving.
- Tracks fuel level as `spaces remaining` on a configurable scale, such as `0` to `8`.
- Shows monthly spending, distance, fuel economy, cost per kilometer, and tank history.
- Stores all v1 data locally on the device.

## Capture Flow

Fill-ups and snapshots use a simple wizard:

1. Add evidence photos.
2. Review OCR-prefilled fields and correct anything that looks wrong.
3. Confirm the summary and save.

OCR works best for text-heavy images such as receipts and digital odometer displays. Analog fuel gauges are kept as evidence, but the fuel level should still be confirmed manually with the app's quarter-step fuel-level control.

## Privacy Model

This project is intentionally local-first.

- No backend.
- No cloud sync.
- No analytics SDK.
- No API keys.
- No third-party credentials.
- No real invoice, odometer, or fuel photos are stored in this repository.

Captured photos and local database records are app data. They should stay on the device and out of GitHub issues, fixtures, commits, and screenshots unless they are fully redacted.

See [SECURITY.md](SECURITY.md) for the repository safety policy.

## Current Status

The iOS app target is currently named `Cartrack` internally. The GitHub project name is `car-fuel-notebook`.

Implemented locally:

- SwiftUI iPhone app.
- SwiftData local persistence.
- Multi-vehicle support.
- Fill-up and snapshot capture wizards.
- On-device OCR service using Apple's Vision framework.
- Manual correction for captured values.
- Fuel-level validation from `0.00` to the vehicle's configured maximum.
- Monthly dashboard, history, vehicle management, reminders, and reset flow.
- Unit, integration, and UI test coverage.

Screenshots will be added later once the first polished app screens are ready.

## Project Structure

- `Cartrack/`: SwiftUI app, screens, capture services, image storage, reminders, reset flow, and app shell.
- `CartrackCore/`: shared domain logic, SwiftData models, OCR parsing, fuel-level rules, unit conversion, and analytics.
- `CartrackCore/Tests/`: strict domain-level unit tests.
- `CartrackTests/`: iOS integration tests.
- `CartrackUITests/`: smoke tests for the main app workflows.
- `Scripts/`: local verification, coverage, simulator selection, and publish helpers.
- `docs/`: design notes, ADRs, release checks, and testing notes.

## Requirements

- macOS with Xcode installed.
- iOS Simulator support.
- Swift 6 compatible toolchain.

The local verification script prefers an `iPhone Air` simulator when available, but it can run on another installed iPhone simulator.

## Run The Tests

Fast core tests with the 90% coverage gate:

```bash
Scripts/check_core_coverage.sh 90
```

Full local quality gate:

```bash
Scripts/verify_local.sh
```

Latest verified local result:

- Core tests: `49` passing.
- Core line coverage: `94.21%`.
- iOS integration tests: `20` passing.
- iOS UI smoke tests: `5` passing.
- Full result: `TEST SUCCEEDED`.

## GitHub Actions

The repository includes a GitHub Actions workflow for macOS runners. It runs:

- Core coverage with a 90% threshold.
- iPhone app, integration, and UI tests.

The workflow does not require signing certificates, secrets, distribution profiles, or cloud credentials.

## Safe Publishing Checklist

Before pushing or opening issues with real examples:

- Run `Scripts/preflight_publish.sh --require-remote`.
- Do not commit real fuel invoices, odometer photos, dashboard photos, or location exports.
- Add only redacted OCR transcript fixtures under `CartrackCore/Tests/CartrackCoreTests/Fixtures/OCR/`.
- Keep `.env`, local databases, build outputs, and exported captures out of git.

## Roadmap

- Add polished screenshots to this README.
- Add more redacted OCR fixtures from real-world receipt formats.
- Improve dashboard comparisons and projections after more driving data exists.
- Explore computer-vision assistance for analog fuel gauges after enough labeled examples are available.
