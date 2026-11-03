# İndirme asistanının motoru: katalog, İndirilenler klasörünü izleme, doğrulama, bekleme süreleri.
# Arayüzden bağımsızdır. Önce tools\Ets2Common.ps1, sonra bu dosya dot-source edilir.
#
# Katalog yapısı (assistant\catalog):
#   mods\<id>.json   bir mod: indirme sayfası, varyantlar (bedava/premium), beklenen dosyalar (ad, boyut, SHA256)
#   packs\<id>.json  bir konvoy paketi: hangi modlar, gereken DLC'ler, host'tan gelen dosyalar
# Yeni mod eklemek = mods\ altına bir JSON + paketin "mods" listesine id'si.

$script:PartialExtensions = '.crdownload', '.part', '.partial', '.download', '.tmp'
$script:StableSeconds = 3

function Read-JsonFile([string]$Path) {
    # PS 5.1 Get-Content BOM'suz UTF-8'i ANSI okur; doğrudan UTF-8 okunur
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
    # StrictMode altında JSON'da olmayan alana erişim hata verir
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.PSObject.Properties[$Name].Value }
    return $Default
}

function ConvertTo-Hashtable($Object) {
    $h = @{}
    if ($Object) { foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    return $h
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Get-UserDownloadsFolder {
    # Kullanıcı İndirilenler'i başka sürücüye taşımış olabilir; gerçek yeri kayıt defterinde
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        $p = [Environment]::ExpandEnvironmentVariables($v)
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Test-MinVersion($Item, [string]$Current, [string]$What) {
    $min = Get-Prop $Item 'minAssistantVersion'
    if ($min -and [version]$Current -lt [version]$min) {
        throw "$What için asistanın en az $min sürümü gerekiyor (bu sürüm: $Current). Asistanın yeni sürümünü al."
    }
}

function New-AssistantContext {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$AssistantDir,
        [Parameter(Mandatory)][string]$ToolsDir,
        [string]$DownloadsPath,
        [string]$PackId
    )
    $pkgFile = Join-Path $PackageRoot 'paket.json'
    if (-not (Test-Path -LiteralPath $pkgFile)) { throw "paket.json bulunamadı: $pkgFile. Asistan, host'un verdiği paket klasöründen çalıştırılmalı." }
    $pkg = Read-JsonFile $pkgFile
    $version = (Read-JsonFile (Join-Path $AssistantDir 'version.json')).assistantVersion

    $catalogDir = Join-Path $AssistantDir 'catalog'
    $modDefs = @{}
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $catalogDir 'mods') -Filter *.json) { $m = Read-JsonFile $f.FullName; $modDefs[$m.id] = $m }
    $packDefs = @{}
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $catalogDir 'packs') -Filter *.json) { $p = Read-JsonFile $f.FullName; $packDefs[$p.id] = $p }

    if (-not $PackId) { $PackId = Get-Prop $pkg 'pack' }
    $pack = $packDefs[$PackId]
    if (-not $pack) { throw "Katalogda '$PackId' paketi yok." }
    Test-MinVersion $pack $version "'$($pack.name)' paketi"

    $modSetPath = $null; $modSet = $null
    $msName = Get-Prop $pkg 'modSet'
    if ($msName) {
        $modSetPath = Join-Path $PackageRoot $msName
        if (Test-Path -LiteralPath $modSetPath) { $modSet = Read-JsonFile $modSetPath }
    }

    $incoming = Join-Path $PackageRoot 'indirilenler'
    if (-not (Test-Path -LiteralPath $incoming)) { New-Item -ItemType Directory -Path $incoming | Out-Null }
    if (-not $DownloadsPath) { $DownloadsPath = Get-UserDownloadsFolder }

    $statePath = Join-Path $PackageRoot 'asistan-durum.json'
    $state = @{ Cooldowns = @{}; Hashes = @{}; PreferredVariant = 'free'; Installed = @{} }
    if (Test-Path -LiteralPath $statePath) {
        try {
            $s = Read-JsonFile $statePath
            $state.Cooldowns = ConvertTo-Hashtable (Get-Prop $s 'Cooldowns')
            $state.Hashes = ConvertTo-Hashtable (Get-Prop $s 'Hashes')
            $state.Installed = ConvertTo-Hashtable (Get-Prop $s 'Installed')
            $state.PreferredVariant = Get-Prop $s 'PreferredVariant' 'free'
        } catch { }
    }

    $mods = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($pack.mods)) {
        $def = $modDefs[$id]
        if (-not $def) { throw "Paket '$PackId' katalogda olmayan bir modu istiyor: $id" }
        Test-MinVersion $def $version "'$($def.name)' modu"
        $variants = New-Object System.Collections.Generic.List[object]
        foreach ($v in @($def.variants)) {
            $files = New-Object System.Collections.Generic.List[object]
            foreach ($f in @($v.files)) {
                $name = Get-Prop $f 'name'
                $pattern = Get-Prop $f 'pattern'
                $files.Add(@{
                        Key      = "$id/$($v.id)/$(if ($name) { $name } else { $pattern })"
                        ModId    = $id
                        Name     = $name
                        Pattern  = $pattern
                        Display  = Get-Prop $f 'display' $name
                        Aliases  = @(Get-Prop $f 'aliases' @())
                        Size     = [long](Get-Prop $f 'size' 0)
                        Sha256   = Get-Prop $f 'sha256'
                        Url      = Get-Prop $f 'url' $def.page
                        Status   = 'pending'
                        Percent  = 0
                        Detail   = ''
                        Path     = $null
                    })
            }
            $variants.Add(@{
                    Id              = $v.id
                    Label           = Get-Prop $v 'label' $v.id
                    CooldownGroup   = Get-Prop $v 'cooldownGroup'
                    CooldownSeconds = [int](Get-Prop $v 'cooldownSeconds' 0)
                    Instructions    = @(Get-Prop $v 'instructions' @())
                    Files           = $files
                })
        }
        $mods.Add(@{
                Id            = $id
                Name          = $def.name
                Version       = Get-Prop $def 'version' ''
                Site          = Get-Prop $def 'site' ''
                Page          = $def.page
                LoginRequired = [bool](Get-Prop $def 'loginRequired' $false)
                Notes         = @(Get-Prop $def 'notes' @())
                Provides      = @(Get-Prop $def 'provides' @())   # arşivden çıkan, oyuna kurulan dosyalar
                Installed     = $false
                Variants      = $variants
            })
    }

    @{
        Version       = $version
        PackageRoot   = $PackageRoot
        AssistantDir  = $AssistantDir
        ToolsDir      = $ToolsDir
        Package       = $pkg
        Pack          = $pack
        ModSet        = $modSet
        ModSetPath    = $modSetPath
        IncomingPath  = $incoming
        ModFolder     = Get-ModFolder
        DownloadsPath = $DownloadsPath
        StatePath     = $statePath
        State         = $state
        Mods          = $mods
        Seen          = @{}   # İndirilenler'deki dosyaların son boyutu (indirme bitti mi?)
        Rejected      = @{}   # "dosya|adım": bu adıma uymayan, başka varyantın alacağı dosyalar
        Skipped       = @{}
    }
}

