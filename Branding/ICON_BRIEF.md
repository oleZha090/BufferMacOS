# Cliply app icon

Generated with the built-in `image_gen` tool. This is original artwork informed by the user's clipboard-icon reference sheet, using its minimal shapes and soft depth in a black-and-white palette.

The original generated artwork is [Cliply-icon-source.png](Cliply-icon-source.png), 1254 × 1254 pixels with an alpha channel. The 10 checked-in app-icon PNGs in `Cliply/Resources/Assets.xcassets/AppIcon.appiconset/` are mechanically downscaled exports of that artwork, with no compositional changes.

## Final generation prompt

```text
Use case: logo-brand. Asset type: production macOS application icon for a clipboard history app named Cliply. Generate ONE finished square app icon, not a grid or concept sheet. The user supplied a reference sheet of softly dimensional macOS rounded-square clipboard icons: take inspiration from the minimal clean clipboard shape and layered cards, but create an original strictly black-and-white version. Composition: a large almost-black charcoal rounded-square tile, centered in a square 1024 x 1024 canvas with about 8% transparent outer margins, beautifully smooth macOS-style superellipse corners. On the tile: one bold clean pearl-white clipboard, front view with just subtle dimensional depth; rounded top clip with a small dark rounded slot, 3 short horizontal charcoal text bars on the white page. One subtle graphite card slightly offset behind the white clipboard suggests clipboard history without clutter. Keep the silhouette exceptionally clear at 16 px. Premium understated soft studio highlights, restrained grayscale shadows, precise geometry, elegant balanced padding. Strict achromatic black, white and neutral gray ONLY, all colors have equal RGB channels, absolutely no blue, purple, warm or colored tints. True transparent background outside the tile, preserve alpha. No letters, no app name or words, no watermark, no surrounding surface, no labels, no other icons. This is new artwork using the attached sheet only as visual style inspiration, not an edit of that sheet.
```

The image generation tool produced a 1254-pixel square. The Xcode catalog includes all required slot dimensions from 16 to 1024 pixels. Regenerate the exports on Windows with the built-in System.Drawing resize script:

```powershell
powershell -NoProfile -File scripts/generate_icons.ps1
```

All exported files are included in Git, so the macOS build does not need PowerShell, an image generation service, or extra image libraries. Xcode compiles the asset catalog into the app's icon resources. The Menu Bar uses a monochrome native template clipboard symbol that adapts to the system background.
