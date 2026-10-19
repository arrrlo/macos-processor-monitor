#!/usr/bin/env bash
# Measures the running app's average CPU usage and memory over a period (default 300 s).
# Leave the menu and dashboard closed for the idle figure.
#   usage: scripts/measure-overhead.sh [seconds]
set -euo pipefail

DURATION=${1:-300}
PID=$(pgrep -x ProcessorMonitor || true)
if [[ -z "$PID" ]]; then
    echo "ProcessorMonitor is not running" >&2
    exit 1
fi

# ps prints CPU time as [[dd-]hh:]mm:ss.cc
cpu_seconds() {
    ps -o cputime= -p "$1" | awk -F'[:-]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

START=$(cpu_seconds "$PID")
sleep "$DURATION"
END=$(cpu_seconds "$PID")

RSS_KB=$(ps -o rss= -p "$PID" | tr -d ' ')
FOOTPRINT=$(footprint -p "$PID" 2>/dev/null | awk '/Footprint:/ { print $2, $3; exit }' || true)
awk -v start="$START" -v end="$END" -v duration="$DURATION" -v rss="$RSS_KB" -v footprint="$FOOTPRINT" 'BEGIN {
    printf "CPU: %.3f s over %d s = %.3f%% average\n", end - start, duration, (end - start) / duration * 100
    printf "Resident memory: %.1f MB\n", rss / 1024
    if (footprint != "") printf "Physical footprint: %s\n", footprint
}'
if pgrep -f "PrivilegedHelperTools/io.github.arrrlo.macos-processor-monitor.helper" > /dev/null; then
    echo "Helper: running"
else
    echo "Helper: not running"
fi
