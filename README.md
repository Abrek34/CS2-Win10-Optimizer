# CS2-Win10-Optimizer

Windows 10 + NVIDIA tarafında, **CS2 için oyun dışı** optimizasyonları belgeleyen ve uygulayan küçük bir araç seti.

> **Kapsam:** Windows 10 güç/scheduler, GameDVR/FSO, Defender exclusion, NIC power saving, HAGS A/B, NVIDIA Control Panel/Profile Inspector ayarları ve BIOS notları.  
> **Kapsam dışı:** CS2 oyun içi video/Crosshair/autoexec ayarları.  
> **Hedef sistem:** i9-9900K + Z390 + RTX 3070 + 64 GB DDR4-4000 + Windows 10 22H2. Ayrıntı: [`SISTEM-OZELLIKLERI.md`](SISTEM-OZELLIKLERI.md)

---

## İçerik

| Dosya | Açıklama |
|---|---|
| `CS2-Windows10-Optimize.ps1` | Ana script. Dry-run, yedek, restore point, `-Revert`. |
| `CS2-Desktop-OneClick.ps1` | Aynı baseline'ın daha basit tek tık varyantı. `-Revert` destekler. |
| `CS2-Optimize-Baslat.cmd` | PowerShell başlatıcı. |
| `Get-Cs2SystemReport.ps1` | Sistemi envanterler ve Masaüstü'ne Markdown + JSON raporu yazar. Okunur (read-only); hiçbir ayarı değiştirmez. |
| `CS2-Win10-WinUtil-Preferences.ps1` | WinUtil incelemesinden seçilen düşük riskli tercihleri uygular: activity history, location tracking, consumer features, delivery optimization, device companion apps, Razer/Logitech auto-install, Teredo, IPv4 preference, reserved storage, Explorer folder discovery, end task right click. Dry-run varsayılan; backup/revert destekler. |
| `CS2-Win10-Background-Telemetry-Cleanup.ps1` | CS2 odaklı arka plan/telemetri temizliği: DiagTrack/dmwappushservice, CEIP/uyumluluk görevleri, AllowTelemetry, background apps, opsiyonel UWP kaldırma. Dry-run varsayılan; servis/görev/registry backup ve revert destekler. UWP kaldırma tam geri alınamaz. |
| `CS2-Win10-Network-Tuning.ps1` | Düşük latency + paket kaybı yok: link power saving off, WoL off, adapter power management off, RSS on, TCP autotuning normal. Interrupt Moderation/RSC opsiyonel A/B. Flow Control **açık bırakılır** (paket kaybı koruması). Dry-run varsayılan; backup/revert destekler. |
| `CS2-Win10-UsbIdleDisable.ps1` | USB **cihaz seviyesinde** idle/suspend kapatma (fare/klavye polling gecikmesi). Powercfg katmanından ayrı; orijinal değerleri JSON'a kaydedip geri alır. Dry-run varsayılan. |
| `Get-Cs2AimMatrix.ps1` | DPI / CS2 sens / polling matrisi hesaplar: eDPI sabitken DPI kademeleri, cm/360, polling doygunluk hızları ve polling×FPS etkileşimi. Read-only. |
| `Get-Cs2RawAccelCheck.ps1` | RawAccel kurulumunu denetler: sürücü durumu, settings.json çarpanları ve CS2'de **gerçekte oynadığınız** sens/cm-360 değerini hesaplar. Read-only. |
| `Get-Cs2TargetCheck.ps1` | **Hedef profil denetimi.** "CS2 mükemmel sistem" tanımına göre sistemdeki her katmanı kontrol eder; OK/WARN/FAIL + gereken aksiyon raporu üretir. Read-only. |
| `Get-Cs2Benchmark.ps1` | **Ölçüm motoru.** CapFrameX/PresentMon frame time, HWiNFO/nvidia-smi sensörleri, ağ jitter/paket kaybı ve NIC discard sayaçlarını toplar; `summary.md` + `summary.json` üretir. Hiçbir ayarı değiştirmez. |
| `Get-Cs2GpuProfile.ps1` | RTX 3070 power limit yönetimi (nvidia-smi) + doğrulanmış NVIDIA Profile Inspector (.nip) profili üretimi. Revert destekler. |
| `CS2Optimizer.psm1` | Ortak yardımcı modülü (registry, powercfg, NIC, backup/revert). Tüm scriptler bunu kullanır. |
| `RAPOR.md` | Tüm ayarlar, gerekçeler, uygulama sırası, ölçüm protokolü, yapma listesi. |
| `SISTEM-OZELLIKLERI.md` | Ayarların hangi donanım özelliklerine göre seçildiği. |
| `CHANGELOG.md` | Sürüm sürüm değişiklikler. |
| `tests/` | Pester testleri. |

