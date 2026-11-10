#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  CS2 odaklı Windows ağ ayarı: düşük latency + paket kaybı yok.

.DESCRIPTION
  Hedef: "hızlı ve akıcı internet, ama paket kaybı olmadan".

  Temel prensip:
    - Paket KAYBINA yol açan ayarlar KAPALI bırakılır (Rx Flow Control açık kalır).
    - Latency'yi düşüren ama CPU/DPC yükünü artıran ayarlar AYRI ve OPSIYONELdir.
    - Checksum/LSO/RSC gibi offload'lar varsayılan olarak BOZULMAZ (CPU yükünü
      düşürür, latency için kapatmak genelde gereksiz).
    - Speed & Duplex ve Jumbo Frames oynanmaz (sabitleştirmek duplex mismatch ve
      MTU sorunları yaratır).

  Uygulananlar (varsayılan, -Apply ile):
    - Link power saving kapatma: EEE / Green Ethernet / Power Saving Mode /
      Selective Suspend / Ultra Low Power / Gigabit Lite / Wake on Magic & Pattern
    - Adapter power management kapatma (Windows uyku modunda kablo düşmesini önler)
    - RSS (Receive Side Scaling) açık
    - TCP autotuning normal, RSS enabled (global)

  Opsiyonel (-Apply ile birlikte):
    -DisableInterruptModeration : Interrupt Moderation off -> latency düşer,
                                  CPU/DPC yükü artar (ölç!)
    -DisableRsc                : RSC/LRO off -> küçük paket latency için değerlendir
    -EnableLargeSendOffload    : LSO/TSO off -> SADECE sorun ayıklama için
    -DisableChecksumOffload    : SADECE sorun ayıklama için
    -SetUdpSegmentationOff     : USO off -> sadece test amaçlı
    -ResetDnsCache             : DNS önbelleğini temizle (paket kaybını etkilemez)

  Kapsam dışı (bilinçli):
    - Nagle / TCPNoDelay (CS2 UDP)
    - NetworkThrottlingIndex kapatma
    - Speed & Duplex sabitleme, Jumbo Frame, RSS/RSC kuyruklarını maxlama
    - MTU değişikliği (ISP yolu belirleyici; router/ISP ile eşleşmeli)

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply -DisableInterruptModeration

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Revert
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$DisableInterruptModeration,
    [switch]$DisableRsc,
    [switch]$EnableLargeSendOffload,
    [switch]$DisableChecksumOffload,
    [switch]$SetUdpSegmentationOff,
    [switch]$ResetDnsCache,
    [string]$AdapterName
)

$ErrorActionPreference = 'Continue'
$script:Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop   = [Environment]::GetFolderPath('Desktop')
$script:LogPath   = Join-Path $script:Desktop "CS2-NetworkTuning-$script:Stamp.log"
$script:BackupDir = Join-Path $script:Desktop "CS2-NetworkTuning-Backup-$script:Stamp"

Start-Transcript -Path $script:LogPath -Force | Out-Null

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

function Get-LatestBackup {
    Get-ChildItem -Path $script:Desktop -Directory -Filter 'CS2-NetworkTuning-Backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Get-TargetAdapter {
    param([string]$Explicit)
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    if ($Explicit) {
        $m = $adapters | Where-Object { $_.Name -eq $Explicit } | Select-Object -First 1
        if ($m) { return $m }
        Write-Err "Adapter not found: $Explicit"
        return $null
    }
    $up = $adapters | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($up) { return $up }
    return ($adapters | Select-Object -First 1)
}

function Backup-NicProperties {
    param([string]$Name, [object[]]$Props)
    $save = @($Props | Select-Object Name, DisplayName, DisplayValue, RegistryKeyword)
    $save | ConvertTo-Json -Depth 4 |
        Set-Content -Path (Join-Path $script:BackupDir 'nic-backup.json') -Encoding UTF8
    Write-Ok "NIC properties saved: nic-backup.json"
}

function Set-NicProperty {
    param([string]$Adapter, [object[]]$Props, [string]$DisplayName, [string]$Value)
    $p = $Props | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1
    if (-not $p) {
        Write-Info "$DisplayName not present on this adapter; skipped."
        return
    }
    try {
        Set-NetAdapterAdvancedProperty -Name $Adapter -DisplayName $p.DisplayName -DisplayValue $Value -ErrorAction Stop
        Write-Ok "$DisplayName = $Value"
    } catch {
        Write-Warn "$DisplayName could not be changed: $($_.Exception.Message)"
    }
}

