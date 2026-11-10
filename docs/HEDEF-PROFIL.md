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
| **CS2 kalıcı işlem önceliği** (IFEO `PerfOptions`) | **AboveNormal (6)** veya hiç ayarlama | `High` (3) ses crackle/stutter riski; `Realtime` (4) asla. Steam `-high` launch option yapma |
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
| **Mouse polling rate** | **ÖLÇÜLECEK — 8000 Hz destekli fare** | Bkz. aşağıdaki polling matrisi; sabit değer yok, ölçümle karar verilir |
| **Mouse DPI** | **Polling'i doyurmak yeterli** (8000 Hz için ≥1600 DPI) | Düşük DPI + yüksek polling = sensör stutter |
| **Enhance pointer precision** | **Off** (isteğe bağlı) | CS2'de **etkisiz** (raw input) — masaüstü tutarlılığı için |
| **MouseSensitivity** | **10** | Tek 1:1 değer; 10 dışındaki her değer count'ları ölçekler |
| **SmoothMouseXCurve/YCurve** | **Dokunma** | `MouseSpeed=0` iken Windows bunları zaten okumaz; silmek/`00` yapmak gereksiz |
| **Pointer speed** | 6/11 | CS2'de etkisiz; masaüstü tutarlılığı için |
| **Fare yazılımı: acceleration / angle snapping / smoothing** | **Hepsi KAPALI** | **Asıl etkili olan budur** — cihaz içinde uygulanır, raw input onu bypass edemez |
| **RawAccel "accel off"** | **CS2 için gerekli DEĞİL** | CS2 zaten raw input kullanıyor; ölçülebilir fark yok (bkz. 5.7) |
| **eDPI** | Sabit (örn. 800) | Polling/DPI değişirse **oyun içi sens** aynı kalacak şekilde ayarlanır |
| **Raw Input** | On | Oyun içi |

### 5.1 Polling matrisi (8K Hz fare için)

Bu, "1000 Hz kullan" gibi sabit bir kural **değildir.** Doğru yaklaşım: **ölç ve seç.**

| Polling | 360 Hz monitörde | CPU yükü | Tier-1 pro kullanımı | Karar |
|---|---|---|---|---|
| 8000 Hz | Frame başına 22-40 rapor | **%8-15** | **< %2** | **Sizin durumunuzda riskli** |
| 4000 Hz | 11-20 rapor/frame | %4-8 | ~%6 | Yalnızca çok güçlü CPU ile |
| 2000 Hz | 5.5-10 rapor/frame | %1-2 | ~%8-12 | **En iyi denge** |
| 1000 Hz | 2.8-5 rapor/frame | < %1 | **~%92** | CS2 pro standardı, en stabil |
| 500 Hz | 1.4-2.5 rapor/frame | Çok düşük | — | 360 Hz için **yetersiz** (veri boşluğu) |

> Kaynak: ProsBind (Haziran 2026), CS2Sensitivity, mousetesting.com, gear-rank.com.
> 8000 Hz **%8-15 CPU yükü** ekler ve **1% low düşüşü** üretir; "Diminishing Returns —
> 0.875 ms kazanç, DPC latency stutter'a açık."

**İki kural (kaynak: cs2sensitivity.com):**

1. **Polling ≥ 2× monitör refresh rate.** 360 Hz için alt sınır ~720 Hz; pratik standart
   **1000 Hz** (2.8 rapor/frame).
2. **DPI saturation:** 8000 Hz fareyi doyurmak için **≥1600 DPI** gerekir. Düşük DPI'da
   yüksek polling çalıştırırsanız **sensör stutter** olur — polling yüksek olduğu için
   değil, **yetersiz veri üretimi** yüzünden. DPI'yı artırıp oyun içi sens'i eDPI'yi
   koruyacak şekilde düşürürsünüz.

### 5.2 Sizin durumunuz: "FPS 200'lere düşüyor" — çok önemli bir sinyal

Bu gözlem, polling rate'in **FPS kaybının kaynağı olabileceğini** gösteriyor.

```
360 Hz monitör, hedef 357 FPS
  357 FPS -> frame 2.80 ms -> 8000 Hz'de frame başına 22 rapor
  250 FPS -> frame 4.00 ms -> 8000 Hz'de frame başına 32 rapor
  200 FPS -> frame 5.00 ms -> 8000 Hz'de frame başına 40 rapor   <-- sizin durumunuz
```

**Mekanizma:** CS2 (Source 2) tek ana thread'e dayanır. Her mouse raporu bir USB
interrupt'tir. 8000 Hz = saniyede 8000 kesme. FPS düştüğünde (200'e) frame penceresi
5 ms'ye çıkar ve o pencereye **40 rapor** düşer — CPU'nun zaten en yoğun olduğu anda
işlenmesi gereken interrupt sayısı artar. Bu **kötü bir geri besleme döngüsüdür:**

