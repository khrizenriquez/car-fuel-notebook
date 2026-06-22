# OCR Fixture Guide

Use sanitized OCR text fixtures to improve parser coverage without committing private invoices, odometer photos, license plates, locations, or raw images.

## What to Commit
- OCR transcript text only, copied from Vision output or typed from a real receipt/photo.
- Expected extracted values such as gallons, price per gallon, total, odometer miles, trip miles, and fuel spaces remaining.
- Redacted station identifiers if they reveal personal routes.

## What Not to Commit
- Original invoice, odometer, fuel-level, or dashboard photos.
- License plates, addresses, exact station names tied to personal routes, QR codes, NIT/tax IDs, authorization numbers, or payment card fragments.
- Local app databases or capture-export folders.

## How to Add a Fixture
1. Add a new case to `CartrackCore/Tests/CartrackCoreTests/Fixtures/OCR/ocr-fixtures.json`.
2. Set `kind` to `fillUp` or `snapshot`.
3. Paste sanitized `invoiceText`, `odometerText`, and `fuelLevelText`.
4. Fill only the expected fields that should be extracted.
5. Run `Scripts/check_core_coverage.sh 90`.
6. Run `Scripts/verify_local.sh` before committing.

Fixtures should represent real OCR shapes, including noisy labels, comma decimals, spaced odometer thousands, mixed Spanish/English labels, and fractional fuel spaces such as `6 1/2`.
