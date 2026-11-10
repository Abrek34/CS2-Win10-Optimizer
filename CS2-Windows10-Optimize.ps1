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
    - Optional MPO disable, Storage Sense disable, background apps disable, system VRR toggle
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
  Also disable NIC Interrupt Moderation. Test A/B; lowers latency but raises CPU/DPC load.
  Flow Control is intentionally left ENABLED (disabling it can increase packet loss).

.PARAMETER DisableFastStartup
  Set HiberbootEnabled = 0. Not an FPS tweak; can improve driver stability.

.PARAMETER DisableFullscreenOptimizations
  Per-exe compatibility flag for cs2.exe. A/B test; may affect alt-tab/stability.

.PARAMETER RestoreTimerDefaults
  Remove useplatformclock / disabledynamictick / tscsyncpolicy / useplatformtick
  from the current boot entry. Use this if you previously disabled HPET/timers.

.PARAMETER SkipNic
  Do not change network adapter advanced properties.

.PARAMETER DisableMpo
  Disable Multi-Plane Overlay (DWM OverlayTestMode = 5). Optional; may reduce flicker/stutter.
  A/B test; reboot required.

.PARAMETER DisableStorageSense
  Disable Storage Sense automatic cleanup. Optional; avoids background disk I/O.

.PARAMETER DisableBackgroundApps
  Disable global background app access. Optional; reduces background CPU/memory usage.

.PARAMETER EnableSystemVrr
  Enable system-wide VRR optimization. Optional; only use on VRR-capable monitors.

.PARAMETER DisableSystemVrr
  Disable system-wide VRR optimization. Optional; A/B test.

.PARAMETER SetProcessorPerformance
  Processor performance mode: minimum/maximum state %100, core parking off,
  EPP 0 (Speed Shift), aggressive boost. Optional; raises idle power/heat.

.PARAMETER DisableIdleStates
  Disable OS-level idle suspend (IDLEDISABLE=1). Use only if BIOS C-states are
  NOT already disabled; do not combine both.

.PARAMETER DisableDiskIdle
  Disk idle timeout 0. Optional; affects the 240 GB SATA SSD power state.

.PARAMETER SetMmcssGameProfile
  MMCSS Games task: GPU Priority 8, Priority 6, Scheduling Category Medium,
  SFIO Priority High.
  NOT: Scheduling Category "High" YAPILMAZ - oyun thread'lerini Pro Audio
  bandina (23-26) sokup sistem thread'lerini starve ederek stutter uretebilir.
  Microsoft dokumantasina gore "GPU Priority" ve "SFIO Priority" sistem tarafindan
  kullanilmaz; Priority yalnizca "Medium" kategoride anlamlidir.

.PARAMETER DisablePowerThrottling
  PowerThrottlingOff = 1. Optional; stops EcoQoS throttling of game threads.

.PARAMETER SetSystemResponsiveness
  SystemResponsiveness = 10. Optional; do not set 0.

.PARAMETER DisablePagingExecutive
  DisablePagingExecutive = 1. Optional; keeps the kernel resident in RAM.

.PARAMETER DisableMouseAcceleration
  Disable Windows mouse acceleration (MouseSpeed/MouseThreshold = 0).
  Optional; CS2 raw input bypasses it, but it keeps other apps consistent.

.PARAMETER SetBestPerformance
  Visual effects = best performance, transparency off, menu/startup delays 0.
  Optional; mostly cosmetic.

.PARAMETER DisableInterruptModeration
  NIC Interrupt Moderation off. Optional; lowers latency but raises DPC/CPU load.

.PARAMETER DisableFlowControl
  NIC Flow Control off. Optional and risky: it can INCREASE packet loss when
  the link is saturated. Leave enabled unless a measurement proves otherwise.

.PARAMETER SetCs2Priority
  cs2.exe'ye kalici islem onceligi verir (IFEO PerfOptions CpuPriorityClass).
  Degerler: Normal (2), AboveNormal (6), High (3).
  NOT: 'High' bazi sistemlerde ses crackle ve stutter yapabilir; once AboveNormal
  ile olc. Steam launch option -high KULLANMA (CS2'de stutter/audio crackle
  yaptigi biliniyor). Degisiklikten sonra CS2'yi yeniden baslatmak gerekir.
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
    [switch]$SkipNic,
    [switch]$DisableMpo,
    [switch]$DisableStorageSense,
    [switch]$DisableBackgroundApps,
    [switch]$EnableSystemVrr,
    [switch]$DisableSystemVrr,
    [switch]$SetProcessorPerformance,
    [switch]$DisableIdleStates,
    [switch]$DisableDiskIdle,
    [switch]$SetMmcssGameProfile,
    [switch]$DisablePowerThrottling,
    [switch]$SetSystemResponsiveness,
    [switch]$DisablePagingExecutive,
    [switch]$DisableMouseAcceleration,
    [switch]$SetBestPerformance,
    [switch]$DisableInterruptModeration,
    [switch]$DisableFlowControl,
    [ValidateSet('Normal', 'AboveNormal', 'High')]
    [string]$SetCs2Priority
)

