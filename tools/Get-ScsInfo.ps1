<#
.SYNOPSIS
    Bir veya daha fazla ETS2 mod paketini (.scs/.zip ya da açılmış klasör) inceler.

.DESCRIPTION
    Biçim (zip / HashFS / klasör), SHA256, manifest.sii alanları, harita modu olup olmadığı
    ve konvoyda çakışma yaratabilecek kritik def dosyalarını gösterir. Dosyalara yazmaz.

.EXAMPLE
    .\tools\Get-ScsInfo.ps1 -Path "$env:USERPROFILE\Documents\Euro Truck Simulator 2\mod\*.scs"

.EXAMPLE
    .\tools\Get-ScsInfo.ps1 -Path .\original\harita.scs -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]]$Path,
    [switch]$NoHash,
    [switch]$Json
)
begin {
    . "$PSScriptRoot\Ets2Common.ps1"
    $results = New-Object System.Collections.Generic.List[object]
}
process {
    foreach ($p in $Path) {
        foreach ($resolved in (Resolve-Path -Path $p -ErrorAction Stop)) {
            $results.Add((Get-ScsInfoObject -Path $resolved.ProviderPath -NoHash:$NoHash))
        }
    }
}
end {
    if ($Json) { $results | ConvertTo-Json -Depth 5; return }
    foreach ($r in $results) {
        Write-Host ''
        Write-Host "== $($r.Name) ==" -ForegroundColor Cyan
        Write-Host ("Biçim        : {0}   Boyut: {1} MB" -f $r.Format, $r.SizeMB)
        if ($r.Sha256) { Write-Host "SHA256       : $($r.Sha256)" }
        Write-Host ("Harita modu  : {0}  (map dosyası: {1}, def dosyası: {2})" -f $(if ($r.IsMapMod) { 'EVET' } else { 'hayır' }), $r.MapFileCount, $r.DefFileCount)
        if ($r.Manifest) {
            $m = $r.Manifest
            if ($m.Encrypted) { Write-Host 'manifest.sii : ŞİFRELİ' -ForegroundColor Yellow }
            else {
                Write-Host "Unit adı     : $($m.UnitName)"
                if ($m.UnitName -and -not $m.UnitName.StartsWith('.')) {
                    Write-Host "  ! Unit adı '.' ile başlamalı (ör. .$($r.Name -replace '\.\w+$','')). Oyun manifesti okuyamayabilir." -ForegroundColor Yellow
                }
                Write-Host "Ad / sürüm   : $($m.DisplayName) / $($m.PackageVersion)"
                Write-Host "Yazar        : $($m.Author)"
                Write-Host "Uyumlu sürüm : $(($m.CompatibleVersions) -join ', ')"
                Write-Host "DLC bağımlılık: $(($m.DlcDependencies) -join ', ')"
                Write-Host "mp_mod_optional: $($m.MpModOptional)"
                if ($r.IsMapMod -and $m.MpModOptional -eq 'true') {
                    Write-Host '  ! Harita modlarında mp_mod_optional yok sayılır; mod konvoyda zorunludur.' -ForegroundColor Yellow
                }
            }
        }
        if ($r.CriticalDefFiles.Count) {
            Write-Host "Kritik def dosyaları ($($r.CriticalDefFiles.Count)):" -ForegroundColor Yellow
            $r.CriticalDefFiles | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }
            if ($r.CriticalDefFiles.Count -gt 25) { Write-Host "  ... (+$($r.CriticalDefFiles.Count - 25))" }
        }
        if ($r.Note) { Write-Host "Not          : $($r.Note)" -ForegroundColor DarkYellow }
    }
}
