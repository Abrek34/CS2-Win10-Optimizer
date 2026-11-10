#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  WinUtil (Chris Titus Tech) incelemesinden seçilen, CS2 odaklı düşük riskli Windows tercihleri.

.DESCRIPTION
  Bu script WinUtil'in tüm debloat/tweak listesini uygulamaz. Yalnızca CS2 performansı,
  ağ, depolama ve arka plan yükü ile ilgili düşük riskli maddeleri içerir:

    - Activity History disable
    - Location Tracking disable
    - ConsumerFeatures disable
    - Delivery Optimization disable
    - Device companion apps disable
    - Razer / Logitech auto-install disable (registry düzeyinde)
    - Teredo disable
    - IPv4 preference
    - Reserved Storage disable
    - File Explorer automatic folder discovery disable
    - End task with right click enable

  Varsayılan olarak DRY RUN yapar; hiçbir değişiklik uygulamaz.
  -Apply verilmeden değişiklik yapılmaz.
  -Revert ile bu scriptin yaptığı registry/netsh/DISM değişiklikleri geri alınır.

  UWP uygulama kaldırma, servis katliamı, Edge/OneDrive kaldırma, BitLocker,
  WPBT, DNS değiştirme, O&O ShutUp gibi riskli/kozmetik maddeler bilinçli olarak
  kapsam dışıdır.

.PARAMETER Apply
  Değişiklikleri uygula. Verilmezse dry run.

.PARAMETER Revert
  Bu scriptin oluşturduğu en son yedeği geri yükle.

.PARAMETER DisableActivityHistory
  Activity History yayını/yüklemesini kapatır.

.PARAMETER DisableLocationTracking
  Konum izlemeyi kapatır.

.PARAMETER DisableConsumerFeatures
  Microsoft Store önerilen uygulama yüklemelerini azaltır.

.PARAMETER DisableDeliveryOptimization
  Delivery Optimization upload/download davranışını kapatır.

.PARAMETER DisableDeviceCompanionApps
  Cihaz takıldığında companion app kurulumunu engeller.

.PARAMETER DisableRazerAutoInstall
  Razer yazılımının otomatik kurulumunu registry düzeyinde engeller.

.PARAMETER DisableLogitechAutoInstall
  Logitech Download Assistant otomatik kurulumunu registry düzeyinde engeller.

.PARAMETER DisableTeredo
  Teredo tunneling'i kapatır. Bazı oyunlarda sorun çıkarabilir.

.PARAMETER PreferIpv4
  IPv4'ü IPv6'ya tercih eder. IPv6 yapılandırılmamış ağlarda faydalı olabilir.

.PARAMETER DisableReservedStorage
  Reserved Storage'ı kapatır. Küçük disklerde yer kazandırır; büyük güncellemeler
  öncesi yeniden açılması gerekir.

.PARAMETER DisableExplorerFolderDiscovery
  File Explorer'ın klasör türünü tahmin etmesini kapatır. Klasör görünüm geçmişini
  sıfırlar.

.PARAMETER EnableEndTaskRightClick
  Taskbar sağ tık menüsüne "Görevi sonlandır" seçeneği ekler.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-WinUtil-Preferences.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-WinUtil-Preferences.ps1 -Apply -DisableActivityHistory -DisableLocationTracking -DisableDeliveryOptimization -PreferIpv4

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-WinUtil-Preferences.ps1 -Revert
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$DisableActivityHistory,
    [switch]$DisableLocationTracking,
    [switch]$DisableConsumerFeatures,
    [switch]$DisableDeliveryOptimization,
    [switch]$DisableDeviceCompanionApps,
    [switch]$DisableRazerAutoInstall,
    [switch]$DisableLogitechAutoInstall,
    [switch]$DisableTeredo,
    [switch]$PreferIpv4,
    [switch]$DisableReservedStorage,
    [switch]$DisableExplorerFolderDiscovery,
    [switch]$EnableEndTaskRightClick
)

$ErrorActionPreference = 'Continue'
$script:Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop   = [Environment]::GetFolderPath('Desktop')
$script:LogPath   = Join-Path $script:Desktop "CS2-WinUtil-Preferences-$script:Stamp.log"
$script:BackupDir = Join-Path $script:Desktop "CS2-WinUtil-Preferences-Backup-$script:Stamp"

Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop

Start-Transcript -Path $script:LogPath -Force | Out-Null

