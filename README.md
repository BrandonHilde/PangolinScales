# Pangolin Scales

*Curves, scale by scale.* An SVG and font editor written in Odin with SDL3.

A sibling of [Pangolin Paints](../PangolinPaints) and Pangolin Pixels in the Pangolin graphical editing suite: same look and feel,
built for paths instead of pixels. The font side is based on ScalarCanvas.

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows. [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui) is a
git submodule in `libs/odinui`: clone with `git clone --recursive`, or let the build scripts fetch it on the first build
(`git submodule update --init`). To build by hand: `odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui`.
Drag `.svg`, `.ttf` or `.otf` files onto the window to open them.
`PangolinScales --selftest` runs the headless test suite (on Windows use `PangolinScales-console.exe`, since the GUI build has no console).

## Tool groups
The left toolbar holds **tool groups**, as in Pangolin Paints. Each group has a hotkey shown as a keycap (1 to 5 by
default): pressing it picks the tool last used from that group, pressing it again cycles through the group's tools.
- Click a group's keycap to assign a hotkey (any letter or digit; Esc cancels, Backspace clears), rename or remove the group.
  A hotkey on a letter takes over that letter's single-key tool shortcut. Right-click the header for rename / remove.
- The **+** at the end of a group adds any tool or **path operation** (union, subtract, intersect, exclude, combine,
  break apart, reverse, simplify, offset, object / stroke to path) to it; right-click one to take it out. Operation buttons
  act on the selection at once and are greyed out until enough objects are selected. The default **Path** group (6) holds
  the booleans; the hotkey of a group with operations but no tools repeats the operation last used from it.
- **+ New Group** adds an empty group (up to 12). View > Reset Tool Groups brings back the defaults.
- Groups are saved in `scales.cfg`.
- **Canvas mode** (Tab, or the button at the right of the menu bar) hides the toolbar, tabs and side panels; a bar along the
  bottom shows each group as `[key] -> current tool`.

The fill / stroke chips below the groups show the selection's paints (or those new shapes get); click one to edit it in
Properties.

## SVG editing
- **Tools**: select (move, scale, rotate), node edit, pen (click, click-drag for curves, click the first point to close), freehand
  (fits smooth Bezier curves to your stroke), rectangle, ellipse, line, text, eyedropper, hand, zoom.
- **Nodes**: drag anchors and handles (handles mirror when a node is smooth, Alt breaks the symmetry), double click a segment to add a
  node, make nodes smooth or corner, delete nodes, move with the arrow keys.
- **Style**: fill and stroke as none, solid, linear or radial gradient (stops, spread, draggable gradient handles on the canvas),
  stroke width, caps, joins, dashes, opacity, even-odd fill, corner radius, exact X / Y / W / H.
- **Objects**: group / ungroup, z-order, lock and hide, duplicate, copy / paste (also as SVG text with other apps), flip, rotate 90,
  align and distribute, an objects panel (drag rows to reorder objects or move them in and out of groups; drop beside the
  list to cancel).
- **Path menu**: union, subtract, intersect, exclude, combine, break apart, reverse, simplify, offset in and out, stroke to path,
  object to path, text to outlines. Booleans keep untouched curves exact.
- **Text** with the bundled fonts and every installed TTF / OTF (the font button opens a searchable list; size is a slider).
  With the text tool, click a text object to edit it or drag it to move it. Text stays live until converted to outlines.
- **Grid**, snap to grid, a tracing image under or over the drawing, unlimited undo (100 steps).
- **Files**: open and save SVG (paths, shapes, groups, transforms, `use`, gradients, inline CSS, `<style>` classes and ids, arcs,
  text / tspan), export PNG at any scale, with or without a background. Unsupported elements (filters, masks, clip paths, images,
  patterns) are skipped and the status bar says so.

