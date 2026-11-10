#Requires -Version 5.1
<#
.SYNOPSIS
  CS2-Win10-Optimizer için sistem envanteri ve mevcut ayar raporu üretir.

.DESCRIPTION
  Windows 10 üzerinde çalışır. Donanım, monitör, depolama, ağ, güç planı,
  HAGS/GameDVR/scheduler durumu, Defender exclusion'ları, NVIDIA sürücüsü ve
  CS2 kurulumunu toplar. Çıktı olarak Masaüstü'ne Markdown + JSON yazar.

  Yönetici yetkisi gerekmez; bazı alanlar yetki yoksa "N/A" görünebilir.
  Bu script HİÇBİR ayarı değiştirmez; sadece okur.

.PARAMETER OutputDirectory
  Çıktı klasörü. Varsayılan: Masaüstü.

.PARAMETER JsonOnly
  Markdown üretme, sadece JSON yaz.

.PARAMETER Open
  Rapor üretildikten sonra Markdown dosyasını varsayılan editörde açar.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2SystemReport.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2SystemReport.ps1 -OutputDirectory "C:\Temp" -Open
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$JsonOnly,
    [switch]$Open
)

$ErrorActionPreference = 'Continue'
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Info { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }

function Format-Bytes {
    param([Nullable[double]]$Bytes)
    if ($null -eq $Bytes -or $Bytes -le 0) { return 'N/A' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt ($units.Count - 1)) {
        $v /= 1024
        $i++
    }
    return ('{0:N2} {1}' -f $v, $units[$i])
}

function Format-Date {
    param($Value)
    if ($null -eq $Value) { return 'N/A' }
    try { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss') } catch { return [string]$Value }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

function ConvertFrom-MonitorId {
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

    $steam = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if ($steam) {
        $candidates.Add((Join-Path $steam 'steamapps\common\Counter-Strike Global Offensive'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            try {
                $content = Get-Content $vdf -Raw -ErrorAction Stop
                foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                    $p = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $p 'steamapps\common\Counter-Strike Global Offensive'))
                }
            } catch { }
        }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'game\bin\win64\cs2.exe'))) {
            try { return (Resolve-Path $c).Path } catch { return $c }
        }
    }
    return $null
}

function Get-NvidiaSmiInfo {
    $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $fallback = @(
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'),
            (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe')
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if ($fallback) { $cmd = Get-Command $fallback -ErrorAction SilentlyContinue }
    }
    if (-not $cmd) { return $null }

    try {
        $raw = & $cmd.Source --query-gpu=name,driver_version,memory.total,power.limit,power.draw,clocks.current.graphics,clocks.current.memory,temperature.gpu '--format=csv,noheader,nounits' 2>$null
        if (-not $raw) { return $null }
        $line = @($raw)[0]
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        if ($parts.Count -lt 8) { return $null }
        return [ordered]@{
            Name            = $parts[0]
            DriverVersion   = $parts[1]
            MemoryTotal     = $parts[2]
            PowerLimit      = $parts[3]
            PowerDraw       = $parts[4]
            GraphicsClock   = $parts[5]
            MemoryClock     = $parts[6]
            Temperature     = $parts[7]
        }
    } catch {
        return $null
    }
}

function Get-DefaultAdapter {
    $physical = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    if ($physical.Count -eq 0) { return $null }

    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($route) {
        $match = $physical | Where-Object { $_.ifIndex -eq $route.ifIndex } | Select-Object -First 1
        if ($match) { return $match }
    }
    return ($physical | Select-Object -First 1)
}

# ---------------------------------------------------------------------------
# Çıktı klasörü
# ---------------------------------------------------------------------------
if (-not $OutputDirectory) {
    $OutputDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $OutputDirectory) { $OutputDirectory = $env:USERPROFILE }
}
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$baseName = "CS2-SystemReport-$script:Stamp"
$jsonPath = Join-Path $OutputDirectory "$baseName.json"
$mdPath   = Join-Path $OutputDirectory "$baseName.md"

Write-Info "Sistem bilgileri toplanıyor..."

