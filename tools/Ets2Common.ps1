# Ortak yardımcı fonksiyonlar. Diğer scriptler bu dosyayı dot-source eder:
#   . "$PSScriptRoot\Ets2Common.ps1"
# Hiçbir kullanıcıya özel yol sabit yazılmaz; her şey otomatik bulunur.

Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:Ets2AppId = '227300'

function Get-Ets2DocumentsPath {
    # OneDrive yönlendirmesi dahil gerçek Belgeler klasörü
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $path = Join-Path $docs 'Euro Truck Simulator 2'
    if (Test-Path -LiteralPath $path) { return $path }
    throw "ETS2 belgeler klasörü bulunamadı: $path"
}

function Get-SteamLibraryPaths {
    $steam = $null
    try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) { return @() }
    $steam = $steam -replace '/', '\'
    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if (-not ($libs -contains $p)) { $libs.Add($p) }
        }
    }
    return $libs | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-Ets2InstallPath {
    foreach ($lib in Get-SteamLibraryPaths) {
        $p = Join-Path $lib 'steamapps\common\Euro Truck Simulator 2'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-Ets2WorkshopPaths {
    foreach ($lib in Get-SteamLibraryPaths) {
        $p = Join-Path $lib "steamapps\workshop\content\$script:Ets2AppId"
        if (Test-Path -LiteralPath $p) { $p }
    }
}

function Get-FileSha256 {
    param([string]$Path)
    # Get-FileHash, çağıranın -WhatIf'i açıksa hash hesaplamıyor; .NET ile doğrudan hesaplanır
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).ProviderPath)
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
    finally { $fs.Dispose(); $sha.Dispose() }
}

function Get-ScsFormat {
    # İlk 4 bayta göre arşiv biçimi
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 4
        $n = $fs.Read($buf, 0, 4)
    } finally { $fs.Dispose() }
    if ($n -lt 4) { return 'unknown' }
    $magic = [System.Text.Encoding]::ASCII.GetString($buf)
    switch -CaseSensitive ($magic) {
        "PK$([char]3)$([char]4)" { 'zip' }
        'SCS#' { 'hashfs' }
        default { 'unknown' }
    }
}

function ConvertFrom-ManifestText {
    # manifest.sii içinden konvoyla ilgili alanları çıkarır (basit regex, tam SII parser değil)
    param([string]$Text)
    if ($Text.StartsWith('ScsC')) { return [pscustomobject]@{ Encrypted = $true } }
    $get = {
        param($key)
        $m = [regex]::Match($Text, "(?m)^\s*$key\s*:\s*""?([^""\r\n]*)""?")
        if ($m.Success) { $m.Groups[1].Value.Trim() } else { $null }
    }
    $arr = {
        param($key)
        @([regex]::Matches($Text, "(?m)^\s*$key\[\d*\]\s*:\s*""([^""]*)""") | ForEach-Object { $_.Groups[1].Value })
    }
    $unit = [regex]::Match($Text, '(?m)^\s*mod_package\s*:\s*(\S+)')
    [pscustomobject]@{
        Encrypted          = $false
        UnitName           = if ($unit.Success) { $unit.Groups[1].Value } else { $null }
        DisplayName        = & $get 'display_name'
        PackageVersion     = & $get 'package_version'
        Author             = & $get 'author'
        Categories         = & $arr 'category'
        CompatibleVersions = & $arr 'compatible_versions'
        DlcDependencies    = & $arr 'dlc_dependencies'
        MpModOptional      = & $get 'mp_mod_optional'
    }
}

