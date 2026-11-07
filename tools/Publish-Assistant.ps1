<#
.SYNOPSIS
    Asistanın her güncellemesinden sonra çalıştırılır: sürümü artırır, paketi ve exe'yi üretir, exe'yi masaüstüne koyar.

.DESCRIPTION
    1. assistant\version.json içindeki sürümün son hanesini artırır (0.2.0 → 0.2.1). -Minor: 0.2.5 → 0.3.0, -NoBump: artırmaz.
       versionCode HER ZAMAN bir artar (sürüm metni artmasa bile): karşılaştırmayı
       istemci o sayıyla yapıyor.
    2. New-FriendPackage.ps1 ile dist\arkadas-paketi[.zip] ve dist\ETS2-Mod-Asistanı.exe'yi üretir.
    3. Exe'yi masaüstüne kopyalar (eskisinin üzerine yazar).
    4. -Yayinla verilirse: güncelleme paketini üretip MServer'a koyar (sahadaki
       asistanlar kendilerini oradan günceller).

    Kişisel ayarlar (host adı, modset, def dosyası) repoya girmez; local\yayin-ayarlari.json'dan okunur:
      { "HostName": "<adın>", "ModSet": "modset-<ad>.json", "HostFile": ["original\\promods\\promods-eu-def-v284.scs"],
        "Guide": "docs\\KURULUM.txt", "CompatibilityProfile": "local\\uyumluluk\\promods-161-to-162" }
    Yollar repo köküne göredir.

    ⚠️ CompatibilityProfile, paketin catalog\packs\<pack>.json'u compatibilityProfile
    bildiriyorsa ZORUNLUDUR: New-FriendPackage.ps1 o durumda profil dizini olmadan paket
    üretmeyi reddeder. Bu örnekte eksik olduğu için bir kez şu duruma düşüldü — ayar
    dosyası anahtarı hiç taşımıyordu ve sebebi ancak paket tanımı okununca anlaşıldı.

    ⚠️ Bu anahtarların gösterdiği dosyalar gitignore'dadır (original\, local\): klonla
    GELMEZLER ve git onları yedeklemez. Elde yoksa daha önce dağıtılmış bir exe'nin
    içinden çıkarılabilir; paket exe'ye "paket.zip" adlı gömülü kaynak olarak konuyor.

    ⚠️ MSERVER'A GİDEN PAKET, ARKADAŞ PAKETİ DEĞİLDİR. Arkadaş paketi host'un modset'ini
    ve ProMods def dosyasını taşıyor; o zip herkese açık bir adrese KONMAZ. Sunucuya
    yalnızca asistan programı (asistan\ + araclar\ + Asistan.cmd) gider —
    New-AssistantUpdate.ps1 onu ayrıca üretir ve içeriğini denetler.

.PARAMETER Yayinla
    Güncelleme paketini MServer'a koyar. Bu adım olmadan yeni sürüm yalnızca senin
    masaüstündeki exe'dedir; sahadaki asistanlar onu GÖRMEZ.

.PARAMETER Notes
    Sürüm notu — kullanıcı güncelleme penceresinde bunu görür.

.PARAMETER Optional
    Güncellemeyi ertelenebilir yapar. Varsayılan ZORUNLU.

.PARAMETER SadeceYayin
    Arkadaş paketini ve exe'yi ÜRETME, yalnızca MServer'a güncelleme koy. -Yayinla'yı
    ima eder. Arkadaş paketi host'un kişisel dosyalarını (modset, ProMods def) ister;
    yalnızca bir kod düzeltmesini sahaya göndermek için onlara gerek yok.

.PARAMETER MServerRepo
    MServer deposunun yolu (yayın betikleri orada). Varsayılan: bu deponun yanındaki
    ..\MServer.

.EXAMPLE
    .\tools\Publish-Assistant.ps1

.EXAMPLE
    .\tools\Publish-Assistant.ps1 -Yayinla -Notes "Kendini güncelleme eklendi"
