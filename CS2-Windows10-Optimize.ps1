#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Windows 10 desktop optimization for Counter-Strike 2 (CS2).
  Applies only documented / low-risk changes. Does NOT touch in-game settings,
  BIOS overclocks, NVIDIA Control Panel 3D settings, or security features.

.DESCRIPTION
  Safe, reversible baseline:
    - High Performance power plan, PCIe ASPM off, USB selective suspend off
    - Game DVR / Game Bar background capture off, Game Mode on
    - Optional HAGS on/off (A/B test; default: leave unchanged)
    - Optional Defender exclusions for the CS2 folder/process
    - NIC: EEE/Green/Wake/Power Saving/Selective Suspend off, RSS on
    - Optional NIC latency test mode: Interrupt Moderation + Flow Control off
    - TCP autotuning restored to normal, RSS enabled (no Nagle/NetworkThrottling tweaks)
    - Optional Fast Startup off
    - Optional per-exe fullscreen optimizations off
    - Optional Windows GPU preference = High performance for cs2.exe
    - Optional restore of Windows timer defaults (removes HPET/timer bcdedit tweaks)
    - Backups, restore point, transcript, and -Revert support

.PARAMETER Cs2Path
  CS2 install folder. Example:
  "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"
  If omitted, common Steam paths are searched.

.PARAMETER Apply
  Actually apply changes. Without this switch, the script performs a dry run.

.PARAMETER Revert
  Restore the latest backup created by this script.

.PARAMETER EnableHags
  Set HwSchMode = 2 (Hardware-accelerated GPU scheduling on). Reboot required.

.PARAMETER DisableHags
  Set HwSchMode = 1 (HAGS off). Reboot required.

.PARAMETER AddDefenderExclusions
  Add the CS2 folder and cs2.exe to Microsoft Defender exclusions.
  This is a security tradeoff; only the CS2 folder is excluded.

.PARAMETER TuneNicLatency
  Also disable NIC Interrupt Moderation and Flow Control. Test A/B; can increase CPU/DPC.

.PARAMETER DisableFastStartup
  Set HiberbootEnabled = 0. Not an FPS tweak; can improve driver stability.

.PARAMETER DisableFullscreenOptimizations
  Per-exe compatibility flag for cs2.exe. A/B test; may affect alt-tab/stability.

.PARAMETER RestoreTimerDefaults
  Remove useplatformclock / disabledynamictick / tscsyncpolicy / useplatformtick
  from the current boot entry. Use this if you previously disabled HPET/timers.

.PARAMETER SkipNic
  Do not change network adapter advanced properties.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -AddDefenderExclusions -RestoreTimerDefaults

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
#>

[CmdletBinding()]
param(
    [string]$Cs2Path,
    [switch]$Apply,
    [switch]$Revert,
    [switch]$EnableHags,
    [switch]$DisableHags,
    [switch]$AddDefenderExclusions,
    [switch]$TuneNicLatency,
    [switch]$DisableFastStartup,
    [switch]$DisableFullscreenOptimizations,
    [switch]$RestoreTimerDefaults,
    [switch]$SkipNic
)

$ErrorActionPreference = 'Continue'
$script:Stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop     = [Environment]::GetFolderPath('Desktop')
$script:LogPath     = Join-Path $script:Desktop "CS2-Optimize-$script:Stamp.log"
$script:BackupDir   = Join-Path $script:Desktop "CS2-Optimize-Backup-$script:Stamp"

Start-Transcript -Path $script:LogPath -Force | Out-Null

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegString {
    param([string]$Path, [string]$Name, [string]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Backup-RegKey {
    param([string]$Key)
    $safe = ($Key -replace '[:\\]', '_')
    $file = Join-Path $script:BackupDir "$safe.reg"
    & reg.exe export $Key $file /y 2>$null | Out-Null
}

function Find-Cs2Path {
    param([string]$Explicit)
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $candidates.Add($Explicit) }

    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Counter-Strike Global Offensive'))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Steam\steamapps\common\Counter-Strike Global Offensive'))
    }

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $candidates.Add((Join-Path $steam 'steamapps\common\Counter-Strike Global Offensive'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $content = Get-Content $vdf -Raw
            foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                $candidates.Add((Join-Path $p 'steamapps\common\Counter-Strike Global Offensive'))
            }
        }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'game\bin\win64\cs2.exe'))) {
            return (Resolve-Path $c).Path
        }
    }
    return $null
}

