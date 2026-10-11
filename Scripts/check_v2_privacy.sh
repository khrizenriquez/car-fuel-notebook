#!/usr/bin/env bash
set -euo pipefail

# v2 is intentionally local-first. This gate proves the shipped sources do not
# acquire a network client or track the private photo corpus used only on the owner Mac.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "Privacy gate failed: $*" >&2
  exit 1
}

echo "[privacy] Checking for network client APIs in v2 sources"
if rg -n 'URLSession|URLRequest|NSURLSession|NWConnection|Network\.framework|Alamofire|WebSocket' \
  Cartrack CartrackCore -g '*.swift'; then
  fail "v2 must not ship a network client for capture, OCR, or sync."
fi

echo "[privacy] Checking that cloud configuration remains deferred"
./Scripts/check_cloud_readiness.sh

echo "[privacy] Checking that the local private fixture manifest is ignored"
git check-ignore -q CartrackTests/Fixtures/private-image-scenarios.json \
  || fail "The private fixture manifest must remain ignored."
if git ls-files --error-unmatch CartrackTests/Fixtures/private-image-scenarios.json >/dev/null 2>&1; then
  fail "The private fixture manifest is tracked."
fi

echo "[privacy] Checking that photo/PDF evidence is not tracked"
tracked_evidence="$(
  git ls-files | rg -i '(invoice|odometer|fuellevel|capture|receipt|factura).*\.(heic|heif|jpg|jpeg|png|tiff|pdf)$' \
    | rg -v '^docs/assets/readme/' || true
)"
[[ -z "$tracked_evidence" ]] || {
  echo "$tracked_evidence"
  fail "Private capture evidence is tracked."
}

echo "Privacy gate passed: no v2 network client, cloud configuration, or tracked private evidence."
