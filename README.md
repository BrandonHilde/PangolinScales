# Pangolin Scales

*Curves, scale by scale.* An SVG and font editor written in Odin with SDL3.

A sibling of [Pangolin Paints](../PangolinPaints) and Pangolin Pixels in the Pangolin graphical editing suite: same look and feel,
built for paths instead of pixels. The font side is based on ScalarCanvas.

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows. [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui) and
the code the Pangolin tools share ([PangolinShared](https://github.com/BrandonHilde/PangolinShared)) are git submodules in
`libs/odinui` and `libs/shared`: clone with `git clone --recursive`, or let the build scripts fetch them on the first build
(`git submodule update --init`). Odin compiles one folder as one package, so the build scripts first copy the shared code into
`src` as `shared_*.odin` (ignored by git: edit it in `libs/shared`). To build by hand, run that step yourself:
`sh libs/shared/sync.sh` (or `libs\shared\sync.bat`), then `odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui`.
Drag `.svg`, `.ttf` or `.otf` files onto the window to open them.
`PangolinScales --selftest` runs the headless test suite (on Windows use `PangolinScales-console.exe`, since the GUI build has no console).

## Tool groups
The left toolbar holds **tool groups**, as in Pangolin Paints. Each group has a hotkey shown as a keycap (1 to 5 by
default): pressing it picks the tool last used from that group, pressing it again cycles through the group's tools.
- Click a group's keycap to assign a hotkey (any letter or digit; Esc cancels, Backspace clears), rename or remove the group.
  A hotkey on a letter takes over that letter's single-key tool shortcut. Right-click the header for rename / remove.
- The **+** at the end of a group adds any tool, switch or **path operation** (union, subtract, intersect, exclude, combine,
  break apart, reverse, close or open, simplify, offset, object / stroke to path) to it; right-click one to take it out. Operation buttons
  act on the selection at once and are grayed out until enough objects are selected. The default **Path** group (6) holds
  the booleans; the hotkey of a group with operations but no tools repeats the operation last used from it.
- **Switches** (Grid, Snap to Grid, Onion Skin) can sit among the tools. Clicking one turns it on and shows its settings in the
  options bar; picking a tool brings the tool's settings back, and the switch stays on. Click a switch that is on to see its settings
  again, and once more to turn it off. The default **View** group holds Hand, Zoom, Grid and Snap.
- A **color group** holds colors instead: the + of an empty group adds the current fill color or all the swatches. Clicking a color
  makes it the fill, of the selection or for new shapes; the group's hotkey steps through its colors; right-click removes one.
- **+ New Group** adds an empty group (up to 12). Workspaces > Default brings back the default groups.
- Groups are saved in `scales.cfg`.
- **Canvas mode** (Tab, or the button at the right of the menu bar) hides the toolbar, tabs, side panels and the panel under the
  canvas; a bar along the bottom shows each group as `[key] -> current tool`.
- **UI scale** (View > UI Scale): Auto sizes the interface to the screen the window is on, or a slider sets it from 50% to 500%.
  Nothing about the window limits the slider: the panels have a CSS `max-width` or `max-height`, so a very large interface keeps
  room for the canvas.

The options bar holds the current tool's settings only; its name, key and a hint on using it are at the left of the status bar.

The fill / stroke chips below the groups show the selection's paints (or those new shapes get); click one to edit it in
Properties.

## Workspaces
A workspace is a whole tool set-up: the groups, with their hotkeys, switches, operations and colors. The **Workspaces** menu
switches between the built-in Default, Illustration, Font Design and Animation and your own, which are `.scws` files in a
`workspaces` folder next to the executable. Manage Workspaces saves the current set-up under a name or deletes a saved one; Import
and Export read and write a workspace file anywhere.

## The panel under the canvas
The bar under the canvas ends in a switch: **timeline**, **file browser** or hidden, which leaves just the bar. View > Timeline and
View > File Browser do the same. It starts hidden, and comes back as you left it.

**File browser**: thumbnails of the SVG drawings, fonts and images in a folder (`.png`, `.jpg`, `.webp`, `.bmp`, `.tga`, `.gif`, `.qoi`).
Double-click a folder to go into it. Then drag a thumbnail:
| | on the canvas | on the tab bar, or double-click |
|-|-|-|
| SVG | adds its objects at that point, selected, as one undo step | opens it |
| Font | opens it | opens it |
| Image | becomes the tracing image, centered at that point | becomes the tracing image, fitted to the page |

## Animation
An SVG document can have frames. Each is a complete drawing of its own: nothing is tweened, and every tool works on the frame you
are on. The Frame menu and the timeline add, duplicate, delete and move frames.
- **Timeline**: a strip of thumbnails with tag bars above them. Click a frame to go to it, drag it to move it, double-click for its
  duration, right-click for a menu; the wheel scrolls.
- **Playback**: Enter plays and stops, through all frames or the tag picked in the timeline. Anything that edits stops it.
- **Tags** name a range of frames, with a direction (forward, reverse, ping-pong) and a color.
- **Onion skin**: the frames before and after this one drawn faintly under it, with how many and how strongly in the options bar.
- **Undo** is one list for the whole document. Undoing a change from another frame goes to that frame, and frame changes (new, delete,
  move, durations, tags) undo too.
- **Saving**: a document with one frame saves as a plain SVG, as it always has. With more, each frame is a top-level
  `<g data-pangolin-frame="DURATION_MS">` holding its objects, and tags are in `data-pangolin-tags` on the `svg` element. Frames after
  the first are `display="none"`, so a viewer without animation shows frame 1, and a discrete `<animate>` in each makes the
  file play in a browser.
- **Export** (Ctrl+Shift+E): a PNG of the current frame, a numbered PNG sequence (`name_0001.png`) or an animated GIF, for all frames or
  just the selected tag.

## SVG editing
- **Tools**: select (move, scale, rotate), node edit, pen (click for a straight line, drag for a curve; click the first point to close straight, drag it to close with a curve), freehand
  (fits smooth Bezier curves to your stroke), rectangle, ellipse, line, text, eyedropper, hand, zoom.
- **Nodes**: drag anchors and handles (handles mirror when a node is smooth, Alt breaks the symmetry), double click a segment to add a
  node, make nodes smooth or corner, delete nodes, move with the arrow keys. The **control points** tool (Shift+A) picks control points
  only, including ones lying on their anchor: where several overlap, click to step through them, then drag or use the arrow keys.
- **Style**: fill and stroke as none, solid, linear or radial gradient (stops, spread, draggable gradient handles on the canvas), with
  an HSV picker, RGB and alpha sliders, a hex field, swatches and recent colors, stroke width, caps, joins, dashes, opacity, even-odd fill, corner radius, exact X / Y / W / H.
- **Objects**: group / ungroup, z-order, lock and hide, duplicate, copy / paste (also as SVG text with other apps), flip, rotate 90,
  align and distribute, an objects panel (drag rows to reorder objects or move them in and out of groups; drop beside the
  list to cancel).
- **Path menu**: union, subtract, intersect, exclude, combine, break apart, reverse, close or open, simplify, offset in and out, stroke to path,
  object to path, text to outlines. Booleans keep untouched curves exact. Paths stay open unless you close them with the pen or
  turn on **Close Open Paths**, which lets freehand strokes close when they end near their start, and lets booleans and offset
  join the ends of open paths with a straight line. While it is off, union merges open paths into one path without closing
  them, and offset or any other boolean involving an open path is refused.
- **Text** with the bundled fonts and every installed TTF / OTF (the font button opens a searchable list; size is a slider).
  With the text tool, click a text object to edit it or drag it to move it. Text stays live until converted to outlines.
- **Grid**, snap to grid, a tracing image under or over the drawing, undo (100 steps).
- **Navigator** at the bottom of the right panel: the whole page with the visible area marked; click or drag to move the view (View > Navigator).
- **Files**: open and save SVG (paths, shapes, groups, transforms, `use`, gradients, inline CSS, `<style>` classes and ids, arcs,
  text / tspan), export at any scale, with or without a background. Unsupported elements (filters, masks, clip paths, images,
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

## Shortcuts (F1, or Help > Keyboard Shortcuts in the app)
| | |
|-|-|
| 1 - 6 | tool groups (press again to cycle) |
| Tab | canvas mode |
| V / A / Shift+A / P / B | select / node edit / control points / pen / freehand (F also works) |
| R / O / L / T / I | rectangle / ellipse / line / text / eyedropper |
| H, Space (hold), middle drag | pan |
| Wheel, Ctrl+= / Ctrl+- (or + / -) | zoom |
| Ctrl+0 / Ctrl+1 / Ctrl+2 | fit to window / 100% / 200% |
| Ctrl+Z / Ctrl+Shift+Z | undo / redo |
| Ctrl+C, X, V, J | copy, cut, paste, duplicate |
| Ctrl+A / Ctrl+D (or Ctrl+Shift+A) | select all / deselect |
| Ctrl+G / Ctrl+Shift+G | group / ungroup |
| PgUp, PgDn, Home, End | raise, lower, to front, to back |
| Ctrl+Alt+= / Ctrl+Alt+- / Ctrl+Alt+8 | union / subtract / intersect |
| Ctrl+K / Ctrl+Shift+K | combine / break apart |
| Ctrl+; / Ctrl+Shift+; | grid / snap |
| Alt+N | new frame |
| , / . | previous / next frame |
| Shift+, / Shift+. | first / last frame |
| Enter | play or stop (the pen tool has Enter for itself) |
| Alt+O | onion skin |
| Ctrl+S / Ctrl+Shift+S / Ctrl+Shift+E | save / save as / export |
| Shift while dragging | keep proportions, 15 degree steps |
| Alt while dragging | draw from the center, break handle symmetry |
| [ and ] (font mode) | previous / next glyph |
| F1 | the list of shortcuts |

## Customising the interface
The interface is laid out and styled with CSS through [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui), like Pangolin
Paints and with the same color variables. The default theme is [assets/ui/theme.css](assets/ui/theme.css). To change it,
create `theme.css` next to the executable: it is applied on top of the default theme and reloaded while the program runs,
so it only needs what you change.

```css
:root   { --accent: #6aa8ff; --accent-tint: rgba(106, 168, 255, 0.22); --panel: #1f2430; }
#body   { flex-direction: row-reverse; }   /* tools on the right, objects and properties on the left */
#right  { width: 300px; }
#objects { flex-basis: 50%; }               /* a taller object list */
```

The color variables in `:root` also drive the parts the program draws itself (object list, properties, glyph grid,
dialogs, menus). Icons are SVG files in `assets/icons`, drawn by the document renderer at the screen's resolution, and
behave like a font in CSS (`font-family: icons`), so `color` and `font-size` style them like text.

## Developer flags
`--selftest` (tests), `--demo` (sample drawing with a few frames), `--shot file.png` (screenshot after a few frames), `--shot-frame N` (which frame), `--size WxH`, `--scale N` (UI scale for this run, in percent),
`--render in.svg out.png [scale]` (headless SVG to PNG), `--icon-sheet out.png` (every icon at several sizes),
`--clicks "frame:x,y;..."` (left clicks at window pixels on those frames, `frame:x,y,r` for a right click, for checking the interface with `--shot`),
`--drag "frame:x0,y0,x1,y1;..."` (left drags at window pixels over 8 frames),
`--hover "frame:x,y"` (rests the pointer there from that frame on, for checking tooltips with `--shot` and a later `--shot-frame`),
`--menu N` (opens menu N).

## Source layout
`geom`, `path`, `fit`, `boolean`, `pathops` (geometry and path operations) - `raster`, `stroke`, `render` (anti-aliased scanline
renderer) - `doc`, `style`, `commands`, `frames` (document model, frames, timeline, export) - `tools`, `nodeedit`, `texttool`,
`shortcuts` (interaction) - `svg_read`, `svg_write`, `xml` (SVG files) - `text` (fonts for text objects) - `ttf`, `font_doc`,
`font_ui` (font editing) - `app`, `panels`, `toolgroups`, `switches`, `workspaces`, `files_hooks` (window layout, panels, tool groups,
workspaces, what the file browser does here) - `icons`, `brand`, `prefs`, `fileio` - `libs/shared` (copied in as `shared_*.odin`): the
OdinUI host, widgets, `gfx`, pen input, the file browser, tags and playback, image decoders and the GIF encoder, shared with the other
Pangolin tools.

## Known limits
- Fonts: simple glyphs only on export (composites are flattened on import), no hinting, no kerning editor (the `kern` table is only written if
  pairs exist), imports at most 3000 glyphs of a font, and undo history is per glyph. Fix direction turns a glyph whose contours
  it changes back into a single path.
- SVG: `tspan` color overrides, text on a path, clip paths, masks, filters, patterns and embedded images are not supported.

## License
BSD 3-Clause. See [LICENSE](LICENSE).
