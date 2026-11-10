#Requires -RunAsAdministrator
<#
  CS2 Windows 10 Desktop One-Click Baseline
  -----------------------------------------
  Safe, documented, low-risk Windows-side changes only.
  It does NOT touch in-game settings, BIOS overclocks, or NVIDIA Control Panel.

  Run (PowerShell as Administrator):
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Desktop-OneClick.ps1

  Optional:
    -Cs2Path "D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive"
    -EnableHags        (A/B test; reboot required)
    -DisableHags       (A/B test; reboot required)
    -SkipDefender      (do not add CS2 Defender exclusions)
    -SkipNic           (do not touch NIC advanced properties)
    -DisableFastStartup
    -DisableFSO        (per-exe fullscreen optimizations off; A/B test)
    -KeepTimerTweaks   (do not remove HPET/timer bcdedit values)
    -Force             (skip confirmation)

  A restore point and a Desktop backup folder are created.
  Test with CapFrameX before/after; keep only changes that help.
#>

[CmdletBinding()]
param(
    [string]$Cs2Path,
    [switch]$EnableHags,
    [switch]$DisableHags,
    [switch]$SkipDefender,
    [switch]$SkipNic,
    [switch]$DisableFastStartup,
    [switch]$DisableFSO,
    [switch]$KeepTimerTweaks,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$desktop = [Environment]::GetFolderPath('Desktop')
$backup  = Join-Path $desktop "CS2-Optimize-Backup-$stamp"
$log     = Join-Path $desktop "CS2-Optimize-$stamp.log"

Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop

Start-Transcript -Path $log -Force | Out-Null

# Cikti yardimcilari ortak modulden gelir.
function Say  { param($m) Write-Info $m }
function Good { param($m) Write-Ok $m }
function Warn { param($m) Write-Warn $m }
function Bad  { param($m) Write-Err $m }

function Set-Dword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-String {
    param([string]$Path, [string]$Name, [string]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Find-CS2 {
    param([string]$Explicit)
    $paths = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $paths.Add($Explicit) }
    if (${env:ProgramFiles(x86)}) { $paths.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Counter-Strike Global Offensive')) }
    if ($env:ProgramFiles) { $paths.Add((Join-Path $env:ProgramFiles 'Steam\steamapps\common\Counter-Strike Global Offensive')) }

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $paths.Add((Join-Path $steam 'steamapps\common\Counter-Strike Global Offensive'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                $paths.Add((Join-Path $p 'steamapps\common\Counter-Strike Global Offensive'))
            }
        }
    }

    foreach ($p in $paths) {
        if ($p -and (Test-Path (Join-Path $p 'game\bin\win64\cs2.exe'))) {
            return (Resolve-Path $p).Path
        }
    }
    return $null
}

if ($EnableHags -and $DisableHags) {
    Bad 'Use either -EnableHags or -DisableHags, not both.'
    Stop-Transcript | Out-Null
    exit 1
}

if (-not $Force) {
    Write-Host ''
    Write-Host 'CS2 Windows 10 Desktop Baseline' -ForegroundColor Cyan
    Write-Host 'This will change: power plan, GameDVR/GameBar, NIC power saving,'
    Write-Host 'Defender exclusions, and optionally HAGS/FSO/timer defaults.'
    Write-Host 'It will NOT change in-game settings, BIOS, or NVIDIA Control Panel.'
    Write-Host ''
    if ((Read-Host 'Devam etmek icin E yaz') -ne 'E') {
        Say 'Cancelled.'
        Stop-Transcript | Out-Null
        exit 0
    }
}

New-Item -ItemType Directory -Path $backup -Force | Out-Null

$cs2 = Find-CS2 -Explicit $Cs2Path
if ($cs2) {
    $cs2Exe = Join-Path $cs2 'game\bin\win64\cs2.exe'
    Good "CS2: $cs2"
} else {
    $cs2Exe = $null
    Warn 'CS2 path not found. Defender/FSO/GPU preference steps will be skipped.'
}

# Restore point
try {
    Checkpoint-Computer -Description "CS2 Optimize $stamp" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    Good 'Restore point created.'
} catch {
    Warn "Restore point failed: $($_.Exception.Message)"
}

# Registry backups
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
foreach ($k in $keys) { Backup-RegKey -Key $k -BackupDir $backup | Out-Null }
Good "Registry backup: $backup"

# Power plan
Say 'Setting High Performance, PCIe ASPM off, USB selective suspend off...'
& powercfg.exe /setactive SCHEME_MIN 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
& powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
Good 'Power settings applied.'

# GameDVR / GameBar / Game Mode
Say 'Disabling GameDVR background capture; enabling Game Mode...'
Set-Dword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
Set-Dword 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
Set-Dword 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
Good 'GameDVR off; Game Mode on.'

# Optional HAGS
if ($EnableHags) {
    Set-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    Good 'HAGS enabled (reboot).'
} elseif ($DisableHags) {
    Set-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1
    Good 'HAGS disabled (reboot).'
} else {
    $h = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
    Say "HAGS unchanged (HwSchMode=$h). Test both values if needed."
}

# Optional Fast Startup
if ($DisableFastStartup) {
    Set-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Good 'Fast Startup disabled.'
}

# Optional per-exe settings
if ($cs2Exe) {
    if ($DisableFSO) {
        Set-String 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' $cs2Exe '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Good 'Fullscreen optimizations disabled for cs2.exe (A/B test).'
    }
    Set-String 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $cs2Exe 'GpuPreference=2;'
    Good 'cs2.exe GPU preference: High performance.'
}

# Defender exclusions
if (-not $SkipDefender) {
    if ($cs2) {
        $mp = Get-MpPreference
        [ordered]@{
            Cs2Path = $cs2
            OriginalPaths = @($mp.ExclusionPath)
            OriginalProcesses = @($mp.ExclusionProcess)
        } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $backup 'defender-backup.json')
        Add-MpPreference -ExclusionPath $cs2 -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess 'cs2.exe' -ErrorAction SilentlyContinue
        Good 'CS2 folder/process excluded from Defender. Real-time protection stays on.'
    } else {
        Warn 'CS2 path missing; Defender exclusions skipped.'
    }
}

# NIC
if (-not $SkipNic) {
    $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
    if ($adapter) {
        Say "NIC: $($adapter.Name)"
        $props = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
        $props | Where-Object {
            $_.DisplayName -match 'Energy.?Efficient Ethernet|Green Ethernet|Wake on Magic Packet|Wake on Pattern|Power Saving Mode|Selective Suspend|Ultra Low Power|Gigabit Lite'
        } | Select-Object Name, DisplayName, DisplayValue | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $backup 'nic-backup.json')

        foreach ($p in ($props | Where-Object {
            $_.DisplayName -match 'Energy.?Efficient Ethernet|Green Ethernet|Wake on Magic Packet|Wake on Pattern|Power Saving Mode|Selective Suspend|Ultra Low Power|Gigabit Lite'
        })) {
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $p.DisplayName -DisplayValue 'Disabled' -ErrorAction Stop
                Good "$($p.DisplayName) = Disabled"
            } catch {
                Warn "$($p.DisplayName) skipped: $($_.Exception.Message)"
            }
        }

        $rss = $props | Where-Object { $_.DisplayName -match '^Receive Side Scaling' } | Select-Object -First 1
        if ($rss) {
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $rss.DisplayName -DisplayValue 'Enabled' -ErrorAction Stop
                Good 'RSS = Enabled'
            } catch { Warn 'RSS could not be set.' }
        }

        try { Disable-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop; Good 'NIC power management disabled.' } catch { Warn 'NIC power management skipped.' }
    } else {
        Warn 'No active physical NIC found.'
    }

    & netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
    & netsh.exe int tcp set global rss=enabled 2>$null | Out-Null
    Good 'TCP autotuning=normal; RSS=enabled.'
}

# Timer defaults
if (-not $KeepTimerTweaks) {
    Say 'Removing HPET/timer bcdedit tweaks (restoring Windows defaults)...'
    & bcdedit.exe /export (Join-Path $backup 'bcd-backup') 2>$null | Out-Null
    foreach ($v in @('useplatformclock', 'disabledynamictick', 'tscsyncpolicy', 'useplatformtick')) {
        & bcdedit.exe /deletevalue $v 2>$null | Out-Null
    }
    Good 'Timer BCD values removed. Reboot required.'
}

# Report
Write-Host ''
Say 'Current status:'
& powercfg.exe /getactivescheme
$h = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
Say "HwSchMode: $h"
$g = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
Say "GameDVR_Enabled: $g"
Say "Backup: $backup"
Say "Log: $log"
Write-Host ''
Warn 'Reboot required for power, HAGS, timer, Fast Startup and per-exe changes.'
Warn 'BIOS/CPU/RAM/GPU overclock and NVIDIA Control Panel are NOT changed by this script.'
Warn 'Test with CapFrameX before/after. Revert by importing the .reg files from the backup folder or using the restore point.'

Stop-Transcript | Out-Null
