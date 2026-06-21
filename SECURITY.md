# Security Policy

## Scope
Cartrack v1 is a local-first, single-user iPhone app. It does not require a backend, cloud sync, API keys, OAuth clients, analytics SDKs, or third-party credentials.

## Local Data
Fuel events, vehicle records, manual adjustments, and image references are persisted on device through SwiftData and local application-support files. Captured evidence images should stay out of the source repository.

The repository ignores common local database and capture-export names such as `*.sqlite`, `*.db`, `Captures/`, `Invoices/`, `Odometer/`, and `FuelLevel/` to reduce the chance of publishing private driving or invoice data by accident.

## Reporting Issues
Before publishing this repository, choose the private reporting channel you want to use for security issues. Until then, keep security review local and do not include real invoices, license plates, location history, or odometer photos in public issues.

## Dependency Posture
The app currently uses Apple platform frameworks and local Swift code. If third-party dependencies are added later, document why they are needed and include them in CI validation before merging.
