#Requires -Version 5.1
<#
.SYNOPSIS
  RawAccel kurulumunu denetler: CS2'de gerçekte hangi nişan hızını oynadığınızı hesaplar.

.DESCRIPTION
  RawAccel, mouse sürücü zincirine yerleşen bir kernel-mode filtre sürücüsüdür.
  CS2 raw input kullandığı için Windows'un "Enhance pointer precision"
  ayarını zaten bypass eder; ancak RawAccel'in kendi çarpanları (sens multiplier,
  DPI normalization, output smoothing) **CS2'nin gördüğü veriyi doğrudan
  değiştirir.**

  Bu script read-only'dir:
    - RawAccel'in settings.json dosyasını bulur ve okur
    - Kurulu mu / etkin mi kontrol eder
    - Uygulanan çarpanları hesaplar
    - "Gerçekte kaç cm/360 oynuyorsunuz" sonucunu verir
    - CS2'ye giden veri ile masada görünen verinin aynı olup olmadığını
      karşılaştırır (DPI normalization aktifse farklı olur)

  Hiçbir ayar değiştirmez.

.PARAMETER SettingsPath
  RawAccel settings.json dosyasının yolu. Bulunamazsa otomatik aranır.

.PARAMETER Cs2Sens
  CS2'deki mevcut sens değeriniz (varsayılan: 1.0).

.PARAMETER Dpi
  Mevcut fare DPI değeriniz (varsayılan: 800).

.PARAMETER OutputDirectory
  Raporun yazılacağı klasör. Varsayılan: Masaüstü.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2RawAccelCheck.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2RawAccelCheck.ps1 -Cs2Sens 2.0 -Dpi 400
#>

[CmdletBinding()]
param(
    [string]$SettingsPath,
    [double]$Cs2Sens = 1.0,
    [int]$Dpi = 800,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Continue'
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')

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

if (-not $OutputDirectory) { $OutputDirectory = $script:Desktop }
if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

$YAW = 0.022  # CS2 m_yaw default (deg per count)
$NORMALIZED_DPI = 1000  # RawAccel NORMALIZED_DPI

function Get-Cm360 {
    param([double]$Dpi, [double]$Sens)
    if ($Dpi -le 0 -or $Sens -le 0) { return 0 }
    $counts = 360.0 / ($Sens * $YAW)
    return [math]::Round(($counts / $Dpi) * 2.54, 2)
}

function Find-RawAccelSettings {
    param([string]$Explicit)
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($Explicit) { $candidates.Add($Explicit) }

    # RawAccel GUI ayarlari calisma dizininde "settings.json" olarak saklar.
    $candidates.Add((Join-Path $script:Desktop 'settings.json'))
    $candidates.Add((Join-Path $script:Desktop 'RawAccel\settings.json'))
    $candidates.Add((Join-Path $env:APPDATA 'RawAccel\settings.json'))
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'RawAccel\settings.json'))
    $candidates.Add((Join-Path $env:ProgramData 'RawAccel\settings.json'))

    # Surucu/uygulama klasorleri
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        $dirs = @(
            (Join-Path $root 'RawAccel'),
            (Join-Path $root 'Raw Accel'),
            (Join-Path $root 'RawAccelOfficial\RawAccel')
        )
        foreach ($d in $dirs) {
            if (Test-Path $d) { $candidates.Add((Join-Path $d 'settings.json')) }
        }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Surucu / servis kontrolu
# ---------------------------------------------------------------------------
Write-Step 'RawAccel kurulum durumu'

$driver = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'rawaccel|raw_accel' -or $_.DisplayName -match 'rawaccel' }
$service = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'rawaccel|raw_accel' -or $_.DisplayName -match 'rawaccel' }

$driverFound = [bool]$driver
$serviceFound = [bool]$service

if ($driverFound) {
    Write-Ok "Surucu kurulu: $($driver.Name) (durum: $($driver.State))"
} else {
    Write-Warn 'RawAccel surucusu bulunamadi (WMI).'
}
if ($serviceFound) {
    Write-Info "Servis: $($service.Name) (durum: $($service.Status))"
}

