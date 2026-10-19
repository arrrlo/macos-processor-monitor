#!/usr/bin/env bash
# Exports llvm-cov JSON for ALL test bundles of a package.
#
# SwiftPM's own codecov JSON (`swift test --show-codecov-path`) is generated from a single test
# bundle, so code that only another bundle links silently disappears from it. This merges every
# *.xctest bundle in the build products directory against the shared profdata.
#
# usage: export-coverage.sh <path printed by `swift test --show-codecov-path`> <output.json>
set -euo pipefail

codecov_dir=$(dirname "$1")
bin_dir=$(dirname "$codecov_dir")
output=$2

binaries=()
for bundle in "$bin_dir"/*.xctest; do
    name=$(basename "$bundle" .xctest)
    binaries+=("$bundle/Contents/MacOS/$name")
done
if [[ ${#binaries[@]} -eq 0 ]]; then
    echo "error: no test bundles in $bin_dir" >&2
    exit 2
fi

objects=()
for binary in "${binaries[@]:1}"; do
    objects+=(-object "$binary")
done

xcrun llvm-cov export -instr-profile "$codecov_dir/default.profdata" "${binaries[0]}" ${objects[@]+"${objects[@]}"} > "$output"
