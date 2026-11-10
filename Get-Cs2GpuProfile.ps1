#Requires -Version 5.1
<#
.SYNOPSIS
  RTX 3070 (ve diğer NVIDIA GPU) için güvenli power-limit ve undervolt profili yönetimi.

.DESCRIPTION
  NVIDIA GPU tuning iki katmandan oluşur:
    1) Undervolt (voltaj düşürme) -> daha yüksek, daha kararlı boost clock.
       Bunu driver üzerinden yapar; en güvenilir yol NVIDIA Profile Inspector
       (.nip) veya Afterburner. Bu script o yolu OTOMATİKLEŞTİRMEZ; doğru
       profili üretir ve uygulama talimatını verir.
    2) Power limit -> nvidia-smi ile UYGULANABİLİR (GeForce'ta clock locking
       desteklenmez ama power limit çalışır).

  Bu script:
    - GPU'yu ve mevcut power limit / temperatür / clock değerlerini raporlar
    - Güvenli power limit aralığını hesaplar ve isteğe bağlı olarak uygular
    - Revert için orijinal power limit'i kaydeder
    - CS2 için önerilen bir .nip profili (base) üretir

  ÖNEMLİ: nvidia-smi GeForce kartlarda GPU clock locking'i (-lgc) desteklemez.
  "Setting applications clocks is not supported" hatası normaldir; bu bir
  arıza değildir. Undervolt + power limit GeForce'ta doğru yöntemdir.

.PARAMETER Apply
  Power limit değişikliğini uygula. Verilmezse sadece raporlar.

.PARAMETER Revert
  Kaydedilen orijinal power limit'i geri yükle.

.PARAMETER PowerLimitWatts
  Hedef power limit (watt). Verilmezse mevcut limitin %95'i önerilir.

.PARAMETER TargetTemperature
  Hedef sıcaklık (°C). Varsayılan: 83.

.PARAMETER GenerateNip
  CS2 için NVIDIA Profile Inspector profili (.nip) üret.

.PARAMETER NipOutputPath
  Üretilen .nip dosyasının yolu. Varsayılan: Masaüstü.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2GpuProfile.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2GpuProfile.ps1 -Apply -PowerLimitWatts 240

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2GpuProfile.ps1 -Revert
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [int]$PowerLimitWatts,
    [int]$TargetTemperature = 83,
    [switch]$GenerateNip,
    [string]$NipOutputPath,
    [string]$Label = 'rtx3070'
)

$ErrorActionPreference = 'Continue'
$script:Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')
$script:StateFile = Join-Path $script:Desktop "CS2-GpuProfile-$Label-state.json"
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

function Get-SmiPath {
    $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Get-GpuTelemetry {
    param([string]$Smi)
    $raw = & $Smi --query-gpu=name,driver_version,pstate,power.limit,power.default_limit,power.min_limit,power.max_limit,power.draw,temperature.gpu,clocks.current.graphics,clocks.current.memory,utilization.gpu,power.limit_percentage '--format=csv,noheader,nounits' 2>$null
    if (-not $raw) { return $null }
    $parts = (@($raw)[0] -split ',' | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 13) { return $null }
    return [ordered]@{
        Name             = $parts[0]
        DriverVersion    = $parts[1]
        PState           = $parts[2]
        PowerLimit       = [double]$parts[3]
        DefaultPowerLimit = [double]$parts[4]
        MinPowerLimit    = [double]$parts[5]
        MaxPowerLimit    = [double]$parts[6]
        PowerDraw        = [double]$parts[7]
        Temperature      = [double]$parts[8]
        GraphicsClock    = [double]$parts[9]
        MemoryClock      = [double]$parts[10]
        Utilization      = [double]$parts[11]
        LimitPercent     = [double]$parts[12]
    }
}

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: GPU power limit'
    if (-not (Test-Path $script:StateFile)) {
        Write-Err "No saved GPU state found: $script:StateFile"
        exit 1
    }
    $state = Get-Content $script:StateFile -Raw | ConvertFrom-Json
    $smi = Get-SmiPath
    if (-not $smi) { Write-Err 'nvidia-smi not found.'; exit 1 }
    & $smi --power-limit="$($state.OriginalPowerLimit)" 2>&1 | Write-Host
    Write-Ok "Power limit restored: $($state.OriginalPowerLimit) W"
    exit 0
}

$smi = Get-SmiPath
if (-not $smi) {
    Write-Err 'nvidia-smi not found. NVIDIA driver must be installed.'
    exit 1
}

$gpu = Get-GpuTelemetry -Smi $smi
if (-not $gpu) {
    Write-Err 'Could not query GPU via nvidia-smi.'
    exit 1
}