#>
[CmdletBinding()]
param(
    [switch]$Minor,
    [switch]$NoBump,
    [string]$Settings,
    [string]$Desktop = [Environment]::GetFolderPath('Desktop'),
    [switch]$Yayinla,
    [switch]$SadeceYayin,
    [string]$Notes = '',
    [switch]$Optional,
    [string]$MServerRepo
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$inRepo = { param($p) if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $repo $p } }
# Kişisel ayarlar yalnızca ARKADAŞ PAKETİ için gerekli; -SadeceYayin'de aranmaz
# (güncelleme paketi host'un hiçbir dosyasını taşımıyor).
$cfg = $null
if (-not $SadeceYayin) {
    if (-not $Settings) { $Settings = Join-Path $repo 'local\yayin-ayarlari.json' }
    if (-not (Test-Path -LiteralPath $Settings)) { throw "Ayar dosyası yok: $Settings (biçim için: Get-Help $PSCommandPath -Full)" }
    $cfg = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json
}

# 1) Sürüm
$verFile = Join-Path $repo 'assistant\version.json'
$verText = [System.IO.File]::ReadAllText($verFile)
$verJson = $verText | ConvertFrom-Json
$old = $verJson.assistantVersion
$parts = @($old.Split('.') | ForEach-Object { [int]$_ })
if (-not $NoBump) {
    if ($Minor) { $parts[1]++; $parts[2] = 0 } else { $parts[2]++ }
}
$new = $parts -join '.'

# ⚠️ versionCode AYRI ARTAR ve karşılaştırmayı YAPAN sayı budur. İstemci sürüm metnine
# BAKMAZ: "0.3.0 > 0.2.10 mu?" sorusunu metinle cevaplayan her istemci er geç yanlış
# cevap verir. İki alanı tek bir yerden artırmak zorunlu; ayrı ayrı elle güncellenseydi
# biri unutulduğunda yayın sahada SESSİZCE görünmez olurdu (sunucudaki sayı artmaz,
# istemci "güncelim" der).
$oldCode = if ($verJson.PSObject.Properties['versionCode']) { [int]$verJson.versionCode } else { 0 }
$newCode = if ($NoBump) { $oldCode } else { $oldCode + 1 }

if ($new -ne $old) {
    $verText = $verText -replace ('"assistantVersion"\s*:\s*"' + [regex]::Escape($old) + '"'), "`"assistantVersion`":`"$new`""
}
if ($newCode -ne $oldCode) {
    if ($oldCode -gt 0) {
        $verText = $verText -replace ('"versionCode"\s*:\s*' + $oldCode + '\b'), "`"versionCode`":$newCode"
    }
    else {
        # Alan hiç yoksa assistantVersion'ın hemen ardına eklenir.
        $verText = $verText -replace ('("assistantVersion"\s*:\s*"' + [regex]::Escape($new) + '")'), "`$1,`"versionCode`":$newCode"
    }
}
if ($verText -ne [System.IO.File]::ReadAllText($verFile)) {
    [System.IO.File]::WriteAllText($verFile, $verText, (New-Object System.Text.UTF8Encoding $false))
}

