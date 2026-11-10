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
    $text = ($out -join "`n")
    $m = [regex]::Match($text, 'Current AC Power Setting Index:\s*(0x[0-9a-fA-F]+)')
    if ($m.Success) { return [Convert]::ToInt32($m.Groups[1].Value, 16) }
    return $null
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

Export-ModuleMember -Function @(
    'Write-Step', 'Write-Info', 'Write-Ok', 'Write-Warn', 'Write-Err',
    'Get-RegValue', 'Test-RegValue', 'Set-RegDword', 'Set-RegString',
    'Backup-RegKey', 'Restore-RegBackups',
    'Get-LatestBackup', 'New-BackupDir',
    'Save-ServiceState', 'Restore-ServiceState',
    'Save-TaskState', 'Restore-TaskState',
    'Save-Flag', 'Get-Flag',
    'Split-PowerCfgAlias', 'Get-PowerCfgValue', 'Set-PowerCfgValue',
    'Backup-PowerCfgValue', 'Save-PowerCfgBackup', 'Restore-PowerCfgBackup', 'Reset-PowerCfgBackup',
    'Get-TargetAdapter', 'Get-NicProperties', 'Backup-NicProperties', 'Restore-NicProperties',
    'Set-NicPropertyByDisplayName', 'Set-NicPropertyByKeyword', 'Get-NicStatistics',
    'Format-Bytes', 'Format-Date', 'ConvertFrom-MonitorId', 'Get-DefaultGateway'
)