# ---------------------------------------------------------------------------
# Report current state
# ---------------------------------------------------------------------------
Write-Step 'GPU'
$gpu.GetEnumerator() | ForEach-Object { Write-Info "$($_.Key): $($_.Value)" }

Write-Step 'Analysis'
$recommended = [math]::Round($gpu.PowerLimit * 0.95, 0)
Write-Info "Current power limit      : $($gpu.PowerLimit) W (default $($gpu.DefaultPowerLimit) W, max $($gpu.MaxPowerLimit) W)"
Write-Info "Recommended (95%)        : $recommended W"
Write-Info "Target temperature       : $TargetTemperature C"
Write-Info "Driver version           : $($gpu.DriverVersion)"

if ($gpu.PowerLimit -gt 0 -and $gpu.PowerDraw -gt 0) {
    $headroom = $gpu.PowerLimit - $gpu.PowerDraw
    Write-Info ("Current headroom        : {0} W" -f [math]::Round($headroom, 1))
}

Write-Warn 'Undervolt (voltaj dusurme) en buyuk kazanci saglar ama driver seviyesindedir.'
Write-Info 'Bu script power limit uygular; undervolt icin uretilen .nip profilini kullan.'
Write-Info 'Gercek verify: nvidia-smi -q -d PERFORMANCE cikisinda "clocks_throttle_reasons" bolumune bakin.'

# ---------------------------------------------------------------------------
# Apply power limit
# ---------------------------------------------------------------------------
if ($Apply) {
    Write-Step 'Apply power limit'

    if (-not $PowerLimitWatts) { $PowerLimitWatts = [int]$recommended }

    $state = [ordered]@{
        Timestamp          = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Label              = $Label
        OriginalPowerLimit = $gpu.PowerLimit
        NewPowerLimit      = $PowerLimitWatts
        DriverVersion      = $gpu.DriverVersion
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -Path $script:StateFile -Encoding UTF8
    Write-Ok "Original power limit saved: $script:StateFile"

    if ($PowerLimitWatts -lt $gpu.MinPowerLimit -or $PowerLimitWatts -gt $gpu.MaxPowerLimit) {
        Write-Warn "Requested $PowerLimitWatts W is outside the allowed range ($($gpu.MinPowerLimit)-$($gpu.MaxPowerLimit) W); driver will clamp it."
    }

    $out = & $smi --power-limit="$PowerLimitWatts" 2>&1
    $out | Write-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Power limit set to $PowerLimitWatts W"
    } else {
        Write-Warn "nvidia-smi returned exit code $LASTEXITCODE; verify with -q -d POWER."
    }
} else {
    Write-Info 'No change made. Re-run with -Apply to set the power limit.'
}

# ---------------------------------------------------------------------------
# NVIDIA Profile Inspector (.nip) generation
# ---------------------------------------------------------------------------
if ($GenerateNip) {
    Write-Step 'Generate NVIDIA Profile Inspector profile'

    if (-not $NipOutputPath) { $NipOutputPath = Join-Path $script:Desktop "CS2-$Label-$script:Stamp.nip" }

    # Profil CS2'ye uygulanir (exe = cs2.exe). Ayarlar projenin NVIDIA
    # bolumundeki degerlerle uyumludur; third-party profillerin aksine sadece
    # dogrulanmis ve riskli olmayan ayarlar icerir.
    # NOT: SettingID'ler iki gercek referans profille (RTX3070.nip ve ABDO profil)
    # karsilastirilarak dogrulandi. Yanlis SettingID driver profilini bozabilir.
    $nip = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>CS2</ProfileName>
    <Executeables>cs2.exe</Executeables>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Low Latency Mode</SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum pre-rendered frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic sample optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic filter optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Trilinear optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Negative LOD bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader disk cache maximum size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>10240</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Flag to control smooth AFR behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred refresh rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
    # Dosya utf-16 bekleniyor; BOM ile yaz.
    $enc = New-Object System.Text.UnicodeEncoding($false, $true)
    [System.IO.File]::WriteAllText($NipOutputPath, $nip, $enc)
    Write-Ok "Profile written: $NipOutputPath"
    Write-Info 'Apply: NVIDIA Profile Inspector -> File -> Import Profile(s) -> cs2.exe profilini seç -> Apply (Y)'
    Write-Info 'Do NOT apply this profile to the Base Profile: it is scoped to cs2.exe.'
    Write-Info 'Low Latency Mode = 0 (Off) cünkü CS2 Reflex kullanıyor; ikisini üst üste açma.'
}

Write-Step 'Done'
Write-Info 'State file: ' + $script:StateFile
Write-Info 'Revert: run the same script with -Revert'
