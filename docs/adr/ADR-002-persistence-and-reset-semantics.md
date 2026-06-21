# ADR-002: Persistence and Reset Semantics

## Status
Accepted

## Context
The user needs confidence that app updates do not wipe operational data, while still wanting a deliberate reset during the initial test period.

## Decision
Persist data in SwiftData backed by on-device storage and store captured images under application support. Provide a manual full-reset action in Settings that deletes vehicles, events, adjustments, and image files only after confirmation.

## Rejected Alternatives
- Rebuildable or cache-only storage: too risky for real records.
- Reset on reinstall/update or version migration: unacceptable for a logbook app.
- Separate trial and production stores in v1: more complexity than needed.

## Consequences
- Stable behavior across updates.
- Reset flow must clean both database rows and image files.
- Migrations must preserve data when the schema evolves.

## Deferred Work
- Backup/export.
- Safer partial resets.
- Recovery from corrupted stores.
