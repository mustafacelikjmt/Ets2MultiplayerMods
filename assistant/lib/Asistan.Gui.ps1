# İndirme asistanının penceresi (WinForms, koyu tema). Motor: Asistan.Core.ps1.
# Windows'un sekme (TabControl) ve ilerleme çubuğu koyu renge boyanamadığı için sayfa geçişi,
# liste başlıkları ve ilerleme çubuğu burada çiziliyor.

$script:T = @{
    Bg         = [System.Drawing.Color]::FromArgb(22, 25, 31)
    HeaderBg   = [System.Drawing.Color]::FromArgb(15, 18, 24)
    NavBg      = [System.Drawing.Color]::FromArgb(27, 31, 39)
    Surface    = [System.Drawing.Color]::FromArgb(30, 34, 42)
    Surface2   = [System.Drawing.Color]::FromArgb(40, 45, 56)
    Hover      = [System.Drawing.Color]::FromArgb(52, 58, 71)
    Selected   = [System.Drawing.Color]::FromArgb(38, 52, 78)
    Border     = [System.Drawing.Color]::FromArgb(52, 58, 70)
    Text       = [System.Drawing.Color]::FromArgb(230, 233, 239)
    Muted      = [System.Drawing.Color]::FromArgb(150, 159, 174)
    Disabled   = [System.Drawing.Color]::FromArgb(95, 102, 115)
    Accent     = [System.Drawing.Color]::FromArgb(76, 141, 255)
    AccentDark = [System.Drawing.Color]::FromArgb(54, 112, 220)
    AccentDim  = [System.Drawing.Color]::FromArgb(36, 54, 88)
    Green      = [System.Drawing.Color]::FromArgb(70, 200, 110)
    Red        = [System.Drawing.Color]::FromArgb(255, 105, 97)
    Orange     = [System.Drawing.Color]::FromArgb(255, 170, 60)
    Amber      = [System.Drawing.Color]::FromArgb(255, 214, 130)
    Font       = New-Object System.Drawing.Font('Segoe UI', 10)
    FontSmall  = New-Object System.Drawing.Font('Segoe UI', 9)
    FontSemi   = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    FontTitle  = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    FontH2     = New-Object System.Drawing.Font('Segoe UI Semibold', 12.5)
    FontBig    = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
    FontDrop   = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
}

# Koyu kaydırma çubukları ve koyu başlık çubuğu (Windows 10 1809+ / 11); olmazsa sessizce geçilir
try {
    if (-not ('Ets2Konvoy.NativeUi' -as [type])) {
        Add-Type -Namespace Ets2Konvoy -Name NativeUi -MemberDefinition @'
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string app, string idList);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr w, IntPtr l);
[DllImport("uxtheme.dll", EntryPoint = "#135")] public static extern int SetPreferredAppMode(int mode);
[DllImport("uxtheme.dll", EntryPoint = "#133")] public static extern bool AllowDarkModeForWindow(IntPtr hWnd, bool allow);
[DllImport("uxtheme.dll", EntryPoint = "#104")] public static extern void RefreshImmersiveColorPolicyState();
'@
    }
    $script:NativeUi = $true
    # 2 = her zaman koyu (kaydırma çubukları koyu çizilsin). Belgesiz; eski Windows'ta yoksa hata yutulur.
    try { [void][Ets2Konvoy.NativeUi]::SetPreferredAppMode(2); [Ets2Konvoy.NativeUi]::RefreshImmersiveColorPolicyState() } catch { }
} catch { $script:NativeUi = $false }

function New-Control([string]$Type, [hashtable]$Props) {
    $c = New-Object "System.Windows.Forms.$Type"
    foreach ($k in $Props.Keys) { $c.$k = $Props[$k] }
    return $c
}

function Add-Stack($Parent, [object[]]$Controls) {
    # Dock'lu kontrolleri yukarıdan aşağıya verilen sırayla yerleştirir (Fill olan en sona)
    foreach ($c in $Controls) { $Parent.Controls.Add($c); $c.BringToFront() }
}

function New-Spacer([int]$Height = 12, [string]$Dock = 'Top') {
    New-Control Panel @{ Dock = $Dock; Height = $Height; BackColor = [System.Drawing.Color]::Transparent }
}

function New-Text([string]$Text, $Font = $script:T.Font, $Color = $script:T.Text, [int]$Height = 24) {
    New-Control Label @{ Text = $Text; Font = $Font; ForeColor = $Color; Dock = 'Top'; Height = $Height; AutoEllipsis = $true; BackColor = [System.Drawing.Color]::Transparent }
}

function New-Button([string]$Text, [int]$Width = 160, [switch]$Primary) {
    $b = New-Control Button @{
        Text = $Text; Width = $Width; Height = 38; FlatStyle = 'Flat'; Cursor = [System.Windows.Forms.Cursors]::Hand
        Font = $(if ($Primary) { $script:T.FontSemi } else { $script:T.Font }); Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
        UseVisualStyleBackColor = $false
    }
    $bg = if ($Primary) { $script:T.Accent } else { $script:T.Surface2 }
    $hover = if ($Primary) { $script:T.AccentDark } else { $script:T.Hover }
    $b.Tag = @{ Bg = $bg; Border = $(if ($Primary) { $script:T.Accent } else { $script:T.Border }) }
    $b.BackColor = $bg; $b.ForeColor = $script:T.Text
    $b.FlatAppearance.BorderColor = $b.Tag.Border
    $b.FlatAppearance.MouseOverBackColor = $hover
    $b.FlatAppearance.MouseDownBackColor = $hover
    # Kapalı düğme: Windows yazıyı zemin renginden koyulaştırıp okunmaz yapıyor; üstüne biz çiziyoruz
    $b.Add_EnabledChanged({ param($s, $e) $s.BackColor = if ($s.Enabled) { $s.Tag.Bg } else { $script:T.Surface }; $s.Invalidate() })
    $b.Add_Paint({
            param($s, $e)
            if ($s.Enabled) { return }
            $r = $s.ClientRectangle
            $br = New-Object System.Drawing.SolidBrush($script:T.Surface); $e.Graphics.FillRectangle($br, $r); $br.Dispose()
            $pen = New-Object System.Drawing.Pen($script:T.Border); $e.Graphics.DrawRectangle($pen, 0, 0, $r.Width - 1, $r.Height - 1); $pen.Dispose()
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $s.Text, $s.Font, $r, $script:T.Disabled,
                [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix')
        })
    return $b
}

function Set-Text($Control, [string]$Text) {
    # Sadece değiştiyse yaz: her saniyelik yenilemede aynı yazıyı tekrar atamak yazıyı titretiyor
    if ($Control.Text -cne $Text) { $Control.Text = $Text }
}

function New-CheckBox([string]$Text) {
    # Koyu zeminde Windows'un düz (Flat) kutusunun tiki görünmüyor; kutu ve yazı tamamen burada çiziliyor
    $c = New-Control CheckBox @{
        Text = $Text; AutoSize = $false; ForeColor = $script:T.Text; Font = $script:T.Font; FlatStyle = 'Flat'
        Cursor = [System.Windows.Forms.Cursors]::Hand; BackColor = $script:T.Surface
    }
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $c.Font)
    $c.Size = New-Object System.Drawing.Size(($sz.Width + 34), 30)
    $c.Tag = @{ Hot = $false }
    $c.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; $s.Invalidate() })
    $c.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; $s.Invalidate() })
    $c.Add_CheckedChanged({ param($s, $e) $s.Invalidate() })
    $c.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.Clear($s.BackColor)
            $g.SmoothingMode = 'AntiAlias'
            $box = New-Object System.Drawing.Rectangle(1, [int](($s.Height - 18) / 2), 18, 18)
            if ($s.Checked) {
                $br = New-Object System.Drawing.SolidBrush($script:T.Accent); $g.FillRectangle($br, $box); $br.Dispose()
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
                $g.DrawLines($pen, [System.Drawing.PointF[]]@(
                        (New-Object System.Drawing.PointF(($box.X + 4), ($box.Y + 9.5))),
                        (New-Object System.Drawing.PointF(($box.X + 7.5), ($box.Y + 13))),
                        (New-Object System.Drawing.PointF(($box.X + 14), ($box.Y + 5)))))
                $pen.Dispose()
            } else {
                $br = New-Object System.Drawing.SolidBrush($script:T.Surface2); $g.FillRectangle($br, $box); $br.Dispose()
                $pen = New-Object System.Drawing.Pen($(if ($s.Tag.Hot) { $script:T.Accent } else { $script:T.Muted }), 1.4)
                $g.DrawRectangle($pen, $box); $pen.Dispose()
            }
            $tr = New-Object System.Drawing.Rectangle(28, 0, ($s.Width - 28), $s.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $tr, $s.ForeColor,
                [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, NoPrefix')
        })
    return $c
}

