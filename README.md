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
| `CS2-Desktop-OneClick.ps1` | Aynı baseline'ın daha basit tek tık varyantı. |
| `CS2-Optimize-Baslat.cmd` | PowerShell başlatıcı. |
| `RAPOR.md` | Tüm ayarlar, gerekçeler, uygulama sırası, ölçüm protokolü, yapma listesi. |
| `SISTEM-OZELLIKLERI.md` | Ayarların hangi donanım özelliklerine göre seçildiği. |

---

## Hızlı başlangıç

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
- Registry backup, restore point, transcript, `-Revert`.

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

- **v1.0.0** — İlk sürüm: Windows baseline scriptleri, sistem özellikleri dosyası ve detaylı rapor.

---

## Lisans

Bu depo için henüz bir lisans dosyası eklenmedi. Kullanmadan önce kendi risk değerlendirmenizi yapın.
