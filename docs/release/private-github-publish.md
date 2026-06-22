# Private GitHub Publish Runbook

Use this runbook when publishing Cartrack to a private GitHub repository for the first time. The intent is to keep the repo safe to share while preserving the local-first privacy model.

## Before Publishing
- Confirm the repository is private before the first push.
- Do not commit real invoice photos, odometer photos, fuel-level photos, local databases, app container exports, QR codes, NIT/tax IDs, payment fragments, exact stations tied to personal routes, or license plates.
- Add only sanitized OCR transcript fixtures under `CartrackCore/Tests/CartrackCoreTests/Fixtures/OCR/ocr-fixtures.json`.
- Run the full local gate before pushing:

```bash
Scripts/verify_local.sh
```

- Run the publish preflight:

```bash
Scripts/preflight_publish.sh
```

## Create The Private Remote
Create a private empty repository on GitHub, then attach it locally:

```bash
git remote add origin git@github.com:<owner>/<private-repo>.git
git remote -v
Scripts/preflight_publish.sh --require-remote
```

If the remote was created with HTTPS instead of SSH, use the HTTPS URL from GitHub. Do not commit personal access tokens or credentials.

## First Push
Push the current local history:

```bash
git push -u origin main
```

After pushing, open the repository Actions tab and verify both jobs complete:

- `Core Coverage`
- `iPhone App Tests`

Or verify the latest remote run from the terminal:

```bash
Scripts/check_remote_ci.sh
```

The workflow intentionally uses read-only repository permissions, disables code signing, and does not require secrets.

## If GitHub Actions Differs From Local
- Check the runner Xcode version in the `iPhone App Tests` logs.
- Check the simulator selected by `Scripts/select_ios_simulator.sh`.
- Prefer adapting simulator selection or CI runtime assumptions instead of weakening tests.
- Keep the local command `Scripts/verify_local.sh` as the source of truth for reproducing failures.
- Re-run `Scripts/check_remote_ci.sh` after pushing any CI-only fix.

## After Publishing
- Keep the repository private while real vehicle usage is being developed.
- Continue adding only sanitized OCR transcript fixtures.
- Re-run `Scripts/preflight_publish.sh` before future public visibility changes, even if v1 is intended to stay private.
