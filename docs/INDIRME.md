# Release indirme

> ✅ Bu depo artık **public**. Release asset'larına
> `releases/download/...` URL'si ile **giriş yapmadan** doğrudan erişilebilir.
>
> *(Bu depo private iken aynı URL'ler 404 döndürüyordu; GitHub'ın private repo
> davranışıydı. Public'e geçişle sorun çözüldü.)*

## Hızlı indirme (tarayıcıdan, giriş gerekmez)

```
https://github.com/Abrek34/CS2-Win10-Optimizer/releases/download/v1.12.1/CS2-Win10-Optimizer-v1.12.1.zip
```

> Bu URL artık **HTTP 200** döndürüyor ve SHA256 değeri
> `6c3f9cab8af6a57c5b36f998f21bafdfba13522d558ba724e36fa564653f8d94`
> ile birebir eşleşiyor (doğrulandı).

## Yine de 404 alırsanız

Eski private dönemden kalma bir bağlantı olabilir. Repo public olduğu için
tarayıcıdan **doğrudan** indirme çalışır. Yine de sorun yaşarsanız
aşağıdaki yöntemlerden birini kullanın.

---

## Yöntem 0 — Tarayıcıdan doğrudan (en kolay)

Public repo olduğu için giriş gerekmez:

```
https://github.com/Abrek34/CS2-Win10-Optimizer/releases/download/v1.12.1/CS2-Win10-Optimizer-v1.12.1.zip
```

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

Beklenen (v1.12.1):
```
6c3f9cab8af6a57c5b36f998f21bafdfba13522d558ba724e36fa564653f8d94
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

## Doğrulanan test kaydı (v1.12.1 — public, anonim indirme)

| Kontrol | Sonuç |
|---|---|
| **Anonim tarayıcı indirmesi** | ✅ **HTTP 200**, 136.520 bayt |
| SHA256SUMS | ✅ `6c3f9cab…` birebir eşleşiyor |
| ZIP bütünlüğü (`unzip -t`) | ✅ hata yok |
| ZIP içeriği | ✅ 26 dosya, `CS2Optimizer.psm1` + `docs/INDIRME.md` dahil |
| Modül import (temiz indirme) | ✅ 37 fonksiyon |
| `Get-Cs2TargetCheck.ps1` | ✅ Markdown + JSON üretti |
| `Get-Cs2AimMatrix.ps1` | ✅ Doğru DPI matrisi |
| İndirilen pakette testler | ✅ **80/80 Pester geçti** |
