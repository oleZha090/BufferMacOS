param(
    [string]$Source = (Join-Path $PSScriptRoot '..\Branding\Cliply-icon-source.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$assetDirectory = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'Cliply\Resources\Assets.xcassets'))
if (-not $assetDirectory.StartsWith($workspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Icon output must remain inside the project.'
}
$iconDirectory = Join-Path $assetDirectory 'AppIcon.appiconset'
[IO.Directory]::CreateDirectory($iconDirectory) | Out-Null
$encoding = New-Object Text.UTF8Encoding($false)
$image = [Drawing.Image]::FromFile([IO.Path]::GetFullPath($Source))
$entries = @()
try {
    if ($image.Width -ne $image.Height -or $image.Width -lt 1024) {
        throw 'The icon source must be square and at least 1024 pixels.'
    }
    foreach ($size in @(16, 32, 128, 256, 512)) {
        foreach ($scale in @(1, 2)) {
            $pixels = $size * $scale
            $suffix = if ($scale -eq 2) { '@2x' } else { '' }
            $filename = "icon_${size}x${size}${suffix}.png"
            $bitmap = New-Object Drawing.Bitmap($pixels, $pixels, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            $attributes = New-Object Drawing.Imaging.ImageAttributes
            try {
                # Mechanical downscaling only; preserve the generated artwork and its alpha.
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $rectangle = New-Object Drawing.Rectangle(0, 0, $pixels, $pixels)
                $graphics.DrawImage($image, $rectangle, 0, 0, $image.Width, $image.Height, [Drawing.GraphicsUnit]::Pixel, $attributes)
                $bitmap.Save((Join-Path $iconDirectory $filename), [Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $attributes.Dispose()
                $graphics.Dispose()
                $bitmap.Dispose()
            }
            $entries += @{ filename = $filename; idiom = 'mac'; size = "${size}x${size}"; scale = "${scale}x" }
        }
    }
} finally { $image.Dispose() }

$catalog = @{ info = @{ author = 'xcode'; version = 1 } }
$iconCatalog = @{ images = $entries; info = @{ author = 'xcode'; version = 1 } }
[IO.File]::WriteAllText((Join-Path $assetDirectory 'Contents.json'), ($catalog | ConvertTo-Json -Depth 6) + "`n", $encoding)
[IO.File]::WriteAllText((Join-Path $iconDirectory 'Contents.json'), ($iconCatalog | ConvertTo-Json -Depth 6) + "`n", $encoding)
Write-Output 'Prepared 10 macOS app icon slots (16 through 1024 pixels), preserving transparency.'
