#Requires -Version 5.1
<#
.SYNOPSIS
  CS2-Win10-Optimizer ortak yardımcı modülü.

.DESCRIPTION
  Tüm scriptlerde tekrar eden yardımcı fonksiyonlar burada toplanır:
    - Konsol çıktı yardımcıları (Write-Step/Info/Ok/Warn/Err)
    - Registry okuma/yazma (Get-RegValue, Set-RegDword, Set-RegString)
    - Registry yedekleme (Backup-RegKey) ve geri yükleme
    - powercfg okuma/yazma ve birebir geri alma (JSON tabanlı)
    - NIC gelişmiş özellik okuma/yazma (RegistryKeyword tabanlı, yerelden bağımsız)
    - Backup klasörü yönetimi

  Modül bir "read + backup + restore" katmanıdır; kendi başına hiçbir sistem
  değişikliği yapmaz.

.NOTES
  Import yolu:
    Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force
#>

$script:PowerCfgBackup = New-Object System.Collections.Generic.List[object]

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------
function Get-RegValue {
    <#
      .SYNOPSIS
        Bir registry değerini okur; yoksa $null döner.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

function Test-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return $null -ne (Get-RegValue -Path $Path -Name $Name)
}

function Set-RegDword {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegString {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Backup-RegKey {
    <#
      .SYNOPSIS
        Registry anahtarını .reg olarak yedekler. Anahtar yoksa dosya oluşmaz.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $safe = ($Key -replace '[:\\]', '_')
    $file = Join-Path $BackupDir "$safe.reg"
    & reg.exe export $Key $file /y 2>$null | Out-Null
    return $file
}

function Restore-RegBackups {
    param([Parameter(Mandatory = $true)][string]$BackupDir)
    $count = 0
    Get-ChildItem -Path $BackupDir -Filter '*.reg' -ErrorAction SilentlyContinue | ForEach-Object {
        & reg.exe import $_.FullName 2>$null | Out-Null
        $count++
    }
    return $count
}

# ---------------------------------------------------------------------------
# Backup klasörü
# ---------------------------------------------------------------------------
function Get-LatestBackup {
    <#
      .SYNOPSIS
        Masaüstündeki en yeni backup klasörünü döner.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [string]$Desktop = [Environment]::GetFolderPath('Desktop')
    )
    Get-ChildItem -Path $Desktop -Directory -Filter $Pattern -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function New-BackupDir {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [string]$Desktop = [Environment]::GetFolderPath('Desktop'),
        [string]$Stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    )
    $dir = Join-Path $Desktop "$Prefix-$Stamp"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ---------------------------------------------------------------------------
# powercfg
# ---------------------------------------------------------------------------
function Split-PowerCfgAlias {
    <#
      .SYNOPSIS
        "SUB_PROCESSOR PROCTHROTTLEMIN" gibi çok kelimeli alias'ı parçalarına ayırır.
        powercfg bu alias'ı TEK argüman olarak kabul etmez.
    #>
    param([Parameter(Mandatory = $true)][string]$Alias)
    return @($Alias -split '\s+' | Where-Object { $_ })
}

function ConvertFrom-PowerCfgText {
    <#
      .SYNOPSIS
        "powercfg /query" çıktısından AC (alternatif akım) değerini döner.

      .DESCRIPTION
        DİL-BAĞIMSIZ ÇÖZÜMLERİCİ.

        Eski yaklaşım 'Current AC Power Setting Index:' etiketini arıyordu.
        Bu etiket Windows diline göre değişir:
          - EN: "Current AC Power Setting Index: 0x00000005"
          - TR: "Mevcut AC Güç Ayarı Dizinü: 0x00000005"
        Türkçe Windows'ta eşleşme başarısız olur ve tüm güç planı
        kontrolleri sessizce $null dönerdi.

        Yeni yaklaşım etikete güvenmez:
          1) Hex değer içeren satırlar bulunur (0x...). GUID satırları "0x"
            içermediği için elenir.
          2) Etiketinde AC/CA geçen satır tercih edilir.
          3) Bulunamazsa İLK hex satır kullanılır — powercfg AC satırını
            her zaman DC satırından ÖNCE yazar, bu yüzden bu güvenlidir.

      .PARAMETER Text
        powercfg /query çıktısının tam metni.

      .OUTPUTS
        [int] Değer veya $null.
    #>
    param([AllowEmptyString()][string]$Text)

    if (-not $Text) { return $null }

    $pairs = @()
    foreach ($line in ($Text -split "`r?`n")) {
        $m = [regex]::Match($line, '(?i)(0x[0-9a-f]{8})')
        if ($m.Success) {
            $pairs += [pscustomobject]@{
                Label = $line.Substring(0, $m.Index)
                Value = $m.Groups[1].Value
            }
        }
    }
    if ($pairs.Count -eq 0) { return $null }

    $ac = $pairs | Where-Object { $_.Label -match '(?i)\b(ac|ca)\b' } | Select-Object -First 1
    if (-not $ac) { $ac = $pairs[0] }

    return [Convert]::ToInt32($ac.Value, 16)
}

