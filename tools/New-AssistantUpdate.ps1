<#
.SYNOPSIS
    MServer'a konacak GÜNCELLEME paketini üretir (yalnızca asistan programı).

.DESCRIPTION
    ⚠️ BU PAKET, ARKADAŞ PAKETİ DEĞİLDİR VE OLAMAZ. İkisi farklı şeyler:

      arkadas-paketi.zip (New-FriendPackage.ps1)
        asistan + araclar + HOST'A ÖZEL dosyalar (modset, ProMods def .scs, rehber)
        → yalnızca konvoy arkadaşına elden verilir, HİÇBİR YERE YÜKLENMEZ

      ets2-asistan-<sürüm>.zip (bu betik)
        yalnızca asistan + araclar + Asistan.cmd — program, veri değil
        → MServer'a konur ve herkese açık bir adresten indirilir

    Fark gözden kaçarsa sonucu ciddi: host'un modset'i ve başkasına ait mod içeriği
    (def .scs) açık bir adrese yüklenmiş olurdu. Bu yüzden paketin içeriği
    Copy-AssistantPayload ile ÜRETİLİR (seçilerek), var olan bir klasörden kopyalanmaz.

    Güncelleme birimi neden "program": kullanıcının verisi (indirilenler\, paket.json,
    modset-host.json, asistan-durum.json, uyumluluk\) ona ait ve konvoydan konvoya
    değişiyor. Güncelleyici yalnızca asistan\, araclar\ ve Asistan.cmd'yi değiştirir.

.PARAMETER OutDir
    Çıktı klasörü. Varsayılan: dist\guncelleme

.PARAMETER Force
    Aynı adlı zip varsa üzerine yaz.

.EXAMPLE
    .\tools\New-AssistantUpdate.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'AssistantPayload.ps1')

if (-not $OutDir) { $OutDir = Join-Path $repo 'dist\guncelleme' }

$versionFile = Join-Path $repo 'assistant\version.json'
$version = [IO.File]::ReadAllText($versionFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
$versionName = $version.assistantVersion
if (-not $version.PSObject.Properties['versionCode']) {
    throw "assistant\version.json içinde 'versionCode' yok. Güncelleme karşılaştırması bu sayıyla yapılıyor; eklenmeden yayın yapılamaz."
}
$versionCode = [int]$version.versionCode

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

$zip = Join-Path $OutDir "ets2-asistan-$versionName.zip"
if (Test-Path -LiteralPath $zip) {
    if (-not $Force) { throw "$zip zaten var. Üzerine yazmak için -Force." }
    Remove-Item -LiteralPath $zip -Force
}

$staging = Join-Path ([IO.Path]::GetTempPath()) ('ets2-asistan-paket-' + [guid]::NewGuid().ToString('N'))
try {
    Copy-AssistantPayload -Destination $staging -RepoRoot $repo

    # ⚠️ Son denetim: pakete yalnızca beklenen üst düzey yollar girmiş olmalı. Birisi
    # Copy-AssistantPayload'a host'a özel bir şey eklerse burada yakalanır — sessizce
    # yayınlanmasındansa yayın hiç yapılmasın.
    $allowed = Get-AssistantPayloadNames
    foreach ($item in Get-ChildItem -LiteralPath $staging) {
        if ($allowed -notcontains $item.Name) {
            throw "Güncelleme paketine beklenmeyen bir şey girdi: '$($item.Name)'. Yayın durduruldu."
        }
    }

    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

$item = Get-Item -LiteralPath $zip
$sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Güncelleme paketi hazır" -ForegroundColor Green
Write-Host "  Dosya       : $zip"
Write-Host "  Sürüm       : $versionName (versionCode $versionCode)"
Write-Host "  Boyut       : $([math]::Round($item.Length / 1KB, 1)) KB"
Write-Host "  SHA-256     : $sha"

# Çağıranın (Publish-Assistant.ps1) kullanabilmesi için nesne olarak da döndürülür.
[pscustomobject]@{
    Path        = $zip
    VersionName = $versionName
    VersionCode = $versionCode
    Sha256      = $sha
    SizeBytes   = $item.Length
}
