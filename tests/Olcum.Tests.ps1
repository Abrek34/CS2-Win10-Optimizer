Describe 'Olcum cozumleyicileri (dil ve surum bagimsiz)' {

    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'CS2Optimizer.psm1') -Force -ErrorAction Stop

        $benchmark = Get-Content (Join-Path $root 'Get-Cs2Benchmark.ps1') -Raw
        $target   = Get-Content (Join-Path $root 'Get-Cs2TargetCheck.ps1') -Raw
        $module   = Get-Content (Join-Path $root 'CS2Optimizer.psm1') -Raw

        # Turkce Windows ping ciktisi (gercek yerellesim)
        $script:PingTr = @'
8.8.8.8 icin 32 bayt veri:
8.8.8.8 yanit: bayt=32 sure=14ms TTL=116
8.8.8.8 yanit: bayt=32 sure=13ms TTL=116
8.8.8.8 yanit: bayt=32 sure=15ms TTL=116

8.8.8.8 icin Ping istatistikleri:
    Paketler: Gonderilen = 3, Alinan = 3, Kaybedilen = 0 (0% kayip),
    En yuksek = 15ms, En dusuk = 13ms, Ortalama = 14ms
'@

        # Ingilizce Windows ping ciktisi
        $script:PingEn = @'
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=14 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=13 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=118 time=15 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0 lost (0% loss),
round-trip min/avg/max = 13/14/15 ms
'@
    }

    Context 'ConvertFrom-PingOutput' {

        It 'Turkce ping ciktisini ayristirir' {
            $r = ConvertFrom-PingOutput -Text $script:PingTr
            $r.Samples    | Should -Be 3
            $r.PacketLoss | Should -Be 0
            $r.AvgMs      | Should -Be 14
            $r.MinMs      | Should -Be 13
            $r.MaxMs      | Should -Be 15
        }

        It 'Ingilizce ping ciktisini ayristirir' {
            $r = ConvertFrom-PingOutput -Text $script:PingEn
            $r.Samples    | Should -Be 3
            $r.PacketLoss | Should -Be 0
            $r.AvgMs      | Should -Be 14
        }

        It 'Tur ve Ingilizce ciktilar ayni sonucu uretir' {
            $tr = ConvertFrom-PingOutput -Text $script:PingTr
            $en = ConvertFrom-PingOutput -Text $script:PingEn
            $en.Samples    | Should -Be $tr.Samples
            $en.PacketLoss | Should -Be $tr.PacketLoss
            $en.AvgMs      | Should -Be $tr.AvgMs
            $en.JitterMs   | Should -Be $tr.JitterMs
        }

        It 'Paket kaybini Turkce ozet satirindan okur' {
            $tr = @'
1.1.1.1 yanit: bayt=32 sure=8ms TTL=57
1.1.1.1 yanit: bayt=32 sure=9ms TTL=57
Istek zaman asimina ugradi.
Istek zaman asimina ugradi.

1.1.1.1 icin Ping istatistikleri:
    Paketler: Gonderilen = 4, Alinan = 2, Kaybedilen = 2 (50% kayip),
    En yuksek = 9ms, En dusuk = 8ms, Ortalama = 8ms
'@
            $r = ConvertFrom-PingOutput -Text $tr
            $r.PacketLoss | Should -Be 50
            $r.Samples    | Should -Be 2
        }

        It 'Paket kaybini Ingilizce ozet satirindan okur' {
            $en = @'
64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=8 ms
64 bytes from 1.1.1.1: icmp_seq=2 ttl=57 time=9 ms

--- 1.1.1.1 ping statistics ---
4 packets transmitted, 2 received, 2 lost (50% loss),
'@
            $r = ConvertFrom-PingOutput -Text $en
            $r.PacketLoss | Should -Be 50
        }

        It 'Ozet blogundaki min/max/ortalama degerleri ornek olarak sayilmaz' {
            # Turkce ozet: "En yuksek = 15ms, En dusuk = 13ms, Ortalama = 14ms"
            # Bunlar yanit satiri DEGILDIR; ornek sayisini bozmamalidir.
            $r = ConvertFrom-PingOutput -Text $script:PingTr
            $r.Samples | Should -Be 3
            $r.MaxMs   | Should -Be 15
        }

        It 'Jitter ardisik ornek farklarinin ortalamasidir (ortalama-en kucuk DEGIL)' {
            # 10,20,10,20 -> ardisik farklar: 10,10,10 -> jitter 10
            #                eski formül (ortalama - en kucuk) = 15-10 = 5 olurdu
            $text = @'
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=10 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=20 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=118 time=10 ms
64 bytes from 8.8.8.8: icmp_seq=4 ttl=118 time=20 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0 lost (0% loss),
'@
            $r = ConvertFrom-PingOutput -Text $text
            $r.JitterMs | Should -Be 10
        }

        It 'Bos girdi guvenli sekilde bos sonuc doner' {
            $r = ConvertFrom-PingOutput -Text ''
            $r.Samples | Should -Be 0
            $r.PacketLoss | Should -BeNullOrEmpty
        }
    }

    Context 'ConvertFrom-PowerCfgText' {

        It 'Ingilizce etiketi okur' {
            $text = @'
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)
  Subgroup GUID: 54533251-82be-4824-96c1-47b60b740d00  (Processor)
    Power Setting GUID: 893dee8e-2bef-41e0-89c6-b55d0929964c  (Minimum processor state)
      Current AC Power Setting Index: 0x00000005
      Current DC Power Setting Index: 0x00000003
'@
            ConvertFrom-PowerCfgText -Text $text | Should -Be 5
        }

        It 'Turkce etiketi okur (eski regex burada basarisiz olurdu)' {
            $text = @'
Guc Semasi GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Dengeli)
  Alt grup GUID: 54533251-82be-4824-96c1-47b60b740d00  (Islemci)
    Guc Ayari GUID: 893dee8e-2bef-41e0-89c6-b55d0929964c  (En dusuk islemci durumu)
      Mevcut AC Guc Ayari Dizinu: 0x00000005
      Mevcut DC Guc Ayari Dizinu: 0x00000003
