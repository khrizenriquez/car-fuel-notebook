# ADR-005: Editable Data and Recalculation

## Status
Accepted

## Context
The user needs to correct OCR mistakes and manually adjust monthly distance when the computed result does not look right.

## Decision
Allow nearly every captured and derived-supporting field to be edited. Edits overwrite the previous authoritative value and immediately trigger recomputation of affected analytics.

## Rejected Alternatives
- Immutable event records: too rigid for OCR-backed workflows.
- Audit log of original and edited values in v1: useful, but more complexity than needed now.
- Manual recompute action: easy to forget and creates inconsistency.

## Consequences
- Better trust in the stored history.
- Analytics code must be deterministic and recalculable.
- Users can repair edge-case OCR failures without data loss.

## Deferred Work
- Edit history or audit trail.
- Conflict resolution if sync is introduced later.