$selected = @(
    $DisableActivityHistory,
    $DisableLocationTracking,
    $DisableConsumerFeatures,
    $DisableDeliveryOptimization,
    $DisableDeviceCompanionApps,
    $DisableRazerAutoInstall,
    $DisableLogitechAutoInstall,
    $DisableTeredo,
    $PreferIpv4,
    $DisableReservedStorage,
    $DisableExplorerFolderDiscovery,
    $EnableEndTaskRightClick
)

$hasSelection = ($selected -contains $true)

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: latest WinUtil preferences backup'

    $backup = Get-LatestBackup -Pattern 'CS2-WinUtil-Preferences-Backup-*'
    if (-not $backup) {
        Write-Err 'No CS2-WinUtil-Preferences backup folder found on Desktop.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Info "Using backup: $($backup.FullName)"
    $script:BackupDir = $backup.FullName

    Get-ChildItem -Path $backup.FullName -Filter '*.reg' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Info "Importing $($_.Name)"
        & reg.exe import $_.FullName 2>$null | Out-Null
    }

    $teredoFlag = Get-Flag -Name 'Teredo' -BackupDir $script:BackupDir
    if ($teredoFlag -and $teredoFlag.Value) {
        & netsh.exe interface teredo set state default 2>$null | Out-Null
        Write-Ok 'Teredo restored to default.'
    }

    $reservedFlag = Get-Flag -Name 'ReservedStorage' -BackupDir $script:BackupDir
    if ($reservedFlag -and $reservedFlag.Value) {
        & DISM.exe /Online /Set-ReservedStorageState /State:Enabled 2>$null | Out-Null
        Write-Ok 'Reserved Storage re-enabled.'
    }

    $explorerFlag = Get-Flag -Name 'ExplorerFolderDiscovery' -BackupDir $script:BackupDir
    if ($explorerFlag -and $explorerFlag.Value) {
        Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags' -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU' -Recurse -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Name 'FolderType' -ErrorAction SilentlyContinue
        Write-Ok 'File Explorer folder discovery restored (bags removed).'
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
    Write-Info 'Recommended first run: -Apply -DisableActivityHistory -DisableLocationTracking -DisableDeliveryOptimization -PreferIpv4'
    Write-Info "Log: $script:LogPath"

    if (-not $hasSelection) {
        Write-Info 'No preferences selected. Use one or more switches, or -Apply with a selected set.'
        Stop-Transcript | Out-Null
        exit 0
    }

    if ($DisableActivityHistory) { Write-Info 'Would disable Activity History.' }
    if ($DisableLocationTracking) { Write-Info 'Would disable Location Tracking.' }
    if ($DisableConsumerFeatures) { Write-Info 'Would disable ConsumerFeatures.' }
    if ($DisableDeliveryOptimization) { Write-Info 'Would disable Delivery Optimization.' }
    if ($DisableDeviceCompanionApps) { Write-Info 'Would disable device companion apps.' }
    if ($DisableRazerAutoInstall) { Write-Info 'Would disable Razer auto-install (registry only).' }
    if ($DisableLogitechAutoInstall) { Write-Info 'Would disable Logitech auto-install (registry only).' }
    if ($DisableTeredo) { Write-Info 'Would disable Teredo.' }
    if ($PreferIpv4) { Write-Info 'Would set IPv4 preference (DisabledComponents=32).' }
    if ($DisableReservedStorage) { Write-Info 'Would disable Reserved Storage (DISM).' }
    if ($DisableExplorerFolderDiscovery) { Write-Info 'Would disable File Explorer automatic folder discovery.' }
    if ($EnableEndTaskRightClick) { Write-Info 'Would enable End Task with right click.' }

    Stop-Transcript | Out-Null
    exit 0
}

if (-not $hasSelection) {
    Write-Err 'No preferences selected. Use at least one switch with -Apply.'
    Stop-Transcript | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null

$keys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\System',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location',
    'HKLM\SYSTEM\Maps',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Device Metadata',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer',
    'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters',
    'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags',
    'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU',
    'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
)
foreach ($k in $keys) { Backup-RegKey -Key $k -BackupDir $script:BackupDir | Out-Null }

# Activity History
if ($DisableActivityHistory) {
    Write-Step 'Activity History'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 1
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
    Write-Ok 'Activity History disabled.'
}

# Location Tracking
if ($DisableLocationTracking) {
    Write-Step 'Location Tracking'
    Set-RegString 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' 0
    Set-RegDword 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' 0
    Write-Ok 'Location Tracking disabled.'
}

# ConsumerFeatures
if ($DisableConsumerFeatures) {
    Write-Step 'ConsumerFeatures'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Write-Ok 'ConsumerFeatures disabled.'
}

