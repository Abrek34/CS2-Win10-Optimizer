# CS2 / Windows 10 / NVIDIA Optimizasyon Raporu

> **Sürüm:** v1.8.0 — 10 Kasım 2026  
> **Durum:** Çalışma dosyası. Uygulananlar, planlananlar ve ölçüm sonuçları bu dosyada takip edilecek.  
> **Kapsam:** Windows 10 işletim sistemi, NVIDIA sürücü/Inspector katmanı, BIOS/firmware ve ölçüm metodolojisi.  
> **Kapsam dışı:** CS2 oyun içi video/Crosshair/autoexec ayarları.

---

## 0. Özet

> 🎯 **Hedef:** Elimizdeki donanımla (i9-9900K + Z390-A PRO + RTX 3070 + 64 GB
> DDR4-4000 + 360 Hz) **CS2 için mümkün olan en akıcı sistemi** yakalamak.
> Tam hedef tanımı ve kabul kriterleri: [`docs/HEDEF-PROFIL.md`](docs/HEDEF-PROFIL.md)
> Hedefe uzaklığı ölçen araç: `Get-Cs2TargetCheck.ps1` (read-only).

- Amaç: ortalama FPS'ten çok **1% low / 0.1% low, frametime kararlılığı ve input latency** iyileştirmesi.
- Temel ilke: **tek değişiklik → ölçüm → karar**. Aynı anda 10 tweak uygulanmayacak.
- Bu sistemde en yüksek getirisi olan katmanlar sırasıyla:
  1. RAM/CPU/ring stabilitesi (BIOS),
  2. Windows güç ve arka plan yükü,
  3. NVIDIA sürücü profili,
  4. IRQ/MSI/timer gibi ölçüm gerektiren ileri ayarlar.
- **Önemli düzeltme:** `Win32PrioritySeparation=38` (0x26) "kısa sabit quantum" değildir. Doğrusu **short + variable + 3:1 foreground boost**'tur ve Windows 10 client'ta varsayılan `2` değeri zaten buna çözümlenir. Yani 38 genellikle **no-op**'tur; tek başına FPS artışı beklenmemeli. Yine de açıkça sabitlemek için tutulabilir.
- **Önemli uyarı:** `NetworkThrottlingIndex` kapatılmamalı. Kapatmak bazı sistemlerde NDIS.sys DPC latency'sini artırıyor.
- **Önemli uyarı:** Z390'da resmî Resizable BAR yok; RTX 3070 için Inspector'dan rBAR zorlanmamalı.

---

## 1. Sistem ve mevcut durum

