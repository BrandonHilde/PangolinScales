package pangolin

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import oui "odinui:odinui"

// ---------------------------------------------------------------------------
// Frame-by-frame animation for SVG documents. Each frame is a complete drawing of its own, with its own root
// node; nothing is tweened. d.root is always the live frame's root, so the tools never need to know frames exist.
// A font document keeps the single frame doc_new gives it: a glyph swaps d.root by itself (font_load_glyph), which
// is why frame_root is how to reach a frame's drawing rather than frames[i].root.
// ---------------------------------------------------------------------------

FRAME_DURATION :: 100 // ms, for a document that has never said otherwise

Frame :: struct {
	root:      ^Node,
	duration:  int, // ms
	ver:       int, // bumped when this frame's drawing changes; a frame switch alone doesn't
	thumb:     Texture,
	thumb_ver: int,
}

// Onion skin: the neighboring frames drawn under this one.
onion := false
onion_prev := 1 // how many frames before this one show
onion_next := 1 // and after it
onion_alpha := 30 // percent

frame_root :: proc(d: ^Doc, i: int) -> ^Node {
	if i == d.active_frame do return d.root
	return d.frames[i].root
}

@(private = "file")
frame_new_root :: proc(d: ^Doc) -> ^Node {
	root := node_new(d, .Group)
	name_set(&root.name, "root")
	return root
}

// Makes frame `i` the live one. It costs no undo step and leaves the document unmodified.
@(private = "file")
frame_go :: proc(d: ^Doc, i: int) {
	if i != d.active_frame do clear(&d.sel)
	d.frames[d.active_frame].root = d.root
	d.active_frame = i
	d.root = d.frames[i].root
	d.version += 1 // the renderer draws another drawing now
	// a burst of edits shares an undo step, but not across frames: each step belongs to one
	last_style_push, xf_push_t = -1, -1
}

frame_set :: proc(d: ^Doc, f: int) {
	nf := clamp(f, 0, len(d.frames) - 1)
	if nf == d.active_frame do return
	tools_cancel() // a half-finished gesture belongs to the frame it started on
	frame_go(d, nf)
}

// The shared timeline code calls this.
set_frame :: proc(f: int) {
	frame_set(doc, f)
}

// Editing the frame list ---------------------------------------------------------------------------------

tags_on_insert :: proc(d: ^Doc, pos: int) {
	for &t in d.tags {
		if t.from >= pos do t.from += 1
		if t.to >= pos do t.to += 1
	}
}

tags_on_delete :: proc(d: ^Doc, pos: int) {
	i := 0
	for i < len(d.tags) {
		t := &d.tags[i]
		if t.from > pos do t.from -= 1
		if t.to >= pos do t.to -= 1
		if t.to < t.from || t.to < 0 {
			ordered_remove(&d.tags, i)
			continue
		}
		t.from = max(t.from, 0)
		i += 1
	}
}

// Adds a frame after the current one and goes to it: empty, or a copy of the current one.
frame_add :: proc(d: ^Doc, duplicate: bool) {
	tools_cancel()
	frames_history_push(d)
	pos := d.active_frame + 1
	root: ^Node
	if duplicate {
		root = node_clone(d.root)
		renumber(d, root) // a gradient's id in the saved file comes from the object's uid
	} else {
		root = frame_new_root(d)
	}
	inject_at(&d.frames, pos, Frame{root = root, duration = d.frames[d.active_frame].duration, thumb_ver = -1})
	tags_on_insert(d, pos)
	frame_go(d, pos)
	doc_changed(d)
}

frame_delete :: proc(d: ^Doc) -> bool {
	if len(d.frames) <= 1 do return false
	tools_cancel()
	frames_history_push(d)
	pos := d.active_frame
	node_free(d.root)
	tex_destroy(&d.frames[pos].thumb)
	ordered_remove(&d.frames, pos)
	tags_on_delete(d, pos)
	if play_tag >= len(d.tags) do play_tag = -1
	clear(&d.sel)
	d.active_frame = clamp(pos, 0, len(d.frames) - 1)
	d.root = d.frames[d.active_frame].root
	doc_changed(d)
	return true
}

