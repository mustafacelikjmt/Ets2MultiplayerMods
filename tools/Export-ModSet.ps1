<#
.SYNOPSIS
    Bu bilgisayardaki ETS2 kurulumunun konvoyla ilgili "parmak izini" çıkarır.

.DESCRIPTION
    Oyun sürümü, sahip olunan DLC'ler, Workshop modları ve elle kurulan modları (SHA256 ile)
    tek bir JSON dosyasına yazar. Konvoydaki her oyuncu bunu çalıştırır, dosyalar
    Compare-ModSet.ps1 ile karşılaştırılır.

    Gizlilik: JSON'a kullanıcı adı, klasör yolu veya Steam kimliği YAZILMAZ;
    sadece dosya adları, Workshop öğe numaraları, hash'ler ve sürüm bilgisi yazılır.

.EXAMPLE
    .\tools\Export-ModSet.ps1 -Label mustafa
    # -> .\modset-mustafa.json
#>
[CmdletBinding()]
param(
    [string]$Label = $env:USERNAME,
    [string]$OutFile,
    [switch]$IncludeAllDlcs
)
. "$PSScriptRoot\Ets2Common.ps1"

if (-not $OutFile) { $OutFile = Join-Path (Get-Location) "modset-$Label.json" }

$docs = Get-Ets2DocumentsPath
$log = Get-Ets2LogInfo

function ConvertTo-ModRecord {
    param($info, [string]$Source, [string]$WorkshopId)
    [pscustomobject]@{
        Source             = $Source
        WorkshopId         = $WorkshopId
        File               = $info.Name
        Format             = $info.Format
        SizeMB             = $info.SizeMB
        Sha256             = $info.Sha256
        IsMapMod           = $info.IsMapMod
        DisplayName        = if ($info.Manifest -and -not $info.Manifest.Encrypted) { $info.Manifest.DisplayName } else { $null }
        PackageVersion     = if ($info.Manifest -and -not $info.Manifest.Encrypted) { $info.Manifest.PackageVersion } else { $null }
        CompatibleVersions = if ($info.Manifest -and -not $info.Manifest.Encrypted) { $info.Manifest.CompatibleVersions } else { @() }
    }
}

$mods = New-Object System.Collections.Generic.List[object]

# Elle kurulan modlar
$modDir = Join-Path $docs 'mod'
if (Test-Path -LiteralPath $modDir) {
    Get-ChildItem -LiteralPath $modDir | Where-Object { $_.PSIsContainer -or $_.Extension -in '.scs', '.zip' } | ForEach-Object {
        Write-Host "Okunuyor: mod\$($_.Name)"
        $mods.Add((ConvertTo-ModRecord (Get-ScsInfoObject -Path $_.FullName) 'local' $null))
    }
}

# Workshop modları
foreach ($ws in @(Get-Ets2WorkshopPaths)) {
    Get-ChildItem -LiteralPath $ws -Directory | ForEach-Object {
        $id = $_.Name
        $pkgs = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.scs, *.zip)
        if (-not $pkgs.Count) {
            # Workshop yapısı: versions.sii + sürüm klasörleri (açılmış hâlde)
            $pkgs = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter manifest.sii | ForEach-Object { $_.Directory })
        }
        foreach ($pkg in $pkgs) {
            Write-Host "Okunuyor: workshop\$id\$($pkg.Name)"
            $mods.Add((ConvertTo-ModRecord (Get-ScsInfoObject -Path $pkg.FullName) 'workshop' $id))
        }
    }
}

$dlcs = if ($log) { $log.Dlcs } else { @() }
$mapDlcs = @($dlcs | Where-Object { $script:MapDlcNames.ContainsKey($_) })

$result = [pscustomobject]@{
    Label        = $Label
    CreatedAt    = (Get-Date).ToString('s')
    GameVersion  = if ($log) { $log.GameVersion } else { $null }
    MapDlcs      = $mapDlcs
    DlcAppIds    = @(Get-Ets2OwnedDlcAppIds)
    Dlcs         = if ($IncludeAllDlcs) { $dlcs } else { $null }
    ActiveModLog = if ($log) { $log.ModLines } else { @() }
    Mods         = $mods
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Host ''
Write-Host "Oyun sürümü : $($result.GameVersion)"
Write-Host "Harita DLC  : $(($mapDlcs | ForEach-Object { $script:MapDlcNames[$_] }) -join ', ')"
Write-Host "Steam DLC   : $($result.DlcAppIds.Count) adet"
Write-Host "Mod sayısı  : $($mods.Count) (harita modu: $(@($mods | Where-Object IsMapMod).Count))"
Write-Host "Yazıldı     : $OutFile" -ForegroundColor Green
