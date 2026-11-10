#Requires -Version 5.1
<#
.SYNOPSIS
  CS2-Win10-Optimizer için tekrarlanabilir ölçüm (benchmark) motoru.

.DESCRIPTION
  Projenin temel felsefesi: "tek değişiklik → ölçüm → karar". Bu script o ölçümü
  otomatikleştirir. Kendisi hiçbir ayarı DEĞİŞTİRMEZ; yalnızca ölçer ve raporlar.

  Yetenekleri:
    - CapFrameX varsa: oyun içi benchmark otomatik başlatılır, CSV çıktısı alınır
      (avg / 1% low / 0.1% low / frametime p99).
    - CapFrameX yoksa: PresentMon ile frame time + present latency toplanır.
    - HWiNFO64 sensörleri (varsa) CSV olarak toplanır (CPU/GPU clock, sıcaklık, WHEA).
    - LatencyMon yoksa: atlanır (DPC/ISR ölçümü manuel).
    - Ağ: hedeflere ICMP ping serisi ile jitter ve paket kaybı ölçülür.
    - NIC: discard/error sayaçları okunur (paket kaybı göstergesi).
    - Tüm sonuçlar tek klasörde toplanır ve özet Markdown/JSON olarak yazılır.

  Bu script read-only'dir: registry, servis, güç planı veya BIOS değiştirmez.

.PARAMETER OutputDirectory
  Sonuçların yazılacağı klasör. Varsayılan: Masaüstü.

.PARAMETER CapFrameXPath
  CapFrameX.exe yolu. Bulunamazsa otomatik aranır.

