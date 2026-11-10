#Requires -Version 5.1
<#
.SYNOPSIS
  CS2 fare DPI / sens / polling rate matrisini hesaplar ve raporlar.

.DESCRIPTION
  CS2'de `m_yaw = 0.022` derece/count. cm/360 şu formülle hesaplanır:

      cm/360 = (360 / (DPI * CS2_sens * 0.022)) / DPI * 2.54

  Bu script:
    - Verilen DPI + sens için cm/360 ve eDPI hesaplar
    - Sabit eDPI'yi koruyarak tüm DPI kademelerini listeler (fiziksel hareket aynı)
    - Her DPI'nin hangi polling rate'i doyurduğunu gösterir
      (raporun benzersiz veri üretmesi için gereken minimum fare hizi)
    - 360 Hz monitörde polling x FPS etkileşimini gösterir

  Read-only: hiçbir ayar değiştirmez, sadece hesaplar.

.PARAMETER Dpi
  Mevcut fare DPI değeriniz. Varsayılan: 800.

.PARAMETER Sens
  Mevcut CS2 sens değeriniz. Varsayılan: 1.0.

.PARAMETER PollingHz
  Mevcut polling rate. Varsayılan: 8000. Birden fazla: 8000,4000,2000,1000.

.PARAMETER MonitorHz
  Monitör refresh rate. Varsayılan: 360.

.PARAMETER TargetFps
  Hedef FPS. Varsayılan: 357 (360 Hz - 3).

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2AimMatrix.ps1 -Dpi 400 -Sens 2.0

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2AimMatrix.ps1 -Dpi 1600 -Sens 0.5 -PollingHz 8000,2000,1000
#>

[CmdletBinding()]
param(
    [int]$Dpi = 800,
    [double]$Sens = 1.0,
    [int[]]$PollingHz = @(8000, 4000, 2000, 1000),
    [int]$MonitorHz = 360,
    [int]$TargetFps = 357
)

$ErrorActionPreference = 'Continue'
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')

Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop

# PowerShell diziyi tek string olarak geçirebilir; "8000,2000,1000" -> diziye cevir.
$PollingHz = @(
    foreach ($p in $PollingHz) {
        foreach ($part in ("$p" -split ',')) {
            $v = 0
            if ([int]::TryParse($part.Trim(), [ref]$v) -and $v -gt 0) { $v }
        }
    }
)
if ($PollingHz.Count -eq 0) { $PollingHz = @(8000, 4000, 2000, 1000) }

$YAW = 0.022  # CS2 m_yaw default (deg per count)

function Get-Cm360 {
    param([double]$Dpi, [double]$Sens)
    if ($Dpi -le 0 -or $Sens -le 0) { return 0 }
    $counts = 360.0 / ($Sens * $YAW)
    return [math]::Round(($counts / $Dpi) * 2.54, 2)
}

function Get-SaturationSpeed {
    # Her polling raporunda benzersiz veri olmasi icin gereken minimum
    # fare hareket hizi (mm/s).
    param([double]$Dpi, [double]$Hz)
    if ($Dpi -le 0 -or $Hz -le 0) { return 0 }
    $mmPerCount = 25.4 / $Dpi
    $intervalSec = 1.0 / $Hz
    return [math]::Round($mmPerCount / $intervalSec, 0)
}

$eDpi = $Dpi * $Sens

Write-Step 'Mevcut ayarlar'
Write-Info "DPI            : $Dpi"
Write-Info "CS2 sens       : $Sens"
Write-Info "eDPI (DPI*sens): $eDpi"
Write-Info "cm/360         : $(Get-Cm360 -Dpi $Dpi -Sens $Sens)"
Write-Info "Polling        : $($PollingHz -join ', ') Hz"
Write-Info "Monitor        : $MonitorHz Hz / hedef $TargetFps FPS"

# ---------------------------------------------------------------------------
# Kademeler (eDPI sabit)
# ---------------------------------------------------------------------------
$levels = @(400, 800, 1600, 3200, 6400) | Where-Object { $_ -le 25600 }

