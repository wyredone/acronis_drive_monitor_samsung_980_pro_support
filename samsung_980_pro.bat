@echo off
setlocal EnableExtensions
rem ============================================================================
rem  Acronis Custom Script - Samsung 980 Pro NVMe Health Monitor (Windows 10)
rem  Exit codes: 0 = OK, 1 = Warning, 2+ = Critical (Acronis failure)
rem  Optional: set SAMSUNG_980_SERIAL below to pin one drive when multiple exist
rem  Logs full NVMe health attribute dump each run to %TEMP%\samsung_980_pro_monitor.log
rem ============================================================================

rem --- Optional serial filter (leave empty to check ALL matching 980 PROs) ---
set "SAMSUNG_980_SERIAL="

rem --- Debug log location ---
set "MON_LOG=%TEMP%\samsung_980_pro_monitor.log"

rem --- Use 64-bit PowerShell even if Acronis launches this as a 32-bit process
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

rem --- Extract embedded PowerShell payload (regex marker match from bottom up)
set "PS1=%TEMP%\samsung_980_pro_check_%RANDOM%_%RANDOM%.ps1"
set "MON_SELF=%~f0"
set "MON_PS1=%PS1%"
"%PSEXE%" -NoLogo -NoProfile -NonInteractive -Command ^
  "$self = Get-Content -LiteralPath $env:MON_SELF; $idx = -1; for ($i = $self.Count - 1; $i -ge 0; $i--) { if ($self[$i] -match '^:::PS_PAYLOAD_BEGIN:::\s*$') { $idx = $i; break } }; if ($idx -lt 0) { exit 3 }; $self[($idx+1)..($self.Count-1)] | Set-Content -LiteralPath $env:MON_PS1 -Encoding UTF8"
set "EXTRACT_RC=%ERRORLEVEL%"

rem --- Verify extraction completed successfully and produced the payload file ---
if not "%EXTRACT_RC%"=="0" (
    del /q "%PS1%" >nul 2>&1
    echo Status: Failure
    echo Description: Failed to extract monitor payload script. Exit code %EXTRACT_RC%.
    exit /b 2
)
if not exist "%PS1%" (
    echo Status: Failure
    echo Description: Monitor payload file was not created.
    exit /b 2
)

rem --- Run payload with 64-bit PowerShell; Bypass required for file execution
"%PSEXE%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" -SerialFilter "%SAMSUNG_980_SERIAL%" -LogPath "%MON_LOG%"
set "RC=%ERRORLEVEL%"

del /q "%PS1%" >nul 2>&1
exit /b %RC%

:::PS_PAYLOAD_BEGIN:::
param(
    [string]$SerialFilter = '',
    [string]$LogPath = "$env:TEMP\samsung_980_pro_monitor.log"
)

# ---------------- Thresholds (tune as needed) ----------------
$WearWarnPct      = 20    # remaining life % at/below = Warning
$WearCritPct      = 10    # remaining life % at/below = Critical
$TempWarnC        = 70    # composite temp C at/above = Warning
$TempCritC        = 80    # composite temp C at/above = Critical
$LatencyWarnMs    = 1000  # max read/write/flush latency ms at/above = Warning
$LatencyCritMs    = 10000 # max read/write/flush latency ms at/above = Critical
$MaxLogBytes      = 2MB   # log rotates when exceeding this size
$WarningOpStatus  = @('Degraded','Stressed')
$CriticalOpStatus = @('Predictive Failure','Lost Communication','No Contact','Error','Failed')
$HealthyOpStatus  = @('OK','Online')
# Exit codes: 0 OK, 1 Warning, 2 Critical

$script:Worst = 0
$Findings = New-Object System.Collections.Generic.List[string]
$SerialFilter = $SerialFilter.Trim()

# --- Log rotation ---
try {
    if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt $MaxLogBytes)) {
        Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.old') -Force
    }
} catch { }

function Write-Log {
    param([string]$Msg)
    try {
        Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'MM-dd-yy hh:mm:ss tt'), $Msg)
    } catch { }
}

function Escalate {
    param([int]$Level, [string]$Msg)
    if ($Level -gt $script:Worst) { $script:Worst = $Level }
    $Findings.Add($Msg)
    Write-Log ("Level {0}: {1}" -f $Level, $Msg)
}

