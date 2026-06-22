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
- Done: OCR service uses an injectable text recognizer so prefill parsing is covered without real Vision calls, and Vision failures return an empty prefill instead of hanging analysis.
- Done: UI coverage for creating a vehicle, opening capture, saving a fill-up, saving a snapshot, and verifying both in history.
- Done: UI coverage for editing an existing fill-up and confirming Settings reset returns the app to empty dashboard state.
- Done: monthly manual adjustments can be created, edited, and explicitly deleted with confirmation; UI coverage verifies create/delete recalculates dashboard distance.
- Done: deleting a fill-up removes its invoice, odometer, and fuel-level image assets plus local files; integration coverage verifies no orphaned evidence remains.
- Done: deleting a vehicle cascades through its fill-ups, snapshots, monthly manual adjustments, image asset records, and owned image files; integration coverage verifies no orphaned local evidence remains.
- Done: local image cleanup treats already-missing files as no-ops but propagates real file removal errors through deletion, replacement, and reset flows.
- Done: vehicle and history deletions require explicit UI confirmation and surface deletion errors instead of silently swallowing failed saves or file cleanup.
- Done: vehicle and monthly adjustment forms surface persistence errors and only dismiss after successful save/delete operations.
- Done: Settings reset integration coverage verifies persisted domain records and a real local image file are removed.
- Done: Settings reset cancels any pending inactivity reminder after the local data/image reset succeeds.
- Done: fill-up and snapshot fuel-level correction supports text entry, quarter-step buttons, and slider input while storing exact normalized `spaces remaining` values such as `6.5`.
- Done: editing a fill-up or snapshot preserves any existing event coordinate when no fresh location reading is available, while preferring a complete new coordinate when present.
- Done: current tank analytics ignore stale snapshots captured before the latest fill-up, so a new fill-up resets tank progress and fuel-level reference.
- Done: core analytics coverage verifies monthly summaries, manual adjustments, tank cycles, and current tank status stay separated by vehicle when multiple cars have data.
- Done: smoke UI coverage verifies switching between multiple vehicles across dashboard filtering, capture vehicle selection, and history filtering.
- Done: inactivity reminders now respect the enabled/disabled Settings preference, cancel when disabled, and reset after each new fill-up or snapshot capture; app-unit coverage verifies scheduling behavior without touching real notifications.
- Done: launch hardening now shows a persistence error screen instead of terminating if SwiftData initialization fails.
- Done: dashboard includes a current-month closing projection based on elapsed-day pace.
- Done: local quality gate script runs strict core coverage plus full iPhone Air simulator tests.
- Done: git repository initialized locally with generated build data, local databases, capture exports, and common secret files ignored.
- Done: GitHub Actions workflow added with strict core coverage and iPhone app/integration/UI tests on `macos-26`.
- Done: simulator selection script prefers `iPhone Air` locally but can fall back to another available iPhone simulator in CI.
- Done: OCR fixtures expanded for space-separated odometer thousands, abbreviated pump receipt labels, and fractional tank readings like `6 1/2 espacios`.
- Done: sanitized OCR fixture harness added so parser cases can be extended from real Vision transcripts without committing private invoice, odometer, or dashboard photos.
- Done: repository security notes added for local-only data, ignored evidence files, and no-secret v1 posture.
- Done: private GitHub publish runbook and local publish preflight added for safety checks before the first remote push.

## Remaining V1 Checklist
- Add additional sanitized OCR transcript fixtures as actual invoices and photos become available.
- Push to a private GitHub remote, run `Scripts/preflight_publish.sh --require-remote`, and review the first remote GitHub Actions run.
- Keep improving dashboard insights after real driving data accumulates.

## Recommended Execution Order
1. Run `Scripts/verify_local.sh` and `Scripts/preflight_publish.sh`.
2. Create a private GitHub remote, add it as `origin`, and run `Scripts/preflight_publish.sh --require-remote`.
3. Push the initialized repository to the private remote.
4. Review the first GitHub Actions run and adjust runner/runtime only if needed.
5. Add additional sanitized OCR fixtures from real-world evidence.
6. Iterate dashboard insights with real month-over-month data.