function Save-AssistantState($Ctx) {
    try { Write-JsonFile $Ctx.StatePath $Ctx.State } catch { }
}

function Get-ActiveVariant($Ctx, $Mod) {
    $v = @($Mod.Variants | Where-Object { $_.Id -eq $Ctx.State.PreferredVariant }) | Select-Object -First 1
    if ($v) { return $v }
    return $Mod.Variants[0]
}

function Test-ModComplete($Mod) {
    # Oyuna kurulmuş modun dosyalarını indirmeye gerek yok
    if ($Mod.Installed) { return $true }
    foreach ($v in $Mod.Variants) {
        if (-not @($v.Files | Where-Object { $_.Status -ne 'done' }).Count) { return $true }
    }
    return $false
}

function Test-HasVariant($Ctx, [string]$VariantId) {
    return [bool](@($Ctx.Mods | ForEach-Object { $_.Variants } | Where-Object { $_.Id -eq $VariantId }).Count)
}

function Get-NormalizedName([string]$Name) {
    # Tarayıcının aynı ada eklediği " (1)" / "(2)" son ekini at
    return ($Name -replace '\s?\(\d+\)(?=\.[^.]*$|$)', '')
}

function Test-NameMatch($Spec, [string]$FileName) {
    $n = Get-NormalizedName $FileName
    if ($Spec.Name -and ($n -ieq $Spec.Name -or @($Spec.Aliases | Where-Object { $n -ieq $_ }).Count)) { return $true }
    if ($Spec.Pattern -and $n -like $Spec.Pattern) { return $true }
    return $false
}