# ---------------------------------------------------------------------------
# Ayarlar dosyasi
# ---------------------------------------------------------------------------
$settingsFile = Find-RawAccelSettings -Explicit $SettingsPath
$settings = $null

if ($settingsFile) {
    Write-Ok "Ayarlar dosyasi: $settingsFile"
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    } catch {
        Write-Warn "Ayarlar dosyasi okunamadi: $($_.Exception.Message)"
    }
} else {
    Write-Warn 'settings.json bulunamadi.'
    Write-Info 'RawAccel ayarlari genelde RawAccel klasorunde "settings.json" olarak durur.'
    Write-Info 'Bulursaniz -SettingsPath ile belirtebilirsiniz.'
}

# ---------------------------------------------------------------------------
# Carpannlari oku
# ---------------------------------------------------------------------------
function Get-ProfileValue {
    param($Profile, [string]$Name, $Default = $null)
    if (-not $Profile) { return $Default }
    if ($Profile.PSObject.Properties.Name -contains $Name) {
        $v = $Profile.$Name
        if ($null -ne $v) { return $v }
    }
    return $Default
}

$sensMult = 1.0
$outputDpi = $NORMALIZED_DPI
$normDpi = 0        # cihaz DPI normalization (0 = kapali)
$outSmooth = 0
$inSmooth = 0
$accelMode = 'bilinmiyor'
$angleSnap = 0
$speedClamp = $false

if ($settings) {
    # JSON yapisi versiyona gore degisebilir; en olasi alanlar.
    $prof = $settings
    if ($settings.PSObject.Properties.Name -contains 'profile') { $prof = $settings.profile }
    if ($prof -and $prof.PSObject.Properties.Name -contains 'profiles') {
        $first = @($prof.profiles)[0]
        if ($first) { $prof = $first }
    }

    $sensMult = [double](Get-ProfileValue -Profile $prof -Name 'sensMultiplier' -Default (Get-ProfileValue -Profile $prof -Name 'sens' -Default 1.0))
    $outputDpi = [double](Get-ProfileValue -Profile $prof -Name 'outputDpi' -Default $NORMALIZED_DPI)
    $normDpi = [double](Get-ProfileValue -Profile $prof -Name 'dpi' -Default 0)
    $outSmooth = [double](Get-ProfileValue -Profile $prof -Name 'outputSpeedSmoothHalflife' -Default 0)
    $inSmooth = [double](Get-ProfileValue -Profile $prof -Name 'inputSpeedSmoothHalflife' -Default 0)
    $angleSnap = [double](Get-ProfileValue -Profile $prof -Name 'degreesSnap' -Default 0)
    $mode = Get-ProfileValue -Profile $prof -Name 'accelMode' -Default $null
    if ($mode) { $accelMode = [string]$mode }
}

# ---------------------------------------------------------------------------
# Hesap
# ---------------------------------------------------------------------------
Write-Step 'Uygulanan carpannlar'
Write-Info "Sens multiplier        : $sensMult"
Write-Info "Output DPI              : $outputDpi"
Write-Info "DPI normalization (cihaz DPI): $normDpi  (0 = kapali)"
Write-Info "Output smoothing        : $outSmooth ms"
Write-Info "Input smoothing         : $inSmooth ms"
Write-Info "Angle snap              : $angleSnap derece"
Write-Info "Acceleration mode       : $accelMode"

# RawAccel formulu (kaynak koddan):
#   dpi_factor               = normDpi > 0 ? 1000 / normDpi : 1
#   output_dpi_adj_factor    = outputDpi / 1000
#   dpi_adjustment           = output_dpi_adj_factor * dpi_factor
#   out = in * sensMultiplier * dpi_adjustment
$dpiFactor = if ($normDpi -gt 0) { $NORMALIZED_DPI / $normDpi } else { 1.0 }
$outputAdjFactor = $outputDpi / $NORMALIZED_DPI
$dpiAdjustment = $outputAdjFactor * $dpiFactor
$totalMultiplier = $sensMult * $dpiAdjustment

Write-Host ''
Write-Step 'Hesaplanan etki'
Write-Info ("DPI factor            : {0}" -f $dpiFactor)
Write-Info ("Output DPI factor     : {0}" -f $outputAdjFactor)
Write-Info ("Toplam DPI adjustment : {0}" -f $dpiAdjustment)
Write-Info ("TOPLAM CARPAN         : {0}" -f $totalMultiplier)

