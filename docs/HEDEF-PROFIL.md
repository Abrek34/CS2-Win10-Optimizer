# CS2 Mükemmel Sistem — Hedef Profil

> **Hedef:** Elimizdeki donanımla (i9-9900K + Z390-A PRO + RTX 3070 + 64 GB DDR4-4000
> + 360 Hz + Ethernet) **CS2 için mümkün olan en akıcı ve en düşük latency'li sistemi**
> yakalamak.
>
> Bu dosya bir "tweak listesi" değil, bir **hedef tanımıdır.** Her katman için
> "hedefte mi, değil mi, ne yapmalı" sorusu cevaplanır.
> Denetim aracı: `Get-Cs2TargetCheck.ps1` (read-only).

---

## 0. Temel strateji: bu sistemde bottleneck nerede?

| Katman | Durum | Sonuç |
|---|---|---|
| **CPU** | 9900K 8C/16T @ 5.0 GHz fixed | CS2 tek ana thread'e dayanır → **CPU en önemli katman** |
| **GPU** | RTX 3070 8 GB | 1080p'de CS2 GPU-bound değil → GPU OC yerine **undervolt** (kararlı clock) |
| **RAM** | 2×32 GB DDR4-4000 CL18 | 2 DIMM = düşük IMC yükü → 4000 mümkün, **CL18 3600'dan iyi** |
| **Monitör** | 360 Hz | 2.78 ms/panel bütçe → **357 FPS hedef**, 1% low kritik |
| **Ağ** | Ethernet + RT-AX82U | Kablolu zaten; asıl mesele **jitter/bufferbloat** |

> **Sonuç:** Performans kazancı %80'lik kısımdan **BIOS (CPU/ring/RAM)** gelir.
> Windows tweak'leri ikincil; ağ ayarları ise "paket kaybı olmadan" hedefi için
> kritik ama **FPS artırmaz**.

---

## 1. Hedef mimari — 6 katman

```
BIOS (CPU/RAM/güç)  →  Windows (güç/scheduler)  →  GPU (sürücü/Reflex)
     →  Input (fare)  →  Ağ (jitter)  →  Arka plan (overlay/telemetri)
```

Sıralama önemli: **BIOS → Windows → GPU → Input → Ağ → Arka plan.**
Her katman ölçülmeden sonrakine geçilmez.

---

## 2. Katman 1 — BIOS (en yüksek getiri)

| Ayar | Hedef | Neden | Durum |
|---|---|---|---|
| **CPU Core Ratio** | **50 (5.0 GHz) Sync All Cores** | Zaten mevcut | ✅ |
| **Ring / Uncore** | **47 (4.7 GHz)** | L3 gecikmesini düşürür; 5.0/4.7 kanıtlanmış kombinasyon | ⬜ |
| **AVX Offset** | 0 veya -1 | AVX testlerinde kararlılık | ⬜ |
| **XMP** | **4000 CL18-22-22-42** | 2 DIMM ile IMC yükü düşük | ✅ |
| **VCCSA / VCCIO** | 1.20-1.25 V (4000 için) | Bellek gecikmesi | ⬜ |
| **C-States** | **Disabled** (C1E/C3/C6/C7/C8/C10) | Fixed 5.0 ile clock tutarlılığı | ⬜ |
| **Intel SpeedStep (EIST)** | **Disabled** | OS'in çarpan düşürmesini engeller | ⬜ |
| **Speed Shift (HWP)** | Enabled + **EPP 0** | Hızlı ramp; 9900K destekler | ⬜ |
| **Package C-State Limit** | C0 | Gecikme kaynağı | ⬜ |
| **Turbo Boost** | Enabled | | ⬜ |
| **Power Limits (PL1/PL2)** | Max (4095 W) | Power throttling yok | ⬜ |
| **CPU Current Limit** | Max (255 A) | | ⬜ |
| **Above 4G Decoding** | Enabled | 3070 geniş BAR erişimi | ⬜ |
| **Resizable BAR** | **Off/Auto** | Z390 resmî desteklemiyor, zorlama riskli | ⬜ |
| **PCIe ASPM** | Disabled | GPU/NVMe link power saving | ⬜ |
| **Spread Spectrum** | Disabled | BCLK 100 stabilitesi | ⬜ |
| **Thermal Throttle koruması** | **AÇIK** | Termal güvenlik — kapatma | ✅ |
| **BIOS sürümü** | 7B98v1F veya üstü | Güvenlik + Z390 uyumluluğu | ⬜ |
| **XHCI Hand-off** | Enabled | | ⬜ |
| **iGPU** | Kullanmıyorsan Disabled | Ek yükten kurtulma | ⬜ |

