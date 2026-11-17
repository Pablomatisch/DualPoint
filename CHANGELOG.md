# Changelog

All notable changes to DualPoint are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-17

First public release. Built from `main` at `8e1c333`.

### Added

- Native macOS menu bar application with no Dock icon.
- Per-device cursor positions saved as display-relative anchors.
- Automatic switching between the built-in trackpad, mice and external trackpads.
- Display assignments and a live display map in Settings.
- Four-step setup assistant with a temporary handover test.
- Menu bar panel with quick device assignments and a switching toggle.
- Settings tabs for General, Devices, Activity and About.
- `DualPointDiagnose` command-line tool for hardware inspection.
- Dependency-free `DualPointSelfTest` executable (55 assertions).
- Architecture, permissions, design and testing documentation.
- MIT License for DualPoint's original code, documentation and artwork.
- DMG and ZIP release artifacts with SHA-256 checksums.

### Notes

- DualPoint manages one real system cursor. It does not draw a second pointer.
- Input Monitoring is required. Accessibility is only a fallback.
- This release is ad-hoc signed and not notarized.
- Real-hardware handover checks are listed as pending in `docs/TESTING.md`.

[1.0.0]: https://github.com/Pablomatisch/DualPoint/releases/tag/v1.0.0
