#Requires -Version 5.1
<#
.SYNOPSIS
  CS2-Win10-Optimizer için tekrarlanabilir ölçüm (benchmark) motoru.

.DESCRIPTION
  Projenin temel felsefesi: "tek değişiklik → ölçüm → karar". Bu script o ölçümü
  otomatikleştirir. Kendisi hiçbir ayarı DEĞİŞTİRMEZ; yalnızca ölçer ve raporlar.

  Yetenekleri:
    - PresentMon varsa: frame time + p99 + 1% low + 0.1% low + input-to-photon
      latency toplanır (kolon seçimi PresentMon sürümüne göre otomatiktir).
    - CapFrameX / PresentMon CSV'si -FrameCsv ile verilirse aynı istatistikler
      üretilir (CapFrameX'in kendi arayüzünde benchmark yapıp export etmek için).
    - HWiNFO64 sensörleri (varsa) CSV olarak toplanır (CPU/GPU clock, sıcaklık, WHEA).
    - LatencyMon yoksa: atlanır (DPC/ISR ölçümü manuel).
    - Ağ: hedeflere ICMP ping serisi ile jitter ve paket kaybı ölçülür
      (çıktı ayrıştırma Windows diline bağlı DEĞİLDİR: EN/TR/TR kayıp dahil).
    - NIC: discard/error sayaçları ölçüm başı ve sonunda okunur; FARK raporlanır.
    - Tüm sonuçlar tek klasörde toplanır ve özet Markdown/JSON olarak yazılır.

  Bu script read-only'dir: registry, servis, güç planı veya BIOS değiştirmez.

.PARAMETER OutputDirectory
  Sonuçların yazılacağı klasör. Varsayılan: Masaüstü.

.PARAMETER CapFrameXPath
  CapFrameX.exe yolu. Bulunamazsa otomatik aranır.

.PARAMETER PresentMonPath
  PresentMon.exe yolu. Bulunamazsa otomatik aranır.

.PARAMETER FrameCsv
  Daha önce dışa aktarılmış bir CapFrameX veya PresentMon CSV dosyası.
  Bu dosya üzerinden de aynı istatistikler (avg / 1% low / 0.1% low / p99)
  hesaplanır. CapFrameX'te benchmark'u elle çalıştırıp CSV export ederseniz
  ölçümü script'e aktarabilirsiniz.

.PARAMETER HWiNFOPath
  HWiNFO64.exe yolu. Bulunamazsa otomatik aranır.

.PARAMETER Seconds
  PresentMon/HWiNFO toplama süresi (saniye). Varsayılan: 120.

.PARAMETER PingTargets
  ICMP hedefleri. Varsayılan: router (otomatik), 1.1.1.1, 8.8.8.8.

.PARAMETER PingCount
  Her hedef için ping sayısı. Varsayılan: 20.

.PARAMETER SkipNetwork
  Ağ ölçümünü atla.

.PARAMETER SkipGame
  Oyun/PresentMon ölçümünü atla.

.PARAMETER Label
  Ölçüm etiketi (ör. "before-hags", "after-hags"). Rapor dosya adına yazılır.

.PARAMETER PollingHz
  Ölçüm sırasındaki mouse polling rate (Hz). Raporu etiketler; örn. 8000, 4000,
  2000, 1000. Polling karşılaştırmasında hangi turun hangi olduğunu ayırt etmek için.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2Benchmark.ps1 -Label baseline

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2Benchmark.ps1 -Seconds 180 -Label after-hags
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$CapFrameXPath,
    [string]$PresentMonPath,
    [string]$FrameCsv,
    [string]$HWiNFOPath,
    [int]$Seconds = 120,
    [string[]]$PingTargets,
    [int]$PingCount = 20,
    [switch]$SkipNetwork,
    [switch]$SkipGame,
    [string]$Label = 'run',
    [int]$PollingHz = 0
)

$ErrorActionPreference = 'Continue'
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')

if (-not $OutputDirectory) { $OutputDirectory = $script:Desktop }
if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

