package pangolin

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

tool_text :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if over do ui.cursor = .IBEAM
	if !pressed do return
	hit := pick_node(d, p, true)
	if hit != nil && hit.kind == .Text {
		text_begin(d, hit, false)
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
