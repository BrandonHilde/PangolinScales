package pangolin

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// Text tool: click to place text, type to edit. Text stays live (font, size, fill) until converted to outlines.
// ---------------------------------------------------------------------------

cur_font: Name
cur_text_size: f32 = 32

text_new: bool // the node being edited was just created (discarded again if left empty)
text_pushed: bool

text_editing :: proc() -> bool {
	return tl.text_uid != 0
}

text_begin :: proc(d: ^Doc, n: ^Node, is_new: bool) {
	text_finish()
	tl.text_uid = n.uid
	text_new = is_new
	text_pushed = is_new
	sel_set(d, n)
}

text_finish :: proc() {
	d := doc
	if d == nil || tl.text_uid == 0 {
		tl.text_uid = 0
		return
	}
	n := node_find(d.root, tl.text_uid)
	tl.text_uid = 0
	if n == nil do return
	if len(n.text) == 0 {
		if p := node_parent(d.root, n); p != nil {
			if i := node_index(p, n); i >= 0 do ordered_remove(&p.children, i)
		}
		node_free(n)
		clear(&d.sel)
		if text_new && len(d.undo) > 0 {
			s := pop(&d.undo)
			state_free(&s)
		}
		doc_changed(d)
	}
}

// A press on a text object: dragging moves it, a click (no drag) edits it.
text_press_uid: u32

tool_text :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if tl.kind == .Move {
		text_drag(d, p, sp)
		return
	}
	if over do ui.cursor = .IBEAM
	if !pressed do return
	hit := pick_node(d, p, true)
	if hit != nil && hit.kind == .Text {
		sel_set(d, hit)
		sel_remember(d)
		tl.kind = .Move
		tl.start, tl.cur, tl.start_scr, tl.moved, tl.pushed = p, p, sp, false, false
		text_press_uid = hit.uid
		return
	}
	history_push(d)
	n := new_shape(d, .Text)
	n.stroke = paint_none()
	n.x, n.y = snap_pt(p).x, snap_pt(p).y
	n.size = cur_text_size
	n.font = cur_font.n > 0 ? cur_font : make_name(DEFAULT_FONT)
	append(&d.root.children, n)
	text_begin(d, n, true)
	doc_changed(d)
}

// Moves the pressed text object with the pointer (grid snap and Shift as with the select tool); a release
// without a drag starts editing it instead.
text_drag :: proc(d: ^Doc, p, sp: Vec2) {
	tl.cur = p
	if !ui.down[0] {
		if !tl.moved && tl.text_uid != text_press_uid {
			if n := node_find(d.root, text_press_uid); n != nil do text_begin(d, n, false)
		}
		tl_reset()
		text_press_uid = 0
		return
	}
	if !tl.moved && v_len(sp - tl.start_scr) < 3 do return
	tl.moved = true
	ui.cursor = .RESIZE_ALL
	push_once(d)
	delta := p - tl.start
	if snap_grid {
		target := snap_pt(Vec2{tl.bbox.x0, tl.bbox.y0} + delta)
		delta = target - Vec2{tl.bbox.x0, tl.bbox.y0}
	}
	if ui.shift {
		if abs(delta.x) > abs(delta.y) do delta.y = 0
		else do delta.x = 0
	}
	sel_apply(d, mat_translate(delta.x, delta.y))
}

// Keyboard input for the node being edited. A click outside finishes editing.
text_update :: proc(d: ^Doc, p: Vec2, pressed: bool) {
	n := node_find(d.root, tl.text_uid)
	if n == nil {
		tl.text_uid = 0
		return
	}
	if pressed {
		if hit := pick_node(d, p, true); hit != n do text_finish()
		return
	}
	// keys belong to a focused field or an open dialog (the font chooser's search), not the text
	if ui.focus_id != 0 || dialog.kind != .None do return
	changed := false
	touch :: proc(d: ^Doc) {
		if !text_pushed {
			history_push(d)
			text_pushed = true
		}
	}
	for r in ui.chars {
		if r < 32 || r == 127 do continue
		touch(d)
		buf, n_enc := utf8.encode_rune(r)
		append(&n.text, ..buf[:n_enc])
		changed = true
	}
	if key_hit(.ENTER) {
		if ui.ctrl {
			text_finish()
			return
		}
		touch(d)
		append(&n.text, '\n')
		changed = true
	}
	if key_hit(.BACKSPACE) && len(n.text) > 0 {
		touch(d)
		_, size := utf8.decode_last_rune(n.text[:])
		resize(&n.text, len(n.text) - size)
		changed = true
	}
	if key_hit(.ESCAPE) {
		text_finish()
		return
	}
	if changed do doc_changed(d)
}

// Caret position (document space, local to the node) at the end of the text: x, baseline y, line height.
text_end_pos :: proc(n: ^Node) -> (x, y, h: f32) {
	f := font_load(font_find(name_str(&n.font)))
	if f == nil do return n.x, n.y, n.size
	scale := stbtt.ScaleForMappingEmToPixels(&f.info, n.size)
	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&f.info, &asc, &desc, &gap)
	line_h := f32(asc - desc + gap) * scale
	x, y = n.x, n.y
	prev: rune
	for r in text_str(n) {
		if r == '\n' {
			x = n.x
			y += line_h
			prev = 0
			continue
		}
		if prev != 0 do x += f32(stbtt.GetCodepointKernAdvance(&f.info, prev, r)) * scale
		adv, lsb: i32
		stbtt.GetCodepointHMetrics(&f.info, r, &adv, &lsb)
		x += f32(adv) * scale
		prev = r
	}
	return x, y, f32(asc) * scale
}

