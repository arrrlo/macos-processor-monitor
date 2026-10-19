#!/bin/sh
# Removes macOS Processor Monitor completely. Run with sudo:
#   sudo "/Applications/macOS Processor Monitor.app/Contents/Resources/uninstall.sh"
LABEL=io.github.arrrlo.macos-processor-monitor

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo." >&2
    exit 1
fi

CONSOLE_USER=$(stat -f %Su /dev/console)
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$CONSOLE_USER" != "loginwindow" ]; then
    launchctl bootout "gui/$(id -u "$CONSOLE_USER")/$LABEL" 2>/dev/null
fi
launchctl bootout "system/$LABEL.helper" 2>/dev/null
pkill -x ProcessorMonitor 2>/dev/null

rm -f "/Library/LaunchAgents/$LABEL.plist" \
      "/Library/LaunchDaemons/$LABEL.helper.plist" \
      "/Library/PrivilegedHelperTools/$LABEL.helper"
rm -rf "/Applications/macOS Processor Monitor.app"
pkgutil --forget "$LABEL" >/dev/null 2>&1

echo "macOS Processor Monitor has been removed."
