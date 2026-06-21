# ADR-006: Core Module and Coverage Gate

## Status
Accepted

## Context
The app has important business rules around fuel-level scale, OCR parsing, monthly allocation, tank-cycle calculation, and manual corrections. Those rules need strict tests and should be easy to study independently from SwiftUI screens and iOS-only services.

## Decision
Create `CartrackCore` as a shared domain module. The iOS app compiles the shared core sources, and SwiftPM runs unit tests directly against the same core code. Add a coverage gate script that fails below 90% line coverage for `CartrackCore`, plus a full local verification script that also runs app, integration, and smoke UI tests on an available iPhone simulator.

## Rejected Alternatives
- Measuring coverage only through UI tests: slower, more fragile, and less useful for learning business rules.
- Keeping all logic inside SwiftUI views: hard to test and hard to reason about.
- Lowering the coverage threshold: not aligned with the goal of strict, study-friendly tests.

## Consequences
- Domain rules are modular and testable without an iOS simulator.
- Coverage is meaningful because it focuses on logic instead of view rendering.
- UI and iOS integration are verified separately because they are slower and require simulator support.
- CI can reuse the same scripts while selecting an available iPhone simulator dynamically.

## Deferred Work
- Consider turning `CartrackCore` into an imported package product if the app grows into multiple targets.
- Expand UI coverage beyond smoke flows if future dashboards or OCR correction screens become more complex.
