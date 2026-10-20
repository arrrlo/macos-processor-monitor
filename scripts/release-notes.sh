#!/usr/bin/env bash
# Prints the CHANGELOG.md section of one version, for the GitHub release notes.
# Fails if the section is missing or empty.
#   usage: scripts/release-notes.sh <version>
set -euo pipefail

VERSION=${1:?usage: scripts/release-notes.sh <version>}
CHANGELOG="$(dirname "$0")/../CHANGELOG.md"

# The section runs from its "## [version]" heading to the next "## [" heading or the link references.
NOTES=$(awk -v heading="## [$VERSION]" '
    /^## \[/ || /^\[[^]]+\]: / { if (found) exit; found = index($0, heading) == 1; next }
    found
' "$CHANGELOG")

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    echo "CHANGELOG.md has no entries for $VERSION" >&2
    exit 1
fi
printf '%s\n' "$NOTES" | sed -e '/./,$!d'
