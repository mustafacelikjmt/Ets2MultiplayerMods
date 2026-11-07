# Asistanın kendini güncellemesi. MServer (kişisel güncelleme sunucusu) ile konuşur.
#
# AKIŞ
#   1. assistant\version.json'daki versionCode ile sunucunun manifest'ini karşılaştır
#   2. Yenisi varsa kullanıcıya sor (zorunlu yayında sormadan)
#   3. Paketi indir, SHA-256'yı DOĞRULA, geçici klasöre aç, içeriğini denetle
#   4. asistan\ ve araclar\ klasörlerini takas et (kullanıcının verisine DOKUNMA)
#   5. Asistanı yeniden başlat
#
# ⚠️ SUNUCUYA ERİŞİLEMEMESİ BİR HATA DEĞİLDİR. Güncelleme denetimi asistanın açılış
#    yolunda duruyor; internet yoksa, sunucu kapalıysa ya da yanıt bozuksa asistan
#    NORMAL AÇILMALI. Bir güncelleme sunucusunun, güncelleyeceği programı çalışamaz
#    hale getirmesi kabul edilemez — arkadaş o an konvoya girmeye çalışıyor olabilir.
#    Bu yüzden buradaki her ağ işi try/catch içinde ve hata sessizce yutuluyor
#    (ayrıntı güncelleme-hata.log dosyasına yazılır).
#
# ⚠️ KARŞILAŞTIRMA versionCode İLE YAPILIR, sürüm metniyle DEĞİL. "0.3.0 > 0.2.10 mu?"
#    sorusunu metin karşılaştırmasıyla cevaplayan her istemci er geç yanlış cevap verir.

Set-StrictMode -Version 2.0

# PowerShell 5.1 varsayılan olarak TLS 1.0/1.1 deneyebiliyor; mustafacelik.site yalnız
# TLS 1.2+ kabul ediyor. Bu satır olmadan istek "temel bağlantı kapatıldı" diye düşer
# ve belirti ağ hatası gibi görünür — oysa sorun istemcide.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Write-UpdateLog {
    param([string]$PackageRoot, [string]$Message)
    try {
        $line = '{0}  {1}' -f (Get-Date).ToString('s'), $Message
        Add-Content -LiteralPath (Join-Path $PackageRoot 'guncelleme.log') -Value $line -Encoding UTF8
    } catch { }
}

function Get-AssistantVersionInfo {
    <#
    .SYNOPSIS
        version.json'u okur: sürüm, versionCode ve güncelleme adresi.
    .DESCRIPTION
        Eski paketlerde 'versionCode' ve 'update' alanları YOKTUR (güncelleme
        yeteneğinden önce dağıtılmış sürümler). O durumda $null döner ve çağıran
        denetimi atlar — eksik alan bir hata değil, "bu kurulum henüz güncellenebilir
        değil" demek.
    #>
    param([Parameter(Mandatory)][string]$AssistantDir)

    $file = Join-Path $AssistantDir 'version.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }

    $json = Read-JsonFile $file
    $update = Get-Prop $json 'update'
    $baseUrl = Get-Prop $update 'baseUrl'
    $code = Get-Prop $json 'versionCode' 0

    if (-not $baseUrl -or [int]$code -le 0) { return $null }

    return [pscustomobject]@{
        VersionName = Get-Prop $json 'assistantVersion' '0.0.0'
        VersionCode = [int]$code
        BaseUrl     = $baseUrl.TrimEnd('/')
        Package     = Get-Prop $update 'package' ''
    }
}