function Get-PowerCfgValue {
    <#
      .SYNOPSIS
        Bir powercfg ayarının mevcut AC değerini döner (yoksa $null).
    #>
    param([Parameter(Mandatory = $true)][string]$Alias)
    $parts = Split-PowerCfgAlias -Alias $Alias
    if ($parts.Count -eq 0) { return $null }
    $out = & powercfg.exe /query SCHEME_CURRENT @parts 2>$null
    if (-not $out) { return $null }
    return (ConvertFrom-PowerCfgText -Text ($out -join "`n"))
}

function Set-PowerCfgValue {
    param(
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][int]$Value
    )
    $parts = Split-PowerCfgAlias -Alias $Alias
    & powercfg.exe /setacvalueindex SCHEME_CURRENT @parts $Value 2>$null | Out-Null
    Write-Ok "$Alias = $Value"
}

function Backup-PowerCfgValue {
    <#
      .SYNOPSIS
        Bir powercfg ayarının mevcut değerini modül oturumunda saklar.
    #>
    param([Parameter(Mandatory = $true)][string]$Alias)
    $v = Get-PowerCfgValue -Alias $Alias
    if ($null -eq $v) {
        Write-Warn "Could not read current value for $Alias; it will not be restored individually."
        return
    }
    $script:PowerCfgBackup.Add([ordered]@{ Alias = $Alias; Value = $v })
    Write-Info "Saved $Alias = $v"
}

function Save-PowerCfgBackup {
    param([Parameter(Mandatory = $true)][string]$BackupDir)
    if ($script:PowerCfgBackup.Count -eq 0) { return }
    $script:PowerCfgBackup | ConvertTo-Json -Depth 4 |
        Set-Content -Path (Join-Path $BackupDir 'powercfg-backup.json') -Encoding UTF8
    Write-Ok 'Power setting values saved: powercfg-backup.json'
}

function Restore-PowerCfgBackup {
    param([Parameter(Mandatory = $true)][string]$BackupDir)
    $file = Join-Path $BackupDir 'powercfg-backup.json'
    if (-not (Test-Path $file)) { return 0 }
    $entries = Get-Content $file -Raw | ConvertFrom-Json
    $count = 0
    foreach ($entry in @($entries)) {
        $parts = Split-PowerCfgAlias -Alias $entry.Alias
        & powercfg.exe /setacvalueindex SCHEME_CURRENT @parts $entry.Value 2>$null | Out-Null
        Write-Ok "Power setting restored: $($entry.Alias) = $($entry.Value)"
        $count++
    }
    & powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null
    return $count
}

function Reset-PowerCfgBackup {
    $script:PowerCfgBackup.Clear()
}

# ---------------------------------------------------------------------------
# NIC
# ---------------------------------------------------------------------------
function Get-TargetAdapter {
    <#
      .SYNOPSIS
        Aktif fiziksel Ethernet adaptörünü bulur.
    #>
    param([string]$Explicit)
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    if ($Explicit) {
        return ($adapters | Where-Object { $_.Name -eq $Explicit } | Select-Object -First 1)
    }
    $up = $adapters | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($up) { return $up }
    return ($adapters | Select-Object -First 1)
}

function Get-NicProperties {
    param([Parameter(Mandatory = $true)][string]$AdapterName)
    return @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue)
}

