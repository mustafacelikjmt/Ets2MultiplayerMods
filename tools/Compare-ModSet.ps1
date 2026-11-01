<#
.SYNOPSIS
    İki oyuncunun Export-ModSet.ps1 çıktısını karşılaştırır.

.DESCRIPTION
    Konvoyda sorun çıkaracak farkları listeler: oyun sürümü, harita DLC'leri,
    eksik modlar ve aynı adlı ama içeriği (SHA256) farklı modlar.
    Host'un dosyası -Reference, diğer oyuncunun dosyası -Difference olarak verilir.

.EXAMPLE
    .\tools\Compare-ModSet.ps1 -Reference .\modset-mustafa.json -Difference .\modset-arkadas.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Reference,
    [Parameter(Mandatory)][string]$Difference
)

$ref = Get-Content -LiteralPath $Reference -Raw | ConvertFrom-Json
$dif = Get-Content -LiteralPath $Difference -Raw | ConvertFrom-Json
$problems = 0

function Write-Problem([string]$msg) { $script:problems++; Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Ok([string]$msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }

Write-Host "Host: $($ref.Label)   Oyuncu: $($dif.Label)" -ForegroundColor Cyan

Write-Host 'Oyun sürümü'
if ($ref.GameVersion -eq $dif.GameVersion) { Write-Ok $ref.GameVersion }
else { Write-Problem "Farklı sürüm: $($ref.GameVersion) <> $($dif.GameVersion) (konvoya katılım engellenir)" }

Write-Host 'Harita DLC''leri'
$missingDlc = @($ref.MapDlcs | Where-Object { $dif.MapDlcs -notcontains $_ })
$extraDlc = @($dif.MapDlcs | Where-Object { $ref.MapDlcs -notcontains $_ })
if (-not $missingDlc.Count -and -not $extraDlc.Count) { Write-Ok 'Aynı' }
foreach ($d in $missingDlc) { Write-Problem "$($dif.Label) bu harita DLC'sine sahip değil: $d" }
foreach ($d in $extraDlc) { Write-Host "  [i] Sadece $($dif.Label) sahip: $d" -ForegroundColor DarkYellow }

if ($ref.PSObject.Properties['DlcAppIds'] -and $dif.PSObject.Properties['DlcAppIds']) {
    Write-Host 'Steam DLC''leri (tümü)'
    $missingApp = @($ref.DlcAppIds | Where-Object { $dif.DlcAppIds -notcontains $_ })
    if (-not $missingApp.Count) { Write-Ok "$($dif.Label), host'un tüm DLC'lerine sahip" }
    foreach ($a in $missingApp) {
        # Harita DLC'si değilse konvoyu engellemeyebilir; mod DLC bağımlılığı varsa engeller
        Write-Host "  [!] $($dif.Label) sahip değil: https://store.steampowered.com/app/$a" -ForegroundColor Yellow
    }
}

Write-Host 'Modlar'
function Get-ModKey($m) { if ($m.WorkshopId) { "ws:$($m.WorkshopId)/$($m.File)" } else { "local:$($m.File)" } }
$difByKey = @{}; foreach ($m in @($dif.Mods)) { $difByKey[(Get-ModKey $m)] = $m }
$difByHash = @{}; foreach ($m in @($dif.Mods)) { if ($m.Sha256) { $difByHash[$m.Sha256] = $m } }

foreach ($m in @($ref.Mods)) {
    $key = Get-ModKey $m
    $tag = if ($m.IsMapMod) { '[HARİTA] ' } else { '' }
    $other = $difByKey[$key]
    if (-not $other -and $m.Sha256 -and $difByHash.ContainsKey($m.Sha256)) {
        $other = $difByHash[$m.Sha256]
        Write-Host "  [i] $tag$($m.File): $($dif.Label) tarafında farklı adla var ($($other.File))" -ForegroundColor DarkYellow
        continue
    }
    if (-not $other) { Write-Problem "$tag$($m.File) eksik ($(if ($m.WorkshopId) { "Workshop $($m.WorkshopId)" } else { 'elle kurulacak' }))"; continue }
    if ($m.Sha256 -and $other.Sha256 -and $m.Sha256 -ne $other.Sha256) {
        Write-Problem "$tag$($m.File) içerik farklı (sürüm $($m.PackageVersion) <> $($other.PackageVersion)). Host'taki dosya kopyalanmalı."
        continue
    }
    Write-Ok "$tag$($m.File)"
}

Write-Host ''
Write-Host 'Not: Bu karşılaştırma kurulu dosyalara bakar. Mod Yöneticisi''ndeki AKTİF liste ve SIRA' -ForegroundColor DarkGray
Write-Host 'her iki oyuncuda aynı olmalı; ActiveModLog alanları game.log.txt''den alınmıştır.' -ForegroundColor DarkGray
if ($problems) { Write-Host "$problems sorun bulundu." -ForegroundColor Red; exit 1 }
Write-Host 'Sorun bulunmadı.' -ForegroundColor Green
