<#
.SYNOPSIS
    Asistanın ayrı pencerede çalıştırdığı işler: kurulum (arşivleri aç + mod klasörüne kur),
    sürükle-bırak ile gelen dosyaları kurma ve kontrol dosyası.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('install', 'add', 'export', 'compat', 'profile', 'restoreprofile')][string]$Task,
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$ToolsDir,
    [string]$ModSet,
    [string]$Label = 'arkadas',
    # add: { Files = [...], HostFiles = [...] } içeren JSON
    [string]$FileList,
    [string]$ResultFile,
    [string]$CompatibilityProfile,
    [switch]$NoPause,
    [string]$ProfilePath,
    [string]$ProfileBackup
)
$ErrorActionPreference = 'Stop'
# Üzerine yazılacak eski sürümler buraya taşınır (sadece gerekirse oluşur)
$oldVersions = Join-Path $PackageRoot ("yedek-modlar\{0:yyyy-MM-dd_HHmmss}_eski-surumler" -f (Get-Date))
try {
    if ($Task -in 'profile','restoreprofile') {
        . (Join-Path $ToolsDir 'Ets2Common.ps1')
        $result = if ($Task -eq 'profile') { Set-Ets2ProfileModOrder -ProfilePath $ProfilePath -ModSet $ModSet -BackupRoot (Join-Path $PackageRoot 'yedek-profiller') } else { Restore-Ets2ModProfile -BackupDir $ProfileBackup }
        if ($ResultFile) { $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
    } elseif ($Task -eq 'compat') {
        if (-not $CompatibilityProfile) { throw 'Uyumluluk profili pakette yok.' }
        $compatArgs = @{ Profile = $CompatibilityProfile; BackupRoot = (Join-Path $PackageRoot 'yedek-modlar\uyumluluk'); ResultFile = $ResultFile }
        if ($ModSet) { $compatArgs.ModSet = $ModSet }
        & (Join-Path $ToolsDir 'Update-ModCompatibility.ps1') @compatArgs | Out-Null
    } elseif ($Task -eq 'add') {
        $Host.UI.RawUI.WindowTitle = 'ETS2 Mod Asistanı – Bırakılan dosyalar kuruluyor'
        $list = [System.IO.File]::ReadAllText($FileList, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $incoming = Join-Path $PackageRoot 'indirilenler'
        $files = @{}
        $ignored = New-Object System.Collections.Generic.List[string]
        foreach ($p in @($list.Files)) {
            $f = Get-Item -LiteralPath $p
            if ($f.Name -match '\.7z\.\d{3}$' -or $f.Extension -in '.7z', '.rar', '.zip', '.scs') { $files[$f.FullName] = $f }
            else { $ignored.Add($f.Name) }
        }
        # Çok parçalı arşiv: eksik parçalar aynı klasörde ya da asistanın indirilenler klasöründe olabilir
        $missingParts = New-Object System.Collections.Generic.List[string]
        $bases = @($files.Values | Where-Object { $_.Name -match '^(.+\.7z)\.\d{3}$' } | ForEach-Object { $_.Name -replace '\.\d{3}$', '' } | Sort-Object -Unique)
        foreach ($b in $bases) {
            $dropped = @($files.Values | Where-Object { $_.Name -like "$b.*" })
            foreach ($dir in @($dropped | ForEach-Object { $_.DirectoryName }) + $incoming | Sort-Object -Unique) {
                foreach ($s in @(Get-ChildItem -LiteralPath $dir -File -Filter "$b.*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.\d{3}$' })) {
                    if (-not @($files.Values | Where-Object { $_.Name -eq $s.Name }).Count) { $files[$s.FullName] = $s }
                }
            }
            $group = @($files.Values | Where-Object { $_.Name -like "$b.*" })
            $nums = @($group | ForEach-Object { [int]($_.Name.Substring($_.Name.Length - 3)) } | Sort-Object)
            # Kaç parça olduğu tek parçadan anlaşılmaz; katalog biliyorsa ondan
            $last = $nums[-1]
            $known = if ($list.PSObject.Properties['PartCounts'] -and $list.PartCounts.PSObject.Properties[$b]) { $list.PartCounts.$b }
            if ($known -and [int]$known -gt $last) { $last = [int]$known }
            $absent = @(1..$last | Where-Object { $nums -notcontains $_ })
            if ($absent.Count) {
                # Eksik parça varken açılamaz; elimizdekiler sonraki sefere indirilenler'de dursun
                foreach ($g in $dropped) {
                    $t = Join-Path $incoming $g.Name
                    if ($g.FullName -ne $t -and -not (Test-Path -LiteralPath $t)) { Copy-Item -LiteralPath $g.FullName -Destination $t }
                }
                $missingParts.Add("$b (eksik parça: $(($absent | ForEach-Object { '{0:000}' -f $_ }) -join ', '))")
                foreach ($g in $group) { $files.Remove($g.FullName) }
            }
        }
        foreach ($h in @($list.HostFiles)) { if (Test-Path -LiteralPath $h) { $files[(Get-Item -LiteralPath $h).FullName] = Get-Item -LiteralPath $h } }

        $staging = Join-Path $PackageRoot ('_kurulum_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            Write-Host 'Dosyalar açılıyor (büyük arşivler birkaç dakika sürebilir, pencereyi kapatma)...' -ForegroundColor Cyan
            if ($files.Count) { & (Join-Path $ToolsDir 'Expand-ModArchives.ps1') -Path @($files.Keys) -Destination $staging -NoHint }
            else { New-Item -ItemType Directory -Path $staging | Out-Null }
            if ($CompatibilityProfile) {
                & (Join-Path $ToolsDir 'Update-ModCompatibility.ps1') -Profile $CompatibilityProfile -Source $staging -BackupRoot $oldVersions | Out-Null
            }
            Write-Host ''
            Write-Host 'Oyunun mod klasörüne kuruluyor...' -ForegroundColor Cyan
            $installArgs = @{ Source = $staging; Force = $true; AllowUnlisted = $true; BackupDir = $oldVersions }
            if ($ModSet) { $installArgs.ModSet = $ModSet }
            if ($ResultFile) { $installArgs.ResultFile = $ResultFile }
            & (Join-Path $ToolsDir 'Install-ModPack.ps1') @installArgs
        } finally {
            $stageFull = [IO.Path]::GetFullPath($staging)
            $packageFull = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\') + '\'
            if ($stageFull.StartsWith($packageFull, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($stageFull).StartsWith('_kurulum_')) {
                Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if ($missingParts.Count) {
            Write-Host ''
            Write-Host 'Parçası eksik arşivler (eldeki parçalar saklandı, eksikleri de bırakınca kurulur):' -ForegroundColor Yellow
            $missingParts | ForEach-Object { Write-Host "  $_" }
        }
        if ($ResultFile) {
            $res = if (Test-Path -LiteralPath $ResultFile) { Get-Content -LiteralPath $ResultFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{ Ok = $true } }
            $res | Add-Member -NotePropertyName MissingParts -NotePropertyValue $missingParts.ToArray() -Force
            $res | Add-Member -NotePropertyName Ignored -NotePropertyValue $ignored.ToArray() -Force
            $res | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
        }
    } elseif ($Task -eq 'install') {
        $Host.UI.RawUI.WindowTitle = 'ETS2 Mod Asistanı – Kurulum'
        Write-Host 'Arşivler açılıyor (birkaç dakika sürebilir, pencereyi kapatma)...' -ForegroundColor Cyan
        $modlar = Join-Path $PackageRoot 'modlar'
        & (Join-Path $ToolsDir 'Expand-ModArchives.ps1') -Source (Join-Path $PackageRoot 'indirilenler') -Destination $modlar -NoHint
        if ($CompatibilityProfile) {
            & (Join-Path $ToolsDir 'Update-ModCompatibility.ps1') -Profile $CompatibilityProfile -Source $modlar -BackupRoot $oldVersions | Out-Null
        }
        Write-Host ''
        Write-Host 'Oyunun mod klasörüne kuruluyor ve host''un dosyalarıyla karşılaştırılıyor...' -ForegroundColor Cyan
        $installArgs = @{ Source = $modlar; Force = $true; BackupDir = $oldVersions }
        if ($ModSet) { $installArgs.ModSet = $ModSet }
        if ($ResultFile) { $installArgs.ResultFile = $ResultFile }
        & (Join-Path $ToolsDir 'Install-ModPack.ps1') @installArgs
    } else {
        $Host.UI.RawUI.WindowTitle = 'ETS2 Mod Asistanı – Kontrol dosyası'
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
if (-not $NoPause) { Read-Host 'Bitti. Pencereyi kapatmak için Enter''a bas' }
