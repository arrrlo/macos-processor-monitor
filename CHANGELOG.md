# Changelog

All notable changes to macOS Processor Monitor are listed here. Every change adds a line under
**Unreleased**, and each release moves those lines under its version. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) (with an extra **Internal** section for
tooling and tests) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- This changelog. Release notes on GitHub now list the changes in each version.
- GPU load in the menu bar (`23%  49°C   GPU 5%`) and in the menu.

### Changed

- The dashboard's core bars stretch to fill the Occupancy card from edge to edge.

### Fixed

- The release `.sha256` file names the installer without a `build/` prefix, so
  `shasum -a 256 -c` verifies it next to the downloaded `.pkg`.

## [1.0.0] - 2026-10-19

### Added

- Menu bar item with the current processor load and temperature, e.g. `23%  49°C`.
- Processor load with its user / system / idle split.
- Occupancy of every core, grouped by core cluster, with cluster names read from the chip.
- Processor temperature: the average and maximum of the chip's die sensors.
- Top 10 processes by CPU usage, system-wide, with app names and icons. A root helper, started on
  demand by launchd, reads other users' processes. Without it the list falls back to your own processes.
- Dashboard window with all of the above, plus a per-core chart.
- Starts at login, with a refresh interval of 1, 2 or 5 seconds.
- Installer package (`.pkg`) built and published by GitHub Actions.

[Unreleased]: https://github.com/arrrlo/macos-processor-monitor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/arrrlo/macos-processor-monitor/releases/tag/v1.0.0