$safeLabel = ($Label -replace '[^A-Za-z0-9._-]', '_')
$runDir = Join-Path $OutputDirectory "CS2-Benchmark-$safeLabel-$script:Stamp"
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

# Ayristirici yardimcilar da modul ile gelir; modul yoksa inline fallback.
if (-not (Get-Command -Name 'ConvertFrom-PingOutput' -ErrorAction SilentlyContinue)) {
    Write-Warning 'ConvertFrom-PingOutput bulunamadi; yerlesim-duyarsiz olcum kullanilamaz (ag sonuclari bos kalir).'
    function ConvertFrom-PingOutput {
        param([AllowEmptyString()][string]$Text)
        return [ordered]@{ PacketLoss = $null; AvgMs = $null; MinMs = $null; MaxMs = $null;
                           JitterMs = $null; StdDevMs = $null; Samples = 0; Timeouts = 0 }
    }
}
if (-not (Get-Command -Name 'Get-FrameTimeStats' -ErrorAction SilentlyContinue)) {
    Write-Warning 'Get-FrameTimeStats bulunamadi; frame time olcumu kullanilamaz.'
    function Get-FrameTimeStats { param([object[]]$Rows) return $null }
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Find-Tool {
    param([string]$Name, [string]$ExplicitPath, [string[]]$ExtraDirs)
    if ($ExplicitPath -and (Test-Path $ExplicitPath)) { return $ExplicitPath }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $dirs = @(
        'C:\Program Files',
        'C:\Program Files (x86)',
        "$env:LOCALAPPDATA\Programs",
        "$env:LOCALAPPDATA\CapFrameX",
        "$env:LOCALAPPDATA\Programs\CapFrameX"
    )
    if ($ExtraDirs) { $dirs = $ExtraDirs + $dirs }
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path $d)) { continue }
        $hit = Get-ChildItem -Path $d -Filter $Name -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Get-NvidiaSmiPath {
    $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Measure-Ping {
    param([string]$Target, [int]$Count)
    if (-not $Target) { return $null }
    $out = & ping.exe -n $Count $Target 2>&1
    $text = ($out -join "`n")

    # Dil-bağımsız ayrıştırma: EN/TR/de yerelleşimlerinin hepsini destekler.
    $stats = ConvertFrom-PingOutput -Text $text
    $stats['Target']   = $Target
    $stats['RawOutput'] = ($out | Select-Object -Last 6)
    return $stats
}

# ---------------------------------------------------------------------------
# Environment discovery
# ---------------------------------------------------------------------------
Write-Step 'Environment'
$capframex = Find-Tool -Name 'CapFrameX.exe' -ExplicitPath $CapFrameXPath
$presentmon = Find-Tool -Name 'PresentMon.exe' -ExplicitPath $PresentMonPath
$hwinfo = Find-Tool -Name 'HWiNFO64.exe' -ExplicitPath $HWiNFOPath
$smi = Get-NvidiaSmiPath

Write-Info "CapFrameX  : $(if ($capframex) { $capframex } else { 'bulunamadı' })"
Write-Info "PresentMon : $(if ($presentmon) { $presentmon } else { 'bulunamadı' })"
Write-Info "HWiNFO64  : $(if ($hwinfo) { $hwinfo } else { 'bulunamadı' })"
Write-Info "nvidia-smi : $(if ($smi) { $smi } else { 'bulunamadı' })"
Write-Info "Output     : $runDir"

# ---------------------------------------------------------------------------
# System snapshot
# ---------------------------------------------------------------------------
Write-Step 'System snapshot'

# Tek bir WMI hatasinin TUM snapshot'i dusmesine yol acmamasi icin her
# deger ayri ayri guvenli sekilde alinir (literal icinde hata = tamamen bos).
function Get-SafeValue {
    param([scriptblock]$Block, $Default = $null)
    try { $v = & $Block } catch { $v = $null }
    if ($null -eq $v) { return $Default }
    return $v
}

$osInfo     = Get-SafeValue { Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue }
$cpuInfo    = Get-SafeValue { Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 }
$memInfo    = Get-SafeValue { Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue }
$gpuWin     = Get-SafeValue { Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1 }
$planText   = Get-SafeValue { (& powercfg.exe /getactivescheme 2>$null) -join ' ' }
$hwSchMode  = Get-SafeValue { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode }

$snapshot = [ordered]@{
    Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Label     = $Label
    PollingHz = $(if ($PollingHz -gt 0) { $PollingHz } else { 'N/A' })
    Computer  = $env:COMPUTERNAME
    OS        = $osInfo.Caption
    Build     = $osInfo.BuildNumber
    CPU       = $cpuInfo.Name
    RAM_GB    = [math]::Round((($memInfo | Measure-Object Capacity -Sum).Sum / 1GB), 1)
    GPU       = $gpuWin.Name
    GPUDriver = $gpuWin.DriverVersion
    PowerPlan = $planText
    HwSchMode = $hwSchMode
}

$snapshot | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $runDir 'system-snapshot.json') -Encoding UTF8
$snapshot.GetEnumerator() | ForEach-Object { Write-Info "$($_.Key): $($_.Value)" }