function Get-LatestBackup {
    Get-ChildItem -Path $script:Desktop -Directory -Filter 'CS2-Optimize-Backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: latest backup'

    $backup = Get-LatestBackup
    if (-not $backup) {
        Write-Err 'No CS2-Optimize backup folder found on Desktop.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Info "Using backup: $($backup.FullName)"

    Get-ChildItem -Path $backup.FullName -Filter '*.reg' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Info "Importing $($_.Name)"
        & reg.exe import $_.FullName 2>$null | Out-Null
    }

    $powerFile = Join-Path $backup.FullName 'power-scheme.txt'
    if (Test-Path $powerFile) {
        $oldScheme = (Get-Content $powerFile -Raw).Trim()
        if ($oldScheme) {
            & powercfg.exe /setactive $oldScheme 2>$null | Out-Null
            Write-Ok "Power scheme restored: $oldScheme"
        }
    }

    $nicFile = Join-Path $backup.FullName 'nic-backup.json'
    if (Test-Path $nicFile) {
        $nic = Get-Content $nicFile -Raw | ConvertFrom-Json
        foreach ($item in @($nic)) {
            Set-NetAdapterAdvancedProperty -Name $item.Name -DisplayName $item.DisplayName -DisplayValue $item.DisplayValue -ErrorAction SilentlyContinue
        }
        Write-Ok 'NIC advanced properties restored.'
    }

    $defFile = Join-Path $backup.FullName 'defender-backup.json'
    if (Test-Path $defFile) {
        $def = Get-Content $defFile -Raw | ConvertFrom-Json
        if ($def.Cs2Path) {
            Remove-MpPreference -ExclusionPath $def.Cs2Path -ErrorAction SilentlyContinue
        }
        Remove-MpPreference -ExclusionProcess 'cs2.exe' -ErrorAction SilentlyContinue
        if ($def.OriginalPaths) {
            foreach ($p in @($def.OriginalPaths)) {
                if ($p) { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
            }
        }
        if ($def.OriginalProcesses) {
            foreach ($p in @($def.OriginalProcesses)) {
                if ($p) { Add-MpPreference -ExclusionProcess $p -ErrorAction SilentlyContinue }
            }
        }
        Write-Ok 'Defender exclusions restored.'
    }

    Write-Ok 'Revert completed. Reboot recommended.'
    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------------------
# Dry run / validation
# ---------------------------------------------------------------------------
if ($EnableHags -and $DisableHags) {
    Write-Err 'Use either -EnableHags or -DisableHags, not both.'
    Stop-Transcript | Out-Null
    exit 1
}

if (-not $Apply) {
    Write-Step 'DRY RUN'
    Write-Info 'No changes were made. Re-run with -Apply to apply.'
    Write-Info 'Recommended first run: -Apply -AddDefenderExclusions -RestoreTimerDefaults'
    Write-Info 'Optional A/B tests: -EnableHags OR -DisableHags, -TuneNicLatency, -DisableFullscreenOptimizations'
    Write-Info "Log: $script:LogPath"
    Stop-Transcript | Out-Null
    exit 0
}

New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null

$cs2 = Find-Cs2Path -Explicit $Cs2Path
if ($cs2) {
    $cs2Exe = Join-Path $cs2 'game\bin\win64\cs2.exe'
    Write-Ok "CS2 path: $cs2"
} else {
    $cs2Exe = $null
    Write-Warn 'CS2 path not found. Defender/FSO/GPU preference steps will be skipped.'
}

# ---------------------------------------------------------------------------
# Restore point + backups
# ---------------------------------------------------------------------------
Write-Step 'Restore point and backups'
try {
    Checkpoint-Computer -Description "CS2 Optimize $script:Stamp" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    Write-Ok 'System restore point created.'
} catch {
    Write-Warn "Restore point could not be created: $($_.Exception.Message)"
}

$keys = @(
    'HKCU\System\GameConfigStore',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR',
    'HKCU\Software\Microsoft\GameBar',
    'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers',
    'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power',
    'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
    'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
)
foreach ($k in $keys) { Backup-RegKey $k }

$currentScheme = (& powercfg.exe /getactivescheme) -join ' '
$schemeGuid = ([regex]::Match($currentScheme, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})')).Value
if ($schemeGuid) {
    Set-Content -Path (Join-Path $script:BackupDir 'power-scheme.txt') -Value $schemeGuid
    Write-Ok "Active power scheme saved: $schemeGuid"
}

# ---------------------------------------------------------------------------
# Power
# ---------------------------------------------------------------------------
Write-Step 'Power plan: High Performance + low-latency PCIe/USB'
& powercfg.exe /setactive SCHEME_MIN 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
& powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
Write-Ok 'High Performance, PCIe ASPM off, USB selective suspend off.'

# ---------------------------------------------------------------------------
# Game DVR / Game Bar / Game Mode
# ---------------------------------------------------------------------------
Write-Step 'Game DVR / Game Bar / Game Mode'
Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
Write-Ok 'Game DVR capture off; Game Mode on.'

# ---------------------------------------------------------------------------
# HAGS (optional)
# ---------------------------------------------------------------------------
Write-Step 'Hardware-accelerated GPU scheduling'
if ($EnableHags) {
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    Write-Ok 'HAGS enabled. Reboot required.'
} elseif ($DisableHags) {
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1
    Write-Ok 'HAGS disabled. Reboot required.'
} else {
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
    Write-Info "HAGS unchanged. Current HwSchMode: $hags"
}

# ---------------------------------------------------------------------------
# Fast Startup (optional)
# ---------------------------------------------------------------------------
if ($DisableFastStartup) {
    Write-Step 'Fast Startup'
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Write-Ok 'Fast Startup disabled.'
}

# ---------------------------------------------------------------------------
# Per-exe settings (optional)
# ---------------------------------------------------------------------------
if ($cs2Exe) {
    if ($DisableFullscreenOptimizations) {
        Write-Step 'Fullscreen Optimizations (cs2.exe)'
        Set-RegString 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' $cs2Exe '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Write-Ok 'Fullscreen optimizations disabled for cs2.exe. A/B test.'
    }

    Write-Step 'Windows GPU preference (cs2.exe)'
    Set-RegString 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $cs2Exe 'GpuPreference=2;'
    Write-Ok 'cs2.exe set to High performance in Windows Graphics settings.'
}

# ---------------------------------------------------------------------------
# Defender exclusions (optional)
# ---------------------------------------------------------------------------
if ($AddDefenderExclusions) {
    Write-Step 'Defender exclusions'
    if ($cs2) {
        $mp = Get-MpPreference
        $defBackup = [ordered]@{
            Cs2Path          = $cs2
            OriginalPaths    = @($mp.ExclusionPath)
            OriginalProcesses = @($mp.ExclusionProcess)
        }
        $defBackup | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $script:BackupDir 'defender-backup.json')
        Add-MpPreference -ExclusionPath $cs2 -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess 'cs2.exe' -ErrorAction SilentlyContinue
        Write-Ok 'CS2 folder and cs2.exe excluded. Real-time protection remains on.'
    } else {
        Write-Warn 'CS2 path not found; Defender exclusions skipped.'
    }
}

# ---------------------------------------------------------------------------
# NIC advanced properties
# ---------------------------------------------------------------------------
if (-not $SkipNic) {
    Write-Step 'Network adapter'
    $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        Select-Object -First 1

    if (-not $adapter) {
        Write-Warn 'No active physical adapter found. NIC changes skipped.'
    } else {
        Write-Info "Adapter: $($adapter.Name) / $($adapter.InterfaceDescription)"
        $props = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue

        $saveProps = $props | Where-Object {
            $_.DisplayName -match 'Energy.?Efficient Ethernet|Green Ethernet|Wake on Magic Packet|Wake on Pattern|Power Saving Mode|Selective Suspend|Ultra Low Power|Gigabit Lite|Interrupt Moderation|Flow Control|Receive Side Scaling'
        } | Select-Object Name, DisplayName, DisplayValue, RegistryKeyword

        $saveProps | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $script:BackupDir 'nic-backup.json')

        $disablePattern = 'Energy.?Efficient Ethernet|Green Ethernet|Wake on Magic Packet|Wake on Pattern|Power Saving Mode|Selective Suspend|Ultra Low Power|Gigabit Lite'
        foreach ($p in ($props | Where-Object { $_.DisplayName -match $disablePattern })) {
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $p.DisplayName -DisplayValue 'Disabled' -ErrorAction Stop
                Write-Ok "$($p.DisplayName) = Disabled"
            } catch {
                Write-Warn "$($p.DisplayName) could not be changed: $($_.Exception.Message)"
            }
        }

        $rss = $props | Where-Object { $_.DisplayName -match '^Receive Side Scaling' } | Select-Object -First 1
        if ($rss) {
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $rss.DisplayName -DisplayValue 'Enabled' -ErrorAction Stop
                Write-Ok 'Receive Side Scaling = Enabled'
            } catch {
                Write-Warn "RSS could not be enabled: $($_.Exception.Message)"
            }
        }

        if ($TuneNicLatency) {
            Write-Warn 'NIC latency test mode: Interrupt Moderation / Flow Control disabled. A/B test.'
            foreach ($name in @('Interrupt Moderation', 'Flow Control')) {
                $p = $props | Where-Object { $_.DisplayName -eq $name } | Select-Object -First 1
                if ($p) {
                    try {
                        Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $p.DisplayName -DisplayValue 'Disabled' -ErrorAction Stop
                        Write-Ok "$name = Disabled"
                    } catch {
                        Write-Warn "$name could not be changed: $($_.Exception.Message)"
                    }
                }
            }
        }

        try {
            Disable-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
            Write-Ok 'Adapter power management disabled.'
        } catch {
            Write-Warn "Adapter power management could not be disabled: $($_.Exception.Message)"
        }
    }

    Write-Step 'TCP global settings'
    & netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
    & netsh.exe int tcp set global rss=enabled 2>$null | Out-Null
    Write-Ok 'TCP autotuning = normal; RSS = enabled. No Nagle/NetworkThrottling changes.'
}