$effectiveSens = $Cs2Sens * $totalMultiplier
$cm360Raw = Get-Cm360 -Dpi $Dpi -Sens $Cs2Sens
$cm360Eff = Get-Cm360 -Dpi $Dpi -Sens $effectiveSens

Write-Host ''
Write-Step "CS2'de gercekte oynadiginiz degerler"
Write-Host ("  Oyun ici sens (CS2)        : {0}" -f $Cs2Sens)
Write-Host ("  RawAccel toplam carpani     : {0}" -f [math]::Round($totalMultiplier, 4))
Write-Host ("  => ETKIN SENS               : {0}" -f [math]::Round($effectiveSens, 4))
Write-Host ("  cm/360 (carpansiz)          : {0} cm" -f $cm360Raw)
Write-Host ("  cm/360 (etkin)              : {0} cm" -f $cm360Eff)

if ([math]::Abs($totalMultiplier - 1.0) -lt 0.0001) {
    Write-Ok 'Toplam carpan 1.0 -> CS2 ham sensör verisini aliyor (kimlik işlemi).'
    Write-Info 'Bu durumda "accel off" gerçekten hiçbir şeyi değiştirmiyor.'
} else {
    Write-Warn ("Toplam carpan 1.0 DEGIL ({0}) -> CS2'ye giden veri farklı." -f [math]::Round($totalMultiplier, 4))
    Write-Info 'Hissettiğiniz "daha temiz/direkt sensör" hissi bu carpandan geliyor olabilir.'
    Write-Info 'Ölçüm yaparken bu carpani hesaba katin.'
}

if ($outSmooth -gt 0) {
    Write-Warn ("Output smoothing aktif ({0} ms) -> girdiye gecikme ekler." -f $outSmooth)
    Write-Info 'Bu durum "gecikme azaldi" degil, "gecikme eklendi" demektir.'
}

if ($angleSnap -gt 0) {
    Write-Warn ("Angle snap aktif ({0} derece) -> dikey hareketler yataya kilitlenir." -f $angleSnap)
}

# ---------------------------------------------------------------------------
# Fare yazilimi acceleration uyarisi
# ---------------------------------------------------------------------------
Write-Host ''
Write-Step 'Kontrol edilmeli: fare yazilimi (firmware) acceleration'
Write-Info 'Raw input, cihazin KENDI icinde uyguladigi acceleration''i bypass edemez.'
Write-Info 'Fare yaziliminda "acceleration / angle snapping / smoothing / motion sync" kapatilmalı.'

# ---------------------------------------------------------------------------
# Cikti
# ---------------------------------------------------------------------------
$report = [ordered]@{
    GeneratedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    DriverFound   = $driverFound
    ServiceFound  = $serviceFound
    SettingsFile  = $settingsFile
    Multipliers   = [ordered]@{
        SensMultiplier   = $sensMult
        OutputDpi        = $outputDpi
        NormalizationDpi = $normDpi
        DpiFactor        = $dpiFactor
        OutputAdjFactor  = $outputAdjFactor
        DpiAdjustment    = $dpiAdjustment
        TotalMultiplier  = $totalMultiplier
    }
    Smoothing     = [ordered]@{ OutputMs = $outSmooth; InputMs = $inSmooth }
    AngleSnap     = $angleSnap
    Effective     = [ordered]@{
        Cs2Sens       = $Cs2Sens
        EffectiveSens = [math]::Round($effectiveSens, 4)
        Cm360Raw      = $cm360Raw
        Cm360Effective = $cm360Eff
    }
}

$jsonPath = Join-Path $OutputDirectory "CS2-RawAccelCheck-$script:Stamp.json"
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
Write-Ok "JSON: $jsonPath"

Write-Host ''
Write-Info 'Bu script hicbir ayari degistirmedi (read-only).'
Write-Info 'Olcum: Get-Cs2Benchmark.ps1 -Label rawaccel-on / -Label rawaccel-off'
Write-Info 'Hedef profil referansi: docs/HEDEF-PROFIL.md bolum 5.6'
