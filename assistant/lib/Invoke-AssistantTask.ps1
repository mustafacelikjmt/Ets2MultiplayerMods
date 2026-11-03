<#
.SYNOPSIS
    Asistanın ayrı pencerede çalıştırdığı işler: kurulum (arşivleri aç + mod klasörüne kur) ve kontrol dosyası.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('install', 'export')][string]$Task,
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$ToolsDir,
    [string]$ModSet,
    [string]$Label = 'arkadas',
    [string]$ResultFile
)
$ErrorActionPreference = 'Stop'
try {
    if ($Task -eq 'install') {
        $Host.UI.RawUI.WindowTitle = 'ETS2 Konvoy – Kurulum'
        Write-Host 'Arşivler açılıyor (birkaç dakika sürebilir, pencereyi kapatma)...' -ForegroundColor Cyan
        $modlar = Join-Path $PackageRoot 'modlar'
        & (Join-Path $ToolsDir 'Expand-ModArchives.ps1') -Source (Join-Path $PackageRoot 'indirilenler') -Destination $modlar -NoHint
        Write-Host ''
        Write-Host 'Oyunun mod klasörüne kuruluyor ve host''un dosyalarıyla karşılaştırılıyor...' -ForegroundColor Cyan
        $installArgs = @{ Source = $modlar; Force = $true }
        if ($ModSet) { $installArgs.ModSet = $ModSet }
        if ($ResultFile) { $installArgs.ResultFile = $ResultFile }
        & (Join-Path $ToolsDir 'Install-ModPack.ps1') @installArgs
    } else {
        $Host.UI.RawUI.WindowTitle = 'ETS2 Konvoy – Kontrol dosyası'
        $out = Join-Path $PackageRoot "modset-$Label.json"
        & (Join-Path $ToolsDir 'Export-ModSet.ps1') -Label $Label -OutFile $out
        if ($ResultFile) { [pscustomobject]@{ Ok = $true; File = $out } | ConvertTo-Json | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
    }
} catch {
    Write-Host ''
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
    if ($ResultFile) { [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
}
Write-Host ''
Read-Host 'Bitti. Pencereyi kapatmak için Enter''a bas'
