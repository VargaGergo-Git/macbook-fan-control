# MacFanControl

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-lightgrey.svg)](https://www.apple.com/macos/)

**Free, open-source fan control for all MacBooks.**

MacFanControl is a lightweight menu bar app that lets you monitor fan speeds and temperatures, set manual fan RPM, or return fans to automatic control. It adapts at runtime to Intel and Apple Silicon MacBooks (M1–M5).

## Features

- Menu bar app with live fan RPM and readable temperature names
- Manual fan speed sliders for each fan
- One-click **Auto** (release to system control) and **Max** buttons
- Administrator password asked **once** to install a LaunchDaemon helper — sliders never trigger that dialog
- Runtime hardware probing — no hardcoded Mac model list
- Apple Silicon M3+ unlock support via adaptive `Ftst` sequence
- Diagnostic export for GitHub issue reports

## Requirements

- macOS 13 (Ventura) or later
- MacBook with AppleSMC (Intel 2015+ or any Apple Silicon MacBook)
- Administrator password **once** the first time you click **Allow fan control…** (the helper stays installed)

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
```

Then launch the binary next to `MacFanControlHelper`. With SwiftPM this is usually `.build/release/MacFanControl`. With Xcode’s toolchain it may be `.build/out/Products/Release/MacFanControl`. `./scripts/run.sh` locates either path.

To package a `.dmg` locally:

```bash
./scripts/build-dmg.sh
```

## Usage

1. Launch MacFanControl — a fan icon appears in the menu bar.
2. Click the icon to open the control panel.
3. Click **Allow fan control…**. macOS asks for your administrator password **once** and installs a small helper at `/usr/local/libexec/MacFanControlHelper`. Moving the slider, Auto, and Max will **not** ask again — including after you quit and reopen the app.
4. Click **Auto** to return fans to system control.
5. Click **Copy diagnostic info** to share hardware details when reporting issues.

**Safety:** When you quit the app or click **Auto**, all fans are released back to automatic control. The helper stays installed so the next launch does not ask for a password.

To remove the helper later:

```bash
./scripts/uninstall-helper.sh
```

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

Fan writes require administrator privileges. Click **Allow fan control…** once. That installs a LaunchDaemon (`com.macfancontrol.helper`) which stays running as root and only accepts commands from your user account over a local socket. Slider moves never show the password dialog. Remove it with `./scripts/uninstall-helper.sh`.

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
