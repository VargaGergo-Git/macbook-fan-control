# Compatibility matrix

MacFanControl uses runtime SMC probing instead of a hardcoded model list. This document tracks known behavior by MacBook generation.

## Expected behavior

| Generation | Fan count | Mode key | Ftst unlock | Notes |
|------------|-----------|----------|-------------|-------|
| Intel MacBook (2015–2020) | 1–2 | `F%dMd` | Not used | Direct manual mode write works |
| Apple Silicon M1/M2 | 1–2 | `F%dMd` | Rarely needed | Root required for writes |
| Apple Silicon M3/M4 | 1–2 | `F%dMd` | Often required | `thermalmonitord` may hold system mode |
| Apple Silicon M5+ | 1–2 | `F%dmd` (lowercase) | Often required | Min RPM key may be read-only |

## Community test results

| Model | macOS | Read RPM | Manual control | Auto release | Reporter |
|-------|-------|----------|----------------|--------------|----------|
| _Add your results via PR_ | | | | | |

## Read-only mode

If SMC writes fail but reads succeed, the app shows fan RPM and temperatures in read-only mode with an explanatory status message.

## Reporting unsupported hardware

Use **Copy diagnostic info** in the app and open a GitHub Issue. Include:

- MacBook model year and chip
- macOS version
- Whether fans spin up when moving the slider
- Whether **Auto** restores normal behavior