---

## Önerilen iş akışı

Projenin felsefesi: **tek değişiklik → ölçüm → karar.** Şu sırayla ilerle:

```powershell
# 1) Sistem envanteri (read-only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2SystemReport.ps1

# 1b) Hedef profile kac uzakta? (read-only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2TargetCheck.ps1

# 1c) DPI/sens/polling matrisi (read-only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2AimMatrix.ps1 -Dpi 400 -Sens 2.0

# 1d) RawAccel carpanlari ve gercek etkin sens (read-only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2RawAccelCheck.ps1 -Cs2Sens 2.0 -Dpi 400

# 2) Baseline ölçümü (CS2 açıkken çalıştır)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2Benchmark.ps1 -Label baseline

# 3) Bir değişiklik uygula (dry-run önce!)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -SetProcessorPerformance

# 4) Tekrar ölç ve karşılaştır
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2Benchmark.ps1 -Label after-processor-perf

# 5) Fark yoksa geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
```

> Ölçüm karşılaştırmasında **ortalama FPS değil 1% low ve frametime p99** dikkat et.
>
> **Hedef profilin tam tanımı:** [`docs/HEDEF-PROFIL.md`](docs/HEDEF-PROFIL.md)

---

## Hızlı başlangıç

> ✅ **Bu depo public.** Release ZIP'ini tarayıcıdan doğrudan indirebilirsiniz
> (giriş gerekmez):
>
> ```
> https://github.com/Abrek34/CS2-Win10-Optimizer/releases/download/v1.12.1/CS2-Win10-Optimizer-v1.12.1.zip
> ```
>
> Alternatif yollar ve SHA256 doğrulama: [`docs/INDIRME.md`](docs/INDIRME.md)

```bash
# Komut satirindan (gh kurulu ve giris yapilmis olmali)
gh release download --repo Abrek34/CS2-Win10-Optimizer --pattern '*.zip' --dir .
gh release download --repo Abrek34/CS2-Win10-Optimizer --pattern 'SHA256SUMS' --dir .
sha256sum -c SHA256SUMS
```

ZIP'i açtıktan sonra **`CS2Optimizer.psm1` dosyasını silmeyin** (ortak modül).

PowerShell'i **yönetici** olarak aç:

```powershell
# 1) Hiçbir değişiklik yapmadan kontrol
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1

# 2) Önerilen ilk uygulama
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -AddDefenderExclusions -RestoreTimerDefaults

# 3) Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
```

Alternatif tek tık:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Desktop-OneClick.ps1
```

veya `CS2-Optimize-Baslat.cmd` dosyasına çift tıkla.

---

## Sistem raporu (envanter)

`Get-Cs2SystemReport.ps1` sistemi envanterler ve Masaüstü'ne `CS2-SystemReport-<zaman damgası>.md` ve `.json` dosyaları yazar. **Hiçbir ayarı değiştirmez** (read-only).

```powershell
# Masaüstü'ne rapor üret
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2SystemReport.ps1

