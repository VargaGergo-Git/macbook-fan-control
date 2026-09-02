# Compatibility matrix

MacFanControl uses runtime SMC probing instead of a hardcoded model list. This document tracks known behavior by MacBook generation.

## Chassis notes

| Chassis | Quiet | Balanced | Performance |
|---------|-------|----------|-------------|
| MacBook Air | Late ramp, soft RPM ceiling | Daily default | Starts earlier (~60 °C) because thin chassis climb fast |
| MacBook Pro | Soft but higher ceiling | Daily default | 65→85 °C ramp to full max |
| Other / Intel | Conservative middle | Daily default | Pro-like performance ramp |

Single-fan Airs and base Pros use the same UI; copy and curve math adapt to fan count and model id (`hw.model`).

## Expected behavior

| Generation | Fan count | Mode key | Ftst unlock | Notes |
|------------|-----------|----------|-------------|-------|
| Intel MacBook (2015–2020) | 1–2 | `F%dMd` | Not used | Direct manual mode write works |
| Apple Silicon MacBook Air (M1–M4) | 1 | `F%dMd` / `F%dmd` | Often on M3+ | Quiet/Balanced recommended for daily use |
| Apple Silicon MacBook Pro M1/M2 | 1–2 | `F%dMd` | Rarely needed | Root required for writes |
| Apple Silicon MacBook Pro M3/M4 | 1–2 | `F%dMd` | Often required | `thermalmonitord` may hold system mode |
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