function New-Card([int]$Height, [string]$Dock = 'Top') {
    $p = New-Control Panel @{ Dock = $Dock; Height = $Height; BackColor = $script:T.Surface; Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14) }
    $p.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen($script:T.Border)
            $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose()
        })
    return $p
}

function New-Flow([int]$Height = 44) {
    New-Control FlowLayoutPanel @{ Dock = 'Top'; Height = $Height; WrapContents = $false; BackColor = [System.Drawing.Color]::Transparent; Padding = New-Object System.Windows.Forms.Padding(0) }
}

function Set-LastColumnFill($Lv) {
    if ($Lv.Columns.Count -lt 2) { return }
    $sum = 0
    for ($i = 0; $i -lt $Lv.Columns.Count - 1; $i++) { $sum += $Lv.Columns[$i].Width }
    $w = [Math]::Max(120, $Lv.ClientSize.Width - $sum - 1)
    if ($Lv.Columns[$Lv.Columns.Count - 1].Width -ne $w) { $Lv.Columns[$Lv.Columns.Count - 1].Width = $w }
}

function New-DarkList([object[]]$Columns) {
    # Sahip çizimli liste: koyu başlık, satır yüksekliği, durum sütunu kendi renginde,
    # Tag = 'group' olan satırlar grup başlığı gibi çizilir.
    $lv = New-Control ListView @{
        View = 'Details'; FullRowSelect = $true; Dock = 'Fill'; HeaderStyle = 'Nonclickable'; OwnerDraw = $true; MultiSelect = $false
        BackColor = $script:T.Surface; ForeColor = $script:T.Text; BorderStyle = 'None'; Font = $script:T.Font; HideSelection = $true
    }
    foreach ($c in $Columns) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $il = New-Object System.Windows.Forms.ImageList
    $il.ImageSize = New-Object System.Drawing.Size(1, 30)
    $lv.SmallImageList = $il
    $lv.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($lv, $true, $null)
    $lv.Add_DrawColumnHeader({
            param($s, $e)
            $br = New-Object System.Drawing.SolidBrush($script:T.NavBg)
            $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
            $pen = New-Object System.Drawing.Pen($script:T.Border)
            $e.Graphics.DrawLine($pen, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1); $pen.Dispose()
            $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 8), $e.Bounds.Y, ($e.Bounds.Width - 12), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $script:T.FontSemi, $r, $script:T.Muted,
                [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis, SingleLine, NoPrefix')
        })
    $lv.Add_DrawItem({ param($s, $e) $e.DrawDefault = $false })
    $lv.Add_DrawSubItem({
            param($s, $e)
            $g = $e.Graphics
            $flags = [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis, SingleLine, NoPrefix'
            if ($e.Item.Tag -eq 'group') {
                if ($e.ColumnIndex -ne 0) { return }
                $r = $e.Item.Bounds
                $br = New-Object System.Drawing.SolidBrush($script:T.Surface); $g.FillRectangle($br, $r); $br.Dispose()
                $pen = New-Object System.Drawing.Pen($script:T.Border)
                $g.DrawLine($pen, $r.X + 8, $r.Bottom - 2, $r.Right - 8, $r.Bottom - 2); $pen.Dispose()
                $tr = New-Object System.Drawing.Rectangle(($r.X + 8), ($r.Y + 4), ($r.Width - 16), ($r.Height - 4))
                [System.Windows.Forms.TextRenderer]::DrawText($g, $e.Item.Text, $script:T.FontSemi, $tr, $e.Item.ForeColor, $flags)
                return
            }
            $bg = if ($e.Item.Selected) { $script:T.Selected } else { $script:T.Surface }
            $br = New-Object System.Drawing.SolidBrush($bg); $g.FillRectangle($br, $e.Bounds); $br.Dispose()
            # Gruplu listede satırlar grup başlığının biraz içinden başlar
            $pad = if ($e.ColumnIndex -eq 0 -and $s.Tag -eq 'grouped') { 22 } else { 8 }
            $tr = New-Object System.Drawing.Rectangle(($e.Bounds.X + $pad), $e.Bounds.Y, ($e.Bounds.Width - $pad - 4), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $e.SubItem.Text, $s.Font, $tr, $e.SubItem.ForeColor, $flags)
        })
    $lv.Add_Resize({ param($s, $e) Set-LastColumnFill $s })
    # Koyu kaydırma çubuğu: tema, pencere tutamacı her (yeniden) oluştuğunda verilmeli
    $lv.Add_HandleCreated({ param($s, $e) Set-DarkNative $s })
    return $lv
}

function New-ListRow($Lv, [string[]]$Texts, [switch]$Group) {
    $it = New-Object System.Windows.Forms.ListViewItem($Texts[0])
    $it.UseItemStyleForSubItems = $false
    $it.ForeColor = if ($Group) { $script:T.Accent } else { $script:T.Text }
    for ($i = 1; $i -lt $Lv.Columns.Count; $i++) {
        $sub = $it.SubItems.Add($(if ($i -lt $Texts.Count) { $Texts[$i] } else { '' }))
        $sub.ForeColor = $script:T.Text
    }
    if ($Group) { $it.Tag = 'group' }
    [void]$Lv.Items.Add($it)
    return $it
}

function Set-DarkNative($Control) {
    if (-not $script:NativeUi) { return }
    try {
        if ($Control -is [System.Windows.Forms.Form]) {
            $on = 1
            [void][Ets2Konvoy.NativeUi]::DwmSetWindowAttribute($Control.Handle, 20, [ref]$on, 4)
        } elseif ($Control -is [System.Windows.Forms.ListView]) {
            try { [void][Ets2Konvoy.NativeUi]::AllowDarkModeForWindow($Control.Handle, $true) } catch { }
            [void][Ets2Konvoy.NativeUi]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $null)
            $hdr = [Ets2Konvoy.NativeUi]::SendMessage($Control.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero)   # LVM_GETHEADER
            if ($hdr -ne [IntPtr]::Zero) { [void][Ets2Konvoy.NativeUi]::SetWindowTheme($hdr, 'DarkMode_ItemsView', $null) }
        } else {
            [void][Ets2Konvoy.NativeUi]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $null)
        }
    } catch { }
}

