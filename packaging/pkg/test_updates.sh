#!/bin/bash
set -eu
TASK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/ifan-update-tests.XXXXXX")"
trap 'rm -rf "$TASK_TEMP"' EXIT
for test in test_update_manifest test_update_channels; do
    swiftc -swift-version 6 \
        "$TASK_ROOT/Sources/MacFanControl/UpdateManifest.swift" \
        "$TASK_ROOT/Sources/MacFanControl/UpdatePreferences.swift" \
        "$TASK_ROOT/packaging/pkg/$test.swift" -o "$TASK_TEMP/$test"
    "$TASK_TEMP/$test"
done
python3 "$TASK_ROOT/packaging/pkg/test_update_service.py"