function Get-CachedSha256($Ctx, [System.IO.FileInfo]$File) {
    $key = '{0}|{1}|{2}' -f $File.Name, $File.Length, $File.LastWriteTimeUtc.Ticks
    if ($Ctx.State.Hashes.ContainsKey($key)) { return $Ctx.State.Hashes[$key] }
    $h = Get-FileSha256 $File.FullName
    $Ctx.State.Hashes[$key] = $h
    return $h
}

function Test-SpecFile($Ctx, $Spec, [System.IO.FileInfo]$File) {
    if ($Spec.Size -and $File.Length -ne $Spec.Size) {
        return @{ Ok = $false; Detail = "Boyut yanlış ($(Format-Size $File.Length), beklenen $(Format-Size $Spec.Size))" }
    }
    if ($Spec.Sha256) {
        if ((Get-CachedSha256 $Ctx $File) -ne $Spec.Sha256) { return @{ Ok = $false; Detail = 'Dosya bozuk ya da farklı sürüm' } }
        return @{ Ok = $true; Detail = 'Doğrulandı' }
    }
    return @{ Ok = $true; Detail = 'Kurulumda kontrol edilecek' }
}

function Move-ToQuarantine($Ctx, [System.IO.FileInfo]$File) {
    $q = Join-Path $Ctx.IncomingPath '_hatali'
    if (-not (Test-Path -LiteralPath $q)) { New-Item -ItemType Directory -Path $q | Out-Null }
    $target = Join-Path $q ('{0:yyyyMMdd-HHmmss}_{1}' -f (Get-Date), $File.Name)
    Move-Item -LiteralPath $File.FullName -Destination $target -Force
}

function Complete-Spec($Ctx, $Spec, $Variant, [System.IO.FileInfo]$File, [string]$Detail, [switch]$Copy, [switch]$NoCooldown) {
    # Dosyayı indirilenler klasörüne kendi adıyla alır ve adımı tamamlar
    $name = if ($Spec.Name) { $Spec.Name } else { Get-NormalizedName $File.Name }
    $target = Join-Path $Ctx.IncomingPath $name
    if ($File.FullName -ne $target) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        if ($Copy) { Copy-Item -LiteralPath $File.FullName -Destination $target } else { Move-Item -LiteralPath $File.FullName -Destination $target }
        $moved = Get-Item -LiteralPath $target
        if ($Spec.Sha256) { $Ctx.State.Hashes['{0}|{1}|{2}' -f $moved.Name, $moved.Length, $moved.LastWriteTimeUtc.Ticks] = $Spec.Sha256 }
    }
    $Spec.Status = 'done'; $Spec.Percent = 100; $Spec.Detail = $Detail; $Spec.Path = $target
    if (-not $NoCooldown -and $Variant.CooldownSeconds -gt 0 -and $Variant.CooldownGroup) {
        $Ctx.State.Cooldowns[$Variant.CooldownGroup] = (Get-Date).ToString('o')
    }
}

function Test-OtherSpecAccepts($Ctx, $Mod, $Spec, [System.IO.FileInfo]$File) {
    foreach ($v in $Mod.Variants) {
        foreach ($s in $v.Files) {
            if ($s.Key -eq $Spec.Key -or $s.Status -eq 'done' -or -not (Test-NameMatch $s $File.Name)) { continue }
            if ((Test-SpecFile $Ctx $s $File).Ok) { return $true }
        }
    }
    return $false
}