function Get-ScsEntryNames {
    # zip arşivi veya açılmış klasör için iç dosya listesi ('/' ile, küçük harf)
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\') + '\'
        return Get-ChildItem -LiteralPath $Path -Recurse -File |
            ForEach-Object { $_.FullName.Substring($root.Length).Replace('\', '/').ToLowerInvariant() }
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try { return $zip.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\', '/').ToLowerInvariant() } }
    finally { $zip.Dispose() }
}

function Get-ScsTextEntry {
    param([string]$Path, [string]$Entry)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $f = Join-Path $Path $Entry
        if (Test-Path -LiteralPath $f) { return [System.IO.File]::ReadAllText($f) }
        return $null
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $e = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -ieq $Entry } | Select-Object -First 1
        if (-not $e) { return $null }
        $sr = New-Object System.IO.StreamReader($e.Open())
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $zip.Dispose() }
}

function Get-ScsInfoObject {
    # Tek bir mod paketi (.scs/.zip ya da açılmış klasör) hakkında özet bilgi
    param([string]$Path, [switch]$NoHash)
    $item = Get-Item -LiteralPath $Path
    $isDir = $item.PSIsContainer
    $format = if ($isDir) { 'folder' } else { Get-ScsFormat $Path }

    $entries = @()
    $manifest = $null
    $note = $null
    if ($format -in 'zip', 'folder') {
        try {
            $entries = @(Get-ScsEntryNames $Path)
            $mtext = Get-ScsTextEntry $Path 'manifest.sii'
            if ($mtext) { $manifest = ConvertFrom-ManifestText $mtext } else { $note = 'manifest.sii yok' }
        } catch { $note = "Okunamadı: $($_.Exception.Message)" }
    } elseif ($format -eq 'hashfs') {
        $note = 'HashFS: içerik için SCS Extractor gerekli'
    } else {
        $note = 'Tanınmayan biçim (şifreli olabilir)'
    }

    $mapFiles = @($entries | Where-Object { $_ -like 'map/*' -or $_ -like '*.mbd' })
    $defFiles = @($entries | Where-Object { $_ -like 'def/*' })
    # Konvoyda dünyayı etkileyen kritik def dosyaları (çakışma adayları)
    $criticalDefs = @($defFiles | Where-Object {
        $_ -match '^def/(country|city|company|world|ferry|cargo|economy_data|traffic|climate|weather)' -or
        $_ -match '^def/(country|city|company)\.sii$'
    })

    [pscustomobject]@{
        Name              = $item.Name
        Path              = $item.FullName
        Format            = $format
        SizeMB            = if ($isDir) { $null } else { [math]::Round($item.Length / 1MB, 2) }
        Sha256            = if ($isDir -or $NoHash) { $null } else { Get-FileSha256 $item.FullName }
        IsMapMod          = ($mapFiles.Count -gt 0)
        MapFileCount      = $mapFiles.Count
        DefFileCount      = $defFiles.Count
        CriticalDefFiles  = $criticalDefs
        Manifest          = $manifest
        Note              = $note
    }
}

function Get-Ets2LogInfo {
    # game.log.txt'den sürüm, DLC'ler ve aktif mod satırları
    param([string]$LogPath = (Join-Path (Get-Ets2DocumentsPath) 'game.log.txt'))
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }
    $lines = Get-Content -LiteralPath $LogPath
    $version = $null
    foreach ($l in $lines) {
        $m = [regex]::Match($l, 'Euro Truck Simulator 2 init ver\.([0-9.]+s?)')
        if ($m.Success) { $version = $m.Groups[1].Value; break }
    }
    $dlcs = @($lines | ForEach-Object {
            $m = [regex]::Match($_, '\] (dlc_[a-z0-9_]+)\.scs: Created and validated')
            if ($m.Success) { $m.Groups[1].Value }
        } | Sort-Object -Unique)
    $modLines = @($lines | Where-Object { $_ -match '\[mods\]|\[ufs\] mod pool|\[mod_package_manager\]' } |
        ForEach-Object { ($_ -replace '^\S+\s*:\s*', '').Trim() })
    $errors = @($lines | Where-Object { $_ -match '<ERROR>' } | ForEach-Object { ($_ -replace '^\S+\s*:\s*', '').Trim() } |
        Select-Object -Unique)
    [pscustomobject]@{
        LogPath    = $LogPath
        LogCreated = ($lines | Where-Object { $_ -match 'log created on' } | Select-Object -First 1)
        GameVersion = $version
        Dlcs       = $dlcs
        ModLines   = $modLines
        Errors     = $errors
    }
}

# Bilinen harita DLC paket adları (konvoyda harita eşleşmesi için önemli)
$script:MapDlcNames = @{
    'dlc_east'     = 'Going East!'
    'dlc_north'    = 'Scandinavia'
    'dlc_polar'    = 'Nordic Horizons'
    'dlc_fr'       = 'Vive la France!'
    'dlc_it'       = 'Italia'
    'dlc_balt'     = 'Beyond the Baltic Sea'
    'dlc_balkan_e' = 'Road to the Black Sea'
    'dlc_iberia'   = 'Iberia'
    'dlc_balkan_w' = 'West Balkans'
    'dlc_greece'   = 'Greece'
    'dlc_russia'   = 'Heart of Russia'
}

function Get-Ets2OwnedDlcAppIds {
    # Steam'in kurduğu DLC depoları (appmanifest_227300.acf). Log'daki .scs listesine ek olarak
    # sahiplik kontrolü için.
    foreach ($lib in Get-SteamLibraryPaths) {
        $acf = Join-Path $lib "steamapps\appmanifest_$script:Ets2AppId.acf"
        if (Test-Path -LiteralPath $acf) {
            return @([regex]::Matches((Get-Content -LiteralPath $acf -Raw), '"dlcappid"\s+"(\d+)"') |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        }
    }
    return @()
}