// Moves a frame to index `to`; the document stays on the frame it was on.
frame_move_to :: proc(d: ^Doc, from, to: int) -> bool {
	n := len(d.frames)
	if from < 0 || from >= n || to < 0 || to >= n || from == to do return false
	tools_cancel()
	frames_history_push(d)
	d.frames[d.active_frame].root = d.root
	f := d.frames[from]
	ordered_remove(&d.frames, from)
	inject_at(&d.frames, to, f)
	for x, i in d.frames {
		if x.root == d.root do d.active_frame = i
	}
	doc_changed(d)
	return true
}

frames_set_duration :: proc(d: ^Doc, ms: int, all: bool) {
	frames_history_push(d)
	if all {
		for &f in d.frames do f.duration = ms
	} else {
		d.frames[d.active_frame].duration = ms
	}
	doc_changed(d)
}

// The Tags window (shared with the other Pangolin tools) edits doc.tags as it goes and knows nothing of undo, so
// what it changed becomes one undo step when it closes.
@(private = "file")
tags_before: [dynamic]Tag
@(private = "file")
tags_modified_before: bool

tags_dialog_opened :: proc(d: ^Doc) {
	clear(&tags_before)
	append(&tags_before, ..d.tags[:])
	tags_modified_before = d.modified
}

tags_dialog_closed :: proc(d: ^Doc) {
	if slice.equal(tags_before[:], d.tags[:]) {
		d.modified = tags_modified_before
		return
	}
	s := state_take_frames(d)
	delete(s.tags)
	s.tags = slice.clone(tags_before[:])
	history_add(d, s)
	doc_changed(d)
}

// Thumbnails ---------------------------------------------------------------------------------------------

@(private = "file")
frame_thumb_stale :: proc(f: ^Frame, w, h: int) -> bool {
	return !tex_valid(f.thumb) || f.thumb_ver != f.ver || int(f.thumb.w) != w || int(f.thumb.h) != h
}

@(private = "file")
frame_thumb_render :: proc(d: ^Doc, i, w, h: int) {
	pix := make([]Color, w * h, context.temp_allocator)
	r: Raster
	raster_init(&r, w, h)
	defer raster_free(&r)
	k := min(f32(w) / max(d.w, 1), f32(h) / max(d.h, 1))
	view := Mat{k, 0, 0, k, (f32(w) - d.w * k) / 2, (f32(h) - d.h * k) / 2}
	render_doc_to(d, pix, w, h, view, &r, true, frame_root(d, i))
	f := &d.frames[i]
	tex_destroy(&f.thumb)
	f.thumb = tex_from_pixels(pix, w, h, .Linear)
	f.thumb_ver = f.ver
}

// Timeline: the bar's buttons ------------------------------------------------------------------------------

// An icon button with a small + or - badge (new frame, delete frame).
obadge_button :: proc(key: string, ic: Icon, plus: bool, tip: Tip, enabled := true) -> bool {
	n := oui.button_begin(uictx, key, {class = "icon-btn tl-btn", disabled = !enabled})
	oui.label(uictx, "icon", icon_text(ic), {class = "icon"})
	oui.label(uictx, "badge", icon_text(plus ? .Plus : .Minus), {class = "icon badge"})
	oui.end(uictx)
	oui_tip(n, tip)
	return n.clicked && enabled
}