# Yazılanı geri oku: regex ile yapılan bir değişikliğin tutmaması sessiz bir hata olurdu.
$check = [System.IO.File]::ReadAllText($verFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
if ($check.assistantVersion -ne $new -or [int]$check.versionCode -ne $newCode) {
    throw "version.json güncellenemedi (beklenen $new / $newCode, dosyada $($check.assistantVersion) / $($check.versionCode))."
}

Write-Host "Sürüm     : $old → $new (versionCode $oldCode → $newCode)" -ForegroundColor Cyan

# 2) Paket + exe
#
# ⚠️ -SadeceYayin bu adımı ATLAR ve bunun pratik bir sebebi var: arkadaş paketi host'un
# KİŞİSEL dosyalarını (modset, ProMods def .scs) gerektiriyor, güncelleme paketi ise
# gerektirmiyor. İkisi tek adıma bağlı kalsaydı, yalnızca bir kod düzeltmesini sahaya
# göndermek için o dosyaların elinde olması gerekirdi — başka bir makinede çalışırken
# ya da def dosyası yokken yayın hiç yapılamazdi.
if ($SadeceYayin) {
    Write-Host 'Arkadaş paketi ve exe atlandı (-SadeceYayin).' -ForegroundColor DarkGray
}
else {

$dist = Join-Path $repo 'dist'
$exe = Join-Path $dist 'ETS2-Mod-Asistanı.exe'
$pkgArgs = @{
    ModSet   = & $inRepo $cfg.ModSet
    HostFile = @($cfg.HostFile | ForEach-Object { & $inRepo $_ })
    HostName = $cfg.HostName
    OutDir   = Join-Path $dist 'arkadas-paketi'
    Exe      = $exe
    Force    = $true
}
if ($cfg.PSObject.Properties['Guide'] -and $cfg.Guide) { $pkgArgs.Guide = & $inRepo $cfg.Guide }
if ($cfg.PSObject.Properties['CompatibilityProfile'] -and $cfg.CompatibilityProfile) { $pkgArgs.CompatibilityProfile = & $inRepo $cfg.CompatibilityProfile }
& (Join-Path $PSScriptRoot 'New-FriendPackage.ps1') @pkgArgs

# 3) Masaüstü
$target = Join-Path $Desktop (Split-Path $exe -Leaf)
Copy-Item -LiteralPath $exe -Destination $target -Force
# Eski adlarla kalmış kopyalar (sadece bizim exe'miz ise) kaldırılır
foreach ($oldName in 'ETS2-Mod-Asistani.exe', 'ETS2-Konvoy-Asistani.exe') {
    $old = Join-Path $Desktop $oldName
    if ((Test-Path -LiteralPath $old) -and (Get-Item -LiteralPath $old).VersionInfo.ProductName -like 'ETS2 * Asistanı') {
        Remove-Item -LiteralPath $old -Force
        Write-Host "Eski kopya kaldırıldı: $old" -ForegroundColor DarkYellow
    }
}
foreach ($oldName in 'ETS2-Mod-Asistani.exe', 'ETS2-Konvoy-Asistani.exe') {
    $old = Join-Path $dist $oldName
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
}
Write-Host "Masaüstü  : $target (sürüm $((Get-Item -LiteralPath $target).VersionInfo.FileVersion))" -ForegroundColor Green

}   # -SadeceYayin değilse: paket + exe + masaüstü

# 4) MServer'a yayın
if ($Yayinla -or $SadeceYayin) {
    if (-not $MServerRepo) { $MServerRepo = Join-Path (Split-Path $repo -Parent) 'MServer' }
    $publisher = Join-Path $MServerRepo 'deploy\Publish-AppRelease.ps1'
    if (-not (Test-Path -LiteralPath $publisher)) {
        throw "MServer yayın betiği bulunamadı: $publisher (-MServerRepo ile yolunu ver)."
    }

    Write-Host ''
    Write-Host 'MServer yayını' -ForegroundColor Cyan

    # ⚠️ Güncelleme paketi BURADA, ayrıca üretiliyor — arkadaş paketi KULLANILMIYOR.
    # Arkadaş paketi host'un modset'ini ve ProMods def dosyasını taşıyor; onu açık bir
    # adrese koymak başkasına ait mod içeriğini yayınlamak olurdu.
    $update = & (Join-Path $PSScriptRoot 'New-AssistantUpdate.ps1') -Force | Select-Object -Last 1

    $publishArgs = @{
        PackagePath             = $update.Path
        Product                 = 'Ets2Asistan'
        Platform                = 'windows'
        VersionName             = $update.VersionName
        VersionCode             = $update.VersionCode
        PackageName             = 'ets2-asistan'
    }
    if ($Notes) { $publishArgs.Notes = $Notes }
    if ($Optional) { $publishArgs.Optional = $true }

    & $publisher @publishArgs

    Write-Host ''
    Write-Host 'Sahadaki asistanlar bu sürümü bir sonraki açılışlarında görecek.' -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host 'Not: Bu sürüm MServer''a KONMADI; sahadaki asistanlar onu görmez.' -ForegroundColor Yellow
    Write-Host '     Yayınlamak icin: .\tools\Publish-Assistant.ps1 -Yayinla -Notes "..."' -ForegroundColor Yellow
}
