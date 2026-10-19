#!/usr/bin/env bash
# Builds build/macOS Processor Monitor.app and the privileged helper binary (release, arm64),
# both ad-hoc signed with the hardened runtime. Version comes from VERSION; set BUILD_NUMBER
# to override the bundle version (defaults to the git commit count).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="macOS Processor Monitor"
LABEL=io.github.arrrlo.macos-processor-monitor
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
OUT=build
APP="$OUT/$APP_NAME.app"
HELPER="$OUT/$LABEL.helper"

swift build -c release -Xswiftc -warnings-as-errors --product ProcessorMonitor
swift build -c release -Xswiftc -warnings-as-errors --product ProcessorMonitorHelper
BIN=$(swift build -c release -Xswiftc -warnings-as-errors --show-bin-path)

rm -rf "$APP" "$HELPER"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ProcessorMonitor" "$APP/Contents/MacOS/ProcessorMonitor"
cp "$BIN/ProcessorMonitorHelper" "$HELPER"
strip -S -x "$APP/Contents/MacOS/ProcessorMonitor" "$HELPER"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp scripts/uninstall.sh "$APP/Contents/Resources/uninstall.sh"
chmod 755 "$APP/Contents/Resources/uninstall.sh"

# Signing must be the last change to each binary.
codesign --force --sign - --options runtime --identifier "$LABEL.helper" "$HELPER"
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"
codesign --verify --strict "$HELPER"

echo "Built $APP ($VERSION, build $BUILD_NUMBER) and $HELPER"