## Font editing
- Create a font, or open a `.ttf` / `.otf` (TrueType and CFF outlines, composites are flattened). A font document has the same
  interface as an SVG (every tool, the Object / Path / Text menus, the objects and properties panel) plus a **Font** menu and a
  font panel. Each glyph is a drawing of its own: shapes, groups, hidden and locked objects and its undo history stay with the
  glyph when you move to another one.
- The glyph's outline is everything visible as it is painted: fills, and strokes as their outline shape. Hide an object to leave it
  out.
- Metric guides on the canvas: baseline, x-height, cap height, ascender, descender, origin and advance width. The status bar shows
  the pointer in font units.
- Glyph grid with thumbnails and a filter, add whole character sets (A-Z, a-z, digits, punctuation, ASCII, Latin-1), edit glyph name,
  code point and advance width, center a glyph, fit the advance to the outline.
- **Fix direction** orients contours the TrueType way, **Remove overlap** merges overlapping strokes into clean outlines. Overlap
  removal also runs on export (switchable).
- A preview line sets any text in the font being edited. Export writes a TrueType file (`glyf`, `cmap`, `head`, `hhea`, `hmtx`,
  `loca`, `maxp`, `name`, `OS/2`, `post`, `kern`); cubic curves are converted to quadratics.

## Shortcuts (Help > Keyboard Shortcuts in the app)
| | |
|-|-|
| 1 - 5 | tool groups (press again to cycle) |
| Tab | canvas mode |
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

## Customising the interface
The interface is laid out and styled with CSS through [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui), like Pangolin
Paints and with the same colour variables. The default theme is [assets/ui/theme.css](assets/ui/theme.css). To change it,
create `theme.css` next to the executable: it is applied on top of the default theme and reloaded while the program runs,
so it only needs what you change.

```css
:root   { --accent: #6aa8ff; --accent-tint: rgba(106, 168, 255, 0.22); --panel: #1f2430; }
#body   { flex-direction: row-reverse; }   /* tools on the right, objects and properties on the left */
#right  { width: 300px; }
#objects { flex-basis: 50%; }               /* a taller object list */
```

The colour variables in `:root` also drive the parts the program draws itself (object list, properties, glyph grid,
dialogs, menus). Icons are SVG files in `assets/icons`, drawn by the document renderer at the screen's resolution, and
behave like a font in CSS (`font-family: icons`), so `color` and `font-size` style them like text.

## Developer flags
`--selftest` (tests), `--demo` (sample drawing), `--shot file.png` (screenshot after a few frames), `--size WxH`, `--scale N`,
`--render in.svg out.png [scale]` (headless SVG to PNG), `--icon-sheet out.png` (every icon at several sizes),
`--clicks "frame:x,y;..."` (left clicks at window pixels on those frames, for checking the interface with `--shot`),
`--menu N` (opens menu N).

## Source layout
`geom`, `path`, `fit`, `boolean`, `pathops` (geometry and path operations) - `raster`, `stroke`, `render` (anti-aliased scanline
renderer) - `doc`, `style`, `commands` (document model) - `tools`, `nodeedit`, `texttool`, `shortcuts` (interaction) -
`svg_read`, `svg_write`, `xml` (SVG files) - `text` (fonts for text objects) - `ttf`, `font_doc`, `font_ui` (font editing) -
`app`, `panels`, `toolgroups` (window layout, panels, tool groups) - `oui`, `oui_kit` (OdinUI host: SDL renderer backend,
input bridge, controls) - `gfx`, `ui`, `icons`, `brand`, `pen*`, `prefs`, `fileio` (platform and widgets, shared with
Pangolin Paints).

## Known limits
- Fonts: simple glyphs only on export (composites are flattened on import), no hinting, no kerning editor (the `kern` table is only written if
  pairs exist), imports at most 3000 glyphs of a font, and undo history is per glyph. Fix direction turns a glyph whose contours
  it changes back into a single path.
- SVG: `tspan` colour overrides, text on a path, clip paths, masks, filters, patterns and embedded images are not supported.

## License
BSD 3-Clause. See [LICENSE](LICENSE).
