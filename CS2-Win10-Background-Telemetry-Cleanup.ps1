#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  CS2-Win10-Optimizer için Windows 10 arka plan, telemetri ve gereksiz UWP uygulama temizliği.

.DESCRIPTION
  Bu script Win11Debloat benzeri geniş bir temizlik yapmaz. CS2 odaklı, daha dar ve
  geri alınabilir bir temizlik yapar:

    - DiagTrack / dmwappushservice gibi telemetri servislerini kapatır
    - CEIP ve uyumluluk telemetrisi zamanlanmış görevlerini devre dışı bırakır
    - Arka plan uygulama erişimini kapatır
    - İsteğe bağlı: güvenli/gereksiz UWP uygulamalarını kaldırır
    - İsteğe bağlı: Xbox uygulamalarını kaldırır
    - İsteğe bağlı: Windows Error Reporting'i kapatır

  Varsayılan olarak DRY RUN yapar; hiçbir değişiklik uygulamaz.
  -Apply verilmeden değişiklik yapılmaz.
  -Revert ile servis/görev/registry değişiklikleri geri alınır.

  UWP uygulama kaldırma işlemi tamamen geri alınamaz: kaldırılan uygulamalar
  Microsoft Store'dan yeniden kurulmalıdır. Bu nedenle -RemoveNonEssentialApps /
  -RemoveXboxApps yalnızca açıkça verildiğinde çalışır.

.PARAMETER Apply
  Değişiklikleri uygula. Verilmezse dry run.

.PARAMETER Revert
  Bu scriptin oluşturduğu en son yedeği geri yükle.

.PARAMETER DisableTelemetry
  DiagTrack, dmwappushservice, ilgili zamanlanmış görevler ve telemetri registry
  ayarlarını kapatır. -Apply ile birlikte kullanılmalıdır.

.PARAMETER DisableBackgroundApps
  Global background app access'i kapatır.

.PARAMETER RemoveNonEssentialApps
  CS2 için genellikle gereksiz UWP uygulamalarını kaldırır.

.PARAMETER RemoveXboxApps
  Xbox / Game Bar ile ilgili UWP uygulamalarını kaldırır. Game Bar kullanıyorsanız
  vermeyin.

.PARAMETER DisableErrorReporting
  Windows Error Reporting servisini kapatır.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Apply -DisableTelemetry -DisableBackgroundApps

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Apply -DisableTelemetry -RemoveNonEssentialApps

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Revert
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$DisableTelemetry,
    [switch]$DisableBackgroundApps,
    [switch]$RemoveNonEssentialApps,
    [switch]$RemoveXboxApps,
    [switch]$DisableErrorReporting
)

$ErrorActionPreference = 'Continue'
$script:Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop   = [Environment]::GetFolderPath('Desktop')
$script:LogPath   = Join-Path $script:Desktop "CS2-BackgroundTelemetryCleanup-$script:Stamp.log"
$script:BackupDir = Join-Path $script:Desktop "CS2-BackgroundTelemetryCleanup-Backup-$script:Stamp"

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

Start-Transcript -Path $script:LogPath -Force | Out-Null

function Disable-ServiceSafe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Info "$Name not found; skipped."
        return
    }
    Save-ServiceState -Name $Name -BackupDir $script:BackupDir | Out-Null
    try {
        Stop-Service -Name $Name -Force -ErrorAction Stop
    } catch {
        Write-Warn "$Name could not be stopped: $($_.Exception.Message)"
    }
    try {
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-Ok "$Name disabled."
    } catch {
        Write-Warn "$Name could not be disabled: $($_.Exception.Message)"
    }
}

