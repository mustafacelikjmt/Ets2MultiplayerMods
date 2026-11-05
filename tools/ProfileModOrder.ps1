# Ets2Common.ps1 ile birlikte yüklenir. Profil keşfi ve yalnızca active_mods düzenlemesi.
function Get-Ets2ModProfiles {
    $roots = New-Object System.Collections.Generic.List[object]
    $docs = $null
    try { $docs = Get-Ets2DocumentsPath } catch { }
    if ($docs) { foreach ($kind in 'profiles','steam_profiles') { $roots.Add(@{ Path = (Join-Path $docs $kind); Cloud = ($kind -eq 'steam_profiles') }) } }
    if (-not $env:ETS2KONVOY_DOCS) {
        $steamInfo = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        $steam = if ($steamInfo -and $steamInfo.PSObject.Properties['SteamPath']) { $steamInfo.SteamPath } else { $null }
        if ($steam) {
            foreach ($account in @(Get-ChildItem -LiteralPath (Join-Path $steam 'userdata') -Directory -ErrorAction SilentlyContinue)) {
                foreach ($kind in 'profiles','steam_profiles') { $roots.Add(@{ Path = (Join-Path $account.FullName "227300/remote/$kind"); Cloud = $true }) }
            }
        }
    }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $root.Path -Directory)) {
            $path = Join-Path $dir.FullName 'profile.sii'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $name = $dir.Name
            if ($name -match '^(?:[0-9a-fA-F]{2})+$') {
                $bytes = New-Object byte[] ($name.Length / 2)
                for ($i=0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($name.Substring($i*2,2),16) }
                $name = [Text.Encoding]::UTF8.GetString($bytes)
            }
            [pscustomobject]@{ Name=$name; Path=$path; Cloud=$root.Cloud; Display=("$name ($(if($root.Cloud){'Steam Cloud'}else{'Yerel'}))") }
        }
    }
}

function Set-Ets2ProfileModOrder {
    param([string]$ProfilePath,[string]$ModSet,[string]$BackupRoot)
    if (Get-Process eurotrucks2 -ErrorAction SilentlyContinue) { throw 'Önce oyunu kapat.' }
    $profile = @(Get-Ets2ModProfiles | Where-Object { $_.Path -eq $ProfilePath }) | Select-Object -First 1
    if (-not $profile) { throw 'Profil bulunamadı. Oyunda önce bir profil oluşturup oyunu kapat.' }
    if ($profile.Cloud -and (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Steam Cloud profili için Steam menüsünden Çıkış yap; ardından tekrar uygula. Steam açıkken profil değiştirilmez.' }
    $set = [IO.File]::ReadAllText($ModSet,[Text.Encoding]::UTF8) | ConvertFrom-Json
    $order = @(Get-ActiveModOrder @($set.ActiveModLog))
    if (-not $order.Count) { throw 'Paketin mod sırası eksik.' }
    $mods = @($set.Mods | Where-Object { $_.Source -eq 'local' })
    if ($mods.Count -ne $order.Count -or @($set.Mods | Where-Object { $_.Source -ne 'local' }).Count) { throw 'Bu özellik eksiksiz yerel mod seti gerektirir.' }
    $modDir = Join-Path (Get-Ets2DocumentsPath) 'mod'
    $entries = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($item in $order) {
        $match = @($mods | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.File) -ceq $item.Package })
        if ($match.Count -ne 1 -or $seen.ContainsKey($item.Package)) { throw 'Paketin mod listesi/sırası tutarsız.' }
        $seen[$item.Package] = $true
        $path = Join-Path $modDir $match[0].File
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileSha256 $path) -ine $match[0].Sha256) { throw "Eksik/farklı mod: $($match[0].File). Önce kurulumu ve 1.62 uyarlamasını tamamla." }
        $entries.Add($item.Package + '|' + $item.Name)
    }
    if (-not ('Ets2Mods.ProfileModOrder' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ProfileModOrder.cs') }
    $before = Get-FileSha256 $ProfilePath
    $text = [Ets2Mods.ProfileModOrder]::Decode([IO.File]::ReadAllBytes($ProfilePath))
    $array = $entries.ToArray(); [array]::Reverse($array)
    $changed = [Ets2Mods.ProfileModOrder]::Replace($text,$array)
    if ($changed -ceq $text) { return [pscustomobject]@{ Ok=$true; Updated=$false; ModCount=$order.Count; Profile=$profile.Name; BackupDir=$null } }
    $backup = Join-Path $BackupRoot ((Get-Date -Format 'yyyy-MM-dd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $original = Join-Path $backup 'profile.sii'
    Copy-Item -LiteralPath $ProfilePath -Destination $original
    if ((Get-FileSha256 $original) -ne $before) { throw 'Profil yedeği doğrulanamadı.' }
    $temp = Join-Path (Split-Path $ProfilePath -Parent) ('.asistan-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        [IO.File]::WriteAllText($temp,$changed,(New-Object Text.UTF8Encoding $false))
        if ([Ets2Mods.ProfileModOrder]::Decode([IO.File]::ReadAllBytes($temp)) -cne $changed) { throw 'Yeni profil doğrulanamadı.' }
        $after = Get-FileSha256 $temp
        if ((Get-FileSha256 $ProfilePath) -ne $before -or (Get-Process eurotrucks2 -ErrorAction SilentlyContinue) -or ($profile.Cloud -and (Get-Process steam -ErrorAction SilentlyContinue))) { throw 'Profil değişti veya oyun/Steam açıldı. İşlem iptal edildi.' }
        [pscustomobject]@{ Target=$ProfilePath; OriginalSha256=$before; AppliedSha256=$after } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'geri-alma.json') -Encoding UTF8
        [Ets2Mods.ProfileModOrder]::ReplaceFile($temp,$ProfilePath)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    return [pscustomobject]@{ Ok=$true; Updated=$true; ModCount=$order.Count; Profile=$profile.Name; BackupDir=$backup }
}

function Restore-Ets2ModProfile {
    param([string]$BackupDir)
    if (-not ('Ets2Mods.ProfileModOrder' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ProfileModOrder.cs') }
    if (Get-Process eurotrucks2,steam -ErrorAction SilentlyContinue) { throw 'Geri almadan önce oyunu ve Steam uygulamasını kapat.' }
    $record = [IO.File]::ReadAllText((Join-Path $BackupDir 'geri-alma.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not @(Get-Ets2ModProfiles | Where-Object { $_.Path -eq $record.Target }).Count) { throw 'Hedef profil bulunamadı.' }
    $original = Join-Path $BackupDir 'profile.sii'
    if ((Get-FileSha256 $record.Target) -ne $record.AppliedSha256) { throw 'Profil işlemden sonra değişmiş. Yeni oyun ilerlemesini ezmemek için otomatik geri alınmadı.' }
    if ((Get-FileSha256 $original) -ne $record.OriginalSha256) { throw 'Profil yedeği bozuk.' }
    $temp = $record.Target+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        Copy-Item -LiteralPath $original -Destination $temp
        if ((Get-FileSha256 $record.Target) -ne $record.AppliedSha256 -or (Get-Process eurotrucks2,steam -ErrorAction SilentlyContinue)) { throw 'Profil değişti veya oyun/Steam açıldı; geri alma iptal edildi.' }
        [Ets2Mods.ProfileModOrder]::ReplaceFile($temp,$record.Target)
    }
    finally { if(Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    [pscustomobject]@{ Ok=$true; Restored=$true; BackupDir=$BackupDir }
}
