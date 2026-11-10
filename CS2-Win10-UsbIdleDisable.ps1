#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  USB cihaz seviyesinde güç yönetimini kapatır (fare/klavye gecikmesi için).

.DESCRIPTION
  Windows'ta USB güç yönetimi iki farklı katmanda çalışır:

    1) OS katmanı  : "USB selective suspend" (powercfg / USB 2a737441.../48e6b7a6...)
                      -> projede zaten kapatiliyor.
    2) Cihaz katmanı: Her USB cihazın kendi "Device Parameters" altında
                       SelectiveSuspendOn / AllowIdleIrpInD3 / IdleInWorkingState
                       gibi değerler vardir. Bunlar KAPALI degilse cihaz
                       kendi guc yonetimine girip gecikmeye yol acar.

  Bu script 2. katmani kapatir: WMIC ile USB hub'lari listeler, her cihaz icin
  Device Parameters altindaki idle/suspend degerlerini 0 yapar.

  AYNI KATMANDA YAPILAN DIGER SEYLER:
    - Nagle / TcpAckFrequency / TCPNoDelay          -> REDDEDILDI (CS2 UDP)
    - NetworkThrottlingIndex = 0xFFFFFFFF           -> REDDEDILDI (DPC latency artar)
    - SystemResponsiveness = 0                       -> REDDEDILDI (proje 10 kullanir)
    - netsh heuristics/timestamps/ecn disabled       -> REDDEDILDI (dusuk FPS, placebo)
    - netsh int tcp set global rsc=disabled          -> REDDEDILDI (CPU yukunu artirir)
    - arp -d * / nbtstat -R                         -> REDDEDILDI (yalniza birkac kez)
    - Disable-NetAdapterPowerManagement              -> zaten projede var

  Bu script SADECE USB cihaz idle/suspend degerlerine dokunur.

  Duyarlilik: Registry'deki "EnhancedPowerManagementEnabled" gibi bazi degerler
  yalnizca Windows 10/11'de mevcut olabilir; bulunamayan degerler atlanir.

  Onemli: Degisiklikten sonra USB cihazlarinin yeniden takilmasi ya da sistemin
  yeniden baslatilmasi gerekebilir.

.PARAMETER Apply
  Degisiklikleri uygula. Verilmezse dry run (yalnizca liste).

.PARAMETER Revert
  Kaydedilen orijinal degerleri geri yukle.

.PARAMETER UsbHubOnly
  Sadece USB hub'lari (fare/klavye bagli olduklari icin) hedefle.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-UsbIdleDisable.ps1

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-UsbIdleDisable.ps1 -Apply

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-UsbIdleDisable.ps1 -Revert
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$UsbHubOnly
)

$ErrorActionPreference = 'Continue'
$script:Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Desktop = [Environment]::GetFolderPath('Desktop')
$script:StateFile = Join-Path $script:Desktop "CS2-UsbIdle-State-$script:Stamp.json"

Import-Module (Join-Path $PSScriptRoot 'CS2Optimizer.psm1') -Force -ErrorAction Stop

# Cihaz idle/suspend ile ilgili tum degerler
$idleValues = @(
    'EnhancedPowerManagementEnabled',
    'AllowIdleIrpInD3',
    'SelectiveSuspendOn',
    'DeviceSelectiveSuspended',
    'SelectiveSuspendEnabled',
    'IdleInWorkingState'
)

function Get-UsbDeviceKeys {
    $result = New-Object System.Collections.Generic.List[string]
    try {
        $hubs = @(Get-CimInstance Win32_USBHub -ErrorAction SilentlyContinue)
        foreach ($h in $hubs) {
            $id = $h.DeviceID
            if (-not $id) { continue }
            # DeviceID: USB\ROOT_HUB30\... veya USB\VID_...&PID_...\&...
            $enumKey = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id
            if (-not (Test-Path $enumKey)) { continue }

            # Altinda VID_...&PID_... cihazlar olabilir
            $children = @(Get-ChildItem -Path $enumKey -ErrorAction SilentlyContinue)
            if ($children.Count -eq 0) {
                $result.Add($enumKey)
                continue
            }
            foreach ($child in $children) {
                $result.Add($child.PSPath)
            }
        }
    } catch {
        Write-Warn "USB hub listesi alinamadi: $($_.Exception.Message)"
    }
    return $result
}