# Farklı klasöre üret ve Markdown'u aç
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2SystemReport.ps1 -OutputDirectory "C:\Temp\Raporlar" -Open
```

Raporun içinde: işletim sistemi, CPU, RAM modülleri (slot, üretici, hız, yapılandırılmış hız), anakart/BIOS, GPU/VRAM (nvidia-smi ve WMI), monitör (çözünürlük/Hz), depolama, NIC (link hızı, IPv4, DNS, gelişmiş NIC özellikleri), güç planı, HAGS/GameDVR/power throttling gibi kayıt defteri ayarları, Defender exclusion'ları ve CS2 kurulum yolu.

`RAPOR.md`'deki “bilinmiyor” yerlerini (monitör Hz, RAM düzeni, NVIDIA sürücü sürümü, ağ) doldurmak için bu raporu kullanabilirsin.

---

## Script ne yapar?

- High Performance güç planı, PCIe ASPM off, USB selective suspend off.
- GameDVR/AppCapture/GameBar policy off; Game Mode on.
- Opsiyonel HAGS on/off (`-EnableHags` / `-DisableHags`).
- Opsiyonel Defender exclusions (`-AddDefenderExclusions`) — sadece CS2 klasörü + `cs2.exe`.
- NIC: EEE/Green/Wake/Power Saving/Selective Suspend off; RSS on.
- Opsiyonel NIC latency modu (`-TuneNicLatency`): Interrupt Moderation + Flow Control off.
- TCP autotuning normal, RSS enabled; **Nagle/NetworkThrottling'e dokunmaz**.
- Opsiyonel Fast Startup off (`-DisableFastStartup`).
- Opsiyonel FSO off (`-DisableFullscreenOptimizations`).
- Windows GPU preference = High performance (`cs2.exe`).
- Opsiyonel timer BCD temizliği (`-RestoreTimerDefaults`).
- Opsiyonel GameBoost-derived tweak'ler: MPO disable (`-DisableMpo`), Storage Sense disable (`-DisableStorageSense`), background apps disable (`-DisableBackgroundApps`), system VRR toggle (`-EnableSystemVrr` / `-DisableSystemVrr`).
- Opsiyonel WinUtil-derived tercihler: `CS2-Win10-WinUtil-Preferences.ps1` (activity history, location tracking, consumer features, delivery optimization, device companion apps, Razer/Logitech auto-install, Teredo, IPv4 preference, reserved storage, Explorer folder discovery, end task right click). Dry-run varsayılan.
- Arka plan/telemetri temizliği: `CS2-Win10-Background-Telemetry-Cleanup.ps1` (DiagTrack/dmwappushservice, CEIP/uyumluluk görevleri, AllowTelemetry, background apps, opsiyonel UWP kaldırma). Dry-run varsayılan; UWP kaldırma tam geri alınamaz.
- Ağ ayarları: `CS2-Win10-Network-Tuning.ps1` (link power saving off, WoL off, adapter power management off, RSS on, TCP autotuning normal; Interrupt Moderation/RSC opsiyonel A/B; **Flow Control açık kalır**).
- Opsiyonel performans/latency: `-SetProcessorPerformance` (min/max %100, EPP 0, aggressive boost), `-DisableIdleStates`, `-DisableDiskIdle`, `-SetMmcssGameProfile`, `-DisablePowerThrottling`, `-SetSystemResponsiveness`, `-DisablePagingExecutive`, `-DisableMouseAcceleration`, `-SetBestPerformance`, `-DisableInterruptModeration`.
- Registry + powercfg değerleri backup, restore point, transcript, `-Revert`.
## Script ne yapmaz?

- Oyun içi ayarlara dokunmaz.
- BIOS/CPU/RAM/GPU overclock yapmaz.
- NVIDIA Control Panel / Profile Inspector ayarlarını değiştirmez.
- Defender'ı kapatmaz; sadece seçilen klasörü tarama dışı bırakır.
- Windows Update/Spectre-Meltdown mitigasyonlarını kapatmaz.

---

## Önemli uyarılar

- **Yönetici yetkisi gerekir.** Registry, güç planı, NIC ve Defender değişiklikleri sistem genelidir.
- **Yedek alın.** Script otomatik yedek ve restore point oluşturur; yine de önemli verinizi ayrıca yedekleyin.
- **Tek değişiklik → ölçüm → karar.** Aynı anda onlarca tweak uygulamayın.
- **`NetworkThrottlingIndex` kapatılmamalı.** Bazı sistemlerde NDIS.sys DPC latency'sini artırır.
- **Z390'da ReBAR zorlanmamalı.**
- **Windows 10 22H2 destek dışı.** Bu proje performans odaklıdır; güvenlik yamaları ayrıca değerlendirilmelidir.
- **Üçüncü taraf “optimized” NVIDIA Inspector build'leri kullanılmamalı.**

---

## Ölçüm

- [CapFrameX](https://capframex.com) — avg / 1% low / 0.1% low, frametime.
- [LatencyMon](https://resplendence.com/latencymon) — DPC/ISR.
- [HWiNFO64](https://hwinfo.com) — WHEA, effective clock, sıcaklık.
- PresentMon — input-to-photon.

Ayrıntılı protokol: [`RAPOR.md`](RAPOR.md) → “Ölçüm protokolü”.

---

## Geri alma

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
```