function Disable-TaskSafe {
    param([string]$TaskPath, [string]$TaskName)
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Info "Task not found: $TaskPath$TaskName"
        return
    }
    Save-TaskState -TaskPath $TaskPath -TaskName $TaskName -BackupDir $script:BackupDir | Out-Null
    try {
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        Write-Ok "Disabled task: $TaskPath$TaskName"
    } catch {
        Write-Warn "Could not disable task $TaskPath$TaskName : $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Revert
# ---------------------------------------------------------------------------
if ($Revert) {
    Write-Step 'Revert: latest cleanup backup'

    $backup = Get-LatestBackup -Pattern 'CS2-BackgroundTelemetryCleanup-Backup-*'
    if (-not $backup) {
        Write-Err 'No CS2-BackgroundTelemetryCleanup backup folder found on Desktop.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Info "Using backup: $($backup.FullName)"
    $script:BackupDir = $backup.FullName

    # Registry keys
    Get-ChildItem -Path $backup.FullName -Filter '*.reg' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Info "Importing $($_.Name)"
        & reg.exe import $_.FullName 2>$null | Out-Null
    }

    # Services
    Get-ChildItem -Path $backup.FullName -Filter 'service-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($state.Name) {
                Restore-ServiceState -Name $state.Name -BackupDir $backup.FullName
                Write-Ok "Restored service: $($state.Name)"
            }
        } catch {
            Write-Warn "Could not restore service from $($_.Name): $($_.Exception.Message)"
        }
    }

    # Scheduled tasks
    Get-ChildItem -Path $backup.FullName -Filter 'task-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($state.TaskPath -and $state.TaskName) {
                Restore-TaskState -TaskPath $state.TaskPath -TaskName $state.TaskName -BackupDir $backup.FullName
            }
        } catch {
            Write-Warn "Could not restore task from $($_.Name): $($_.Exception.Message)"
        }
    }

    # Removed apps cannot be automatically reinstalled.
    $removedAppsFile = Join-Path $backup.FullName 'removed-apps.json'
    if (Test-Path $removedAppsFile) {
        Write-Warn 'Removed UWP apps cannot be automatically reinstalled.'
        Write-Warn "Removed app list: $removedAppsFile"
        Write-Warn 'Reinstall them manually from Microsoft Store if needed.'
    }

    Write-Ok 'Revert completed. Reboot recommended.'
    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------------------
# Dry run / validation
# ---------------------------------------------------------------------------
$doTelemetry = $DisableTelemetry -or $Apply
$doBackground = $DisableBackgroundApps -or $Apply
$doErrorReporting = $DisableErrorReporting -or $Apply
$doRemoveApps = $RemoveNonEssentialApps -or $RemoveXboxApps

if (-not $Apply) {
    Write-Step 'DRY RUN'
    Write-Info 'No changes were made. Re-run with -Apply to apply.'
    Write-Info 'Recommended first run: -Apply -DisableTelemetry -DisableBackgroundApps'
    Write-Info 'Optional app removal: -Apply -DisableTelemetry -RemoveNonEssentialApps'
    Write-Info 'Optional Xbox app removal: -Apply -DisableTelemetry -RemoveXboxApps'
    Write-Info 'Optional error reporting: -Apply -DisableErrorReporting'
    Write-Info "Log: $script:LogPath"

    if ($doTelemetry) {
        Write-Step 'Telemetry changes that would be applied'
        Write-Info 'Services: DiagTrack, dmwappushservice'
        Write-Info 'Tasks: Application Experience, CEIP, DiskDiagnosticDataCollector'
        Write-Info 'Registry: AllowTelemetry = 0'
    }

    if ($doBackground) {
        Write-Step 'Background app changes that would be applied'
        Write-Info 'GlobalUserDisabled = 1'
    }

    if ($doErrorReporting) {
        Write-Step 'Error reporting changes that would be applied'
        Write-Info 'Service: WerSvc'
    }

    if ($doRemoveApps) {
        Write-Step 'UWP apps that would be removed'
        $appsToRemove = @()
        if ($RemoveNonEssentialApps) {
            $appsToRemove += @(
                'Microsoft.3DBuilder',
                'Microsoft.BingFinance',
                'Microsoft.BingNews',
                'Microsoft.BingSports',
                'Microsoft.BingWeather',
                'Microsoft.GetHelp',
                'Microsoft.Getstarted',
                'Microsoft.Microsoft3DViewer',
                'Microsoft.MicrosoftOfficeHub',
                'Microsoft.MixedReality.Portal',
                'Microsoft.People',
                'Microsoft.SkypeApp',
                'Microsoft.Wallet',
                'Microsoft.WindowsMaps',
                'Microsoft.ZuneMusic',
                'Microsoft.ZuneVideo',
                'Microsoft.MicrosoftSolitaireCollection',
                'Microsoft.WindowsFeedbackHub',
                'Microsoft.WindowsCommunicationsApps',
                'Microsoft.OneConnect',
                'Microsoft.WindowsAlarms',
                'Microsoft.WindowsSoundRecorder',
                'Microsoft.YourPhone'
            )
        }
        if ($RemoveXboxApps) {
            $appsToRemove += @(
                'Microsoft.XboxApp',
                'Microsoft.XboxGamingOverlay',
                'Microsoft.XboxIdentityProvider',
                'Microsoft.XboxSpeechToTextOverlay',
                'Microsoft.Xbox.TCUI',
                'Microsoft.GamingApp'
            )
        }
        $appsToRemove = $appsToRemove | Select-Object -Unique
        $installed = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $appsToRemove -contains $_.Name })
        if ($installed.Count -eq 0) {
            Write-Info 'No matching installed UWP apps found.'
        } else {
            foreach ($a in $installed) { Write-Info $a.Name }
        }
        Write-Warn 'UWP app removal is not fully reversible. Reinstall from Microsoft Store if needed.'
    }

    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null

