# Sistem Özellikleri ve Ayar Eşleşmesi

> **Proje:** CS2-Win10-Optimizer  
> **Sürüm:** v1.0.0 — 10 Kasım 2026  
> **Amaç:** Bu depodaki Windows/NVIDIA/BIOS ayarlarının hangi donanım ve sistem varsayımlarına göre seçildiğini belgelemek.

Bu dosya, ayarların “herkese uygun” genel bir tweak listesi olmadığını; **i9-9900K + Z390 + RTX 3070 + 64 GB DDR4** kombinasyonuna göre daraltıldığını gösterir. Farklı bir donanımda aynı değerler aynı sonucu vermeyebilir.

---

## 1. Sabit sistem özellikleri

| Bileşen | Değer | Ayar kararlarına etkisi |
|---|---|---|
| **CPU** | Intel Core i9-9900K, 8 çekirdek / 16 thread, Coffee Lake Refresh, LGA1151 | 5.0 GHz fixed, ring 4.7, C-states/EPP, HT A/B testi |
| **CPU soğutma** | **240 mm sıvı (AIO)** | 5.0 GHz fixed için termal headroom iyi; C-states off sırasında sıcaklığı izle |
| **Anakart** | **ASUS Prime Z390-A** (Z390, LGA1151) | PCIe 3.0, resmî ReBAR yok, Above 4G/ASPM ayarları |
| **RAM** | 64 GB DDR4-4000, CL18-22-22-42 | 4000 MHz IMC yükü, dual-rank/4 DIMM stabilitesi, tRFC/tREFI |
| **RAM düzeni** | **2×32 GB DDR4-4000 CL18-22-22-42** (dual-rank henüz bilinmiyor) | 2 DIMM = IMC yükü 4×16'dan daha düşük; 4000 CL18 stabilite TM5/Karhu ile onaylanacak |
| **GPU** | NVIDIA RTX 3070, 8 GB GDDR6, Ampere | Prefer max performance, undervolt, shader cache, 8 GB VRAM sınırı |
| **GPU modeli** | **RTX 3070 8 GB GDDR6** (AIB/FE modeli bilinmiyor; NVIDIA son sürüm sürücü kurulu) | Power limit, fan eğrisi, VBIOS |
| **Depolama** | **240 GB SATA SSD** | Disk idle, SysMain/Search değerlendirmesi |
| **OS** | Windows 10 22H2 (build 19045) | GameDVR/FSO/HAGS/power plan; destek dışı |
| **Monitör** | **360 Hz** (çözünürlük bilinmiyor; genellikle 1080p, doğrula) | fps cap = 357 önerilebilir, G-Sync/Reflex kararları |
| **Ağ** | **Ethernet (kablolu), router: ASUS RT-AX82U** | NIC advanced properties, SQM/QoS |
| **PSU** | **Doldurulacak:** model/watt | 5.0 GHz + RTX 3070 transient yükleri |
| **Kasa/hava akışı** | **Doldurulacak** | RAM/VRM/GPU sıcaklıkları |

> **Not:** Monitör ve ağ bilgileri gelene kadar fps cap, G-Sync/Reflex ve NIC/router ayarları “koşullu” kabul edilmelidir.

---

## 2. Ayar → hedef donanım eşleşmesi

### 2.1 CPU / scheduler

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| 5.0 GHz all-core fixed | 9900K'nın 8C/16T yapısı ve CS2'nin CPU davranışı | AVX ağırlıklı testlerde ayrı stabilite gerekir |
| Ring 4.7 GHz | 9900K uncore/cache; CS2'de 1% low'a etki eder | Ring'i düşürmek genelde zarar verir |
| C-states off (BIOS) / `IDLEDISABLE=1` | Fixed 5.0 ile clock tutarlılığı | Sıcaklık/VRM artar; ikisini birlikte kullanma |
| `PERFEPP=0` (Speed Shift EPP) | 9900K HWP destekler; boşta bile performans yönelimi | Sürekli max performans güç tüketimini artırır |
| Core parking off | 9900K'da 16 thread'in tamamını kullanılabilir tutar | Masaüstünde genelde zaten kapalı; önce kontrol et |
| `Win32PrioritySeparation=38` | 9900K gibi çok çekirdekli CPU'da foreground/background quantum dengesi | Win10 client default `2` zaten aynı mod; genelde no-op |
| HT on/off A/B | 9900K'da 8C/16T vs 8C/8T; CS2'de çelişkili sonuçlar | Körlemesine kapatma; D2 benchmark şart |
| `SystemResponsiveness=10` | MMCSS'in arka plan rezervini azaltır | 0 yapma; ses/network thread'lerini aç bırakabilir |