function Get-AssistantUpdate {
    <#
    .SYNOPSIS
        Sunucuda daha yeni bir sürüm var mı? Varsa manifest'i, yoksa $null döner.
    #>
    param(
        [Parameter(Mandatory)]$Info,
        [Parameter(Mandatory)][string]$PackageRoot,
        [int]$TimeoutSec = 10
    )

    # Kendi sürümümüzü bildiriyoruz: sunucu yalnızca GERİDE olan istemciler için log
    # satırı yazıyor, yani sahada kaç eski kurulum kaldığı oradan görülebiliyor.
    $url = '{0}/manifest?versionCode={1}&versionName={2}' -f `
        $Info.BaseUrl, $Info.VersionCode, [uri]::EscapeDataString($Info.VersionName)

    try {
        $old = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            $manifest = Invoke-RestMethod -Uri $url -TimeoutSec $TimeoutSec -UseBasicParsing
        } finally { $ProgressPreference = $old }
    } catch {
        # 404 = "bu kanalda yayın yok" ya da "kanal tanımsız"; ikisi de normal durum.
        Write-UpdateLog $PackageRoot "Denetim yapılamadı: $($_.Exception.Message)"
        return $null
    }

    $remoteCode = [int](Get-Prop $manifest 'versionCode' 0)
    if ($remoteCode -le $Info.VersionCode) {
        Write-UpdateLog $PackageRoot "Güncel (yerel $($Info.VersionCode), sunucu $remoteCode)."
        return $null
    }

    # ⚠️ Paket kimliği denetimi: indireceğimiz şeyin BİZE ait olduğunu doğrular. Kanal
    # yapılandırması yanlışlıkla başka bir ürünü işaret ederse, asistan kendi yerine
    # başka bir programı kurardı.
    $remotePackage = Get-Prop $manifest 'package' ''
    if ($Info.Package -and $remotePackage -and $remotePackage -ne $Info.Package) {
        Write-UpdateLog $PackageRoot "Paket kimliği uyuşmuyor (beklenen $($Info.Package), gelen $remotePackage). Güncelleme atlandı."
        return $null
    }

    if (-not (Get-Prop $manifest 'url')) {
        Write-UpdateLog $PackageRoot 'Manifest indirme adresi taşımıyor; güncelleme atlandı.'
        return $null
    }

    return $manifest
}

function Install-AssistantUpdate {
    <#
    .SYNOPSIS
        Paketi indirir, doğrular ve kurar. Başarılıysa $true döner.
    .DESCRIPTION
        Kullanıcının verisine (indirilenler\, paket.json, modset-host.json,
        asistan-durum.json, uyumluluk\) HİÇ DOKUNMAZ: yalnızca asistan\, araclar\ ve
        Asistan.cmd değişir. Güncelleme birimi "asistan programı"dır, konvoy paketi değil.
    #>
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$PackageRoot
    )

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ('ets2-asistan-guncelleme-' + [guid]::NewGuid().ToString('N'))
    $zipPath = "$staging.zip"
    $expected = Get-AssistantPayloadNames

    try {
        # --- İndir -----------------------------------------------------------------
        $old = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Manifest.url -OutFile $zipPath -TimeoutSec 300 -UseBasicParsing
        } finally { $ProgressPreference = $old }

        # --- Doğrula ----------------------------------------------------------------
        # ⚠️ ÖZET DENETİMİ ATLANMAZ. Yarım inmiş ya da araya girilmiş bir paketi açmak,
        #    çalışan bir kurulumu bozuk dosyalarla değiştirmek demek — ve geri dönüşü
        #    kullanıcı için yok (elinde yalnızca bozulmuş klasör kalır).
        $declared = Get-Prop $Manifest 'sha256' ''
        $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $declared -or $actual -ne $declared.ToLowerInvariant()) {
            throw "İndirilen paketin özeti tutmuyor (beklenen $declared, gelen $actual)."
        }

        $size = (Get-Item -LiteralPath $zipPath).Length
        $declaredSize = [long](Get-Prop $Manifest 'sizeBytes' 0)
        if ($declaredSize -gt 0 -and $size -ne $declaredSize) {
            throw "İndirilen paketin boyutu tutmuyor ($size / $declaredSize)."
        }

        # --- Aç ----------------------------------------------------------------------
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $stagingFull = [IO.Path]::GetFullPath($staging).TrimEnd('\') + '\'
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }   # klasör girdisi
                # ⚠️ Yol taşması kapısı: zip içindeki "..\..\Windows\System32\..." gibi
                #    bir girdi, hedef klasörün dışına yazardı (Zip Slip).
                $destination = [IO.Path]::GetFullPath((Join-Path $staging ($entry.FullName -replace '/', '\')))
                if (-not $destination.StartsWith($stagingFull, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Paket, klasörün dışına çıkan bir girdi içeriyor: $($entry.FullName)"
                }
                New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
            }
        } finally { $zip.Dispose() }

        # --- İçerik denetimi -----------------------------------------------------------
        # ⚠️ Takastan ÖNCE. Eksik bir paketle takas yapılsaydı, asistan bir dosyasını
        #    bulamayıp açılmaz hale gelirdi ve kullanıcının geri döneceği sürüm olmazdı.
        foreach ($name in $expected) {
            if (-not (Test-Path -LiteralPath (Join-Path $staging $name))) {
                throw "Güncelleme paketi eksik: '$name' yok."
            }
        }

        $newVersion = Read-JsonFile (Join-Path $staging 'asistan\version.json')
        $newCode = [int](Get-Prop $newVersion 'versionCode' 0)
        if ($newCode -ne [int]$Manifest.versionCode) {
            throw "Paketin içindeki sürüm ($newCode) manifest'tekiyle ($($Manifest.versionCode)) aynı değil."
        }

        # --- Takas ------------------------------------------------------------------
        # Klasör klasör: önce eskisini yana al, yenisini koy. Bir adım düşerse o ana
        # kadar yapılanlar geri alınır — yarım bir kurulum bırakmaktansa hiç
        # güncellememek yeğdir.
        $moved = New-Object System.Collections.Generic.List[object]
        try {
            foreach ($name in $expected) {
                $target = Join-Path $PackageRoot $name
                $backup = "$target.eski"
                if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
                if (Test-Path -LiteralPath $target) {
                    Move-Item -LiteralPath $target -Destination $backup -Force
                    $moved.Add([pscustomobject]@{ Target = $target; Backup = $backup })
                }
                Move-Item -LiteralPath (Join-Path $staging $name) -Destination $target -Force
            }
        } catch {
            foreach ($item in $moved) {
                if (Test-Path -LiteralPath $item.Target) { Remove-Item -LiteralPath $item.Target -Recurse -Force }
                Move-Item -LiteralPath $item.Backup -Destination $item.Target -Force
            }
            throw
        }

        foreach ($item in $moved) {
            Remove-Item -LiteralPath $item.Backup -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-UpdateLog $PackageRoot "Güncellendi: $($Manifest.versionName) (versionCode $($Manifest.versionCode))."
        return $true
    }
    finally {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AssistantUpdateCheck {
    <#
    .SYNOPSIS
        Açılışta çağrılır. Güncelleme kurulduysa $true döner — çağıran asistanı yeniden
        başlatıp çıkmalıdır.
    .PARAMETER Silent
        Pencere gösterme (test / snapshot modu). Zorunlu güncelleme yine de kurulur.
    #>
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$AssistantDir,
        [switch]$Silent
    )

    $info = Get-AssistantVersionInfo -AssistantDir $AssistantDir
    if (-not $info) { return $false }

    $manifest = Get-AssistantUpdate -Info $info -PackageRoot $PackageRoot
    if (-not $manifest) { return $false }

    $mandatory = [bool](Get-Prop $manifest 'mandatory' $false)
    $notes = Get-Prop $manifest 'notes' ''
    $sizeText = Format-Size ([double](Get-Prop $manifest 'sizeBytes' 0))

    if (-not $Silent -and -not $mandatory) {
        $text = "Asistanın yeni sürümü var: $($manifest.versionName)`r`n" +
                "(şu anki sürüm: $($info.VersionName))`r`n`r`n"
        if ($notes) { $text += "$notes`r`n`r`n" }
        $text += "İndirilecek: $sizeText`r`n`r`nŞimdi güncellensin mi?"

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $text, 'ETS2 Mod Asistanı', 'YesNo', 'Question')
        if ($answer -ne 'Yes') {
            Write-UpdateLog $PackageRoot "Kullanıcı erteledi: $($manifest.versionName)."
            return $false
        }
    }

    try {
        $installed = Install-AssistantUpdate -Manifest $manifest -PackageRoot $PackageRoot
    } catch {
        Write-UpdateLog $PackageRoot "Güncelleme BAŞARISIZ: $($_.Exception.Message)"
        if (-not $Silent) {
            # ⚠️ Zorunlu güncelleme bile olsa asistan AÇILIR. Sunucu tarafındaki bir
            #    sorun yüzünden kullanıcıyı programsız bırakmak, güncellemenin
            #    çözdüğünden daha büyük bir sorun olurdu.
            [System.Windows.Forms.MessageBox]::Show(
                "Güncelleme kurulamadı, asistan mevcut sürümle açılıyor.`r`n`r`n$($_.Exception.Message)",
                'ETS2 Mod Asistanı', 'OK', 'Warning') | Out-Null
        }
        return $false
    }

    if ($installed -and -not $Silent) {
        [System.Windows.Forms.MessageBox]::Show(
            "Asistan $($manifest.versionName) sürümüne güncellendi. Yeniden başlatılıyor.",
            'ETS2 Mod Asistanı', 'OK', 'Information') | Out-Null
    }

    return $installed
}