function Set-NicPropertyByKeyword {
    param([string]$Adapter, [object[]]$Props, [string]$KeywordPattern, [string]$Value)
    $p = $Props | Where-Object { $_.RegistryKeyword -match $KeywordPattern } | Select-Object -First 1
    if (-not $p) {
        Write-Info "No property matching '$KeywordPattern'; skipped."
        return
    }
    try {
        Set-NetAdapterAdvancedProperty -Name $Adapter -DisplayName $p.DisplayName -DisplayValue $Value -ErrorAction Stop
        Write-Ok "$($p.DisplayName) = $Value"
    } catch {
        Write-Warn "$($p.DisplayName) could not be changed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: latest network tuning backup'

    $backup = Get-LatestBackup
    if (-not $backup) {
        Write-Err 'No CS2-NetworkTuning backup folder found on Desktop.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Info "Using backup: $($backup.FullName)"

    $nicFile = Join-Path $backup.FullName 'nic-backup.json'
    if (Test-Path $nicFile) {
        $nic = Get-Content $nicFile -Raw | ConvertFrom-Json
        foreach ($item in @($nic)) {
            if ($item.Name -and $item.DisplayName) {
                Set-NetAdapterAdvancedProperty -Name $item.Name -DisplayName $item.DisplayName -DisplayValue $item.DisplayValue -ErrorAction SilentlyContinue
            }
        }
        Write-Ok 'NIC advanced properties restored.'
    }

    Write-Ok 'Revert completed. Reboot recommended.'
    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------
if (-not $Apply) {
    Write-Step 'DRY RUN'
    Write-Info 'No changes were made. Re-run with -Apply to apply.'
    Write-Info 'Recommended first run: -Apply'
    Write-Info "Log: $script:LogPath"

    $adapter = Get-TargetAdapter -Explicit $AdapterName
    if (-not $adapter) {
        Write-Err 'No suitable physical adapter found.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Step "Adapter: $($adapter.Name)"
    Write-Info "Description : $($adapter.InterfaceDescription)"
    Write-Info "Status     : $($adapter.Status) / $($adapter.LinkSpeed)"

    $props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
    Write-Step 'Current advanced properties'
    $props |
        Sort-Object DisplayName |
        Select-Object DisplayName, DisplayValue, RegistryKeyword |
        Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    Write-Step 'Would be changed'
    Write-Info 'EEE / Green Ethernet / Power Saving Mode / Selective Suspend / Ultra Low Power / Gigabit Lite -> Disabled'
    Write-Info 'Wake on Magic Packet / Wake on Pattern Match -> Disabled'
    Write-Info 'Adapter power management -> disabled'
    Write-Info 'Receive Side Scaling -> Enabled'
    Write-Info 'TCP autotuning -> normal, RSS -> enabled'

    Write-Step 'Deliberately NOT changed'
    Write-Info 'Flow Control (keeping it ON protects against packet loss)'
    Write-Info 'Speed & Duplex (stay on Auto), Jumbo Frames, buffer/RSS queue depth'
    Write-Info 'Checksum/LSO/RSC offloads (leave enabled; disabling wastes CPU)'

    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null

$adapter = Get-TargetAdapter -Explicit $AdapterName
if (-not $adapter) {
    Write-Err 'No suitable physical adapter found. Nothing applied.'
    Stop-Transcript | Out-Null
    exit 1
}

Write-Step "Adapter: $($adapter.Name) / $($adapter.InterfaceDescription)"
Write-Info "Status: $($adapter.Status) / Link speed: $($adapter.LinkSpeed)"

$props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
Backup-NicProperties -Name $adapter.Name -Props $props

# ---------------------------------------------------------------------------
# Power saving off (link level)
# ---------------------------------------------------------------------------
Write-Step 'Link power saving off'
foreach ($name in @(
    'Energy Efficient Ethernet',
    'Green Ethernet',
    'Power Saving Mode',
    'Selective Suspend',
    'Ultra Low Power',
    'Gigabit Lite'
)) {
    Set-NicProperty -Adapter $adapter.Name -Props $props -DisplayName $name -Value 'Disabled'
}

Write-Step 'Wake on LAN off'
foreach ($name in @('Wake on Magic Packet', 'Wake on Pattern Match')) {
    Set-NicProperty -Adapter $adapter.Name -Props $props -DisplayName $name -Value 'Disabled'
}

# ---------------------------------------------------------------------------
# Adapter power management
# ---------------------------------------------------------------------------
Write-Step 'Adapter power management'
try {
    Disable-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
    Write-Ok 'Adapter power management disabled (Windows sleep drop fixed).'
} catch {
    Write-Warn "Adapter power management could not be disabled: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# RSS
# ---------------------------------------------------------------------------
Write-Step 'Receive Side Scaling'
$rss = $props | Where-Object { $_.DisplayName -match '^Receive Side Scaling' } | Select-Object -First 1
if ($rss) {
    try {
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $rss.DisplayName -DisplayValue 'Enabled' -ErrorAction Stop
        Write-Ok 'Receive Side Scaling = Enabled'
    } catch {
        Write-Warn "RSS could not be enabled: $($_.Exception.Message)"
    }
} else {
    Write-Info 'RSS property not found; skipping.'
}

# ---------------------------------------------------------------------------
# Optional latency / troubleshooting switches
# ---------------------------------------------------------------------------
if ($DisableInterruptModeration) {
    Write-Step 'Interrupt Moderation off (optional, A/B test)'
    Write-Warn 'Latency drops, but CPU and DPC load rise. Measure with LatencyMon + CapFrameX.'
    Set-NicProperty -Adapter $adapter.Name -Props $props -DisplayName 'Interrupt Moderation' -Value 'Disabled'
}

if ($DisableRsc) {
    Write-Step 'RSC / LRO off (optional, evaluation only)'
    Write-Info 'RSC coalesces received TCP segments; disabling gives finer granularity.'
    Write-Info 'CS2 traffic is mostly UDP, so the effect is usually small. Measure.'
    Set-NicPropertyByKeyword -Adapter $adapter.Name -Props $props -KeywordPattern '^\*RSC$|^RSC|LargeReceive' -Value 'Disabled'
    Set-NicProperty -Adapter $adapter.Name -Props $props -DisplayName 'Large Receive Offload' -Value 'Disabled'
}

if ($EnableLargeSendOffload) {
    Write-Step 'Large Send Offload off (troubleshooting only)'
    Write-Warn 'Not a latency tweak. Use only to isolate a driver/compatibility problem.'
    Set-NicPropertyByKeyword -Adapter $adapter.Name -Props $props -KeywordPattern '^\*LSO$|^LSO|LargeSend' -Value 'Disabled'
    Set-NicProperty -Adapter $adapter.Name -Props $props -DisplayName 'Large Send Offload v2' -Value 'Disabled'
}

if ($DisableChecksumOffload) {
    Write-Step 'Checksum offload off (troubleshooting only)'
    Write-Warn 'Not a latency tweak. Disabling raises CPU usage on every packet.'
    Set-NicPropertyByKeyword -Adapter $adapter.Name -Props $props -KeywordPattern 'Checksum' -Value 'Disabled'
}

if ($SetUdpSegmentationOff) {
    Write-Step 'UDP segmentation offload off (troubleshooting only)'
    Write-Warn 'Can cause fragmentation issues. Use only to isolate a problem.'
    Set-NicPropertyByKeyword -Adapter $adapter.Name -Props $props -KeywordPattern 'USO|UdpSegment' -Value 'Disabled'
}

# ---------------------------------------------------------------------------
# TCP global settings
# ---------------------------------------------------------------------------
Write-Step 'TCP global settings'
& netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
& netsh.exe int tcp set global rss=enabled 2>$null | Out-Null
Write-Ok 'TCP autotuning = normal; RSS = enabled.'
Write-Info 'Nagle/TCPNoDelay and NetworkThrottlingIndex are intentionally NOT changed.'

if ($ResetDnsCache) {
    Write-Step 'DNS cache'
    & ipconfig.exe /flushdns 2>$null | Out-Null
    Write-Ok 'DNS cache flushed.'
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Step 'Adapter status after tuning'
Get-NetAdapter -Name $adapter.Name |
    Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Host

Write-Step 'NIC statistics (errors / discards should be 0)'
try {
    Get-NetAdapterStatistics -Name $adapter.Name |
        Select-Object Name, ReceivedDiscardedPackets, ReceivedPacketErrors, OutboundDiscardedPackets, OutboundPacketErrors, ReceivedBytes, SentBytes |
        Format-List | Out-String -Width 200 | Write-Host
} catch {
    Write-Warn "Could not read adapter statistics: $($_.Exception.Message)"
}

Write-Step 'Current advanced properties'
$propsAfter = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
$propsAfter |
    Sort-Object DisplayName |
    Select-Object DisplayName, DisplayValue, RegistryKeyword |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Host

Write-Step 'TCP global'
(& netsh.exe int tcp show global 2>$null) | Write-Host

Write-Step 'Done'
Write-Ok "Backup: $script:BackupDir"
Write-Ok "Log: $script:LogPath"
Write-Info 'Revert: run the same script with -Revert.'
Write-Info 'Router-side settings (bufferbloat / QoS) are not covered by this script; see RAPOR.md.'

Stop-Transcript | Out-Null