# ---------------------------------------------------------------------------
# Timer defaults (optional)
# ---------------------------------------------------------------------------
if ($RestoreTimerDefaults) {
    Write-Step 'Restore Windows timer defaults'
    & bcdedit.exe /export (Join-Path $script:BackupDir 'bcd-backup') 2>$null | Out-Null
    foreach ($v in @('useplatformclock', 'disabledynamictick', 'tscsyncpolicy', 'useplatformtick')) {
        & bcdedit.exe /deletevalue $v 2>$null | Out-Null
    }
    Write-Ok 'Timer BCD tweaks removed. Reboot required.'
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Step 'Current status'
& powercfg.exe /getactivescheme
$hagsNow = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
Write-Info "HwSchMode: $hagsNow"

$gdvr = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
Write-Info "GameDVR_Enabled: $gdvr"

$mpNow = Get-MpPreference
Write-Info "Defender exclusion paths: $((@($mpNow.ExclusionPath) -join '; '))"

Write-Step 'Startup commands (review manually; nothing disabled)'
Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
    Select-Object Name, Command, Location |
    Format-Table -AutoSize

Write-Step 'Done'
Write-Ok "Backup: $script:BackupDir"
Write-Ok "Log: $script:LogPath"
Write-Warn 'Reboot required for power, HAGS, Fast Startup, timer and per-exe changes.'
Write-Info 'Revert: run the same script with -Revert.'
Write-Info 'BIOS/CPU/RAM/GPU overclock and NVIDIA Control Panel settings are NOT changed by this script.'

Stop-Transcript | Out-Null