function Write-AttributeDump {
    param($Disk, $Storage, [string]$Label)

    Write-Log "===== NVMe ATTRIBUTE DUMP: $Label ====="

    $diskProps = @(
        'FriendlyName','Model','SerialNumber','FirmwareVersion','BusType','MediaType',
        'Size','AllocatedSize','LogicalSectorSize','PhysicalSectorSize','SpindleSpeed',
        'HealthStatus','OperationalStatus','Usage','DeviceId','UniqueId'
    )
    foreach ($p in $diskProps) {
        try {
            $v = $Disk.$p
            if ($null -ne $v -and "$v" -ne '') {
                if ($p -eq 'Size' -or $p -eq 'AllocatedSize') {
                    $gb = [math]::Round($v / 1GB, 2)
                    Write-Log ("  Disk.{0} = {1} ({2} GB)" -f $p, $v, $gb)
                } else {
                    Write-Log ("  Disk.{0} = {1}" -f $p, ($v -join ','))
                }
            }
        } catch { }
    }

    if ($Storage) {
        $skip = @('PSComputerName','CimClass','CimInstanceProperties','CimSystemProperties',
                  'DeviceId','PassThroughClass','PassThroughIds','PassThroughNamespace','PassThroughServer')
        foreach ($prop in ($Storage | Get-Member -MemberType Property, NoteProperty | Sort-Object Name)) {
            $name = $prop.Name
            if ($skip -contains $name) { continue }
            try {
                $v = $Storage.$name
                if ($null -ne $v -and "$v" -ne '') {
                    Write-Log ("  SMART.{0} = {1}" -f $name, $v)
                }
            } catch { }
        }

        if ($null -ne $Storage.Wear) {
            $used = [math]::Round([double]$Storage.Wear, 1)
            $remaining = [math]::Max(0, [math]::Min(100, [math]::Round(100 - $used, 1)))
            Write-Log ("  Derived.PercentageUsed = {0}%" -f $used)
            Write-Log ("  Derived.RemainingLife = {0}%" -f $remaining)
        }
        if ($null -ne $Storage.PowerOnHours -and $Storage.PowerOnHours -gt 0) {
            Write-Log ("  Derived.PowerOnDays = {0}" -f [math]::Round($Storage.PowerOnHours / 24, 1))
        }
    } else {
        Write-Log "  (reliability counters unavailable - no SMART dump)"
    }

    try {
        $wmi = Get-CimInstance -Namespace root\microsoft\windows\storage -ClassName MSFT_StorageReliabilityCounter -ErrorAction Stop |
               Where-Object { $_.DeviceId -eq $Disk.DeviceId }
        if ($wmi) {
            foreach ($cp in $wmi.CimInstanceProperties) {
                if ($null -ne $cp.Value -and "$($cp.Value)" -ne '' -and $cp.Name -notin @('DeviceId','PassThroughClass','PassThroughIds','PassThroughNamespace','PassThroughServer','PSComputerName')) {
                    Write-Log ("  WMI.{0} = {1}" -f $cp.Name, $cp.Value)
                }
            }
        }
    } catch {
        Write-Log ("  WMI reliability query failed: {0}" -f $_.Exception.Message)
    }

    Write-Log "===== END ATTRIBUTE DUMP: $Label ====="
}

Write-Log "----- Run start (PID $PID, 64-bit: $([Environment]::Is64BitProcess)) -----"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Log "WARNING: Not running elevated; reliability counters may be unavailable."
}

try {
    Import-Module Storage -ErrorAction Stop
} catch {
    Write-Host 'Status: Failure'
    Write-Host "Description: Failed to load Windows Storage module: $($_.Exception.Message)"
    Write-Log "CRITICAL: Import-Module Storage failed: $($_.Exception.Message)"
    exit 2
}

try {
    $allDisks = @(Get-PhysicalDisk -ErrorAction Stop)
} catch {
    Write-Host 'Status: Failure'
    Write-Host "Description: Get-PhysicalDisk failed: $($_.Exception.Message)"
    Write-Log "CRITICAL: Get-PhysicalDisk failed: $($_.Exception.Message)"
    exit 2
}

foreach ($d in $allDisks) {
    Write-Log ("Detected disk: '{0}' SN='{1}' Health='{2}' OpStatus='{3}'" -f $d.FriendlyName, $d.SerialNumber, $d.HealthStatus, ($d.OperationalStatus -join ','))
}

$disks = @($allDisks | Where-Object { $_.FriendlyName -like '*980 PRO*' })

if ($SerialFilter) {
    $sf = $SerialFilter
    $disks = @($disks | Where-Object { $_.SerialNumber -and $_.SerialNumber.Trim() -eq $sf })
    if ($disks.Count -eq 0) {
        Write-Host 'Status: Failure'
        Write-Host "Description: No Samsung 980 PRO with serial '$sf' detected."
        Write-Log "CRITICAL: No disk matched serial filter '$sf'."
        exit 2
    }
}

if ($disks.Count -eq 0) {
    Write-Host 'Status: Failure'
    Write-Host 'Description: Samsung 980 Pro SSD not detected by OS.'
    Write-Log 'CRITICAL: No 980 PRO detected.'
    exit 2
}

if ($disks.Count -gt 1 -and -not $SerialFilter) {
    Write-Log ("NOTE: {0} matching 980 PRO drives found; evaluating all. Set SAMSUNG_980_SERIAL to pin one." -f $disks.Count)
}

$Summaries = New-Object System.Collections.Generic.List[string]

