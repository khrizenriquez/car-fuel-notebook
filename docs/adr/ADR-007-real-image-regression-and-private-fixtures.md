# ADR-007: Real-Image Regression and Private Fixtures

## Status

Accepted

## Context

Cartrack relies on Apple Vision and heuristic parsing to prefill receipts and BMW Z4 cluster readings. Text-only parser tests are fast and reproducible, but they cannot detect regressions caused by image orientation, exposure, crop selection, seven-segment recognition, or the Photos workflow in the iOS Simulator.

The project also has real invoices and dashboard photographs that contain personal vehicle and route evidence. Those images are useful for local regression but should not become public CI fixtures or production resources.

Some historical OCR behavior was stabilized with values keyed by exact image signatures. That makes a known file pass without proving that the reader generalizes to a recompressed, resized, newly captured, or otherwise equivalent image.

## Decision

Use a three-layer regression strategy:

1. Keep sanitized OCR transcripts in `CartrackCore` for deterministic parser tests.
2. Run a private manifest of real images through `OCRService` on the owner's Mac.
3. Import representative private scenarios into a dedicated simulator named `Cartrack Private Fixtures` and exercise the visible Photos, review, save, history, and dashboard flows.

The private manifest is the single source of truth for image paths, expected fields, tolerances, manual fuel confirmation, exclusions, and simulator participation.

Digital cluster readings use these tolerances:

- odometer: `±1 mi`;
- trip: `±0.2 mi`.

Analog fuel-gauge photos remain review-first under ADR-003. The expected OCR result is `nil` when a confident gauge-specific reading is unavailable. The user-selected value in `0...8` spaces, step `0.25`, becomes authoritative after confirmation.

Production OCR may use general display detection, segmentation, candidate reconciliation, and confidence rules. It must not return fixture answers from an exact file hash or pixel signature.

Private images and their real manifest remain ignored by Git. CI runs sanitized tests without the private pack. Local strict mode fails when the pack is absent or incomplete.

The simulator preparation script may erase only the exact, validated UDID of `Cartrack Private Fixtures`. It must reject missing, ambiguous, or partially matched devices.

## Rejected Alternatives

- Only parser tests: they do not execute Vision or image handling.
- Only UI tests: they are too slow and provide poor OCR diagnostics.
- Cloud OCR: conflicts with the local-first privacy decision.
- Commit all real photos: makes CI easy but violates the evidence privacy boundary.
- Keep exact-signature answers in production: passes known files while concealing general-reader failures.
- Automatically estimate analog fuel from the current photos: there is no accepted gauge-specific model or confidence contract.

## Consequences

- Real-image regressions are reproducible on a Mac that has the private fixture pack.
- Public CI remains deterministic and does not require personal evidence.
- Failures report scenario, expected value, observed value, tolerance, and recognized text.
- The private gate takes longer than the public gate because it runs Vision and Photos UI flows.
- New images extend a manifest instead of adding duplicated XCTest arrays.
- OCR failures must be repaired with general algorithms or must fall back safely to manual correction.

## Verification Contract

The implementation provides:

- `Scripts/verify_local.sh` for the public suite;
- `Scripts/verify_private_image_scenarios.sh` for the strict private suite;
- `CARTRACK_REQUIRE_PRIVATE_FIXTURES=1` to include the private gate from local verification;
- an ADR-aware publish preflight that rejects tracked private evidence;
- a readiness audit containing the last observed public and private results.

The real-image regression phase is complete only when both public and private gates pass and the production target contains no exact-fixture response table.
