#!/usr/bin/env bash
# Regenerates packaging/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil --convert icns --output packaging/AppIcon.icns "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
echo "Wrote packaging/AppIcon.icns"
