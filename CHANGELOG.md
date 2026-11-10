# Changelog

Tüm önemli değişiklikler bu dosyada belgelenir.
Format: [Semantic Versioning](https://semver.org/lang/tr/).

## [v1.14.0] — 2026-11-10

### Düzeltilen (ölçüm sonucunu bozan gerçek hatalar)
Bu sürüm, proje **ilk kez gerçek Windows'ta çalıştırılmadan önce** yapılan
kod denetiminde bulunan hataları giderir. Hepsi ölçümü doğrudan bozuyordu.

1. **PresentMon CSV kolon uyumsuzluğu** — PresentMon 2.x varsayılan metriklerinde
   `FrameTime` kolonu **yoktur** (`MsBetweenPresents` vardır). Eski kod yalnızca
   `$r.FrameTime` okuduğu için bugün indirilen PresentMon ile **0 frame** parse
   ediliyor, ölçüm sessizce boş kalıyordu.
   → `Get-FrameTimeStats` ile sürüm-bağımsız kolon seçimi.
2. **Ondalık ayracı (Türkçe locale)** — `[double]::TryParse("2.780", [ref]$v)`
   CurrentCulture kullanır; tr-TR'de `2780` üretir (1000× hatalı).
   → Tüm ayrıştırmalar `InvariantCulture`.
3. **ping çıktısı yerelleştirmesi** — `time=14 ms` / `süre=14ms` ve
   `(0% loss)` / `(0% kayıp)` farkları. Eski regex'ler Türkçe Windows'ta
   **hiç eşleşmiyordu** → ağ ölçümü tamamen işlevsizdi.
   → `ConvertFrom-PingOutput` (dil bağımsız).
4. **Jitter tanımı** — `ortalama − en küçük` jitter değildir.
   → Ardışık RTT farklarının ortalaması + `StdDevMs`.
5. **powercfg etiketi yerelleştirmesi** — "Current AC Power Setting Index"
   Türkçe'de "Mevcut AC Güç Ayarı Dizinü". `Get-PowerCfgValue` buna bağlıydı →
   **tüm güç planı kontrolleri Türkçe Windows'ta sessizce boş** dönüyordu.
   → `ConvertFrom-PowerCfgText` (etikete güvenmez).
6. **NIC sayaçları** — mutlak değer yerine ölçüm aralığı **farkı** raporlanır.
7. **GPU state dosyası** — sabit ad, ikinci uygulama orijinal güç limitini
   eziyordu → geri alma bozuluyordu. Artık zaman damgalı ad + en yeni dosya.
8. **Sistem snapshot'ı** — tek bir `Get-CimInstance` hatası tüm snapshot'ı
   düşürüyordu. Artık her değer hata toleranslı.
9. **PresentMon 2.x argümanları** — `--terminate_after_timed`,
   `--no_console_stats` yalnızca 2.x'te var; sürüm tespiti ile koşullu.
10. **CapFrameX otomasyon iddiası** — dokümanda "otomatik başlatılır" yazıyordu
    ama kod yalnızca bilgi mesajı basıyordu. İddia kaldırıldı, yerine
    `-FrameCsv` ile CSV içe aktarma yolu geldi.

### Eklenen
- `Get-FrameTimeStats` (modül): sürüm-bağımsız frame time istatistiği —
  **1% low**, **0.1% low**, p99, p99.9, **input-to-photon**, display latency.
- `ConvertFrom-PingOutput` (modül): dil bağımsız ping ayrıştırma.
- `ConvertFrom-PowerCfgText` (modül): dil bağımsız powercfg AC değeri okuma.
- `Get-Cs2Benchmark.ps1 -FrameCsv`: CapFrameX / PresentMon CSV'si içe aktarma.
- `tests/Olcum.Tests.ps1`: **29 yeni test** (Türkçe/İngilizce yerelleşimler,
  PresentMon 1.x/2.x şemaları, locale sayı ayrıştırma, 1% low doğrulaması).
- `tests/Regression.Tests.ps1`: GPU state dosyası regresyon testleri (3) +
  **UTF-8 BOM regresyon testleri (17)**.

11. **UTF-8 BOM eksikliği** — Türkçe karakter içeren **13 script'te BOM yoktu**.
    Windows PowerShell 5.1, BOM'suz .ps1 dosyasını sistem ANSI kodlamasıyla
    (cp1254) okur → Türkçe metinler bozulur, bazı UTF-8 bayt dizileri tirnak
    gibi karakterlere denk gelip **sözdizimini** bozabilir.
    → Tüm `.ps1` / `.psm1` dosyalarına UTF-8 BOM eklendi, regresyon testiyle kilitlendi.

### Ölçülen / doğrulanan
- Test sayısı: **80 → 129** (hepsi geçiyor)
- PSScriptAnalyzer: **0 error** (CI eşiği), BOM uyarısı 0
- Modül export: **37 → 40** fonksiyon
- `Get-FrameTimeStats` doğrulaması (1800 karelik sentetik PresentMon 2.x CSV):
  avg 2.795 ms → **357.8 FPS**, 1% low **235 FPS**, 0.1% low 77.8 FPS,
  p99 2.78 ms, input-to-photon 17.98 ms — hesaplar elle doğrulandı.
- Türkçe ve İngilizce ping çıktıları **aynı sonucu** üretiyor.

### Değişen
- `Get-Cs2Benchmark.ps1` artık **input-to-photon** ve **1% low** raporluyor;
  kabul kriterleri raporun altında otomatik gösteriliyor.
- Rapor (RAPOR.md) yeni **8B** bölümü: ölçüm motorundaki düzeltmelerin
  tamamı, gerekçeleriyle belgelendi.

## [v1.13.0] — 2026-11-10

### Değişen
- **Repo artık PUBLIC.** `releases/download/...` URL'leri giriş yapmadan
  **HTTP 200** döndürüyor (private iken 404 döndürüyordu — GitHub davranışı).
- Güvenlik kontrolü yapıldı: commit yazarı GitHub noreply adresi; gizli anahtar,
  token, kişisel e-posta/telefon **yok**.
- `docs/INDIRME.md` ve README güncellendi: doğrudan tarayıcı indirmesi birincil
  yol olarak gösterildi.

### Doğrulama (anonim indirme)
- Tarayıcı indirmesi: HTTP 200, 136.520 bayt
- SHA256SUMS: `6c3f9cab…` birebir eşleşiyor
- ZIP bütünlüğü, modül import (37 fonksiyon), TargetCheck, AimMatrix: OK
- İndirilen pakette **80/80 Pester testi** geçti

### Bilinen engel (repo dışı)
GitHub **hesap kilidi** devam ediyor:
`The job was not started because your account is locked due to a billing issue.`
Bu hesap seviyesinde bir sorundur, repo visibility ile ilgisi yoktur.
CI çalışması için: https://github.com/settings/billing

## [v1.12.1] — 2026-11-10

### Eklenen
- `docs/INDIRME.md`: private repo release indirme rehberi.
  - Deponun private olması nedeniyle `releases/download/...` URL'leri **giriş
    yapmadan 404** döndürür. Bu bir hata değil, GitHub davranışı.
  - 4 alternatif indirme yolu: GitHub arayüzü, `gh release download`,
    `gh api` ile asset çekme, doğrudan clone.
  - SHA256 doğrulama komutları ve v1.12.0 için beklenen hash.

### Doğrulama (gerçek indirme testi)
Release asset'ı GitHub API'sinden indirildi ve test edildi:
  - ZIP bütünlüğü: OK (unzip -t, hata yok)
  - ZIP içeriği ↔ repo: 25/25 dosya byte-byte aynı
  - Modül import (temiz indirme): 37 fonksiyon, OK
  - Get-Cs2TargetCheck.ps1: Markdown + JSON üretti, OK
  - Get-Cs2AimMatrix.ps1: doğru DPI matrisi, OK
  - SHA256SUMS: eşleşiyor

## [v1.12.0] — 2026-11-10

### Düzeltilen (tam proje denetimi sonucu)
- **powercfg revert sıralaması hatası (kritik).** `-Revert` önce aktif güç planını
  geri yüklüyor, sonra alt ayarları `SCHEME_CURRENT` üzerine yazıyordu → alt
  ayarlar **yanlış plana** yazılıyordu. Sıra düzeltildi: alt ayarlar önce,
  plan sonra.
- **ASPM ve USB selective suspend yedeklenmiyordu.** Her çalıştırmada değiştiriliyor
  ama `powercfg-backup.json`'a alınmıyordu → `-Revert` bunları geri alamıyordu.
  Artık `Backup-PowerCfgValue` ile yedekleniyor.
- **`CS2-Desktop-OneClick.ps1` geri alma desteği yoktu.** Kullanıcı yalnızca elle
  `.reg` import etmek zorundaydı. Artık `-Revert` var (registry + powercfg + NIC +
  Defender).
- **Modül importu script'i çökertiyordu.** `Import-Module -ErrorAction Stop`
  kullanılıyordu; `.psm1` dosyası olmadan script çalışmıyordu. Artık `try/catch`
  ile graceful fallback var (minimum yardımcılar inline tanımlanır).
- **Ölü parametreler:** `Get-Cs2TargetCheck.ps1 -Cs2Path` hiç kullanılmıyordu →
  artık CS2 kurulum yolunu raporluyor. `CS2-Win10-UsbIdleDisable.ps1 -UsbHubOnly`
  uygulanmıyordu → artık gerçekten sadece hub'ları hedefliyor.

### Eklenen
- `tests/Regression.Tests.ps1`: 49 regresyon testi. Bulunan hataların tekrarını
  otomatik olarak engeller:
  - powercfg revert sırası (alt ayarlar plandan önce geri yüklenmeli)
  - ASPM/USB yedekleme mevcut olmalı
  - OneClick'ta `-Revert` ve tüm geri yükleme yolları
  - MMCSS `Scheduling Category` **High** asla kullanılmamalı (stutter riski)
  - Flow Control yalnızca explicit bayrakla kapatılmalı
  - RSC yalnızca explicit bayrakla kapatılmalı
  - Ölü parametre bulunmamalı
  - Her script modülü import etmeli **ve** graceful fallback içermeli

### Denetim
Tüm proje baştan sona statik denetlendi:
- Dry-run (Apply'siz) bloklarında sistem değiştiren komut: **0**
- Revert kapsamı: her script yedeklediği her şeyi geri alabiliyor
- Backup klasörü seçimi: tümünde "en yeni" (Descending) doğru
- Ölü parametre: 0 (2 tanesi bulundu, düzeltildi)

## [v1.11.0] — 2026-11-10

### Eklenen
- `CS2-Win10-UsbIdleDisable.ps1`: USB **cihaz seviyesinde** idle/suspend kapatma.
  - Windows'ta USB güç yönetimi iki katmanlıdır: OS (powercfg USB selective suspend —
    projede zaten var) ve cihaz (Device Parameters altındaki SelectiveSuspendOn,
    AllowIdleIrpInD3, IdleInWorkingState, EnhancedPowerManagementEnabled,
    DeviceSelectiveSuspended, SelectiveSuspendEnabled).
  - 8K Hz farede cihaz kendi güç yönetimine girerse polling raporları gecikir;
    360 Hz monitörde frame başına 40 rapor düşen durumda 1% low'a yansıyabilir.
  - Orijinal değerler JSON'a kaydedilir; `-Revert` ile birebir geri alınır.
  - Kaynak: KatzRead CS2 Optimizer paketi (`Disable USB Idle.bat`).

### Belgelenen
- `RAPOR.md` bölüm 19.6: KatzRead CS2 Optimizer paketi incelemesi —
  **alınan 1 madde** ve **reddedilen ~18 madde** gerekçeleriyle.
  - Reddedilenler arasında: NetworkThrottlingIndex=0xFFFFFFFF, Nagle, netsh heuristics/
    timestamps/rsc/ecn kapatma, nvlddmkm DisablePreemption, P0 kilidi, NvTelemetry64
    silme, event log temizleme, VRR sistem geneli kapatma.
- `docs/HEDEF-PROFIL.md` bölüm 5.8: USB iki katmanı ve yeni script.
- Hedef profil tablosuna USB cihaz idle satırı eklendi.

### Değerlendirme
Katz paketi ağırlıklı olarak popüler tweak listelerinin birleşimi. Bizim projede
çoğu madde zaten var ya da bilinçli olarak reddedildi. Tek gerçek katkı USB
device-level idle/suspend oldu.

## [v1.10.0] — 2026-11-10

### Belgelenen
- `RAPOR.md` bölüm 4.7: "0 ve 1 tick'i kaldır" (CPU affinity) efsanesi
  çürütüldü ve **uygulanmaması** gerektiği belgelendi.
  - Efsanenin kökeni **AMD Ryzen** (çift-CCD, 7950X/9950X): çapraz-CCD L3
    gecikmesi. 9900K **tek CCD + paylaşılan L3** → sorun yok.
  - 9900K'da CPU 0 ve CPU 1 = **iki ayrı fiziksel çekirdek** → kaldırmak
    2 çekirdek kaybettirir; CS2 çekirdek sınırlı bir oyundur.
  - Bitsum: affinity "band-aid" SMT kapatmanın **yerine geçmez**; Windows boş
    yarıyı hâlâ kullanır → thread contention.
  - Anti-cheat (VAC/FACEIT) affinity değişikliklerini engelleyebilir.
  - Doğru alternatifler zaten projede: `CPMINCORES 100`, BIOS C-states off,
    HT on/off A/B testi.
- Yapma listesine eklendi.
- `SISTEM-OZELLIKLERI.md` hedef tablosu güncellendi.

## [v1.9.0] — 2026-11-10

### Eklenen
- `-SetCs2Priority` parametresi: `cs2.exe`'ye **kalıcı işlem önceliği** verir.
  - Mekanizma: `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File
    Execution Options\cs2.exe\PerfOptions` → `CpuPriorityClass` (DWORD)
  - Değerler: `Normal` (2), `AboveNormal` (6), `High` (3)
  - Ayar her yeni `cs2.exe` sürecinde otomatik uygulanır (Task Manager'daki
    elle "High priority" kalıcı değildir)
  - `Realtime` (4) bilinçli olarak **sunulmuyor** (sistemi kilitleyebilir)
  - Yeni registry anahtarı backup/revert kapsamına alındı
- `Get-Cs2TargetCheck.ps1`: IFEO `CpuPriorityClass` kontrolü eklendi
  (Realtime → FAIL, High → WARN, AboveNormal/Normal → OK)

### Belgelenen
- `RAPOR.md` bölüm 4.6: CS2'ye kalıcı öncelik verme — mekanizma, değerler,
  riskler ve ölçüm protokolü.
- Yapma listesine eklendi: Steam `-high` launch option, `CpuPriorityClass=4`,
  kalıcı `CpuPriorityClass=3`.
- `docs/HEDEF-PROFIL.md` hedef tablosu güncellendi.

### Risk notu (Microsoft dokümanıyla doğrulandı)
Microsoft Learn "Scheduling Priorities": *"Use HIGH_PRIORITY_CLASS with care. If
a thread runs at the highest priority level for extended periods, other threads
in the system will not get processor time."* ve *"You should almost never use
REALTIME_PRIORITY_CLASS, because this interrupts system threads that manage
mouse input, keyboard input, and background disk flushing."*

Base priority tablosu: Normal=8, Above Normal=11, **High=13**, Realtime=15.
Windows kuralı: yüksek öncelikli thread hazır olduğunda düşük öncelikli thread
time slice'ını **bitirmeden** preempt eder.

Sonuç: `High` (3) sistemin ses (DPC), mouse input ve disk flush thread'lerini
preempt eder → **audio crackle + stutter** (kaldırılmak istenen şeyin tam tersi).
Steam launch option `-high` da aynı sorunu yapar. Kalıcı öncelik isteniyorsa
**IFEO** kullanılmalı ve önce `AboveNormal` ile ölçülmelidir.

## [v1.8.0] — 2026-11-10

### Düzeltilen (önemli)
- **MMCSS `Scheduling Category=High` artık uygulanmıyor.** High kategorisi oyun
  thread'lerini Pro Audio bandına (23-26) sokup sistem thread'lerini starve ederek
  **stutter üretir** — kaldırılmaya çalışılan şeyin tam tersi. Artık `Medium`
  kullanılıyor (Microsoft varsayılanı). `Priority=6` yalnızca Medium'da anlamlı.
  Kaynak: Microsoft MMCSS dokümanı + JINSHI MMCSS Games Task referansı.
- **`MouseSensitivity=10` eklendi.** Tek 1:1 değerdir; 10 dışındaki her değer
  count'ları ölçekler (skip/duplicate). Daha önce ayarlanmıyordu.
- `SmoothMouseXCurve`/`SmoothMouseYCurve` **dokunulmuyor**: `MouseSpeed=0` iken
  Windows bunları zaten okumaz. Silmek veya `00` yapmak gereksiz.

### Eklenen
- `Get-Cs2TargetCheck.ps1`: MouseSensitivity ve SmoothMouseX/Y kontrolü,
  MMCSS Scheduling Category (High ise FAIL) ve GPU Priority (inert, INFO).

### Belgelenen
- RAPOR.md: MMCSS ve Mouse satırları kaynaklara göre düzeltildi.
- Yapma listesine eklendi: MMCSS High, SmoothMouse silme/00, MouseSensitivity≠10.
- docs/HEDEF-PROFIL.md bölüm 5 güncellendi.

## [v1.7.0] — 2026-11-10

### Eklenen
- `Get-Cs2AimMatrix.ps1`: DPI / CS2 sens / polling matrisi hesaplayıcı (read-only).
  - eDPI sabit tutularak DPI kademeleri (cm/360 değişmez)
  - Her DPI'nin hangi polling rate'i doyurduğu (gereken minimum fare hızı)
  - Polling × FPS etkileşimi (frame başına rapor sayısı)
  - "Polling ≥ 2× monitör Hz" kuralı denetimi
- `Get-Cs2RawAccelCheck.ps1`: RawAccel kurulum denetimi (read-only).
  - Sürücü/servis durumu, settings.json çarpanları
  - CS2'de **gerçekte oynanan** sens ve cm/360 hesabı
  - Output smoothing / angle snap uyarıları
- `docs/HEDEF-PROFIL.md` bölüm 5 yeniden yazıldı:
  - Polling matrisi (CPU yükü ve Tier-1 pro kullanım oranlarıyla)
  - "FPS 200'lere düşüyor" gözleminin polling ile ilişkisi (geri besleme döngüsü)
  - DPI önerisi tablosu (8000 Hz için ≥1600 DPI, eDPI korunarak)
  - 8K ile ilgili sistem ayarları ve 5 turlu test protokolü
  - RawAccel analizi: **kaynak koddan doğrulandı** — "accel off" tamamen
    kimlik işlemi değildir; sens multiplier, DPI normalization, output smoothing
    ve carry katmanları veriyi değiştirir.

### Düzeltilen
- Daha önce "RawAccel accel off CS2 için ölçülebilir fark yaratmaz" yönündeki
  değerlendirme düzeltildi: RawAccel `MOUSE_INPUT_DATA`'yı gerçekten değiştirir
  (`driver.cpp` → `it->LastX = out_x`), CS2 raw input kullansa bile fark yaratabilir.

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