| Bileşen | Değer / Not |
|---|---|
| CPU | Intel Core i9-9900K, 8C/16T, 5.0 GHz fixed |
| Anakart | **MSI Z390-A PRO** (Z390, LGA1151, PCIe 3.0, resmî ReBAR yok) |
| GPU | **NVIDIA RTX 3070 8 GB GDDR6** (AIB/FE modeli bilinmiyor; NVIDIA son sürüm sürücü kurulu) |
| RAM | **64 GB (2×32 GB) DDR4-4000 CL18-22-22-42** (dual-rank bilinmiyor) |
| Depolama | **240 GB SATA SSD** |
| Soğutma | **240 mm sıvı (AIO)** |
| OS | Windows 10 22H2 (destek dışı; tüketici ESU penceresi Ekim 2026'da kapandı) |
| Monitör | **360 Hz** (çözünürlük henüz bilinmiyor; 360 Hz panel genellikle 1080p olur, doğrula) |
| Ağ | **Ethernet (kablolu), router: ASUS RT-AX82U** |
| CS2 yolu | Script otomatik buluyor; gerekirse `-Cs2Path` ile verilecek |

### 1.1 Sistem envanter raporu (Get-Cs2SystemReport.ps1)

`Get-Cs2SystemReport.ps1`, sistemin mevcut durumunu okur ve Masaüstü'ne `CS2-SystemReport-<zaman damgası>.md` ve `.json` dosyaları yazar. Hiçbir ayarı değiştirmez (read-only, yönetici gerekmez; bazı alanlar yetki yoksa `N/A` çıkarır).

**Topladıkları:**
- İşletim sistemi (sürüm, build, mimari, son önyükleme)
- CPU (model, çekirdek/thread, saat), RAM (toplam, modül sayısı, slot/üretici/part no/hız/yapılandırılmış hız)
- Anakart/BIOS sürümü, GPU/VRAM (nvidia-smi öncelikli, yoksa WMI), monitör (çözünürlük/Hz)
- Depolama (disk, tip, bus, boyut, sağlık), NIC (adapter, link hızı, MAC, IPv4, gateway, DNS, gelişmiş NIC özellikleri)
- Güç planı, HAGS, GameDVR, AppCapture, Auto Game Mode, Win32PrioritySeparation, SystemResponsiveness, NetworkThrottlingIndex, PowerThrottlingOff, DisablePagingExecutive, Fast Startup, HVCI, bekleyen reboot
- Defender exclusion'ları (path/process)
- CS2 kurulum yolu ve cs2.exe sürümü

**Kullanım:** `RAPOR.md`'deki “Doldurulacak / bilinmiyor" yerlerini (monitör Hz, RAM düzeni, NVIDIA sürücü sürümü, ağ modeli) bu raporla doldurabilirsin. `SISTEM-OZELLIKLERI.md`'deki varsayımlarla karşılaştır.

### Mevcut çalışma dosyaları

| Dosya | Ne yapar | Not |
|---|---|---|
| `CS2-Windows10-Optimize.ps1` | Ana, parametreli script. Dry-run, yedek, restore point, `-Revert`. | Raporun “Windows” bölümünün büyük kısmını uygular. |
| `CS2-Desktop-OneClick.ps1` | Aynı değişikliklerin daha basit, tek tık varyantı. | Ana script varken ikinci kez çalıştırmaya gerek yok. |
| `CS2-Optimize-Baslat.cmd` | PowerShell başlatıcı. | Yönetici olarak çalıştırılmalı. |
| `Get-Cs2SystemReport.ps1` | Sistemi envanterler ve Masaüstü'ne Markdown + JSON raporu yazar. | Okunur (read-only); “bilinmiyor” yerlerini doldurmak için kullan. |
| `CS2-Win10-WinUtil-Preferences.ps1` | WinUtil incelemesinden seçilen düşük riskli tercihleri uygular. | Dry-run varsayılan; backup/revert destekler; UWP kaldırma/servis katliamı yapmaz. |
| `CS2-Win10-Background-Telemetry-Cleanup.ps1` | CS2 odaklı arka plan/telemetri temizliği: DiagTrack/dmwappushservice, CEIP/uyumluluk görevleri, AllowTelemetry, background apps, opsiyonel UWP kaldırma. | Dry-run varsayılan; servis/görev/registry backup ve revert destekler; UWP kaldırma tam geri alınamaz. |

> İki script de **oyun içi ayarlara, BIOS'a ve NVIDIA Control Panel'e dokunmuyor.** Bu raporun NVIDIA/BIOS bölümleri ayrıca uygulanacak.

---

## 2. Ölçüm protokolü (tweak'lerden önce)

### Araçlar

| Araç | Ne için | Not |
|---|---|---|
| **CapFrameX** | avg / 1% low / 0.1% low, frametime grafiği | CS2 benchmark map, 3 run |
| **LatencyMon** | DPC/ISR latency, sürücü kaynaklı takılma | 5-10 dk boşta + oyun sırasında |
| **HWiNFO64** | WHEA, effective clock, RAM sıcaklığı, VRM, GPU clock | Log açık kalsın |
| **PresentMon** | input-to-photon / present latency | CapFrameX ile birlikte |
| **NVIDIA Inspector** | GPU clock/voltage/thermal izleme | OC için Afterburner daha pratik |

### Kurallar

1. Her değişiklikten önce **3 run** baseline al.
2. Aynı map, aynı server/bot setup, aynı saat.
3. Değişiklikten sonra **3 run** daha al.
4. Fark yoksa **geri al**. “Belki işe yarar” diye tutma.
5. WHEA 19/18 varsa performans değil **stabilite** sorunu olarak ele al.

### Baseline tablosu (doldurulacak)

| Metrik | Baseline | Tweak sonrası | Fark | Karar |
|---|---:|---:|---:|---|
| Avg FPS | | | | |
| 1% low | | | | |
| 0.1% low | | | | |
| Frametime p99 (ms) | | | | |
| DPC max (µs) | | | | |
| GPU clock (avg) | | | | |
| CPU effective clock | | | | |
| WHEA hataları | | | | |

---

## 3. BIOS / firmware katmanı

> BIOS'a girmeden önce mevcut profili kaydet (OC profile slotu). Her değişiklik sonrası Windows'ta HWiNFO ile WHEA kontrol et.

| Ayar | Öneri | Neden / Not | Durum |
|---|---|---|---|
| BIOS sürümü | Son stabil sürüm | Z390 firmware'leri RAM uyumluluğunu etkiler | ⬜ |
| XMP / DOCP | **XMP 4000 CL18** açık | 64 GB'da IMC yükü yüksek; stabilite test edilecek | ⬜ |
| RAM voltajı | XMP'nin istediği değer (genelde 1.35-1.40 V) | 4 DIMM/dual-rank ise 1.40 V gerekebilir; ısıyı izle | ⬜ |
| VCCIO / VCCSA | Auto ile başla; 4000 için gerekirse 1.20-1.30 V aralığı | Çok yüksek verme; stabilite testi şart | ⬜ |
| CPU çarpanı | 5.0 GHz all-core | CS2 AVX ağırlıklı değil; 5.0 rahat | ✅ mevcut |
| CPU voltajı / LLC | Kararlı en düşük Vcore; LLC orta | 5.0 için tipik 1.25-1.35 V; silikona göre | ✅ mevcut |
| Ring / uncore | 4.7 GHz başlangıç | Ring düşürmek 1% low'u bozabilir | ⬜ |
| C-states | **Disabled** (veya C1E off) | Fixed 5.0 ile tutarlılık; sıcaklık artar | ⬜ |
| Speed Shift (HWP) | Enabled; Windows EPP=0 | 9900K HWP destekler; boşta güç tasarrufu | ⬜ |
| Spread Spectrum | **Disabled** | BCLK 100 stabilitesi | ⬜ |
| PCIe ASPM | **Disabled** | GPU/NVMe link power saving kapat | ⬜ |
| Above 4G Decoding | **Enabled** | RTX 3070 için gerekli; ReBAR için değil | ⬜ |
| Resizable BAR | **Disabled / Auto** | Z390 resmî desteklemiyor; zorlama | ⬜ |
| HPET | BIOS default | Zorla açma/kapatma; Windows tarafında da dokunma | ⬜ |
| Fast Boot | İsteğe bağlı | Driver değişiminde kapatmak debug'ı kolaylaştırır | ⬜ |
| Fan eğrileri | CPU 80 °C'de %100'e yakın; GPU agresif | Termal throttle'ı önle | ⬜ |
| TPM / PTT | BitLocker kullanılıyorsa açık | Win10 için zorunlu değil | ⬜ |

### RAM stabilite testi

- **TM5 anta777** (extreme) veya **Karhu RAM Test**.
- 4000 CL18'de hata varsa sırasıyla:
  1. 3733 CL17,
  2. 3600 CL16,
  3. 3600 CL18.
- 64 GB'da `tRFC`, `tREFI`, `tFAW`, `tRRD` latency'ye en çok dokunan alt zamanlamalar.
- WHEA 19 varsa voltaj/timing düşür, “mavi ekran yok” yeterli değil.

---

## 4. Windows 10 — güç yönetimi

### 4.1 Güç planı

Ana script `SCHEME_MIN` (High Performance) seçiyor. Alternatifler:

| Plan | Ne zaman | Not |
|---|---|---|
| **High Performance** | Varsayılan öneri | Core parking kapalı, disk/USB uyku kapalı |
| **Ultimate Performance** | İstersen dene | `powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61`; her sistemde görünmez |
| Balanced | Dizüstü/ısı sorunu varsa | Masaüstünde önerilmez |

### 4.2 powercfg komutları

```powershell
# Yönetici PowerShell

# High Performance
powercfg /setactive SCHEME_MIN

# PCIe ASPM kapat
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0

# USB selective suspend kapat
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

# Disk uyku kapat
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0

powercfg /setactive SCHEME_CURRENT
```

Opsiyonel (fixed 5.0 kullanıyorsan mantıklı; sıcaklık artar):

```powershell
# Core parking kapat (zaten kapalı olabilir; önce powercfg /q ile bak)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES 100

# CPU frekansını sabit tut
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

# OS tarafından C-state kapatma
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1

# Energy Performance Preference = max performance (Speed Shift)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0

# Aktif soğutma
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 1

powercfg /setactive SCHEME_CURRENT
```

> `IDLEDISABLE=1` ve BIOS C-states off birlikte gereksiz olabilir; birini seç. Sıcaklık/VRM testi yap.

### 4.3 Registry: scheduler ve MMCSS

| Ayar | Konum | Değer | Etki / Not | Durum |
|---|---|---|---|---|
| `Win32PrioritySeparation` | `HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl` | `38` (0x26) | Short+variable+3:1; **Win10 client default 2 ile aynı**. Genelde no-op. | ⬜ |
| `SystemResponsiveness` | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` | `10` | MMCSS arka plan rezervi %20 → %10. 0 yapma. | ⬜ |
| `NetworkThrottlingIndex` | aynı yer | **dokunma** | Kapatmak NDIS.sys DPC latency'sini artırabilir. | ❌ |
| `PowerThrottlingOff` | `HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling` | `1` | EcoQoS'un oyun thread'lerini kısmasını engeller. | ⬜ |
| `Games` profili | `...\SystemProfile\Tasks\Games` | `GPU Priority=8`, `Priority=6`, `Scheduling Category=**Medium**`, `SFIO Priority=High` | **Düzeltme:** `Scheduling Category=High` **stutter üretir** — oyun thread'lerini Pro Audio bandına (23-26) sokup sistem thread'lerini starve eder. `GPU Priority` ve `SFIO Priority` Microsoft dokümanına göre **hiç kullanılmaz**. `Priority=6` yalnızca `Medium` kategoride anlamlıdır (`High`da her zaman 2 sayılır). | ⬜ |
| `DisablePagingExecutive` | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` | `1` | Kernel'i RAM'de tutar; 64 GB'da zararsız, etki küçük. | ⬜ |
| `HwSchMode` | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | `2` = HAGS açık, `1` = kapalı | A/B test; bazı sistemlerde stutter. | ⬜ |

### 4.4 Önemli düzeltme: `Win32PrioritySeparation`

- `38` / `0x26` = **short quantum, variable, 3:1 foreground boost**.
- Windows 10 client'ta `2` zaten bu moda çözümlenir.
- Yani 38'e geçmek çoğu sistemde **davranış değiştirmez**; “FPS tweak” olarak sunulmamalı.
- Alternatif `0x2A` (42) = short, fixed, 3:1; fixed olduğu için foreground quantum avantajı pratikte kalkar. Körlemesine 42/38 denemesi yapma; ölç.

### 4.5 Güç ile ilgili yapılmayacaklar

- `NetworkThrottlingIndex=0xFFFFFFFF` → ❌
- `useplatformclock=true` (HPET zorlama) → ❌
- `disabledynamictick=yes` → sadece ölçerek; varsayılan olarak ❌
- Pagefile kapatma → ❌
- Tüm servisleri disable etme → ❌

---

## 5. Windows 10 — GPU, IRQ ve timer

### 5.1 MSI mode

| Adım | Ne yapılacak | Not | Durum |
|---|---|---|---|
| 1 | GPU/NIC'in zaten MSI kullanıp kullanmadığını kontrol et | Device Manager → Properties → Resources; veya `MSI_util_v3` | ⬜ |
| 2 | Zaten MSI ise **dokunma** | Gereksiz risk | ⬜ |
| 3 | Değilse `MSISupported=1` + reboot | GPU'da siyah ekran riski; Safe Mode hazır olsun | ⬜ |
| 4 | Interrupt Priority = High | Sadece LatencyMon'da belirgin DPC varsa; körlemesine yapma | ⚠️ |
| 5 | Interrupt affinity | En son adım; CPU 0 sistem interrupt'ları için yoğun | ⚠️ |

### 5.2 Timer resolution

| Ayar | Öneri | Not |
|---|---|---|
| `bcdedit /set disabledynamictick yes` | Varsayılan: **yapma** | Bazı sistemlerde micro-stutter azalır; güç/ısı artar. A/B test. |
| `bcdedit /set useplatformclock true` | **Yapma** | HPET zorlama genelde latency'yi artırır. |
| 0.5 ms timer araçları (ISLC, SetTimerResolution) | Sadece ölçümle | Windows 10 process kapanınca eski çözünürlüğe döner; sürekli arka plan gerekir. |
| `GlobalTimerResolutionRequests=1` | İsteğe bağlı | Win10 2004+; global timer request. Ölçmeden uygulama. |

### 5.3 HAGS (Hardware-accelerated GPU scheduling)

- `HwSchMode=2` → açık, `1` → kapalı.
- CS2'de bazı sistemlerde açıkken 1% low iyileşiyor, bazılarında stutter artıyor.
- **A/B test:** 3 run açık, 3 run kapalı; aynı map.
- RTX 3070 + Win10 22H2 destekler.

---

## 6. Windows 10 — GameDVR, FSO, görsel ve input

| Ayar | Konum | Değer | Not | Durum |
|---|---|---|---|---|
| Game DVR | `HKCU\System\GameConfigStore` | `GameDVR_Enabled=0` | Arka plan kaydı kapat | ✅ script |
| App capture | `HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR` | `AppCaptureEnabled=0` | | ✅ script |
| GameDVR policy | `HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR` | `AllowGameDVR=0` | | ✅ script |
| Game Mode | `HKCU\Software\Microsoft\GameBar` | `AutoGameModeEnabled=1`, `AllowAutoGameMode=1` | Açık başla; 1% low bozarsa kapat | ✅ script |
| Game Bar startup | `HKCU\Software\Microsoft\GameBar` | `ShowStartupPanel=0`, `UseNexusForGameBarEnabled=0` | | ⬜ |
| FSO (cs2.exe) | `HKCU\...\AppCompatFlags\Layers` | `~ DISABLEDXMAXIMIZEDWINDOWEDMODE` | Alt-tab/stabilite A/B test | ⬜ opsiyonel |
| GPU preference | `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` | `cs2.exe` = `GpuPreference=2;` | Windows Graphics settings High performance | ✅ script |
| Görsel efektler | `HKCU\...\Explorer\VisualEffects` | `VisualFXSetting=2` | Best performance; kozmetik | ⬜ |
| Mouse accel | `HKCU\Control Panel\Mouse` | `MouseSpeed=0`, `MouseThreshold1=0`, `MouseThreshold2=0`, **`MouseSensitivity=10`** | **Düzeltme:** `MouseSensitivity` 10 değilse count'ları ölçekler (skip/duplicate) — tek 1:1 değer odur. `SmoothMouseXCurve/YCurve`'a dokunma: `MouseSpeed=0` iken zaten okunmazlar (silmek/`00` yapmak gereksiz). **CS2 raw input kullandığı için bu ayar masaüstünü etkiler, nişan hızını değil.** | ⬜ |
| Enhance pointer precision | `HKCU\Control Panel\Mouse` → Pointer Options | **Off** | Windows mouse acceleration; CS2 Raw Input bypass eder ama genel hijyen için kapat | ⬜ |
| Pointer speed | `HKCU\Control Panel\Mouse` | **6/11** | Windows çarpanını varsayılanda tut; acceleration kapalı olsun | ⬜ |
| Mouse polling rate | Mouse yazılımı / firmware | **1000 Hz** (9900K için 1000/2000 Hz; 4000/8000 Hz CPU thread yükünü artırabilir) | CS2 CPU-bound olduğunda yüksek polling frametime bozabilir; ölçümle | ⬜ |
| Transparency | `HKCU\...\Themes\Personalize` | `EnableTransparency=0` | Küçük etki | ⬜ |

> Game Mode: CS2'de çoğu sistemde açık kalması daha iyi. Kapatacaksan 1% low ve frametime p99'a bak, “FPS arttı” diye karar verme.

---

## 7. Windows 10 — arka plan, bellek, depolama

| Konu | Öneri | Etki / Risk | Durum |
|---|---|---|---|
| Defender exclusions | Sadece CS2 klasörü + `cs2.exe` | Real-time protection açık kalır; güvenlik trade-off'u | ✅ script opsiyonel |
| Memory Integrity / HVCI (Core Isolation) | Windows Security → Device Security → Core Isolation | Test için **Off**, sonra güvenlik değerlendirmesi | 5-10% FPS kazancı olabilir; WSL/Hyper-V/Docker/Sandbox kullanıyorsan yalnızca HVCI kapat, VBS foundation'ı koru; güvenlik trade-off'u | ⚠️ opsiyonel |
| VBS (Virtualization-Based Security) | `msinfo32` ile durum kontrolü | Test için geçici kapatma, sonra yeniden aç | HVCI'den daha geniş; WSL/Hyper-V/Docker/Sandbox bozabilir; güvenlik riski | ⚠️ opsiyonel |
| Startup apps | Razer/iCUE/Armoury/Nahimic/Sonic Studio kapat | 1% low'un en yaygın suçluları | ⬜ |
| Steam overlay | Steam → Settings → In-Game | **Off** | Microstutter/input lag kaynağı olabilir; A/B test | ⬜ |
| Discord overlay | Discord → Overlay | **Off** | Aynı; ses/overlay hook'ları frametime bozabilir | ⬜ |
| NVIDIA overlay (App/GFE) | NVIDIA App → Overlay | **Off** | Overlay hook'ları ölçümü ve frametime'i etkiler | ⬜ |
| SysMain (Superfetch) | **Ölçerek** kapat | NVMe'de etki tartışmalı; uygulama açılışı yavaşlar | ⚠️ |
| Windows Search | Kullanmıyorsan indexing kapat | Arka plan disk I/O azalır | ⬜ |
| Shader cache bakımı | NVIDIA CP → Shader cache size | Unlimited/10 GB; düzenli silme | Stutter varsa sürücü güncellemesi sonrası bir kez temizle; her seferinde silme | ⬜ |
| Delivery Optimization | Upload limiti | FPS'e etkisi yok; bant genişliği | ⬜ |
| Telemetry servisleri | İsteğe bağlı | Performans etkisi ihmal edilebilir; gizlilik | ⬜ |
| Pagefile | **System managed** bırak | 64 GB var diye kapatma; anti-cheat/uygulama sorunları | ❌ kapatma |
| NVMe | Firmware güncel, PCIe 3.0 x4, disk sleep off | `powercfg` DISKIDLE=0 | ⬜ |
| Memory compression | **Açık bırak** | Kapatmak RAM baskısında zarar verir | ❌ |
| Prefetch/Superfetch | Varsayılan | NVMe'de ölçülebilir fark yok | ⬜ |

### Defender exclusion komutu (script zaten yapıyor)

```powershell
Add-MpPreference -ExclusionPath "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"
Add-MpPreference -ExclusionProcess "cs2.exe"
```

> Bu, Defender'ı kapatmaz. Sadece CS2 dosyalarının sürekli taranmasını engeller. Yine de bir güvenlik trade-off'udur; klasörün temiz olduğundan emin ol.

---

## 8. Windows 10 — ağ (detaylı)

> **Hedef:** "hızlı ve akıcı internet" — ama **paket kaybı olmadan**. Bu iki hedef bazen çelişir; öncelik paket kaybını silmemektir.
> **Donanım:** Anakart üzeri **Intel I219-V** Gigabit LAN, router **ASUS RT-AX82U**, kablolu bağlantı.

### 8.1 Temel prensip: neyi kapatmamalı

En yaygın hata, "her şeyi kapat" yaklaşımıdır. Aşağıdakiler **varsayılan olarak açık bırakılır**:

| Ayar | Değer | Neden dokunulmaz |
|---|---|---|
| **Rx/Tx Flow Control** | **Enabled** | Pause frame ile buffer taşmasını önler. Kapatmak **paket kaybını artırır**. |
| **Checksum Offload** | Enabled | Kapatmak her pakette CPU işi yapar; CPU yükü artar. |
| **LSO / TSO** | Enabled | Büyük gönderimlerde CPU yükünü düşürür. |
| **RSS** | Enabled | 8C/16T'da alıcı işlemeyi çekirdeklere dağıtır. |
| **Speed & Duplex** | **Auto** | Tek tarafı sabitlemek duplex mismatch → yeniden gönderim ve düşük hız. |
| **Jumbo Frames** | **1500** | Ev/ISP yolunda uçtan uca desteklenmez; parçalanma ve drop riski. |
| **Buffer / RSS kuyruk derinliği** | Varsayılan | Drop görünmeden maxlamak kuyruk gecikmesi ekler. |
| **RSC / LRO** | Enabled | TCP segment birleştirme CPU'yu rahatlatır; CS2 çoğunlukla UDP. |

> Kaynak mantığı: *"A Guide to Windows NIC Advanced Settings"* (KomuraSoft, 2026) — checksum/RSS/LSO/RSC varsayılan açık kalmalı, Speed & Duplex Auto, Jumbo yalnızca uçtan uca hizalıysa.

### 8.2 Kapatılması gerekenler (güç tasarrufu)

| Ayar | Değer | Neden |
|---|---|---|
| Energy Efficient Ethernet / Green Ethernet | **Disabled** | Link idle'da güç düşürme; hız ayarı değil ama link kararlılığı/düşüş sorunu için ilk izole adımı. |
| Power Saving Mode | Disabled | Aynı gerekçe. |
| Selective Suspend | Disabled | Windows uykusunda link düşmesi. |
| Ultra Low Power / Gigabit Lite | Disabled | Aynı gerekçe. |
| Wake on Magic Packet / Wake on Pattern Match | Disabled | WoL kullanılmıyorsa; istenmeyen uyanmaları ve DPC kaynaklarını keser. |
| **Adapter power management** | **Disabled** | `Disable-NetAdapterPowerManagement` — uyku sırasında kablo düşmesi ve gecikme. |

### 8.3 Ölçümle değerlendirilecekler (opsiyonel)

| Ayar | Etki | Risk |
|---|---|---|
| **Interrupt Moderation → Off** | Interrupt sıklığı azalır → latency düşer | **CPU ve DPC yükü artar.** Ölçmeden kalıcı yapma. |
| **RSC / LRO → Off** | Daha ince segment granülaritesi | CS2 UDP ağırlıklı; etkisi genelde küçük. |
| LSO / Checksum / USO → Off | Yalnızca sorun ayıklama | CPU artar, gerekçesizse zararlı. |
| DNS cache flush | İlk çözümleme hızlanır | Ölçülebilir etkisi çok küçük; zararsız. |

### 8.4 Script ile uygulama

`CS2-Win10-Network-Tuning.ps1` (dry-run varsayılan, backup/revert destekli):

```powershell
# Temel uygulama
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply

# Interrupt Moderation A/B testi (ölç!)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply -DisableInterruptModeration

# Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Revert
```

Script ayrıca: adapter bilgisi, **NIC istatistikleri (discard/error sayacı)**, `netsh int tcp show global` ve tüm advanced property listesini konsola basar — böylece "paket kaybı var mı" ölçülebilir.

### 8.5 Router tarafı — ASUS RT-AX82U

> Router ayarları Windows'tan daha büyük etki yapar. "Hızlı internet" ile "düşük latency" arasındaki fark genelde **bufferbloat** kaynaklıdır.

**Önce ölç:** `waveform.com/bufferbloat` (veya `speedtest.net` bufferbloat testi) → A/B/C/D/F notu.

| Ayar | Değer | Not |
|---|---|---|
| **Adaptive QoE** | **ON** | ASUS'un 2026 güncel arayüzü. Eski "Adaptive QoS" yerine geçebilir. |
| **QoE modu** | **Gaming Mode** | Oyun paketlerine daha yüksek trafik ağırlığı; latency ve paket kaybını azaltır (ASUS dokümanı). |
| **Bandwidth Limiter** | **PC'nin bant genişliğini ~%95'ine sabitle** | Bufferbloat için en etkili tek ayar. Tam bant genişliği = kuyruk birikmesi = latency spike. |
| QoS türleri | **Tek seferde bir tür** | ASUS Adaptive QoS / Traditional QoS / Bandwidth Limiter aynı anda kullanılamaz. |
| **PC bağlantısı** | **Kablolu (LAN)** | Wi-Fi jitter ve tekrar (retransmission) kaynaklıdır. |
| **Jumbo / MTU** | **1500** | Router'ın LAN/WAN MTU'su 1500 ise NIC'de jumbo açma. |
| SQM / fq_codel | RT-AX82U stock firmware'de yok | **Düşük latency + bufferbloat için en iyi çözüm**, ancak bu router SQM desteklemiyor. Alternatif: Merlin firmware (varsa) ya da hızlı bir PC/router'ı SQM'li bir cihazla değiştirmek. |

> **Gerçekçi beklenti:** RT-AX82U'da bufferbloat "iyi" ama "mükemmel" değildir; Adaptive QoE + %95 limiter belirgin iyileşme sağlar. SQM/fq_codel seviyesindeki latency ancak router değişikliği veya Merlin firmware ile mümkün.

### 8.6 Windows QoS / DSCP (opsiyonel, sınırlı)

Windows 10/11'de `New-NetQosPolicy` ile uygulama bazlı DSCP işaretleme mümkündür (ör. `cs2.exe` → DSCP 46 / EF). **Ancak:**
- Tüketici router'larının çoğu (RT-AX82U dahil) DSCP'yi uygulama bazlı QoS yerine yok sayar; işaretlemek tek başına etkisizdir.
- Router tarafında QoS zaten çalışıyorsa gereksiz karmaşıklıktır.
- Bu yüzden proje **uygulamaz**; sadece ileri seviye seçenek olarak not edilir.

### 8.7 Reddedilenler

- ❌ **Nagle / `TCPNoDelay` / `TcpDelAckTicks`** — CS2 UDP; etkisiz.
- ❌ **`NetworkThrottlingIndex = 0xFFFFFFFF`** — DPC latency artışı.
- ❌ **Rx Flow Control kapatma** — paket kaybını artırır (hedefimizin tam tersi).
- ❌ **Speed & Duplex sabitleme** — duplex mismatch riski.
- ❌ **Jumbo Frame** — uçtan uca hizalı değil, parçalanma/drop.
- ❌ **Checksum/LSO/RSC kapatma** — CPU yükünü artırır.
- ❌ **MTU değiştirme** — ISP yolu belirleyici; router/ISP ile eşleşmeli.

---

## 8A. Input lag — ölçüm zinciri

> **Kural:** FPS artışı değil, **click-to-photon** ve **1% low** hedeflenir. Tek katman değiştir, ölç, karar ver.

### 8A.1 Zincir (kayıp nereden oluyor?)

```
Fare → USB polling → Windows input queue → CS2 tick → oyun → NVIDIA render queue → monitör
        (1 ms)        (1-3 ms)          (tick)    (CPU)      (Reflex kuyruğu)   (1 panel)
```

Her halka ayrı ölçülür. Kayıp genelde **render queue** veya **CPU tick** kaynaklıdır; fare/mouse ayarı değil.

### 8A.2 Ölçüm araçları

| Araç | Ölçtüğü | Not |
|---|---|---|
| **NVIDIA Reflex Analyzer** | Gerçek click-to-photon (ms) | En güvenilir referans; 360 Hz'te 2.78 ms/panel sınırı. |
| **PresentMon** | Present latency / frame time | Reflex Analyzer yoksa en iyi ikame. |
| **CapFrameX** | 1% / 0.1% low, p99 frametime | Akıcılığın ana metriği. |
| **MouseTester / Mouse Rate Checker** | Polling rate doğrulama | 1000 Hz ayarının gerçekten uygulandığını doğrular. |
| **LatencyMon** | DPC/ISR kaynakları | Interrupt Moderation A/B testinde belirleyici. |

### 8A.3 Sıralı müdahale planı

1. **NVIDIA Reflex**: Oyun içi `Enabled` + driver `Low Latency Mode = Off`. Stutter varsa `-noreflex` + driver `Ultra` + driver cap'i dene (A/B).
2. **FPS cap**: G-Sync + V-Sync + Reflex → `refresh−3` (360 Hz → **357**). G-Sync yoksa: uncapped veya stabil yüksek cap. Cap'i **tek yerden** yönet.
3. **HAGS**: Açık/kapalı A/B (proje zaten destekliyor).
4. **Mouse**: polling **1000 Hz**, Enhance pointer precision **Off**, pointer speed **6/11**. 4000/8000 Hz CS2 CPU thread'ini yorabilir.
5. **Overlay'ler**: Steam / Discord / NVIDIA overlay **Off** — microstutter kaynağı.
6. **BIOS**: fixed 5.0 GHz + ring 4.7 + C-states off; termal throttle yoksa effective clock düşmez.
7. **Interrupt Moderation**: **yalnızca** LatencyMon DPC deltası gösterirse kapat.
8. **VBS/HVCI**: 5-10% kazanç mümkün; güvenlik trade-off'unu kabul ederek test et.

> **Ölçüm sırası önemli:** 3 run baseline → bir değişiklik → 3 run → karar. CapFrameX'te ortalama FPS değil **1% low** ve **frametime p99**'a bak.

---

## 9. NVIDIA — sürücü kurulumu

| Adım | Öneri | Not |
|---|---|---|
| Sürücü tipi | **Game Ready** | Studio'ya gerek yok |
| Temiz kurulum | **DDU** ile | Özellikle sürücü düşürürken/yükseltirken |
| NVIDIA App / GFE | Overlay istemiyorsan kapat | Overlay input/frametime ölçümünü etkileyebilir |
| Kurulum sonrası | 3D ayarları sıfırlanır | Profili yeniden uygula |
| Profil yedeği | Inspector `.nip` export | Sürücü güncellemesinden sonra geri yükle |
| Sürücü sürümü | Son stabil | Beta sürücülerden kaçın; sorun varsa bir önceki WHQL |

---

## 10. NVIDIA Control Panel / NVIDIA App — CS2 profili

> Ayarları **global** değil, **`cs2.exe` profiline** uygula. Global “Prefer max performance” boşta güç/ısıyı artırır.

| Ayar | Değer | Neden / Not |
|---|---|---|
| Power management mode | **Prefer maximum performance** | Buy fazında GPU downclock'unu engeller; en önemli tek ayar |
| Low Latency Mode | **Off** (CS2'de Reflex açıksa) / **Ultra** (Reflex kapalıysa) | Reflex varsa sürücü ayarı gereksiz; üst üste bindirme |
| Vertical sync | **Off** (G-Sync + Reflex istisnası) | Tek başına input lag ekler |
| Max frame rate | **Off** / G-Sync varsa refresh−3 | Çift cap yapma; cap'i tek yerden yönet |
| Preferred refresh rate | **Highest available** | Monitörün max Hz'ini zorlar |
| Texture filtering — Quality | **High performance** | Ücretsiz FPS; CS2'de görsel fark ihmal edilebilir |
| Anisotropic sample optimization | **On** | Texture filtering maliyetini düşürür |
| Trilinear optimization | **On** | Aynı |
| Shader cache size | **Unlimited / 10 GB** | Shader compile stutter'ını azaltır; **disable etme** |
| Threaded optimization | **Auto / On** | Source 2 thread yönetimini bozmamak için Auto iyi |
| Triple buffering | **Off** | OpenGL için; CS2'de gereksiz |
| FXAA / MFAA | **Off** | Görüntüyü bulanıklaştırır |
| Ambient occlusion | **Off** | Gereksiz GPU maliyeti |
| DSR / Image scaling | **Off** | Çift ölçekleme artifact yapar |
| G-Sync | Monitör destekliyorsa **Fullscreen only** | VRR + Reflex + V-Sync + cap kombinasyonu |
| Background app max frame rate | **30** (NVIDIA App) | Alt-tab'da GPU'yu boşa çalıştırmaz |
| Monitor technology | G-Sync Compatible (varsa) | Monitöre göre |

### Reflex ve Low Latency Mode notu

- Varsayılan: CS2 içinde **NVIDIA Reflex = Enabled**; driver **Low Latency Mode = Off** (Reflex render queue'yu yönetir).
- Reflex stutter yaparsa test et: in-game Reflex **Disabled** + driver **Low Latency Mode = Ultra** + driver-level FPS cap.
- **Reflex ve Ultra Low Latency Mode'u aynı anda açık bırakma**; ikisi aynı pipeline'da çakışır.
- RTX 3070'de **Enabled + Boost** güç/ısıyı artırabilir ve bazı sistemlerde 1% low'u bozabilir; A/B test et.
- `-noreflex` topluluğun bir test seçeneğidir; NVIDIA'nın varsayılan yolu Reflex On'dur.

### G-Sync + Reflex + V-Sync notu

- G-Sync varsa tear-free + düşük latency için: **G-Sync On + V-Sync On (NVCP) + Reflex On + fps cap (refresh−3)**.
- Rekabetçi CS2'de V-Sync off tercih edilebilir; o zaman G-Sync'in kapsamı dışında kalırsın.
- Bu üçlüyü aynı anda açıp “Ultra Low Latency” de açma; çakışır.

### FPS cap notu (360 Hz için)

- **G-Sync + V-Sync + Reflex** kombinasyonunda manuel cap gerekmez; Reflex FPS'i refresh altına tutar.
- **G-Sync yoksa:** uncapped veya frametime'i stabilize eden yüksek bir cap kullan; 360 Hz için `500+` veya uncapped değerlendir.
- **G-Sync varsa ve manuel cap kullanacaksan:** `refresh − 3` (360 Hz için `357`).
- Cap'i tek yerden yönet; in-game + driver + RTSS üst üste bindirme.

---

## 11. NVIDIA Profile Inspector — CS2 profili

### 11.1 İki farklı araç

| Araç | Ne yapar | Kaynak |
|---|---|---|
| **NVIDIA Inspector** | İzleme, clock/voltage, fan, overclock | `orbmu2k.de` |
| **NVIDIA Profile Inspector** | Sürücü profili (DRS) editörü | `github.com/Orbmu2k/nvidiaProfileInspector` |

> “Optimized” üçüncü taraf build'leri kullanma. Resmî GitHub/orbmu2k dışına çıkma.

### 11.2 DRS ayarları

| Kategori | Ayar | Değer | Not |
|---|---|---|---|
| Sync & Refresh | Frame Rate Limiter V3 | **Off** / cap | Cap kullanacaksan tek yerden |
| Sync & Refresh | Maximum Pre-Rendered Frames | **1** | Reflex/LLM varsa zaten etkisiz |
| Sync & Refresh | Low Latency Mode | **Off** (Reflex açık) / **Ultra** (kapalı) | “Ultra Low Latency” ile birlikte set etme |
| Sync & Refresh | Vertical Sync | **Force off** | G-Sync + Reflex istisnası |
| Sync & Refresh | Preferred Refresh Rate | **Highest available** | |
| Texture Filtering | Texture Filtering — Quality | **High performance** | |
| Texture Filtering | Anisotropic Filter — Sample Optimization | **On** | |
| Texture Filtering | Texture Filtering — Trilinear Optimization | **On** | |
| Common | Power Management — Mode | **Prefer maximum performance** | |
| Common | Shader Cache — Cachesize | **Unlimited / 10 GB** | Driver Default da olur; disable etme |
| Common | Threaded Optimization | **Auto / On** | |
| Common | CUDA — Force P2 State | **Off** | |
| Common | Ansel — Enabled | **Off** | |
| Common | rBAR — Feature / Options | **Dokunma** | Z390'da resmî ReBAR yok |
| Antialiasing | FXAA / MFAA | **Off** | |
| Antialiasing | Ambient Occlusion | **Off** | |
| Common | DSR — Factors | **Off** | |

### 11.3 Uyarılar

- `Low Latency Mode` + Reflex + driver cap'i aynı anda kullanma.
- `rBAR`'ı Z390'da zorlama; boot/black screen riski.
- Sürücü güncellemesi DRS ayarlarını sıfırlar; `.nip` export et.
- Bazı ayarlar sürücü sürümüne göre yeniden adlandırılabilir; değer mantığı aynı.

---

## 12. NVIDIA Inspector — overclock / undervolt (RTX 3070)

| Ayar | Başlangıç | Not |
|---|---|---|
| Core offset | **+100 MHz** | Stabilse +150'ye çık; artifact varsa geri çek |
| Memory offset | **+500 MHz** | GDDR6; +800'e kadar denenebilir; artifact/çökme = geri |
| Power limit | **%105-110** | Sıcaklık ve VRM izle |
| Temp limit | **83-90 °C** | 3070 için makul |
| Fan curve | Agresif | 70 °C üstünde %70+ |
| Undervolt | **0.900-0.950 V @ ~1900-1950 MHz** | Silikona göre değişir; Afterburner curve editor daha kolay |
| Test | 3DMark Time Spy stress / OCCT / CS2 30 dk | Artifact = başarısız |

> CS2 1080p'de çoğu zaman GPU-bound değil. Overclock yerine **undervolt + stabil clock** daha çok işe yarar: daha az ısı, daha tutarlı boost, daha iyi 1% low.

---

## 13. Bu sisteme özel notlar

### i9-9900K

- 8C/16T; P/E çekirdek yok. “Prefer performance cores” gibi ayarlar sende yok.
- 5.0 GHz fixed CS2 için rahat; AVX ağırlıklı testlerde (Prime95 AVX) ayrı stabilite gerekir.
- Ring 4.7 GHz iyi başlangıç; ring'i düşürmek 1% low'u bozabilir.
- HT on/off: CS2'de sonuçlar çelişkili; D2 benchmark ile A/B test et. Körlemesine kapatma.

### Z390

- PCIe 3.0 x16; RTX 3070 için CS2'de darboğaz değil.
- Resmî ReBAR yok; Inspector'dan zorlama.
- Above 4G Decoding açık olsun (3070 için faydalı), ReBAR kapalı.

### RTX 3070

- 8 GB VRAM; 1080p CS2'de sorun yok.
- 1080p'de CPU-bound olma ihtimali yüksek; GPU OC'den çok CPU/RAM/ring stabilitesi önemli.
- Undervolt, termal throttle'ı azaltarak boost tutarlılığını artırır.

### 64 GB 4000 CL18

- 4 DIMM / dual-rank ise IMC yükü yüksek; 4000 her silikonda stabil olmayabilir.
- Fallback: 3733 CL17 → 3600 CL16 → 3600 CL18.
- `tRFC` ve `tREFI` latency'ye en çok dokunan ayarlar; ama stabiliteyi bozmadan.
- RAM sıcaklığı 50 °C üstüne çıkıyorsa airflow artır.

### Windows 10 22H2

- Destek dışı; tüketici ESU penceresi Ekim 2026'da kapandı.
- Performans için sorun değil; güvenlik için Windows 11 veya kurumsal ESU değerlendir.
- Win11'e geçiş 9900K'da resmî destekli mi kontrol et (TPM 2.0/PTT + Secure Boot).

---

## 14. Mevcut scriptlerin kapsamı

### `CS2-Windows10-Optimize.ps1`

**Uyguladıkları:**
- High Performance plan, PCIe ASPM off, USB selective suspend off.
- GameDVR/AppCapture/GameBar policy off; Game Mode on.
- Opsiyonel HAGS on/off.
- Opsiyonel Defender exclusions (CS2 klasörü + `cs2.exe`).
- NIC: EEE/Green/Wake/Power Saving/Selective Suspend off; RSS on.
- Opsiyonel NIC latency modu: Interrupt Moderation + Flow Control off.
- TCP autotuning normal, RSS enabled; Nagle/NetworkThrottling'e dokunmuyor.
- Opsiyonel Fast Startup off.
- Opsiyonel FSO off (cs2.exe).
- Windows GPU preference = High performance (cs2.exe).
- Opsiyonel timer BCD temizliği (`useplatformclock`, `disabledynamictick`, `tscsyncpolicy`, `useplatformtick`).
- Opsiyonel GameBoost-derived tweak'ler: MPO disable, Storage Sense disable, background apps disable, system VRR toggle.
- Opsiyonel WinUtil-derived tercihler: activity history, location tracking, consumer features, delivery optimization, device companion apps, Razer/Logitech auto-install, Teredo, IPv4 preference, reserved storage, Explorer folder discovery, end task right click.
- Opsiyonel performans/latency: `-SetProcessorPerformance` (min/max %100, EPP 0, aggressive boost), `-DisableIdleStates`, `-DisableDiskIdle`, `-SetMmcssGameProfile`, `-DisablePowerThrottling`, `-SetSystemResponsiveness`, `-DisablePagingExecutive`, `-DisableMouseAcceleration`, `-SetBestPerformance`.
- Opsiyonel NIC: `-DisableInterruptModeration` (latency için; CPU/DPC artar), `-DisableFlowControl` (paket kaybı riski nedeniyle önerilmez).
- Registry + powercfg değerleri backup, restore point, transcript, `-Revert`.

**Kapsamadıkları (bu raporun konusu):**
- `Win32PrioritySeparation`, `SystemResponsiveness`, `PowerThrottlingOff`.
- BIOS/CPU/RAM/ring.
- NVIDIA Control Panel / Profile Inspector.
- MSI mode / interrupt affinity.
- Timer resolution ayarlama (sadece temizleme var).
- SysMain/Search/startup temizliği.
- Ağ router/QoS.

**Kullanım:**

```powershell
# Dry run (değişiklik yapmaz)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1

# Uygula
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -AddDefenderExclusions -RestoreTimerDefaults

# HAGS A/B
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -EnableHags
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply -DisableHags

# Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
```

> `-RestoreTimerDefaults` sadece daha önce HPET/timer tweak'i yaptıysan anlamlı. Temiz kurulumda gereksiz.

### `CS2-Win10-Background-Telemetry-Cleanup.ps1`

**Uyguladıkları:**
- DiagTrack ve dmwappushservice servislerini kapatır.
- CEIP/uyumluluk telemetrisi zamanlanmış görevlerini devre dışı bırakır.
- `AllowTelemetry = 0` ayarlar.
- Global background app access'i kapatır.
- Opsiyonel UWP uygulama kaldırma/deprovision.
- Opsiyonel Windows Error Reporting kapatma.
- Servis/görev/registry backup ve `-Revert`.

**Kapsamadıkları:**
- Defender, Windows Update, BITS, networking servisleri.
- BIOS/CPU/RAM/GPU overclock.
- NVIDIA Control Panel / Profile Inspector.
- UWP kaldırma tam geri alınamaz; Microsoft Store'dan yeniden kurulmalıdır.

**Kullanım:**

```powershell
# Dry run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1

# Telemetri + background apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Apply -DisableTelemetry -DisableBackgroundApps

# Opsiyonel UWP kaldırma
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Apply -DisableTelemetry -RemoveNonEssentialApps

# Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Background-Telemetry-Cleanup.ps1 -Revert
```

### `CS2-Win10-Network-Tuning.ps1`

**Uyguladıkları:**
- Link power saving kapatma: EEE / Green Ethernet / Power Saving Mode / Selective Suspend / Ultra Low Power / Gigabit Lite.
- Wake on Magic Packet / Wake on Pattern Match kapatma.
- Adapter power management kapatma (uykuda link düşmesi).
- Receive Side Scaling açık.
- TCP autotuning normal, RSS enabled.
- Opsiyonel: Interrupt Moderation off (latency), RSC off, LSO/checksum/USO off (sadece sorun ayıklama), DNS cache flush.
- Rapor: adapter bilgisi, NIC istatistikleri (discard/error), `netsh int tcp show global`, tüm advanced property listesi.

**Kapsamadıkları:**
- Flow Control, checksum/LSO/RSC varsayılanlarını bozmaz (paket kaybı ve CPU yükü nedeniyle).
- Speed & Duplex, Jumbo Frames, MTU, buffer derinliği.
- Nagle, NetworkThrottlingIndex.
- Router tarafı (bufferbloat / QoS) — RAPOR.md bölüm 8.5.

**Kullanım:**

```powershell
# Dry run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1

# Uygula
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply

# Latency A/B testi
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Apply -DisableInterruptModeration

# Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Win10-Network-Tuning.ps1 -Revert
```

### `CS2-Desktop-OneClick.ps1`

- Aynı baseline'ın daha basit varyantı.
- `-SkipDefender`, `-SkipNic`, `-DisableFastStartup`, `-DisableFSO`, `-KeepTimerTweaks`, `-Force` parametreleri var.
- Ana script varken ikinci kez çalıştırmaya gerek yok; ikisi de backup/restore point oluşturur.

---

## 15. Uygulama planı ve kontrol listesi

### Faz 0 — Hazırlık

- [ ] BIOS profili kaydet.
- [ ] Windows restore point oluştur.
- [ ] CapFrameX + LatencyMon + HWiNFO kur.
- [ ] 3 run baseline al.
- [ ] Monitör Hz/çözünürlük ve G-Sync durumunu yaz.

### Faz 1 — BIOS/RAM

- [ ] XMP 4000 CL18 açık; TM5/Karhu test.
- [ ] Hata varsa 3733 CL17 / 3600 CL16 dene.
- [ ] Ring 4.7, C-states off, ASPM off, Above 4G on, ReBAR off.
- [ ] WHEA kontrolü.

### Faz 2 — Windows güç/scheduler

- [ ] High Performance (veya Ultimate).
- [ ] PCIe ASPM off, USB suspend off, disk idle 0.
- [ ] Core parking kapalı (zaten kapalıysa dokunma).
- [ ] `Win32PrioritySeparation=38` (no-op olabilir).
- [ ] `SystemResponsiveness=10`.
- [ ] `PowerThrottlingOff=1`.
- [ ] `DisablePagingExecutive=1`.

### Faz 3 — GameDVR/FSO/görsel

- [ ] Script ile GameDVR/GameBar kapat.
- [ ] Game Mode açık; 1% low test.
- [ ] FSO'yu cs2.exe için kapat (A/B).
- [ ] Görsel efektler = best performance.
- [ ] Mouse accel off.

### Faz 4 — NVIDIA

- [ ] DDU ile temiz Game Ready sürücü.
- [ ] CS2 profili: Prefer max performance, Low Latency (Reflex'e göre), V-Sync off, shader cache unlimited.
- [ ] Texture filtering high performance; FXAA/AO/DSR off.
- [ ] Profile Inspector ince ayarları; `.nip` export.
- [ ] 3070 undervolt/OC; stress test.

### Faz 5 — Arka plan/ağ

- [ ] Defender exclusions (CS2 klasörü).
- [ ] Startup apps temizle.
- [ ] SysMain/Search'i ölçerek değerlendir.
- [ ] NIC power saving off; Interrupt Moderation/Flow Control A/B.
- [ ] Router SQM/QoS.

### Faz 6 — İleri seviye (ölçümle)

- [ ] HAGS on/off A/B.
- [ ] MSI mode kontrol; gerekiyorsa aç.
- [ ] Interrupt affinity (sadece LatencyMon sorunu varsa).
- [ ] Timer resolution (sadece ölçülebilir kazanç varsa).
- [ ] HT on/off A/B.

---

## 16. Yapma listesi

- ❌ `NetworkThrottlingIndex` kapatma.
- ❌ `useplatformclock` / HPET zorlama.
- ❌ Defender / Windows Update / Spectre-Meltdown mitigasyonlarını kapatma.
- ❌ Pagefile kapatma.
- ❌ Memory compression kapatma.
- ❌ Z390'da ReBAR zorlama.
- ❌ MSI mode + High priority'yi ölçmeden üst üste uygulama.
- ❌ 0.5 ms timer aracını sürekli arka planda çalıştırıp ölçüm yapmama.
- ❌ “Optimized” üçüncü taraf NVIDIA Inspector build'leri.
- ❌ Aynı anda 20 tweak.
- ❌ `Win32PrioritySeparation=38`'den büyük FPS artışı beklemek (default ile aynı).
- ❌ SysMain/Search'ü körlemesine kapatmak.
- ❌ Tüm Xbox/telemetry servislerini topluca disable etmek.
- ❌ MMCSS `Scheduling Category=High` — Pro Audio bandına sokar, sistem thread'lerini starve edip stutter üretir.
- ❌ `SmoothMouseXCurve`/`SmoothMouseYCurve` silmek veya `00` yapmak — `MouseSpeed=0` iken gereksiz.
- ❌ `MouseSensitivity` 10 dışında bir değer — count'ları ölçekler.

### 16.1 İnternette önerilen ama projede reddedilen tweak'ler

Aşağıdakiler internette “FPS tweak” olarak öneriliyor; ancak kanıt/zarar dengesi veya güvenlik nedeniyle projeye **eklenmedi**:

- ❌ Nagle disable (`TcpAckFrequency`, `TCPNoDelay`, `TcpDelAckTicks`) — CS2 UDP; etkisi yok/yanlış yönlü olabilir.
- ❌ `NetworkThrottlingIndex = 0xFFFFFFFF` — NDIS.sys DPC latency'sini artırabilir.
- ❌ Prefetch disable — SSD'de uygulama açılışını yavaşlatabilir; FPS etkisi düşük.
- ❌ CPU Throttle States disable — yol/doğrulama eksik; termal risk yüksek.
- ❌ GPU Preemption disable — frame pacing iddiası var; TDR/black screen riski.
- ❌ HDCP disable — streaming hizmetlerini bozabilir; FPS etkisi zayıf.
- ❌ TSX enable — donanıma bağlı; güvenlik/uyumluluk riski.
- ❌ Active Probing disable — arka plan ağ kontrolünü kapatır; “No internet” uyarısı kozmetik olabilir.
- ❌ Mouse/Keyboard Data Queue Size düşürme — sabit değer güvenli değil; input drop riski.
- ❌ Delete Logs / Delete Temp scriptleri — sistem/uygulama loglarını ve geçici dosyaları topluca siler.
- ❌ Service toplu disable (FontCache, WIA, WerSvc, PCA vb.) — sistem işlevlerini bozabilir.
- ❌ SvcHostSplitThresholdInKB tweak — performans kazancı şüpheli; svchost sayısını artırır.
- ❌ ABDO/üçüncü taraf NVIDIA `.nip` profilleri — base profile'e uygular; CS2 profiline değil.

### 16.2 Opsiyonel / ölçülebilir tweak'ler (varsayılan değil)

Bu ayarlar sadece ölçümle değerlendirilmeli; varsayılan olarak uygulanmaz:

- USB Selective Suspend registry seçeneği:
  - Yol: `HKLM\SYSTEM\CurrentControlSet\Services\USB`
  - Değer: `DisableSelectiveSuspend = 1`
  - Not: Projede zaten `powercfg` ile USB selective suspend kapatılıyor; bu registry alternatifidir.
- Timer Coalescing:
  - Yol: `HKLM\SYSTEM\CurrentControlSet\Control\Power`
  - Değer: `CoalescingTimerInterval = 0`
  - Not: Sadece LatencyMon'da timer coalescing sorunu varsa test edilmeli; güç/ısı trade-off'u vardır.
- Driver search off:
  - Yol: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching`
  - Değer: `SearchOrderConfig = 0`
  - Not: Performans değil; sürücü kurulum davranışını değiştirir. İsteğe bağlı.

---

## 17. Geri alma ve yedekleme

| Katman | Yedek | Geri alma |
|---|---|---|
| Registry | Script `CS2-Optimize-Backup-*` klasörüne `.reg` export eder | `.reg` import veya `-Revert` |
| Power plan | Aktif scheme GUID kaydedilir | `powercfg /setactive <GUID>` |
| NIC | `nic-backup.json` | `Set-NetAdapterAdvancedProperty` |
| Defender | `defender-backup.json` | Exclusion'ları kaldır |
| BCD | `bcd-backup` | `bcdedit /import` |
| BIOS | OC profile slotu | BIOS'tan geri yükle |
| NVIDIA | `.nip` export | Profile Inspector import |
| Sistem | Restore point | System Restore |

> `-Revert` sadece scriptin yaptığı değişiklikleri geri alır; NVIDIA/BIOS/registry'de elle yaptıklarını kapsamaz.

---

## 18. Açık sorular / sonraki adımlar

1. Monitör **360 Hz** onaylandı; çözünürlük henüz bilinmiyor (doğrula, genellikle 1080p).
2. G-Sync var mı? CS2'de Reflex açık mı?
3. RAM 2×32 GB onaylandı; dual-rank mı bilinmiyor.
4. 4000 CL18 stabil mi? TM5/Karhu sonucu?
5. HT on/off denendi mi?
6. HAGS açık/kapalı hangi değerde şu an?
7. Ağ **Ethernet** onaylandı; router: ASUS RT-AX82U.
8. Windows 11'e geçiş düşünülüyor mu?

Bu soruların çoğuna `Get-Cs2SystemReport.ps1` ile üretilen rapor (monitör çözünürlük/Hz, RAM modül düzeni/hızı, NIC modeli, NVIDIA sürücü sürümü) yanıt verebilir; `SISTEM-OZELLIKLERI.md`'deki varsayımlarla karşılaştır.

### Karar günlüğü

| Tarih | Değişiklik | Öncesi | Sonrası | Karar | Not |
|---|---|---|---|---|---|
| | | | | | |
| | | | | | |
| | | | | | |

---

## 19. GameBoost v3 incelemesi (harici tweak pack)

GameBoost v3, i9-9900K / Z390-A PRO / RTX 3070 / 360 Hz hedefli bir `.bat` + `.nip` paketidir. Backup/restore ve donanım algılama içermesi iyi; ancak bizim projenin çoğu ayarını zaten içeriyor ve bazı riskli değerler var.

### 19.1 Projede zaten olanlar
- Ultimate Performance / High Performance güç planı
- PCIe ASPM off, core parking off, USB selective suspend off
- Game DVR / AppCapture / Game Bar off, Game Mode on
- HAGS on/off
- FSO off
- Win32PrioritySeparation = 38
- SystemResponsiveness = 10
- PowerThrottlingOff = 1
- Mouse acceleration off
- Visual effects = performans
- Storage Sense kapatma
- Arka plan uygulama kapatma
- DNS flush
- HVCI/VBS kapatma (opsiyonel, güvenlik trade-off'u)
- RTX 3070 NVIDIA panel önerileri

### 19.2 Projeye eklenebilecek opsiyonel maddeler

| Madde | Değer / Not | Risk |
|---|---|---|
| MPO disable | `HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode = 5` | DWM overlay katmanlarını kapatır; flicker/stutter için A/B test |
| Storage Sense disable | `HKCU\...\StoragePolicy\01 = 0` | Arka plan temizlik I/O'sunu engeller; opsiyonel |
| Background apps disable | `HKCU\...\BackgroundAccessApplications\GlobalUserDisabled = 1` | Arka plan uygulama yükünü azaltır |
| VRR sistem geneli | `DirectXUserGlobalSettings = SwapEffectUpgradeEnable=1;VRROptimizeEnable=1/0` | Sadece VRR destekli monitörde test et |
| MenuShowDelay / StartupDelay | `0` | Kozmetik; performans etkisi düşük |

### 19.3 Projeye eklenmemesi gerekenler
- `NetworkThrottlingIndex = 0xFFFFFFFF` (projede ❌)
- Nagle disable (projede ❌; CS2 UDP)
- Service toplu disable (FontCache, WIA, WerSvc, PCA vb.) (projede ❌)
- MPO disable topluca uygulama (opsiyonel A/B dışında ❌)
- `RTX3070.nip` base profile importu (üçüncü taraf; CS2 profiline değil base profile'e uygular; power management mode adaptive, shader cache 4 GB)
- `Disable HPET.cmd` içindeki `disabledynamictick yes` + `useplatformtick yes` (projede yalnızca ölçülebilir kazanç varsa)
- `SvcHostSplitThresholdInKB` (performans kazancı şüpheli)

### 19.4 Donanım uyumsuzluğu
GameBoost BIOS rehberi **DDR4-3600 CL16** varsayıyor; bizim sistem **DDR4-4000 CL18-22-22-42**. Bu nedenle XMP, VCCIO/VCCSA, command rate ve voltaj önerileri doğrudan uygulanmamalı. Genel ilkeler (XMP açık, C-states off, Above 4G on, ReBAR) kullanılabilir.

### 19.5 Değerlendirme
GameBoost v3 iyi bir **referans** ve backup/restore yaklaşımı güzel; ancak bizim projede zaten daha güvenli ve ölçülebilir bir yapı var. GameBoost'tan alınabilecek tek anlamlı opsiyonel maddeler: **MPO disable**, **Storage Sense disable**, **background apps disable** ve **VRR sistem geneli toggle**. Bunlar da A/B test ile değerlendirilmeli.

---

## Ek A — Win11Debloat inceleme özeti (önceki konu)

- Resmî repo: `github.com/Raphire/Win11Debloat` (MIT, ~62k yıldız).
- Kaynak taramasında obfuscation, `IEX`/base64, kalıcılık, Defender/firewall/UAC/hosts/DNS tampering bulunmadı.
- Son release `2026.10.30` ZIP SHA-256 `6830bf501d2740c3317133ac0ecdc2a3ab80ed7f6c83e7f0f20dc66afbf758a7`; `SHA256SUMS` ile eşleşiyor.
- `Get.ps1` indirdiği ZIP'in hash'ini doğruluyor.
- Riskler: admin-level değişiklikler, varsayılan `AllUsers` app removal, Force Remove Edge'in yıkıcı olması, opsiyonel güvenlik ayarlarının düşürülmesi.
- README'deki `& ([scriptblock]::Create((irm "https://debloat.raphi.re/")))` yöntemi uzaktan kod çalıştırır; tercih edilmemeli.
- Sonuç: malware/backdoor yok; “sıfır risk” denemez. Scripti gözden geçirerek ve tek tek seçerek kullan.

---

## Ek B — Doğrulama notları / kaynaklar

- `Win32PrioritySeparation` decode: short+variable+3:1 = 0x26; Win10 client default 0x02 ile aynı mod.
- `NetworkThrottlingIndex`: kapatmanın NDIS.sys DPC latency'sini artırdığına dair xperf ölçümleri.
- NVIDIA Profile Inspector: `github.com/Orbmu2k/nvidiaProfileInspector`.
- NVIDIA Inspector: `orbmu2k.de/tools/nvidia-inspector-tool`.
- CapFrameX: `capframex.com`.
- LatencyMon: `resplendence.com/latencymon`.
- HWiNFO64: `hwinfo.com`.
- Win11Debloat: `github.com/Raphire/Win11Debloat`.

---

> **Not:** Bu dosya bir çalışma raporudur. Uyguladıkça “Durum” ve “Karar günlüğü” bölümlerini güncelle. Ölçümsüz hiçbir tweak'i “kalıcı” işaretleme.
