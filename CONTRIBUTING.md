# Contributing to MacFanControl

Thank you for helping improve fan control for MacBook owners.

## Reporting hardware issues

If fan control does not work on your MacBook:

1. Update to the latest release.
2. Open MacFanControl and click **Copy diagnostic info**.
3. Open a [GitHub Issue](https://github.com/VargaGergo-Git/macbook-fan-control/issues/new) and paste the diagnostic text.
4. Include your MacBook model (e.g. MacBook Pro 14" M3 Pro, 2023) and macOS version.

Do **not** include your serial number, username, or other personal data.

## Pull requests

1. Fork the repository and create a feature branch.
2. Keep changes focused — one concern per PR.
3. Run tests before submitting:

   ```bash
   swift test
   swift build -c release
   ```

4. Test on real Mac hardware when changing SMC or fan control logic.
5. Update [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) if you verify a new Mac model.

## Code structure

- `Sources/MacFanControlCore/` — SMC IOKit layer, fan controller, hardware probing
- `Sources/MacFanControl/` — SwiftUI menu bar app and views
- `Tests/MacFanControlTests/` — Unit tests for codecs and diagnostics

## SMC changes

Changes to unlock sequences or key probing must include:

- A comment referencing the hardware tested
- Notes in `docs/SMC-KEYS.md` if new keys or behavior are discovered