# Delivery Optimization
if ($DisableDeliveryOptimization) {
    Write-Step 'Delivery Optimization'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Write-Ok 'Delivery Optimization disabled.'
}

# Device companion apps
if ($DisableDeviceCompanionApps) {
    Write-Step 'Device companion apps'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Write-Ok 'Device companion apps disabled.'
}

# Razer auto-install (registry only)
if ($DisableRazerAutoInstall) {
    Write-Step 'Razer auto-install (registry)'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' 'DisableCoInstallers' 1
    Write-Ok 'Razer auto-install registry settings applied.'
    Write-Warn 'Full blocking also requires removing/locking the Razer installer folder; not done automatically.'
}

# Logitech auto-install (registry only)
if ($DisableLogitechAutoInstall) {
    Write-Step 'Logitech auto-install (registry)'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' 'DisableCoInstallers' 1
    Write-Ok 'Logitech auto-install registry settings applied.'
    Write-Warn 'Full blocking also requires removing/locking the Logitech Download Assistant folder; not done automatically.'
}

# Teredo + IPv4 preference
$disabledComponents = 0
if ($DisableTeredo) { $disabledComponents = $disabledComponents -bor 1 }
if ($PreferIpv4) { $disabledComponents = $disabledComponents -bor 32 }

if ($DisableTeredo -or $PreferIpv4) {
    Write-Step 'Network: Teredo / IPv4 preference'
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' $disabledComponents
    if ($DisableTeredo) {
        & netsh.exe interface teredo set state disabled 2>$null | Out-Null
        Save-Flag -Name 'Teredo' -Value $true -BackupDir $script:BackupDir
        Write-Ok 'Teredo disabled.'
    }
    if ($PreferIpv4) {
        Write-Ok 'IPv4 preference set (DisabledComponents includes 32).'
    }
}

# Reserved Storage
if ($DisableReservedStorage) {
    Write-Step 'Reserved Storage'
    & DISM.exe /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null
    Save-Flag -Name 'ReservedStorage' -Value $true -BackupDir $script:BackupDir
    Write-Ok 'Reserved Storage disabled. Re-enable before major Windows updates.'
}

# File Explorer automatic folder discovery
if ($DisableExplorerFolderDiscovery) {
    Write-Step 'File Explorer automatic folder discovery'
    Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU' -Recurse -Force -ErrorAction SilentlyContinue
    $allFolders = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'
    if (-not (Test-Path $allFolders)) { New-Item -Path $allFolders -Force | Out-Null }
    Set-RegString $allFolders 'FolderType' 'NotSpecified'
    Save-Flag -Name 'ExplorerFolderDiscovery' -Value $true -BackupDir $script:BackupDir
    Write-Ok 'File Explorer automatic folder discovery disabled. Sign out/reboot recommended.'
}

# End task with right click
if ($EnableEndTaskRightClick) {
    Write-Step 'End task with right click'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
    Write-Ok 'End Task with right click enabled.'
}

$applied = @()
if ($DisableActivityHistory) { $applied += 'DisableActivityHistory' }
if ($DisableLocationTracking) { $applied += 'DisableLocationTracking' }
if ($DisableConsumerFeatures) { $applied += 'DisableConsumerFeatures' }
if ($DisableDeliveryOptimization) { $applied += 'DisableDeliveryOptimization' }
if ($DisableDeviceCompanionApps) { $applied += 'DisableDeviceCompanionApps' }
if ($DisableRazerAutoInstall) { $applied += 'DisableRazerAutoInstall' }
if ($DisableLogitechAutoInstall) { $applied += 'DisableLogitechAutoInstall' }
if ($DisableTeredo) { $applied += 'DisableTeredo' }
if ($PreferIpv4) { $applied += 'PreferIpv4' }
if ($DisableReservedStorage) { $applied += 'DisableReservedStorage' }
if ($DisableExplorerFolderDiscovery) { $applied += 'DisableExplorerFolderDiscovery' }
if ($EnableEndTaskRightClick) { $applied += 'EnableEndTaskRightClick' }

$manifest = [ordered]@{
    Stamp   = $script:Stamp
    Applied = $applied
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $script:BackupDir 'applied-preferences.json') -Encoding UTF8

Write-Step 'Done'
Write-Ok "Backup: $script:BackupDir"
Write-Ok "Log: $script:LogPath"
Write-Warn 'Reboot recommended after registry/network/storage changes.'
Write-Info 'Revert: run the same script with -Revert.'
Write-Info 'This script does not remove UWP apps, disable services, change BIOS, NVIDIA Control Panel, Defender, or in-game settings.'

Stop-Transcript | Out-Null