# ---------------------------------------------------------------------------
# Donanım / OS
# ---------------------------------------------------------------------------
$computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$os       = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$cpu      = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$board    = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
$bios     = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$ram      = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
$gpus     = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$nvidia   = Get-NvidiaSmiInfo

$ramTotalBytes = 0
foreach ($m in $ram) {
    if ($m.Capacity) { $ramTotalBytes += [double]$m.Capacity }
}

$ramModules = @()
foreach ($m in $ram) {
    $ramModules += [ordered]@{
        Slot             = if ($m.DeviceLocator) { $m.DeviceLocator } else { $m.BankLabel }
        Manufacturer     = if ($m.Manufacturer) { $m.Manufacturer.Trim() } else { 'N/A' }
        PartNumber       = if ($m.PartNumber) { $m.PartNumber.Trim() } else { 'N/A' }
        Capacity         = Format-Bytes ([double]$m.Capacity)
        Speed            = if ($m.Speed) { "$($m.Speed) MHz" } else { 'N/A' }
        ConfiguredSpeed  = if ($m.ConfiguredClockSpeed) { "$($m.ConfiguredClockSpeed) MHz" } else { 'N/A' }
        FormFactor       = switch ($m.FormFactor) { 8 { 'DIMM' } 12 { 'SODIMM' } default { [string]$m.FormFactor } }
        MemoryType       = switch ($m.SMBIOSMemoryType) { 26 { 'DDR4' } 24 { 'DDR3' } 34 { 'DDR5' } default { [string]$m.SMBIOSMemoryType } }
    }
}

$isLaptop = $false
if ($computer -and $computer.PCSystemType -eq 2) { $isLaptop = $true }
if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { $isLaptop = $true }

$osCaption = if ($os) { $os.Caption } else { 'N/A' }
$osBuild   = if ($os) { $os.BuildNumber } else { 'N/A' }
$osVersion = if ($os) { $os.Version } else { 'N/A' }
$osArch    = if ($os) { $os.OSArchitecture } else { 'N/A' }
$lastBoot  = if ($os) { Format-Date $os.LastBootUpTime } else { 'N/A' }