timeline_bar_controls :: proc() {
	d := doc
	tb :: proc(key: string, ic: Icon, tip: Tip, enabled := true, lit := false) -> bool {
		c, _ := oui_icon_button(key, ic, tip, {class = "tl-btn", enabled = enabled, lit = lit})
		return c
	}
	n := len(d.frames)
	if obadge_button("frame-new", .Frame, true, cmd_tip("New frame", .Frame_New)) do run_cmd(.Frame_New)
	if tb("frame-dup", .Copy, cmd_tip("Duplicate frame", .Frame_Dup)) do run_cmd(.Frame_Dup)
	if obadge_button("frame-del", .Frame, false, cmd_tip("Delete frame", .Frame_Del), n > 1) do run_cmd(.Frame_Del)
	if tb("frame-left", .Frame_Left, cmd_tip("Move frame left", .Frame_Left), d.active_frame > 0) do run_cmd(.Frame_Left)
	if tb("frame-right", .Frame_Right, cmd_tip("Move frame right", .Frame_Right), d.active_frame < n - 1) do run_cmd(.Frame_Right)
	oui.element_leaf(uictx, "gap1", "tl-gap")
	if tb("first", .First, cmd_tip("First frame", .Frame_First)) do run_cmd(.Frame_First)
	if tb("prev", .Left, cmd_tip("Previous frame", .Frame_Prev)) do run_cmd(.Frame_Prev)
	if tb("play", playing ? .Stop : .Right, cmd_tip(playing ? "Pause" : "Play", .Play), lit = playing) do run_cmd(.Play)
	if tb("next", .Right, cmd_tip("Next frame", .Frame_Next)) do run_cmd(.Frame_Next)
	if tb("last", .Last, cmd_tip("Last frame", .Frame_Last)) do run_cmd(.Frame_Last)
	oui.element_leaf(uictx, "gap2", "tl-gap")
	timeline_tag_controls()
	if obutton(fmt.tprintf("%d ms", d.frames[d.active_frame].duration), 64, {"Frame duration", cmd_help(.Frame_Props)}, key = "duration") do run_cmd(.Frame_Props)
	if tb("onion", .Onion, cmd_tip("Onion skin", .Toggle_Onion), lit = onion) do run_cmd(.Toggle_Onion)
}

// Timeline: the strip of frames ----------------------------------------------------------------------------

tl_scroll: i32

Frame_Drag :: struct {
	idx: int, // the frame pressed on, or -1
	x0:  i32,
	on:  bool, // it has moved far enough to be a drag rather than a click
}

frame_drag := Frame_Drag {
	idx = -1,
}

// Where a dragged frame lands when the pointer is at gap `gap` between frames.
frame_drop_index :: proc(from, gap: int) -> int {
	return gap > from ? gap - 1 : gap
}

