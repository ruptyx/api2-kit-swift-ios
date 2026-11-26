"""Prints the id of an iPhone simulator on the newest iOS the runner has."""
import json
import re
import sys

WANTED = ["iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro"]

found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    version = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not version:
        continue
    for device in devices:
        if device["name"] in WANTED and device.get("isAvailable", True):
            rank = (int(version[1]), int(version[2]), -WANTED.index(device["name"]))
            found.append((rank, device["udid"], device["name"], runtime))

if not found:
    sys.exit("no iPhone simulator found")
found.sort()
print(found[-1][1])
print(f"simulator: {found[-1][2]} on {found[-1][3]}", file=sys.stderr)
