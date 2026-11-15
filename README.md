# DualPoint

**Independent cursor positions for every physical pointing device.**

DualPoint is a native macOS menu bar utility that remembers a separate cursor
position for each pointing device. Move your built-in trackpad and the pointer
returns to where you left it on the MacBook display; pick up your external mouse
and the pointer jumps back to its own last position on the external monitor.

DualPoint manages **one real macOS cursor**. It does not draw a second cursor.

> Status: early development. The application skeleton builds and runs; device
> management, cursor switching and the full interface are being implemented.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 13 Ventura or newer
- Input Monitoring permission (required to identify input devices)
- Command Line Tools (`xcode-select --install`) to build without Xcode

## Build

```bash
./Scripts/build-app.sh
open build/DualPoint.app
```

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/DualPointCore` | Device detection, cursor engine, display and persistence logic |
| `Sources/DualPoint` | SwiftUI menu bar application |
| `Scripts` | Build and icon-generation scripts |
| `Resources` | `Info.plist` and application icon |
| `Tests` | Unit tests for core logic |
| `docs` | Architecture, feasibility and testing documentation |

## License

Copyright © 2026 DualPoint. All rights reserved.
