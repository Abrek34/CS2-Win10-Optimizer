Describe 'Regresyon: gecmiste bulunan gercek hatalar' {

    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $main = Get-Content (Join-Path $root 'CS2-Windows10-Optimize.ps1') -Raw
        $oneclick = Get-Content (Join-Path $root 'CS2-Desktop-OneClick.ps1') -Raw
        $usb = Get-Content (Join-Path $root 'CS2-Win10-UsbIdleDisable.ps1') -Raw
        $target = Get-Content (Join-Path $root 'Get-Cs2TargetCheck.ps1') -Raw
        $network = Get-Content (Join-Path $root 'CS2-Win10-Network-Tuning.ps1') -Raw
    }

    Context 'powercfg revert siralamasi' {

        It 'Ana script: alt ayarlar aktif plan degistirilmeden ONCE geri yuklenir' {
            # Revert blogunda powercfg geri yukleme, plan degistirmeden once olmali.
            $revertBlock = $main.Substring($main.IndexOf('if ($Revert)'), $main.IndexOf('if (-not $Apply)') - $main.IndexOf('if ($Revert)'))
            $pcfgPos = $revertBlock.IndexOf('powercfg-backup.json')
            $schemePos = $revertBlock.IndexOf('power-scheme.txt')
            $pcfgPos | Should -BeGreaterThan 0
            $schemePos | Should -BeGreaterThan 0
            $pcfgPos | Should -BeLessThan $schemePos
        }

        It 'Ana script: ASPM ve USB suspend degerleri yedeklenir' {
            $main | Should -Match "Backup-PowerCfgValue -Alias 'SUB_PCIEXPRESS ASPM'"
            $main | Should -Match "Backup-PowerCfgValue -Alias '2a737441-1930-4402-8d77-b2bebba308a3"
        }

        It 'Ana script: powercfg yedegi diske yazilir' {
            $main | Should -Match 'Save-PowerCfgBackup -BackupDir'
        }

        It 'OneClick: powercfg yedegi diske yazilir' {
            $oneclick | Should -Match 'Save-PowerCfgBackup -BackupDir'
        }

        It 'OneClick: ASPM ve USB suspend yedeklenir' {
            $oneclick | Should -Match "Backup-PowerCfgValue -Alias 'SUB_PCIEXPRESS ASPM'"
        }
    }

    Context 'OneClick revert destegi' {

        It 'OneClick: -Revert parametresi var' {
            $oneclick | Should -Match '\[switch\]\$Revert'
        }

        It 'OneClick: revert registry, NIC, defender ve powercfg geri yukler' {
            $oneclick | Should -Match 'Restore-RegBackups'
            $oneclick | Should -Match 'nic-backup\.json'
            $oneclick | Should -Match 'defender-backup\.json'
            $oneclick | Should -Match 'powercfg-backup\.json'
        }

        It 'Ana script gibi OneClick de Revert blogunu Apply oncesine koyar' {
            $revertPos = $oneclick.IndexOf('if ($Revert)')
            $applyPos = $oneclick.IndexOf('if (-not $Apply)')
            if ($applyPos -ge 0) {
                $revertPos | Should -BeLessThan $applyPos
            }
        }
    }

    Context 'ollu parametreler' {

        It 'USB scripti: -UsbHubOnly gercekten kullaniliyor' {
            $usb | Should -Match 'Get-UsbDeviceKeys -HubOnly'
            $usb | Should -Match '\[bool\]\$UsbHubOnly'
        }

        It 'TargetCheck: -Cs2Path raporda kullaniliyor' {
            $target | Should -Match 'CS2 kurulum yolu'
            $target | Should -Match '\$Cs2Path'
        }
    }

    Context 'MMCSS degerleri' {

        It 'Scheduling Category High KULLANILMIYOR (stutter riski)' {
            # High -> Pro Audio bandi (23-26), sistem thread'lerini starve eder.
            $main | Should -Not -Match "Scheduling Category' 'High'"
            $main | Should -Match "Scheduling Category' 'Medium'"
        }
    }

    Context 'Network: guvenli varsayilanlar' {

        It 'Ana script: Flow Control yalnizca explicit -DisableFlowControl ile kapanir' {
            # Akis Kontrolu (flow control) kapatmak paket kaybini artirir.
            $main | Should -Match '\[switch\]\$DisableFlowControl'
        }

        It 'Network scripti: RSC ancak explicit -DisableRsc ile kapatilir' {
            $network | Should -Match '\[switch\]\$DisableRsc'
            $network | Should -Not -Match "KeywordPattern '\^\\\*RSC\$'.*Value 'Disabled'\s*$"
        }
    }
}

Describe 'Tum scriptler icin ortak kurallar' {

    BeforeDiscovery {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $scriptFiles = Get-ChildItem -Path $scriptRoot -Filter '*.ps1' -File | Where-Object { $_.Name -notlike 'tests*' }
    }

    It '$_: yapisal olarak gecerli' -ForEach $scriptFiles {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It '$_: ortak modulu import ediyor' -ForEach $scriptFiles {
        $content = Get-Content $_.FullName -Raw
        $content | Should -Match "Import-Module \(Join-Path \`$PSScriptRoot 'CS2Optimizer\.psm1'\)"
    }

    It '$_: modul bulunamazsa graceful fallback var' -ForEach $scriptFiles {
        $content = Get-Content $_.FullName -Raw
        $content | Should -Match 'catch\s*\{[^}]*Write-Warning'
        $content | Should -Match 'if \(-not \(Get-Command -Name ''Write-Info'''
    }
}