panel_timeline_grid :: proc(body: Rect) {
	ui.layer = 0
	d := doc
	TAG_H :: 8
	NUM_H :: 13
	PAD :: 4
	fill_rect(body, C_PANEL_DK)
	th := max(body.h - TAG_H - NUM_H - PAD, 12)
	tw := clamp(i32(f32(th) * d.w / max(d.h, 1)), 28, 170)
	cell_w := tw + 6
	n := i32(len(d.frames))
	content := n * cell_w + PAD * 2
	over := ui_hover(body)
	if over {
		if ui.wheel != 0 do tl_scroll -= i32(ui.wheel) * cell_w
		if ui.wheel_h != 0 do tl_scroll += i32(ui.wheel_h) * cell_w
	}
	// follow the current frame when it changes, and otherwise leave the view where the wheel put it
	@(static) seen_frame := -1
	@(static) seen_doc: ^Doc
	if seen_frame != d.active_frame || seen_doc != d {
		seen_frame, seen_doc = d.active_frame, d
		ax := i32(d.active_frame) * cell_w
		if ax < tl_scroll do tl_scroll = ax
		if ax + cell_w + PAD * 2 > tl_scroll + body.w do tl_scroll = ax + cell_w + PAD * 2 - body.w
	}
	tl_scroll = clamp(tl_scroll, 0, max(content - body.w, 0))

	clip_begin(body)
	defer clip_end()
	x0 := body.x + PAD - tl_scroll
	cy := body.y + TAG_H
	px_w, px_h := int(math.round(f32(tw) * ui.scale)), int(math.round(f32(th) * ui.scale))
	// one thumbnail per interface frame, so a long animation can't stall the interface; never in mid-gesture,
	// when the current frame is changing all the time
	rendered := tl.kind != .None
	for i in 0 ..< int(n) {
		fx := x0 + i32(i) * cell_w
		if fx + cell_w < body.x || fx > body.x + body.w do continue
		f := &d.frames[i]
		cell := Rect{fx, cy, cell_w - 2, th + NUM_H}
		active := i == d.active_frame
		hover := over && in_rect(cell, ui.mx, ui.my)
		if active {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_ACCENT_TINT)
			draw_rrect_outline(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_ACCENT)
		} else if hover {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, Color{255, 255, 255, 12})
		}
		if frame_thumb_stale(f, px_w, px_h) && !rendered && px_w > 0 && px_h > 0 {
			frame_thumb_render(d, i, px_w, px_h)
			rendered = true
		}
		box := Rect{cell.x + 2, cell.y + 2, tw, th - 2}
		if tex_valid(f.thumb) {
			draw_tex(f.thumb, {0, 0, f32(f.thumb.w), f32(f.thumb.h)}, {f32(box.x), f32(box.y), f32(box.w), f32(box.h)})
		} else {
			ctl_well(box)
		}
		label := fmt.tprintf("%d", i + 1)
		text(cell.x + (cell.w - text_w(label)) / 2, cell.y + th + (NUM_H - FONT_CAP) / 2, label, active ? C_TEXT : C_TEXT_DIM)
		if hover {
			tooltip_hover(make_id({}, fmt.tprintf("frame%d", i)), {fmt.tprintf("Frame %d (%d ms)", i + 1, f.duration), "Click to go to this frame, drag to move it. Double-click for its duration, right-click for a menu."})
			if ui.pressed[0] {
				set_frame(i)
				frame_drag = {
					idx = i,
					x0  = ui.mx,
				}
				if ui.dbl_click do run_cmd(.Frame_Props)
			}
			// opened on release, since a popup opened on the press would be closed by that same click
			if ui.released[1] && !popup.open {
				set_frame(i)
				popup_begin(make_id({}, "framemenu"), Rect{ui.mx, ui.my, 1, 1}, 150)
				popup_item("Insert Frame", cmd = .Frame_New)
				popup_item("Duplicate Frame", cmd = .Frame_Dup)
				popup_item("Delete Frame", cmd = .Frame_Del, enabled = n > 1)
				popup_sep()
				popup_item("Duration...", cmd = .Frame_Props)
			}
		}
	}
	// tag bars above the frames they cover
	for &t, ti in d.tags {
		tr := Rect{x0 + i32(t.from) * cell_w, body.y + 2, i32(t.to - t.from + 1) * cell_w - 2, 4}
		draw_rrect(f32(tr.x), f32(tr.y), f32(tr.w), f32(tr.h), 2, t.color)
		if ti == play_tag do draw_rrect_outline(f32(tr.x - 1), f32(tr.y - 1), f32(tr.w + 2), f32(tr.h + 2), 2, WHITE)
		if over && in_rect(tr, ui.mx, ui.my) {
			tooltip_hover(make_id(tr, "tag"), {name_str(&t.name), "This tag's range of frames. Click to play only these frames, again to play all."})
			if ui.pressed[0] do play_tag = play_tag == ti ? -1 : ti
		}
	}
	// dragging a frame: the line shows where it would land, and past the edges the strip scrolls
	if frame_drag.idx >= 0 {
		if frame_drag.idx >= int(n) {
			frame_drag = {
				idx = -1,
			}
		} else {
			if !frame_drag.on && ui.down[0] && abs(ui.mx - frame_drag.x0) > 4 do frame_drag.on = true
			gap := int(clamp((ui.mx - x0 + cell_w / 2) / cell_w, 0, n))
			if frame_drag.on {
				ui.cursor = .RESIZE_EW
				if ui.mx < body.x + 12 do tl_scroll -= 4
				if ui.mx > body.x + body.w - 12 do tl_scroll += 4
				if frame_drop_index(frame_drag.idx, gap) != frame_drag.idx {
					fill_rect(Rect{x0 + i32(gap) * cell_w - 2, cy, 2, th + NUM_H}, C_ACCENT)
				}
			}
			if !ui.down[0] {
				if frame_drag.on do frame_move_to(d, frame_drag.idx, frame_drop_index(frame_drag.idx, gap))
				frame_drag = {
					idx = -1,
				}
			}
		}
	}
	// where the view is in the strip; the wheel moves it
	if content > body.w {
		bar := max(body.w * body.w / content, 12)
		draw_rrect(f32(body.x + tl_scroll * (body.w - bar) / max(content - body.w, 1)), f32(body.y + body.h - 3), f32(bar), 2, 1, C_RING_HI)
	}
}