### 2.2 RAM / bellek

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| XMP 4000 CL18 | Mevcut kitin hızı; Z390 IMC için üst sınır | 64 GB'da her silikonda stabil olmayabilir |
| Fallback 3733 CL17 / 3600 CL16 | 4000 hata verirse IMC yükünü düşürür | CL düşürmek her zaman daha iyi değil; voltaj/timing dengesi |
| `tRFC` / `tREFI` sıkılaştırma | DDR4 dual-rank'te latency'ye en çok dokunan alt zamanlamalar | Stabiliteyi bozmadan; TM5/Karhu şart |
| `DisablePagingExecutive=1` | 64 GB RAM'de kernel'in page out olmasını engeller | Etki küçük; pagefile'ı kapatma |
| Pagefile system managed | 64 GB olsa da bazı uygulamalar/anti-cheat pagefile ister | Kapatmak riskli |
| Memory compression açık | 64 GB'da bile bellek baskısında zarar verir | Kapatma |

### 2.3 GPU / NVIDIA

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| Power management = Prefer max performance | RTX 3070'in buy fazında downclock'unu engeller | Global değil, CS2 profiline uygula |
| Undervolt 0.900-0.950 V @ ~1900-1950 MHz | 3070'in boost/termal dengesi; daha tutarlı clock | Silikona göre değişir; stress test |
| Core +100 / Mem +500 MHz | 3070 Ampere için ılımlı başlangıç | Artifact/çökme = geri çek |
| Shader cache Unlimited/10 GB | Source 2 shader compile stutter'ını azaltır | Disable etme; sürücü güncellemesinde sıfırlanır |
| Low Latency Mode / Reflex | CS2'nin Reflex'i ile çakışmaması gerekir | Reflex açıksa driver LLM gereksiz |
| 8 GB VRAM sınırı | 1080p CS2'de VRAM sorunu beklenmez | 1440p/RT açıksa texture ayarları önemli |
| PCIe 3.0 x16 | Z390 + 3070; CS2'de darboğaz değil | ReBAR zorlama |
| HAGS A/B | RTX 3070 + Win10 22H2 destekler | Bazı sistemlerde stutter; ölç |

### 2.4 Anakart / platform

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| Above 4G Decoding = On | RTX 3070'in büyük BAR erişimi için faydalı | ReBAR ile karıştırma |
| Resizable BAR = Off/Auto | Z390 resmî ReBAR desteklemez | Inspector'dan zorlama |
| PCIe ASPM = Off | GPU/NVMe link power saving'i kapatır | Güç tüketimi artar |
| Spread Spectrum = Off | BCLK 100 stabilitesi | Aşırı OC'de dikkat |
| HPET = BIOS default | Zorlama latency'yi bozabilir | `useplatformclock` kullanma |

### 2.5 Windows 10

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| High Performance plan | 9900K fixed 5.0 ile uyumlu | Ultimate Performance isteğe bağlı |
| GameDVR/GameBar off | Arka plan kaydı CPU/GPU/disk kullanır | Game Mode'u ayrı değerlendir |
| FSO off (cs2.exe) | Tam ekran optimizasyonları bazı sistemlerde input/frametime bozar | A/B test; alt-tab davranışı değişebilir |
| GPU preference = High performance | Windows'un cs2.exe'yi 3070'e ataması | Tek GPU varsa etkisi küçük |
| Defender exclusion (CS2) | Steam/CS2 dosya taramasını azaltır | Güvenlik trade-off'u; sadece oyun klasörü |
| SysMain/Search ölçerek | NVMe'de etki tartışmalı | Körlemesine kapatma |
| `PowerThrottlingOff=1` | EcoQoS'un CS2 thread'lerini kısmasını engeller | Pil ömrü/ısı trade-off'u |

### 2.6 Monitör / ağ (koşullu)

| Ayar | Neden bu sistemde anlamlı? | Sınır / not |
|---|---|---|
| fps cap = refresh−3 (G-Sync varsa) | 3070'in CS2'de ürettiği yüksek fps'te frametime tutarlılığı | Monitör Hz'i bilinmiyor |
| G-Sync Fullscreen only | VRR + Reflex + V-Sync kombinasyonu | Monitör desteği bilinmiyor |
| Reflex açık/kapalı | CS2 + NVIDIA driver etkileşimi | Oyun içi ayar; bu proje dokunmuyor |
| NIC power saving off | Ethernet'te jitter'ı azaltır | Wi-Fi ise farklı ayarlar |
| Router SQM/QoS | Bufferbloat'ı azaltır | Router modeli bilinmiyor |

