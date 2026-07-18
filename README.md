# Acronis Drive Monitor — Samsung 980 PRO Support

Single-file Windows 10 batch monitor that adds Samsung 980 PRO NVMe health reporting to Acronis Drive Monitor by using the built-in Windows Storage PowerShell module.

## What it monitors

- Windows physical-disk `HealthStatus`
- `OperationalStatus`
- NVMe wear percentage and estimated remaining life
- Temperature
- Uncorrected read and write errors
- Maximum read, write, and flush latency
- Multiple Samsung 980 PRO drives
- Optional serial-number targeting
- Full SMART-style reliability-counter logging

## Requirements

- Windows 10
- Windows PowerShell 5.1
- Windows Storage PowerShell module
- Acronis Drive Monitor with custom-script support
- Administrator privileges recommended
- Samsung 980 PRO visible through `Get-PhysicalDisk`

The monitor deliberately launches 64-bit Windows PowerShell through `Sysnative` when Acronis starts it from a 32-bit process.

## Installation

1. Download `samsung_980_pro.bat`.
2. Copy it to the Acronis Drive Monitor script directory, commonly:

   ```text
   C:\Program Files (x86)\Acronis\DriveMonitor
   ```

3. Configure Acronis Drive Monitor to run the batch file as its custom disk-health script.
4. Run Acronis Drive Monitor with sufficient privileges to read storage reliability counters.

## Manual test

Open an elevated Windows PowerShell window and run:

```powershell
cd "C:\Program Files (x86)\Acronis\DriveMonitor"
.\samsung_980_pro.bat
$LASTEXITCODE
Get-Content "$env:TEMP\samsung_980_pro_monitor.log" -Tail 100
```

Expected output resembles:

```text
Status: OK
Description: 980 PRO [SN ...] Life: 98%, Temp: 43C, Health: Healthy, Op: OK
```

## Exit codes

| Exit code | Meaning | Acronis state |
|---:|---|---|
| `0` | Healthy | OK |
| `1` | Degraded, incomplete telemetry, or threshold warning | Warning |
| `2` | Critical condition or monitor failure | Failure |

The process exit code is authoritative. The `Status:` and `Description:` lines are human-readable diagnostic output.

## Default thresholds

| Metric | Warning | Critical |
|---|---:|---:|
| Remaining life | `<= 20%` | `<= 10%` |
| Temperature | `>= 70°C` | `>= 80°C` |
| Maximum latency | `>= 1,000 ms` | `>= 10,000 ms` |
| Uncorrected read/write errors | — | Any value above zero |

Edit these values inside the embedded PowerShell section of `samsung_980_pro.bat`:

```powershell
$WearWarnPct   = 20
$WearCritPct   = 10
$TempWarnC     = 70
$TempCritC     = 80
$LatencyWarnMs = 1000
$LatencyCritMs = 10000
```

## Multiple drives and serial-number targeting

By default, every physical disk whose `FriendlyName` contains `980 PRO` is checked. The worst result controls the final exit code.

To monitor one specific drive, edit the batch configuration near the top:

```bat
set "SAMSUNG_980_SERIAL=YOUR_SERIAL_NUMBER"
```

To list detected disks and serial numbers:

```powershell
Get-PhysicalDisk | Format-Table FriendlyName, SerialNumber, DeviceId, HealthStatus, OperationalStatus -AutoSize
```

## Logging

The monitor writes detailed diagnostics to:

```text
%TEMP%\samsung_980_pro_monitor.log
```

The log contains:

- PowerShell process architecture
- Detected physical disks
- Selected Samsung 980 PRO drives
- Disk identity and firmware data
- Every reliability-counter property exposed by Windows
- Derived wear and remaining-life values
- WMI/CIM fallback data
- Warning and critical escalation reasons

The active log rotates to `.old` after it exceeds 2 MB.

## How the single-file batch works

1. The batch launcher selects 64-bit Windows PowerShell.
2. It extracts the PowerShell payload below `:::PS_PAYLOAD_BEGIN:::` into a uniquely named temporary `.ps1` file.
3. It verifies extraction succeeded.
4. It runs the payload with Windows PowerShell 5.1.
5. It returns the PowerShell exit code to Acronis.
6. It deletes only its own temporary payload file.

## Troubleshooting

### Samsung 980 PRO not detected

Run:

```powershell
Get-PhysicalDisk | Format-List FriendlyName, Model, SerialNumber, BusType, DeviceId
```

Confirm the device name includes `980 PRO`. Some storage-controller or enclosure drivers may expose a different friendly name or hide NVMe telemetry.

### Storage module or cmdlet unavailable

Run:

```powershell
Import-Module Storage
Get-Command Get-PhysicalDisk
Get-Command Get-StorageReliabilityCounter
```

Use Windows PowerShell 5.1, not PowerShell 7, for the Windows Storage module workflow used by this project.

### Reliability counters unavailable

Run from an elevated Windows PowerShell prompt:

```powershell
$disk = Get-PhysicalDisk | Where-Object FriendlyName -Like '*980 PRO*' | Select-Object -First 1
Get-StorageReliabilityCounter -PhysicalDisk $disk | Format-List *
```

Possible causes include permissions, storage-controller drivers, RAID abstraction, USB/NVMe enclosures, or a Windows driver that does not expose the required counters.

### Acronis launches 32-bit PowerShell

The script automatically uses:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe
```

when available. This bridges a 32-bit Acronis process into 64-bit Windows PowerShell.

### Inspect the monitor log

```powershell
Get-Content "$env:TEMP\samsung_980_pro_monitor.log" -Tail 200
```

## Design and safety notes

- Missing wear or temperature telemetry is reported as a warning rather than silently treated as healthy.
- Failure to read reliability counters is critical because the monitor cannot validate NVMe health.
- Unknown health and operational states are not assumed healthy.
- Wear values are preserved to one decimal place and clamped to `0–100%` remaining.
- Temporary files use two random components and each run deletes only its own payload.
- Visible findings are limited while the complete details remain in the log.

## Scope

This project is specifically designed for Samsung 980 PRO drives exposed through the Windows 10 Storage subsystem. It is not a replacement for Samsung Magician, firmware updates, backups, or professional data-recovery procedures.

## License

MIT License. See `LICENSE`.