# ---------------------------------------------------------------------------
# GPU telemetry (nvidia-smi)
# ---------------------------------------------------------------------------
$gpuTelemetry = $null
if ($smi) {
    Write-Step 'GPU telemetry (nvidia-smi)'
    try {
        $raw = & $smi --query-gpu=name,driver_version,pstate,clocks.current.graphics,clocks.current.memory,temperature.gpu,power.draw,power.limit,utilization.gpu,clocks_throttle_reasons.active '--format=csv,noheader,nounits' 2>$null
        if ($raw) {
            $line = @($raw)[0]
            $parts = $line -split ',' | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 10) {
                $gpuTelemetry = [ordered]@{
                    Name          = $parts[0]
                    DriverVersion = $parts[1]
                    PState        = $parts[2]
                    GraphicsClock = $parts[3]
                    MemoryClock   = $parts[4]
                    Temperature   = $parts[5]
                    PowerDraw     = $parts[6]
                    PowerLimit    = $parts[7]
                    Utilization   = $parts[8]
                    ThrottleReasons = $parts[9]
                }
                $gpuTelemetry.GetEnumerator() | ForEach-Object { Write-Info "$($_.Key): $($_.Value)" }
            }
        }
    } catch {
        Write-Warn "nvidia-smi query failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Network: ping / jitter / loss
# ---------------------------------------------------------------------------
function Get-NicSnapshot {
    $snap = @{}
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        foreach ($a in $adapters) {
            $s = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
            if ($s) {
                $snap[$a.Name] = [ordered]@{
                    Name              = $a.Name
                    LinkSpeed         = [string]$a.LinkSpeed
                    ReceivedDiscarded = [long]$s.ReceivedDiscardedPackets
                    ReceivedErrors    = [long]$s.ReceivedPacketErrors
                    OutboundDiscarded = [long]$s.OutboundDiscardedPackets
                    OutboundErrors    = [long]$s.OutboundPacketErrors
                    ReceivedBytes     = [long]$s.ReceivedBytes
                    SentBytes         = [long]$s.SentBytes
                }
            }
        }
    } catch {
        Write-Warn "Adapter statistics unavailable: $($_.Exception.Message)"
    }
    return $snap
}

$netResults = @()
$nicStats = @()
$dnsTimes = @()
$nicBefore = Get-NicSnapshot

