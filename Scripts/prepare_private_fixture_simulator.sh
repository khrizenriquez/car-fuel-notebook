#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIMULATOR_NAME="Cartrack Private Fixtures"
MANIFEST="CartrackTests/Fixtures/private-image-scenarios.json"
RESET="false"

if [[ "${1:-}" == "--reset" ]]; then
  RESET="true"
elif [[ $# -gt 0 ]]; then
  echo "Usage: Scripts/prepare_private_fixture_simulator.sh [--reset]" >&2
  exit 2
fi

[[ -f "$MANIFEST" ]] || {
  echo "Missing private fixture manifest: $MANIFEST" >&2
  exit 1
}

device_json="$(xcrun simctl list devices available -j)"
runtime_json="$(xcrun simctl list runtimes available -j)"
device_type_json="$(xcrun simctl list devicetypes -j)"

resolve_result="$(
  SIMCTL_DEVICES="$device_json" \
  SIMCTL_RUNTIMES="$runtime_json" \
  SIMCTL_DEVICE_TYPES="$device_type_json" \
  /usr/bin/python3 - "$SIMULATOR_NAME" <<'PY'
import json
import os
import re
import sys

name = sys.argv[1]
devices_payload = json.loads(os.environ["SIMCTL_DEVICES"])
runtimes_payload = json.loads(os.environ["SIMCTL_RUNTIMES"])
device_types_payload = json.loads(os.environ["SIMCTL_DEVICE_TYPES"])

matches = []
for runtime, devices in devices_payload.get("devices", {}).items():
    for device in devices:
        if device.get("isAvailable") and device.get("name") == name:
            matches.append((device["udid"], runtime))

if len(matches) > 1:
    sys.stderr.write(f"Refusing ambiguous simulator name: {name} ({len(matches)} matches).\n")
    sys.exit(3)

if matches:
    print(f"existing\t{matches[0][0]}\t{matches[0][1]}")
    sys.exit(0)

available_runtimes = [
    runtime for runtime in runtimes_payload.get("runtimes", [])
    if runtime.get("isAvailable") and runtime.get("platform") == "iOS"
]
if not available_runtimes:
    sys.stderr.write("No available iOS simulator runtime.\n")
    sys.exit(4)

def version(runtime):
    value = runtime.get("version", "0")
    return tuple(int(part) for part in re.findall(r"\d+", value))

runtime = sorted(available_runtimes, key=version)[-1]
device_types = device_types_payload.get("devicetypes", [])
preferred_names = ["iPhone Air", "iPhone 17", "iPhone 16"]
selected_type = None
for preferred in preferred_names:
    selected_type = next(
        (item for item in device_types if item.get("name") == preferred),
        None,
    )
    if selected_type:
        break
if not selected_type:
    selected_type = next(
        (item for item in device_types if item.get("name", "").startswith("iPhone")),
        None,
    )
if not selected_type:
    sys.stderr.write("No iPhone simulator device type.\n")
    sys.exit(5)

print(f"create\t{selected_type['identifier']}\t{runtime['identifier']}")
PY
)"

IFS=$'\t' read -r state value runtime_identifier <<<"$resolve_result"

if [[ "$state" == "create" ]]; then
  udid="$(xcrun simctl create "$SIMULATOR_NAME" "$value" "$runtime_identifier")"
else
  udid="$value"
fi

validation_json="$(xcrun simctl list devices -j)"
validated_name="$(SIMCTL_VALIDATION_JSON="$validation_json" /usr/bin/python3 - "$udid" <<'PY'
import json
import os
import sys

udid = sys.argv[1]
payload = json.loads(os.environ["SIMCTL_VALIDATION_JSON"])
for devices in payload.get("devices", {}).values():
    for device in devices:
        if device.get("udid") == udid:
            print(device.get("name", ""))
            sys.exit(0)
sys.exit(1)
PY
)"

if [[ "$validated_name" != "$SIMULATOR_NAME" ]]; then
  echo "Refusing to modify unexpected simulator '$validated_name' ($udid)." >&2
  exit 6
fi

if [[ "$RESET" == "true" ]]; then
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid"
fi

xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b

fixture_paths=()
while IFS= read -r fixture_path; do
  fixture_paths+=("$fixture_path")
done < <(
  PRIVATE_SCENARIO_ID="${CARTRACK_PRIVATE_SCENARIO_ID:-}" \
  PRIVATE_MEDIA_ROLE="${CARTRACK_PRIVATE_MEDIA_ROLE:-}" \
  /usr/bin/python3 - "$MANIFEST" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)

scenario_filter = os.environ.get("PRIVATE_SCENARIO_ID", "")
role_filter = os.environ.get("PRIVATE_MEDIA_ROLE", "")
valid_roles = ("invoiceImage", "odometerImage", "fuelImage")
if role_filter and role_filter not in valid_roles:
    sys.stderr.write(f"Unsupported CARTRACK_PRIVATE_MEDIA_ROLE: {role_filter}\n")
    sys.exit(9)

seen = set()
matched_scenario = False
for scenario in manifest.get("scenarios", []):
    if scenario.get("excluded") or not scenario.get("ui", {}).get("runInSimulator", False):
        continue
    if scenario_filter and scenario.get("id") != scenario_filter:
        continue
    matched_scenario = True
    roles = (role_filter,) if role_filter else valid_roles
    for key in roles:
        path = scenario.get(key)
        if path and path not in seen:
            seen.add(path)
            print(path)

if scenario_filter and not matched_scenario:
    sys.stderr.write(f"No simulator-enabled scenario matched: {scenario_filter}\n")
    sys.exit(10)
PY
)

if [[ ${#fixture_paths[@]} -eq 0 ]]; then
  echo "No simulator fixtures selected in $MANIFEST." >&2
  exit 7
fi

for path in "${fixture_paths[@]}"; do
  [[ -f "$path" ]] || {
    echo "Missing simulator fixture: $path" >&2
    exit 8
  }
done

xcrun simctl addmedia "$udid" "${fixture_paths[@]}"
echo "platform=iOS Simulator,id=$udid"
