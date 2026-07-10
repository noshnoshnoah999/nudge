#!/bin/bash
# Exercises the per-item sync merge rules (CloudSync.swift) outside the app target.
#
# There is no XCTest target in this project, and the merge rules are the one place where a
# mistake silently eats reminders — so they get executed, not just reviewed. The REST layer
# is trimmed off because it needs Secrets/Auth from the app; everything above it is pure.
#
#   ./ios/Nudge/SyncMergeTests/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../Nudge"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$src/Models.swift" "$work/"
# Everything from "MARK: - REST" down needs the app target; the merge logic above it doesn't.
awk '/^\/\/ MARK: - REST/{exit} {print}' "$src/CloudSync.swift" > "$work/CloudSync.swift"
cp "$here/main.swift" "$work/"

swiftc -o "$work/mergetest" "$work/Models.swift" "$work/CloudSync.swift" "$work/main.swift"
"$work/mergetest"
