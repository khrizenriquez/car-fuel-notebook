#!/usr/bin/env bash
set -euo pipefail

preferred_name="${CARTRACK_SIMULATOR_NAME:-iPhone Air}"

json="$(xcrun simctl list devices available -j)"

SIMCTL_JSON="$json" /usr/bin/python3 - "$preferred_name" <<'PY'
import json
import os
import re
import sys

preferred = sys.argv[1]
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

preferred_candidates = [candidate for candidate in candidates if candidate["name"] == preferred]
pool = preferred_candidates or candidates
selected = sorted(pool, key=lambda candidate: (candidate["version"], candidate["name"]))[-1]

print(f"platform=iOS Simulator,id={selected['udid']}")
PY
