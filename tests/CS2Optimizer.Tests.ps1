Describe 'CS2Optimizer modulu' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' 'CS2Optimizer.psm1'
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module CS2Optimizer -Force -ErrorAction SilentlyContinue
    }

    Context 'Split-PowerCfgAlias' {

        It 'cok kelimeli alias dogru parcalara ayirilir' {
            $parts = Split-PowerCfgAlias -Alias 'SUB_PROCESSOR PROCTHROTTLEMIN'
            $parts.Count | Should -Be 2
            $parts[0] | Should -Be 'SUB_PROCESSOR'
            $parts[1] | Should -Be 'PROCTHROTTLEMIN'
        }

        It 'iki kelimeli alias iki parcaya ayirilir' {
            $parts = Split-PowerCfgAlias -Alias 'SUB_DISK DISKIDLE'
            $parts.Count | Should -Be 2
            $parts[0] | Should -Be 'SUB_DISK'
            $parts[1] | Should -Be 'DISKIDLE'
        }

        It 'bos girdi bos dizi doner' {
            $parts = Split-PowerCfgAlias -Alias '   '
            $parts.Count | Should -Be 0
        }
    }

    Context 'Format-Bytes' {

        It 'byte degerini bayt olarak gosterir' {
            # Ondalik ayirici sistem yereline baglidir (TR: virgul, EN: nokta).
            $out = Format-Bytes -Bytes 512
            $out | Should -Match '^512[.,]00 B$'
        }

        It 'kilobyte degerine donusturur' {
            Format-Bytes -Bytes 1536 | Should -Match 'KB'
        }

        It 'megabyte degerine donusturur' {
            Format-Bytes -Bytes (5 * 1MB) | Should -Match 'MB'
        }

        It 'gigabyte degerine donusturur' {
            Format-Bytes -Bytes (3 * 1GB) | Should -Match 'GB'
        }

        It 'sifir deger N/A doner' {
            Format-Bytes -Bytes 0 | Should -Be 'N/A'
        }

        It 'null deger N/A doner' {
            Format-Bytes -Bytes $null | Should -Be 'N/A'
        }

        It 'negatif deger N/A doner' {
            Format-Bytes -Bytes -100 | Should -Be 'N/A'
        }
    }

    Context 'Format-Date' {

        It 'gecerli tarih degerini bicimlendirir' {
            $d = [datetime]'2026-01-02 03:04:05'
            Format-Date -Value $d | Should -Be '2026-01-02 03:04:05'
        }

        It 'null deger N/A doner' {
            Format-Date -Value $null | Should -Be 'N/A'
        }

        It 'string degeri oldugu gibi doner' {
            Format-Date -Value 'abc' | Should -Be 'abc'
        }
    }

    Context 'ConvertFrom-MonitorId' {

        It 'WMI monitor id dizisini metne cevirir' {
            ConvertFrom-MonitorId -Value @(65, 66, 67) | Should -Be 'ABC'
        }

        It 'sifir olmayan karakterleri atlar' {
            ConvertFrom-MonitorId -Value @(65, 0, 66) | Should -Be 'AB'
        }

        It 'null deger N/A doner' {
            ConvertFrom-MonitorId -Value $null | Should -Be 'N/A'
        }

        It 'tum sifir dizi N/A doner' {
            ConvertFrom-MonitorId -Value @(0, 0, 0) | Should -Be 'N/A'
        }
    }

    Context 'Modul disi API yuzeyi' {

        It 'tum scriptlerin kullandigi fonksiyonlari export eder' {
            $required = @(
                'Write-Step', 'Write-Info', 'Write-Ok', 'Write-Warn', 'Write-Err',
                'Get-RegValue', 'Test-RegValue', 'Set-RegDword', 'Set-RegString',
                'Backup-RegKey', 'Restore-RegBackups',
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
            $exported = (Get-Module CS2Optimizer).ExportedFunctions.Keys
            foreach ($fn in $required) {
                $exported | Should -Contain $fn
            }
        }
    }
}

Describe 'Script sozdizimi butunlugu' {

    BeforeDiscovery {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $scriptFiles = Get-ChildItem -Path $scriptRoot -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    }

    It 'tum .ps1 dosyalari sozdizimsel olarak gecerli' -ForEach $scriptFiles {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'modul dosyasi mevcut' {
        Join-Path (Split-Path -Parent $PSScriptRoot) 'CS2Optimizer.psm1' | Should -Exist
    }
}