Write-Step 'eDPI korunarak DPI kademeleri (fiziksel hareket degismez)'
Write-Host ("{0,-6} {1,-10} {2,-9} {3,-12} {4,-12} {5,-12}" -f 'DPI', 'CS2 sens', 'eDPI', 'cm/360', '8000Hz', '4000Hz')
foreach ($d in $levels) {
    $s = [math]::Round($eDpi / $d, 4)
    if ($s -lt 0.0001) { continue }
    $cm = Get-Cm360 -Dpi $d -Sens $s
    $sp8 = Get-SaturationSpeed -Dpi $d -Hz 8000
    $sp4 = Get-SaturationSpeed -Dpi $d -Hz 4000
    Write-Host ("{0,-6} {1,-10} {2,-9} {3,-12} {4,-12} {5,-12}" -f $d, $s, [math]::Round($eDpi, 0), $cm, "$sp8 mm/s", "$sp4 mm/s")
}

Write-Host ''
Write-Step 'Polling x FPS etkilesimi (frame basina rapor sayisi)'
Write-Host ("{0,-10} {1,-12} {2,-12} {3,-12}" -f 'Polling', '357 FPS', '250 FPS', '200 FPS')
foreach ($hz in $PollingHz) {
    $a = [math]::Round($hz * (1000.0 / 357) / 1000, 1)
    $b = [math]::Round($hz * (1000.0 / 250) / 1000, 1)
    $c = [math]::Round($hz * (1000.0 / 200) / 1000, 1)
    Write-Host ("{0,-10} {1,-12} {2,-12} {3,-12}" -f "$hz Hz", "$a rapor", "$b rapor", "$c rapor")
}

Write-Host ''
Write-Step 'Polling kurali kontrolu'
$minPolling = [math]::Round($MonitorHz * 2)
Write-Info "Kural: polling >= 2 x monitör Hz  ->  bu sistem icin minimum $minPolling Hz"
foreach ($hz in $PollingHz) {
    if ($hz -ge $minPolling) {
        Write-Ok "$hz Hz kurali karsiliyor"
    } else {
        Write-Warn "$hz Hz kurali KARSILAMIYOR (360 Hz icin >= $minPolling Hz)"
    }
}

Write-Host ''
Write-Step 'DPI saturation kontrolu (mevcut DPI)'
foreach ($hz in $PollingHz) {
    $need = Get-SaturationSpeed -Dpi $Dpi -Hz $hz
    $verdict = if ($need -le 16) {
        'RAHAT (en yavas normal harekette bile benzersiz veri)'
    } elseif ($need -le 64) {
        'RAHAT (normal hareketlerde benzersiz veri)'
    } elseif ($need -le 130) {
        'SINIRDA (hizli hareketlerde benzersiz)'
    } else {
        'RISKLI (cogu harekette tekrarli rapor -> sensör stutter)'
    }
    Write-Host ("  {0,5} Hz -> {1,5} mm/s gerekir : {2}" -f $hz, $need, $verdict)
}

# ---------------------------------------------------------------------------
# Cikti
# ---------------------------------------------------------------------------
$rows = @()
foreach ($d in $levels) {
    $s = [math]::Round($eDpi / $d, 4)
    if ($s -lt 0.0001) { continue }
    $rows += [ordered]@{
        Dpi             = $d
        Cs2Sens         = $s
        EDpi            = [math]::Round($eDpi, 0)
        Cm360           = Get-Cm360 -Dpi $d -Sens $s
        SpeedNeeded8000 = Get-SaturationSpeed -Dpi $d -Hz 8000
        SpeedNeeded4000 = Get-SaturationSpeed -Dpi $d -Hz 4000
    }
}

$report = [ordered]@{
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Current     = [ordered]@{ Dpi = $Dpi; Sens = $Sens; EDpi = [math]::Round($eDpi, 0); Cm360 = Get-Cm360 -Dpi $Dpi -Sens $Sens }
    MonitorHz   = $MonitorHz
    TargetFps   = $TargetFps
    MinPolling  = $minPolling
    PollingHz   = $PollingHz
    Levels      = $rows
}

$jsonPath = Join-Path $script:Desktop "CS2-AimMatrix-$script:Stamp.json"
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
Write-Ok "JSON: $jsonPath"

Write-Host ''
Write-Info 'Bu script hicbir ayari degistirmedi (read-only, sadece hesap).'
Write-Info 'Karar icin olcum: Get-Cs2Benchmark.ps1 -Label pollXXXX -PollingHz XXXX'
Write-Info 'Hedef profil referansi: docs/HEDEF-PROFIL.md bolum 5'
