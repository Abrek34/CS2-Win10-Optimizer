# Release indirme — private repo kuralları

> ⚠️ Bu depo **private**. Bu yüzden release asset'larına
> `releases/download/...` URL'si ile **giriş yapmadan** erişilemez ve
> **404** döner. Bu bir hata değil, GitHub'ın private repo davranışı.

---

## Hızlı kontrol

Tarayıcıdan şu URL'yi açtığınızda **404** görürseniz panik yapmayın:

```
https://github.com/Abrek34/CS2-Win10-Optimizer/releases/download/v1.12.0/CS2-Win10-Optimizer-v1.12.0.zip
```

Bu normaldir. Aşağıdaki yöntemlerden birini kullanın.

---

## Yöntem 1 — GitHub arayüzü (en kolay)

1. https://github.com/Abrek34/CS2-Win10-Optimizer/releases adresine gidin
2. **Giriş yapın** (sağ üstteki Sign in)
3. İlgili sürümün **Assets** bölümünden ZIP'i indirin

## Yöntem 2 — GitHub CLI (otomatik)

```bash
# gh kurulu ve giriş yapılmış olmalı
gh auth login

# Son sürümün asset'ını indir
gh release download --repo Abrek34/CS2-Win10-Optimizer --pattern '*.zip' --dir .

# SHA256 dogrulama
gh release download --repo Abrek34/CS2-Win10-Optimizer --pattern 'SHA256SUMS' --dir .
sha256sum -c SHA256SUMS
```

## Yöntem 3 — API (script/otomasyon için)

```bash
REPO=Abrek34/CS2-Win10-Optimizer
TAG=v1.12.0

AID=$(gh api repos/$REPO/releases/tags/$TAG --jq '.assets[] | select(.name | endswith(".zip")) | .id')
gh api "repos/$REPO/releases/assets/$AID" -H 'Accept: application/octet-stream' > CS2-Win10-Optimizer-$TAG.zip
```

## Yöntem 4 — Doğrudan clone (kaynak)

```bash
git clone https://github.com/Abrek34/CS2-Win10-Optimizer.git
cd CS2-Win10-Optimizer
```

> Repo private olduğu için clone da kimlik doğrulama ister
> (`git clone` https://token@github.com/... veya SSH key).

---

## Doğrulama

İndirdikten sonra **mutlaka** SHA256 kontrolü yapın:

```bash
sha256sum -c SHA256SUMS
# veya Windows PowerShell:
Get-FileHash .\CS2-Win10-Optimizer-v1.12.0.zip -Algorithm SHA256
```

Beklenen (v1.12.0):
```
8d628c9bdfa2da225101463f9275d38dbbf1b3d01834da4488472fca2ac939a8
```

---

## İndirdikten sonra

ZIP'i açın ve **tüm dosyaları aynı klasörde** tutun:

```
CS2-Win10-Optimizer-v1.12.0/
├── CS2Optimizer.psm1          <-- ORTAK MODUL, silmeyin
├── CS2-Windows10-Optimize.ps1
├── Get-Cs2TargetCheck.ps1
├── Get-Cs2Benchmark.ps1
├── ...
└── docs/
```

`CS2Optimizer.psm1` dosyasını silerseniz scriptler yine çalışır (graceful
fallback) ama bazı yardımcı fonksiyonlar eksik kalır — bu yüzden **silmeyin**.

### Hızlı başlangıç

```powershell
# 1) Hedefe ne kadar uzaktayız? (read-only, yönetici gerektirmez)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2TargetCheck.ps1

# 2) Baseline ölçümü (CS2 açıkken çalıştır)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Cs2Benchmark.ps1 -Label baseline

# 3) Bir değişiklik uygula (yönetici PowerShell)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Apply

# 4) Geri al
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CS2-Windows10-Optimize.ps1 -Revert
```

---

## Doğrulanan test kaydı (v1.12.0)

| Kontrol | Sonuç |
|---|---|
| GitHub API'de repo içeriği | ✅ 25 dosya + klasörler |
| Release asset sayısı | ✅ 2 (ZIP + SHA256SUMS) |
| `gh api` ile indirme | ✅ 131 KB, ZIP bütünlüğü doğru |
| ZIP içeriği ↔ repo | ✅ 25/25 dosya byte-byte aynı |
| Modül import (temiz indirme) | ✅ 37 fonksiyon |
| `Get-Cs2TargetCheck.ps1` çalıştırma | ✅ Markdown + JSON üretildi |
| `Get-Cs2AimMatrix.ps1` çalıştırma | ✅ Doğru DPI matrisi |
| SHA256SUMS | ✅ `8d628c9b…` eşleşiyor |
