<#
.SYNOPSIS
    Asistanın ikonunu (M harfli) çizer: çok boyutlu .ico (16–256 px) ve önizleme PNG'si.

.DESCRIPTION
    Koyu lacivert yuvarlak kare, asistanın mavi vurgu renginde ince çerçeve ve ortada beyaz "M";
    altında yol şeridi gibi turuncu bir çizgi. Küçük boyutlarda (16-24 px) ayrıntı atılır,
    harf büyütülür. ICO içinde 128/256 px PNG, küçükler klasik 32 bit BMP olarak saklanır
    (.NET Framework'ün Icon sınıfı PNG kayıtlarını çizemiyor; pencere ikonu onunla yükleniyor).

.EXAMPLE
    .\tools\New-AssistantIcon.ps1 -OutFile .\assistant\assets\asistan.ico -PreviewPng .\work\ikon.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutFile,
    [string]$PreviewPng
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundedRect([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconBitmap([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([System.Drawing.Color]::Transparent)
    $small = $Size -le 24

    # Zemin: koyu lacivertten maviye çapraz geçiş
    $m = [float]([Math]::Max(0.5, $Size * 0.03))
    $rect = New-Object System.Drawing.RectangleF($m, $m, ($Size - 2 * $m), ($Size - 2 * $m))
    $path = New-RoundedRect $rect.X $rect.Y $rect.Width $rect.Height ([float]($Size * 0.22))
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
        [System.Drawing.Color]::FromArgb(54, 112, 220), [System.Drawing.Color]::FromArgb(18, 28, 56), [float]60)
    $g.FillPath($grad, $path)
    if (-not $small) {
        # Üstten aşağı yumuşak ışık (sert kenar olmadan)
        $hl = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
            [System.Drawing.Color]::FromArgb(45, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [float]90)
        $g.FillPath($hl, $path)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 140, 185, 255), [float]([Math]::Max(1, $Size * 0.014)))
        $g.DrawPath($pen, $path)
    }

    # "M"
    # Harf büyük boyutta çizilip hedef kutuya ölçeklenir (yazı tipinin iç boşluklarından bağımsız)
    $family = New-Object System.Drawing.FontFamily('Segoe UI Black')
    $tp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tp.AddString('M', $family, 0, [float]200, (New-Object System.Drawing.PointF(0, 0)), [System.Drawing.StringFormat]::GenericTypographic)
    $b = $tp.GetBounds()
    $boxH = if ($small) { $Size * 0.60 } else { $Size * 0.40 }
    $boxW = if ($small) { $Size * 0.74 } else { $Size * 0.56 }
    $k = [Math]::Min($boxH / $b.Height, $boxW / $b.Width)
    $top = if ($small) { ($Size - $b.Height * $k) / 2 } else { $Size * 0.22 }
    $mx = New-Object System.Drawing.Drawing2D.Matrix
    $mx.Translate([float](($Size - $b.Width * $k) / 2), [float]$top)
    $mx.Scale([float]$k, [float]$k)
    $mx.Translate([float](-$b.X), [float](-$b.Y))
    $tp.Transform($mx)
    if (-not $small) {
        $shadow = $tp.Clone()
        $sm = New-Object System.Drawing.Drawing2D.Matrix; $sm.Translate(0, [float]($Size * 0.02)); $shadow.Transform($sm)
        $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 0, 0, 0))), $shadow)
    }
    $g.FillPath([System.Drawing.Brushes]::White, $tp)

    # Altta yol şeridi (turuncu, kesik çizgi)
    if (-not $small) {
        $y = $Size * 0.80
        $h = [float]([Math]::Max(2, $Size * 0.055))
        $seg = $Size * 0.13; $gap = $Size * 0.06
        $total = 3 * $seg + 2 * $gap
        $x = ($Size - $total) / 2
        $orange = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 170, 60))
        for ($i = 0; $i -lt 3; $i++) {
            $sp = New-RoundedRect ([float]($x + $i * ($seg + $gap))) ([float]$y) ([float]$seg) $h ([float]($h / 2))
            $g.FillPath($orange, $sp)
        }
    }
    $g.Dispose()
    return $bmp
}

function ConvertTo-IcoDib([System.Drawing.Bitmap]$Bmp) {
    # BITMAPINFOHEADER (yükseklik iki kat: renk + AND maskesi), BGRA satırlar alttan üste, 1 bit maske
    $s = $Bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $maskRow = [int]([Math]::Ceiling($s / 32.0) * 4)
    $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2)); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]0); $w.Write([uint32]($s * $s * 4 + $maskRow * $s)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) { $c = $Bmp.GetPixel($x, $y); $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A) }
    }
    for ($y = $s - 1; $y -ge 0; $y--) {
        $row = New-Object byte[] $maskRow
        for ($x = 0; $x -lt $s; $x++) { if ($Bmp.GetPixel($x, $y).A -eq 0) { $row[[int][Math]::Floor($x / 8)] = $row[[int][Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) } }
        $w.Write($row)
    }
    $w.Flush()
    return , $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    if ($PreviewPng -and $s -eq 256) { $bmp.Save($PreviewPng, [System.Drawing.Imaging.ImageFormat]::Png) }
    if ($s -ge 128) {
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $data = $ms.ToArray()
    } else { $data = ConvertTo-IcoDib $bmp }
    $bmp.Dispose()
    , $data
}

# ICO: 6 bayt başlık + boyut başına 16 bayt kayıt + PNG verileri
$dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutFile))
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($out)
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256))   # 256 → 0
    $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Flush()
[System.IO.File]::WriteAllBytes([System.IO.Path]::GetFullPath($OutFile), $out.ToArray())
Write-Host "İkon: $OutFile ($([math]::Round($out.Length / 1KB)) KB, $($sizes -join '/') px)" -ForegroundColor Green