### Katman 1 hedef değerlendirmesi
**Ring 4.7 en önemli eksik.** 9900K'da core 5.0 + ring 4.7 kombinasyonu
L3 gecikmesini düşürür ve CS2'nin thread-sensitif yapısında doğrudan 1% low'a
yansır. Core OC'den sonra **ilk** denenmesi gereken ayar budur.

---

## 3. Katman 2 — Windows 10

| Ayar | Hedef | Komut / Araç |
|---|---|---|
| Güç planı | **High Performance** | `powercfg /setactive SCHEME_MIN` |
| CPU minimum state | **100%** | `powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100` |
| CPU maximum state | 100% | `... PROCTHROTTLEMAX 100` |
| Speed Shift EPP | **0** | `... SUB_PROCESSOR PERFEPP 0` |
| Core parking | **Off** | `... SUB_PROCESSOR CPMINCORES 100` |
| Disk idle timeout | **0** | `... SUB_DISK DISKIDLE 0` |
| PCIe ASPM | Off | `... SUB_PCIEXPRESS ASPM 0` |
| USB selective suspend | Off | `... 2a737441-... 48e6b7a6-... 0` |
| Game DVR / AppCapture | **Off** | `CS2-Windows10-Optimize.ps1 -Apply` |
| Game Bar paneli | Off | aynı |
| **Game Mode** | **On** | aynı |
| PowerThrottlingOff | **1** | `-DisablePowerThrottling` |
| SystemResponsiveness | **10** | `-SetSystemResponsiveness` |
| DisablePagingExecutive | 1 | `-DisablePagingExecutive` |
| MMCSS Games profili | GPU Priority 8 / Priority 6 / High | `-SetMmcssGameProfile` |
| Win32PrioritySeparation | 38 (0x26) | zaten default ile aynı → **no-op** |
| NetworkThrottlingIndex | **10 (varsayılan)** | **dokunma** |
| HAGS | **A/B test** (1 vs 2) | `-EnableHags` / `-DisableHags` |
| Görsel efektler | Best performance | `-SetBestPerformance` |
| Mouse acceleration | **Off** | `-DisableMouseAcceleration` |
| Pagefile | System managed | **kapatma** |
| Memory compression | Açık | **kapatma** |
| NVMe/SATA disk sleep | Off | yukarıda |

### Katman 2 hedef değerlendirmesi
Windows katmanı **zaten projede tam kapsamlı.** Burada yeni bir şey yok; önemli olan
**doğru sırayla ve ölçerek** uygulamak.

---

## 4. Katman 3 — GPU / NVIDIA (RTX 3070)

