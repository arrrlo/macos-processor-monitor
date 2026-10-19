#!/usr/bin/env bash
# Packages the output of build-app.sh into build/macos-processor-monitor-<version>.pkg, a single
# installer containing the app, the helper daemon and the login agent.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="macOS Processor Monitor"
LABEL=io.github.arrrlo.macos-processor-monitor
VERSION=$(tr -d '[:space:]' < VERSION)
OUT=build
ROOT="$OUT/pkgroot"
RESOURCES="$OUT/pkg-resources"
PRODUCT="$OUT/macos-processor-monitor-$VERSION.pkg"

rm -rf "$ROOT" "$RESOURCES" "$OUT/component.pkg" "$PRODUCT"
mkdir -p "$ROOT/Applications" "$ROOT/Library/PrivilegedHelperTools" "$ROOT/Library/LaunchDaemons" "$ROOT/Library/LaunchAgents"
ditto "$OUT/$APP_NAME.app" "$ROOT/Applications/$APP_NAME.app"
cp "$OUT/$LABEL.helper" "$ROOT/Library/PrivilegedHelperTools/$LABEL.helper"
cp "packaging/$LABEL.helper.plist" "$ROOT/Library/LaunchDaemons/$LABEL.helper.plist"
cp "packaging/$LABEL.plist" "$ROOT/Library/LaunchAgents/$LABEL.plist"
chmod 755 "$ROOT/Library/PrivilegedHelperTools/$LABEL.helper"
chmod 644 "$ROOT/Library/LaunchDaemons/$LABEL.helper.plist" "$ROOT/Library/LaunchAgents/$LABEL.plist"
chmod 755 packaging/scripts/preinstall packaging/scripts/postinstall

# Without this, Installer "relocates" the update to any other copy of the bundle it finds
# (e.g. one in build/) instead of writing to /Applications.
pkgbuild --analyze --root "$ROOT" "$OUT/component.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$OUT/component.plist"

pkgbuild \
    --root "$ROOT" \
    --component-plist "$OUT/component.plist" \
    --scripts packaging/scripts \
    --identifier "$LABEL" \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$OUT/component.pkg"

mkdir -p "$RESOURCES"
cp packaging/resources/*.html "$RESOURCES/"
cp LICENSE "$RESOURCES/LICENSE.txt"
sed "s/__VERSION__/$VERSION/" packaging/distribution.xml > "$OUT/distribution.xml"
productbuild --distribution "$OUT/distribution.xml" --resources "$RESOURCES" --package-path "$OUT" "$PRODUCT"

echo "Built $PRODUCT ($(du -h "$PRODUCT" | cut -f1))"