function Show-AssistantWindow {
    param($Ctx, [switch]$Snapshot, [string]$SnapshotPath)
    $T = $script:T
    $green = $T.Green; $blue = $T.Accent; $red = $T.Red; $orange = $T.Orange
    $ui = @{ Busy = $false; Current = $null; Items = @{}; Groups = @{}; LastWait = @{}; InstallProc = $null; ExportProc = $null; AddProc = $null; CompatProc = $null
        PendingDrop = $null; Prereq = @(); Page = 0; Ratio = 0.0; DragHot = $false
        Bg = $null; AfterMove = $null; DropPaths = @(); LastBackup = $null }

    $form = New-Control Form @{
        Text = "ETS2 Mod Asistanı $($Ctx.Version)"; Size = New-Object System.Drawing.Size(1100, 780)
        MinimumSize = New-Object System.Drawing.Size(980, 700); StartPosition = 'CenterScreen'; Font = $T.Font
        BackColor = $T.Bg; ForeColor = $T.Text
    }
    $form.Add_HandleCreated({ Set-DarkNative $form })
    $iconPath = Join-Path $Ctx.AssistantDir 'assets\asistan.ico'
    if (Test-Path -LiteralPath $iconPath) { try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { } }

    # --- Üst bant ---------------------------------------------------------------------------
    $hostName = Get-Prop $Ctx.Package 'host' 'host'
    $header = New-Control Panel @{ Dock = 'Top'; Height = 72; Width = 1100; BackColor = $T.HeaderBg }
    $header.Controls.Add((New-Control Label @{ Text = 'ETS2 Mod Asistanı'; Font = $T.FontTitle; ForeColor = $T.Text; AutoSize = $true; Location = New-Object System.Drawing.Point(22, 12) }))
    $header.Controls.Add((New-Control Label @{
                Text = "$($Ctx.Pack.name)   ·   Host: $hostName   ·   sürüm $($Ctx.Version)"; ForeColor = $T.Muted; Font = $T.FontSmall
                AutoSize = $true; Location = New-Object System.Drawing.Point(24, 44)
            }))
    $header.Controls.Add((New-Control Label @{
                Text = "Dosyalar elindeyse indirme yapma:`r`npencereye sürükleyip bırak, asistan açar ve kurar."
                ForeColor = $T.Amber; TextAlign = 'MiddleRight'; Font = $T.FontSmall
                Location = New-Object System.Drawing.Point(640, 12); Size = New-Object System.Drawing.Size(436, 48); Anchor = 'Top,Right'
            }))

    # --- Sayfa düğmeleri --------------------------------------------------------------------
    $nav = New-Control FlowLayoutPanel @{ Dock = 'Top'; Height = 50; BackColor = $T.NavBg; Padding = New-Object System.Windows.Forms.Padding(16, 8, 0, 0); WrapContents = $false }
    $navLine = New-Control Panel @{ Dock = 'Top'; Height = 1; BackColor = $T.Border }
    $navButtons = @()
    foreach ($n in '1   Ön kontrol', '2   İndir', '3   Kur', '4   Mod sırası') {
        $b = New-Control Button @{
            Text = $n; AutoSize = $true; Height = 34; FlatStyle = 'Flat'; Font = $T.FontSemi; ForeColor = $T.Muted; BackColor = $T.NavBg
            Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0); Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
            Cursor = [System.Windows.Forms.Cursors]::Hand; UseVisualStyleBackColor = $false; Tag = $navButtons.Count
        }
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $T.Surface2
        $b.FlatAppearance.MouseDownBackColor = $T.Surface2
        $nav.Controls.Add($b); $navButtons += $b
    }

    $content = New-Control Panel @{ Dock = 'Fill'; BackColor = $T.Bg; Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 18) }
    Add-Stack $form @($header, $nav, $navLine, $content)

    function New-Page { New-Control Panel @{ Dock = 'Fill'; BackColor = $T.Bg; Visible = $false } }

    # --- 1. Ön kontrol ----------------------------------------------------------------------
    $pageCheck = New-Page
    $lvCheck = New-DarkList @(@('Kontrol', 360), @('Durum', 90), @('Ayrıntı', 480))
    $checkCard = New-Card 0 'Fill'; $checkCard.Padding = New-Object System.Windows.Forms.Padding(1)
    $checkCard.Controls.Add($lvCheck)
    $flowCheck = New-Flow 52; $flowCheck.Dock = 'Bottom'; $flowCheck.Padding = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    $btnRecheck = New-Button 'Tekrar kontrol et' 170
    $btnClean = New-Button 'Farklı modları kaldır ve yedekle' 280
    $btnBackupOpen = New-Button 'Yedek klasörünü aç' 180
    $btnBackupOpen.Visible = Test-Path -LiteralPath (Get-BackupRoot $Ctx)
    $flowCheck.Controls.AddRange(@($btnRecheck, $btnClean, $btnBackupOpen))
    $lblCheck = New-Text '' $T.FontSemi $T.Muted 28
    Add-Stack $pageCheck @(
        (New-Text 'Ön kontrol' $T.FontH2 $T.Text 30),
        (New-Text 'Oyun sürümü, harita DLC''leri, disk yeri, host''tan gelen dosyalar ve mod klasöründeki diğer modlar. Kırmızı satır varsa önce onu çöz.' $T.Font $T.Muted 26),
        $lblCheck, (New-Spacer 4), $flowCheck, $checkCard)

    # --- 2. İndir ---------------------------------------------------------------------------
    $pageDl = New-Page
    $actionCard = New-Card 254
    $grid = New-Control TableLayoutPanel @{ Dock = 'Fill'; ColumnCount = 2; RowCount = 3; BackColor = [System.Drawing.Color]::Transparent }
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 68)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 32)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 36)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 46)))
    $lblAction = New-Control Label @{ Font = $T.FontH2; ForeColor = $T.Text; Dock = 'Fill'; AutoEllipsis = $true; TextAlign = 'MiddleLeft'; Margin = New-Object System.Windows.Forms.Padding(0) }
    $lblInstr = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Text; Margin = New-Object System.Windows.Forms.Padding(0, 4, 12, 0) }
    $waitBox = New-Control Panel @{ Dock = 'Fill'; BackColor = [System.Drawing.Color]::Transparent; Margin = New-Object System.Windows.Forms.Padding(0) }
    $lblWait = New-Control Label @{ Font = $T.FontBig; ForeColor = $orange; TextAlign = 'MiddleRight'; Dock = 'Top'; Height = 50 }
    $lblWaitNote = New-Control Label @{ ForeColor = $orange; TextAlign = 'TopRight'; Dock = 'Fill'; Font = $T.FontSmall }
    Add-Stack $waitBox @($lblWait, $lblWaitNote)
    $flowDl = New-Flow 46; $flowDl.Dock = 'Fill'; $flowDl.Margin = New-Object System.Windows.Forms.Padding(0)
    $btnOpen = New-Button 'Sayfayı aç' 170 -Primary
    $btnPick = New-Button 'Dosyayı elle seç…' 170
    $btnSkip = New-Button 'Sonraya bırak' 140
    $chkPremium = New-CheckBox 'ProMods Premium aldım (bekleme yok, tek dosya)'
    $chkPremium.Margin = New-Object System.Windows.Forms.Padding(8, 4, 0, 0)
    $chkPremium.Visible = Test-HasVariant $Ctx 'premium'
    $chkPremium.Checked = ($Ctx.State.PreferredVariant -eq 'premium')
    $flowDl.Controls.AddRange(@($btnOpen, $btnPick, $btnSkip, $chkPremium))
    $grid.Controls.Add($lblAction, 0, 0); $grid.SetColumnSpan($lblAction, 2)
    $grid.Controls.Add($lblInstr, 0, 1); $grid.Controls.Add($waitBox, 1, 1)
    $grid.Controls.Add($flowDl, 0, 2); $grid.SetColumnSpan($flowDl, 2)
    $actionCard.Controls.Add($grid)

    $lvFiles = New-DarkList @(@('Dosya', 340), @('Boyut', 100), @('Durum', 420))
    $lvFiles.Tag = 'grouped'
    $filesCard = New-Card 0 'Fill'; $filesCard.Padding = New-Object System.Windows.Forms.Padding(1)
    $filesCard.Controls.Add($lvFiles)

    $bottom = New-Control Panel @{ Dock = 'Bottom'; Height = 78; BackColor = [System.Drawing.Color]::Transparent; Padding = New-Object System.Windows.Forms.Padding(0, 14, 0, 0) }
    $track = New-Control Panel @{ Dock = 'Top'; Height = 8; BackColor = $T.Surface2 }
    $trackFill = New-Control Panel @{ Dock = 'Left'; Width = 0; BackColor = $T.Accent }
    $track.Controls.Add($trackFill)
    $track.Add_Resize({ $trackFill.Width = [int]($track.Width * $ui.Ratio) })
    $rowBottom = New-Control TableLayoutPanel @{ Dock = 'Fill'; ColumnCount = 2; RowCount = 2; BackColor = [System.Drawing.Color]::Transparent; Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0) }
    [void]$rowBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$rowBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
    [void]$rowBottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 50)))
    [void]$rowBottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 50)))
    $lblTotal = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Text; Font = $T.FontSemi; TextAlign = 'MiddleLeft'; Margin = New-Object System.Windows.Forms.Padding(0) }
    $lblWatch = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Muted; Font = $T.FontSmall; TextAlign = 'MiddleLeft'; AutoEllipsis = $true; Margin = New-Object System.Windows.Forms.Padding(0) }
    $btnFolder = New-Button 'İndirilenler klasörünü aç' 210
    $btnFolder.Margin = New-Object System.Windows.Forms.Padding(12, 4, 0, 0)
    $rowBottom.Controls.Add($lblTotal, 0, 0); $rowBottom.Controls.Add($lblWatch, 0, 1)
    $rowBottom.Controls.Add($btnFolder, 1, 0); $rowBottom.SetRowSpan($btnFolder, 2)
    Add-Stack $bottom @($track, $rowBottom)
    Add-Stack $pageDl @($actionCard, (New-Spacer 14), $bottom, $filesCard)

    # --- 3. Kur -----------------------------------------------------------------------------
    $pageInstall = New-Page
    $pageInstall.AutoScroll = $true
    $dropZone = New-Control Panel @{ Dock = 'Top'; Height = 104; BackColor = $T.Surface; Padding = New-Object System.Windows.Forms.Padding(3) }
    $dropZone.Add_Paint({
            param($s, $e)
            $col = if ($ui.DragHot) { $T.Accent } else { $T.Muted }
            $pen = New-Object System.Drawing.Pen($col, 1.5)
            $pen.DashStyle = 'Dash'
            $e.Graphics.DrawRectangle($pen, 1, 1, $s.Width - 3, $s.Height - 3); $pen.Dispose()
        })
    $lblDrop = New-Control Label @{
        Dock = 'Fill'; TextAlign = 'MiddleCenter'; ForeColor = $T.Text; BackColor = [System.Drawing.Color]::Transparent; Font = $T.FontDrop
        Text = "Dosyaları buraya sürükleyip bırak"
    }
    $lblDropSub = New-Control Label @{
        Dock = 'Bottom'; Height = 32; TextAlign = 'TopCenter'; ForeColor = $T.Muted; BackColor = [System.Drawing.Color]::Transparent; Font = $T.FontSmall
        Text = 'Arşivler (.7z, .zip, .rar) açılır, .scs dosyaları olduğu gibi alınır, hepsi oyunun mod klasörüne kurulur. Klasör de bırakabilirsin.'
    }
    Add-Stack $dropZone @($lblDropSub, $lblDrop)

    $installCard = New-Card 214
    $lblInstallInfo = New-Text "Ya da indirmeler bitince: asistan indirilenler klasöründeki arşivleri açar, modları oyuna kurar ve her birini host'unkiyle karşılaştırır. Ayrı bir siyah pencere açılır; iş bitene kadar kapatma." $T.Font $T.Muted 44
    $lblInstallInfo.AutoEllipsis = $false
    $flowInstall = New-Flow 50; $flowInstall.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $btnInstall = New-Button 'Arşivleri aç ve kur' 230 -Primary
    $btnInstall.Enabled = $false
    $lblInstSum = New-Control Label @{ AutoSize = $true; Font = $T.FontH2; ForeColor = $T.Text; Margin = New-Object System.Windows.Forms.Padding(14, 7, 0, 0) }
    $flowInstall.Controls.AddRange(@($btnInstall, $lblInstSum))
    $lblInstall = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Muted; Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0) }
    Add-Stack $installCard @((New-Text 'Kurulum' $T.FontH2 $T.Text 30), $lblInstallInfo, $flowInstall, $lblInstall)

    $exportCard = New-Card 186
    $lblExportInfo = New-Text "Kurulumdan sonra: oyunda modları '4. Mod sırası'ndaki sırayla etkinleştir, profili yükle, biraz sür ve oyundan çık. Sonra kontrol dosyanı oluştur ve host'a gönder." $T.Font $T.Muted 44
    $lblExportInfo.AutoEllipsis = $false
    $flowExport = New-Flow 50; $flowExport.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $lblName = New-Control Label @{ Text = 'Adın:'; AutoSize = $true; ForeColor = $T.Text; Margin = New-Object System.Windows.Forms.Padding(0, 10, 8, 0) }
    $txtName = New-Control TextBox @{
        Text = (Get-Prop $Ctx.Package 'playerLabel' 'arkadas'); Width = 160; BackColor = $T.Surface2; ForeColor = $T.Text; BorderStyle = 'FixedSingle'
        Font = New-Object System.Drawing.Font('Segoe UI', 11); Margin = New-Object System.Windows.Forms.Padding(0, 6, 14, 0)
    }
    $btnExport = New-Button 'Kontrol dosyasını oluştur' 220
    $flowExport.Controls.AddRange(@($lblName, $txtName, $btnExport))
    $lblExport = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Muted; Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0) }
    Add-Stack $exportCard @((New-Text 'Kontrol dosyası' $T.FontH2 $T.Text 30), $lblExportInfo, $flowExport, $lblExport)

    $compatCard = New-Card 204
    $lblCompatInfo = New-Text "Bu bilgisayardaki mevcut ProMods paketlerini, Mustafa'nın denediği 1.62 düzeltmesiyle uyarlar. Orijinaller yedeklenir; zaten güncellenmiş dosyalar atlanır. Yeni kurulumlarda düzeltme otomatik uygulanır." $T.Font $T.Muted 54
    $lblCompatInfo.AutoEllipsis = $false
    $flowCompat = New-Flow 46
    $btnCompat = New-Button "Kurulu modları 1.62'ye uyarla" 280 -Primary
    $btnCompatBackup = New-Button 'Uyumluluk yedeklerini aç' 230
    $flowCompat.Controls.AddRange(@($btnCompat, $btnCompatBackup))
    $lblCompat = New-Control Label @{ Dock = 'Fill'; ForeColor = $T.Muted; Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0); Text = 'Oyun kapalı olmalı. İşlem birkaç dakika sürebilir; dosyalar host ile birebir doğrulanır.' }
    Add-Stack $compatCard @((New-Text 'Oyun güncellemesi · ETS2 1.62' $T.FontH2 $T.Text 30), $lblCompatInfo, $flowCompat, $lblCompat)
    $compatCard.Visible = [bool]$Ctx.CompatibilityProfile
    Add-Stack $pageInstall @($compatCard, (New-Spacer 14), $dropZone, (New-Spacer 14), $installCard, (New-Spacer 14), $exportCard)

    # --- 4. Mod sırası ----------------------------------------------------------------------
    $pageOrder = New-Page
    $lvOrder = New-DarkList @(@('#', 56), @('Mod Yöneticisi''nde görünen ad', 460), @('Dosya', 360))
    $orderCard = New-Card 0 'Fill'; $orderCard.Padding = New-Object System.Windows.Forms.Padding(1)
    $orderCard.Controls.Add($lvOrder)
    $lblOrder = New-Text "Oyunda Profil → Mod Yöneticisi'nde bu modları etkinleştir ve YUKARIDAN AŞAĞIYA bu sırayla diz. Başka mod ekleme; konvoyda host'la birebir aynı liste olmalı." $T.Font $T.Muted 44
    $lblOrder.AutoEllipsis = $false
    $order = @(Get-HostLoadOrder $Ctx)
    $i = 0
    foreach ($o in $order) { $i++; [void](New-ListRow $lvOrder @([string]$i, $o.Name, $o.Package)) }
    if (-not $order.Count) { $lblOrder.Text = 'Host''un mod sırası pakette yok. Sırayı host''a sor.' }
    Add-Stack $pageOrder @((New-Text 'Mod sırası' $T.FontH2 $T.Text 30), $lblOrder, (New-Spacer 6), $orderCard)

    $pages = @($pageCheck, $pageDl, $pageInstall, $pageOrder)
    Add-Stack $content $pages

    # --- Davranış ---------------------------------------------------------------------------
    $showPage = {
        param([int]$Index)
        $ui.Page = $Index
        for ($k = 0; $k -lt $pages.Count; $k++) {
            $pages[$k].Visible = ($k -eq $Index)
            $navButtons[$k].BackColor = if ($k -eq $Index) { $T.AccentDim } else { $T.NavBg }
            $navButtons[$k].ForeColor = if ($k -eq $Index) { $T.Text } else { $T.Muted }
        }
        foreach ($lv in @($lvCheck, $lvFiles, $lvOrder)) { Set-LastColumnFill $lv }
    }
    foreach ($b in $navButtons) { $b.Add_Click({ param($s, $e) & $showPage ([int]$s.Tag) }) }

    # İzlenen klasör yazısı sabit; sadece doğrulama/taşıma sürerken geçici durum gösterilir
    $watchText = "İzlenen klasör: $($Ctx.DownloadsPath)   ·   tarayıcın başka yere kaydediyorsa 'Dosyayı elle seç'"
    $lblWatch.Text = $watchText
    $statusText = { param($msg) $lblWatch.Text = $msg; [System.Windows.Forms.Application]::DoEvents() }

    $fillPrereq = {
        $lvCheck.BeginUpdate()
        $lvCheck.Items.Clear()
        $ui.Prereq = @(Get-PrerequisiteReport $Ctx)
        foreach ($p in $ui.Prereq) {
            $label = switch ($p.State) { 'ok' { 'Tamam' } 'warn' { 'Uyarı' } default { 'SORUN' } }
            $it = New-ListRow $lvCheck @($p.Name, $label, $p.Detail)
            $it.SubItems[1].ForeColor = switch ($p.State) { 'ok' { $green } 'warn' { $orange } default { $red } }
            $it.SubItems[2].ForeColor = if ($p.State -eq 'ok') { $T.Muted } else { $T.Text }
        }
        $lvCheck.EndUpdate()
        Set-LastColumnFill $lvCheck
        $bad = @($ui.Prereq | Where-Object { $_.State -eq 'fail' }).Count
        $lblCheck.Text = if ($bad) { "$bad sorun var. Çözüp 'Tekrar kontrol et'e bas. İndirmeye yine de başlayabilirsin." } else { 'Her şey hazır. "2  İndir" sayfasına geç.' }
        $lblCheck.ForeColor = if ($bad) { $red } else { $green }
    }

    $buildList = {
        $lvFiles.BeginUpdate()
        $lvFiles.Items.Clear(); $ui.Items = @{}; $ui.Groups = @{}
        foreach ($mod in $Ctx.Mods) {
            $ui.Groups[$mod.Id] = New-ListRow $lvFiles @($mod.Name) -Group
            foreach ($spec in (Get-ActiveVariant $Ctx $mod).Files) {
                $ui.Items[$spec.Key] = New-ListRow $lvFiles @($spec.Display, $(if ($spec.Size) { Format-Size $spec.Size } else { '?' }), '')
                $ui.Items[$spec.Key].SubItems[1].ForeColor = $T.Muted
            }
        }
        $lvFiles.EndUpdate()
        Set-LastColumnFill $lvFiles
    }

    $refresh = {
        $act = Get-NextAction $Ctx
        $ui.Current = $act.Item
        foreach ($mod in $Ctx.Mods) {
            $complete = Test-ModComplete $mod
            $files = (Get-ActiveVariant $Ctx $mod).Files
            $doneCount = @($files | Where-Object { $_.Status -eq 'done' }).Count
            $gtext = if ($mod.Installed) { "$($mod.Name) $($mod.Version)   ·   oyuna kurulu ✓" } elseif ($complete) { "$($mod.Name) $($mod.Version)   ·   indi ✓" } else { "$($mod.Name) $($mod.Version)   ·   $doneCount / $($files.Count)" }
            $gcolor = if ($complete) { $green } else { $T.Accent }
            $grow = $ui.Groups[$mod.Id]
            if ($grow.Text -ne $gtext) { $grow.Text = $gtext }
            if ($grow.ForeColor -ne $gcolor) { $grow.ForeColor = $gcolor }
            foreach ($spec in $files) {
                $it = $ui.Items[$spec.Key]
                if (-not $it) { continue }
                $text, $color = if ($mod.Installed) { 'Oyuna kurulu ✓', $green }
                elseif ($complete -or $spec.Status -eq 'done') { "Tamam ✓   $($spec.Detail)", $green }
                elseif ($spec.Status -eq 'downloading') { "İniyor…  %$($spec.Percent)", $blue }
                elseif ($spec.Status -eq 'error') { $spec.Detail, $red }
                elseif ($ui.Current -and $ui.Current.Spec.Key -eq $spec.Key) { '◀  Sıradaki', $orange }
                else { "Bekliyor   $($spec.Detail)", $T.Muted }
                $nameColor = if ($ui.Current -and $ui.Current.Spec.Key -eq $spec.Key) { $orange } else { $T.Text }
                if ($it.SubItems[2].Text -ne $text) { $it.SubItems[2].Text = $text }
                if ($it.SubItems[2].ForeColor -ne $color) { $it.SubItems[2].ForeColor = $color; $lvFiles.Invalidate($it.Bounds) }
                if ($it.ForeColor -ne $nameColor) { $it.ForeColor = $nameColor; $it.SubItems[0].ForeColor = $nameColor; $lvFiles.Invalidate($it.Bounds) }
            }
        }

        $waitLines = @()
        foreach ($g in $act.Waits.Keys) {
            $w = $act.Waits[$g]
            $site = @($Ctx.Mods | Where-Object { @($_.Variants | Where-Object { $_.CooldownGroup -eq $g }).Count } | ForEach-Object { $_.Site }) | Select-Object -First 1
            if (-not $site) { $site = $g }
            if ($w.Busy) { $waitLines += "$site dosyası iniyor" }
            else { $waitLines += ('{0}:{1:00}' -f [math]::Floor($w.Remaining / 60), ($w.Remaining % 60)) }
        }
        # Bekleme bitince sesli uyarı
        foreach ($g in @($ui.LastWait.Keys)) {
            if (-not $act.Waits.ContainsKey($g)) { [System.Media.SystemSounds]::Exclamation.Play(); $ui.LastWait.Remove($g) }
        }
        foreach ($g in $act.Waits.Keys) { $ui.LastWait[$g] = $true }

        $wf = if (@($act.Waits.Values | Where-Object { $_.Busy }).Count) { $T.FontH2 } else { $T.FontBig }
        if ($lblWait.Font -ne $wf) { $lblWait.Font = $wf }
        Set-Text $lblWait $(($waitLines -join "`r`n"))
        Set-Text $lblWaitNote $(if ($act.Waits.Count) { "promods.net bekleme süresi.`r`nSüre dolmadan o sitede yeni dosyaya basma,`r`nsayaç baştan başlar." } else { '' })

        switch ($act.Kind) {
            'download' {
                $m = $act.Item.Mod; $v = $act.Item.Variant; $s = $act.Item.Spec
                Set-Text $lblAction $("Sıradaki:  $($s.Display)    ($($m.Name) $($m.Version))")
                $lines = @()
                foreach ($l in @($v.Instructions) + @($m.Notes)) { $lines += '•  ' + ($l -replace '\{file\}', $s.Display) }
                if ($s.Status -eq 'error') { $lines = @("•  Önceki indirme hatalıydı: $($s.Detail)") + $lines }
                $lines += '•  İnen dosyayı asistan kendisi bulur ve doğrular; sen bir şey taşıma.'
                Set-Text $lblInstr $($lines -join "`r`n")
                $btnOpen.Enabled = $true; $btnPick.Enabled = $true; $btnSkip.Enabled = $true
                Set-Text $form $("ETS2 Mod Asistanı $($Ctx.Version)")
            }
            'wait' {
                Set-Text $lblAction $('Bekleme süresi doluyor…')
                Set-Text $lblInstr $("•  Şu an indirilecek başka dosya yok. Sayaç bitince asistan ses çıkarır ve sıradaki dosyayı gösterir.`r`n•  Pencereyi açık bırak, bilgisayarı uyku moduna alma.")
                $btnOpen.Enabled = $false; $btnPick.Enabled = $true; $btnSkip.Enabled = $false
                Set-Text $form $("($($waitLines -join ', ')) ETS2 Mod Asistanı")
            }
            'downloading' {
                Set-Text $lblAction $('İndirmeler sürüyor…')
                Set-Text $lblInstr $('•  Tarayıcıdaki indirmelerin bitmesini bekle. Biten dosyalar otomatik olarak alınır.')
                $btnOpen.Enabled = $false; $btnPick.Enabled = $true; $btnSkip.Enabled = $false
            }
            'done' {
                # Metin bir kez yazılır (iki kez yazmak her saniye yazının yanıp sönmesine yol açıyordu)
                if (-not @($Ctx.Mods | Where-Object { -not $_.Installed }).Count) {
                    Set-Text $lblAction 'Bütün modlar oyuna kurulu ✓'
                    Set-Text $lblInstr '•  "4  Mod sırası" sayfasındaki sırayla modları oyunda etkinleştir.'
                } else {
                    Set-Text $lblAction 'Bütün dosyalar indi ✓'
                    Set-Text $lblInstr '•  "3  Kur" sayfasına geç ve "Arşivleri aç ve kur" düğmesine bas.'
                }
                $btnOpen.Enabled = $false; $btnPick.Enabled = $false; $btnSkip.Enabled = $false
                Set-Text $form $("ETS2 Mod Asistanı $($Ctx.Version)")
            }
        }

        # Dikkat: $t adı kullanılmaz, PowerShell'de $T (tema) ile aynı değişken
        $tot = Get-DownloadTotals $Ctx
        $ui.Ratio = if ($tot.TotalBytes) { [Math]::Min(1.0, $tot.DoneBytes / $tot.TotalBytes) } else { 0.0 }
        $trackFill.Width = [int]($track.Width * $ui.Ratio)
        $trackFill.BackColor = if ($ui.Ratio -ge 1) { $green } else { $T.Accent }
        Set-Text $lblTotal $("$($tot.DoneFiles) / $($tot.Files) dosya   ·   $(Format-Size $tot.DoneBytes) / $(Format-Size $tot.TotalBytes)")
        $hostOk = -not @(Get-HostFileReport $Ctx | Where-Object { $_.State -ne 'ok' }).Count
        $btnInstall.Enabled = ($act.Kind -eq 'done') -and $hostOk -and -not $ui.InstallProc -and -not $ui.AddProc -and -not $ui.CompatProc
        $btnCompat.Enabled = [bool]$Ctx.ModFolder -and [bool]$Ctx.CompatibilityProfile -and (Test-Path -LiteralPath $Ctx.CompatibilityProfile) -and -not $ui.InstallProc -and -not $ui.AddProc -and -not $ui.ExportProc -and -not $ui.CompatProc -and -not $ui.Bg
        $btnExport.Enabled = -not $ui.CompatProc -and -not $ui.ExportProc
        $btnClean.Enabled = -not $ui.CompatProc -and -not $ui.InstallProc -and -not $ui.AddProc -and -not $ui.Bg
        if ($act.Kind -eq 'done' -and -not $hostOk) { $lblInstall.Text = 'Host''tan gelen dosya eksik/farklı, "1  Ön kontrol" sayfasına bak.'; $lblInstall.ForeColor = $red }
        $sum = Get-InstallSummary $Ctx
        $allIn = $sum.Total -and $sum.Installed -eq $sum.Total
        Set-Text $lblInstSum $(if ($allIn) { "Oyunda kurulu:  $($sum.Total) / $($sum.Total)  ✓" } else { "Oyunda kurulu:  $($sum.Installed) / $($sum.Total)" })
        $lblInstSum.ForeColor = if ($allIn) { $green } else { $T.Text }

        # Sayfa düğmelerinde tamamlanma işareti
        $marks = @(
            (-not @($ui.Prereq | Where-Object { $_.State -eq 'fail' }).Count),
            ($act.Kind -eq 'done'),
            $allIn,
            $false)
        $names = '1   Ön kontrol', '2   İndir', '3   Kur', '4   Mod sırası'
        for ($k = 0; $k -lt 4; $k++) {
            $nt = if ($marks[$k]) { "$($names[$k])  ✓" } else { $names[$k] }
            if ($navButtons[$k].Text -ne $nt) { $navButtons[$k].Text = $nt }
        }
    }

    # --- Mod klasörünü temizleme (arka planda: büyük dosyaların hash'i pencereyi dondurmasın) ---
    $startBg = {
        param([string]$Kind, [hashtable]$Data)
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
                param($Common, $Core, $Kind, $Data)
                . $Common; . $Core
                if ($Kind -eq 'scan') {
                    @{ Conflicts = @(Get-ModFolderConflicts -ModFolder $Data.ModFolder -ModSet $Data.ModSet -Installed $Data.Installed -HashCache $Data.Hashes); Hashes = $Data.Hashes }
                } else { Move-ModsToBackup -ModFolder $Data.ModFolder -Names $Data.Names -BackupRoot $Data.BackupRoot }
            })
        [void]$ps.AddArgument((Join-Path $Ctx.ToolsDir 'Ets2Common.ps1')).AddArgument((Join-Path $Ctx.AssistantDir 'lib\Asistan.Core.ps1')).AddArgument($Kind).AddArgument($Data)
        $ui.Bg = @{ Kind = $Kind; Ps = $ps; Handle = $ps.BeginInvoke() }
        $btnClean.Enabled = $false
    }

    $formatConflicts = {
        param($List)
        $lines = @($List | Select-Object -First 15 | ForEach-Object { "•  $($_.Name)   ($($_.Reason), $(Format-Size $_.Size))" })
        if (@($List).Count -gt 15) { $lines += "… ve $(@($List).Count - 15) tane daha" }
        $lines -join "`r`n"
    }

    $startMove = {
        param($List)
        $lblCheck.Text = 'Modlar yedeğe taşınıyor…'; $lblCheck.ForeColor = $blue
        & $startBg 'move' @{ ModFolder = $Ctx.ModFolder; Names = @($List | ForEach-Object { $_.Name }); BackupRoot = (Get-BackupRoot $Ctx) }
    }

    $onBgDone = {
        param([string]$Kind, $Out, $Err)
        $btnClean.Enabled = $true
        if ($Err -or -not $Out) {
            $lblCheck.Text = "Mod klasörü işlemi hata verdi: $(if ($Err) { $Err } else { 'sonuç yok' })"; $lblCheck.ForeColor = $red
            $ui.AfterMove = $null; return
        }
        if ($Kind -eq 'scan') {
            foreach ($k in $Out.Hashes.Keys) { $Ctx.State.Hashes[$k] = $Out.Hashes[$k] }
            Save-AssistantState $Ctx
            $list = @($Out.Conflicts)
            if (-not $list.Count) {
                $lblCheck.Text = 'Mod klasöründe host''un listesi dışında ya da farklı mod yok ✓'; $lblCheck.ForeColor = $green
                return
            }
            $q = [System.Windows.Forms.MessageBox]::Show($form,
                "Oyunun mod klasöründe host'unkilerle çakışan $($list.Count) mod var:`r`n`r`n$(& $formatConflicts $list)`r`n`r`nBunlar mod klasöründen kaldırılıp yedeğe taşınsın mı? (Silinmez.)`r`nYedek: $(Get-BackupRoot $Ctx)`r`nOyun kapalı olmalı.",
                'Farklı modları kaldır ve yedekle', 'YesNo', 'Question')
            if ($q -eq 'Yes') { & $startMove $list }
            else { $lblCheck.Text = "Mod klasöründe $($list.Count) farklı mod var; dokunulmadı."; $lblCheck.ForeColor = $orange }
            return
        }
        # move
        $ui.LastBackup = $Out.Dir
        $btnBackupOpen.Visible = $true
        $msg = "$(@($Out.Moved).Count) mod yedeğe taşındı:`r`n$($Out.Dir)"
        if (@($Out.Failed).Count) { $msg += "`r`n`r`nTaşınamadı (oyun açık olabilir):`r`n$(@($Out.Failed) -join "`r`n")" }
        & $fillPrereq
        $lblCheck.Text = $(if (@($Out.Failed).Count) { "$(@($Out.Moved).Count) mod yedeklendi, $(@($Out.Failed).Count) tanesi taşınamadı." } else { "$(@($Out.Moved).Count) mod yedeğe taşındı ✓  ($($Out.Dir))" })
        $lblCheck.ForeColor = if (@($Out.Failed).Count) { $orange } else { $green }
        $after = $ui.AfterMove; $ui.AfterMove = $null
        if ($after) { & $after }
        else { [System.Windows.Forms.MessageBox]::Show($form, $msg, 'Yedekleme') | Out-Null }
    }

    $startDropInstall = {
        $rf = Join-Path $Ctx.PackageRoot 'birakma-sonucu.json'
        if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
        $ui.AddProc = Start-DropInstall $Ctx $ui.DropPaths $rf
        & $showPage 2
        $lblInstall.Text = 'Bırakılan dosyalar kuruluyor… Siyah pencerede "Bitti" yazınca Enter''a bas.'; $lblInstall.ForeColor = $blue
    }

    $startFullInstall = {
        $rf = Join-Path $Ctx.PackageRoot 'kurulum-sonucu.json'
        if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
        $ui.InstallProc = Start-AssistantTask $Ctx install -ResultFile $rf
        $btnInstall.Enabled = $false
        & $showPage 2
        $lblInstall.Text = 'Kurulum sürüyor… Siyah pencerede "Bitti" yazınca Enter''a bas.'; $lblInstall.ForeColor = $blue
    }

    $askConflictsThen = {
        # Kurmadan önce: host'un listesinde olmayan modlar varsa kaldırılıp yedeklensin mi? (sadece adlara bakılır, anında)
        param([scriptblock]$Then)
        $list = @(Get-ModFolderConflicts -ModFolder $Ctx.ModFolder -ModSet $Ctx.ModSet -Quick)
        if (-not $list.Count) { & $Then; return }
        $q = [System.Windows.Forms.MessageBox]::Show($form,
            "Oyunun mod klasöründe host'un listesinde olmayan $($list.Count) mod var:`r`n`r`n$(& $formatConflicts $list)`r`n`r`nKurmadan önce bunlar kaldırılıp yedeğe taşınsın mı? (Silinmez.)`r`n`r`nEvet: yedeğe taşı, sonra kur`r`nHayır: dokunma, sadece kur`r`nİptal: vazgeç",
            'Çakışan modlar', 'YesNoCancel', 'Question')
        if ($q -eq 'Cancel') { return }
        if ($q -eq 'No') { & $Then; return }
        $ui.AfterMove = $Then
        & $showPage 0
        & $startMove $list
    }

    $handleDrop = {
        # Sürükle-bırak olayında soru sorulmaz (Gezgin bırakma bitene kadar donar); zamanlayıcıdan çağrılır
        $paths = @($ui.PendingDrop); $ui.PendingDrop = $null
        if ($ui.AddProc -or $ui.InstallProc -or $ui.CompatProc -or $ui.Bg) {
            [System.Windows.Forms.MessageBox]::Show($form, 'Önceki iş hâlâ sürüyor. Bitince tekrar bırak.', 'Dosya ekleme') | Out-Null
            return
        }
        $names = @($paths | ForEach-Object { [System.IO.Path]::GetFileName($_) })
        $shown = if ($names.Count -gt 12) { (@($names[0..11]) -join "`r`n") + "`r`n… ve $($names.Count - 12) tane daha" } else { $names -join "`r`n" }
        $q = [System.Windows.Forms.MessageBox]::Show($form,
            "Bırakılanlar:`r`n$shown`r`n`r`nArşivler açılıp modlar oyunun mod klasörüne kurulacak; host'un listesindekiler host'unkiyle karşılaştırılır.`r`nOyun kapalı olmalı. Devam edilsin mi?",
            'Dosyaları kur', 'YesNo', 'Question')
        if ($q -ne 'Yes') { return }
        $ui.DropPaths = $paths
        & $askConflictsThen $startDropInstall
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
        $bk = @(Get-Prop $res 'BackedUp' @()); if ($bk.Count) { $lines += "Eski sürümü yedeğe alınıp yenisi kuruldu: $($bk -join ', ')" }
        $lblInstall.Text = $lines -join "`r`n"
        $lblInstall.ForeColor = if ($diff.Count -or $mp.Count) { $red } else { $green }
    }

    $tick = {
        if ($ui.Busy) { return }
        $ui.Busy = $true
        try {
            if ($ui.Bg -and $ui.Bg.Handle.IsCompleted) {
                $bg = $ui.Bg; $ui.Bg = $null
                $out = $null; $err = $null
                try {
                    $out = @($bg.Ps.EndInvoke($bg.Handle)) | Select-Object -Last 1
                    if ($bg.Ps.Streams.Error.Count) { $err = $bg.Ps.Streams.Error[0].ToString() }
                } catch { $err = $_.Exception.Message }
                $bg.Ps.Dispose()
                & $onBgDone $bg.Kind $out $err
            }
            if ($ui.PendingDrop) { & $handleDrop }
            [void](Update-InstalledState $Ctx)
            [void](Update-AssistantDownloads $Ctx -Notify $statusText)
            if ($lblWatch.Text -ne $watchText) { $lblWatch.Text = $watchText; $lblWatch.ForeColor = $T.Muted }
            & $refresh
            foreach ($p in @('InstallProc', 'ExportProc', 'AddProc', 'CompatProc')) {
                $proc = $ui[$p]
                if ($proc -and $proc.HasExited) {
                    $ui[$p] = $null
                    $rf = Join-Path $Ctx.PackageRoot $(switch ($p) { 'InstallProc' { 'kurulum-sonucu.json' } 'AddProc' { 'birakma-sonucu.json' } 'CompatProc' { 'uyumluluk-sonucu.json' } default { 'kontrol-sonucu.json' } })
                    $res = if (Test-Path -LiteralPath $rf) { Read-JsonFile $rf } else { $null }
                    if ($res -and $p -ne 'ExportProc') {
                        Register-InstalledFiles $Ctx @(Get-Prop $res 'Installed' @())
                        [void](Update-InstalledState $Ctx); & $refresh
                    }
                    if ($p -eq 'AddProc') { & $showAddResult $res; continue }
                    if ($p -eq 'CompatProc') {
                        if ($res -and (Get-Prop $res 'Ok' $false)) {
                            $updated = @(Get-Prop $res 'Updated' @()).Count
                            $recognized = @(Get-Prop $res 'Installed' @()).Count
                            $missing = @(Get-Prop $res 'Missing' @()).Count
                            $lblCompat.Text = "$updated dosya güncellendi; $recognized dosya doğrulandı. Oyunda modları '4  Mod sırası'na göre etkinleştir."
                            if ($missing) { $lblCompat.Text += " $missing ProMods paketi bu bilgisayarda bulunamadı." }
                            if (Get-Prop $res 'BackupDir') { $ui.LastBackup = $res.BackupDir }
                            $lblCompat.ForeColor = if ($missing) { $orange } else { $green }
                        } else {
                            $lblCompat.Text = "İşlem tamamlanamadı. $(Get-Prop $res 'Error' 'Uyumluluk sonucu alınamadı; tekrar dene.')"
                            $lblCompat.ForeColor = $red
                        }
                        continue
                    }
                    if ($p -eq 'InstallProc') {
                        if ($res -and (Get-Prop $res 'Ok' $false)) {
                            $lblInstall.Text = "Kurulum tamam ✓  Bütün dosyalar host'unkiyle aynı.`r`nŞimdi '4  Mod sırası' sayfasına bak ve oyunu aç."; $lblInstall.ForeColor = $green
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
            if ($ui.Bg -or $ui.CompatProc -or $ui.InstallProc -or $ui.AddProc) { return }
            $q = [System.Windows.Forms.MessageBox]::Show($form,
                "Arşivler açılıp oyunun mod klasörüne kurulacak (birkaç dakika sürer).`r`nOyun kapalı olmalı. Devam edilsin mi?", 'Kurulum', 'YesNo', 'Question')
            if ($q -ne 'Yes') { return }
            & $askConflictsThen $startFullInstall
        })
    $btnClean.Add_Click({
            if ($ui.Bg -or $ui.AddProc -or $ui.InstallProc -or $ui.CompatProc) { return }
            if (-not $Ctx.ModFolder -or -not (Test-Path -LiteralPath $Ctx.ModFolder)) {
                [System.Windows.Forms.MessageBox]::Show($form, 'Oyunun mod klasörü bulunamadı. Oyunu bir kez açıp kapat.', 'Mod klasörü') | Out-Null; return
            }
            if (-not $Ctx.ModSet) { [System.Windows.Forms.MessageBox]::Show($form, 'Host''un mod listesi pakette yok; neyin farklı olduğu bilinemez.', 'Mod klasörü') | Out-Null; return }
            $lblCheck.Text = 'Mod klasörü taranıyor… (aynı adlı büyük dosyaların hash''i hesaplanıyor, biraz sürebilir)'; $lblCheck.ForeColor = $blue
            & $startBg 'scan' @{ ModFolder = $Ctx.ModFolder; ModSet = $Ctx.ModSet; Installed = $Ctx.State.Installed.Clone(); Hashes = $Ctx.State.Hashes.Clone() }
        })
    $btnBackupOpen.Add_Click({
            $p = if ($ui.LastBackup -and (Test-Path -LiteralPath $ui.LastBackup)) { $ui.LastBackup } else { Get-BackupRoot $Ctx }
            if (Test-Path -LiteralPath $p) { Start-Process explorer.exe -ArgumentList "`"$p`"" }
        })
    $btnExport.Add_Click({
            if ($ui.CompatProc) { return }
            $label = ($txtName.Text.Trim().ToLowerInvariant() -replace '[^a-z0-9_-]', '')
            if (-not $label) { $label = 'arkadas' }
            $rf = Join-Path $Ctx.PackageRoot 'kontrol-sonucu.json'
            if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
            $ui.ExportProc = Start-AssistantTask $Ctx export -Label $label -ResultFile $rf
            $btnExport.Enabled = $false
            $lblExport.Text = 'Oluşturuluyor… (oyun kapalı olmalı)'; $lblExport.ForeColor = $blue
        })

    $btnCompat.Add_Click({
            if ($ui.CompatProc -or $ui.InstallProc -or $ui.AddProc -or $ui.ExportProc -or $ui.Bg) { return }
            $rf = Join-Path $Ctx.PackageRoot 'uyumluluk-sonucu.json'
            if (Test-Path -LiteralPath $rf) { Remove-Item -LiteralPath $rf -Force }
            $ui.CompatProc = Start-AssistantTask $Ctx compat -ResultFile $rf
            $btnCompat.Enabled = $false
            $lblCompat.Text = 'Modlar kontrol ediliyor, yedekleniyor ve 1.62 düzeltmesi hazırlanıyor… Asistanı kapatma.'
            $lblCompat.ForeColor = $blue
        })
    $btnCompatBackup.Add_Click({
            $backupPath = Join-Path $Ctx.PackageRoot 'yedek-modlar\uyumluluk'
            if (Test-Path -LiteralPath $backupPath) { Start-Process explorer.exe -ArgumentList "`"$backupPath`"" }
        })

    # Sürükle-bırak: pencerenin her yerine dosya/klasör bırakılabilir
    $onDragEnter = {
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy'; if (-not $ui.DragHot) { $ui.DragHot = $true; $dropZone.Invalidate() } }
    }
    $onDragLeave = { if ($ui.DragHot) { $ui.DragHot = $false; $dropZone.Invalidate() } }
    $onDragDrop = { param($s, $e) $ui.DragHot = $false; $dropZone.Invalidate(); $ui.PendingDrop = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) }
    $enableDrop = {
        param($c)
        $c.AllowDrop = $true; $c.Add_DragEnter($onDragEnter); $c.Add_DragLeave($onDragLeave); $c.Add_DragDrop($onDragDrop)
        foreach ($ch in $c.Controls) { & $enableDrop $ch }
    }
    & $enableDrop $form

    & $fillPrereq
    & $buildList
    [void](Update-InstalledState $Ctx)
    & $tick
    & $showPage $(if (@($ui.Prereq | Where-Object { $_.State -eq 'fail' }).Count) { 0 } else { 1 })
    $form.Add_Shown({ $form.ActiveControl = $navButtons[$ui.Page]; foreach ($lv in @($lvCheck, $lvFiles, $lvOrder)) { Set-DarkNative $lv; Set-LastColumnFill $lv } })

    if ($Snapshot) {
        # Test için: pencere ekranda kısa süre açılır, her sayfanın görüntüsü kaydedilir, kapanır
        $form.Add_Shown({
                for ($k = 0; $k -lt $pages.Count; $k++) {
                    & $showPage $k
                    $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 250; [System.Windows.Forms.Application]::DoEvents()
                    # Sadece pencerenin kendisi çizilir (ekrandan kopyalamak başka pencereleri yakalayabiliyor)
                    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
                    $bmp.Save(($SnapshotPath -f $k), [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                }
                $form.Close()
            })
        $form.TopMost = $true
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
