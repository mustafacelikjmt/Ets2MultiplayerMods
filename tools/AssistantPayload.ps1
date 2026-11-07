# Asistan "programının" tek kaynağı: pakete ve güncellemeye hangi dosyaların girdiği.
#
# ⚠️ BU LİSTE NEDEN TEK YERDE: iki tüketicisi var ve ikisi de aynı şeyi kurmak zorunda —
#   · New-FriendPackage.ps1   ilk kurulum paketini (arkadaşa verilen exe) üretir
#   · New-AssistantUpdate.ps1 MServer'a konan güncelleme paketini üretir
# Listeler ayrı ayrı yazılsaydı biri eksik kalırdı ve belirtisi en kötü biçimde ortaya
# çıkardı: kurulum çalışır, ilk güncellemeden SONRA asistan bir aracı bulamayıp patlar.
# Kullanıcı o noktada "güncelleme bozdu" der ve geri dönecek bir sürümü yoktur.
#
# Buraya yeni bir araç eklemek = tek satır. İki yerde değil.

Set-StrictMode -Version 2.0

# Asistanın kendi dosyaları (assistant\ altından, pakette yine "asistan\" olur).
$script:AssistantItems = @(
    'Start-Asistan.ps1',
    'version.json',
    'lib',
    'catalog',
    'assets'
)

# Asistanın çalışmak için ihtiyaç duyduğu araçlar (tools\ altından, pakette "araclar\").
# ⚠️ Repodaki tools\ klasörünün TAMAMI değil: yayın/bakım betikleri (Publish-*, New-*,
# Export-*, tests\) arkadaşın paketinde işi olmayan şeyler ve bazıları host'a özel.
#
# ⚠️ AssistantPayload.ps1 KENDİSİ de listede ve bu bilinçli: güncelleyici
# (lib\Asistan.Update.ps1) "neyi değiştireceğim" sorusunu Get-AssistantPayloadNames'e
# soruyor. Dosya pakete girmeseydi o liste güncelleyicinin içine ikinci kez yazılırdı —
# tam da bu dosyanın önlemek için var olduğu şey.
$script:AssistantToolItems = @(
    'AssistantPayload.ps1',
    'Ets2Common.ps1',
    'Expand-ModArchives.ps1',
    'Install-ModPack.ps1',
    'Export-ModSet.ps1',
    'Compare-ModSet.ps1',
    'Update-ModCompatibility.ps1',
    'CompatibilityPatch.cs',
    'ProfileModOrder.cs',
    'ProfileModOrder.ps1'
)

function Get-AssistantPayloadNames {
    <#
    .SYNOPSIS
        Güncellemenin DEĞİŞTİRDİĞİ üst düzey yolları döndürür.
    .DESCRIPTION
        Güncelleyici bu adlara bakarak "paketin içinde beklediğim her şey var mı?" diye
        sorar ve yalnızca bunları değiştirir. Kullanıcının verisi (indirilenler\,
        paket.json, modset-host.json, asistan-durum.json) bu listede YOKTUR ve
        güncellemede hiç dokunulmaz.
    #>
    return @('asistan', 'araclar', 'Asistan.cmd')
}

function Copy-AssistantPayload {
    <#
    .SYNOPSIS
        Asistan programını (asistan\ + araclar\ + Asistan.cmd) hedef klasöre kopyalar.
    .PARAMETER Destination
        Hedef klasör. Yoksa oluşturulur.
    .PARAMETER RepoRoot
        Depo kökü. Verilmezse bu betiğin bir üst klasörü.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [string]$RepoRoot
    )
    $ErrorActionPreference = 'Stop'

    if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
    $assistant = Join-Path $RepoRoot 'assistant'
    $tools = Join-Path $RepoRoot 'tools'

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $asistanOut = Join-Path $Destination 'asistan'
    if (Test-Path -LiteralPath $asistanOut) { Remove-Item -LiteralPath $asistanOut -Recurse -Force }
    New-Item -ItemType Directory -Path $asistanOut | Out-Null
    foreach ($item in $script:AssistantItems) {
        $source = Join-Path $assistant $item
        if (-not (Test-Path -LiteralPath $source)) { throw "Asistan dosyası eksik: $source" }
        Copy-Item -LiteralPath $source -Destination $asistanOut -Recurse
    }

    Copy-Item -LiteralPath (Join-Path $assistant 'Asistan.cmd') -Destination $Destination -Force

    $toolsOut = Join-Path $Destination 'araclar'
    if (Test-Path -LiteralPath $toolsOut) { Remove-Item -LiteralPath $toolsOut -Recurse -Force }
    New-Item -ItemType Directory -Path $toolsOut | Out-Null
    foreach ($t in $script:AssistantToolItems) {
        $source = Join-Path $tools $t
        if (-not (Test-Path -LiteralPath $source)) { throw "Araç eksik: $source" }
        Copy-Item -LiteralPath $source -Destination $toolsOut
    }
}
