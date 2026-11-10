# GitHub Actions çalıştırma notu

## Mevcut durum

> **2026-11-10 güncellemesi:** Repo **public** yapıldı. Public olmak release
> indirmesini düzeltti (asset'lar artık anonim HTTP 200 dönüyor) **ama CI
> kilidini kaldırmadı** — kilit **hesap seviyesinde**. Public repo'lar için
> Actions dakikaları ücretsiz olsa da hesap kilidi her şeyi bloklar.
> Aşağıdaki teşhis hâlâ geçerlidir.

Bu depodaki CI iş akışı **GitHub tarafından başlatılamıyor**. Run durumu `startup_failure`
olarak kaydediliyor ve hiçbir job çalışmıyor.

Kök neden kod değil, **hesap durumu**. Başka bir repodaki (AbrekMouse) job
annotation'ı bunu açıkça söylüyor:

```
The job was not started because your account is locked due to a billing issue.
```

Bu, hesabın faturalama nedeniyle kilitlendiğini gösterir. Hesap kilidi
kalktığında bu depodaki CI kendiliğinden çalışacaktır.

## Nasıl doğrulandı?

1. `actionlint` ile `.github/workflows/ci.yml` doğrulandı → **hata yok**.
2. YAML parser ile parse edildi → **geçerli**.
3. 10 `.ps1` dosyasının tamamı PowerShell AST parser'dan geçti → **hata yok**.
4. 27 Pester testi çalıştırıldı → **geçti**.
5. `tests/Verify-ModuleUsage.ps1` → **8/8 script başarılı**.
6. Repo içinde **tek workflow dosyası** (`.github/workflows/ci.yml`) var; başka
   bir bozuk workflow veya `BuildFailed` dosyası **yok** (bu isim GitHub'ın
   parse hatası için ürettiği sentetik bir placeholder'dır).
7. Sorunu izole etmek için repo içine **minimal** bir workflow (`echo ok`)
   eklendi → o da aynı `startup_failure` ile düştü. Yani sorun `ci.yml`'in
   içeriğinde değil, hesap/ortam seviyesinde.

## Çözüm

GitHub'da:

1. <https://github.com/settings/billing> → faturalama durumunu kontrol edin.
2. Ödeme yöntemi ekleyin veya kilit kalkana kadar bekleyin.
3. Kilit kalktığında CI'ı elle tetikleyebilirsiniz:
   **Actions → CI → Run workflow**

## CI ne yapar?

`.github/workflows/ci.yml` iki job içerir:

| Job | İçerik |
|---|---|
| `validate` | Sözdizimi denetimi (tüm `.ps1`), modül içe aktarma testi, PSScriptAnalyzer, Pester testleri, modül kullanım doğrulaması |
| `dry-run` | Tüm scriptleri dry-run modunda çalıştırır (hiçbir ayar değişmez) |

`validate` job'ı **hata** durumunda kırmızıya döner; uyarılar (warning) bloklamaz.

## Yerelde eşdeğer kontrol

CI çalışamazken de aynı kontrolleri bilgisayarınızda yapabilirsiniz:

```powershell
# Sözdizimi
Get-ChildItem *.ps1 | ForEach-Object {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
    if ($e) { "$($_.Name): $($e[0].Message)" } else { "OK $($_.Name)" }
}

# Modül doğrulaması
./tests/Verify-ModuleUsage.ps1

# Pester
Invoke-Pester ./tests
```

> Bu kontrollerin tamamı **değişiklik yapmadan** çalışır.