```
FPS düşer → frame uzar → frame'e düşen rapor artar → CPU daha da meşgul → FPS daha düşer
```

**Hipotez (test edilmeli):** 8000 Hz polling, sizin 1% low düşüşünüzün (200'ler)
**birincil sorumlusu olabilir.** 9900K 5.0 GHz güçlü bir CPU'dur, ama 8K polling
için gereken tek çekirdekli interrupt işleme kapasitesi her sistemde yetmez.

### 5.3 DPI önerisi (sizin 8K fareniz için)

Hedef: **fiziksel hareketi değiştirmeden** polling'i doyurmak.

| DPI | CS2 sens | cm/360 | 8000 Hz'i doyurmak için gereken hız | Değerlendirme |
|---:|---:|---:|---:|---|
| 400 | 2.000 | 52.0 | 508 mm/s | ❌ 8K için yetersiz (sadece çok hızlı flicks) |
| 800 | 1.000 | 52.0 | 254 mm/s | ⚠️ 8K için sınırda; 4K için ideal |
| **1600** | **0.500** | **52.0** | **127 mm/s** | ✅ **8K için önerilen asgari** |
| 3200 | 0.250 | 52.0 | 64 mm/s | ✅ 8K rahat; en düşük sürtünme |
| 6400 | 0.125 | 52.0 | 32 mm/s | ⚠️ Çok yüksek; çoğu fare 6400 desteklemez |

> **Not:** CS2'de `m_yaw = 0.022` derece/count. Yukarıdaki cm/360 değerleri
> **eDPI = 800** (DPI × CS2 sens) sabit tutularak hesaplandı — yani fiziksel
> hareket **hiç değişmiyor**, sadece sayılar değişiyor.
>
> Örnek: 400 DPI @ 2.0 → 1600 DPI @ 0.5 geçerseniz, fare elinizde **aynı hızda
> aynı mesafeyi** kat eder, ama 8000 Hz'i doyurmak için 4 kat daha fazla veri
> üretir.

**Neden DPI yükseltmek "hissetmeyi" değiştirmez:**
DPI ve sens ters orantılı değiştirildiğinde eDPI sabit kalır → cm/360 sabit kalır →
fiziksel hareket ve nişan hızı **aynıdır**. Tek fark: yüksek DPI'da mouse
**daha hassas** hareket eder, yani mikro düzeltmeler daha ince ayarlanabilir ve
polling doygunluğu sağlanır.

### 5.4 Önerilen test protokolü (sizin için)

`Get-Cs2Benchmark.ps1` ile **aynı map, aynı saat, 3'er run:**

```
1) 8000 Hz + mevcut DPI  → -Label poll8000
2) 8000 Hz + 1600 DPI    → -Label poll8000-dpi1600
3) 4000 Hz + 1600 DPI    → -Label poll4000-dpi1600
4) 2000 Hz + 1600 DPI    → -Label poll2000-dpi1600
5) 1000 Hz + 800/1600 DPI→ -Label poll1000
```

**Karşılaştırma metriği:**
- **1% low FPS** (ortalama FPS değil) — sizin 200'e düşen değeriniz burada
- **Frametime p99**
- **Mouse input latency** (hareket → ekran tepkisi; kaydedilmiş video veya
  mouse latency test aracı ile)

**Karar kuralı:**
- 8000 Hz'de 1% low **200'lerde** kalıyorsa → **polling'i düşür** (2000 Hz).
- 2000 Hz'de 1% low belirgin artıyorsa → **1000 Hz** (pro standardı).
- 1000 Hz'de 1% low yine 200'lerdeyse → sorun polling **değil**; CPU/ring/termal
  tarafına dön (Katman 1).

### 5.5 8K ile ilgili sistem ayarları (denenecekler)

8K polling stutter yaşarsanız, **ölçümle birlikte** şunları dene:

| Ayar | Neden |
|---|---|
| **C-states off (BIOS)** | Kesme işleme gecikmesini (interrupt latency) düşürür |
| **USB selective suspend off** | USB portu uykuya girip interrupt gecikmesi yaratır |
| **Interrupt Moderation A/B** | DPC yükünü değiştirir (projede zaten opsiyonel) |
| **Core parking off** | Boştaki core'ler uyanma gecikmesi üretir |
| **Mouse yazılımında "USB polling" ayarı** | 8K farelerde "report rate" ve "sensor smoothing" ayrı ayrıdır; smoothing'i kapatmak polling'i bozmadan stabiliteyi artırır |
| **USB portu: doğrudan anakart (arkada çıkışlı)** | Hub/ön panel portları interrupt gecikmesi ekler |
| **Fare kablosu: USB 2.0 değil, USB 3.x** | Yüksek report rate için bant genişliği (fare destekliyorsa) |

### 5.6 RawAccel analizi — "accel off" CS2'de gerçekten işe yarıyor mu?

> **Kısa cevap:** RawAccel ** placebo değil** — gerçek bir kernel-mode sürücüdür
> ve mouse input'unu gerçekten değiştirir. Ama **CS2 özelinde "accel off"
> modunun ölçülebilir bir faydası yoktur.** Hissettiğiniz fark büyük ihtimalle
> **beklenti/placebo** veya **fare firmware'i** kaynaklıdır.

#### Neden?

**1) CS2 zaten raw input kullanıyor — kalıcı olarak.**
Source 2'de `m_rawinput` **1'e sabitlendi** ve kapatılamaz. Yani oyun, fare
ayarlarının işlediği işlenmiş imleç konumunu değil, **cihazın gönderdiği ham
(count) verisini** okur.