.PARAMETER PresentMonPath
  PresentMon.exe yolu. Bulunamazsa otomatik aranır.

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
Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop
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

    $loss = $null
    $m = [regex]::Match($text, '\((\d+)%\s+(packet\s+)?loss\)')
    if ($m.Success) { $loss = [int]$m.Groups[1].Value }

    $rtt = @()
    foreach ($line in $out) {
        $rm = [regex]::Match([string]$line, 'time[=<]\s*(\d+)\s*ms')
        if ($rm.Success) { $rtt += [int]$rm.Groups[1].Value }
    }

    $avg = $null; $min = $null; $max = $null; $jitter = $null
    if ($rtt.Count -gt 0) {
        $avg = [math]::Round(($rtt | Measure-Object -Average).Average, 2)
        $min = ($rtt | Measure-Object -Minimum).Minimum
        $max = ($rtt | Measure-Object -Maximum).Maximum
        if ($rtt.Count -gt 1) {
            $jitter = [math]::Round((($rtt | Measure-Object -Average).Average) - (($rtt | Measure-Object -Minimum).Minimum), 2)
        }
    }

    return [ordered]@{
        Target      = $Target
        PacketLoss  = $loss
        AvgMs       = $avg
        MinMs       = $min
        MaxMs       = $max
        JitterMs    = $jitter
        Samples     = $rtt.Count
        RawOutput   = ($out | Select-Object -Last 6)
    }
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
$snapshot = [ordered]@{
    Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Label     = $Label
    PollingHz = $(if ($PollingHz -gt 0) { $PollingHz } else { 'N/A' })
    Computer  = $env:COMPUTERNAME
    OS        = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    Build     = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
    CPU       = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    RAM_GB    = [math]::Round(((Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object Capacity -Sum).Sum / 1GB), 1)
    GPU       = ((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1).Name)
    GPUDriver = ((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1).DriverVersion)
    PowerPlan = ((& powercfg.exe /getactivescheme 2>$null) -join ' ')
    HwSchMode = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
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
$netResults = @()
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

    # NIC error / discard counters (packet loss indicators)
    Write-Step 'NIC statistics'
    $nicStats = @()
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        foreach ($a in $adapters) {
            $s = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
            if ($s) {
                $nicStats += [ordered]@{
                    Name               = $a.Name
                    LinkSpeed          = [string]$a.LinkSpeed
                    ReceivedDiscarded  = $s.ReceivedDiscardedPackets
                    ReceivedErrors     = $s.ReceivedPacketErrors
                    OutboundDiscarded  = $s.OutboundDiscardedPackets
                    OutboundErrors     = $s.OutboundPacketErrors
                    ReceivedBytes      = $s.ReceivedBytes
                    SentBytes          = $s.SentBytes
                }
                Write-Info ("{0}: rx_discarded={1} rx_errors={2} tx_discarded={3} tx_errors={4}" -f `
                    $a.Name, $s.ReceivedDiscardedPackets, $s.ReceivedPacketErrors, $s.OutboundDiscardedPackets, $s.OutboundPacketErrors)
            }
        }
    } catch {
        Write-Warn "Adapter statistics unavailable: $($_.Exception.Message)"
    }

    # DNS resolution time
    Write-Step 'DNS resolution'
    $dnsTimes = @()
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
        $pmCsv = Join-Path $runDir 'presentmon.csv'
        $pmLog = Join-Path $runDir 'presentmon.log'
        try {
            $p = Start-Process -FilePath $presentmon `
                -ArgumentList @('--process_name', 'cs2.exe', '--output_file', $pmCsv, '--timed', $Seconds) `
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
                $frames = @()
                foreach ($r in $rows) {
                    $ft = $r.FrameTime
                    if ($ft) {
                        $v = 0.0
                        if ([double]::TryParse($ft, [ref]$v)) { $frames += $v }
                    }
                }
                if ($frames.Count -gt 10) {
                    $sorted = @($frames | Sort-Object)
                    $avg = ($frames | Measure-Object -Average).Average
                    $p99 = $sorted[[math]::Max(0, [math]::Floor($sorted.Count * 0.99) - 1)]
                    $p999 = $sorted[[math]::Max(0, [math]::Floor($sorted.Count * 0.999) - 1)]
                    $fpsAvg = if ($avg -gt 0) { 1000.0 / $avg } else { 0 }
                    $frameResults = [ordered]@{
                        Tool       = 'PresentMon'
                        Frames     = $frames.Count
                        AvgMs      = [math]::Round($avg, 3)
                        P99Ms      = [math]::Round($p99, 3)
                        P999Ms     = [math]::Round($p999, 3)
                        AvgFPS     = [math]::Round($fpsAvg, 1)
                        Source     = $pmCsv
                    }
                    Write-Ok ("avg={0}ms  p99={1}ms  p99.9={2}ms  ~{3} FPS" -f `
                        $frameResults.AvgMs, $frameResults.P99Ms, $frameResults.P999Ms, $frameResults.AvgFPS)
                } else {
                    Write-Warn 'PresentMon CSV parse edilemedi veya yeterli frame yok (CS2 çalışıyor muydun?).'
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
        Write-Info 'CapFrameX CLI ile otomatik yakalama mümkündür; ayrıca elle benchmark yapabilirsin.'
        Write-Info 'Proje dokümanı: RAPOR.md bölüm 2 (ölçüm protokolü).'
    }

    if ($hwinfo) {
        Write-Step 'HWiNFO sensör kaydı (referans)'
        Write-Info "HWiNFO bulundu: $hwinfo"
        Write-Info 'HWiNFO sensör CSV kaydını aynı klasöre kaydet; WHEA kayıtlarını kontrol et.'
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
    $md.Add('| Hedef | Kayıp % | Ort ms | Min ms | Max ms | Jitter ms |')
    $md.Add('|---|---:|---:|---:|---:|---:|')
    foreach ($r in $netResults) {
        $md.Add("| $($r.Target) | $($r.PacketLoss) | $($r.AvgMs) | $($r.MinMs) | $($r.MaxMs) | $($r.JitterMs) |")
    }
    $md.Add('')
}
if ($nicStats.Count -gt 0) {
    $md.Add('## NIC istatistikleri')
    $md.Add('')
    $md.Add('| Adapter | Link | Rx discarded | Rx errors | Tx discarded | Tx errors |')
    $md.Add('|---|---|---:|---:|---:|---:|')
    foreach ($n in $nicStats) {
        $md.Add("| $($n.Name) | $($n.LinkSpeed) | $($n.ReceivedDiscarded) | $($n.ReceivedErrors) | $($n.OutboundDiscarded) | $($n.OutboundErrors) |")
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
}
$mdPath = Join-Path $runDir 'summary.md'
$md -join "`r`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Ok "Summary JSON : $jsonPath"
Write-Ok "Summary MD   : $mdPath"
Write-Info 'Bu script hiçbir ayarı değiştirmedi (read-only).'
Write-Info 'Karar: 3 run baseline → bir değişiklik → 3 run → 1% low ve frametime p99 karşılaştır.'

Get-ChildItem -Path $runDir -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
