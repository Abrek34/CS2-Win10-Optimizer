#Requires -Version 5.1
<#
.SYNOPSIS
  "CS2 Mükemmel Sistem" hedef profilini denetler: sistem hedefe uygun mu?

.DESCRIPTION
  Bu script HİÇBİR AYARI DEĞİŞTİRMEZ. Yalnızca okur ve her katman için
  "hedefte mi / değil mi / öneri nedir" tablosu üretir.

  Hedef profil (i9-9900K + Z390-A PRO + RTX 3070 + 64 GB DDR4-4000 + 360 Hz):
    - BIOS: 5.0 GHz fixed, ring 4.7, C-states off, EPP 0, XMP 4000 CL18
    - Windows: High Performance, min/max %100, EPP 0, core parking off, disk idle 0
    - Scheduler: Game Mode on, Game DVR/Bar off, PowerThrottlingOff, SystemResponsiveness 10
    - GPU: Prefer max performance, LLM Off (Reflex varsa), V-Sync off, 357 cap
    - Input: polling 1000 Hz, mouse acceleration off
    - Ag: kablolu, link power saving off, Flow Control acik, RSS on
    - Arka plan: overlay'ler kapali, telemetri minimum

  Donanim uyumlulugu icin "hedef profil" referansi:
    docs/HEDEF-PROFIL.md

.PARAMETER OutputDirectory
  Raporun yazilacagi klasor. Varsayilan: Masaustu.

.PARAMETER Cs2Path
  CS2 kurulum yolu. Verilmezse otomatik aranir.

.PARAMETER TargetFps
  Hedef FPS (360 Hz monitorda 357). Cap degerlendirmesinde kullanilir.

.PARAMETER Json
  Sadece JSON yaz.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2TargetCheck.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2TargetCheck.ps1 -TargetFps 357
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Cs2Path,
    [int]$TargetFps = 357,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')

Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop

if (-not $OutputDirectory) { $OutputDirectory = $script:Desktop }
if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Layer,
        [Parameter(Mandatory = $true)][string]$Item,
        [Parameter(Mandatory = $true)][string]$Target,
        $Actual = 'N/A',
        [ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$Status = 'INFO',
        [string]$Action = ''
    )
    $checks.Add([ordered]@{
        Layer  = $Layer
        Item   = $Item
        Target = $Target
        Actual = [string]$Actual
        Status = $Status
        Action = $Action
    })
}

function Get-PowerCfgIndexValue {
    param([string]$Alias)
    $parts = Split-PowerCfgAlias -Alias $Alias
    if ($parts.Count -eq 0) { return $null }
    $out = & powercfg.exe /query SCHEME_CURRENT @parts 2>$null
    if (-not $out) { return $null }
    $m = [regex]::Match(($out -join "`n"), 'Current AC Power Setting Index:\s*(0x[0-9a-fA-F]+)')
    if ($m.Success) { return [Convert]::ToInt32($m.Groups[1].Value, 16) }
    return $null
}

