# ADR-001: Local-First Single-User iPhone Architecture

## Status
Accepted

## Context
The app is intended primarily for a personal iPhone workflow with invoice, odometer, and fuel-level image capture. Offline operation and privacy are more important than cross-device access in v1.

## Decision
Use a native iPhone architecture built with SwiftUI and SwiftData. The app will be single-user, local-first, and iPhone-only for v1.

## Rejected Alternatives
- Web app or GitHub Pages: weak local persistence and limited native capture flow.
- Cross-platform framework first: adds portability concerns before product fit is proven.
- Cloud-first backend: conflicts with privacy and offline-first priorities.

## Consequences
- Better camera, local storage, and system integration.
- Simpler v1 scope.
- No out-of-the-box desktop access or sync.

## Deferred Work
- iPad layouts.
- Cloud sync.
- Cross-device export/import.
