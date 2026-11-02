<#
.SYNOPSIS
    İndirilen mod arşivlerini (çok parçalı .7z, .7z, .zip) açar ve tüm mod paketlerini tek klasörde toplar.

.DESCRIPTION
    7-Zip gerekmez: Windows'un kendi tar.exe'si (libarchive) 7z ve zip okur.
    - name.7z.001, .002 ... parçaları sırayla birleştirilip açılır.
    - Tek parça .7z açılır.
    - Kökünde manifest.sii olan .zip bir moddur (ör. ProMods DLC Support) ve olduğu gibi kopyalanır;
      diğer .zip'ler arşiv sayılıp açılır.
    - Kaynaktaki tek başına duran .scs dosyaları kopyalanır.
    Sonuçta Destination klasöründe sadece .scs / mod .zip dosyaları olur; Install-ModPack.ps1 buna verilir.

.EXAMPLE
    .\tools\Expand-ModArchives.ps1 -Source C:\ETS2Konvoy\indirilenler -Destination C:\ETS2Konvoy\modlar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
)
. "$PSScriptRoot\Ets2Common.ps1"

$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $tar)) { throw "Windows tar.exe bulunamadı: $tar (Windows 10 1803 veya daha yenisi gerekir)" }
if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Path $Destination | Out-Null }
$Destination = (Resolve-Path -LiteralPath $Destination).Path

function Test-ModZip {
    # Kökünde manifest.sii varsa zip'in kendisi bir mod paketidir
    param([string]$Path)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try { return [bool]($zip.Entries | Where-Object { $_.FullName -ieq 'manifest.sii' } | Select-Object -First 1) }
    finally { $zip.Dispose() }
}

function Expand-Archive7 {
    # Arşivi geçici klasöre açar, içindeki mod paketlerini Destination'a taşır
    param([string]$Archive, [string]$Label)
    $tmp = Join-Path $Destination ('_tmp_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "  açılıyor: $Label"
        & $tar -xf $Archive -C $tmp
        if ($LASTEXITCODE -ne 0) { Write-Host "  [X] $Label açılamadı (tar çıkış kodu $LASTEXITCODE). Dosya eksik/bozuk olabilir, tekrar indir." -ForegroundColor Red; return }
        foreach ($f in Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.Extension -in '.scs', '.zip' }) {
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $Destination $f.Name) -Force
            Write-Host "  [+] $($f.Name)" -ForegroundColor Green
        }
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

$files = @(Get-ChildItem -LiteralPath $Source -File)

# Çok parçalı 7z: ad.7z.001, ad.7z.002 ...
$parts = $files | Where-Object { $_.Name -match '^(.+\.7z)\.(\d{3})$' } | Group-Object { $_.Name -replace '\.\d{3}$', '' }
foreach ($g in $parts) {
    $ordered = @($g.Group | Sort-Object Name)
    $nums = @($ordered | ForEach-Object { [int]($_.Name.Substring($_.Name.Length - 3)) })
    $expectedNums = 1..$nums[-1]
    if (Compare-Object $nums $expectedNums) {
        Write-Host "[X] $($g.Name): parça eksik (bulunan: $($nums -join ', ')). Eksik parçayı indir." -ForegroundColor Red
        continue
    }
    Write-Host "$($g.Name): $($ordered.Count) parça birleştiriliyor"
    $joined = Join-Path $Destination $g.Name
    $out = [System.IO.File]::Create($joined)
    try {
        foreach ($p in $ordered) {
            $in = [System.IO.File]::OpenRead($p.FullName)
            try { $in.CopyTo($out) } finally { $in.Dispose() }
        }
    } finally { $out.Dispose() }
    try { Expand-Archive7 $joined $g.Name } finally { Remove-Item -LiteralPath $joined -Force }
}

foreach ($f in $files) {
    if ($f.Name -match '\.7z\.\d{3}$') { continue }
    switch ($f.Extension.ToLowerInvariant()) {
        '.7z' { Expand-Archive7 $f.FullName $f.Name }
        '.zip' {
            if (Test-ModZip $f.FullName) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Destination $f.Name) -Force
                Write-Host "  [+] $($f.Name) (mod zip)" -ForegroundColor Green
            } else { Expand-Archive7 $f.FullName $f.Name }
        }
        '.scs' {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Destination $f.Name) -Force
            Write-Host "  [+] $($f.Name)" -ForegroundColor Green
        }
    }
}

$result = @(Get-ChildItem -LiteralPath $Destination -File | Where-Object { $_.Extension -in '.scs', '.zip' })
Write-Host ''
Write-Host "$($result.Count) mod paketi hazır: $Destination" -ForegroundColor Cyan
Write-Host "Sonraki adım: .\tools\Install-ModPack.ps1 -Source `"$Destination`" -ModSet <host'un modset JSON'u>" -ForegroundColor Cyan
