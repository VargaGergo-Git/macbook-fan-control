# MacFanControl

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-lightgrey.svg)](https://www.apple.com/macos/)

**Free, open-source fan control for all MacBooks.**

MacFanControl is a lightweight menu bar app that lets you monitor fan speeds and temperatures, set manual fan RPM, or return fans to automatic control. It adapts at runtime to Intel and Apple Silicon MacBooks (M1–M5).

On Apple Silicon you cannot overclock or raise TDP. The useful boost is spinning the fan earlier so firmware can hold clocks. **Quiet**, **Balanced**, and **Performance** do that with chassis-aware ramps for MacBook Air and MacBook Pro.

## Features

- Polished menu-bar panel with live die temperature, fan RPM, an **8-minute chart**, and thermal-pressure chips
- Chassis detection for **MacBook Air** and **MacBook Pro** — Quiet / Balanced / Performance use different °C ramps and soft RPM ceilings on thin Air machines
- Presets: **Auto**, **Quiet**, **Balanced**, **Performance**, and **Max**, plus a slider for a fixed RPM
- Thermal-pressure chip from `thermald` (`com.apple.system.thermalpressurelevel`) — Nominal / Moderate / Heavy — more useful than `ProcessInfo.thermalState` on Apple Silicon
- Temperature list shows the hottest available sensors (CPU / GPU when present, otherwise System / Storage / Battery / Wi-Fi — works on Airs without discrete GPU keys)
- Live **battery** card: charge percent, charging vs on-battery, pack watts, adapter watts vs rated limit, system load, voltage/current, and time to full/empty (IOKit `AppleSmartBattery`, no extra password)
- Administrator password asked **once** to install a LaunchDaemon helper — sliders and presets never trigger that dialog
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
bash scripts/run.sh
```

`scripts/run.sh` builds both binaries, ensures the helper sits next to the app, and launches it. Manual build:

```bash
swift build -c release
```

Then launch the binary next to `MacFanControlHelper`. With SwiftPM this is usually `.build/release/MacFanControl`. With Xcode’s toolchain it may be `.build/out/Products/Release/MacFanControl`. `bash scripts/run.sh` locates either path.

To package a `.dmg` locally:

```bash
bash scripts/build-dmg.sh
```

## Usage

1. Launch MacFanControl — a fan icon appears in the menu bar.
2. Click the icon to open the control panel.
3. Click **Allow fan control…**. macOS asks for your administrator password **once** and installs a small helper at `/usr/local/libexec/MacFanControlHelper`. Moving the slider, Auto, Quiet, Balanced, Performance, and Max will **not** ask again — including after you quit and reopen the app.
4. Choose a preset:
   - **Auto** — Apple’s quiet-first curve (fans released to firmware).
   - **Quiet** — soft cabin; ramps late and caps below absolute max on Air.
   - **Balanced** — daily sweet spot for compile/browser load on Air and base Pro.
   - **Performance** — cools earlier so firmware can hold clocks. On Air it starts sooner than on Pro because thin chassis climb faster. It cannot raise package power.
   - **Max** — hold the hardware maximum RPM.
5. Drag the slider to override to a fixed RPM (never below that fan’s `F0Mn` minimum).
6. The **Power** section shows charge rate, adapter watts, and time remaining. It is read-only and does not need the helper.
7. Click **Copy diagnostic info** to share hardware details when reporting issues.

**Safety:** When you quit the app or click **Auto**, all fans are released back to automatic control. The helper stays installed so the next launch does not ask for a password.

To remove the helper later:

```bash
bash scripts/uninstall-helper.sh
```

## Compatibility

| Generation | Status |
|------------|--------|
| Intel MacBook (2015–2020) | Supported — direct SMC mode write |
| Apple Silicon MacBook Air (M1–M4) | Supported — Quiet/Balanced tuned for thin chassis |
| Apple Silicon MacBook Pro M1/M2 | Supported — root required for writes |
| Apple Silicon MacBook Pro M3/M4 | Supported — `Ftst` unlock when needed |
| Apple Silicon M5+ | Supported — runtime `F%dmd` key probe |

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the community test matrix and [docs/SMC-KEYS.md](docs/SMC-KEYS.md) for SMC key documentation.

## Security note

Official releases are ad-hoc signed. If macOS blocks the app:

1. Right-click the app → **Open**, or
2. Build from source yourself with `swift build`

Fan writes require administrator privileges. Click **Allow fan control…** once. That installs a LaunchDaemon (`com.macfancontrol.helper`) which stays running as root and only accepts commands from your user account over a local socket. Slider moves never show the password dialog. Remove it with `bash scripts/uninstall-helper.sh`.

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