function Update-AssistantDownloads {
    # Tek tarama turu: indirilenler klasörünü ve kullanıcının İndirilenler'ini kontrol eder.
    # Arayüz bunu saniyede bir çağırır. $Notify: uzun işlemlerde (hash) durum metni için.
    param($Ctx, [scriptblock]$Notify)
    $now = Get-Date
    $dl = @()
    if (Test-Path -LiteralPath $Ctx.DownloadsPath) { $dl = @(Get-ChildItem -LiteralPath $Ctx.DownloadsPath -File -ErrorAction SilentlyContinue) }
    $partials = @($dl | Where-Object { $script:PartialExtensions -contains $_.Extension.ToLowerInvariant() })
    $finals = @($dl | Where-Object { $script:PartialExtensions -notcontains $_.Extension.ToLowerInvariant() })
    $inFiles = @(Get-ChildItem -LiteralPath $Ctx.IncomingPath -File)
    $consumed = @{}   # bu turda taşınan dosyalar
    $changed = $false

    foreach ($mod in $Ctx.Mods) {
        foreach ($spec in @($mod.Variants | ForEach-Object { $_.Files })) {
            if ($spec.Status -eq 'done' -and $spec.Path -and -not (Test-Path -LiteralPath $spec.Path)) { $spec.Status = 'pending'; $spec.Detail = ''; $spec.Path = $null }
        }
        foreach ($variant in $mod.Variants) {
            foreach ($spec in $variant.Files) {
                if ($spec.Status -eq 'done') { continue }
                if (Test-ModComplete $mod) {
                    # Mod başka varyantla (ör. premium) tamamlandı; bu dosya artık beklenmiyor
                    if ($spec.Status -ne 'pending') { $spec.Status = 'pending'; $spec.Detail = ''; $changed = $true }
                    continue
                }

                # 1) Zaten asistanın klasöründe mi? (Hatalıysa yerinde kalır; yenisi inince üzerine yazılır.
                #    Başka bir varyantın dosyası olabileceği için buradan taşınmaz.)
                $have = @($inFiles | Where-Object { Test-NameMatch $spec $_.Name -and (Test-Path -LiteralPath $_.FullName) }) | Select-Object -First 1
                if ($have) {
                    if ($Notify -and $spec.Sha256) { & $Notify "Doğrulanıyor: $($have.Name)" }
                    $r = Test-SpecFile $Ctx $spec $have
                    if ($r.Ok) { Complete-Spec $Ctx $spec $variant $have $r.Detail -NoCooldown; $changed = $true; continue }
                    if ($spec.Status -ne 'error') { $spec.Status = 'error'; $spec.Detail = "$($r.Detail) – tekrar indir"; $changed = $true }
                }

                # 2) İndirilenler'de sürüyor mu / bitti mi?
                $part = @($partials | Where-Object { Test-NameMatch $spec ([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }) | Select-Object -First 1
                $cand = @($finals | Where-Object { -not $consumed.ContainsKey($_.FullName) -and (Test-NameMatch $spec $_.Name) } |
                    Sort-Object LastWriteTime -Descending) | Select-Object -First 1
                if ($part) {
                    $spec.Status = 'downloading'
                    $spec.Percent = if ($spec.Size) { [math]::Min(99, [int](100 * $part.Length / $spec.Size)) } else { 0 }
                    continue
                }
                if (-not $cand) {
                    if ($spec.Status -eq 'downloading') { $spec.Status = 'pending'; $spec.Detail = 'İndirme yarıda kaldı' }
                    continue
                }
                if ($Ctx.Rejected.ContainsKey($cand.FullName + '|' + $spec.Key)) { continue }
                $seen = $Ctx.Seen[$cand.FullName]
                if (-not $seen -or $seen.Length -ne $cand.Length) { $Ctx.Seen[$cand.FullName] = @{ Length = $cand.Length; Since = $now }; $seen = $Ctx.Seen[$cand.FullName] }
                $stable = ($now - $seen.Since).TotalSeconds -ge $script:StableSeconds
                if (($spec.Size -and $cand.Length -lt $spec.Size) -or -not $stable) {
                    $spec.Status = 'downloading'
                    $spec.Percent = if ($spec.Size) { [math]::Min(99, [int](100 * $cand.Length / $spec.Size)) } else { 0 }
                    continue
                }
                if ($Notify) { & $Notify "Doğrulanıyor: $($cand.Name)" }
                $r = Test-SpecFile $Ctx $spec $cand
                if ($r.Ok) {
                    if ($Notify) { & $Notify "Taşınıyor: $($cand.Name)" }
                    Complete-Spec $Ctx $spec $variant $cand $r.Detail
                    $consumed[$cand.FullName] = $true
                    $Ctx.Seen.Remove($cand.FullName)
                } elseif (Test-OtherSpecAccepts $Ctx $mod $spec $cand) {
                    # Aynı ada uyan başka varyant (ör. premium tek dosya) alacak
                    $Ctx.Rejected[$cand.FullName + '|' + $spec.Key] = $true
                } else {
                    Move-ToQuarantine $Ctx $cand
                    $consumed[$cand.FullName] = $true
                    $Ctx.Seen.Remove($cand.FullName)
                    $spec.Status = 'error'; $spec.Detail = "$($r.Detail) – tekrar indir"
                }
                $changed = $true
            }
        }
    }
    if ($changed) { Save-AssistantState $Ctx }
    return $changed
}

function Get-CooldownRemaining($Ctx, [string]$Group, [int]$Seconds) {
    $last = $Ctx.State.Cooldowns[$Group]
    if (-not $last) { return 0 }
    $elapsed = ((Get-Date) - [datetime]::Parse($last, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)).TotalSeconds
    return [math]::Max(0, [int][math]::Ceiling($Seconds - $elapsed))
}

function Get-NextAction($Ctx) {
    # Sıradaki adım. Beklemeli kaynaklar (ProMods bedava) darboğaz olduğu için önce onlar;
    # bekleme sürerken diğer kaynakların dosyaları önerilir.
    $waits = @{}
    $first = @{ Cooldown = $null; Other = $null; Skipped = $null }
    $downloading = 0
    foreach ($mod in $Ctx.Mods) {
        if (Test-ModComplete $mod) { continue }
        $v = Get-ActiveVariant $Ctx $mod
        $downloading += @($v.Files | Where-Object { $_.Status -eq 'downloading' }).Count
        foreach ($spec in $v.Files) {
            if ($spec.Status -notin 'pending', 'error') { continue }
            $item = @{ Mod = $mod; Variant = $v; Spec = $spec }
            if ($Ctx.Skipped.ContainsKey($spec.Key)) { if (-not $first.Skipped) { $first.Skipped = $item }; continue }
            if ($v.CooldownSeconds -gt 0 -and $v.CooldownGroup) {
                $g = $v.CooldownGroup
                $busy = @($Ctx.Mods | Where-Object { -not (Test-ModComplete $_) } | ForEach-Object { Get-ActiveVariant $Ctx $_ } | Where-Object { $_.CooldownGroup -eq $g } |
                    ForEach-Object { $_.Files } | Where-Object { $_.Status -eq 'downloading' }).Count -gt 0
                $rem = Get-CooldownRemaining $Ctx $g $v.CooldownSeconds
                if ($busy -or $rem -gt 0) { $waits[$g] = @{ Busy = $busy; Remaining = $rem }; continue }
                if (-not $first.Cooldown) { $first.Cooldown = $item }
            } elseif (-not $first.Other) { $first.Other = $item }
        }
    }
    $pick = if ($first.Cooldown) { $first.Cooldown } elseif ($first.Other) { $first.Other } else { $first.Skipped }
    $kind = if ($pick) { 'download' } elseif ($waits.Count) { 'wait' } elseif ($downloading) { 'downloading' } else { 'done' }
    return @{ Kind = $kind; Item = $pick; Waits = $waits; Downloading = $downloading }
}

function Get-DownloadTotals($Ctx) {
    $total = 0L; $done = 0L; $files = 0; $doneFiles = 0
    foreach ($mod in $Ctx.Mods) {
        $complete = Test-ModComplete $mod
        foreach ($spec in (Get-ActiveVariant $Ctx $mod).Files) {
            $files++
            $total += $spec.Size
            if ($complete -or $spec.Status -eq 'done') { $doneFiles++; $done += $spec.Size }
            elseif ($spec.Status -eq 'downloading') { $done += [long]($spec.Size * $spec.Percent / 100) }
        }
    }
    @{ TotalBytes = $total; DoneBytes = $done; Files = $files; DoneFiles = $doneFiles }
}

function Add-ManualFile {
    # Kullanıcının elle gösterdiği dosya: hash'i hangi beklenen dosyaya uyuyorsa onu tamamlar
    param($Ctx, [string]$Path, $Preferred)
    $file = Get-Item -LiteralPath $Path
    $hash = Get-CachedSha256 $Ctx $file
    $already = @($Ctx.Mods | ForEach-Object { $_.Variants } | ForEach-Object { $_.Files } |
        Where-Object { $_.Status -eq 'done' -and $_.Sha256 -eq $hash }) | Select-Object -First 1
    if ($already) { return @{ Ok = $true; Message = "$($already.Display) zaten eklenmiş." } }
    foreach ($mod in $Ctx.Mods) {
        foreach ($v in $mod.Variants) {
            foreach ($spec in $v.Files) {
                if ($spec.Status -ne 'done' -and $spec.Sha256 -and $spec.Sha256 -eq $hash) {
                    Complete-Spec $Ctx $spec $v $file 'Doğrulandı (elle eklendi)' -Copy -NoCooldown
                    Save-AssistantState $Ctx
                    return @{ Ok = $true; Message = "$($spec.Display) eklendi." }
                }
            }
        }
    }
    if ($Preferred -and -not $Preferred.Spec.Sha256) {
        Complete-Spec $Ctx $Preferred.Spec $Preferred.Variant $file 'Elle eklendi, kurulumda kontrol edilecek' -Copy -NoCooldown
        Save-AssistantState $Ctx
        return @{ Ok = $true; Message = "$($file.Name), $($Preferred.Mod.Name) için eklendi." }
    }
    return @{ Ok = $false; Message = "$($file.Name) beklenen dosyalardan hiçbirine uymuyor (bozuk ya da farklı sürüm olabilir)." }
}

function Get-HostFileReport($Ctx) {
    foreach ($hf in @(Get-Prop $Ctx.Pack 'hostFiles' @())) {
        $path = Join-Path $Ctx.IncomingPath $hf.name
        $exp = $null
        if ($Ctx.ModSet) { $exp = @($Ctx.ModSet.Mods | Where-Object { $_.File -eq $hf.name }) | Select-Object -First 1 }
        if (-not (Test-Path -LiteralPath $path)) {
            @{ Name = $hf.label; State = 'fail'; Detail = "$($hf.name) indirilenler klasöründe yok. Host'tan gelen paketteki dosyayı oraya geri koy." }
        } elseif ($exp -and $exp.Sha256 -and (Get-CachedSha256 $Ctx (Get-Item -LiteralPath $path)) -ne $exp.Sha256) {
            @{ Name = $hf.label; State = 'fail'; Detail = "$($hf.name) host'unkinden farklı. Paketteki dosyayı tekrar koy (siteden indirdiğin def'i değil)." }
        } else {
            @{ Name = $hf.label; State = 'ok'; Detail = $hf.name }
        }
    }
}

function Get-PrerequisiteReport($Ctx) {
    $r = New-Object System.Collections.Generic.List[object]
    $install = Get-Ets2InstallPath
    if ($install) { $r.Add(@{ Name = 'Euro Truck Simulator 2'; State = 'ok'; Detail = 'Kurulu' }) }
    else { $r.Add(@{ Name = 'Euro Truck Simulator 2'; State = 'fail'; Detail = 'Steam kütüphanelerinde bulunamadı' }) }

    $docs = $null
    try { $docs = Get-Ets2DocumentsPath } catch { }
    if (-not $docs) {
        $r.Add(@{ Name = 'Oyun klasörü (Belgeler)'; State = 'fail'; Detail = 'Yok. Oyunu bir kez açıp kapat.' })
    } else {
        $log = Get-Ets2LogInfo
        $want = Get-Prop $Ctx.Pack 'gameVersion' ''
        $hostVer = if ($Ctx.ModSet) { $Ctx.ModSet.GameVersion } else { $null }
        if (-not $log -or -not $log.GameVersion) {
            $r.Add(@{ Name = 'Oyun sürümü'; State = 'warn'; Detail = 'Bilinmiyor. Oyunu bir kez açıp kapat, sonra "Tekrar kontrol et".' })
        } elseif ($want -and -not $log.GameVersion.StartsWith($want)) {
            $r.Add(@{ Name = 'Oyun sürümü'; State = 'fail'; Detail = "$($log.GameVersion) – $want.x gerekiyor. Steam'de oyunu güncelle." })
        } elseif ($hostVer -and $hostVer -ne $log.GameVersion) {
            $r.Add(@{ Name = 'Oyun sürümü'; State = 'warn'; Detail = "$($log.GameVersion), host'unki $hostVer. İkiniz de Steam'de güncelleyin." })
        } else {
            $r.Add(@{ Name = 'Oyun sürümü'; State = 'ok'; Detail = $log.GameVersion })
        }
    }

    $owned = @(Get-Ets2OwnedDlcAppIds)
    $req = @(Get-Prop $Ctx.Pack 'requiredDlcs' @())
    $missing = @($req | Where-Object { $owned -notcontains $_.appId })
    if (-not $req.Count) { }
    elseif (-not $owned.Count) { $r.Add(@{ Name = 'Harita DLC''leri'; State = 'warn'; Detail = 'Steam DLC listesi okunamadı' }) }
    elseif ($missing.Count) { $r.Add(@{ Name = 'Harita DLC''leri'; State = 'fail'; Detail = 'Eksik: ' + (($missing | ForEach-Object { $_.name }) -join ', ') }) }
    else { $r.Add(@{ Name = 'Harita DLC''leri'; State = 'ok'; Detail = "$($req.Count) DLC'nin hepsi var" }) }

    # Disk: indirmeler + açılmış paketler bu klasörde, kurulmuş paketler Belgeler'de
    $download = (Get-DownloadTotals $Ctx).TotalBytes
    $extracted = 0L
    if ($Ctx.ModSet) { foreach ($m in @($Ctx.ModSet.Mods | Where-Object { $_.Source -eq 'local' })) { $extracted += [long]([double]$m.SizeMB * 1MB) } }
    else { $extracted = [long]([double](Get-Prop $Ctx.Pack 'diskGb' 0) * 1GB / 2) }
    $need = @{}
    $pkgDrive = [System.IO.Path]::GetPathRoot($Ctx.PackageRoot)
    $need[$pkgDrive] = $download + $extracted
    if ($docs) {
        $docDrive = [System.IO.Path]::GetPathRoot($docs)
        $need[$docDrive] = [long]$need[$docDrive] + $extracted
    }
    foreach ($d in $need.Keys) {
        $free = (New-Object System.IO.DriveInfo $d).AvailableFreeSpace
        $state = if ($free -ge $need[$d] * 1.1) { 'ok' } else { 'fail' }
        $r.Add(@{ Name = "Boş disk ($d)"; State = $state; Detail = "Boş $(Format-Size $free), gereken ~$(Format-Size $need[$d])" })
    }

    if (-not $Ctx.ModSet) { $r.Add(@{ Name = 'Host''un mod listesi'; State = 'fail'; Detail = 'Paketteki modset dosyası yok; kurulum doğrulanamaz.' }) }
    foreach ($h in @(Get-HostFileReport $Ctx)) { $r.Add($h) }
    return $r
}

function Get-ModFolder {
    try { return (Join-Path (Get-Ets2DocumentsPath) 'mod') } catch { return $null }
}

function Register-InstalledFiles($Ctx, $Installed) {
    # Kurulum görevinin kurduğu dosyalar. Boyut + değiştirilme zamanı saklanır: sonra her açılışta
    # 20 GB'ı yeniden hash'lemeden "hâlâ aynı dosya mı" bakılabilir.
    if (-not $Ctx.ModFolder) { return }
    foreach ($i in @($Installed)) {
        $p = Join-Path $Ctx.ModFolder $i.File
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $f = Get-Item -LiteralPath $p
        # pscustomobject: JSON'dan okunan kayıtlarla aynı tür (Get-Prop ikisinde de çalışsın)
        $Ctx.State.Installed[$i.File] = [pscustomobject]@{ Size = $f.Length; Ticks = $f.LastWriteTimeUtc.Ticks; Sha256 = $i.Sha256 }
    }
    Save-AssistantState $Ctx
}

function Test-FileInstalled($Ctx, [string]$Name) {
    $rec = $Ctx.State.Installed[$Name]
    if (-not $rec -or -not $Ctx.ModFolder) { return $false }
    $p = Join-Path $Ctx.ModFolder $Name
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $f = Get-Item -LiteralPath $p
    if ($f.Length -ne [long](Get-Prop $rec 'Size' 0) -or $f.LastWriteTimeUtc.Ticks -ne [long](Get-Prop $rec 'Ticks' 0)) { return $false }
    if ($Ctx.ModSet) {
        $exp = @($Ctx.ModSet.Mods | Where-Object { $_.File -eq $Name }) | Select-Object -First 1
        if ($exp -and $exp.Sha256 -and $exp.Sha256 -ne (Get-Prop $rec 'Sha256')) { return $false }
    }
    return $true
}

function Update-InstalledState($Ctx) {
    $changed = $false
    foreach ($mod in $Ctx.Mods) {
        $now = $mod.Provides.Count -gt 0 -and -not @($mod.Provides | Where-Object { -not (Test-FileInstalled $Ctx $_) }).Count
        if ($now -ne $mod.Installed) { $mod.Installed = $now; $changed = $true }
    }
    return $changed
}

function Get-InstallSummary($Ctx) {
    # Host'un elle kurduğu modlardan hangileri bu bilgisayarda (asistanla) kurulu
    $names = @(if ($Ctx.ModSet) { $Ctx.ModSet.Mods | Where-Object { $_.Source -eq 'local' } | ForEach-Object { $_.File } }
        else { @($Ctx.Mods | ForEach-Object { $_.Provides }) + @(Get-Prop $Ctx.Pack 'hostFiles' @() | ForEach-Object { $_.name }) })
    $missing = @($names | Where-Object { -not (Test-FileInstalled $Ctx $_) })
    @{ Total = $names.Count; Installed = $names.Count - $missing.Count; Missing = $missing }
}

function Start-DropInstall($Ctx, [string[]]$Paths, [string]$ResultFile) {
    # Sürükle-bırak: arşivler açılır, mod dosyaları doğrudan oyuna kurulur (ayrı pencerede).
    # Host dosyaları (def) da her seferinde eklenir; aynıysa "zaten kurulu" geçer.
    $files = foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -File -Recurse | ForEach-Object { $_.FullName } }
        elseif (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).FullName }
    }
    $hostFiles = @(Get-Prop $Ctx.Pack 'hostFiles' @() | ForEach-Object { Join-Path $Ctx.IncomingPath $_.name } | Where-Object { Test-Path -LiteralPath $_ })
    # Çok parçalı arşivlerin parça sayısı (tek parça bırakılırsa eksikler anlaşılsın)
    $partCounts = @{}
    foreach ($spec in @($Ctx.Mods | ForEach-Object { $_.Variants } | ForEach-Object { $_.Files })) {
        if ($spec.Name -and $spec.Name -match '^(.+\.7z)\.(\d{3})$') {
            $n = [int]$Matches[2]
            if (-not $partCounts[$Matches[1]] -or $partCounts[$Matches[1]] -lt $n) { $partCounts[$Matches[1]] = $n }
        }
    }
    $listPath = Join-Path $Ctx.PackageRoot 'birakilan-dosyalar.json'
    Write-JsonFile $listPath ([pscustomobject]@{ Files = @($files); HostFiles = $hostFiles; PartCounts = $partCounts })
    return Start-AssistantTask $Ctx add -FileList $listPath -ResultFile $ResultFile
}

function Get-HostLoadOrder($Ctx) {
    if (-not $Ctx.ModSet) { return @() }
    return @(Get-ActiveModOrder @($Ctx.ModSet.ActiveModLog))
}

function Start-AssistantTask {
    # Kurulum ve kontrol dosyası işleri ayrı bir PowerShell penceresinde çalışır (kullanıcı çıktıyı görür)
    param($Ctx, [ValidateSet('install', 'add', 'export')][string]$Task, [string]$Label, [string]$FileList, [string]$ResultFile)
    $runner = Join-Path $Ctx.AssistantDir 'lib\Invoke-AssistantTask.ps1'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$runner`"", '-Task', $Task,
        '-PackageRoot', "`"$($Ctx.PackageRoot)`"", '-ToolsDir', "`"$($Ctx.ToolsDir)`"")
    if ($Ctx.ModSetPath) { $argList += @('-ModSet', "`"$($Ctx.ModSetPath)`"") }
    if ($Label) { $argList += @('-Label', $Label) }
    if ($FileList) { $argList += @('-FileList', "`"$FileList`"") }
    if ($ResultFile) { $argList += @('-ResultFile', "`"$ResultFile`"") }
    return Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -PassThru
}