# Registry backups
$keys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
)
foreach ($k in $keys) { Backup-RegKey -Key $k -BackupDir $script:BackupDir | Out-Null }

# ---------------------------------------------------------------------------
# Telemetry
# ---------------------------------------------------------------------------
if ($DisableTelemetry) {
    Write-Step 'Telemetry: services'

    $telemetryServices = @('DiagTrack', 'dmwappushservice')
    foreach ($svcName in $telemetryServices) {
        Disable-ServiceSafe -Name $svcName
    }

    Write-Step 'Telemetry: scheduled tasks'
    $telemetryTasks = @(
        @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' },
        @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' },
        @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
        @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
    )
    foreach ($t in $telemetryTasks) {
        Disable-TaskSafe -TaskPath $t.Path -TaskName $t.Name
    }

    Write-Step 'Telemetry: registry'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Write-Ok 'AllowTelemetry set to 0.'
} else {
    Write-Info 'Telemetry changes skipped (use -DisableTelemetry).'
}

# ---------------------------------------------------------------------------
# Error reporting
# ---------------------------------------------------------------------------
if ($DisableErrorReporting) {
    Write-Step 'Error reporting'
    Disable-ServiceSafe -Name 'WerSvc'
}

# ---------------------------------------------------------------------------
# Background apps
# ---------------------------------------------------------------------------
if ($DisableBackgroundApps) {
    Write-Step 'Background apps'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    Write-Ok 'Global background app access disabled.'
} else {
    Write-Info 'Background app changes skipped (use -DisableBackgroundApps).'
}

# ---------------------------------------------------------------------------
# UWP app removal
# ---------------------------------------------------------------------------
$appsToRemove = @()
if ($RemoveNonEssentialApps) {
    $appsToRemove += @(
        'Microsoft.3DBuilder',
        'Microsoft.BingFinance',
        'Microsoft.BingNews',
        'Microsoft.BingSports',
        'Microsoft.BingWeather',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.Microsoft3DViewer',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MixedReality.Portal',
        'Microsoft.People',
        'Microsoft.SkypeApp',
        'Microsoft.Wallet',
        'Microsoft.WindowsMaps',
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsCommunicationsApps',
        'Microsoft.OneConnect',
        'Microsoft.WindowsAlarms',
        'Microsoft.WindowsSoundRecorder',
        'Microsoft.YourPhone'
    )
}
if ($RemoveXboxApps) {
    $appsToRemove += @(
        'Microsoft.XboxApp',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.Xbox.TCUI',
        'Microsoft.GamingApp'
    )
}
$appsToRemove = $appsToRemove | Select-Object -Unique

if ($appsToRemove.Count -gt 0) {
    Write-Step 'UWP app removal'

    $installed = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $appsToRemove -contains $_.Name })
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $appsToRemove -contains $_.DisplayName })

    $removedNames = @()

    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
        Write-Info 'No matching installed/provisioned UWP apps found.'
    } else {
        foreach ($a in $installed) {
            Write-Info "Installed: $($a.Name)"
            try {
                Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok "Removed: $($a.Name)"
                $removedNames += $a.Name
            } catch {
                Write-Warn "Could not remove $($a.Name): $($_.Exception.Message)"
            }
        }

        foreach ($p in $provisioned) {
            Write-Info "Provisioned: $($p.DisplayName)"
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                Write-Ok "Deprovisioned: $($p.DisplayName)"
                $removedNames += $p.DisplayName
            } catch {
                Write-Warn "Could not deprovision $($p.DisplayName): $($_.Exception.Message)"
            }
        }

        $removedNames = $removedNames | Select-Object -Unique
        $removedNames | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $script:BackupDir 'removed-apps.json') -Encoding UTF8
        Write-Warn 'Removed/deprovisioned UWP apps cannot be automatically reinstalled.'
        Write-Warn "Removed app list: $(Join-Path $script:BackupDir 'removed-apps.json')"
        Write-Warn 'Reinstall them manually from Microsoft Store if needed.'
    }
} else {
    Write-Info 'UWP app removal skipped (use -RemoveNonEssentialApps and/or -RemoveXboxApps).'
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Step 'Current status'
& powercfg.exe /getactivescheme
Write-Info "Defender exclusion paths: (not changed by this script)"
Write-Info "Telemetry services and scheduled tasks: see backup folder for original state."

Write-Step 'Done'
Write-Ok "Backup: $script:BackupDir"
Write-Ok "Log: $script:LogPath"
Write-Warn 'Reboot required after telemetry/service changes.'
Write-Info 'Revert: run the same script with -Revert.'
Write-Info 'This script does not change BIOS, NVIDIA Control Panel, Defender, or in-game settings.'

Stop-Transcript | Out-Null