> "Because the game takes movement from the device rather than the OS cursor,
> Windows **Enhance pointer precision** does not shape your aim in CS2."
> — CSDB.gg, "Does CS2 Have Raw Input?" (Temmuz 2026)

Bu, bizim projedeki `-DisableMouseAcceleration` ayarının neden CS2 için aslında
**gerekli olmadığını** da açıklar: raw input, Windows pointer acceleration'ını
zaten yolda çıkarıyor.

**2) RawAccel "accel off" modunda ne yapar? (kaynak koddan doğrulandı)**

RawAccel, mouse sürücü zincirine yerleşen bir **kernel-mode filtre
sürücüsüdür** (MIT lisanslı, imzalı, anti-cheat dostu tasarlanmış). Sürücü
kaynak kodundaki kritik satır (`driver.cpp`, `RawaccelCallback`):

```c
devExt->mod.modify(input, devExt->speed_processor, devExt->mod_settings,
                   devExt->input_dpi_normalization_factor, time);
...
it->LastX = out_x;   // <-- MOUSE_INPUT_DATA DEĞİŞTİRİLİR
it->LastY = out_y;
```

**Düzeltme:** "Accel off" **tamamen kimlik işlemi (identity) DEĞİLDİR.**
`accel_noaccel` sınıfı yalnızca *hızlanma eğrisinde* 1.0 döndürür; **ama**
sürücü hâlâ şunları uygular:

| Katman | Ne yapar | "Accel off"ta etkisi |
|---|---|---|
| **Sens multiplier** | Çıktıyı çarpanla ölçekler | **1.0 değilse his değişir** |
| **DPI normalization** | `dpi_factor = 1000 / cihaz_DPI` | **Etkinse çıktı ölçeklenir** |
| **Output DPI adjustment** | `output_dpi / 1000` çarpanı | **Etkinse çıktı ölçeklenir** |
| **Output smoothing (EMA)** | Paketleri yumuşatır | **Etkinse gecikme + his değişimi** |
| **Carry (ondalık biriktirme)** | Kırılan sayımı biriktirir | Küçük ama gerçek fark |
| **Speed clamp** | Hızı sınırlar | Etkinse flicks kısalır |

Yani tarif ettiğiniz "dağlar kadar fark" **tam olarak bu katmanlardan birinden**
geliyor. En güçlü aday: **DPI normalization** veya **sens multiplier'ın 1.0
olmaması.** Bu durumda RawAccel sadece accel'i kapatmaz, **nişan hızınızı da
değiştirir** — siz bunu "hissedilen doğrudan sensör okuma" olarak yorumlarsınız.

> **Kritik uyarı:** RawAccel + CS2 kombinasyonunda CS2'nin oyun içi sens'i
> **RawAccel'in çarpanı ile birlikte** uygulanır. 400 DPI @ 2.0 oynarken
> RawAccel'de sens multiplier 1.25 ise, gerçekte **400 DPI @ 2.5** oynuyorsunuz
> demektir. Bu, ölçüm yaparken tüm karşılaştırmaları geçersiz kılar.

**Sonuç:** Hissettiğiniz fark **gerçek** (RawAccel placebo değil, veriyi
gerçekten değiştiriyor) — ama muhtemelen beklediğiniz şey değil: muhtemelen
**nişan hızınız değişmiş** ya da RawAccel **girdiye gecikme/yumuşatma
ekliyordur** ve siz "daha temiz" algıladınız.

**3) Gerçekten etkili olan acceleration fare içindedir.**
Raw input, **cihazın kendi içinde** uygulanan acceleration'ı bypass edemez.
Fare yazılınızda/onboard memory'de "acceleration", "angle snapping" veya
"smoothing" varsa, o veri **oyuna ulaşmadan önce** değişmiş olur ve CS2 bunu
düzeltemez.

> "It does not remove acceleration configured on the mouse itself through its
> firmware or vendor software, because that is applied before the data ever
> reaches the game."
> — CSDB.gg

