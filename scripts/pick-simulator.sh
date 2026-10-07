#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, for use as an xcodebuild destination:
#
#   DESTINATION="platform=iOS Simulator,id=$(scripts/pick-simulator.sh)" scripts/verify.sh
#
# Picks from the newest iOS runtime that has an iPhone, preferring a plain numbered model ("iPhone 16") with the
# highest number over the Pro, Plus, SE and "e" variants. Exits with 1 when no iPhone simulator is available.

set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

runtimes = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in runtimes.items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not match:
        continue
    version = tuple(int(part) for part in match.group(1).split("-"))
    for device in devices:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))

if not candidates:
    sys.exit("pick-simulator: no available iPhone simulator found")

newest = max(version for version, _, _ in candidates)

def rank(candidate):
    _, name, _ = candidate
    plain = re.fullmatch(r"iPhone (\d+)", name)
    return (1 if plain else 0, int(plain.group(1)) if plain else 0, name)

print(max((c for c in candidates if c[0] == newest), key=rank)[2])
'
