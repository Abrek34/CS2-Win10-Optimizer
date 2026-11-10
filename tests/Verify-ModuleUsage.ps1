# Modul yukleme ve cozumleme testi.
# Her script icin: Import-Module calisiyor mu, kullanilan fonksiyonlar
# modulde mevcut mu, script AST uzerinden ayristiriliyor mu?
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'CS2Optimizer.psm1'

Import-Module $module -Force
$exported = (Get-Module CS2Optimizer).ExportedFunctions.Keys

# Scriptlerde kullanilan yardimci fonksiyon adlari (modul disi kalan
# lokal tanimlar haric).
$moduleFns = @(
    'Write-Step', 'Write-Info', 'Write-Ok', 'Write-Warn', 'Write-Err',
    'Set-RegDword', 'Set-RegString', 'Backup-RegKey', 'Restore-RegBackups',
    'Get-LatestBackup', 'New-BackupDir',
    'Split-PowerCfgAlias', 'Get-PowerCfgValue', 'Set-PowerCfgValue',
    'Backup-PowerCfgValue', 'Save-PowerCfgBackup', 'Restore-PowerCfgBackup',
    'Reset-PowerCfgBackup',
    'Get-TargetAdapter', 'Get-NicProperties', 'Backup-NicProperties',
    'Restore-NicProperties', 'Set-NicPropertyByDisplayName',
    'Set-NicPropertyByKeyword', 'Get-NicStatistics',
    'Save-ServiceState', 'Restore-ServiceState',
    'Save-TaskState', 'Restore-TaskState', 'Save-Flag', 'Get-Flag',
    'Format-Bytes', 'Format-Date', 'ConvertFrom-MonitorId', 'Get-DefaultGateway'
)

$failed = $false
$files = Get-ChildItem -Path $root -Filter '*.ps1' -File | Sort-Object Name

foreach ($f in $files) {
    Write-Host "=== $($f.Name) ==="

    # 1) Sozdizimi
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors) {
        Write-Host "  [FAIL] Sozdizimi:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "     line $($_.Extent.StartLineNumber): $($_.Message)" }
        $failed = $true
        continue
    }
    Write-Host "  [OK] Sozdizimi"

    # 2) Modul importu
    if (Select-String -Path $f.FullName -Pattern 'Import-Module.*CS2Optimizer\.psm1' -Quiet) {
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $imports = $ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Import-Module'
            }, $true)
            if ($imports.Count -gt 0) {
                Write-Host "  [OK] Import-Module cagrisi mevcut ($($imports.Count) adet)"
            } else {
                Write-Host "  [FAIL] Import-Module bulunamadi" -ForegroundColor Red
                $failed = $true
            }
        } catch {
            Write-Host "  [FAIL] Import-Module AST hatasi: $($_.Exception.Message)" -ForegroundColor Red
            $failed = $true
        }
    } else {
        Write-Host "  [--] Modul kullanmiyor (bagimsiz script)"
    }

    # 3) Kullanilan yardimci fonksiyonlar modulde var mi?
    $text = Get-Content $f.FullName -Raw
    $missing = @()
    foreach ($fn in $moduleFns) {
        # Lokal tanim varsa module gerek yok.
        if ($text -match "(?m)^function\s+$([regex]::Escape($fn))\b") { continue }
        # Cagri olarak geciyor mu?
        if ($text -notmatch "\b$([regex]::Escape($fn))\b") { continue }
        # Modulde export edilmis olmali.
        if ($exported -notcontains $fn) { $missing += $fn }
    }
    if ($missing.Count -gt 0) {
        Write-Host "  [FAIL] Modulde olmayan ama cagrilan fonksiyonlar: $($missing -join ', ')" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "  [OK] Tum cagrilan yardimcilar cozumleniyor"
    }
}

Write-Host ""
if ($failed) {
    Write-Host "SONUC: BASARISIZ" -ForegroundColor Red
    exit 1
}
Write-Host "SONUC: TUM SCRIPTLER BASARILI" -ForegroundColor Green
exit 0
