# Changelog

## 1.0.0 — 07-18-26

Initial public release.

### Added

- Single-file `.bat` launcher with embedded Windows PowerShell 5.1 payload.
- Forced 64-bit PowerShell execution for 32-bit Acronis processes.
- Samsung 980 PRO discovery through `Get-PhysicalDisk`.
- Optional serial-number targeting.
- Multiple-drive evaluation with worst-severity result propagation.
- Wear and estimated remaining-life monitoring.
- Temperature thresholds.
- Uncorrected read/write error detection.
- Read, write, and flush latency thresholds.
- Health and operational-state evaluation.
- Full SMART-style attribute logging and CIM fallback diagnostics.
- Log rotation at 2 MB.
- Acronis-compatible exit codes: `0`, `1`, and `2`.

### Hardened

- Checks all payload-extraction failures, not only a specific exit code.
- Verifies the temporary PowerShell payload exists before execution.
- Uses environment variables for file paths to avoid quoting failures.
- Uses a per-run temporary filename and deletes only that run's payload.
- Avoids deleting payloads belonging to concurrent monitor runs.
- Treats reliability-counter failures as critical.
- Treats missing wear and temperature telemetry as warnings.
- Preserves fractional wear data and clamps remaining life to `0–100%`.
- Adds a critical latency threshold.
- Maps unknown health and operational states conservatively.
- Limits Acronis-visible findings while retaining complete log details.