| Ayar | Hedef | Nerede |
|---|---|---|
| **Power management mode** | **Prefer maximum performance** | NVCP → `cs2.exe` profili |
| **Low Latency Mode** | **Off** (Reflex açıkken) | NVCP |
| **Vertical Sync** | Off (G-Sync+Reflex kullanılıyorsa driver'da On) | NVCP |
| **Maximum pre-rendered frames** | 1 | NVCP / Inspector |
| **Shader cache** | Unlimited / 10 GB | NVCP |
| **Texture filtering — Quality** | High performance | NVCP |
| **Anisotropic sample optimization** | On | NVCP |
| **Trilinear optimization** | On | NVCP |
| **Threaded optimization** | Auto / On | NVCP |
| **Preferred refresh rate** | Highest available | NVCP |
| **Frame Rate Limiter** | Off (cap tek yerde) | NVCP |
| **CS2 in-game Reflex** | **Enabled (+Boost ayrı test)** | Oyun içi |
| **GPU undervolt** | 0.900-0.950 V @ ~1900-1950 MHz | Afterburner / Inspector |
| **GPU power limit** | %105-110 | Afterburner / `Get-Cs2GpuProfile.ps1 -Apply` |
| **Temperature limit** | 83-90 °C | Afterburner |
| **Fan eğrisi** | Agresif (70 °C üstü %70+) | Afterburner |

### Katman 3 hedef değerlendirmesi
**En yüksek GPU getirisi overclock değil, undervolt.** Sabit boost clock → tutarlı
frametime → daha iyi 1% low. 8 GB VRAM 1080p'de sorun değil.
`Get-Cs2GpuProfile.ps1` doğrulanmış `.nip` profili üretir (yalnızca `cs2.exe`
kapsamında, base profile'e uygulanmaz).

> ⚠️ GeForce'ta `nvidia-smi -lgc` (clock locking) **çalışmaz**; power limit çalışır.
> Undervolt driver seviyesindedir (Inspector/Afterburner).

---

## 5. Katman 4 — Input (en yüksek "hissedilen" getiri)

| Ayar | Hedef | Not |
|---|---|---|
| **Mouse polling rate** | **1000 Hz** | 4000/8000 Hz CS2 CPU thread'ini yorabilir |
| **Enhance pointer precision** | **Off** | Windows mouse acceleration |
| **Pointer speed** | 6/11 | CS2 raw input bunu bypass eder ama hijyen |
| **DPI / eDPI** | Sabit (örn. 800) | Oyun içi, bu proje dokunmuyor |
| **Raw Input** | On | Oyun içi |

### Katman 4 hedef değerlendirmesi
Polling rate donanım ayarıdır, scriptle değiştirilemez — **elle kontrol edilmeli.**
2000 Hz bir deneme değeri; 4000/8000 Hz'de CS2'nin ana thread'inde stall görülür.

---

## 6. Katman 5 — Ağ ("paket kaybı olmadan")

| Ayar | Hedef | Neden |
|---|---|---|
| **Bağlantı** | Ethernet (kablolu) | Wi-Fi jitter + retransmission |
| **EEE / Green Ethernet** | **Off** | Link idle güç düşürme; kararlılık sorunu ilk izole adımı |
| **Power Saving Mode / Selective Suspend** | **Off** | Uyku sırasında link düşmesi |
| **Wake on Magic Packet / Pattern** | Off | İstenmeyen uyanma + DPC kaynağı |
| **Adapter power management** | **Off** | `Disable-NetAdapterPowerManagement` |
| **Rx/Tx Flow Control** | **Enabled** | **Kapatmak paket kaybını artırır** |
| **RSS** | **Enabled** | 8C/16T'da alıcı işlemeyi dağıtır |
| **Checksum / LSO / RSC** | **Enabled (varsayılan)** | Kapatmak CPU yükünü artırır |
| **Speed & Duplex** | **Auto** | Sabitlemek duplex mismatch |
| **Jumbo Frames** | **1500** | Uçtan uca hizalı değil → parçalanma/drop |
| **TCP autotuning** | normal | Abartılı TCP tweak yok |
| **Router: Adaptive QoE** | **ON, Gaming Mode** | Oyun trafiği önceliği (RT-AX82U) |
| **Router: Bandwidth Limiter** | **PC bant genişliğinin ~%95'i** | Bufferbloat'un en etkili tek çözümü |
| **Router: SQM/fq_codel** | Mümkün değil (stock FW) | En iyi latency çözümü; RT-AX82U desteklemiyor |
| **DNS** | Değiştirme gerekmez | CS2 ping'i etkilemez |

### Katman 5 hedef değerlendirmesi
Router tarafı Windows'tan daha büyük etki yapar. **Önce bufferbloat ölç**
(`waveform.com/bufferbloat`), sonra %95 limiter uygula.

---

## 7. Katman 6 — Arka plan / overlay / telemetri

| Ayar | Hedef | Neden |
|---|---|---|
| **Steam overlay** | **Off** | Microstutter kaynağı |
| **Discord overlay** | **Off** | Aynı |
| **NVIDIA overlay** | **Off** | Aynı |
| **RGB/anakart yazılımları** (iCUE, Armoury, Nahimic) | Kapalı | 1% low'un en yaygın suçluları |
| **Startup uygulamaları** | Minimal | Aynı |
| **Telemetri** | Minimum | Kaynak kullanımı; gizlilik |
| **HVCI / Memory Integrity** | A/B test | 5-10% FPS kazancı; **güvenlik trade-off** |
| **WSL/Hyper-V** kullanıyorsan | HVCI'ye dokunma | VBS gereksinimleri bozulur |

---

## 8. "Mükemmel" tanımı — kabul kriterleri

Sistem şu koşulları sağladığında **hedef yakalanmış** sayılır:

| # | Kriter | Ölçüm |
|---|---|---|
| 1 | **Ortalama FPS ≥ 357** | CapFrameX, 3 run, aynı map |
| 2 | **1% low ≥ 280** | CapFrameX |
| 3 | **Frametime p99 ≤ 4.0 ms** | CapFrameX |
| 4 | **Termal throttle yok** | HWiNFO `clocks_throttle_reasons` boş |
| 5 | **WHEA hatası yok** | HWiNFO log |
| 6 | **DPC/ISR max < 100 µs** | LatencyMon, 10 dk boşta + oyun |
| 7 | **Paket kaybı %0** | `Get-Cs2Benchmark.ps1` → ping + NIC sayaçları |
| 8 | **Jitter < 5 ms** | Aynı |
| 9 | **Bufferbloat notu A veya B** | waveform.com/bufferbloat |
| 10 | **Mouse polling 1000 Hz sabit** | Mouse Rate Checker |

> **1% low ≥ 280** 360 Hz'de pratik sınır: ortalama 357 iken 1% low 280'in
> üzerindeyse panik yapacak bir düşüş yok demektir.

---

## 9. Uygulama sırası (ölçümle)

```
0. Get-Cs2SystemReport.ps1            → envanter, eksik donanım bilgisi
1. Get-Cs2TargetCheck.ps1             → hedefe uzaklık raporu
2. Get-Cs2Benchmark.ps1 -Label base   → BASELINE (3 run)
3. BIOS: ring 4.7 + C-states off      → reboot, WHEA kontrol
4. Get-Cs2Benchmark.ps1 -Label ring47 → karşılaştır
5. Windows: -SetProcessorPerformance  → ölç
6. Windows: -DisableMpo (A/B)         → ölç
7. Network: CS2-Win10-Network-Tuning  → ölç + paket kaybı sayacı
8. GPU: Get-Cs2GpuProfile -Apply      → ölç
9. Router: Adaptive QoE Gaming + %95  → bufferbloat tekrar ölç
10. Kalan katmanlar tek tek            → her biri 3 run ölçüm
11. Fark yoksa GERİ AL
```

> Her adımda **yalnızca bir değişiklik.** İki değişiklik yapıp "iyileşti" demek,
> hangisinin işe yaradığını bilmeyi imkânsız kılar.

---

## 10. Bilinçli olarak "mükemmel" olmayan şeyler

| Karar | Neden |
|---|---|
| **Nagle / TCPNoDelay kapatma** | CS2 UDP; etkisiz, yanlış yönlü |
| **NetworkThrottlingIndex kapatma** | DPC latency artışı |
| **Jumbo Frame** | Uçtan uca hizalı değil → parçalanma |
| **Flow Control kapatma** | Paket kaybı artar |
| **Checksum/LSO/RSC kapatma** | CPU yükü artar |
| **SysMain/Search körlemesine kapatma** | NVMe'de ölçülebilir fark yok, arama bozulur |
| **HPET zorlama / useplatformclock** | Latency artar |
| **Pagefile kapatma** | Anti-cheat/uygulama sorunları |
| **Memory compression kapatma** | RAM baskısında zarar verir |
| **Z390'da ReBAR zorlama** | Boot/black screen riski |
| **Termal korumayı kapatma** | Güvenlik |
| **GPU clock locking (GeForce)** | Desteklenmiyor |
| **Windows 11'e geçiş (şimdilik)** | 9900K'da destek ve performans belirsiz |

---

## İlgili dosyalar

| Dosya | Rol |
|---|---|
| `Get-Cs2TargetCheck.ps1` | Hedefe uzaklığı ölçer (read-only) |
| `Get-Cs2Benchmark.ps1` | Ölçüm motoru (read-only) |
| `Get-Cs2SystemReport.ps1` | Donanım envanteri (read-only) |
| `CS2-Windows10-Optimize.ps1` | Katman 1-2 uygulaması |
| `CS2-Win10-Network-Tuning.ps1` | Katman 5 uygulaması |
| `Get-Cs2GpuProfile.ps1` | Katman 3 uygulaması |
| `CS2-Win10-Background-Telemetry-Cleanup.ps1` | Katman 6 uygulaması |
| `RAPOR.md` | Her ayarın gerekçesi |
| `SISTEM-OZELLIKLERI.md` | Donanım → karar eşleşmesi |
