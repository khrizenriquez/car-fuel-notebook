# V1 Readiness Audit

Last local audit: 2026-06-22.

This audit maps the original Cartrack v1 requirements to current evidence in the repository. Treat `Complete` as locally verified and `External` as intentionally waiting on a private GitHub remote, first remote CI run, or real sanitized OCR transcripts.

## Verification Summary
- Local quality gate: `Scripts/verify_local.sh`
- Latest observed result: `TEST SUCCEEDED`
- Core coverage: `94.21%`, above the required `90%`
- Publish safety gate: `Scripts/preflight_publish.sh`
- Latest publish preflight result: passed, with expected warning that no remote is configured yet

## Requirement Evidence
| Requirement | Status | Evidence |
| --- | --- | --- |
| Native iPhone app using Apple stack | Complete | SwiftUI app files under `Cartrack/`, SwiftData model container in `CartrackCore/Sources/CartrackCore/CartrackModelContainer.swift`, Apple-only services for Vision, CoreLocation, UserNotifications, PhotosPicker, and local files. |
| Local-first single-user v1 with no cloud sync | Complete | No backend configuration or secrets required; `SECURITY.md`; `README.md` Security Notes; `.gitignore` excludes local databases and evidence exports. |
| Local database survives app updates | Locally designed | SwiftData default persistent store is used by the app and reset is only explicit; documented in `docs/adr/ADR-002-persistence-and-reset-semantics.md`. A true app-update migration test requires an installed prior app build and is deferred until release packaging exists. |
| Full reset exists only as explicit Settings action | Complete | `Cartrack/Features/Settings/SettingsView.swift`; `CartrackTests/PersistenceIntegrationTests.swift`; `CartrackUITests/CartrackSmokeUITests.swift` verifies Settings reset returns to empty dashboard. |
| Monthly dashboard is primary home view | Complete | `Cartrack/App/RootTabView.swift` and `Cartrack/Features/Dashboard/DashboardView.swift`; UI tests start from Dashboard and verify dashboard metrics and adjustments. |
| Fill-up flow captures invoice, odometer, and fuel-level evidence | Complete | `Cartrack/Features/Capture/FillUpFormView.swift`; `Cartrack/Features/Shared/ImageCaptureField.swift`; `CartrackTests/EventImageIntegrationTests.swift` verifies all three fill-up image assets are stored and deleted. |
| Snapshot flow captures odometer and fuel-level evidence | Complete | `Cartrack/Features/Capture/SnapshotFormView.swift`; `CartrackTests/EventImageIntegrationTests.swift` verifies snapshot image asset storage/deletion. |
| On-device OCR prefill with manual correction | Complete | `Cartrack/Services/OCRService.swift`; `CartrackCore/Sources/CartrackCore/OCRTextParser.swift`; `CartrackTests/OCRServiceTests.swift`; `CartrackCore/Tests/CartrackCoreTests/OCRTextParserCoreTests.swift`. |
| Do not commit private photos/invoices | Complete | `docs/testing/ocr-fixtures.md`; `.gitignore`; `Scripts/preflight_publish.sh` rejects tracked private evidence image/PDF patterns and scans for common secrets. |
| Fuel level canonical field is spaces remaining | Complete | `CartrackCore/Sources/CartrackCore/FuelLevelScale.swift`; `Cartrack/Features/Shared/FuelLevelInputView.swift`; `README.md`; UI test verifies saved `6.5` spaces. |
| Fuel level range `0.00 ... 8.00`, step `0.25` | Complete | `CartrackCore/Tests/CartrackCoreTests/FuelLevelScaleCoreTests.swift`; `CartrackTests/FuelLevelScaleTests.swift`; UI correction controls in `FuelLevelInputView.swift`. |
| Trip reset policy warns but does not hard-block | Complete | Fill-up form validation/warning behavior in `Cartrack/Features/Capture/FillUpFormView.swift`; save remains available for corrected/manual values. |
| Monthly metrics include spend, gallons, km, km/gal, cost/km | Complete | `CartrackCore/Sources/CartrackCore/AnalyticsEngine.swift`; `CartrackCore/Tests/CartrackCoreTests/AnalyticsEngineCoreTests.swift`; `Cartrack/Features/Dashboard/DashboardView.swift`. |
| Tank metrics include distance, efficiency, autonomy, current progress | Complete | `AnalyticsEngine.currentTankStatus`; analytics core tests for current tank status, stale snapshots, autonomy, and consumed-cost estimate. |
| Default final-fill month allocation and prorated alternate | Complete | `AnalyticsEngine.monthlySummaries`; tests `testFinalFillMonthAllocationPutsCycleInClosingMonth` and `testProratedAllocationSplitsCycleAcrossMonthsAndPreservesTotals`; ADR-004. |
| Edits overwrite values and trigger recalculation | Complete | `testEditingFillValuesRecalculatesMonthlyAnalytics`; UI test `testEditFillUpThenResetAllData`; editable form views for fill-ups, snapshots, vehicles, and adjustments. |
| Multiple vehicles are separated across capture, history, and analytics | Complete | `testMonthlySummariesKeepVehicleDataSeparated`; `testMultiVehicleFilteringAcrossDashboardCaptureAndHistory`. |
| Reminders trigger from inactivity and reset after capture | Complete | `Cartrack/Services/ReminderService.swift`; `CartrackTests/ReminderServiceTests.swift`; reset cancels reminders after full local reset. |
| Automatic location capture is enabled per event | Complete | `Cartrack/Services/LocationService.swift`; event coordinate preservation tests in `CartrackCore/Tests/CartrackCoreTests/ModelCoreTests.swift`; form save paths preserve or update coordinates. |
| Strict tests at or above 90% | Complete | `Scripts/check_core_coverage.sh 90`; latest observed coverage `94.21%`; CI workflow enforces the same command. |
| Modular architecture for study and maintenance | Complete | `CartrackCore` domain package, app services, feature folders, ADRs, and test targets split by concern. |
| GitHub Actions workflow ready | Complete locally | `.github/workflows/ios-ci.yml`; `Scripts/preflight_publish.sh` verifies read-only permissions, no signing, and 90% coverage gate. First hosted run is external until remote exists. |
| Private GitHub publishing path is safe | Complete locally | `docs/release/private-github-publish.md`; `Scripts/preflight_publish.sh`; `SECURITY.md`. |
| Additional real OCR hardening from actual evidence | External | Requires real invoice/odometer/fuel-level photos or Vision transcripts. Only sanitized OCR transcript text should be committed. |
| First private remote push and remote CI review | External | Requires a private GitHub repository URL and network-side Actions execution. |
| Dashboard insight iteration from real month-over-month data | External | Requires accumulated real driving data after app usage begins. |

## Current Remaining Work
1. Create a private GitHub repository.
2. Add it as `origin`.
3. Run `Scripts/preflight_publish.sh --require-remote`.
4. Push `main` and review the first GitHub Actions run.
5. Add sanitized OCR transcript fixtures as real evidence becomes available.
6. Revisit dashboard insights after real month-over-month data accumulates.