function Backup-NicProperties {
    param(
        [Parameter(Mandatory = $true)][string]$AdapterName,
        [Parameter(Mandatory = $true)][object[]]$Properties,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $save = @($Properties | Select-Object Name, DisplayName, DisplayValue, RegistryKeyword)
    $save | ConvertTo-Json -Depth 4 |
        Set-Content -Path (Join-Path $BackupDir 'nic-backup.json') -Encoding UTF8
    Write-Ok 'NIC properties saved: nic-backup.json'
}

function Restore-NicProperties {
    param([Parameter(Mandatory = $true)][string]$BackupDir)
    $file = Join-Path $BackupDir 'nic-backup.json'
    if (-not (Test-Path $file)) { return 0 }
    $items = Get-Content $file -Raw | ConvertFrom-Json
    $count = 0
    foreach ($item in @($items)) {
        if ($item.Name -and $item.DisplayName) {
            Set-NetAdapterAdvancedProperty -Name $item.Name -DisplayName $item.DisplayName -DisplayValue $item.DisplayValue -ErrorAction SilentlyContinue
            $count++
        }
    }
    Write-Ok 'NIC advanced properties restored.'
    return $count
}

function Set-NicPropertyByDisplayName {
    <#
      .SYNOPSIS
        NIC gelişmiş özelliğini DisplayName ile ayarlar.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$AdapterName,
        [Parameter(Mandatory = $true)][object[]]$Properties,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $p = $Properties | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1
    if (-not $p) {
        Write-Info "$DisplayName not present on this adapter; skipped."
        return $false
    }
    try {
        Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $p.DisplayName -DisplayValue $Value -ErrorAction Stop
        Write-Ok "$DisplayName = $Value"
        return $true
    } catch {
        Write-Warn "$DisplayName could not be changed: $($_.Exception.Message)"
        return $false
    }
}

function Set-NicPropertyByKeyword {
    <#
      .SYNOPSIS
        NIC gelişmiş özelliğini RegistryKeyword ile ayarlar (yerelden bağımsız).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$AdapterName,
        [Parameter(Mandatory = $true)][object[]]$Properties,
        [Parameter(Mandatory = $true)][string]$KeywordPattern,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $p = $Properties | Where-Object { $_.RegistryKeyword -match $KeywordPattern } | Select-Object -First 1
    if (-not $p) {
        Write-Info "No property matching '$KeywordPattern'; skipped."
        return $false
    }
    try {
        Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $p.DisplayName -DisplayValue $Value -ErrorAction Stop
        Write-Ok "$($p.DisplayName) = $Value"
        return $true
    } catch {
        Write-Warn "$($p.DisplayName) could not be changed: $($_.Exception.Message)"
        return $false
    }
}

function Get-NicStatistics {
    param([string]$AdapterName)
    $result = @()
    $adapters = if ($AdapterName) {
        @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $AdapterName })
    } else {
        @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    }
    foreach ($a in $adapters) {
        $s = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        $result += [ordered]@{
            Name              = $a.Name
            LinkSpeed         = [string]$a.LinkSpeed
            ReceivedDiscarded = $s.ReceivedDiscardedPackets
            ReceivedErrors    = $s.ReceivedPacketErrors
            OutboundDiscarded = $s.OutboundDiscardedPackets
            OutboundErrors    = $s.OutboundPacketErrors
            ReceivedBytes     = $s.ReceivedBytes
            SentBytes         = $s.SentBytes
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Servis / zamanlanmış görev durumu
# ---------------------------------------------------------------------------
function Save-ServiceState {
    <#
      .SYNOPSIS
        Bir servisin StartType ve Status değerini yedekler.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $state = [ordered]@{
        Name      = $svc.Name
        StartType = [string]$svc.StartType
        Status    = [string]$svc.Status
    }
    $state | ConvertTo-Json -Depth 3 |
        Set-Content -Path (Join-Path $BackupDir "service-$Name.json") -Encoding UTF8
    return $state
}

function Restore-ServiceState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $path = Join-Path $BackupDir "service-$Name.json"
    if (-not (Test-Path $path)) { return $false }
    try {
        $state = Get-Content $path -Raw | ConvertFrom-Json
        if ($state.StartType) {
            Set-Service -Name $Name -StartupType $state.StartType -ErrorAction SilentlyContinue
        }
        if ($state.Status -eq 'Running') {
            Start-Service -Name $Name -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Warn "Service restore failed for $Name : $($_.Exception.Message)"
        return $false
    }
}

function Save-TaskState {
    <#
      .SYNOPSIS
        Bir zamanlanmış görevin durumunu yedekler.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $null }
    $state = [ordered]@{
        TaskPath = $TaskPath
        TaskName = $TaskName
        State    = [string]$task.State
    }
    $safe = ($TaskPath + $TaskName -replace '[\\/:*?"<>|]', '_')
    $state | ConvertTo-Json -Depth 3 |
        Set-Content -Path (Join-Path $BackupDir "task-$safe.json") -Encoding UTF8
    return $state
}

function Restore-TaskState {
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $safe = ($TaskPath + $TaskName -replace '[\\/:*?"<>|]', '_')
    $path = Join-Path $BackupDir "task-$safe.json"
    if (-not (Test-Path $path)) { return $false }
    try {
        $state = Get-Content $path -Raw | ConvertFrom-Json
        if ($state.State -eq 'Ready' -or $state.State -eq 'Running') {
            Enable-ScheduledTask -TaskPath $state.TaskPath -TaskName $state.TaskName -ErrorAction SilentlyContinue | Out-Null
        }
        return $true
    } catch {
        Write-Warn "Task restore failed for $TaskPath$TaskName : $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Basit flag yedekleme (revert için)
# ---------------------------------------------------------------------------
function Save-Flag {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Value,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $flag = [ordered]@{ Name = $Name; Value = $Value }
    $flag | ConvertTo-Json -Depth 3 |
        Set-Content -Path (Join-Path $BackupDir "$Name.flag.json") -Encoding UTF8
}

function Get-Flag {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )
    $path = Join-Path $BackupDir "$Name.flag.json"
    if (-not (Test-Path $path)) { return $null }
    try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------------------
# Format yardımcıları
# ---------------------------------------------------------------------------
function Format-Bytes {
    param([Nullable[double]]$Bytes)
    if ($null -eq $Bytes -or $Bytes -le 0) { return 'N/A' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt ($units.Count - 1)) { $v /= 1024; $i++ }
    return ('{0:N2} {1}' -f $v, $units[$i])
}

function Format-Date {
    param($Value)
    if ($null -eq $Value) { return 'N/A' }
    try { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss') } catch { return [string]$Value }
}

function ConvertFrom-MonitorId {
    <#
      .SYNOPSIS
        WMI monitör ID dizisini okunabilir metne çevirir.
    #>
    param($Value)
    if ($null -eq $Value) { return 'N/A' }
    try {
        $chars = @($Value) | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }
        $text = (-join $chars).Trim()
        if ($text) { return $text }
        return 'N/A'
    } catch {
        return 'N/A'
    }
}

function Get-DefaultGateway {
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1
        if ($route) { return $route.NextHop }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
# Olcum cozumleyicileri (dil/versiyon bagimsiz)
# ---------------------------------------------------------------------------
function ConvertFrom-PingOutput {
    <#
      .SYNOPSIS
        ping.exe ciktisini dil bagimsiz olarak ayristirir.

      .DESCRIPTION
        DİL-BAĞIMSIZ ÇÖZÜMLERİCİ.

        Eski yaklasim `time[=<]\s*(\d+)\s*ms` ve
        `\((\d+)%\s+(packet\s+)?loss\)` regex'lerini kullaniyordu. Bu
        regexler Turkce Windows'ta KIRILIR:

          EN yanit : "64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=14 ms"
          TR  yanit : "8.8.8.8 yanıt: bayt=32 süre=14ms TTL=116"

          EN ozet   : "Lost = 0 (0% loss)"
          TR  ozet   : "Kaybedilen = 0 (0% kayıp)"

        Sonuc: Turkce Windows'ta RTT listesi BOS, kayip %null,
        jitter null -> ag olcumu tamamen islevsiz kaliyordu.

        Yeni yaklasim:
          1) "statistik/statistics" basligindan sonraki bolum (ozet) ayrilir.
          2) Yanit satirlari IPv4 adresi ICEREN satirlardir; her satirdan
             sure degeri ("süre", "time", "zeit", ...) veya genel
             "<sayi> ms" deseni cikarilir.
          3) Ozet bolumden kayip yuzdesi parantez icinden okunur; yoksa
             "Lost/Kaybedilen" ve "Sent/Gonderilen" sayilarindan hesaplanir.

      .PARAMETER Text
        ping.exe ciktisinin tam metni.

      .OUTPUTS
        [hashtable] Target yoksa Target alani disarida birakilir.
    #>
    param([AllowEmptyString()][string]$Text)

    $result = [ordered]@{
        PacketLoss = $null
        AvgMs      = $null
        MinMs      = $null
        MaxMs      = $null
        JitterMs   = $null
        StdDevMs   = $null
        Samples    = 0
        Timeouts   = 0
    }
    if (-not $Text) { return $result }

    $lines = @($Text -split "`r?`n")

    # 1) Ozet blogunu ayir
    $statsIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)(statistik|statistics|statistiques|statistiken|estad[ií]sticas)') {
            $statsIdx = $i
            break
        }
    }
    $replyLines = @()
    $statsLines = @()
    if ($statsIdx -ge 0) {
        if ($statsIdx -gt 0) { $replyLines = $lines[0..($statsIdx - 1)] }
        $statsLines = $lines[$statsIdx..($lines.Count - 1)]
    } else {
        $replyLines = $lines
    }

    # 2) RTT ornekleri
    $rtt = New-Object System.Collections.Generic.List[double]
    $timeouts = 0
    foreach ($line in $replyLines) {
        if ($line -match '(?i)(zaman\s*a[sş][iı]m[iı]|timed\s*out|timeout|u[gğ]rad[iı])') {
            $timeouts++
            continue
        }
        # Yanit satiri mutlaka bir IPv4 adresi icerir
        if ($line -notmatch '\d{1,3}(\.\d{1,3}){3}') { continue }
        $m = [regex]::Match($line, '(?i)(s\u00FCre|saat|time|zeit|temps|duraci\u00F3n|tiempo)\s*[=<]\s*(\d+(?:\.\d+)?)\s*ms')
        if (-not $m.Success) {
            $m = [regex]::Match($line, '(?i)(\d+(?:\.\d+)?)\s*ms')
        }
        if ($m.Success) {
            $val = 0.0
            # NOT: 2 argümanlı TryParse CurrentCulture kullanır. Türkçe locale'de
            # "14,5" gibi virgüllü değerler hatalı ayrıştırılır; InvariantCulture şart.
            if ([double]::TryParse($m.Groups[$m.Groups.Count - 1].Value,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
                if ($val -gt 0) { $rtt.Add($val) }
            }
        }
    }

    # 3) Kayip yuzdesi
    $statsText = ($statsLines -join "`n")
    if ($statsText) {
        $lm = [regex]::Match($statsText, '\(\s*(\d+)\s*%')
        if ($lm.Success) {
            $result.PacketLoss = [int]$lm.Groups[1].Value
        } else {
            $lost = [regex]::Match($statsText, '(?i)(lost|kaybedilen)\s*=\s*(\d+)')
            $sent = [regex]::Match($statsText, '(?i)(sent|g[öo]nderilen)\s*=\s*(\d+)')
            if ($lost.Success -and $sent.Success) {
                $sentVal = [int]$sent.Groups[1].Value
                if ($sentVal -gt 0) {
                    $result.PacketLoss = [math]::Round(
                        (100.0 * [int]$lost.Groups[1].Value) / $sentVal, 2)
                }
            }
        }
    }

    # 4) Istatistikler
    if ($rtt.Count -gt 0) {
        $arr = $rtt.ToArray()
        $avg = ($arr | Measure-Object -Average).Average
        $result.Samples  = $arr.Count
        $result.AvgMs    = [math]::Round($avg, 2)
        $result.MinMs    = ($arr | Measure-Object -Minimum).Minimum
        $result.MaxMs    = ($arr | Measure-Object -Maximum).Maximum
        $result.StdDevMs = [math]::Round([math]::Sqrt(
            (($arr | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Sum).Sum) / $arr.Count), 3)
        # Jitter = ardışık RTT örnekleri arasındaki mutlak farkların ortalaması.
        # (Eski "ortalama - en küçük" formülü jitter değildir.)
        if ($arr.Count -gt 1) {
            $sum = 0.0
            for ($i = 1; $i -lt $arr.Count; $i++) {
                $sum += [math]::Abs($arr[$i] - $arr[$i - 1])
            }
            $result.JitterMs = [math]::Round($sum / ($arr.Count - 1), 3)
        }
    }
    $result.Timeouts = $timeouts
    return $result
}

