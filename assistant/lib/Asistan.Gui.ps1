# İndirme asistanının penceresi (WinForms). Motor: Asistan.Core.ps1.

function New-Control([string]$Type, [hashtable]$Props) {
    $c = New-Object "System.Windows.Forms.$Type"
    foreach ($k in $Props.Keys) { $c.$k = $Props[$k] }
    return $c
}

function Show-AssistantWindow {
    param($Ctx, [switch]$Snapshot, [string]$SnapshotPath)
    $fontUi = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontBold = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $fontBig = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $green = [System.Drawing.Color]::FromArgb(0, 120, 40)
    $blue = [System.Drawing.Color]::FromArgb(0, 90, 180)
    $red = [System.Drawing.Color]::FromArgb(190, 20, 20)
    $orange = [System.Drawing.Color]::FromArgb(200, 100, 0)
    $ui = @{ Busy = $false; Current = $null; Items = @{}; Groups = @{}; LastWait = @{}; InstallProc = $null; ExportProc = $null; AddProc = $null; PendingDrop = $null; Prereq = @() }

    $form = New-Control Form @{
        Text = "ETS2 Konvoy İndirme Asistanı $($Ctx.Version)"; Size = New-Object System.Drawing.Size(1000, 720)
        MinimumSize = New-Object System.Drawing.Size(900, 600); StartPosition = 'CenterScreen'; Font = $fontUi
    }

    $tabs = New-Control TabControl @{ Dock = 'Fill' }
    $header = New-Control Panel @{ Dock = 'Top'; Height = 58; Width = 1000; BackColor = [System.Drawing.Color]::FromArgb(32, 48, 72) }
    $header.Controls.Add((New-Control Label @{
                Text = "Dosyalar elindeyse (arşiv ya da .scs) bu pencereye sürükleyip bırak:`r`nasistan açar ve oyuna kurar."
                ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 140); TextAlign = 'MiddleRight'
                Location = New-Object System.Drawing.Point(480, 6); Size = New-Object System.Drawing.Size(500, 46); Anchor = 'Top,Right'
            }))
    $header.Controls.Add((New-Control Label @{ Text = 'ETS2 Konvoy İndirme Asistanı'; Font = $fontBold; ForeColor = 'White'; AutoSize = $true; Location = New-Object System.Drawing.Point(12, 6) }))
    $hostName = Get-Prop $Ctx.Package 'host' 'host'
    $header.Controls.Add((New-Control Label @{
                Text = "$($Ctx.Pack.name)  ·  Host: $hostName  ·  sürüm $($Ctx.Version)"; ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 225)
                AutoSize = $true; Location = New-Object System.Drawing.Point(14, 32)
            }))
    $form.Controls.Add($tabs)
    $form.Controls.Add($header)

    # --- 1. Ön kontrol ---------------------------------------------------------------------
    $tabCheck = New-Control TabPage @{ Text = '1. Ön kontrol'; Padding = New-Object System.Windows.Forms.Padding(10) }
    $lvCheck = New-Control ListView @{ View = 'Details'; FullRowSelect = $true; Dock = 'Fill'; HeaderStyle = 'Nonclickable' }
    [void]$lvCheck.Columns.Add('Kontrol', 340); [void]$lvCheck.Columns.Add('Durum', 80); [void]$lvCheck.Columns.Add('Ayrıntı', 520)
    $pnlCheck = New-Control Panel @{ Dock = 'Bottom'; Height = 50 }
    $btnRecheck = New-Control Button @{ Text = 'Tekrar kontrol et'; Size = New-Object System.Drawing.Size(170, 34); Location = New-Object System.Drawing.Point(0, 10) }
    $lblCheck = New-Control Label @{ AutoSize = $true; Location = New-Object System.Drawing.Point(185, 18) }
    $pnlCheck.Controls.AddRange(@($btnRecheck, $lblCheck))
    $tabCheck.Controls.Add($lvCheck); $tabCheck.Controls.Add($pnlCheck)

    # --- 2. İndir --------------------------------------------------------------------------
    $tabDl = New-Control TabPage @{ Text = '2. İndir'; Padding = New-Object System.Windows.Forms.Padding(10) }
    $pnlAction = New-Control Panel @{ Dock = 'Top'; Height = 205; Width = 950 }
    $lblAction = New-Control Label @{ Font = $fontBold; Location = New-Object System.Drawing.Point(0, 4); Size = New-Object System.Drawing.Size(940, 28); Anchor = 'Top,Left,Right' }
    $lblInstr = New-Control Label @{ Location = New-Object System.Drawing.Point(2, 36); Size = New-Object System.Drawing.Size(630, 112); Anchor = 'Top,Left' }
    $lblWait = New-Control Label @{ Font = $fontBig; ForeColor = $orange; TextAlign = 'MiddleRight'; Location = New-Object System.Drawing.Point(650, 36); Size = New-Object System.Drawing.Size(290, 60); Anchor = 'Top,Right' }
    $lblWaitNote = New-Control Label @{ ForeColor = $orange; TextAlign = 'TopRight'; Location = New-Object System.Drawing.Point(650, 96); Size = New-Object System.Drawing.Size(290, 50); Anchor = 'Top,Right' }
    $btnOpen = New-Control Button @{ Text = 'Sayfayı aç'; Font = $fontBold; Size = New-Object System.Drawing.Size(170, 40); Location = New-Object System.Drawing.Point(0, 155) }
    $btnPick = New-Control Button @{ Text = 'Dosyayı elle seç…'; Size = New-Object System.Drawing.Size(160, 40); Location = New-Object System.Drawing.Point(180, 155) }
    $btnSkip = New-Control Button @{ Text = 'Sonraya bırak'; Size = New-Object System.Drawing.Size(130, 40); Location = New-Object System.Drawing.Point(350, 155) }
    $chkPremium = New-Control CheckBox @{ Text = 'ProMods Premium aldım (bekleme yok, tek dosya)'; AutoSize = $true; Location = New-Object System.Drawing.Point(500, 165) }
    $chkPremium.Visible = Test-HasVariant $Ctx 'premium'
    $chkPremium.Checked = ($Ctx.State.PreferredVariant -eq 'premium')
    $pnlAction.Controls.AddRange(@($lblAction, $lblInstr, $lblWait, $lblWaitNote, $btnOpen, $btnPick, $btnSkip, $chkPremium))

    $lvFiles = New-Control ListView @{ View = 'Details'; FullRowSelect = $true; Dock = 'Fill'; HeaderStyle = 'Nonclickable'; ShowGroups = $true }
    [void]$lvFiles.Columns.Add('Dosya', 330); [void]$lvFiles.Columns.Add('Boyut', 100); [void]$lvFiles.Columns.Add('Durum', 470)

    $pnlBottom = New-Control Panel @{ Dock = 'Bottom'; Height = 62; Width = 950 }
    $progress = New-Control ProgressBar @{ Location = New-Object System.Drawing.Point(0, 8); Size = New-Object System.Drawing.Size(620, 20); Anchor = 'Top,Left,Right'; Maximum = 1000 }
    $lblTotal = New-Control Label @{ Location = New-Object System.Drawing.Point(630, 8); Size = New-Object System.Drawing.Size(310, 22); Anchor = 'Top,Right' }
    $lblWatch = New-Control Label @{ Location = New-Object System.Drawing.Point(0, 36); Size = New-Object System.Drawing.Size(700, 22); Anchor = 'Top,Left,Right'; ForeColor = 'DimGray' }
    $btnFolder = New-Control Button @{ Text = 'İndirilenler klasörünü aç'; Size = New-Object System.Drawing.Size(220, 28); Location = New-Object System.Drawing.Point(720, 32); Anchor = 'Top,Right' }
    $pnlBottom.Controls.AddRange(@($progress, $lblTotal, $lblWatch, $btnFolder))
    $tabDl.Controls.Add($lvFiles); $tabDl.Controls.Add($pnlBottom); $tabDl.Controls.Add($pnlAction)

    # --- 3. Kur ----------------------------------------------------------------------------
    $tabInstall = New-Control TabPage @{ Text = '3. Kur'; Padding = New-Object System.Windows.Forms.Padding(14); Size = New-Object System.Drawing.Size(970, 600) }
    $lblInstallInfo = New-Control Label @{
        Location = New-Object System.Drawing.Point(14, 14); Size = New-Object System.Drawing.Size(920, 80); Anchor = 'Top,Left,Right'
        Text = "Bütün dosyalar inince bu düğme açılır. Asistan arşivleri açar, modları oyunun mod klasörüne kopyalar ve`r`nher birini host'un dosyasıyla karşılaştırır. Ayrı bir siyah pencere açılır; iş bitene kadar kapatma.`r`nAynı adlı eski mod dosyaların varsa host'unkiyle değiştirilir. Pencereye sürükleyip bıraktığın dosyalar ise hemen kurulur."
    }
    $btnInstall = New-Control Button @{ Text = 'Arşivleri aç ve kur'; Font = $fontBold; Size = New-Object System.Drawing.Size(240, 44); Location = New-Object System.Drawing.Point(14, 100); Enabled = $false }
    $lblInstall = New-Control Label @{ Location = New-Object System.Drawing.Point(270, 104); Size = New-Object System.Drawing.Size(660, 90); Anchor = 'Top,Left,Right' }
    $lblInstSum = New-Control Label @{ Font = $fontBold; Location = New-Object System.Drawing.Point(14, 154); Size = New-Object System.Drawing.Size(250, 44) }
    $lblExportInfo = New-Control Label @{
        Location = New-Object System.Drawing.Point(14, 210); Size = New-Object System.Drawing.Size(920, 66); Anchor = 'Top,Left,Right'
        Text = "Kurulumdan sonra: oyunu aç, Mod Yöneticisi'nde modları '4. Mod sırası' sekmesindeki sırayla etkinleştir, profili yükle,`r`nbiraz sür ve oyundan çık. Sonra aşağıdaki düğmeyle kontrol dosyanı oluştur ve host'a gönder."
    }
    $lblName = New-Control Label @{ Text = 'Adın:'; AutoSize = $true; Location = New-Object System.Drawing.Point(14, 290) }
    $txtName = New-Control TextBox @{ Text = (Get-Prop $Ctx.Package 'playerLabel' 'arkadas'); Size = New-Object System.Drawing.Size(150, 26); Location = New-Object System.Drawing.Point(64, 287) }
    $btnExport = New-Control Button @{ Text = 'Kontrol dosyasını oluştur'; Size = New-Object System.Drawing.Size(220, 34); Location = New-Object System.Drawing.Point(230, 282) }
    $lblExport = New-Control Label @{ Location = New-Object System.Drawing.Point(14, 326); Size = New-Object System.Drawing.Size(920, 60); Anchor = 'Top,Left,Right' }
    $tabInstall.Controls.AddRange(@($lblInstallInfo, $btnInstall, $lblInstall, $lblInstSum, $lblExportInfo, $lblName, $txtName, $btnExport, $lblExport))

    # --- 4. Mod sırası ---------------------------------------------------------------------
    $tabOrder = New-Control TabPage @{ Text = '4. Mod sırası'; Padding = New-Object System.Windows.Forms.Padding(10) }
    $lblOrder = New-Control Label @{
        Dock = 'Top'; Height = 48
        Text = "Oyunda Profil → Mod Yöneticisi'nde bu modları etkinleştir ve YUKARIDAN AŞAĞIYA bu sırayla diz.`r`nBaşka mod ekleme; konvoyda host'la birebir aynı liste olmalı."
    }
    $lvOrder = New-Control ListView @{ View = 'Details'; FullRowSelect = $true; Dock = 'Fill'; HeaderStyle = 'Nonclickable' }
    [void]$lvOrder.Columns.Add('#', 40); [void]$lvOrder.Columns.Add('Mod Yöneticisi''nde görünen ad', 480); [void]$lvOrder.Columns.Add('Dosya', 380)
    $order = @(Get-HostLoadOrder $Ctx)
    $i = 0
    foreach ($o in $order) {
        $i++
        $it = New-Object System.Windows.Forms.ListViewItem([string]$i)
        [void]$it.SubItems.Add($o.Name); [void]$it.SubItems.Add($o.Package)
        [void]$lvOrder.Items.Add($it)
    }
    if (-not $order.Count) { $lblOrder.Text = 'Host''un mod sırası pakette yok. Sırayı host''a sor.' }
    $tabOrder.Controls.Add($lvOrder); $tabOrder.Controls.Add($lblOrder)

    $tabs.TabPages.AddRange(@($tabCheck, $tabDl, $tabInstall, $tabOrder))

    # --- Davranış ---------------------------------------------------------------------------
    $statusText = { param($t) $lblWatch.Text = $t; [System.Windows.Forms.Application]::DoEvents() }

    $fillPrereq = {
        $lvCheck.Items.Clear()
        $ui.Prereq = @(Get-PrerequisiteReport $Ctx)
        foreach ($p in $ui.Prereq) {
            $it = New-Object System.Windows.Forms.ListViewItem($p.Name)
            $label = switch ($p.State) { 'ok' { 'Tamam' } 'warn' { 'Uyarı' } default { 'SORUN' } }
            [void]$it.SubItems.Add($label); [void]$it.SubItems.Add($p.Detail)
            $it.ForeColor = switch ($p.State) { 'ok' { $green } 'warn' { $orange } default { $red } }
            [void]$lvCheck.Items.Add($it)
        }
        $bad = @($ui.Prereq | Where-Object { $_.State -eq 'fail' }).Count
        $lblCheck.Text = if ($bad) { "$bad sorun var. Çözüp 'Tekrar kontrol et'e bas. İndirmeye yine de başlayabilirsin." } else { 'Her şey hazır. "2. İndir" sekmesine geç.' }
        $lblCheck.ForeColor = if ($bad) { $red } else { $green }
    }

    $buildList = {
        $lvFiles.BeginUpdate()
        $lvFiles.Items.Clear(); $lvFiles.Groups.Clear(); $ui.Items = @{}; $ui.Groups = @{}
        foreach ($mod in $Ctx.Mods) {
            $g = New-Object System.Windows.Forms.ListViewGroup($mod.Id, $mod.Name)
            [void]$lvFiles.Groups.Add($g); $ui.Groups[$mod.Id] = $g
            foreach ($spec in (Get-ActiveVariant $Ctx $mod).Files) {
                $it = New-Object System.Windows.Forms.ListViewItem($spec.Display, $g)
                [void]$it.SubItems.Add($(if ($spec.Size) { Format-Size $spec.Size } else { '?' })); [void]$it.SubItems.Add('')
                [void]$lvFiles.Items.Add($it); $ui.Items[$spec.Key] = $it
            }
        }
        $lvFiles.EndUpdate()
    }

    $refresh = {
        $act = Get-NextAction $Ctx
        $ui.Current = $act.Item
        foreach ($mod in $Ctx.Mods) {
            $complete = Test-ModComplete $mod
            $files = (Get-ActiveVariant $Ctx $mod).Files
            $doneCount = @($files | Where-Object { $_.Status -eq 'done' }).Count
            $ui.Groups[$mod.Id].Header = if ($mod.Installed) { "$($mod.Name) $($mod.Version)  –  oyuna kurulu ✓" } elseif ($complete) { "$($mod.Name) $($mod.Version)  –  tamam ✓" } else { "$($mod.Name) $($mod.Version)  –  $doneCount / $($files.Count)" }
            foreach ($spec in $files) {
                $it = $ui.Items[$spec.Key]
                if (-not $it) { continue }
                $text, $color = if ($mod.Installed) { 'Oyuna kurulu ✓', $green }
                elseif ($complete -or $spec.Status -eq 'done') { "Tamam ✓  $($spec.Detail)", $green }
                elseif ($spec.Status -eq 'downloading') { "İniyor… %$($spec.Percent)", $blue }
                elseif ($spec.Status -eq 'error') { $spec.Detail, $red }
                elseif ($ui.Current -and $ui.Current.Spec.Key -eq $spec.Key) { '◀ Sıradaki', $orange }
                else { "Bekliyor  $($spec.Detail)", [System.Drawing.SystemColors]::WindowText }
                if ($it.SubItems[2].Text -ne $text) { $it.SubItems[2].Text = $text }
                if ($it.ForeColor -ne $color) { $it.ForeColor = $color }
            }
        }

        $waitLines = @()
        foreach ($g in $act.Waits.Keys) {
            $w = $act.Waits[$g]
            $site = @($Ctx.Mods | Where-Object { @($_.Variants | Where-Object { $_.CooldownGroup -eq $g }).Count } | ForEach-Object { $_.Site }) | Select-Object -First 1
            if (-not $site) { $site = $g }
            if ($w.Busy) { $waitLines += "$site dosyası iniyor" }
            else { $waitLines += ('{0}: {1}:{2:00}' -f $site, [math]::Floor($w.Remaining / 60), ($w.Remaining % 60)) }
        }
        # Bekleme bitince sesli uyarı
        foreach ($g in @($ui.LastWait.Keys)) {
            if (-not $act.Waits.ContainsKey($g)) { [System.Media.SystemSounds]::Exclamation.Play(); $ui.LastWait.Remove($g) }
        }
        foreach ($g in $act.Waits.Keys) { $ui.LastWait[$g] = $true }

        $lblWait.Text = ($waitLines -join "`r`n")
        $lblWaitNote.Text = if ($act.Waits.Count) { "Süre dolmadan o sitede yeni dosyaya basma, sayaç baştan başlar." } else { '' }

        switch ($act.Kind) {
            'download' {
                $m = $act.Item.Mod; $v = $act.Item.Variant; $s = $act.Item.Spec
                $lblAction.Text = "Sıradaki: $($s.Display)   ($($m.Name) $($m.Version))"
                $lines = @()
                foreach ($l in @($v.Instructions) + @($m.Notes)) { $lines += '• ' + ($l -replace '\{file\}', $s.Display) }
                if ($s.Status -eq 'error') { $lines = @("• Önceki indirme hatalıydı: $($s.Detail)") + $lines }
                $lines += '• İnen dosyayı asistan kendisi bulur ve doğrular; sen bir şey taşıma.'
                $lines += '• Dosyalar zaten elindeyse indirme: pencereye sürükleyip bırak.'
                $lblInstr.Text = $lines -join "`r`n"
                $btnOpen.Enabled = $true; $btnPick.Enabled = $true; $btnSkip.Enabled = $true
                $form.Text = "ETS2 Konvoy İndirme Asistanı $($Ctx.Version)"
            }
            'wait' {
                $lblAction.Text = 'Bekleme süresi doluyor…'
                $lblInstr.Text = "• Şu an indirilecek başka dosya yok. Sayaç bitince asistan ses çıkarır ve sıradaki dosyayı gösterir.`r`n• Pencereyi açık bırak, bilgisayarı uyku moduna alma."
                $btnOpen.Enabled = $false; $btnPick.Enabled = $true; $btnSkip.Enabled = $false
                $form.Text = "($($waitLines -join ', ')) ETS2 Konvoy İndirme Asistanı"
            }
            'downloading' {
                $lblAction.Text = 'İndirmeler sürüyor…'
                $lblInstr.Text = '• Tarayıcıdaki indirmelerin bitmesini bekle. Biten dosyalar otomatik olarak alınır.'
                $btnOpen.Enabled = $false; $btnPick.Enabled = $true; $btnSkip.Enabled = $false
            }
            'done' {
                $lblAction.Text = 'Bütün dosyalar indi ✓'
                $lblInstr.Text = '• "3. Kur" sekmesine geç ve "Arşivleri aç ve kur" düğmesine bas.'
                if (-not @($Ctx.Mods | Where-Object { -not $_.Installed }).Count) {
                    $lblAction.Text = 'Bütün modlar oyuna kurulu ✓'
                    $lblInstr.Text = '• "4. Mod sırası" sekmesindeki sırayla modları oyunda etkinleştir.'
                }
                $btnOpen.Enabled = $false; $btnPick.Enabled = $false; $btnSkip.Enabled = $false
                $form.Text = "ETS2 Konvoy İndirme Asistanı $($Ctx.Version)"
            }
        }

        $t = Get-DownloadTotals $Ctx
        $progress.Value = if ($t.TotalBytes) { [int](1000 * $t.DoneBytes / $t.TotalBytes) } else { 0 }
        $lblTotal.Text = "$($t.DoneFiles) / $($t.Files) dosya  ·  $(Format-Size $t.DoneBytes) / $(Format-Size $t.TotalBytes)"
        $hostOk = -not @(Get-HostFileReport $Ctx | Where-Object { $_.State -ne 'ok' }).Count
        $btnInstall.Enabled = ($act.Kind -eq 'done') -and $hostOk -and -not $ui.InstallProc -and -not $ui.AddProc
        $sum = Get-InstallSummary $Ctx
        $lblInstSum.Text = if ($sum.Total -and $sum.Installed -eq $sum.Total) { "Oyunda kurulu: $($sum.Total) / $($sum.Total) ✓" } else { "Oyunda kurulu: $($sum.Installed) / $($sum.Total)" }
        $lblInstSum.ForeColor = if ($sum.Total -and $sum.Installed -eq $sum.Total) { $green } else { [System.Drawing.SystemColors]::ControlText }
        if ($act.Kind -eq 'done' -and -not $hostOk) { $lblInstall.Text = 'Host''tan gelen dosya eksik/farklı, "1. Ön kontrol" sekmesine bak.'; $lblInstall.ForeColor = $red }
    }

    $handleDrop = {
        # Sürükle-bırak olayında soru sorulmaz (Gezgin bırakma bitene kadar donar); zamanlayıcıdan çağrılır
        $paths = @($ui.PendingDrop); $ui.PendingDrop = $null
        if ($ui.AddProc -or $ui.InstallProc) {
            [System.Windows.Forms.MessageBox]::Show($form, 'Önceki kurulum hâlâ sürüyor. Siyah pencere kapanınca tekrar bırak.', 'Dosya ekleme') | Out-Null
            return
        }
        $names = @($paths | ForEach-Object { [System.IO.Path]::GetFileName($_) })
        $shown = if ($names.Count -gt 12) { (@($names[0..11]) -join "`r`n") + "`r`n… ve $($names.Count - 12) tane daha" } else { $names -join "`r`n" }
        $q = [System.Windows.Forms.MessageBox]::Show($form,
            "Bırakılanlar:`r`n$shown`r`n`r`nArşivler açılıp modlar oyunun mod klasörüne kurulacak; host'un listesindekiler host'unkiyle karşılaştırılır.`r`nOyun kapalı olmalı. Devam edilsin mi?",
            'Dosyaları kur', 'YesNo', 'Question')
        if ($q -ne 'Yes') { return }
        $rf = Join-Path $Ctx.PackageRoot 'birakma-sonucu.json'
        if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
        $ui.AddProc = Start-DropInstall $Ctx $paths $rf
        $tabs.SelectedTab = $tabInstall
        $lblInstall.Text = 'Bırakılan dosyalar kuruluyor… Siyah pencerede "Bitti" yazınca Enter''a bas.'; $lblInstall.ForeColor = $blue
    }

    $showAddResult = {
        param($res)
        if (-not $res) { $lblInstall.Text = 'Kurulum yarıda kaldı ya da hata verdi.'; $lblInstall.ForeColor = $red; return }
        if (Get-Prop $res 'Error') { $lblInstall.Text = "Hata: $($res.Error)"; $lblInstall.ForeColor = $red; return }
        $lines = @("Kurulan / zaten kurulu: $(@(Get-Prop $res 'Installed' @()).Count) dosya")
        $diff = @(Get-Prop $res 'Different' @()); if ($diff.Count) { $lines += "Host'unkinden FARKLI, kurulmadı: $($diff -join ', ')" }
        $unl = @(Get-Prop $res 'Unlisted' @()); if ($unl.Count) { $lines += "Host'un listesinde yok (kuruldu ama konvoyda etkinleştirme): $($unl -join ', ')" }
        $mp = @(Get-Prop $res 'MissingParts' @()); if ($mp.Count) { $lines += "Parçası eksik, açılamadı: $($mp -join '; ')" }
        $ign = @(Get-Prop $res 'Ignored' @()); if ($ign.Count) { $lines += "Mod dosyası değil, atlandı: $($ign -join ', ')" }
        $lblInstall.Text = $lines -join "`r`n"
        $lblInstall.ForeColor = if ($diff.Count -or $mp.Count) { $red } else { $green }
    }

    $tick = {
        if ($ui.Busy) { return }
        $ui.Busy = $true
        try {
            if ($ui.PendingDrop) { & $handleDrop }
            $lblWatch.Text = "İzlenen klasör: $($Ctx.DownloadsPath)"
            [void](Update-InstalledState $Ctx)
            [void](Update-AssistantDownloads $Ctx -Notify $statusText)
            $lblWatch.Text = "İzlenen klasör: $($Ctx.DownloadsPath)   (tarayıcın başka yere kaydediyorsa 'Dosyayı elle seç' kullan)"
            & $refresh
            foreach ($p in @('InstallProc', 'ExportProc', 'AddProc')) {
                $proc = $ui[$p]
                if ($proc -and $proc.HasExited) {
                    $ui[$p] = $null
                    $rf = Join-Path $Ctx.PackageRoot $(switch ($p) { 'InstallProc' { 'kurulum-sonucu.json' } 'AddProc' { 'birakma-sonucu.json' } default { 'kontrol-sonucu.json' } })
                    $res = if (Test-Path -LiteralPath $rf) { Read-JsonFile $rf } else { $null }
                    if ($res -and $p -ne 'ExportProc') {
                        Register-InstalledFiles $Ctx @(Get-Prop $res 'Installed' @())
                        [void](Update-InstalledState $Ctx); & $refresh
                    }
                    if ($p -eq 'AddProc') { & $showAddResult $res; continue }
                    if ($p -eq 'InstallProc') {
                        if ($res -and (Get-Prop $res 'Ok' $false)) {
                            $lblInstall.Text = "Kurulum tamam ✓ Bütün dosyalar host'unkiyle aynı.`r`nŞimdi '4. Mod sırası' sekmesine bak ve oyunu aç."; $lblInstall.ForeColor = $green
                        } elseif ($res -and (Get-Prop $res 'Missing')) {
                            $lblInstall.Text = "Eksik ya da farklı: $((@($res.Missing)) -join ', ')"; $lblInstall.ForeColor = $red
                        } else {
                            $lblInstall.Text = "Kurulum yarıda kaldı ya da hata verdi. $(Get-Prop $res 'Error' '')"; $lblInstall.ForeColor = $red
                        }
                    } elseif ($res -and (Get-Prop $res 'Ok' $false)) {
                        $lblExport.Text = "Oluşturuldu: $($res.File)`r`nBu dosyayı host'a ($hostName) gönder."; $lblExport.ForeColor = $green
                        Start-Process explorer.exe -ArgumentList "/select,`"$($res.File)`""
                    } else {
                        $lblExport.Text = "Oluşturulamadı. $(Get-Prop $res 'Error' '')"; $lblExport.ForeColor = $red
                    }
                    $btnExport.Enabled = $true
                }
            }
        } catch {
            $lblWatch.Text = "Hata: $($_.Exception.Message)"
        } finally { $ui.Busy = $false }
    }

    $btnRecheck.Add_Click({ & $fillPrereq })
    $btnOpen.Add_Click({ if ($ui.Current) { Start-Process $ui.Current.Spec.Url } })
    $btnSkip.Add_Click({ if ($ui.Current) { $Ctx.Skipped[$ui.Current.Spec.Key] = $true; & $refresh } })
    $btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($Ctx.DownloadsPath)`"" })
    $chkPremium.Add_CheckedChanged({
            $Ctx.State.PreferredVariant = if ($chkPremium.Checked) { 'premium' } else { 'free' }
            Save-AssistantState $Ctx
            & $buildList; & $refresh
        })
    $btnPick.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Title = 'İndirdiğin dosyayı seç'
            $dlg.InitialDirectory = $Ctx.DownloadsPath
            $dlg.Multiselect = $true
            if ($dlg.ShowDialog($form) -ne 'OK') { return }
            $ui.Busy = $true
            try {
                $msgs = foreach ($f in $dlg.FileNames) { & $statusText "Doğrulanıyor: $([System.IO.Path]::GetFileName($f))"; (Add-ManualFile $Ctx $f $ui.Current).Message }
                [System.Windows.Forms.MessageBox]::Show($form, ($msgs -join "`r`n"), 'Dosya ekleme') | Out-Null
            } finally { $ui.Busy = $false }
            & $refresh
        })
    $btnInstall.Add_Click({
            $q = [System.Windows.Forms.MessageBox]::Show($form,
                "Arşivler açılıp oyunun mod klasörüne kurulacak (birkaç dakika sürer).`r`nOyun kapalı olmalı. Devam edilsin mi?", 'Kurulum', 'YesNo', 'Question')
            if ($q -ne 'Yes') { return }
            $rf = Join-Path $Ctx.PackageRoot 'kurulum-sonucu.json'
            if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
            $ui.InstallProc = Start-AssistantTask $Ctx install -ResultFile $rf
            $btnInstall.Enabled = $false
            $lblInstall.Text = 'Kurulum sürüyor… Siyah pencerede "Bitti" yazınca Enter''a bas.'; $lblInstall.ForeColor = $blue
        })
    $btnExport.Add_Click({
            $label = ($txtName.Text.Trim().ToLowerInvariant() -replace '[^a-z0-9_-]', '')
            if (-not $label) { $label = 'arkadas' }
            $rf = Join-Path $Ctx.PackageRoot 'kontrol-sonucu.json'
            if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
            $ui.ExportProc = Start-AssistantTask $Ctx export -Label $label -ResultFile $rf
            $btnExport.Enabled = $false
            $lblExport.Text = 'Oluşturuluyor… (oyun kapalı olmalı)'; $lblExport.ForeColor = $blue
        })

    # Sürükle-bırak: pencerenin her yerine dosya/klasör bırakılabilir
    $onDragEnter = { param($s, $e) if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } }
    $onDragDrop = { param($s, $e) $ui.PendingDrop = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) }
    $enableDrop = {
        param($c)
        $c.AllowDrop = $true; $c.Add_DragEnter($onDragEnter); $c.Add_DragDrop($onDragDrop)
        foreach ($ch in $c.Controls) { & $enableDrop $ch }
    }
    & $enableDrop $form

    & $fillPrereq
    & $buildList
    [void](Update-InstalledState $Ctx)
    & $tick
    $tabs.SelectedTab = if (@($ui.Prereq | Where-Object { $_.State -eq 'fail' }).Count) { $tabCheck } else { $tabDl }

    if ($Snapshot) {
        # Test için: pencere saydam açılır, her sekmenin görüntüsü kaydedilir, kapanır
        $form.Opacity = 0
        $form.Add_Shown({
                foreach ($tp in $tabs.TabPages) {
                    $tabs.SelectedTab = $tp
                    $form.Refresh(); [System.Windows.Forms.Application]::DoEvents()
                    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
                    $bmp.Save(($SnapshotPath -f $tabs.TabPages.IndexOf($tp)), [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                }
                $form.Close()
            })
        [void]$form.ShowDialog()
        $form.Dispose()
        return
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick($tick)
    $timer.Start()
    $form.Add_FormClosing({ $timer.Stop(); Save-AssistantState $Ctx })
    [void]$form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()
}
