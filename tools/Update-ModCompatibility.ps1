<#
.SYNOPSIS
    Test edilmiş yerel uyumluluk yamasını uygular; orijinalleri yedekler.
.DESCRIPTION
    Python veya indirme gerekmez. Yalnızca profildeki kaynak SHA256 değerlerini
    kabul eder; çıktıyı test edilmiş SHA256 ile doğrular. Mevcut hedefler atlanır.
    Varsayılan kaynak oyunun mod klasörüdür. Profil/kayıt dosyaları düzenlenmez.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Profile,
    [string]$Source,
    [string]$BackupRoot,
    [string]$ModSet,
    [string]$ResultFile
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ets2Common.ps1"
$staging = $null
$backup = $null
$commitComplete = $false
$moved = New-Object System.Collections.Generic.List[string]
try {
    if (Get-Process eurotrucks2 -ErrorAction SilentlyContinue) { throw 'Önce Euro Truck Simulator 2 oyununu kapat.' }
    $config = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Profile).Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($config.Schema -ne 1 -or $config.GameVersion -ne '1.62') { throw 'Bu uyumluluk profili desteklenmiyor.' }
    $install = Get-Ets2InstallPath
    $version = if ($install) { (Get-Item -LiteralPath (Join-Path $install 'bin\win_x64\eurotrucks2.exe')).VersionInfo.FileVersion } else { (Get-Ets2LogInfo).GameVersion }
    if (-not $version -or $version -notmatch '^1\.62\.') { throw "Bu işlem ETS2 1.62 içindir. Bulunan sürüm: $version" }
    if (-not $Source) { $Source = Join-Path (Get-Ets2DocumentsPath) 'mod' }
    $Source = (Resolve-Path -LiteralPath $Source).Path
    $profileRoot = Split-Path (Resolve-Path -LiteralPath $Profile).Path -Parent
    if (-not $BackupRoot) { $BackupRoot = Join-Path (Split-Path $Source -Parent) 'mod-uyumluluk-yedekleri' }
    $BackupRoot = [IO.Path]::GetFullPath($BackupRoot)
    if ($BackupRoot.Equals($Source, [StringComparison]::OrdinalIgnoreCase) -or $BackupRoot.StartsWith($Source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Yedek klasörü mod klasörünün dışında olmalı.'
    }
    $plans = New-Object System.Collections.Generic.List[object]
    $installed = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]
    $hashes = @{}
    $names = @{}
    foreach ($file in @($config.Files)) {
        if ([IO.Path]::GetFileName($file.File) -cne $file.File -or [IO.Path]::GetFileName($file.Patch) -cne $file.Patch -or $names.ContainsKey($file.File)) { throw 'Geçersiz/tekrarlanan yama dosyası adı.' }
        $names[$file.File] = $true
        $path = Join-Path $Source $file.File
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($file.File); continue }
        Write-Host "Kontrol: $($file.File)"
        $hash = Get-FileSha256 $path
        $hashes[$file.File] = $hash
        if ($hash -ieq $file.PatchedSha256) {
            $installed.Add([pscustomobject]@{ File = $file.File; Sha256 = $hash })
            continue
        }
        if ($hash -ine $file.OriginalSha256 -or (Get-Item -LiteralPath $path).Length -ne $file.OriginalSize) {
            throw "Tanınmayan veya değiştirilmiş mod: $($file.File). Hiçbir dosya değiştirilmedi. Bu yama yalnızca test edilmiş kaynak dosyalar içindir."
        }
        $patch = Join-Path $profileRoot $file.Patch
        if ((Get-FileSha256 $patch) -ine $file.PatchSha256) { throw "Uyumluluk yaması bozuk: $($file.Patch)" }
        $plans.Add($file)
    }
    if ($plans.Count) {
        $need = 0L
        $backupNeed = 0L
        foreach ($file in $plans) { $need += [long]$file.PatchedSize; $backupNeed += [long]$file.OriginalSize }
        $sameDrive = [IO.Path]::GetPathRoot($Source) -eq [IO.Path]::GetPathRoot($BackupRoot)
        if ($sameDrive) { $need += $backupNeed }
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Source))
        if ($drive.AvailableFreeSpace -lt $need + 64MB) { throw "Geçici kopyalar için en az $([math]::Ceiling($need / 1GB)) GB boş alan gerekiyor." }
        if (-not $sameDrive -and (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($BackupRoot))).AvailableFreeSpace -lt $backupNeed + 64MB) { throw 'Yedek sürücüsünde yeterli boş alan yok.' }
        if (-not ('Ets2Mods.CompatibilityPatch' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CompatibilityPatch.cs') }
        # Same-volume staging permits atomic per-file replacement; originals are
        # copied to backup before any replacement, including cross-volume backups.
        $staging = Join-Path (Split-Path $Source -Parent) ('.ets2-uyumluluk-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging | Out-Null
        foreach ($file in $plans) {
            Write-Host "Hazırlanıyor: $($file.File)"
            $target = Join-Path $staging $file.File
            [Ets2Mods.CompatibilityPatch]::Apply((Join-Path $Source $file.File), (Join-Path $profileRoot $file.Patch), $target, [long]$file.PatchedSize)
            if ((Get-FileSha256 $target) -ine $file.PatchedSha256) { throw "Yama sonucu doğrulanamadı: $($file.File). Kurulu dosyalar değiştirilmedi." }
        }
        $backup = Join-Path $BackupRoot ((Get-Date -Format 'yyyy-MM-dd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        foreach ($file in $plans) {
            $original = Join-Path $Source $file.File
            Copy-Item -LiteralPath $original -Destination (Join-Path $backup $file.File)
            if ((Get-FileSha256 (Join-Path $backup $file.File)) -ine $file.OriginalSha256) { throw 'Yedek doğrulanamadı; kurulu dosyalar değiştirilmedi.' }
        }
        @('ETS2 Mod Asistanı – orijinal mod yedekleri.', 'Geri almak için oyunu ve asistanı kapat; bu dosyaları aşağıdaki mod klasörüne kopyala.', $Source) |
            Set-Content -LiteralPath (Join-Path $backup 'GERİ-YÜKLEME.txt') -Encoding UTF8
        if (Get-Process eurotrucks2 -ErrorAction SilentlyContinue) { throw 'Oyun işlem sırasında açıldı. Dosyalar değiştirilmedi; oyunu kapatıp tekrar dene.' }
        # Originals must still match after long-running staging/backup work.
        foreach ($file in $plans) {
            if ((Get-FileSha256 (Join-Path $Source $file.File)) -ine $file.OriginalSha256) { throw 'İşlem sırasında bir kaynak dosya değişti; işlem iptal edildi.' }
        }
        try {
            foreach ($file in $plans) {
                $path = Join-Path $Source $file.File
                $rollback = Join-Path $staging ($file.File + '.original')
                [IO.File]::Move($path, $rollback)
                $moved.Add($file.File)
                [IO.File]::Move((Join-Path $staging $file.File), $path)
                $hashes[$file.File] = $file.PatchedSha256
                $installed.Add([pscustomobject]@{ File = $file.File; Sha256 = $file.PatchedSha256 })
            }
            $commitComplete = $true
        } catch {
            foreach ($name in $moved) {
                $path = Join-Path $Source $name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
                [IO.File]::Move((Join-Path $staging ($name + '.original')), $path)
            }
            throw
        }
    }
    if ($ModSet) {
        $set = [IO.File]::ReadAllText($ModSet, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($file in @($set.Mods | Where-Object { $_.Source -eq 'local' })) {
            if ($names.ContainsKey($file.File)) { continue }
            $path = Join-Path $Source $file.File
            if ((Test-Path -LiteralPath $path) -and (Get-FileSha256 $path) -ieq $file.Sha256) {
                $installed.Add([pscustomobject]@{ File = $file.File; Sha256 = $file.Sha256 })
            }
        }
    }
    $result = [pscustomobject]@{ Ok = $true; Updated = @($plans | ForEach-Object { $_.File }); Installed = $installed.ToArray(); Missing = $missing.ToArray(); BackupDir = $backup; Profile = $config.Id; GameVersion = $version }
    if ($ResultFile) { $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
    $result
} catch {
    if ($ResultFile) { [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message; BackupDir = $backup } | ConvertTo-Json | Set-Content -LiteralPath $ResultFile -Encoding UTF8 }
    throw
} finally {
    if ($staging -and (Test-Path -LiteralPath $staging)) {
        # Never erase rollback originals if rollback itself failed.
        $remaining = @(Get-ChildItem -LiteralPath $staging -Filter '*.original' -File)
        if ($commitComplete -or -not $remaining.Count) {
            $resolvedStage = [IO.Path]::GetFullPath($staging)
            $expectedParent = [IO.Path]::GetFullPath((Split-Path $Source -Parent)).TrimEnd('\') + '\'
            if ($resolvedStage.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedStage).StartsWith('.ets2-uyumluluk-')) {
                Remove-Item -LiteralPath $resolvedStage -Recurse -Force
            }
        }
    }
}