**Bu, sizin durumunuz için en olası açıklamadır:** 8K farenizde firmware
tarafında bir acceleration/smoothing profili açıksa, RawAccel "accel off" ile
**o katmanı** etkisizleştiriyor olabilir → gerçek fark. Bu durumda doğru çözüm
**fare yazılımından kapatmak**, kernel sürücüsü yüklemek değil.

#### Sizin durumunuz için pratik öneri

| Adım | Ne yapılacak | Neden |
|---|---|---|
| 1 | **Fare yazılımını kontrol et** | Acceleration / angle snapping / smoothing / motion sync ayarlarını kapat |
| 2 | **Fare onboard memory'sini sıfırla** | Cihazın kendi profili CS2'yi etkiler |
| 3 | **Windows EPP'yi kapat** (projede zaten var) | CS2'de etkisiz ama masaüstü tutarlılığı + RawAccel'in etkisizleştirdiği OS katmanı |
| 4 | **RawAccel'i ölçerek karar ver** | Ya da kaldır ya da bırak — CS2 için ölçülebilir fark beklenmez |
| 5 | **VAC riski değerlendir** | Kernel sürücüsü; imzalı ve anti-cheat dostu tasarlanmış ama garanti verilemez |

#### Ölçüm protokolü

```
1) RawAccel AÇIK, fare yazılımı acceleration AÇIK   → -Label rawaccel-on-accel-on
2) RawAccel AÇIK, fare yazılımı acceleration KAPALI  → -Label rawaccel-on-accel-off
3) RawAccel KAPALI (uninstall), fare yazılımı KAPALI → -Label rawaccel-off
```

**Karar metriği:** CapFrameX 1% low + p99 **ve** mouse latency testi
(mouse hareketi → ekran tepkisi süresi).

**Beklenti:**
- (1) vs (2) farkı büyükse → sorun **fare yazılımı** (RawAccel değil).
- (2) vs (3) farkı yoksa → RawAccel CS2'de **etkisiz**, kaldırmak güvenlik
  profili için mantıklı (kernel sürücüsü gereksiz yük).
- (3) vs (4) farkı varsa → RawAccel gerçekten işe yarıyor, ama bu durumda
  CS2'nin raw input davranışı beklenmeyen bir yönde değişmiş demektir;
  dikkatli olun.

> **Önemli:** RawAccel kendi **kendi ayarlarında "sens multiplier"** ve
> **DPI normalization** seçenekleri vardır. Bunlar CS2'nin oyun içi sens'ini
> **değiştirir** (fiziksel hareket değişir!). Profilinizde sens multiplier
> 1.0'den farklıysa, RawAccel aslında "accel off" olsa bile **nişan hızınızı
> değiştiriyor** demektir. Bu, ölçtüğünüz farkın gerçek açıklaması olabilir.

### 5.7 Katman 4 hedef değerlendirmesi

1000 Hz **pro standardıdır ve CS2 için en güvenli değerdir** — ama sizin fareniz 8K
olduğu için bu "herkese tek kural" değildir. Doğru cevap: **ölç, sonra karar ver.**
Ölçüm aracı hazır; eksik olan tek şey polling'i değiştirip 4-5 tur ölçüm yapmanız.

**Sizin durumunuz için en olası sonuç:** FPS'in 200'lere düşmesi 8K polling'den
kaynaklanıyorsa, **2000 Hz + 1600 DPI** (aynı fiziksel hareket) sizin için hem
input latency'yi iyi tutar hem 1% low'ları toparlar. Ama bu bir **tahmin** —
ölçümle doğrulanmalı.

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
| 10 | **Mouse polling 1000 Hz'de 1% low ≥ 280** (8K/4K/2K denendi) | Mouse Rate Checker + CapFrameX |

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
| `Get-Cs2AimMatrix.ps1` | DPI/sens/polling matrisi hesaplar (read-only) |
| `Get-Cs2RawAccelCheck.ps1` | RawAccel çarpanlarını ve gerçek etkin sens'i denetler (read-only) |
| `Get-Cs2TargetCheck.ps1` | Hedefe uzaklığı ölçer (read-only) |
| `Get-Cs2Benchmark.ps1` | Ölçüm motoru (read-only) |
| `Get-Cs2SystemReport.ps1` | Donanım envanteri (read-only) |
| `CS2-Windows10-Optimize.ps1` | Katman 1-2 uygulaması |
| `CS2-Win10-Network-Tuning.ps1` | Katman 5 uygulaması |
| `Get-Cs2GpuProfile.ps1` | Katman 3 uygulaması |
| `CS2-Win10-Background-Telemetry-Cleanup.ps1` | Katman 6 uygulaması |
| `RAPOR.md` | Her ayarın gerekçesi |
| `SISTEM-OZELLIKLERI.md` | Donanım → karar eşleşmesi |