function Get-FrameTimeStats {
    <#
      .SYNOPSIS
        PresentMon / CapFrameX CSV'sinden frame time istatistiklerini hesaplar.

      .DESCRIPTION
        SÜRÜM-BAĞIMSIZ ÇÖZÜMLERİCİ.

        PresentMon 1.x CSV'sinde  "FrameTime"  kolonu vardır.
        PresentMon 2.x VARSAYILAN metriklerinde "FrameTime" kolonu YOKTUR;
        bunun yerine "MsBetweenPresents" bulunur.

        Eski kod yalnızca `$r.FrameTime` okuyordu. PresentMon 2.x (bugün
        indirilen sürüm) ile CSV'de o kolon bulunmadığından 0 frame
        parse ediliyor ve olcum sessizce BASARISIZ oluyordu.

        Bu fonksiyon:
          - Aday kolon listesinden bulunabilen ilk frame time kolonunu seçer
          - 1% low ve 0.1% low hesaplar (projenin kabul kriteri)
          - Input-to-photon (girdi-gecikme) ve display latency raporlar
          - Oyun filtresi uygular (Application kolonu varsa)

      .PARAMETER Rows
        Import-Csv ile okunmuş satırlar.

      .PARAMETER ApplicationFilter
        Application kolonunda aranacak metin (bos ise filtre uygulanmaz).

      .OUTPUTS
        [hashtable] veya $null (veri yoksa).
    #>
    [CmdletBinding()]
    param(
        [object[]]$Rows,
        [string]$ApplicationFilter = 'cs2',
        [string[]]$TimeColumns = @(
            'FrameTime', 'MsBetweenPresents', 'FrameTime (ms)', 'FrameTime(ms)',
            'frametime', 'Frame Time', 'frametime(ms)', 'MsUntilDisplayed'
        ),
        [string[]]$InputLatencyColumns = @(
            'MsAllInputToPhotonLatency', 'MsClickToPhotonLatency',
            'AllInputToPhasesLatency', 'InputLatency'
        ),
        [string[]]$DisplayLatencyColumns = @(
            'DisplayLatency', 'MsUntilDisplayed', 'MsRenderPresentLatency'
        )
    )

    if (-not $Rows -or $Rows.Count -eq 0) { return $null }

    $names = @($Rows[0].PSObject.Properties.Name)

    function Select-Column {
        param([string[]]$Candidates, [string[]]$Available)
        foreach ($c in $Candidates) {
            $hit = $Available | Where-Object { $_ -eq $c } | Select-Object -First 1
            if ($hit) { return $hit }
        }
        return $null
    }

    $timeCol = Select-Column -Candidates $TimeColumns -Available $names
    if (-not $timeCol) { return $null }

    $appCol = Select-Column -Candidates @('Application', 'ProcessName') -Available $names
    $inCol  = Select-Column -Candidates $InputLatencyColumns -Available $names
    $dspCol = Select-Column -Candidates $DisplayLatencyColumns -Available $names

    $times  = New-Object System.Collections.Generic.List[double]
    $inputs = New-Object System.Collections.Generic.List[double]
    $disps  = New-Object System.Collections.Generic.List[double]

    foreach ($r in $Rows) {
        if ($appCol -and $ApplicationFilter) {
            $app = [string]$r.$appCol
            if ($app -and ($app -notlike "*$ApplicationFilter*")) { continue }
        }
        # NOT: 2 argümanlı TryParse CurrentCulture kullanır. PresentMon CSV'si
        # nokta ile ondalık yazar; Türkçe locale'de "2.780" -> 2780 olurdu
        # (1000 kat hatalı frame time). InvariantCulture zorunlu.
        $v = 0.0
        $raw = $r.$timeCol
        if ($null -ne $raw -and [double]::TryParse([string]$raw,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
            if ($v -gt 0) { $times.Add($v) }
        }
        if ($inCol) {
            $iv = 0.0
            $rawIn = $r.$inCol
            if ($null -ne $rawIn -and [double]::TryParse([string]$rawIn,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$iv)) {
                if ($iv -gt 0) { $inputs.Add($iv) }
            }
        }
        if ($dspCol) {
            $dv = 0.0
            $rawDsp = $r.$dspCol
            if ($null -ne $rawDsp -and [double]::TryParse([string]$rawDsp,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$dv)) {
                if ($dv -gt 0) { $disps.Add($dv) }
            }
        }
    }

    if ($times.Count -eq 0) { return $null }

    $sorted = @($times | Sort-Object)
    $avg    = ($times | Measure-Object -Average).Average

    function Get-Percentile {
        param([double[]]$Sorted, [double]$Pct)
        if ($Sorted.Count -eq 0) { return $null }
        $idx = [math]::Max(0, [math]::Ceiling($Sorted.Count * $Pct) - 1)
        return $Sorted[[math]::Min($idx, $Sorted.Count - 1)]
    }

    function Get-LowPercent {
        param([double[]]$Sorted, [double]$Fraction)
        # En yavaş %Fraction karelerin ORTALAMA frame time'ı (1% low tanımı)
        $take = [math]::Max(1, [int][math]::Ceiling($Sorted.Count * $Fraction))
        $tail = $Sorted[($Sorted.Count - $take)..($Sorted.Count - 1)]
        return ($tail | Measure-Object -Average).Average
    }

    $low1Ms  = Get-LowPercent -Sorted $sorted -Fraction 0.01
    $low01Ms = Get-LowPercent -Sorted $sorted -Fraction 0.001

    $stats = [ordered]@{
        Column      = $timeCol
        Frames      = $times.Count
        AvgMs       = [math]::Round($avg, 3)
        MinMs       = ($times | Measure-Object -Minimum).Minimum
        MaxMs       = ($times | Measure-Object -Maximum).Maximum
        P99Ms       = [math]::Round((Get-Percentile -Sorted $sorted -Pct 0.99), 3)
        P999Ms      = [math]::Round((Get-Percentile -Sorted $sorted -Pct 0.999), 3)
        Low1Ms      = [math]::Round($low1Ms, 3)
        Low1FPS     = [math]::Round((1000.0 / $low1Ms), 1)
        Low01Ms     = [math]::Round($low01Ms, 3)
        Low01FPS    = [math]::Round((1000.0 / $low01Ms), 1)
        AvgFPS      = [math]::Round((1000.0 / $avg), 1)
    }

    if ($inputs.Count -gt 0) {
        $is = @($inputs | Sort-Object)
        $stats['InputLatencyAvgMs'] = [math]::Round(($inputs | Measure-Object -Average).Average, 3)
        $stats['InputLatencyP99Ms'] = [math]::Round((Get-Percentile -Sorted $is -Pct 0.99), 3)
        $stats['InputLatencyMaxMs'] = [math]::Round((Get-Percentile -Sorted $is -Pct 1.0), 3)
        $stats['InputLatencyColumn'] = $inCol
    }
    if ($disps.Count -gt 0) {
        $ds = @($disps | Sort-Object)
        $stats['DisplayLatencyAvgMs'] = [math]::Round(($disps | Measure-Object -Average).Average, 3)
        $stats['DisplayLatencyP99Ms'] = [math]::Round((Get-Percentile -Sorted $ds -Pct 0.99), 3)
        $stats['DisplayLatencyColumn'] = $dspCol
    }

    return $stats
}

Export-ModuleMember -Function @(
    'Write-Step', 'Write-Info', 'Write-Ok', 'Write-Warn', 'Write-Err',
    'Get-RegValue', 'Test-RegValue', 'Set-RegDword', 'Set-RegString',
    'Backup-RegKey', 'Restore-RegBackups',
    'Get-LatestBackup', 'New-BackupDir',
    'Save-ServiceState', 'Restore-ServiceState',
    'Save-TaskState', 'Restore-TaskState',
    'Save-Flag', 'Get-Flag',
    'Split-PowerCfgAlias', 'ConvertFrom-PowerCfgText',
    'Get-PowerCfgValue', 'Set-PowerCfgValue',
    'Backup-PowerCfgValue', 'Save-PowerCfgBackup', 'Restore-PowerCfgBackup', 'Reset-PowerCfgBackup',
    'Get-TargetAdapter', 'Get-NicProperties', 'Backup-NicProperties', 'Restore-NicProperties',
    'Set-NicPropertyByDisplayName', 'Set-NicPropertyByKeyword', 'Get-NicStatistics',
    'Format-Bytes', 'Format-Date', 'ConvertFrom-MonitorId', 'Get-DefaultGateway',
    'ConvertFrom-PingOutput', 'Get-FrameTimeStats'
)