function Get-ActiveSchemeName {
    $line = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    if (-not $line) { return 'N/A' }
    $m = [regex]::Match($line, '\((.*)\)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $line.Trim()
}

# ---------------------------------------------------------------------------
# Katman 1: Windows / scheduler
# ---------------------------------------------------------------------------
Write-Step 'Windows katmanı'

$plan = Get-ActiveSchemeName
if ($plan -match 'High Performance|High performance|Performans|Yuksek') {
    Add-Check -Layer 'Windows' -Item 'Güç planı' -Target 'High Performance' -Actual $plan -Status 'OK'
} elseif ($plan -match 'Ultimate') {
    Add-Check -Layer 'Windows' -Item 'Güç planı' -Target 'High Performance' -Actual $plan -Status 'OK' -Action 'Ultimate de olur.'
} else {
    Add-Check -Layer 'Windows' -Item 'Güç planı' -Target 'High Performance' -Actual $plan -Status 'FAIL' -Action 'powercfg /setactive SCHEME_MIN'
}

$proctMin = Get-PowerCfgIndexValue -Alias 'SUB_PROCESSOR PROCTHROTTLEMIN'
if ($null -eq $proctMin) {
    Add-Check -Layer 'Windows' -Item 'CPU minimum state' -Target '100' -Actual 'okunamıyor' -Status 'INFO'
} elseif ($proctMin -ge 100) {
    Add-Check -Layer 'Windows' -Item 'CPU minimum state' -Target '100' -Actual $proctMin -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'CPU minimum state' -Target '100' -Actual $proctMin -Status 'FAIL' -Action 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100'
}

$epp = Get-PowerCfgIndexValue -Alias 'SUB_PROCESSOR PERFEPP'
if ($null -eq $epp) {
    Add-Check -Layer 'Windows' -Item 'Speed Shift EPP' -Target '0' -Actual 'okunamıyor' -Status 'INFO' -Action 'HWP destekliyse 0 yap'
} elseif ($epp -eq 0) {
    Add-Check -Layer 'Windows' -Item 'Speed Shift EPP' -Target '0' -Actual $epp -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'Speed Shift EPP' -Target '0' -Actual $epp -Status 'FAIL' -Action 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0'
}

$coreMin = Get-PowerCfgIndexValue -Alias 'SUB_PROCESSOR CPMINCORES'
if ($null -eq $coreMin) {
    Add-Check -Layer 'Windows' -Item 'Core parking' -Target 'off' -Actual 'okunamıyor' -Status 'INFO'
} elseif ($coreMin -ge 100) {
    Add-Check -Layer 'Windows' -Item 'Core parking' -Target 'off' -Actual "min $coreMin core" -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'Core parking' -Target 'off' -Actual "min $coreMin core" -Status 'FAIL' -Action 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100'
}

$diskIdle = Get-PowerCfgIndexValue -Alias 'SUB_DISK DISKIDLE'
if ($null -eq $diskIdle) {
    Add-Check -Layer 'Windows' -Item 'Disk idle timeout' -Target '0' -Actual 'okunamıyor' -Status 'INFO'
} elseif ($diskIdle -eq 0) {
    Add-Check -Layer 'Windows' -Item 'Disk idle timeout' -Target '0' -Actual $diskIdle -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'Disk idle timeout' -Target '0' -Actual $diskIdle -Status 'FAIL' -Action 'powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0'
}

$hags = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
if ($null -eq $hags) {
    Add-Check -Layer 'Windows' -Item 'HAGS' -Target 'A/B test (1=kapali, 2=acik)' -Actual 'varsayilan' -Status 'INFO' -Action 'Iki degerle de olc'
} else {
    Add-Check -Layer 'Windows' -Item 'HAGS' -Target 'A/B test (1=kapali, 2=acik)' -Actual "HwSchMode=$hags" -Status 'INFO' -Action 'A/B olc: 1 ve 2'
}

$gdvr = Get-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
if ($gdvr -eq 0) {
    Add-Check -Layer 'Windows' -Item 'Game DVR' -Target '0 (kapali)' -Actual $gdvr -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'Game DVR' -Target '0 (kapali)' -Actual $(if ($null -eq $gdvr) { 'yok' } else { $gdvr }) -Status 'FAIL' -Action 'CS2-Windows10-Optimize.ps1 -Apply'
}

$gameMode = Get-RegValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
if ($gameMode -eq 1) {
    Add-Check -Layer 'Windows' -Item 'Game Mode' -Target '1 (acik)' -Actual $gameMode -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'Game Mode' -Target '1 (acik)' -Actual $(if ($null -eq $gameMode) { 'yok' } else { $gameMode }) -Status 'FAIL' -Action 'CS2-Windows10-Optimize.ps1 -Apply'
}

$ptOff = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff'
if ($ptOff -eq 1) {
    Add-Check -Layer 'Windows' -Item 'PowerThrottlingOff' -Target '1' -Actual $ptOff -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'PowerThrottlingOff' -Target '1' -Actual $(if ($null -eq $ptOff) { 'yok' } else { $ptOff }) -Status 'FAIL' -Action '-DisablePowerThrottling'
}

$sysResp = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness'
if ($null -eq $sysResp) {
    Add-Check -Layer 'Windows' -Item 'SystemResponsiveness' -Target '10' -Actual 'varsayilan (20)' -Status 'WARN' -Action '-SetSystemResponsiveness'
} elseif ($sysResp -le 10) {
    Add-Check -Layer 'Windows' -Item 'SystemResponsiveness' -Target '10' -Actual $sysResp -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'SystemResponsiveness' -Target '10' -Actual $sysResp -Status 'WARN' -Action '-SetSystemResponsiveness'
}

# MMCSS Games task - Scheduling Category High stutter yaratabilir
$schedCat = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Scheduling Category'
if ("$schedCat" -eq 'High') {
    Add-Check -Layer 'Windows' -Item 'MMCSS Games Scheduling Category' -Target 'Medium' -Actual 'High' -Status 'FAIL' -Action "High = Pro Audio bandi (23-26); sistem threadlerini starve edip stutter yaratabilir. -SetMmcssGameProfile ile Mediuma al"
} elseif ($null -eq $schedCat) {
    Add-Check -Layer 'Windows' -Item 'MMCSS Games Scheduling Category' -Target 'Medium' -Actual 'varsayilan' -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'MMCSS Games Scheduling Category' -Target 'Medium' -Actual $schedCat -Status 'OK'
}

$gpuPrio = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority'
if ($null -ne $gpuPrio) {
    Add-Check -Layer 'Windows' -Item 'MMCSS GPU Priority' -Target 'degistirme (Microsoft: kullanilmiyor)' -Actual $gpuPrio -Status 'INFO' -Action 'Degeri degistirmek etkisiz; GUI hissi yaratabilir'
}

$netThrottle = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex'
if ($null -eq $netThrottle) {
    Add-Check -Layer 'Windows' -Item 'NetworkThrottlingIndex' -Target 'degistirme' -Actual 'varsayilan' -Status 'OK'
} elseif ($netThrottle -eq 10) {
    Add-Check -Layer 'Windows' -Item 'NetworkThrottlingIndex' -Target 'degistirme (10=varsayilan)' -Actual $netThrottle -Status 'OK'
} else {
    Add-Check -Layer 'Windows' -Item 'NetworkThrottlingIndex' -Target 'degistirme' -Actual "0x{0:X}" -f $netThrottle -Status 'FAIL' -Action 'Varsayilana dondur (10) - kapatma'
}

# ---------------------------------------------------------------------------
# Katman 2: Input
# ---------------------------------------------------------------------------
Write-Step 'Input katmanı'

$mouseSpeed = Get-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'
if ($null -eq $mouseSpeed) {
    Add-Check -Layer 'Input' -Item 'Mouse acceleration' -Target 'kapali' -Actual 'okunamıyor' -Status 'INFO' -Action '-DisableMouseAcceleration'
} elseif ("$mouseSpeed" -eq '0') {
    Add-Check -Layer 'Input' -Item 'Mouse acceleration' -Target 'kapali' -Actual 'MouseSpeed=0' -Status 'OK'
} else {
    Add-Check -Layer 'Input' -Item 'Mouse acceleration' -Target 'kapali' -Actual "MouseSpeed=$mouseSpeed" -Status 'FAIL' -Action '-DisableMouseAcceleration'
}

$mouseSens = Get-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity'
if ($null -eq $mouseSens) {
    Add-Check -Layer 'Input' -Item 'MouseSensitivity (1:1 degeri)' -Target '10' -Actual 'yok (varsayilan 10)' -Status 'OK'
} elseif ("$mouseSens" -eq '10') {
    Add-Check -Layer 'Input' -Item 'MouseSensitivity (1:1 degeri)' -Target '10' -Actual $mouseSens -Status 'OK'
} else {
    Add-Check -Layer 'Input' -Item 'MouseSensitivity (1:1 degeri)' -Target '10' -Actual $mouseSens -Status 'WARN' -Action "10 degilse countlar olceklenir (skip/duplicate). -DisableMouseAcceleration"
}

$curveX = Get-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'SmoothMouseXCurve'
$curveY = Get-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'SmoothMouseYCurve'
if ($null -ne $curveX -or $null -ne $curveY) {
    Add-Check -Layer 'Input' -Item 'SmoothMouseXCurve/YCurve' -Target 'dokunma (MouseSpeed=0 iken okunmaz)' -Actual 'mevcut' -Status 'OK' -Action 'Silmek veya 00 yapmak gereksiz; MouseSpeed=0 yeterli'
}

Add-Check -Layer 'Input' -Item 'Mouse polling rate' -Target 'olc: 8000/4000/2000/1000 Hz karsilastir' -Actual 'donanim ayari (raporlanamaz)' -Status 'INFO' -Action '8KHz fare icin: polling 2x monitör Hz (360Hz -> min 720Hz, pratik 1000Hz). DPI >= 1600 ile pollingi doyur. CapFrameX 1% low + p99 ile sec.'
Add-Check -Layer 'Input' -Item 'Mouse DPI (polling saturation)' -Target '8000 Hz icin >= 1600 DPI' -Actual 'raporlanamaz' -Status 'INFO' -Action 'DPI dusukse polling yuksekken sensor stutter olur; DPIyi artirip oyun ici sensi eDPI koruyacak sekilde dusur'
Add-Check -Layer 'Input' -Item 'Windows pointer speed' -Target '6/11' -Actual 'raporlanamaz' -Status 'INFO' -Action 'Pointer Options: hiz 6/11, Enhance pointer precision kapali'

# ---------------------------------------------------------------------------
# Katman 3: GPU
# ---------------------------------------------------------------------------
Write-Step 'GPU katmanı'

$smi = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
if (-not $smi) {
    $fallback = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (Test-Path $fallback) { $smi = Get-Command $fallback }
}
if ($smi) {
    try {
        $raw = & $smi.Source --query-gpu=name,power.limit,power.draw,temperature.gpu,clocks.current.graphics,clocks.current.memory,pstate '--format=csv,noheader,nounits' 2>$null
        if ($raw) {
            $p = (@($raw)[0] -split ',' | ForEach-Object { $_.Trim() })
            Add-Check -Layer 'GPU' -Item 'GPU / limit / draw' -Target 'limit = draw + headroom' -Actual "limit=$($p[1])W draw=$($p[2])W" -Status 'INFO'
            Add-Check -Layer 'GPU' -Item 'GPU sicaklik' -Target '< 80 C' -Actual "$($p[3]) C" -Status 'INFO'
            Add-Check -Layer 'GPU' -Item 'GPU pstate' -Target 'P0 (yuksek clock)' -Actual $p[6] -Status 'INFO' -Action 'Power management mode = Prefer max performance ayarla'
        }
    } catch {
        Add-Check -Layer 'GPU' -Item 'nvidia-smi' -Target 'okunabilir' -Actual 'hata' -Status 'INFO'
    }
} else {
    Add-Check -Layer 'GPU' -Item 'nvidia-smi' -Target 'okunabilir' -Actual 'bulunamadi' -Status 'INFO'
}

$gpuPref = Get-RegValue -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'cs2.exe'
if ($gpuPref -and "$gpuPref" -match 'GpuPreference=2') {
    Add-Check -Layer 'GPU' -Item 'Windows GPU preference' -Target 'High performance' -Actual 'GpuPreference=2' -Status 'OK'
} else {
    Add-Check -Layer 'GPU' -Item 'Windows GPU preference' -Target 'High performance' -Actual $(if ($gpuPref) { "$gpuPref" } else { 'yok' }) -Status 'FAIL' -Action 'CS2-Windows10-Optimize.ps1 -Apply'
}

# IFEO kalici oncelik
$cpuPrio = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' -Name 'CpuPriorityClass'
if ($null -eq $cpuPrio) {
    Add-Check -Layer 'Windows' -Item 'CS2 kalici oncelik (IFEO)' -Target 'yok (varsayilan)' -Actual 'yok' -Status 'INFO' -Action 'Gerekirse -SetCs2Priority AboveNormal ile kalici oncelik ver'
} else {
    $prioName = switch ([int]$cpuPrio) { 2 { 'Normal' } 3 { 'High' } 6 { 'AboveNormal' } 4 { 'REALTIME (riskli!)' } default { "deger=$cpuPrio" } }
    if ([int]$cpuPrio -eq 4) {
        Add-Check -Layer 'Windows' -Item 'CS2 kalici oncelik (IFEO)' -Target 'Normal/AboveNormal' -Actual $prioName -Status 'FAIL' -Action 'REALTIME sistemi kilitleyebilir; derhal Normal yap'
    } elseif ([int]$cpuPrio -eq 3) {
        Add-Check -Layer 'Windows' -Item 'CS2 kalici oncelik (IFEO)' -Target 'Normal/AboveNormal' -Actual $prioName -Status 'WARN' -Action 'High ses crackle/stutter riski; AboveNormal ile karsilastir'
    } else {
        Add-Check -Layer 'Windows' -Item 'CS2 kalici oncelik (IFEO)' -Target 'Normal/AboveNormal' -Actual $prioName -Status 'OK'
    }
}

Add-Check -Layer 'GPU' -Item 'NVCP Power management' -Target 'Prefer maximum performance' -Actual 'manuel kontrol' -Status 'INFO' -Action 'cs2.exe profili: Power management mode = Prefer max performance'
Add-Check -Layer 'GPU' -Item 'NVCP Low Latency Mode' -Target 'Off (Reflex acikken)' -Actual 'manuel kontrol' -Status 'INFO' -Action 'Reflex On iken Off; Reflex kapaliysa Ultra'
Add-Check -Layer 'GPU' -Item 'NVCP Vertical Sync' -Target 'Off' -Actual 'manuel kontrol' -Status 'INFO' -Action 'G-Sync + Reflex kombinasyonunda V-Sync On (driver) kullanilir'
Add-Check -Layer 'GPU' -Item 'FPS cap' -Target "$TargetFps (360 Hz - 3)" -Actual 'manuel kontrol' -Status 'INFO' -Action "Cap tek yerde: Reflex + G-Sync + V-Sync ile $TargetFps"
Add-Check -Layer 'GPU' -Item 'Shader cache' -Target 'Unlimited / 10 GB' -Actual 'manuel kontrol' -Status 'INFO' -Action 'Get-Cs2GpuProfile.ps1 -GenerateNip profilini uygula'

# ---------------------------------------------------------------------------
# Katman 4: Ag
# ---------------------------------------------------------------------------
Write-Step 'Ag katmani'

$adapter = Get-TargetAdapter
if ($adapter) {
    Add-Check -Layer 'Ag' -Item 'Baglanti turu' -Target 'Ethernet (kablolu)' -Actual "$($adapter.Name) / $($adapter.Status)" -Status 'OK'
    Add-Check -Layer 'Ag' -Item 'Link hizi' -Target '1 Gbps' -Actual ([string]$adapter.LinkSpeed) -Status 'INFO'

    $props = Get-NicProperties -AdapterName $adapter.Name
    foreach ($kw in @('*EEE', '*PowerSavingMode', '*SelectiveSuspend', '*WakeOnMagicPacket')) {
        $p = $props | Where-Object { $_.RegistryKeyword -eq $kw } | Select-Object -First 1
        if ($p) {
            $isDisabled = "$($p.DisplayValue)" -match '^Disabled|^Kapali|^Off'
            Add-Check -Layer 'Ag' -Item "NIC: $($p.DisplayName)" -Target 'Disabled' -Actual $p.DisplayValue -Status $(if ($isDisabled) { 'OK' } else { 'FAIL' }) -Action 'CS2-Win10-Network-Tuning.ps1 -Apply'
        }
    }

    $rscProp = $props | Where-Object { $_.RegistryKeyword -eq '*RSS' -or $_.RegistryKeyword -eq '*Rss' } | Select-Object -First 1
    if ($rscProp) {
        $rscOn = "$($rscProp.DisplayValue)" -match '^Enabled|^Acik|^On'
        Add-Check -Layer 'Ag' -Item 'Receive Side Scaling' -Target 'Enabled' -Actual $rscProp.DisplayValue -Status $(if ($rscOn) { 'OK' } else { 'FAIL' }) -Action 'CS2-Win10-Network-Tuning.ps1 -Apply'
    }

    $fcProp = $props | Where-Object { $_.DisplayName -eq 'Flow Control' } | Select-Object -First 1
    if ($fcProp) {
        $fcOn = "$($fcProp.DisplayValue)" -match '^Enabled|^Acik|^On'
        Add-Check -Layer 'Ag' -Item 'Flow Control' -Target 'Enabled (paket kaybi korumasi)' -Actual $fcProp.DisplayValue -Status $(if ($fcOn) { 'OK' } else { 'WARN' }) -Action 'Kapatma: paket kaybini artirir'
    }

    $imProp = $props | Where-Object { $_.DisplayName -eq 'Interrupt Moderation' } | Select-Object -First 1
    if ($imProp) {
        Add-Check -Layer 'Ag' -Item 'Interrupt Moderation' -Target 'A/B test (Off = dusuk latency)' -Actual $imProp.DisplayValue -Status 'INFO' -Action 'Yalnizca LatencyMon DPC farki varsa -DisableInterruptModeration'
    }

    $stats = Get-NicStatistics -AdapterName $adapter.Name
    foreach ($s in $stats) {
        $errs = ([int64]$s.ReceivedDiscarded + [int64]$s.ReceivedErrors + [int64]$s.OutboundDiscarded + [int64]$s.OutboundErrors)
        Add-Check -Layer 'Ag' -Item 'NIC hata/drop sayaci' -Target '0' -Actual $errs -Status $(if ($errs -eq 0) { 'OK' } else { 'WARN' }) -Action 'Kablo/port degistir; >0 ise fiziksel katman sorunu'
    }
} else {
    Add-Check -Layer 'Ag' -Item 'Adapter' -Target 'Ethernet' -Actual 'bulunamadi' -Status 'FAIL'
}

$gw = Get-DefaultGateway
Add-Check -Layer 'Ag' -Item 'Router' -Target 'ASUS RT-AX82U: Adaptive QoE Gaming Mode + %95 limiter' -Actual $(if ($gw) { "GW $gw" } else { 'GW yok' }) -Status 'INFO' -Action 'bufferbloat olc (waveform.com/bufferbloat); yuzde 95 limiter'

# ---------------------------------------------------------------------------
# Katman 5: Arka plan / overlay
# ---------------------------------------------------------------------------
Write-Step 'Arka plan katmani'

$startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
$noise = $startup | Where-Object { $_.Name -match 'iCUE|Armoury|Nahimic|Sonic|Razer|LghUB|Logitech|Discord|Steam|OneDrive|Spotify' }
Add-Check -Layer 'Arka plan' -Item 'Gizli arka plan uygulamalari' -Target 'RGB/overlay yok' -Actual "$($noise.Count) supheli kayit" -Status $(if ($noise.Count -eq 0) { 'OK' } else { 'WARN' }) -Action 'Task Manager > Startup: iCUE/Armoury/Nahimic/Discord kapat'
if ($noise.Count -gt 0) {
    foreach ($n in $noise) { Write-Info "  - $($n.Name)" }
}

$hvci = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled'
Add-Check -Layer 'Arka plan' -Item 'Memory Integrity / HVCI' -Target 'A/B test (guvenlik trade-off)' -Actual $(if ($null -eq $hvci) { 'varsayilan' } else { $hvci }) -Status 'INFO' -Action '5-10% FPS kazanci olabilir; WSL/Hyper-V kullaniyorsan dokunma'

# ---------------------------------------------------------------------------
# Ozet + cikti
# ---------------------------------------------------------------------------
$failCount = @($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq 'WARN' }).Count
$okCount = @($checks | Where-Object { $_.Status -eq 'OK' }).Count

