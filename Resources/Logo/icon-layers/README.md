# App icon layers

`holzBar.svg` split into the three layers that Icon Composer (Xcode 26 and later) takes for a Liquid Glass app icon. Back to front:

1. `01-plank.svg`: the wooden plank with its highlight and grain.
2. `02-bar.svg`: the light menu bar with the chevron and its four items.
3. `03-sparkle.svg`: the sparkle.

The layers are 1024 by 1024 and follow Apple's rules for Icon Composer: no canvas mask (the tile is left out, the system draws it), and no opacity, clip path, blur, gradient or text. The logo's semi-transparent colours are baked into the solid colours they produce (`#D99F61`, `#A9703C`, `#95C8E3`). `python3 Scripts/check-icon-layers.py` proves that the layers still match `holzBar.svg`; run it after changing either.

## Make the icon

On a Mac with Xcode 26 or later:

1. Open Icon Composer (Xcode, Open Developer Tool, Icon Composer).
2. Import the three layers in order, each in a group of its own.
3. Set the background Fill to the solid colour `#0A1426`.
4. Adjust the glass settings (specular, translucency, shadow) and check the Default, Dark and Tinted appearances. The plank stays the one warm accent.
5. Save the file as `AppIcon.icon` in `holzBar/Resources/`.

holzBar keeps its current icon (`AppIcon.appiconset`) until that file exists. Once it does, the project uses it and drops the old icon set; Xcode generates the images for earlier macOS releases from it.
