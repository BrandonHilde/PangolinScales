# Pangolin Scales

*Curves, scale by scale.* An SVG and font editor written in Odin with SDL3.

A sibling of [Pangolin Paints](../PangolinPaints) and Pangolin Pixels in the Pangolin graphical editing suite: same look and feel,
built for paths instead of pixels. The font side is based on ScalarCanvas.

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows (or `odin build src -out:PangolinScales -o:speed`).
Drag `.svg`, `.ttf` or `.otf` files onto the window to open them.
`PangolinScales --selftest` runs the headless test suite (on Windows use `PangolinScales-console.exe`, since the GUI build has no console).

## SVG editing
- **Tools**: select (move, scale, rotate), node edit, pen (click, click-drag for curves, click the first point to close), freehand
  (fits smooth Bezier curves to your stroke), rectangle, ellipse, line, text, eyedropper, hand, zoom.
- **Nodes**: drag anchors and handles (handles mirror when a node is smooth, Alt breaks the symmetry), double click a segment to add a
  node, make nodes smooth or corner, delete nodes, move with the arrow keys.
- **Style**: fill and stroke as none, solid, linear or radial gradient (stops, spread, draggable gradient handles on the canvas),
  stroke width, caps, joins, dashes, opacity, even-odd fill, corner radius, exact X / Y / W / H.
- **Objects**: group / ungroup, z-order, lock and hide, duplicate, copy / paste (also as SVG text with other apps), flip, rotate 90,
  align and distribute, an objects panel.
- **Path menu**: union, subtract, intersect, exclude, combine, break apart, reverse, simplify, offset in and out, stroke to path,
  object to path, text to outlines. Booleans keep untouched curves exact.
- **Text** with the bundled fonts and every installed TTF / OTF. Text stays live until converted to outlines.
- **Grid**, snap to grid, a tracing image under or over the drawing, unlimited undo (100 steps).
- **Files**: open and save SVG (paths, shapes, groups, transforms, `use`, gradients, inline CSS, `<style>` classes and ids, arcs,
  text / tspan), export PNG at any scale, with or without a background. Unsupported elements (filters, masks, clip paths, images,
  patterns) are skipped and the status bar says so.

## Font editing
- Create a font, or open a `.ttf` / `.otf` (TrueType and CFF outlines, composites are flattened). Every glyph is edited with the same
  tools as an SVG: draw, trace over an image, use booleans, transform.
- Metric guides: baseline, x-height, cap height, ascender, descender, origin and advance width.
- Glyph grid with thumbnails and a filter, add whole character sets (A-Z, a-z, digits, punctuation, ASCII, Latin-1), edit glyph name,
  code point and advance width, center a glyph, fit the advance to the outline.
- **Fix direction** orients contours the TrueType way, **Remove overlap** merges overlapping strokes into clean outlines. Overlap
  removal also runs on export (switchable).
- A preview line sets any text in the font being edited. Export writes a TrueType file (`glyf`, `cmap`, `head`, `hhea`, `hmtx`,
  `loca`, `maxp`, `name`, `OS/2`, `post`, `kern`); cubic curves are converted to quadratics.

## Shortcuts (Help > Keyboard Shortcuts in the app)
| | |
|-|-|
| V / A / P / F | select / node edit / pen / freehand |
| R / E / L / T / I | rectangle / ellipse / line / text / eyedropper |
| H, Space (hold), middle drag / wheel | pan / zoom |
| Ctrl+0 / Ctrl+1 | fit page / actual size |
| Ctrl+Z / Ctrl+Shift+Z | undo / redo |
| Ctrl+C, X, V, D | copy, cut, paste, duplicate |
| Ctrl+G / Ctrl+Shift+G | group / ungroup |
| PgUp, PgDn, Home, End | raise, lower, to front, to back |
| Ctrl++ / Ctrl+- / Ctrl+Shift+8 | union / subtract / intersect |
| Ctrl+K / Ctrl+Shift+K | combine / break apart |
| Ctrl+; / Ctrl+Shift+; | grid / snap |
| Shift while dragging | keep proportions, 15 degree steps |
| Alt while dragging | draw from the centre, break handle symmetry |
| [ and ] (font mode) | previous / next glyph |

## Developer flags
`--selftest` (tests), `--demo` (sample drawing), `--shot file.png` (screenshot after a few frames), `--size WxH`, `--scale N`,
`--render in.svg out.png [scale]` (headless SVG to PNG).

## Source layout
`geom`, `path`, `fit`, `boolean`, `pathops` (geometry and path operations) - `raster`, `stroke`, `render` (anti-aliased scanline
renderer) - `doc`, `style`, `commands` (document model) - `tools`, `nodeedit`, `texttool`, `shortcuts` (interaction) -
`svg_read`, `svg_write`, `xml` (SVG files) - `text` (fonts for text objects) - `ttf`, `font_doc`, `font_ui` (font editing) -
`gfx`, `ui`, `icons`, `brand`, `pen*`, `prefs`, `fileio` (platform and widgets, shared in spirit with Pangolin Paints).

## Known limits
- Fonts: simple glyphs only on export (composites are flattened on import), no hinting, no kerning editor (the `kern` table is only written if
  pairs exist), imports at most 3000 glyphs of a font, and undo history is per glyph (it resets when you switch glyphs).
- SVG: `tspan` colour overrides, text on a path, clip paths, masks, filters, patterns and embedded images are not supported.

## License
BSD 3-Clause. See [LICENSE](LICENSE).
