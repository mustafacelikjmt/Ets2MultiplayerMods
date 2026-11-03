<#
.SYNOPSIS
    Konvoya katılacak oyuncu için indirme asistanlı paketi oluşturur (klasör + zip).

.DESCRIPTION
    Pakete giren: asistan (assistant\), gerekli araçlar (tools\), host'un modset JSON'u,
    host'tan gelen dosyalar (ör. ProMods def) ve isteğe bağlı rehber metni.
    Başkasına ait mod dosyası pakete KONMAZ; onları oyuncu asistanla kendisi indirir.
    Host dosyaları (def) kişiseldir: paketi sadece konvoy arkadaşına ver.

.EXAMPLE
    .\tools\New-FriendPackage.ps1 -ModSet .\modset-mustafa.json -HostFile .\original\promods\promods-eu-def-v284.scs `
        -HostName <adın> -Guide .\docs\KURULUM.txt -OutDir .\dist\arkadas-paketi -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModSet,
    [string[]]$HostFile = @(),
    [Parameter(Mandatory)][string]$HostName,
    [string]$Pack = 'konvoy-2026-11',
    [string]$PlayerLabel = 'arkadas',
    [string]$Guide,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$assistant = Join-Path $repo 'assistant'
if (-not (Test-Path -LiteralPath (Join-Path $assistant "catalog\packs\$Pack.json"))) { throw "Katalogda '$Pack' paketi yok." }

if (Test-Path -LiteralPath $OutDir) {
    if (-not $Force) { throw "$OutDir zaten var. Üzerine yazmak için -Force." }
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

# Asistan
$asistanOut = Join-Path $OutDir 'asistan'
New-Item -ItemType Directory -Path $asistanOut | Out-Null
foreach ($item in 'Start-Asistan.ps1', 'version.json', 'lib', 'catalog') {
    Copy-Item -LiteralPath (Join-Path $assistant $item) -Destination $asistanOut -Recurse
}
Copy-Item -LiteralPath (Join-Path $assistant 'Asistan.cmd') -Destination $OutDir

# Araçlar
$tools = Join-Path $OutDir 'araclar'
New-Item -ItemType Directory -Path $tools | Out-Null
foreach ($t in 'Ets2Common.ps1', 'Expand-ModArchives.ps1', 'Install-ModPack.ps1', 'Export-ModSet.ps1', 'Compare-ModSet.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $t) -Destination $tools
}

# Host dosyaları
$msName = 'modset-host.json'
Copy-Item -LiteralPath $ModSet -Destination (Join-Path $OutDir $msName)
$incoming = Join-Path $OutDir 'indirilenler'
New-Item -ItemType Directory -Path $incoming | Out-Null
foreach ($h in $HostFile) { Copy-Item -LiteralPath $h -Destination $incoming }
if ($Guide) { Copy-Item -LiteralPath $Guide -Destination (Join-Path $OutDir 'KURULUM.txt') }

$pkg = [ordered]@{ pack = $Pack; host = $HostName; modSet = $msName; playerLabel = $PlayerLabel; created = (Get-Date).ToString('s') }
[System.IO.File]::WriteAllText((Join-Path $OutDir 'paket.json'), ($pkg | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))

$zip = "$OutDir.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OutDir '*') -DestinationPath $zip
Write-Host "Paket hazır: $OutDir" -ForegroundColor Green
Write-Host "Zip       : $zip ($([math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 2)) MB)" -ForegroundColor Green
Write-Host 'Zip''te host''a özel dosya var (def). Sadece konvoy arkadaşına ver, hiçbir yere yükleme.' -ForegroundColor Yellow
