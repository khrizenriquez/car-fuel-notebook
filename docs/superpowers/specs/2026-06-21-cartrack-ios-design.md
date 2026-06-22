# Cartrack iPhone App Design

## Summary
Cartrack is a single-user, iPhone-only, local-first fuel tracking app. It captures invoice, odometer, and fuel-level images per event, extracts useful values on-device, preserves the raw evidence locally, and computes month-based analytics plus tank-level insights. The app must survive normal updates without resetting its local database or image store.

## Product Goals
- Track real-world fuel behavior with invoice-backed data instead of brochure specs.
- Support multiple vehicles even though the first target is a BMW Z4 E85 2003 2.5i automatic.
- Work offline with local OCR, local persistence, and no cloud dependency in v1.
- Keep the data editable so user corrections always win over automated extraction.
- Make month-by-month historical analysis the primary experience.

## Core Event Types
- `FuelFillEvent`: full refuel event with invoice evidence, odometer evidence, fuel-level evidence, gallons, price, total cost, trip reading, and location.
- `SnapshotEvent`: intermediate checkpoint between refuels with odometer evidence, fuel-level evidence, optional trip value, and location.
- `MonthlyManualAdjustment`: user-supplied monthly distance correction used when computed values need an override or support note.

## Data Rules
- Fuel level is recorded as `spaces remaining`.
- Supported range is `0.00 ... 8.00`.
- Supported granularity is `0.25`.
- `spaces consumed` is always derived from the vehicle scale max.
- Stored analytics are normalized to kilometers, gallons, and quetzales.
- Trip reset is expected after a fill-up and should raise a warning when inconsistent, but not block save.

## UX Shape
- Home screen focuses on current-month summary.
- Capture tab splits into fill-up and snapshot flows.
- History shows fills and snapshots with edit access.
- Vehicles manages multi-vehicle data.
- Settings handles reminder policy and full reset.

## Analytics Rules
- Default monthly grouping assigns a tank cycle to the month of the closing fill-up.
- Alternate monthly grouping prorates a tank cycle across month boundaries for advanced analysis.
- Monthly analytics include spend, gallons, distance, km/gal, and cost/km.
- Current-month projection estimates closing spend, gallons, distance, km/gal, and cost/km from elapsed days in the current month.
- Tank analytics include tank distance, efficiency, estimated autonomy, and current tank progress based on latest known fuel level.

## Technical Direction
- `SwiftUI` for UI.
- `SwiftData` for local persistence.
- `Vision` for OCR and simple parsing.
- `CoreLocation` for automatic event location.
- `UserNotifications` for inactivity reminders.
- Local image storage under application support.

## Non-Goals for v1
- Cloud sync.
- Desktop or web companion.
- Shared multi-user accounts.
- Historical photo import automation.

## Acceptance Criteria
- User can create, edit, and delete vehicles, fill-up events, snapshot events, and monthly adjustments.
- OCR prefill is attempted locally and can be corrected before save.
- Monthly and tank analytics update after edits.
- App data survives updates.
- Full reset only happens after explicit confirmation in Settings.

## Implementation Status
- Done: native SwiftUI/SwiftData project scaffold with local-first persistence.
- Done: core domain module with models, unit conversion, fuel-level scale rules, OCR text parsing, and analytics.
- Done: documentation and ADRs for architecture, persistence/reset, OCR correction, analytics allocation, editable data, and coverage gate.
- Done: app screens for dashboard, capture, history, vehicles, settings, reset, image selection, and manual monthly adjustment.
- Done: local image storage with iOS file protection and event/image synchronization.
- Done: local validation on `iPhone Air` simulator with unit, integration, and smoke UI tests.
- Done: strict core test coverage gate above 90%.
- Done: OCR parser hardening for Guatemala-style invoice labels, comma decimals, currency values, odometer thousands separators, and noisy BMW Z4 fuel-level text.
- Done: UI coverage for creating a vehicle, opening capture, saving a fill-up, saving a snapshot, and verifying both in history.
- Done: UI coverage for editing an existing fill-up and confirming Settings reset returns the app to empty dashboard state.
- Done: monthly manual adjustments can be created, edited, and explicitly deleted with confirmation; UI coverage verifies create/delete recalculates dashboard distance.
- Done: deleting a vehicle cascades through its fill-ups, snapshots, monthly manual adjustments, image asset records, and owned image files; integration coverage verifies no orphaned local evidence remains.
- Done: fill-up and snapshot fuel-level correction supports text entry, quarter-step buttons, and slider input while storing exact normalized `spaces remaining` values such as `6.5`.
- Done: inactivity reminders now respect the enabled/disabled Settings preference, cancel when disabled, and reset after each new fill-up or snapshot capture; app-unit coverage verifies scheduling behavior without touching real notifications.
- Done: launch hardening now shows a persistence error screen instead of terminating if SwiftData initialization fails.
- Done: dashboard includes a current-month closing projection based on elapsed-day pace.
- Done: local quality gate script runs strict core coverage plus full iPhone Air simulator tests.
- Done: git repository initialized locally with generated build data, local databases, capture exports, and common secret files ignored.
- Done: GitHub Actions workflow added with strict core coverage and iPhone app/integration/UI tests on `macos-26`.
- Done: simulator selection script prefers `iPhone Air` locally but can fall back to another available iPhone simulator in CI.
- Done: OCR fixtures expanded for space-separated odometer thousands, abbreviated pump receipt labels, and fractional tank readings like `6 1/2 espacios`.
- Done: repository security notes added for local-only data, ignored evidence files, and no-secret v1 posture.

## Remaining V1 Checklist
- Add more realistic OCR fixtures as actual invoices and photos become available.
- Push to a private GitHub remote and review the first remote GitHub Actions run.
- Keep improving dashboard insights after real driving data accumulates.

## Recommended Execution Order
1. Push the initialized repository to a private remote.
2. Review the first GitHub Actions run and adjust runner/runtime only if needed.
3. Add additional OCR fixtures from real-world evidence.
4. Iterate dashboard insights with real month-over-month data.
