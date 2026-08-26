# SMC keys reference

MacFanControl communicates with the System Management Controller (SMC) through the `AppleSMC` IOKit service using the standard 80-byte `SMCParamStruct` protocol (same as [smcFanControl](https://github.com/hholtmann/smcFanControl)).

## Fan keys

| Key | Type | Access | Meaning |
|-----|------|--------|---------|
| `FNum` | ui8 | read | Number of fans |
| `F%dAc` | flt | read | Actual RPM |
| `F%dTg` | flt | read/write | Target RPM |
| `F%dMn` | flt | read | Minimum RPM (read-only on some M5 models) |
| `F%dMx` | flt | read | Maximum RPM |
| `F%dMd` | ui8 | read/write | Fan mode (Intel, M1–M4) |
| `F%dmd` | ui8 | read/write | Fan mode (M5+, lowercase variant) |
| `Ftst` | ui8 | read/write | Thermal manager test/unlock flag |

### Fan modes (`F%dMd` / `F%dmd`)

| Value | Mode |
|-------|------|
| 0 | Automatic |
| 1 | Manual |
| 3 | System (held by `thermalmonitord` on Apple Silicon) |

## Unlock sequence (Apple Silicon M3+)

When direct `mode = 1` write fails or does not stick:

1. Write `Ftst = 1` (if key exists)
2. Retry `mode = 1` until verified by re-read (~10 s timeout)
3. Write target RPM to `F%dTg`
4. On **Auto** or quit: set `mode = 0`, clear `Ftst = 0`

Credit: [macos-smc-fan research](https://github.com/agoodkind/macos-smc-fan), [macsfan](https://github.com/matejrondzik/macsfan), [Stats](https://github.com/exelban/stats).

## Temperature keys

Temperature sensors are discovered by probing `T000`–`T0FF` keys. Values are decoded based on reported data type (`sp78`, `fpe2`, `flt`).

## Value codecs

| Type | Description |
|------|-------------|
| `ui8` | Single unsigned byte |
| `flt` | IEEE 754 float (fan RPM) |
| `fpe2` | Fixed-point 14.2 |
| `sp78` | Signed fixed-point 7.8 (temperature) |