if ($Revert) {
    Write-Step 'Revert: USB idle degerleri'

    $files = Get-ChildItem -Path $script:Desktop -Filter 'CS2-UsbIdle-State-*.json' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if (-not $files) {
        Write-Err 'No CS2-UsbIdle state file found.'
        exit 1
    }

    $state = Get-Content $files[0].FullName -Raw | ConvertFrom-Json
    $restored = 0
    $removed = 0
    foreach ($entry in $state.Entries) {
        $key = $entry.Key -replace '^HKEY_LOCAL_MACHINE', 'HKLM:'
        if (-not (Test-Path $key)) { continue }
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in $entry.Names) {
                $prop = $item.PSObject.Properties[$name]
                if ($null -eq $prop) { continue }
                $original = $entry.Original[$name]
                if ($null -eq $original) {
                    # Once yoktu -> sil
                    Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
                    $removed++
                } else {
                    New-ItemProperty -Path $key -Name $name -Value $original -PropertyType $entry.Types[$name] -Force | Out-Null
                    $restored++
                }
            }
        } catch {
            Write-Warn "$key geri yuklenemedi: $($_.Exception.Message)"
        }
    }
    Write-Ok "Geri yuklendi: $restored deger, silindi: $removed deger"
    Write-Info 'USB cihazlarini yeniden takmak veya sistemi yeniden baslatmak gerekebilir.'
    exit 0
}

# ---------------------------------------------------------------------------
# Kuru calisma / uygulama
# ---------------------------------------------------------------------------
$keys = Get-UsbDeviceKeys
if ($keys.Count -eq 0) {
    Write-Warn 'USB cihaz bulunamadi (WMIC/CIM erisimi yok olabilir).'
    exit 1
}

Write-Step "USB cihazlar: $($keys.Count)"

if (-not $Apply) {
    Write-Info 'DRY RUN - hicbir sey degistirilmedi.'
    $affected = 0
    foreach ($key in $keys) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            $found = @($idleValues | Where-Object { $null -ne $item.PSObject.Properties[$_] })
            if ($found.Count -gt 0) {
                Write-Info ("{0}  ->  {1}" -f ($key -replace '^.*Enum\\', ''), ($found -join ', '))
                $affected++
            }
        } catch { }
    }
    Write-Host ''
    Write-Ok "Etkilenecek cihaz: $affected / $($keys.Count)"
    Write-Info 'Uygulamak icin -Apply ekleyin.'
    exit 0
}

Write-Step 'USB idle / suspend degerleri kapatiliyor'

$entries = New-Object System.Collections.Generic.List[object]
$changed = 0

foreach ($key in $keys) {
    try {
        $item = Get-ItemProperty -Path $key -ErrorAction Stop
        $present = @()
        $original = @{}
        $types = @{}
        foreach ($name in $idleValues) {
            $prop = $item.PSObject.Properties[$name]
            if ($null -eq $prop) { continue }
            $present += $name
            $original[$name] = $prop.Value
            $types[$name] = $prop.TypeName
        }
        if ($present.Count -eq 0) { continue }

        $entries.Add([ordered]@{
            Key      = ($key -replace '^HKLM:', 'HKEY_LOCAL_MACHINE')
            Names    = $present
            Original = $original
            Types    = $types
        })

        foreach ($name in $present) {
            New-ItemProperty -Path $key -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
        }
        Write-Ok ("{0}  ({1} deger)" -f ($key -replace '^.*Enum\\', ''), $present.Count)
        $changed++
    } catch {
        Write-Warn "Islenemedi: $key  ($($_.Exception.Message))"
    }
}

if ($entries.Count -gt 0) {
    $state = [ordered]@{
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Entries   = $entries
    }
    $state | ConvertTo-Json -Depth 8 | Set-Content -Path $script:StateFile -Encoding UTF8
    Write-Ok "Orijinal degerler kaydedildi: $script:StateFile"
}

Write-Host ''
Write-Ok "Guncellenen cihaz: $changed"
Write-Warn 'Degisiklikten sonra USB cihazlarini yeniden tak veya sistemi yeniden baslat.'
Write-Info 'Etkisi 8K Hz farede polling kaynakli gecikme icin daha belirgin olabilir.'
Write-Info 'Geri almak icin ayni scripti -Revert ile calistir.'