`-Revert` yalnızca scriptin yaptığı değişiklikleri geri alır. BIOS, NVIDIA Control Panel ve elle yapılan registry değişiklikleri kapsam dışıdır.

---

## Sürüm

- **v1.13.0** — Repo **public** oldu; release asset'ları artık giriş yapmadan tarayıcıdan doğrudan indirilebiliyor (doğrulandı).
- **v1.12.1** — Private repo release indirme rehberi eklendi (`docs/INDIRME.md`); asset'lar girişsiz 404 veriyor, 4 alternatif yol belgelendi.
- **v1.12.0** — Tam proje denetimi: powercfg revert sırası, ASPM/USB yedekleme, OneClick `-Revert`, modül graceful fallback düzeltildi; 49 regresyon testi eklendi.
- **v1.11.0** — USB cihaz seviyesinde idle/suspend kapatma scripti eklendi; KatzRead paketi incelemesi (1 alındı, ~18 reddedildi) belgelendi.
- **v1.10.0** — "0 ve 1 tick kaldırma" (CPU affinity) efsanesi çürütüldü; 9900K'da uygulanmamalı.
- **v1.9.0** — `cs2.exe` için kalıcı işlem önceliği (IFEO `PerfOptions`), `-SetCs2Priority` bayrağı eklendi.
- **v1.8.0** — MMCSS `Scheduling Category=High` hatası düzeltildi (stutter üretiyordu), `MouseSensitivity=10` eklendi.
- **v1.7.0** — DPI/sens/polling matrisi hesaplayıcısı, RawAccel çarpan denetim aracı ve 8K Hz polling analizi eklendi.
- **v1.6.0** — 8K Hz mouse desteği: polling matrisi (ölçülecek), DPI saturation kuralı, `-PollingHz` ölçüm parametresi.
- **v1.5.0** — Hedef profil tanımı (`docs/HEDEF-PROFIL.md`) ve hedef denetim aracı (`Get-Cs2TargetCheck.ps1`) eklendi.
- **v1.4.0** — Ölçüm motoru (`Get-Cs2Benchmark.ps1`), GPU profili/power limit (`Get-Cs2GpuProfile.ps1`), ortak modül (`CS2Optimizer.psm1`), Pester testleri ve CI eklendi. Flow Control mantık hatası, powercfg alias hatası ve powercfg revert eksikliği düzeltildi.
- **v1.3.0** — Ağ tuning scripti (düşük latency + paket kaybı yok), input lag ölçüm zinciri ve performans/latency opsiyonları eklendi.
- **v1.2.0** — GameBoost-derived opsiyonel tweak'ler, WinUtil-derived düşük riskli tercihler ve background/telemetry cleanup scripti eklendi.
- **v1.1.0** — `Get-Cs2SystemReport.ps1` sistem envanteri/rapor üreticisi eklendi.
- **v1.0.0** — İlk sürüm: Windows baseline scriptleri, sistem özellikleri dosyası ve detaylı rapor.

Ayrıntı: [`CHANGELOG.md`](CHANGELOG.md)

---

## Geliştirme

```powershell
# Testler (31 birim + 49 regresyon)
Invoke-Pester ./tests

# Regresyon testleri tek tek
Invoke-Pester ./tests/Regression.Tests.ps1

# Sözdizimi denetimi
Get-ChildItem *.ps1 | ForEach-Object {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
    if ($e) { $e } else { "OK $($_.Name)" }
}
```

Her push'ta CI (sözdizimi + PSScriptAnalyzer + Pester + dry-run) çalışır: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

> ⚠️ **CI şu anda başlatılamıyor:** GitHub hesabı faturalama nedeniyle kilitli
> (`The job was not started because your account is locked due to a billing issue`).
> Bu kodla ilgili değil; hesap kilidi kalkınca CI kendiliğinden çalışacaktır.
> Teşhis ve elle doğrulama komutları: [`docs/CI-NOTU.md`](docs/CI-NOTU.md)

---

## Lisans

MIT — [`LICENSE`](LICENSE). Kullanmadan önce kendi risk değerlendirmenizi yapın; her ayar donanım ve sürüme göre farklı etki yapar.