foreach ($disk in $disks) {
    $id = if ($disk.SerialNumber) { "SN " + $disk.SerialNumber.Trim() } else { "DeviceId " + $disk.DeviceId }
    $label = "980 PRO [$id]"

    $opStates = @($disk.OperationalStatus)
    foreach ($op in $opStates) {
        $opText = "$op"
        if ($CriticalOpStatus -contains $opText) {
            Escalate 2 "$label OperationalStatus is '$opText'."
        } elseif ($WarningOpStatus -contains $opText) {
            Escalate 1 "$label OperationalStatus is '$opText'."
        } elseif ($HealthyOpStatus -notcontains $opText) {
            Escalate 1 "$label OperationalStatus is unrecognized: '$opText'."
        }
    }

    switch ("$($disk.HealthStatus)") {
        'Healthy'   { }
        'Warning'   { Escalate 1 "$label HealthStatus is 'Warning'." }
        'Unhealthy' { Escalate 2 "$label HealthStatus is 'Unhealthy'." }
        default     { Escalate 1 "$label HealthStatus is unknown or unsupported: '$($disk.HealthStatus)'." }
    }

    $storage = $null
    try {
        $storage = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
    } catch {
        Escalate 2 "$label reliability counters unavailable: $($_.Exception.Message)"
    }

    Write-AttributeDump -Disk $disk -Storage $storage -Label $label

    $wearTxt = 'N/A'; $tempTxt = 'N/A'

    if ($storage) {
        if ($null -ne $storage.Wear) {
            $wearUsed = [math]::Round([double]$storage.Wear, 1)
            $remaining = [math]::Round(100 - $wearUsed, 1)
            if ($remaining -lt 0) { $remaining = 0 }
            if ($remaining -gt 100) { $remaining = 100 }
            $wearTxt = "$remaining%"
            if     ($remaining -le $WearCritPct) { Escalate 2 "$label remaining life $remaining% (critical <= $WearCritPct%)." }
            elseif ($remaining -le $WearWarnPct) { Escalate 1 "$label remaining life $remaining% (warning <= $WearWarnPct%)." }
        } else {
            Escalate 1 "$label wear counter is unavailable."
        }

        if ($null -ne $storage.Temperature -and $storage.Temperature -gt 0) {
            $t = [int]$storage.Temperature
            $tempTxt = "${t}C"
            if     ($t -ge $TempCritC) { Escalate 2 "$label temperature ${t}C (critical >= ${TempCritC}C)." }
            elseif ($t -ge $TempWarnC) { Escalate 1 "$label temperature ${t}C (warning >= ${TempWarnC}C)." }
        } else {
            Escalate 1 "$label temperature counter is unavailable."
        }

        if ($storage.ReadErrorsUncorrected -gt 0) {
            Escalate 2 "$label has $($storage.ReadErrorsUncorrected) uncorrected READ errors."
        }
        if ($storage.WriteErrorsUncorrected -gt 0) {
            Escalate 2 "$label has $($storage.WriteErrorsUncorrected) uncorrected WRITE errors."
        }

        foreach ($pair in @(
            @{Name='Read';  Val=$storage.ReadLatencyMax},
            @{Name='Write'; Val=$storage.WriteLatencyMax},
            @{Name='Flush'; Val=$storage.FlushLatencyMax}
        )) {
            if ($null -ne $pair.Val -and $pair.Val -ge $LatencyCritMs) {
                Escalate 2 ("$label {0} latency max {1}ms (critical >= {2}ms)." -f $pair.Name, $pair.Val, $LatencyCritMs)
            } elseif ($null -ne $pair.Val -and $pair.Val -ge $LatencyWarnMs) {
                Escalate 1 ("$label {0} latency max {1}ms (warning >= {2}ms)." -f $pair.Name, $pair.Val, $LatencyWarnMs)
            }
        }
    }

    $Summaries.Add("$label Life: $wearTxt, Temp: $tempTxt, Health: $($disk.HealthStatus), Op: $($opStates -join '/')")
}

$summary = $Summaries -join ' | '

switch ($script:Worst) {
    0 {
        Write-Host 'Status: OK'
        Write-Host "Description: $summary"
        Write-Log 'Result: OK (exit 0)'
        exit 0
    }
    1 {
        Write-Host 'Status: Warning'
        $visibleFindings = @($Findings | Select-Object -First 5)
        $suffix = if ($Findings.Count -gt 5) { ' Additional findings are in the log.' } else { '' }
        Write-Host "Description: $($visibleFindings -join ' ')$suffix $summary"
        Write-Log 'Result: WARNING (exit 1)'
        exit 1
    }
    default {
        Write-Host 'Status: Failure'
        $visibleFindings = @($Findings | Select-Object -First 5)
        $suffix = if ($Findings.Count -gt 5) { ' Additional findings are in the log.' } else { '' }
        Write-Host "Description: $($visibleFindings -join ' ')$suffix $summary"
        Write-Log 'Result: CRITICAL (exit 2)'
        exit 2
    }
}