$ErrorActionPreference = 'Continue'
$script:Stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop     = [Environment]::GetFolderPath('Desktop')
$script:LogPath     = Join-Path $script:Desktop "CS2-Optimize-$script:Stamp.log"
$script:BackupDir   = Join-Path $script:Desktop "CS2-Optimize-Backup-$script:Stamp"

try {
    Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop
} catch {
    Write-Warning "CS2Optimizer.psm1 yuklenemedi: $($_.Exception.Message)"
}

# Modul bulunamazsa (tek dosya indirildiyse) minimum yardimcilar tanimlanir.
if (-not (Get-Command -Name 'Write-Info' -ErrorAction SilentlyContinue)) {
    Write-Warning 'CS2Optimizer.psm1 bulunamadi; minimal yardimcilar kullanilacak. Tam islev icin .psm1 dosyasini script ile ayni klasore koyun.'
    function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
    function Write-Info { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Gray }
    function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
    function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
    function Write-Err  { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }
}

Start-Transcript -Path $script:LogPath -Force | Out-Null

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

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: latest backup'

    $backup = Get-LatestBackup -Pattern 'CS2-Optimize-Backup-*'
    if (-not $backup) {
        Write-Err 'No CS2-Optimize backup folder found on Desktop.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Info "Using backup: $($backup.FullName)"

    $restored = Restore-RegBackups -BackupDir $backup.FullName
    Write-Ok "Restored $restored registry key(s)."

    # ONCE alt powercfg ayarlari geri yuklenir (aktif plan henuz eski plan DEGIL),
    # SONRA aktif plan degistirilir. Aksi halde alt ayarlar yanlis plana yazilir.
    $pcfgFile = Join-Path $backup.FullName 'powercfg-backup.json'
    if (Test-Path $pcfgFile) {
        $pcfg = Get-Content $pcfgFile -Raw | ConvertFrom-Json
        foreach ($entry in @($pcfg)) {
            $parts = @($entry.Alias -split '\s+' | Where-Object { $_ })
            & powercfg.exe /setacvalueindex SCHEME_CURRENT @parts $entry.Value 2>$null | Out-Null
            Write-Ok "Power setting restored: $($entry.Alias) = $($entry.Value)"
        }
        & powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
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

if ($EnableSystemVrr -and $DisableSystemVrr) {
    Write-Err 'Use either -EnableSystemVrr or -DisableSystemVrr, not both.'
    Stop-Transcript | Out-Null
    exit 1
}

if (-not $Apply) {
    Write-Step 'DRY RUN'
    Write-Info 'No changes were made. Re-run with -Apply to apply.'
    Write-Info 'Recommended first run: -Apply -AddDefenderExclusions -RestoreTimerDefaults'
    Write-Info 'Optional A/B tests: -EnableHags OR -DisableHags, -TuneNicLatency, -DisableFullscreenOptimizations'
    Write-Info 'Optional GameBoost-derived tweaks: -DisableMpo, -DisableStorageSense, -DisableBackgroundApps, -EnableSystemVrr OR -DisableSystemVrr'
    Write-Info 'Optional performance/latency: -SetProcessorPerformance, -DisableIdleStates, -DisableDiskIdle, -SetMmcssGameProfile, -DisablePowerThrottling, -SetSystemResponsiveness, -DisablePagingExecutive, -DisableMouseAcceleration, -SetBestPerformance'
    Write-Info 'Optional NIC latency: -DisableInterruptModeration (Flow Control is left enabled on purpose)'
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
    'HKCU\Software\Microsoft\DirectX\UserGpuPreferences',
    'HKLM\SOFTWARE\Microsoft\Windows\Dwm',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications',
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games',
    'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling',
    'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management',
    'HKCU\Control Panel\Mouse',
    'HKCU\Control Panel\Desktop',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize',
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions'
)
foreach ($k in $keys) { Backup-RegKey -Key $k -BackupDir $script:BackupDir | Out-Null }

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
# ASPM ve USB selective suspend her calistirmada DEGISTIRILIR; onceki degerleri
# yedeklenir ki -Revert bunlari da geri alabilsin.
Backup-PowerCfgValue -Alias 'SUB_PCIEXPRESS ASPM'
Backup-PowerCfgValue -Alias '2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
& powercfg.exe /setactive SCHEME_MIN 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null | Out-Null
& powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
& powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
Write-Ok 'High Performance, PCIe ASPM off, USB selective suspend off.'
Write-Info 'Onceki ASPM/USB degerleri powercfg-backup.json icinde saklandi (revert edilebilir).'

# ---------------------------------------------------------------------------
# Processor performance / latency (optional)
# ---------------------------------------------------------------------------
if ($SetProcessorPerformance) {
    Write-Step 'Processor performance (min/max 100%, EPP 0, aggressive boost)'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR PROCTHROTTLEMIN'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR PROCTHROTTLEMAX'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR CPMINCORES'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR CPMAXCORES'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR PERFEPP'
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR PERFBOOSTMODE'

    Set-PowerCfgValue -Alias 'SUB_PROCESSOR PROCTHROTTLEMIN' 100
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR PROCTHROTTLEMAX' 100
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR CPMINCORES' 100
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR CPMAXCORES' 100
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR PERFEPP' 0
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR PERFBOOSTMODE' 2
    Write-Warn 'Idle power draw and temperature rise. Verify cooling with HWiNFO.'
}

if ($DisableIdleStates) {
    Write-Step 'OS idle suspend (IDLEDISABLE)'
    if (-not $DisableFastStartup) {
        Write-Warn 'Use only if BIOS C-states are NOT already disabled; do not combine both.'
    }
    Backup-PowerCfgValue -Alias 'SUB_PROCESSOR IDLEDISABLE'
    Set-PowerCfgValue -Alias 'SUB_PROCESSOR IDLEDISABLE' 1
}

if ($DisableDiskIdle) {
    Write-Step 'Disk idle timeout'
    Backup-PowerCfgValue -Alias 'SUB_DISK DISKIDLE'
    Set-PowerCfgValue -Alias 'SUB_DISK DISKIDLE' 0
    Write-Ok 'Disk idle timeout = 0 (never sleeps).'
}

& powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
Save-PowerCfgBackup -BackupDir $script:BackupDir

# ---------------------------------------------------------------------------
# Scheduler / MMCSS / power throttling (optional)
# ---------------------------------------------------------------------------
if ($SetMmcssGameProfile) {
    Write-Step 'MMCSS Games task'
    $gamesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    Set-RegDword $gamesKey 'GPU Priority' 8
    Set-RegDword $gamesKey 'Priority' 6
    Set-RegString $gamesKey 'Scheduling Category' 'Medium'
    Set-RegString $gamesKey 'SFIO Priority' 'High'
    Write-Ok 'Games task: GPU Priority 8, Priority 6, Scheduling Category Medium, SFIO Priority High.'
    Write-Info 'GPU Priority ve SFIO Priority Microsoft dokumanina gore kullanilmiyor (inert).'
    Write-Info 'Scheduling Category "High" bilerek yapilmadi: Pro Audio bandina sokup stutter yaratabilir.'
}

if ($DisablePowerThrottling) {
    Write-Step 'Power throttling'
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
    Write-Ok 'PowerThrottlingOff = 1.'
}

if ($SetSystemResponsiveness) {
    Write-Step 'System responsiveness'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
    Write-Ok 'SystemResponsiveness = 10.'
}

if ($DisablePagingExecutive) {
    Write-Step 'Disable paging executive'
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
    Write-Ok 'DisablePagingExecutive = 1.'
}

# ---------------------------------------------------------------------------
# Input / visual (optional)
# ---------------------------------------------------------------------------
if ($DisableMouseAcceleration) {
    Write-Step 'Mouse acceleration'
    $mouseKey = 'HKCU:\Control Panel\Mouse'
    Set-RegString $mouseKey 'MouseSpeed' '0'
    Set-RegString $mouseKey 'MouseThreshold1' '0'
    Set-RegString $mouseKey 'MouseThreshold2' '0'
    # MouseSensitivity 10 = pointer hiz slaydinin 6. notch'u = tek 1:1 deger.
    # Diger degerler count'lari olcekler (skip/duplicate).
    Set-RegString $mouseKey 'MouseSensitivity' '10'
    Write-Ok 'Mouse acceleration off (MouseSpeed/Threshold = 0), MouseSensitivity = 10.'
    Write-Info 'SmoothMouseXCurve/YCurve dokunulmadi: MouseSpeed=0 iken zaten okunmazlar.'
    Write-Info 'CS2 raw input kullandigi icin bu ayar masaustunu etkiler, nişan hizini degil.'
}

if ($SetBestPerformance) {
    Write-Step 'Visual effects = best performance'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Set-RegString 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
    Write-Ok 'Best performance visuals, transparency off, delays 0.'
}

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
# Optional GameBoost-derived tweaks (default: off)
# ---------------------------------------------------------------------------
if ($DisableMpo -or $DisableStorageSense -or $DisableBackgroundApps -or $EnableSystemVrr -or $DisableSystemVrr) {
    Write-Step 'Optional: GameBoost-derived tweaks'

    if ($DisableMpo) {
        Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5
        Write-Ok 'MPO disabled (OverlayTestMode = 5). Reboot required. A/B test.'
    }

    if ($DisableStorageSense) {
        Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0
        Write-Ok 'Storage Sense disabled.'
    }

    if ($DisableBackgroundApps) {
        Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
        Write-Ok 'Global background app access disabled.'
    }

    if ($EnableSystemVrr -or $DisableSystemVrr) {
        $vrrValue = if ($EnableSystemVrr) {
            'SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;'
        } else {
            'SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;'
        }
        Set-RegString 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' $vrrValue
        if ($EnableSystemVrr) {
            Write-Ok 'System-wide VRR optimization enabled. A/B test.'
        } else {
            Write-Ok 'System-wide VRR optimization disabled. A/B test.'
        }
    }
}
if ($SetCs2Priority) {
    Write-Step "CS2 kalici oncelik: $SetCs2Priority"
    $ifeoPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions'
    $priorityMap = @{ 'Normal' = 2; 'AboveNormal' = 6; 'High' = 3 }
    $priorityValue = $priorityMap[$SetCs2Priority]

    Set-RegDword $ifeoPath 'CpuPriorityClass' $priorityValue
    Write-Ok "IFEO PerfOptions CpuPriorityClass = $priorityValue ($SetCs2Priority)"
    Write-Info 'Ayarlar her yeni cs2.exe surecinde otomatik uygulanir.'
    Write-Info 'Degisiklikten sonra CS2 yeniden baslatilmalidir.'
    if ($SetCs2Priority -eq 'High') {
        Write-Warn 'High, sistem ses/DPC thread''lerini starve edip audio crackle ve stutter yapabilir.'
        Write-Info 'Once AboveNormal ile olc; High''a ancak olcumle fark yaratirsa gec.'
    }
    if ($SetCs2Priority -eq 'Normal') {
        Write-Info 'Normal = Windows varsayilani; essentially bir etkisi yok.'
    }
}


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

        if ($TuneNicLatency -or $DisableInterruptModeration) {
            Write-Warn 'NIC latency test mode: Interrupt Moderation disabled. A/B test.'
            Write-Info 'Latency drops but CPU/DPC load rises. Measure with LatencyMon + CapFrameX.'
            $im = $props | Where-Object { $_.DisplayName -eq 'Interrupt Moderation' } | Select-Object -First 1
            if ($im) {
                try {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $im.DisplayName -DisplayValue 'Disabled' -ErrorAction Stop
                    Write-Ok 'Interrupt Moderation = Disabled'
                } catch {
                    Write-Warn "Interrupt Moderation could not be changed: $($_.Exception.Message)"
                }
            } else {
                Write-Info 'Interrupt Moderation not found on this adapter.'
            }
        }

        if ($DisableFlowControl) {
            Write-Warn 'Flow Control disabled. This REDUCES drop protection and can INCREASE packet loss.'
            Write-Info 'Only use if a measurement proves it helps. Prefer keeping Flow Control enabled.'
            $fc = $props | Where-Object { $_.DisplayName -eq 'Flow Control' } | Select-Object -First 1
            if ($fc) {
                try {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $fc.DisplayName -DisplayValue 'Disabled' -ErrorAction Stop
                    Write-Ok 'Flow Control = Disabled'
                } catch {
                    Write-Warn "Flow Control could not be changed: $($_.Exception.Message)"
                }
            } else {
                Write-Info 'Flow Control not found on this adapter.'
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
