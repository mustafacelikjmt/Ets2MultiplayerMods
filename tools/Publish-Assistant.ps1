<#
.SYNOPSIS
    Asistanın her güncellemesinden sonra çalıştırılır: sürümü artırır, paketi ve exe'yi üretir, exe'yi masaüstüne koyar.

.DESCRIPTION
    1. assistant\version.json içindeki sürümün son hanesini artırır (0.2.0 → 0.2.1). -Minor: 0.2.5 → 0.3.0, -NoBump: artırmaz.
    2. New-FriendPackage.ps1 ile dist\arkadas-paketi[.zip] ve dist\ETS2-Mod-Asistanı.exe'yi üretir.
    3. Exe'yi masaüstüne kopyalar (eskisinin üzerine yazar).

    Kişisel ayarlar (host adı, modset, def dosyası) repoya girmez; local\yayin-ayarlari.json'dan okunur:
      { "HostName": "<adın>", "ModSet": "modset-<ad>.json", "HostFile": ["original\\promods\\promods-eu-def-v284.scs"],
        "Guide": "docs\\KURULUM.txt" }
    Yollar repo köküne göredir.

.EXAMPLE
    .\tools\Publish-Assistant.ps1
#>
[CmdletBinding()]
param(
    [switch]$Minor,
    [switch]$NoBump,
    [string]$Settings,
    [string]$Desktop = [Environment]::GetFolderPath('Desktop')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Settings) { $Settings = Join-Path $repo 'local\yayin-ayarlari.json' }
if (-not (Test-Path -LiteralPath $Settings)) { throw "Ayar dosyası yok: $Settings (biçim için: Get-Help $PSCommandPath -Full)" }
$cfg = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json
$inRepo = { param($p) if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $repo $p } }

# 1) Sürüm
$verFile = Join-Path $repo 'assistant\version.json'
$verText = [System.IO.File]::ReadAllText($verFile)
$old = ($verText | ConvertFrom-Json).assistantVersion
$parts = @($old.Split('.') | ForEach-Object { [int]$_ })
if (-not $NoBump) {
    if ($Minor) { $parts[1]++; $parts[2] = 0 } else { $parts[2]++ }
}
$new = $parts -join '.'
if ($new -ne $old) {
    $verText = $verText -replace ('"assistantVersion"\s*:\s*"' + [regex]::Escape($old) + '"'), "`"assistantVersion`":`"$new`""
    [System.IO.File]::WriteAllText($verFile, $verText, (New-Object System.Text.UTF8Encoding $false))
}
Write-Host "Sürüm     : $old → $new" -ForegroundColor Cyan

# 2) Paket + exe
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