# ---------------------------------------------------------------------------
# Monitör
# ---------------------------------------------------------------------------
$monitors = @()
try {
    $monitorIds = @(Get-CimInstance -Namespace 'root\wmi' -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    foreach ($m in $monitorIds) {
        $monitors += [ordered]@{
            Name         = ConvertFrom-MonitorId $m.UserFriendlyName
            Manufacturer = ConvertFrom-MonitorId $m.ManufacturerName
            Serial       = ConvertFrom-MonitorId $m.SerialNumberID
            YearOfManufacture = $m.YearOfManufacture
        }
    }
} catch { }

$display = $null
$primaryGpu = $gpus | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' } | Select-Object -First 1
if (-not $primaryGpu) { $primaryGpu = $gpus | Select-Object -First 1 }
if ($primaryGpu) {
    $display = [ordered]@{
        Resolution = if ($primaryGpu.CurrentHorizontalResolution -and $primaryGpu.CurrentVerticalResolution) {
            "$($primaryGpu.CurrentHorizontalResolution)x$($primaryGpu.CurrentVerticalResolution)"
        } else { 'N/A' }
        RefreshRate = if ($primaryGpu.CurrentRefreshRate) { "$($primaryGpu.CurrentRefreshRate) Hz" } else { 'N/A' }
    }
}

$vramText = 'N/A'
if ($nvidia -and $nvidia.MemoryTotal) {
    $vramText = "$($nvidia.MemoryTotal) MiB (nvidia-smi)"
} elseif ($primaryGpu -and $primaryGpu.AdapterRAM) {
    $vramText = Format-Bytes ([double]$primaryGpu.AdapterRAM)
}

# ---------------------------------------------------------------------------
# Depolama
# ---------------------------------------------------------------------------
$disks = @()
try {
    $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
    foreach ($d in $physicalDisks) {
        $disks += [ordered]@{
            Name         = $d.FriendlyName
            MediaType    = [string]$d.MediaType
            BusType      = [string]$d.BusType
            Size         = Format-Bytes ([double]$d.Size)
            Health       = [string]$d.HealthStatus
        }
    }
} catch {
    try {
        $wmiDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
        foreach ($d in $wmiDisks) {
            $disks += [ordered]@{
                Name      = $d.Model
                MediaType = 'N/A'
                BusType   = $d.InterfaceType
                Size      = Format-Bytes ([double]$d.Size)
                Health    = 'N/A'
            }
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# Ağ
# ---------------------------------------------------------------------------
$adapter = Get-DefaultAdapter
$network = [ordered]@{
    Name            = 'N/A'
    Description     = 'N/A'
    Status          = 'N/A'
    LinkSpeed       = 'N/A'
    MacAddress      = 'N/A'
    IPv4            = @()
    Gateway         = @()
    DnsServers      = @()
    Properties      = @()
}

if ($adapter) {
    $network.Name        = $adapter.Name
    $network.Description = $adapter.InterfaceDescription
    $network.Status      = [string]$adapter.Status
    $network.LinkSpeed   = [string]$adapter.LinkSpeed
    $network.MacAddress  = [string]$adapter.MacAddress

    try {
        $ipcfg = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction Stop
        $network.IPv4    = @($ipcfg.IPv4Address | ForEach-Object { $_.IPAddress })
        $network.Gateway = @($ipcfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
        try {
            $dns = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop)
            $network.DnsServers = @($dns | ForEach-Object { $_.ServerAddresses } | ForEach-Object { $_ })
        } catch { }
    } catch { }

    $nicKeywords = @(
        '*EEE', '*GreenEthernet', '*WakeOnMagicPacket', '*WakeOnPattern',
        '*PowerSaveMode', '*SelectiveSuspend', '*UltraLowPower', '*GigabitLite',
        '*RSS', '*InterruptModeration', '*FlowControl'
    )
    try {
        $props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction Stop)
        foreach ($key in $nicKeywords) {
            $p = $props | Where-Object { $_.RegistryKeyword -eq $key } | Select-Object -First 1
            if ($p) {
                $network.Properties += [ordered]@{
                    Keyword      = $p.RegistryKeyword
                    DisplayName  = $p.DisplayName
                    DisplayValue = $p.DisplayValue
                    RegistryValue = $p.RegistryValue
                }
            }
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# Windows ayarları
# ---------------------------------------------------------------------------
$schemeLine = (& powercfg.exe /getactivescheme 2>$null) -join ' '
$schemeGuid = ([regex]::Match($schemeLine, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})')).Value
$schemeName = ([regex]::Match($schemeLine, '\((.*)\)')).Groups[1].Value
if (-not $schemeName) { $schemeName = $schemeLine.Trim() }

$windows = [ordered]@{
    PowerPlan             = if ($schemeName) { $schemeName } else { 'N/A' }
    PowerPlanGuid         = if ($schemeGuid) { $schemeGuid } else { 'N/A' }
    HagsMode              = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    GameDvrEnabled        = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    AppCaptureEnabled     = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    AllowGameDvr          = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
    AutoGameMode          = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    Win32PrioritySeparation = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
    SystemResponsiveness  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
    NetworkThrottlingIndex = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
    PowerThrottlingOff    = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff'
    DisablePagingExecutive = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive'
    HiberbootEnabled      = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    HypervisorEnforcedCodeIntegrity = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    PendingReboot         = @()
}

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $windows.PendingReboot += 'CBS'
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $windows.PendingReboot += 'WindowsUpdate'
}
$pfro = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
if ($pfro) { $windows.PendingReboot += 'PendingFileRenameOperations' }

$defender = [ordered]@{
    ExclusionPath    = @()
    ExclusionProcess = @()
}
try {
    $mp = Get-MpPreference -ErrorAction Stop
    $defender.ExclusionPath = @($mp.ExclusionPath)
    $defender.ExclusionProcess = @($mp.ExclusionProcess)
} catch { }

# ---------------------------------------------------------------------------
# CS2
# ---------------------------------------------------------------------------
$cs2Path = Find-Cs2Path
$cs2 = [ordered]@{
    Path        = if ($cs2Path) { $cs2Path } else { 'Bulunamadı' }
    Exe         = 'N/A'
    FileVersion = 'N/A'
    Size        = 'N/A'
}
if ($cs2Path) {
    $exe = Join-Path $cs2Path 'game\bin\win64\cs2.exe'
    if (Test-Path $exe) {
        $cs2.Exe = $exe
        try {
            $info = Get-Item $exe -ErrorAction Stop
            $cs2.FileVersion = $info.VersionInfo.FileVersion
            $cs2.Size = Format-Bytes ([double]$info.Length)
        } catch { }
    }
}

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------
$report = [ordered]@{
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Computer = [ordered]@{
        Hostname   = $env:COMPUTERNAME
        Manufacturer = if ($computer) { $computer.Manufacturer } else { 'N/A' }
        Model      = if ($computer) { $computer.Model } else { 'N/A' }
        IsLaptop   = $isLaptop
    }
    OS = [ordered]@{
        Caption    = $osCaption
        Version    = $osVersion
        Build      = $osBuild
        Architecture = $osArch
        LastBoot   = $lastBoot
    }
    CPU = [ordered]@{
        Name        = if ($cpu) { $cpu.Name.Trim() } else { 'N/A' }
        Cores       = if ($cpu) { $cpu.NumberOfCores } else { 'N/A' }
        Threads     = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 'N/A' }
        MaxClockMHz = if ($cpu) { $cpu.MaxClockSpeed } else { 'N/A' }
        CurrentClockMHz = if ($cpu) { $cpu.CurrentClockSpeed } else { 'N/A' }
        L3CacheKB   = if ($cpu) { $cpu.L3CacheSize } else { 'N/A' }
    }
    Motherboard = [ordered]@{
        Manufacturer = if ($board) { $board.Manufacturer } else { 'N/A' }
        Product      = if ($board) { $board.Product } else { 'N/A' }
        BiosVersion  = if ($bios) { $bios.SMBIOSBIOSVersion } else { 'N/A' }
        BiosDate     = if ($bios) { Format-Date $bios.ReleaseDate } else { 'N/A' }
    }
    Memory = [ordered]@{
        Total     = Format-Bytes $ramTotalBytes
        ModuleCount = $ram.Count
        Modules   = $ramModules
    }
    GPU = [ordered]@{
        Adapters = @($gpus | ForEach-Object {
            [ordered]@{
                Name          = $_.Name
                DriverVersion = $_.DriverVersion
                AdapterRAM    = Format-Bytes ([double]$_.AdapterRAM)
                Resolution    = if ($_.CurrentHorizontalResolution -and $_.CurrentVerticalResolution) {
                    "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
                } else { 'N/A' }
                RefreshRate   = if ($_.CurrentRefreshRate) { "$($_.CurrentRefreshRate) Hz" } else { 'N/A' }
            }
        })
        NvidiaSmi = $nvidia
    }
    Monitors = $monitors
    Display  = $display
    Storage  = $disks
    Network  = $network
    Windows  = $windows
    Defender = $defender
    CS2      = $cs2
}

try {
    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Ok "JSON: $jsonPath"
} catch {
    Write-Warn "JSON yazılamadı: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------
if (-not $JsonOnly) {
    $md = New-Object System.Collections.Generic.List[string]
    function Add-Line { param([string]$Text) $md.Add($Text) }
    function Add-TableRow { param([string]$A, [string]$B) $md.Add(('| {0} | {1} |' -f $A, $B)) }
    function Clean { param($Value) if ($null -eq $Value -or "$Value".Trim() -eq '') { 'N/A' } else { ("$Value").Replace('|', '\|') } }

    Add-Line '# CS2 Sistem Raporu'
    Add-Line ''
    Add-Line ('> Oluşturma: **{0}**  ' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    Add-Line ('> Bilgisayar: **{0}**  ' -f $env:COMPUTERNAME)
    Add-Line '> Bu rapor `Get-Cs2SystemReport.ps1` tarafından otomatik oluşturuldu. Hiçbir ayar değiştirilmedi.'
    Add-Line ''

    Add-Line '## 1. Özet'
    Add-Line ''
    Add-Line '| Bileşen | Değer |'
    Add-Line '|---|---|'
    Add-TableRow 'İşletim sistemi' (Clean "$osCaption ($osArch)")
    Add-TableRow 'Build' (Clean $osBuild)
    Add-TableRow 'CPU' (Clean $(if ($cpu) { $cpu.Name.Trim() } else { 'N/A' }))
    Add-TableRow 'Çekirdek / Thread' (Clean $(if ($cpu) { "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T" } else { 'N/A' }))
    Add-TableRow 'RAM' (Clean "$(Format-Bytes $ramTotalBytes) / $($ram.Count) modül")
    Add-TableRow 'Anakart' (Clean $(if ($board) { "$($board.Manufacturer) $($board.Product)" } else { 'N/A' }))
    Add-TableRow 'BIOS' (Clean $(if ($bios) { "$($bios.SMBIOSBIOSVersion) ($(Format-Date $bios.ReleaseDate))" } else { 'N/A' }))
    Add-TableRow 'GPU' (Clean $(if ($primaryGpu) { $primaryGpu.Name } else { 'N/A' }))
    Add-TableRow 'VRAM' (Clean $vramText)
    Add-TableRow 'NVIDIA sürücü' (Clean $(if ($nvidia) { $nvidia.DriverVersion } elseif ($primaryGpu) { $primaryGpu.DriverVersion } else { 'N/A' }))
    Add-TableRow 'Çözünürlük / Hz' (Clean $(if ($display) { "$($display.Resolution) / $($display.RefreshRate)" } else { 'N/A' }))
    Add-TableRow 'Güç planı' (Clean $windows.PowerPlan)
    Add-TableRow 'CS2 yolu' (Clean $cs2.Path)
    Add-Line ''

    Add-Line '## 2. CPU'
    Add-Line ''
    Add-Line '| Alan | Değer |'
    Add-Line '|---|---|'
    Add-TableRow 'Model' (Clean $(if ($cpu) { $cpu.Name.Trim() } else { 'N/A' }))
    Add-TableRow 'Çekirdek' (Clean $(if ($cpu) { $cpu.NumberOfCores } else { 'N/A' }))
    Add-TableRow 'Thread' (Clean $(if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 'N/A' }))
    Add-TableRow 'Max clock' (Clean $(if ($cpu) { "$($cpu.MaxClockSpeed) MHz" } else { 'N/A' }))
    Add-TableRow 'Current clock' (Clean $(if ($cpu) { "$($cpu.CurrentClockSpeed) MHz" } else { 'N/A' }))
    Add-TableRow 'L3 cache' (Clean $(if ($cpu) { "$($cpu.L3CacheSize) KB" } else { 'N/A' }))
    Add-Line ''

    Add-Line '## 3. Bellek'
    Add-Line ''
    Add-Line ('Toplam: **{0}**, modül sayısı: **{1}**' -f (Format-Bytes $ramTotalBytes), $ram.Count)
    Add-Line ''
    Add-Line '| Slot | Üretici | Part number | Kapasite | Hız | Configured | Tip |'
    Add-Line '|---|---|---|---|---|---|---|'
    foreach ($m in $ramModules) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f (Clean $m.Slot), (Clean $m.Manufacturer), (Clean $m.PartNumber), (Clean $m.Capacity), (Clean $m.Speed), (Clean $m.ConfiguredSpeed), (Clean $m.MemoryType)))
    }
    Add-Line ''

    Add-Line '## 4. GPU / Monitör'
    Add-Line ''
    Add-Line '| GPU | Sürücü | VRAM (AdapterRAM) | Çözünürlük | Hz |'
    Add-Line '|---|---|---|---|---|'
    foreach ($g in @($gpus)) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f (Clean $g.Name), (Clean $g.DriverVersion), (Clean (Format-Bytes ([double]$g.AdapterRAM))), (Clean $(if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)" } else { 'N/A' })), (Clean $(if ($g.CurrentRefreshRate) { "$($g.CurrentRefreshRate) Hz" } else { 'N/A' }))))
    }
    Add-Line ''
    if ($nvidia) {
        Add-Line '**nvidia-smi**'
        Add-Line ''
        Add-Line '| Alan | Değer |'
        Add-Line '|---|---|'
        Add-TableRow 'GPU' (Clean $nvidia.Name)
        Add-TableRow 'Sürücü' (Clean $nvidia.DriverVersion)
        Add-TableRow 'VRAM' (Clean "$($nvidia.MemoryTotal) MiB")
        Add-TableRow 'Power limit' (Clean "$($nvidia.PowerLimit) W")
        Add-TableRow 'Power draw' (Clean "$($nvidia.PowerDraw) W")
        Add-TableRow 'Graphics clock' (Clean "$($nvidia.GraphicsClock) MHz")
        Add-TableRow 'Memory clock' (Clean "$($nvidia.MemoryClock) MHz")
        Add-TableRow 'Sıcaklık' (Clean "$($nvidia.Temperature) °C")
        Add-Line ''
    }
    if ($monitors.Count -gt 0) {
        Add-Line '**Monitörler**'
        Add-Line ''
        Add-Line '| Ad | Üretici | Seri | Yıl |'
        Add-Line '|---|---|---|---|'
        foreach ($m in $monitors) {
            $md.Add(('| {0} | {1} | {2} | {3} |' -f (Clean $m.Name), (Clean $m.Manufacturer), (Clean $m.Serial), (Clean $m.YearOfManufacture)))
        }
        Add-Line ''
    }

    Add-Line '## 5. Depolama'
    Add-Line ''
    Add-Line '| Disk | Tip | Bus | Boyut | Sağlık |'
    Add-Line '|---|---|---|---|---|'
    foreach ($d in $disks) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f (Clean $d.Name), (Clean $d.MediaType), (Clean $d.BusType), (Clean $d.Size), (Clean $d.Health)))
    }
    Add-Line ''

    Add-Line '## 6. Ağ'
    Add-Line ''
    Add-Line '| Alan | Değer |'
    Add-Line '|---|---|'
    Add-TableRow 'Adapter' (Clean $network.Name)
    Add-TableRow 'Açıklama' (Clean $network.Description)
    Add-TableRow 'Durum' (Clean $network.Status)
    Add-TableRow 'Link speed' (Clean $network.LinkSpeed)
    Add-TableRow 'MAC' (Clean $network.MacAddress)
    Add-TableRow 'IPv4' (Clean ($network.IPv4 -join ', '))
    Add-TableRow 'Gateway' (Clean ($network.Gateway -join ', '))
    Add-TableRow 'DNS' (Clean ($network.DnsServers -join ', '))
    Add-Line ''
    if ($network.Properties.Count -gt 0) {
        Add-Line '**NIC advanced properties**'
        Add-Line ''
        Add-Line '| Keyword | Görünen ad | Değer | Registry |'
        Add-Line '|---|---|---|---|'
        foreach ($p in $network.Properties) {
            $md.Add(('| {0} | {1} | {2} | {3} |' -f (Clean $p.Keyword), (Clean $p.DisplayName), (Clean $p.DisplayValue), (Clean $p.RegistryValue)))
        }
        Add-Line ''
    }

    Add-Line '## 7. Windows ayarları'
    Add-Line ''
    Add-Line '| Ayar | Değer |'
    Add-Line '|---|---|'
    Add-TableRow 'Güç planı' (Clean $windows.PowerPlan)
    Add-TableRow 'HAGS (`HwSchMode`)' (Clean $windows.HagsMode)
    Add-TableRow 'GameDVR' (Clean $windows.GameDvrEnabled)
    Add-TableRow 'AppCapture' (Clean $windows.AppCaptureEnabled)
    Add-TableRow 'Auto Game Mode' (Clean $windows.AutoGameMode)
    Add-TableRow 'Win32PrioritySeparation' (Clean $windows.Win32PrioritySeparation)
    Add-TableRow 'SystemResponsiveness' (Clean $windows.SystemResponsiveness)
    Add-TableRow 'NetworkThrottlingIndex' (Clean $windows.NetworkThrottlingIndex)
    Add-TableRow 'PowerThrottlingOff' (Clean $windows.PowerThrottlingOff)
    Add-TableRow 'DisablePagingExecutive' (Clean $windows.DisablePagingExecutive)
    Add-TableRow 'Fast Startup (`HiberbootEnabled`)' (Clean $windows.HiberbootEnabled)
    Add-TableRow 'HVCI' (Clean $windows.HypervisorEnforcedCodeIntegrity)
    Add-TableRow 'Pending reboot' (Clean ($windows.PendingReboot -join ', '))
    Add-Line ''
    Add-Line '> HAGS: 2=açık, 1=kapalı. GameDVR/AppCapture: 0=kapalı. Auto Game Mode: 1=açık. `Win32PrioritySeparation=38` default-equivalent (short/variable/3:1). `SystemResponsiveness` default 20. `NetworkThrottlingIndex` default 10; kapatma. `PowerThrottlingOff=1` açık. `DisablePagingExecutive=1` açık. Fast Startup: 0=kapalı. HVCI: 1=açık.'
    Add-Line ''
    Add-Line '**Defender exclusions**'
    Add-Line ''
    Add-Line ('- Paths: {0}' -f (Clean ($defender.ExclusionPath -join '; ')))
    Add-Line ('- Processes: {0}' -f (Clean ($defender.ExclusionProcess -join '; ')))
    Add-Line ''

    Add-Line '## 8. CS2'
    Add-Line ''
    Add-Line '| Alan | Değer |'
    Add-Line '|---|---|'
    Add-TableRow 'Kurulum yolu' (Clean $cs2.Path)
    Add-TableRow 'cs2.exe' (Clean $cs2.Exe)
    Add-TableRow 'Dosya sürümü' (Clean $cs2.FileVersion)
    Add-TableRow 'Boyut' (Clean $cs2.Size)
    Add-Line ''

    Add-Line '## 9. Notlar / eksikler'
    Add-Line ''
    if (-not $nvidia) {
        Add-Line '- `nvidia-smi` bulunamadı; NVIDIA sürücü/VRAM bilgisi WMI''den alındı.'
    }
    if ($display -and $display.RefreshRate -eq 'N/A') {
        Add-Line '- Monitör yenileme hızı WMI''den okunamadı; NVIDIA Control Panel''den doğrula.'
    }
    if ($ramModules.Count -gt 0) {
        $speeds = @($ramModules | ForEach-Object { $_.ConfiguredSpeed } | Select-Object -Unique)
        Add-Line ('- RAM configured hızları: {0}. XMP/EXPO açık mı kontrol et.' -f (Clean ($speeds -join ', ')))
    }
    if ($isLaptop) {
        Add-Line '- Cihaz dizüstü olarak algılandı; güç/ısı ayarları masaüstünden farklı değerlendirilmeli.'
    }
    if ($windows.PendingReboot.Count -gt 0) {
        Add-Line '- Bekleyen yeniden başlatma var; ölçüm öncesi reboot önerilir.'
    }
    Add-Line '- Windows 10 22H2 destek dışıdır; bu rapor performans içindir, güvenlik yaması değildir.'
    Add-Line ''
    Add-Line '---'
    Add-Line ''
    Add-Line ('JSON: `{0}`' -f $jsonPath)

    try {
        $md -join "`r`n" | Set-Content -Path $mdPath -Encoding UTF8
        Write-Ok "Markdown: $mdPath"
    } catch {
        Write-Warn "Markdown yazılamadı: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Konsol özeti
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== ÖZET ===' -ForegroundColor Cyan
Write-Host ("OS      : {0} (build {1})" -f $osCaption, $osBuild)
if ($cpu) { Write-Host ("CPU     : {0} / {1}C-{2}T" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors) }
Write-Host ("RAM     : {0} / {1} modül" -f (Format-Bytes $ramTotalBytes), $ram.Count)
if ($primaryGpu) { Write-Host ("GPU     : {0} / driver {1}" -f $primaryGpu.Name, $primaryGpu.DriverVersion) }
if ($display) { Write-Host ("Display : {0} / {1}" -f $display.Resolution, $display.RefreshRate) }
Write-Host ("Power   : {0}" -f $windows.PowerPlan)
Write-Host ("CS2     : {0}" -f $cs2.Path)
Write-Host ''

if ($Open -and -not $JsonOnly -and (Test-Path $mdPath)) {
    try { Invoke-Item $mdPath } catch { Write-Warn 'Rapor açılamadı.' }
}
