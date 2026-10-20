# Changelog

All notable changes to macOS Processor Monitor are listed here. Every change adds a line under
**Unreleased**, and each release moves those lines under its version. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) (with an extra **Internal** section for
tooling and tests) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-10-20

### Added

- This changelog. Release notes on GitHub now list the changes in each version.
- GPU load and temperature in the menu bar (`CPU 23%  49°C   GPU 5%  42°C`) and in the menu. The
  temperature is read from the SMC's GPU sensors.
- A GPU row in the dashboard: GPU load with its renderer and tiler shares, GPU temperature, and the
  chip's name and GPU core count.
- The GPU's top 10 processes in the dashboard, by share of GPU time, for every user's processes.
- GPU activity in the dashboard: the last 30 GPU load readings as bars, the GPU's counterpart of the
  per-core occupancy (macOS has no per-core GPU load).

### Changed

- The dashboard's core bars stretch to fill the Occupancy card from edge to edge.
- The menu bar labels the processor "CPU" instead of showing a chip icon, matching "GPU":
  `CPU 23%  49°C   GPU 5%  42°C`.
- The dashboard has one row per processor (load, temperature, occupancy or activity, top 10
  processes), with every card the same height. It is wider and much shorter than before, and the
  process lists keep their numbers at the right edge.

### Fixed

- The release `.sha256` file names the installer without a `build/` prefix, so
  `shasum -a 256 -c` verifies it next to the downloaded `.pkg`.

### Internal

- The sampling engine keeps the last 30 GPU load readings for the dashboard, cleared on every start
  and interval change.
- The sampling engine measures the GPU's top processes while the dashboard is visible, from the
  GPU time the graphics driver records for each process. No helper is needed.
- The test that the CPU tick buffer is unmapped no longer fails when a parallel test maps memory at
  the freed address.
- The dashboard window test checks centring only on screens wide enough for the window, so it passes
  on the CI VM's narrow virtual display.
- Coverage of the GPU process list no longer depends on the GPU being busy during the tests (CI has
  no GPU).

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

[Unreleased]: https://github.com/arrrlo/macos-processor-monitor/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/arrrlo/macos-processor-monitor/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/arrrlo/macos-processor-monitor/releases/tag/v1.0.0