'@
            ConvertFrom-PowerCfgText -Text $text | Should -Be 5
        }

        It 'AC degerini DC degerine tercih eder' {
            $text = @'
      Current DC Power Setting Index: 0x00000001
      Current AC Power Setting Index: 0x00000050
'@
            ConvertFrom-PowerCfgText -Text $text | Should -Be 80
        }

        It 'Etiket taninmazsa ilk hex satiri kullanir (AC her zaman once yazilir)' {
            $text = @'
      Aktuelle Wechselstrom-Leistungseinstellungsindex: 0x00000007
      Aktuelle Gleichstrom-Leistungseinstellungsindex: 0x00000001
'@
            ConvertFrom-PowerCfgText -Text $text | Should -Be 7
        }

        It 'GUID satirlari hex deger sanilmaz' {
            $text = @'
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)
  Subgroup GUID: 54533251-82be-4824-96c1-47b60b740d00  (Processor)
'@
            ConvertFrom-PowerCfgText -Text $text | Should -BeNullOrEmpty
        }

        It 'Bos girdi guvenli sekilde bos sonuc doner' {
            ConvertFrom-PowerCfgText -Text '' | Should -BeNullOrEmpty
        }
    }

    Context 'Get-FrameTimeStats' {

        BeforeAll {
            function New-Pm2Csv {
                param([double[]]$Times, [double[]]$InputLatency)
                $lines = @('Application,ProcessID,MsBetweenPresents,MsAllInputToPhotonLatency,DisplayLatency')
                for ($i = 0; $i -lt $Times.Count; $i++) {
                    $il = if ($InputLatency) { $InputLatency[$i] } else { 0 }
                    $lines += "cs2.exe,1000,$($Times[$i]),$il,4.10"
                }
                return ($lines -join "`n")
            }
        }

        It 'PresentMon 2.x: MsBetweenPresents kolonunu bulur (FrameTime yoktur)' {
            $csv = New-Pm2Csv -Times @(2.78, 2.78, 2.78, 8.50, 2.78)
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.Column | Should -Be 'MsBetweenPresents'
            $s.Frames | Should -Be 5
        }

        It 'PresentMon 1.x / CapFrameX: FrameTime kolonunu bulur' {
            $csv = @'
Application,ProcessID,FrameTime,MsBetweenPresents
cs2.exe,1000,2.780,2.780
cs2.exe,1000,2.780,2.780
cs2.exe,1000,8.500,8.500
'@
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.Column | Should -Be 'FrameTime'
            $s.Frames | Should -Be 3
        }

        It '1% low degerini hesaplar (en yavas %1 karelerin ortalamasi)' {
            $times = @(1..198 | ForEach-Object { 10.0 }) + @(50.0, 50.0)
            $csv = New-Pm2Csv -Times $times
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.Low1Ms  | Should -Be 50
            $s.Low1FPS | Should -Be 20
        }

        It '0.1% low degerini hesaplar' {
            $times = @(1..998 | ForEach-Object { 10.0 }) + @(40.0, 40.0)
            $csv = New-Pm2Csv -Times $times
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.Low01Ms  | Should -Be 40
            $s.Low01FPS | Should -Be 25
        }

        It 'Turkce yerellesimde ondalik ayraci bozulmaz (2.780 -> 2780 olmamali)' {
            $csv = @'
Application,ProcessID,MsBetweenPresents
cs2.exe,1000,2.780
cs2.exe,1000,2.780
cs2.exe,1000,2.780
'@
            $rows = $csv | ConvertFrom-Csv
            $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture =
                    [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                $s = Get-FrameTimeStats -Rows $rows
                $s.AvgMs | Should -Be 2.78
                $s.AvgFPS | Should -BeGreaterThan 300
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $old
            }
        }

        It 'input-to-photon gecikmesini raporlar' {
            $csv = New-Pm2Csv -Times @(2.78, 2.78, 2.78) -InputLatency @(18.4, 19.1, 18.8)
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.InputLatencyAvgMs | Should -Be 18.767
            $s.InputLatencyColumn | Should -Be 'MsAllInputToPhotonLatency'
        }

        It 'CS2 disi uygulama satirlarini filtreler' {
            $csv = @'
Application,ProcessID,MsBetweenPresents
cs2.exe,1000,2.78
chrome.exe,2000,16.60
cs2.exe,1000,2.78
'@
            $s = Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv)
            $s.Frames | Should -Be 2
            $s.AvgMs  | Should -Be 2.78
        }

        It 'Bos veri icin null doner' {
            Get-FrameTimeStats -Rows @() | Should -BeNullOrEmpty
        }

        It 'Frame time kolonu yoksa null doner' {
            $csv = @'
Application,ProcessID,Runtime
cs2.exe,1000,DXGI
'@
            Get-FrameTimeStats -Rows ($csv | ConvertFrom-Csv) | Should -BeNullOrEmpty
        }
    }

    Context 'Regresyon: yerelle bagli regexler geri gelmemeli' {

        BeforeAll {
            # Yorum satirlari eski davranisi ANLATIYOR; kontrol kod satirlarina bakar.
            function Get-CodeOnly {
                param([string]$Content)
                $c = $Content -replace '(?s)<#.*?#>', ''   # blok yorumlari (yardim metni)
                return (($c -split "`r?`n") |
                    Where-Object { $_.Trim() -notmatch '^(#|\*|//)' }) -join "`n"
            }
            $script:ModuleCode   = Get-CodeOnly -Content $module
            $script:TargetCode   = Get-CodeOnly -Content $target
            $script:BenchCode    = Get-CodeOnly -Content $benchmark
        }

        It 'Modulde "Current AC Power Setting Index" etiketine bagimli regex yok' {
            $script:ModuleCode | Should -Not -Match 'Current AC Power Setting Index'
        }

        It 'TargetCheck scriptinde yerelle bagli etiket regexi yok' {
            $script:TargetCode | Should -Not -Match 'Current AC Power Setting Index'
        }

        It 'Benchmark scripti yalnizca $r.FrameTime okumaz' {
            $script:BenchCode | Should -Not -Match '\$r\.FrameTime'
        }

        It 'Benchmark scripti yerelle bagli "packet loss" regexini kullanmaz' {
            $script:BenchCode | Should -Not -Match 'packet\s\+loss'
        }

        It 'Benchmark scripti 2 argumanli TryParse kullanmaz' {
            # 2 argumanli TryParse CurrentCulture kullanir; Turkce locale'de
            # "2.780" -> 2780 olur.
            $script:BenchCode | Should -Not -Match 'TryParse\([^,]+,\s*\[ref\]'
            $script:ModuleCode | Should -Not -Match 'TryParse\([^,]+,\s*\[ref\]'
        }

        It 'Modul ve scriptler dil-bagimsiz cozumleyicileri kullanir' {
            $script:ModuleCode | Should -Match 'ConvertFrom-PowerCfgText'
            $script:ModuleCode | Should -Match 'ConvertFrom-PingOutput'
            $script:ModuleCode | Should -Match 'Get-FrameTimeStats'
            $script:BenchCode  | Should -Match 'ConvertFrom-PingOutput'
            $script:BenchCode  | Should -Match 'Get-FrameTimeStats'
        }
    }
}
