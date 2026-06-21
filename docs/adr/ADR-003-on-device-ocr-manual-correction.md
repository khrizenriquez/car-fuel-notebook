# ADR-003: On-Device OCR and Manual Correction

## Status
Accepted

## Context
The product depends on images as primary evidence, but OCR quality can vary across invoices and cluster photos.

## Decision
Run OCR on-device using Vision. Use heuristic parsing to prefill fields and require a confirmation/edit screen before save. Manual edits become the authoritative values.

## Rejected Alternatives
- Cloud OCR: better extraction but worse privacy and higher operational cost.
- Fully manual entry only: slower workflow and less value from captured evidence.
- Auto-save extracted values without review: too error-prone.

## Consequences
- Faster capture than pure manual entry.
- Some image types, especially fuel-level photos, may still need manual correction.
- Parsing logic should be isolated and replaceable.

## Deferred Work
- Gauge-specific vision models.
- Confidence scoring UI.
- Batch processing of historical photos.