text_overlay :: proc(d: ^Doc) {
	n := node_find(d.root, tl.text_uid)
	if n == nil do return
	w := node_world(d.root, n)
	x, y, h := text_end_pos(n)
	a := to_screen(d, mat_apply(w, {x, y + h * 0.25}))
	b := to_screen(d, mat_apply(w, {x, y - h}))
	if i32(ui.time * 2) % 2 == 0 do draw_line(a, b, C_SEL)
	bb := node_doc_bounds(d, n)
	if !bounds_empty(bb) {
		p0, p1 := to_screen(d, {bb.x0, bb.y0}), to_screen(d, {bb.x1, bb.y1})
		outline_rect(Rect{i32(p0.x) - 2, i32(p0.y) - 2, i32(p1.x - p0.x) + 4, i32(p1.y - p0.y) + 4}, Color{60, 160, 255, 120})
	}
}

// Font and size -------------------------------------------------------------------------------------------

// Name of the font new text gets (and the edited text has).
cur_font_name :: proc() -> string {
	return cur_font.n > 0 ? name_str(&cur_font) : DEFAULT_FONT
}

// Sets the font of new text and of the text being edited, or else of the selected text objects.
text_font_set :: proc(name: string) {
	d := doc
	cur_font = make_name(name)
	if tl.text_uid != 0 {
		if n := node_find(d.root, tl.text_uid); n != nil {
			n.font = cur_font
			doc_changed(d)
		}
		return
	}
	pushed := false
	for n in sel_nodes(d) {
		if n.kind != .Text do continue
		if !pushed {
			style_push(d)
			pushed = true
		}
		n.font = cur_font
	}
	if pushed do doc_changed(d)
}

// Size of new text and of the text being edited.
text_size_set :: proc(size: f32) {
	cur_text_size = size
	if tl.text_uid != 0 {
		if n := node_find(doc.root, tl.text_uid); n != nil {
			n.size = size
			doc_changed(doc)
		}
	}
}

// Text tool options: the font as a button that opens the chooser, the size as a slider.
options_text :: proc() {
	if obutton(cur_font_name(), 120, {"Font", "The font of the text you are editing, or of new text. Click to choose from the bundled and installed fonts."}, key = "font", class = "font-btn") do font_pick_open()
	sz := int(cur_text_size + 0.5)
	if oslider("Size", 100, &sz, 1, 1000, {"Text size", "The size of the text you are editing, or of new text, in pixels. Drag, or use the mouse wheel. Shift steps through round values."}, "px", 2) do text_size_set(f32(sz))
	ohint(tl.text_uid != 0 ? "Type to edit. Ctrl+Enter or a click outside finishes. Drag the text to move it" : "Click to place text, click a text object to edit it, drag one to move it")
}

// Font chooser dialog --------------------------------------------------------------------------------------

font_filter: Name
font_scroll: i32

font_pick_open :: proc() {
	fonts_scan()
	dialog_open(.Font)
	// open on the current font
	ROW :: 16
	for f, i in ufonts {
		if f.name == cur_font_name() do font_scroll = max(i32(i) * ROW - 100, 0)
	}
	font_filter = {}
}

dlg_font :: proc() {
	fonts_scan()
	c := dialog_frame("Choose Font", 320, 330)
	tip_text(c.x, c.y + 3, "Search", C_TEXT, {"Search fonts", "Type part of a font's name to narrow the list."})
	text_field({c.x + 50, c.y, c.w - 50, 14}, &font_filter, {"Search fonts", "Type part of a font's name to narrow the list."})
	list := Rect{c.x, c.y + 22, c.w, c.h - 22 - 24}
	ctl_well(list)
	tip_area(list, "font-list", {"Fonts", "The bundled fonts and every font installed on this computer. Click one to use it."})
	ROW :: 16
	flt := strings.to_lower(name_str(&font_filter), context.temp_allocator)
	idx := make([dynamic]int, context.temp_allocator)
	for f, i in ufonts {
		if flt == "" || strings.contains(strings.to_lower(f.name, context.temp_allocator), flt) do append(&idx, i)
	}
	if ui_hover(list) && ui.wheel != 0 do font_scroll -= i32(ui.wheel) * ROW * 3
	inner := rect_inset(list, 1)
	font_scroll = clamp(font_scroll, 0, max(i32(len(idx)) * ROW - inner.h, 0))
	cur := cur_font_name()
	clip_begin(inner)
	chosen := -1
	for k, row in idx {
		f := ufonts[k]
		ry := inner.y + i32(row) * ROW - font_scroll
		if ry + ROW < inner.y || ry > inner.y + inner.h do continue
		rr := Rect{inner.x, ry, inner.w, ROW}
		hover := ui_hover(rr) && ui_hover(list)
		if hover do tip_area(rr, "font-row", {f.name, "Click to use this font."})
		if f.name == cur {
			fill_rect(rr, C_ACCENT_TINT)
		} else if hover {
			fill_rect(rr, Color{255, 255, 255, 14})
		}
		text(rr.x + 8, rr.y + (ROW - FONT_CAP) / 2, f.name, f.name == cur ? C_ACCENT : C_TEXT)
		if hover && ui.pressed[0] do chosen = k
	}
	clip_end()
	if len(idx) == 0 do text(list.x + 8, list.y + 8, "No matching fonts", C_TEXT_DIM)
	if chosen >= 0 {
		text_font_set(ufonts[chosen].name)
		dialog_close()
		return
	}
	if button_primary({c.x + c.w - 64, c.y + c.h - 18, 64, 18}, "Close", {"Close", "Close this list and keep the current font (Esc)."}) || (IsKeyPressed(.ESCAPE) && ui.focus_id == 0) {
		dialog_close()
	}
}
