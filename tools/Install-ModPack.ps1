<#
.SYNOPSIS
    Bir klasördeki .scs modlarını ETS2 "mod" klasörüne kopyalar ve host'un listesiyle doğrular.

.DESCRIPTION
    Arkadaşın host'tan aldığı (ya da kendi indirdiği) mod dosyalarını kurar.
    -ModSet verilirse (host'un Export-ModSet çıktısı) her dosyanın SHA256'sı host'unkiyle
    karşılaştırılır; uyuşmayan dosya kurulmaz. Sonunda host'ta olup hâlâ eksik olan
    elle kurulacak modlar listelenir. Mevcut dosyaların üzerine yazmak için -Force gerekir.

.EXAMPLE
    .\tools\Install-ModPack.ps1 -Source D:\Indirilenler\konvoy-modlari -ModSet .\modset-mustafa.json

.EXAMPLE
    .\tools\Install-ModPack.ps1 -Source .\original -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$ModSet,
    [switch]$Force
)
. "$PSScriptRoot\Ets2Common.ps1"

$modDir = Join-Path (Get-Ets2DocumentsPath) 'mod'
if (-not (Test-Path -LiteralPath $modDir)) { New-Item -ItemType Directory -Path $modDir | Out-Null }

$expected = @{}
if ($ModSet) {
    $set = Get-Content -LiteralPath $ModSet -Raw | ConvertFrom-Json
    foreach ($m in @($set.Mods | Where-Object { $_.Source -eq 'local' -and $_.Sha256 })) { $expected[$m.File] = $m }
    Write-Host "Host listesi: $($set.Label) ($($expected.Count) elle kurulan mod)" -ForegroundColor Cyan
}

$files = @(Get-ChildItem -LiteralPath $Source -File | Where-Object { $_.Extension -in '.scs', '.zip' })
if (-not $files.Count) { Write-Host "Kaynakta .scs/.zip yok: $Source" -ForegroundColor Yellow }

foreach ($f in $files) {
    $hash = Get-FileSha256 $f.FullName
    $target = Join-Path $modDir $f.Name
    if ($expected.Count) {
        $exp = $expected[$f.Name]
        if (-not $exp) { Write-Host "  [-] $($f.Name): host listesinde yok, atlandı" -ForegroundColor DarkYellow; continue }
        if ($exp.Sha256 -ne $hash) { Write-Host "  [X] $($f.Name): host'unkinden FARKLI dosya, kurulmadı" -ForegroundColor Red; continue }
    }
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileSha256 $target) -eq $hash) { Write-Host "  [=] $($f.Name): zaten kurulu" -ForegroundColor DarkGray; continue }
        if (-not $Force) { Write-Host "  [!] $($f.Name): farklı bir sürüm kurulu. Üzerine yazmak için -Force" -ForegroundColor Yellow; continue }
    }
    if ($PSCmdlet.ShouldProcess($target, "Kopyala $($f.Name)")) {
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        Write-Host "  [+] $($f.Name) kuruldu" -ForegroundColor Green
    }
}

if ($expected.Count) {
    $stillMissing = @($expected.Keys | Where-Object {
            $t = Join-Path $modDir $_
            -not (Test-Path -LiteralPath $t) -or (Get-FileSha256 $t) -ne $expected[$_].Sha256
        })
    Write-Host ''
    if ($stillMissing.Count) {
        Write-Host 'Hâlâ eksik ya da farklı:' -ForegroundColor Red
        $stillMissing | Sort-Object | ForEach-Object { Write-Host "  $_" }
    } else { Write-Host 'Host''un elle kurulan modlarının hepsi birebir aynı şekilde kurulu.' -ForegroundColor Green }
    $ws = @($set.Mods | Where-Object { $_.Source -eq 'workshop' } | Select-Object -ExpandProperty WorkshopId -Unique)
    if ($ws.Count) {
        Write-Host 'Workshop''tan abone olunacaklar:' -ForegroundColor Cyan
        $ws | ForEach-Object { Write-Host "  https://steamcommunity.com/sharedfiles/filedetails/?id=$_" }
    }
}
Write-Host ''
Write-Host 'Son adım: oyunda Mod Yöneticisi''nde modları host''la AYNI SIRADA etkinleştir.' -ForegroundColor Cyan
