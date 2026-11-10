# Changelog

Tüm önemli değişiklikler bu dosyada belgelenir.
Format: [Semantic Versioning](https://semver.org/lang/tr/).

## [v1.6.0] — 2026-11-10

### Düzeltilen
- **Mouse polling rate artık sabit kural değil.** "1000 Hz kullan" ifadesi kaldırıldı;
  8K Hz destekleyen fareler için polling **ölçülecek** bir değişkendir.
- `docs/HEDEF-PROFIL.md` bölüm 5 yeniden yazıldı: 360 Hz monitörde polling matrisi
  (8000/4000/2000/1000/500 Hz), polling ≥ 2× refresh rate kuralı, DPI saturation
  kuralı (8K için ≥1600 DPI) ve 8K'ye özel sistem ayarları.
- `Get-Cs2Benchmark.ps1`: `-PollingHz` parametresi eklendi; rapora yazılır.
- `Get-Cs2TargetCheck.ps1`: polling ve DPI saturation kontrolleri eklendi.

### Eklenen
- `SISTEM-OZELLIKLERI.md`: mouse donanımı (8K Hz polling) kayda gecirildi.

## [v1.5.0] — 2026-11-10

### Eklenen
- `docs/HEDEF-PROFIL.md`: "CS2 Mükemmel Sistem" hedef profili.
  - 6 katman: BIOS → Windows → GPU → Input → Ağ → Arka plan
  - Kabul kriterleri: 357 FPS, 1% low ≥ 280, p99 ≤ 4.0 ms, 0 paket kaybı, jitter < 5 ms
  - Uygulama sırası ve bilerek "mükemmel" olmayanlar listesi
- `Get-Cs2TargetCheck.ps1`: hedef profile uzaklık denetimi (read-only).
  - 6 katman, 28 kontrol; OK/WARN/FAIL + gereken aksiyon
  - Markdown + JSON rapor

## [v1.4.0] — 2026-11-10

### Eklenen
- `Get-Cs2Benchmark.ps1`: tekrarlanabilir ölçüm motoru.
  - CapFrameX/PresentMon ile frame time + present latency toplama
  - HWiNFO sensör referansı, nvidia-smi GPU telemetri (clock/temp/power/throttle)
  - Ağ ölçümü: jitter, paket kaybı, DNS süresi, NIC discard/error sayaçları
  - Tek klasörde `summary.md` + `summary.json` çıktısı
- `Get-Cs2GpuProfile.ps1`: RTX 3070 power limit yönetimi (nvidia-smi) ve
  doğrulanmış NVIDIA Profile Inspector (.nip) profil üretimi.
- `CS2Optimizer.psm1`: ortak yardımcı modülü (registry, powercfg, NIC, backup).
- `tests/CS2Optimizer.Tests.ps1`: 27 Pester testi.
- `.github/workflows/ci.yml`: sözdizimi + PSScriptAnalyzer + Pester + dry-run CI.
- `LICENSE` (MIT) ve `CHANGELOG.md`.

### Düzeltilen
- **Flow Control artık kapatılmıyor.** Rx Flow Control kapatmak paket kaybını
  artırır; hedefimizin tam tersi. `-DisableFlowControl` ayrı, riskli bir bayrağa
  ayrıldı.
- Çok kelimeli powercfg alias'ları (`SUB_PROCESSOR PROCTHROTTLEMIN`) artık
  doğru parçalanıyor; önceki hâli tek argüman geçirdiği için çalışmıyordu.
- powercfg alt ayarları artık JSON yedekle birebir geri alınıyor (önceden sadece
  plan GUID'i geri alınıyordu, alt ayarlar kayboluyordu).
- `.nip` profilindeki iki hatalı SettingID düzeltildi (`Low Latency Mode`,
  `Threaded optimization`); ID'ler iki gerçek referans profille doğrulandı.

## [v1.3.0] — 2026-11-10

### Eklenen
- `CS2-Win10-Network-Tuning.ps1`: düşük latency + paket kaybı yok.
  - Link power saving off, Wake on LAN off, adapter power management off
  - RSS on, TCP autotuning normal
  - Interrupt Moderation / RSC opsiyonel A/B testi
  - NIC discard/error istatistikleri ve `netsh int tcp show global` raporu
- `RAPOR.md` bölüm 8 yeniden yazıldı: nelerin kapatılmaması gerektiği,
  ASUS RT-AX82U router tarafı (Adaptive QoE Gaming Mode + %95 limiter), reddedilenler.
- `RAPOR.md` bölüm 8A: input lag ölçüm zinciri ve sıralı müdahale planı.
- `CS2-Windows10-Optimize.ps1` yeni opsiyonel bayraklar:
  `-SetProcessorPerformance`, `-DisableIdleStates`, `-DisableDiskIdle`,
  `-SetMmcssGameProfile`, `-DisablePowerThrottling`, `-SetSystemResponsiveness`,
  `-DisablePagingExecutive`, `-DisableMouseAcceleration`, `-SetBestPerformance`,
  `-DisableInterruptModeration`, `-DisableFlowControl`.

## [v1.2.0] — 2026-11-10

### Eklenen
- `CS2-Win10-WinUtil-Preferences.ps1`: WinUtil incelemesinden seçilen düşük
  riskli tercihler (activity history, location tracking, consumer features,
  delivery optimization, device companion apps, Razer/Logitech auto-install,
  Teredo, IPv4 preference, reserved storage, Explorer folder discovery,
  end task right click).
- `CS2-Win10-Background-Telemetry-Cleanup.ps1`: DiagTrack/dmwappushservice,
  CEIP/uyumluluk görevleri, AllowTelemetry, background apps, opsiyonel UWP kaldırma.

## [v1.1.0] — 2026-11-10

### Eklenen
- `Get-Cs2SystemReport.ps1`: read-only sistem envanteri (Markdown + JSON).

## [v1.0.0] — 2026-11-10

### Eklenen
- `CS2-Windows10-Optimize.ps1`: ana baseline script (dry-run, yedek, revert).
- `CS2-Desktop-OneClick.ps1`: basit tek tık varyantı.
- `CS2-Optimize-Baslat.cmd`: yönetici başlatıcı.
- `RAPOR.md`, `SISTEM-OZELLIKLERI.md`, `README.md`.
