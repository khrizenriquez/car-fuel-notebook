#!/usr/bin/env bash
set -euo pipefail

preferred_name="${CARTRACK_SIMULATOR_NAME:-iPhone Air}"
requested_count="${1:-1}"

if ! [[ "$requested_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 [positive simulator count]" >&2
  exit 2
fi

json="$(xcrun simctl list devices available -j)"

SIMCTL_JSON="$json" /usr/bin/python3 - "$preferred_name" "$requested_count" <<'PY'
import json
import os
import re
import sys

preferred = sys.argv[1]
requested_count = int(sys.argv[2])
payload = json.loads(os.environ["SIMCTL_JSON"])

def runtime_version(runtime_identifier):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime_identifier)
    if not match:
        return (0, 0)
    return (int(match.group(1)), int(match.group(2)))

candidates = []
for runtime, devices in payload.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", False):
            continue
        name = device.get("name", "")
        udid = device.get("udid", "")
        if not name or not udid or not name.startswith("iPhone"):
            continue
        candidates.append({
            "name": name,
            "udid": udid,
            "runtime": runtime,
            "version": runtime_version(runtime),
        })

if not candidates:
    sys.stderr.write("No available iPhone simulator found.\n")
    sys.exit(1)

latest_version = max(candidate["version"] for candidate in candidates)
latest_candidates = [
    candidate for candidate in candidates if candidate["version"] == latest_version
]
preferred_candidates = [
    candidate for candidate in latest_candidates if candidate["name"] == preferred
]
remaining_candidates = [
    candidate for candidate in latest_candidates if candidate["name"] != preferred
]
selected = preferred_candidates + sorted(remaining_candidates, key=lambda candidate: candidate["name"])

if len(selected) < requested_count:
    sys.stderr.write(
        f"Requested {requested_count} iPhone simulators, but only {len(selected)} are available "
        f"for iOS {latest_version[0]}.{latest_version[1]}.\n"
    )
    sys.exit(1)

for candidate in selected[:requested_count]:
    print(f"platform=iOS Simulator,id={candidate['udid']}")
PY