// Export ----------------------------------------------------------------------------------------------------

Export_Format :: enum {
	PNG,
	Sequence,
	GIF,
}

EXPORT_FORMAT_NAMES := [Export_Format]string {
	.PNG      = "PNG (current frame)",
	.Sequence = "PNG Sequence",
	.GIF      = "Animated GIF",
}

export_format: Export_Format
export_gif_loop := true
export_range_tag := false

export_frame_range :: proc(d: ^Doc) -> (lo, hi: int) {
	lo, hi = 0, len(d.frames) - 1
	if export_range_tag && play_tag >= 0 && play_tag < len(d.tags) {
		lo = clamp(d.tags[play_tag].from, 0, hi)
		hi = clamp(d.tags[play_tag].to, lo, hi)
	}
	return
}

// The frames in the export range as an animated GIF, in the temp allocator.
export_gif_bytes :: proc(d: ^Doc, scale: f32, loop, with_bg: bool) -> (data: []u8, w, h: int) {
	lo, hi := export_frame_range(d)
	n := hi - lo + 1
	pics := make([][]Color, n, context.temp_allocator)
	delays := make([]int, n, context.temp_allocator)
	for i in 0 ..< n {
		pics[i], w, h = render_to_pixels(d, scale, WHITE, with_bg, lo + i)
		delays[i] = d.frames[lo + i].duration
	}
	return gif_encode_frames(pics, w, h, 1, delays, loop), w, h
}

// Writes the frames in the export range as stem_0001.png, stem_0002.png ... and says how many it wrote.
export_sequence :: proc(d: ^Doc, stem: string, scale: f32, with_bg: bool) -> int {
	lo, hi := export_frame_range(d)
	count := 0
	for f in lo ..= hi {
		pix, w, h := render_to_pixels(d, scale, WHITE, with_bg, f)
		if write_file(fmt.tprintf("%s_%04d.png", stem, f - lo + 1), encode_png(pix, w, h)) do count += 1
	}
	return count
}

export_run :: proc(d: ^Doc, format: Export_Format, scale: f32, with_bg: bool) {
	base := name_str(&d.title)
	switch format {
	case .PNG:
		if path, ok := native_dialog(true, "Export PNG", FILTERS_PNG[:], "png", fmt.tprintf("%s.png", base)); ok {
			if png_save(d, path, scale, with_bg) do set_statusf("Exported %s", path_basename(path))
			else do message("Export", "Could not write the file.")
		}
	case .Sequence:
		if path, ok := native_dialog(true, "Export PNG Sequence (base name)", FILTERS_PNG[:], "png", fmt.tprintf("%s.png", base)); ok {
			stem := strings.trim_suffix(path, path_ext(path))
			lo, hi := export_frame_range(d)
			count := export_sequence(d, stem, scale, with_bg)
			if count == hi - lo + 1 do set_statusf("Exported %d PNG files", count)
			else do message("Export", "Could not write all the files.")
		}
	case .GIF:
		if path, ok := native_dialog(true, "Export GIF", FILTERS_GIF[:], "gif", fmt.tprintf("%s.gif", base)); ok {
			data, _, _ := export_gif_bytes(d, scale, export_gif_loop, with_bg)
			if write_file(path, data) do set_statusf("Exported %s", path_basename(path))
			else do message("Export", "Could not write the file.")
		}
	}
}

