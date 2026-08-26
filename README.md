# MacFanControl

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-lightgrey.svg)](https://www.apple.com/macos/)

**Free, open-source fan control for all MacBooks.**

MacFanControl is a lightweight menu bar app that lets you monitor fan speeds and temperatures, set manual fan RPM, or return fans to automatic control. It adapts at runtime to Intel and Apple Silicon MacBooks (M1–M5).

## Features

- Menu bar app with live fan RPM and temperature readouts
- Manual fan speed sliders for each fan
- One-click **Auto** (release to system control) and **Max** buttons
- Runtime hardware probing — no hardcoded Mac model list
- Apple Silicon M3+ unlock support via adaptive `Ftst` sequence
- Diagnostic export for GitHub issue reports

## Requirements

- macOS 13 (Ventura) or later
- MacBook with AppleSMC (Intel 2015+ or any Apple Silicon MacBook)
- Administrator password when changing fan speeds

## Install

### Pre-built release (recommended)

Download the latest `.dmg` from [GitHub Releases](https://github.com/VargaGergo-Git/macbook-fan-control/releases).

Drag **MacFanControl** to Applications. On first launch, macOS Gatekeeper may warn that the app is unsigned — see [Security note](#security-note) below.

### Build from source

```bash
git clone https://github.com/VargaGergo-Git/macbook-fan-control.git
cd macbook-fan-control
chmod +x scripts/run.sh
./scripts/run.sh
```

`scripts/run.sh` builds both binaries, ensures the helper sits next to the app, and launches it. Manual build:

```bash
swift build -c release
.build/release/MacFanControl
```

This builds both `MacFanControl` and `MacFanControlHelper` in `.build/release/`. The helper must sit next to the main binary for fan speed changes to work.

To package a `.dmg` locally:

```bash
./scripts/build-dmg.sh
```

## Usage

1. Launch MacFanControl — a fan icon appears in the menu bar.
2. Click the icon to open the control panel.
3. Move a fan slider to set manual RPM — macOS prompts for your administrator password once per change.
4. Click **Auto** to return fans to system control.
5. Click **Copy diagnostic info** to share hardware details when reporting issues.

**Tip:** To avoid repeated password prompts, run with `sudo .build/release/MacFanControl` after building.

**Safety:** When you quit the app or click **Auto**, all fans are released back to automatic control.

## Compatibility

| Generation | Status |
|------------|--------|
| Intel MacBook (2015–2020) | Supported — direct SMC mode write |
| Apple Silicon M1/M2 | Supported — root required for writes |
| Apple Silicon M3/M4 | Supported — `Ftst` unlock when needed |
| Apple Silicon M5+ | Supported — runtime `F%dmd` key probe |

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the community test matrix and [docs/SMC-KEYS.md](docs/SMC-KEYS.md) for SMC key documentation.

## Security note

Official releases are ad-hoc signed. If macOS blocks the app:

1. Right-click the app → **Open**, or
2. Build from source yourself with `swift build`

Fan writes require administrator privileges — the same requirement as other open-source SMC fan tools.

## Prior art

This project builds on research and code from the macOS fan control community:

- [smcFanControl](https://github.com/hholtmann/smcFanControl)
- [macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [macsfan](https://github.com/matejrondzik/macsfan)
- [macfanctl](https://github.com/2dubu/macfanctl)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