Write-Host ''
Write-Step 'Hedef profil ozeti'
Write-Host ("  OK   : $okCount") -ForegroundColor Green
Write-Host ("  WARN : $warnCount") -ForegroundColor Yellow
Write-Host ("  FAIL : $failCount") -ForegroundColor Red
Write-Host ("  INFO : $(@($checks | Where-Object { $_.Status -eq 'INFO' }).Count)") -ForegroundColor Gray

$result = [ordered]@{
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    TargetFps    = $TargetFps
    Summary      = [ordered]@{ OK = $okCount; WARN = $warnCount; FAIL = $failCount }
    Checks       = $checks
}

$jsonPath = Join-Path $OutputDirectory "CS2-TargetCheck-$script:Stamp.json"
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

if (-not $Json) {
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# CS2 Mükemmel Sistem — Hedef Profil Denetimi')
    $md.Add('')
    $md.Add("> Tarih: **$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))**  ")
    $md.Add("> Hedef FPS: **$TargetFps**  ")
    $md.Add("> Sonuç: OK=$okCount WARN=$warnCount FAIL=$failCount")
    $md.Add('')
    $md.Add('| Katman | Öğe | Hedef | Mevcut | Durum | Aksiyon |')
    $md.Add('|---|---|---|---|---|---|')
    foreach ($c in $checks) {
        $icon = switch ($c.Status) { 'OK' { '✅' } 'WARN' { '⚠️' } 'FAIL' { '❌' } default { 'ℹ️' } }
        $md.Add("| $($c.Layer) | $($c.Item) | $($c.Target) | $($c.Actual) | $icon $($c.Status) | $($c.Action) |")
    }
    $md.Add('')
    $mdPath = Join-Path $OutputDirectory "CS2-TargetCheck-$script:Stamp.md"
    $md -join "`r`n" | Set-Content -Path $mdPath -Encoding UTF8
    Write-Ok "Markdown: $mdPath"
}

Write-Ok "JSON    : $jsonPath"
Write-Info 'Bu script hicbir ayari degistirmedi (read-only).'
Write-Info 'Hedef profil referansi: docs/HEDEF-PROFIL.md'
Write-Info 'Olcum icin: Get-Cs2Benchmark.ps1 -Label baseline'