dlg_export :: proc() {
	d := doc
	many := len(d.frames) > 1
	if !many do export_format = .PNG
	row: i32 = many ? 22 : 0
	c := dialog_frame("Export", 300, 138 + row + 18)
	y := c.y
	if many {
		FORMAT_TIP :: "PNG saves the current frame. A PNG sequence saves one numbered file per frame, and a GIF plays as an animation."
		tip_text(c.x, y + 3, "Format", C_TEXT, {"Format", FORMAT_TIP})
		combo_enum(Rect{c.x + 110, y, c.w - 110, 14}, EXPORT_FORMAT_NAMES, &export_format, {"Format", FORMAT_TIP})
		y += row
	}
	SCALE_TIP :: "The image size compared to the page: 100% is one pixel per document unit. Higher is sharper and a larger file."
	tip_text(c.x, y + 3, "Scale", C_TEXT, {"Scale", SCALE_TIP})
	slider(Rect{c.x + 110, y, c.w - 110, 14}, &dialog.a, 10, 800, "", {"Scale", SCALE_TIP}, "%")
	w, h := int(d.w * f32(dialog.a) / 100 + 0.5), int(d.h * f32(dialog.a) / 100 + 0.5)
	tip_text(c.x, y + 24, fmt.tprintf("Size: %d x %d px", w, h), C_TEXT_DIM, {"Image size", "The size the exported image will be at this scale."})
	y += 42
	checkbox(c.x, y, "Transparent background", &dialog.flag, {"Transparent background", "On: areas with nothing drawn are see-through in the image. In a GIF, pixels are either see-through or solid. Off: the page background is included."})
	y += 18
	if export_format == .GIF {
		checkbox(c.x, y, "Loop forever", &export_gif_loop, {"Loop forever", "On: the GIF keeps repeating. Off: it plays once and stops on the last frame."})
		y += 18
	}
	if export_format != .PNG && play_tag >= 0 && play_tag < len(d.tags) {
		checkbox(c.x, y, "Only the selected tag", &export_range_tag, {"Only the selected tag", "Export just the frames of the tag picked in the timeline, not the whole animation."})
	}
	ok, cancel := dialog_buttons(c, "Choose where to save it (Enter).", "Export")
	if ok {
		format, scale, with_bg := export_format, f32(dialog.a) / 100, !dialog.flag
		dialog_close()
		export_run(d, format, scale, with_bg)
	} else if cancel {
		dialog_close()
	}
}

dlg_frame_props :: proc() {
	c := dialog_frame("Frame Properties", 280, 110)
	y := c.y
	row_int(c, y, "Duration (ms)", &dialog.a, 10, 60000, "How long this frame shows when the animation plays, in thousandths of a second.")
	y += 22
	checkbox(c.x, y, "Apply to all frames", &dialog.flag, {"Apply to all frames", "Give every frame this duration, not just the current one."})
	ok, cancel := dialog_buttons(c, "Apply this duration (Enter). You can undo it.")
	if ok {
		frames_set_duration(doc, dialog.a, dialog.flag)
		dialog_close()
	} else if cancel {
		dialog_close()
	}
}

// Color math --------------------------------------------------------------------------------------------------

rgb_to_hsv :: proc(c: Color) -> (h, s, v: f32) {
	r, g, b := f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255
	mx := max(r, max(g, b))
	mn := min(r, min(g, b))
	d := mx - mn
	v = mx
	s = mx == 0 ? 0 : d / mx
	switch {
	case d == 0:
		h = 0
	case mx == r:
		h = math.mod((g - b) / d, 6)
	case mx == g:
		h = (b - r) / d + 2
	case:
		h = (r - g) / d + 4
	}
	h *= 60
	if h < 0 do h += 360
	return
}

hsv_to_rgb :: proc(h, s, v: f32, a: u8 = 255) -> Color {
	hh := math.mod(h, 360)
	if hh < 0 do hh += 360
	c := v * s
	x := c * (1 - abs(math.mod(hh / 60, 2) - 1))
	m := v - c
	r, g, b: f32
	switch int(hh / 60) {
	case 0:
		r, g, b = c, x, 0
	case 1:
		r, g, b = x, c, 0
	case 2:
		r, g, b = 0, c, x
	case 3:
		r, g, b = 0, x, c
	case 4:
		r, g, b = x, 0, c
	case:
		r, g, b = c, 0, x
	}
	to8 :: proc(f: f32) -> u8 {return u8(clamp(f * 255 + 0.5, 0, 255))}
	return Color{to8(r + m), to8(g + m), to8(b + m), a}
}