if (-not $SkipNetwork) {
    Write-Step 'Network measurement (ping / jitter / packet loss)'

    $targets = @()
    if ($PingTargets -and $PingTargets.Count -gt 0) {
        $targets = $PingTargets
    } else {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1)
        if ($gw -and $gw.NextHop) { $targets += $gw.NextHop }
        $targets += '1.1.1.1'
        $targets += '8.8.8.8'
    }

    foreach ($t in $targets) {
        Write-Info "Pinging $t ..."
        $r = Measure-Ping -Target $t -Count $PingCount
        if ($r) {
            $netResults += $r
            Write-Ok ("{0}: loss={1}% avg={2}ms min={3}ms max={4}ms jitter={5}ms" -f `
                $r.Target, $r.PacketLoss, $r.AvgMs, $r.MinMs, $r.MaxMs, $r.JitterMs)
        }
    }

    # NIC sayaçları ölçüm başında okunur (delta için), aşağıda sonra tekrar okunur.
    Write-Step 'NIC counters (baseline)'

    # DNS resolution time
    Write-Step 'DNS resolution'
    foreach ($hostName in @('steamcommunity.com', 'google.com')) {
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            [void][System.Net.Dns]::GetHostAddresses($hostName)
            $sw.Stop()
            $dnsTimes += [ordered]@{ Host = $hostName; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1) }
            Write-Info "$hostName : $($dnsTimes[-1].Ms) ms"
        } catch {
            Write-Warn "$hostName : DNS failed"
        }
    }
}

# ---------------------------------------------------------------------------
# Game / frame time measurement
# ---------------------------------------------------------------------------
$frameResults = $null
if (-not $SkipGame) {
    if ($presentmon) {
        Write-Step "Frame time capture (PresentMon, $Seconds s)"
        Write-Info "CS2'yi simdi baslat ve oynayin. Olcum arka planda suruyor."
        Write-Info 'PresentMon ETW icin yonetici yetkisi gerektirir. Yonetici degilseniz "Performance Log Users" grubuna ekleyin.'

        $pmCsv = Join-Path $runDir 'presentmon.csv'
        $pmLog = Join-Path $runDir 'presentmon.log'

        # PresentMon 2.x ek argumanlari destekler; 1.x desteklemez.
        $pmArgs = @('--process_name', 'cs2.exe', '--output_file', $pmCsv, '--timed', $Seconds)
        $pmMajor = 1
        try {
            $ver = (Get-Item $presentmon -ErrorAction Stop).VersionInfo.FileVersion
            if ($ver -match '^(\d+)') { $pmMajor = [int]$Matches[1] }
        } catch { }
        if ($pmMajor -ge 2) {
            $pmArgs += '--terminate_after_timed'
            $pmArgs += '--no_console_stats'
            Write-Info "PresentMon surumu: $pmMajor.x (2.x argumanlari kullanildi)"
        } else {
            Write-Info "PresentMon surumu: 1.x (uyumlu argumanlar kullanildi)"
        }

        try {
            $p = Start-Process -FilePath $presentmon -ArgumentList $pmArgs `
                -NoNewWindow -PassThru -RedirectStandardError $pmLog
            Start-Sleep -Seconds ([math]::Max($Seconds + 5, 10))
            if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
            Write-Ok "PresentMon output: $pmCsv"
        } catch {
            Write-Warn "PresentMon could not be started: $($_.Exception.Message)"
        }

        if (Test-Path $pmCsv) {
            try {
                $rows = Import-Csv $pmCsv -ErrorAction Stop
                # Kolon secimi surum-bagimsiz: PresentMon 1.x -> "FrameTime",
                # PresentMon 2.x -> "MsBetweenPresents". Ayristirma modulde.
                $frameResults = Get-FrameTimeStats -Rows $rows
                if ($frameResults) {
                    Write-Ok ("avg={0}ms  1%low={1}FPS  p99={2}ms  p99.9={3}ms  ~{4} FPS  (kolon: {5})" -f `
                        $frameResults.AvgMs, $frameResults.Low1FPS, $frameResults.P99Ms,
                        $frameResults.P999Ms, $frameResults.AvgFPS, $frameResults.Column)
                    if ($frameResults.Contains('InputLatencyAvgMs')) {
                        Write-Ok ("input-to-photon: ort={0}ms  p99={1}ms  (kolon: {2})" -f `
                            $frameResults.InputLatencyAvgMs, $frameResults.InputLatencyP99Ms,
                            $frameResults.InputLatencyColumn)
                    }
                } else {
                    Write-Warn 'PresentMon CSV parse edilemedi veya yeterli frame yok (CS2 calisiyor muydu?).'
                    Write-Info 'CSV basligini kontrol edin: frame time kolonu bekleniyor (FrameTime veya MsBetweenPresents).'
                }
            } catch {
                Write-Warn "PresentMon CSV okunamadı: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Warn 'PresentMon bulunamadı; frame time ölçümü atlandı.'
        Write-Info 'PresentMon indir: https://github.com/GameTechDev/PresentMon/releases'
    }

    if ($capframex) {
        Write-Step 'CapFrameX bulundu'
        Write-Info "Yol: $capframex"
        Write-Info 'CapFrameX kendi arayuzunden benchmark yapip CSV olarak disa aktarin;'
        Write-Info "sonra bu scripti -FrameCsv <dosya.csv> ile calistirin. Ayristirma otomatiktir."
    }

    if ($hwinfo) {
        Write-Step 'HWiNFO sensör kaydı (referans)'
        Write-Info "HWiNFO bulundu: $hwinfo"
        Write-Info 'HWiNFO sensör CSV kaydını aynı klasöre kaydet; WHEA kayıtlarını kontrol et.'
    }
}

# CapFrameX / PresentMon CSV disaridan aliniyorsa ayni istatistikler uretilir.
# -SkipGame kullanilsa da calisir (canli yakalama yapmadan analiz icin).
if ($FrameCsv) {
    Write-Step "Frame CSV analizi: $FrameCsv"
    try {
        $rows = Import-Csv $FrameCsv -ErrorAction Stop
        $imported = Get-FrameTimeStats -Rows $rows
        if ($imported) {
            $imported['Tool'] = 'Imported CSV'
            $imported['Source'] = $FrameCsv
            if ($frameResults) {
                $frameResults['Imported'] = $imported
            } else {
                $frameResults = $imported
            }
            Write-Ok ("CSV: avg={0}ms  1%low={1}FPS  0.1%low={2}FPS  p99={3}ms  (kolon: {4})" -f `
                $imported.AvgMs, $imported.Low1FPS, $imported.Low01FPS, $imported.P99Ms, $imported.Column)
            if ($imported.Contains('InputLatencyAvgMs')) {
                Write-Ok ("CSV input-to-photon: ort={0}ms  p99={1}ms" -f `
                    $imported.InputLatencyAvgMs, $imported.InputLatencyP99Ms)
            }
        } else {
            Write-Warn 'Frame CSV içinden frame time kolonu bulunamadı.'
        }
    } catch {
        Write-Warn "Frame CSV okunamadı: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# NIC counter DELTA (ölçüm aralığındaki paket kaybı)
# ---------------------------------------------------------------------------
Write-Step 'NIC statistics (delta)'
$nicAfter = Get-NicSnapshot
foreach ($name in $nicAfter.Keys) {
    $after = $nicAfter[$name]
    $before = $null
    if ($nicBefore.ContainsKey($name)) { $before = $nicBefore[$name] }
    $rxDisc = if ($before) { $after.ReceivedDiscarded - $before.ReceivedDiscarded } else { $after.ReceivedDiscarded }
    $rxErr  = if ($before) { $after.ReceivedErrors    - $before.ReceivedErrors }    else { $after.ReceivedErrors }
    $txDisc = if ($before) { $after.OutboundDiscarded - $before.OutboundDiscarded } else { $after.OutboundDiscarded }
    $txErr  = if ($before) { $after.OutboundErrors    - $before.OutboundErrors }    else { $after.OutboundErrors }
    $nicStats += [ordered]@{
        Name              = $after.Name
        LinkSpeed         = $after.LinkSpeed
        RxDiscardedDelta  = $rxDisc
        RxErrorsDelta     = $rxErr
        TxDiscardedDelta  = $txDisc
        TxErrorsDelta     = $txErr
        RxBytesDelta      = ($after.ReceivedBytes - $(if ($before) { $before.ReceivedBytes } else { 0 }))
        TxBytesDelta      = ($after.SentBytes     - $(if ($before) { $before.SentBytes }     else { 0 }))
    }
    $total = $rxDisc + $rxErr + $txDisc + $txErr
    if ($total -gt 0) {
        Write-Warn ("{0}: ölçüm aralığında {1} hata/discard (rx_disc={2} rx_err={3} tx_disc={4} tx_err={5})" -f `
            $after.Name, $total, $rxDisc, $rxErr, $txDisc, $txErr)
    } else {
        Write-Ok ("{0}: ölçüm aralığında hata/discard yok" -f $after.Name)
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Step 'Summary'
$summary = [ordered]@{
    GeneratedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Label        = $Label
    PollingHz    = $(if ($PollingHz -gt 0) { $PollingHz } else { 'N/A' })
    RunDirectory = $runDir
    System       = $snapshot
    GPU          = $gpuTelemetry
    Network      = $netResults
    NICStats     = $nicStats
    DNS          = $dnsTimes
    Frames       = $frameResults
}

$jsonPath = Join-Path $runDir 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# CS2 Benchmark Özeti')
$md.Add('')
$md.Add("> Etiket: **$Label**  ")
$md.Add("> Mouse polling: **$(if ($PollingHz -gt 0) { "$PollingHz Hz" } else { 'N/A' })**  ")
$md.Add("> Tarih: **$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))**  ")
$md.Add("> Klasör: ``$runDir``")
$md.Add('')
$md.Add('## Sistem')
$md.Add('')
$md.Add('| Alan | Değer |')
$md.Add('|---|---|')
foreach ($k in $snapshot.Keys) { $md.Add("| $k | $($snapshot[$k]) |") }
$md.Add('')
if ($gpuTelemetry) {
    $md.Add('## GPU')
    $md.Add('')
    $md.Add('| Alan | Değer |')
    $md.Add('|---|---|')
    foreach ($k in $gpuTelemetry.Keys) { $md.Add("| $k | $($gpuTelemetry[$k]) |") }
    $md.Add('')
}
if ($netResults.Count -gt 0) {
    $md.Add('## Ağ')
    $md.Add('')
    $md.Add('| Hedef | Kayıp % | Ort ms | Min ms | Max ms | Jitter ms | StdDev ms | Örnek | Timeout |')
    $md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
    foreach ($r in $netResults) {
        $md.Add("| $($r.Target) | $($r.PacketLoss) | $($r.AvgMs) | $($r.MinMs) | $($r.MaxMs) | $($r.JitterMs) | $($r.StdDevMs) | $($r.Samples) | $($r.Timeouts) |")
    }
    $md.Add('')
}
if ($nicStats.Count -gt 0) {
    $md.Add('## NIC istatistikleri (ölçüm aralığı farkı)')
    $md.Add('')
    $md.Add('| Adapter | Link | Rx discarded | Rx errors | Tx discarded | Tx errors |')
    $md.Add('|---|---|---:|---:|---:|---:|')
    foreach ($n in $nicStats) {
        $md.Add("| $($n.Name) | $($n.LinkSpeed) | $($n.RxDiscardedDelta) | $($n.RxErrorsDelta) | $($n.TxDiscardedDelta) | $($n.TxErrorsDelta) |")
    }
    $md.Add('')
}
if ($frameResults) {
    $md.Add('## Frame time')
    $md.Add('')
    $md.Add('| Metrik | Değer |')
    $md.Add('|---|---:|')
    foreach ($k in $frameResults.Keys) { if ($k -ne 'Source') { $md.Add("| $k | $($frameResults[$k]) |") } }
    $md.Add('')
    if ($frameResults.Contains('Low1FPS')) {
        $md.Add('> **Kabul kriterleri:** 1% low ≥ 280 FPS · p99 ≤ 4.0 ms · 0 paket kaybı')
        $md.Add('')
    }
}
$mdPath = Join-Path $runDir 'summary.md'
$md -join "`r`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Ok "Summary JSON : $jsonPath"
Write-Ok "Summary MD   : $mdPath"
Write-Info 'Bu script hiçbir ayarı değiştirmedi (read-only).'
Write-Info 'Karar: 3 run baseline → bir değişiklik → 3 run → 1% low ve frametime p99 karşılaştır.'

Get-ChildItem -Path $runDir -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