---

## 3. Neden “sisteme özel”?

- **9900K:** P/E çekirdek yok. Windows 11'in “prefer performance cores” mantığı burada geçersiz. 8C/16T ve ring/cache davranışı CS2'nin 1% low'unda belirleyici.
- **Z390:** PCIe 3.0 ve resmî ReBAR yok. RTX 3070'in PCIe 4.0 x16 bağlantısı 3.0 x16'ya düşer; CS2 için ölçülebilir kayıp beklenmez. ReBAR tweak'leri bu platformda riskli.
- **RTX 3070:** 8 GB VRAM ve 220 W sınıfı TGP. 1080p CS2'de genelde GPU değil CPU/RAM sınırı; undervolt, OC'den daha faydalı.
- **64 GB DDR4-4000:** Z390 IMC için yüksek kapasite + yüksek hız. 4000 CL18 stabil olmayabilir; 3733/3600 fallback'i bu yüzden var.
- **Windows 10 22H2:** HAGS/GameDVR/FSO davranışı Win11'den farklı. Ayrıca destek dışı; güvenlik ayrı bir konu.

---

## 4. Varsayımlar ve sınırlar

1. CPU 5.0 GHz all-core **stabil** ve soğutma yeterli kabul edildi.
2. RAM 4000 CL18'in stabil olduğu **doğrulanmadı**; TM5/Karhu sonucu bekleniyor.
3. Monitör **360 Hz** onaylandı; çözünürlük henüz bilinmiyor (genellikle 1080p, doğrula). G-Sync durumu bilinmiyor.
4. CS2'de Reflex'in açık/kapalı olduğu **bilinmiyor**.
5. Ağ: **Ethernet, router ASUS RT-AX82U**.
6. Windows 10 22H2 build 19045 kabul edildi.
7. NVIDIA sürücü sürümü **bilinmiyor**; Game Ready varsayıldı.
8. CS2 Steam üzerinden kurulu kabul edildi.
9. Hyper-V/WSL/VBS kullanımı **bilinmiyor**; kullanılıyorsa VBS kapatma önerisi geçersiz.
10. BIOS'ta XMP dışında agresif OC (BCLK, AVX offset) varsayılmadı.

---

## 5. Doğrulanması gerekenler

- [x] Monitör **360 Hz** onaylandı; çözünürlük bilinmiyor (doğrula)
- [ ] G-Sync / FreeSync uyumluluğu
- [ ] CS2 Reflex açık/kapalı
- [x] RAM düzeni: **2×32 GB** onaylandı; dual-rank mı henüz bilinmiyor
- [ ] 4000 CL18 TM5/Karhu stabil mi
- [ ] CPU 5.0 GHz Vcore/LLC ve sıcaklıklar
- [ ] Ring 4.7 stabil mi
- [ ] HT on/off testi
- [ ] HAGS açık/kapalı testi
- [ ] Ethernet/Wi-Fi ve router modeli
- [ ] Windows 11'e geçiş planı
- [ ] NVIDIA sürücü sürümü

---

---

## 6. Sistem raporu üreteci (Get-Cs2SystemReport.ps1)

`Get-Cs2SystemReport.ps1` read-only bir sistem envanteri üretir: Masaüstü'ne `CS2-SystemReport-<zaman damgası>.md` ve `.json` yazar. Aşağıdaki bu dosyadaki “Doldurulacak / bilinmiyor" yerlerini doğrulayabilir:

- Monitör çözünürluğu ve Hz (fps cap, G-Sync kararı)
- RAM modül düzeni (slot, kapasite, hız, yapılandırılmış hız, dual-rank ipucu)
- NVIDIA sürücü sürümü ve VRAM (nvidia-smi veya WMI)
- NIC modeli, link hızı, DNS ve gelişmiş NIC özellikleri
- Güç planı, HAGS, GameDVR, PowerThrottlingOff gibi Windows ayarlarının gerçek durumu

Raporu üretip `SISTEM-OZELLIKLERI.md`'deki tabloyu doldurduktan sonra bu dosya bir “referans durum" kaydı haline gelir; sonraki BIOS/Windows değişikliklerinde kıyas olarak kullanılabilir.

> Bu dosya, `RAPOR.md` ile birlikte okunmalıdır. Ayarların gerekçeleri ve uygulama sırası raporda; donanım eşleşmesi burada.
