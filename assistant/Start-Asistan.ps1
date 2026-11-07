<#
.SYNOPSIS
    ETS2 Mod Asistanı. Host'un verdiği paket klasöründeki Asistan.cmd ile açılır.

.DESCRIPTION
    Hangi dosyanın nereden indirileceğini sırayla gösterir, indirme sayfasını tarayıcıda açar,
    İndirilenler klasörünü izleyip biten dosyaları doğrular ve paketin "indirilenler" klasörüne alır,
    sitelerin bekleme sürelerini sayar, sonunda arşivleri açıp modları kurar.
    Siteye giriş ve indirme düğmesine basma işini kullanıcı kendi tarayıcısında yapar;
    asistan şifre istemez, saklamaz.

.PARAMETER PackageRoot
    Paket klasörü (paket.json'un olduğu yer). Varsayılan: bu scriptin bir üst klasörü.

.PARAMETER DownloadsPath
    İzlenecek klasör. Varsayılan: Windows'un İndirilenler klasörü.

.PARAMETER Snapshot
    Test için: pencereyi göstermeden sekmelerin görüntüsünü PNG olarak kaydeder ({0} = sekme no).

.PARAMETER NoUpdate
    Açılıştaki güncelleme denetimini atlar. Geliştirirken kullanışlı: repodaki sürümle
    çalışırken sunucudaki yayının çalışma kopyasını ezmesini engeller.
#>
[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$DownloadsPath,
    [string]$Pack,
    [string]$Snapshot,
    [switch]$NoUpdate
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    if (-not $PackageRoot) { $PackageRoot = Split-Path $PSScriptRoot -Parent }
    $PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).ProviderPath
    # Pakette araçlar "araclar" klasöründe, repoda "tools"
    $toolsDir = Join-Path $PackageRoot 'araclar'
    if (-not (Test-Path -LiteralPath (Join-Path $toolsDir 'Ets2Common.ps1'))) { $toolsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools' }
    . (Join-Path $toolsDir 'Ets2Common.ps1')
    . (Join-Path $toolsDir 'AssistantPayload.ps1')
    . (Join-Path $PSScriptRoot 'lib\Asistan.Core.ps1')
    . (Join-Path $PSScriptRoot 'lib\Asistan.Update.ps1')
    . (Join-Path $PSScriptRoot 'lib\Asistan.Gui.ps1')

    # --- Kendini güncelleme ---------------------------------------------------------
    # Pencereden ÖNCE: asistan açıldıktan sonra güncellemek, kullanıcının yarıda kalan
    # bir indirme listesini kaybetmesi demek olurdu. Ağ yoksa ya da sunucu kapalıysa
    # bu çağrı $false döner ve asistan normal açılır (bkz. Asistan.Update.ps1 başlığı).
    #
    # ⚠️ -NoUpdate ve -Snapshot'ta ATLANIR: testin ağa çıkması, sonucu sunucunun o
    #    andaki durumuna bağlar.
    if (-not $NoUpdate -and -not $Snapshot) {
        if (Invoke-AssistantUpdateCheck -PackageRoot $PackageRoot -AssistantDir $PSScriptRoot) {
            # Güncellendi: ÇALIŞAN süreç eski kodu taşıyor (dosyalar belleğe alınmıştı),
            # bu yüzden yeni sürümü ayrı bir süreçte başlatıp çıkıyoruz.
            $self = Join-Path $PackageRoot 'asistan\Start-Asistan.ps1'
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
                                '-File', "`"$self`"", '-PackageRoot', "`"$PackageRoot`"") | Out-Null
            exit 0
        }
    }

    $ctx = New-AssistantContext -PackageRoot $PackageRoot -AssistantDir $PSScriptRoot -ToolsDir $toolsDir -DownloadsPath $DownloadsPath -PackId $Pack
    [System.Windows.Forms.Application]::EnableVisualStyles()
    if ($Snapshot) { Show-AssistantWindow $ctx -Snapshot -SnapshotPath $Snapshot }
    else { Show-AssistantWindow $ctx }
} catch {
    $msg = "$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)"
    try { Set-Content -LiteralPath (Join-Path $PackageRoot 'asistan-hata.log') -Value $msg -Encoding UTF8 } catch { }
    if ($Snapshot) { throw }
    [System.Windows.Forms.MessageBox]::Show("Asistan açılamadı:`r`n`r`n$msg", 'ETS2 Mod Asistanı', 'OK', 'Error') | Out-Null
    exit 1
}
