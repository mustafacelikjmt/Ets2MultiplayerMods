<#
.SYNOPSIS
    Bir klasördeki .scs modlarını ETS2 "mod" klasörüne kopyalar ve host'un listesiyle doğrular.

.DESCRIPTION
    Arkadaşın host'tan aldığı (ya da kendi indirdiği) mod dosyalarını kurar.
    -ModSet verilirse (host'un Export-ModSet çıktısı) her dosyanın SHA256'sı host'unkiyle
    karşılaştırılır; uyuşmayan dosya kurulmaz. Sonunda host'ta olup hâlâ eksik olan
    elle kurulacak modlar listelenir. Mevcut dosyaların üzerine yazmak için -Force gerekir.
    -AllowUnlisted: host listesinde olmayan dosyalar da kurulur (uyarıyla); listede olup farklı olanlar yine kurulmaz.
    -BackupDir: -Force ile üzerine yazılacak farklı sürüm önce bu klasöre taşınır (silinmez).

.EXAMPLE
    .\tools\Install-ModPack.ps1 -Source D:\Indirilenler\konvoy-modlari -ModSet .\modset-mustafa.json

.EXAMPLE
    .\tools\Install-ModPack.ps1 -Source .\original -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$ModSet,
    [switch]$Force,
    [switch]$AllowUnlisted,
    [string]$BackupDir,
    # Sonucu (kurulan/eksik/farklı dosyalar) JSON olarak yazar; indirme asistanı okur
    [string]$ResultFile
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

$installed = New-Object System.Collections.Generic.List[object]
$different = New-Object System.Collections.Generic.List[string]
$unlisted = New-Object System.Collections.Generic.List[string]
$backedUp = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    $hash = Get-FileSha256 $f.FullName
    $target = Join-Path $modDir $f.Name
    if ($expected.Count) {
        $exp = $expected[$f.Name]
        if (-not $exp) {
            if (-not $AllowUnlisted) { Write-Host "  [-] $($f.Name): host listesinde yok, atlandı" -ForegroundColor DarkYellow; continue }
            Write-Host "  [?] $($f.Name): host listesinde yok, yine de kuruluyor (konvoyda etkinleştirme)" -ForegroundColor DarkYellow
            $unlisted.Add($f.Name)
        } elseif ($exp.Sha256 -ne $hash) { Write-Host "  [X] $($f.Name): host'unkinden FARKLI dosya, kurulmadı" -ForegroundColor Red; $different.Add($f.Name); continue }
    }
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileSha256 $target) -eq $hash) { Write-Host "  [=] $($f.Name): zaten kurulu" -ForegroundColor DarkGray; $installed.Add([pscustomobject]@{ File = $f.Name; Sha256 = $hash }); continue }
        if (-not $Force) { Write-Host "  [!] $($f.Name): farklı bir sürüm kurulu. Üzerine yazmak için -Force" -ForegroundColor Yellow; continue }
    }
    if ($PSCmdlet.ShouldProcess($target, "Kopyala $($f.Name)")) {
        if ($BackupDir -and (Test-Path -LiteralPath $target)) {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
            Move-Item -LiteralPath $target -Destination (Join-Path $BackupDir $f.Name) -Force
            Write-Host "  [~] $($f.Name): eski sürüm yedeğe alındı ($BackupDir)" -ForegroundColor DarkYellow
            $backedUp.Add($f.Name)
        }
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        Write-Host "  [+] $($f.Name) kuruldu" -ForegroundColor Green
        $installed.Add([pscustomobject]@{ File = $f.Name; Sha256 = $hash })
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
if ($ResultFile) {
    # @() dışarıda: if'in çıktısı açılır, boş liste $null olur (StrictMode'da .Count hata verir)
    $missing = @(if ($expected.Count) { $stillMissing | Sort-Object })
    [pscustomobject]@{
        # ToArray: PS 5.1'de boş List'i @() ile hashtable'a koymak "Bağımsız değişken türleri eşleşmiyor" hatası veriyor
        Ok = (-not $missing.Count -and -not $different.Count); Missing = $missing; Different = $different.ToArray(); Unlisted = $unlisted.ToArray()
        Installed = $installed.ToArray(); BackedUp = $backedUp.ToArray(); BackupDir = $(if ($backedUp.Count) { $BackupDir } else { $null })
        Time = (Get-Date).ToString('s')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
}
Write-Host ''
Write-Host 'Son adım: oyunda Mod Yöneticisi''nde modları host''la AYNI SIRADA etkinleştir.' -ForegroundColor Cyan
