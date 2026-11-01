package pangolin

import "core:fmt"
import "core:strconv"
import "core:strings"

import oui "odinui:odinui"

// ---------------------------------------------------------------------------
// Font mode user interface: the glyph editing viewport with metric guides, and the glyph / metrics panel.
// ---------------------------------------------------------------------------

Thumb :: struct {
	tex:       Texture,
	ver, mver: int,
	scale:     i32,
}

font_viewport :: proc(vp: Rect) {
	d := doc
	font_sync(d)
	viewport_update(vp)
	render_viewport(d, vp)
	trace_draw(d, vp)
	font_guides(d, vp)
	overlay_draw(vp)
}

Guide :: struct {
	name: string,
	y:    int,
	col:  Color,
}

font_guides :: proc(d: ^Doc, vp: Rect) {
	f := d.font
	g := font_cur(d)
	if g == nil do return
	clip_begin(vp)
	defer clip_end()
	guides := [?]Guide {
		{"ascender", f.asc, Color{90, 150, 230, 255}},
		{"cap height", f.cap_height, Color{150, 120, 220, 255}},
		{"x-height", f.x_height, Color{110, 190, 150, 255}},
		{"baseline", 0, Color{240, 130, 90, 255}},
		{"descender", f.desc, Color{90, 150, 230, 255}},
	}
	for gd in guides {
		sy := to_screen(d, {0, f.em_top - f32(gd.y)}).y
		c := gd.col
		c.a = gd.name == "baseline" ? 170 : 90
		draw_rect(f32(vp.x), sy, f32(vp.w), 1, c)
		text(vp.x + 6, i32(sy) - FONT_CAP - 3, gd.name, Color{gd.col.r, gd.col.g, gd.col.b, 200})
	}
	// side bearings: the origin and the advance width
	x0 := to_screen(d, {0, 0}).x
	x1 := to_screen(d, {g.advance, 0}).x
	draw_rect(x0, f32(vp.y), 1, f32(vp.h), Color{240, 130, 90, 120})
	draw_rect(x1, f32(vp.y), 1, f32(vp.h), Color{240, 130, 90, 120})
	text(i32(x1) + 4, vp.y + 6, fmt.tprintf("advance %d", int(g.advance)), Color{240, 130, 90, 220})
	// the glyph's own name and codepoint
	label := name_str(&g.name)
	if len(g.unicodes) > 0 do label = fmt.tprintf("%s  U+%04X", label, int(g.unicodes[0]))
	text(vp.x + vp.w - text_w(label) - 8, vp.y + 6, label, C_TEXT_DIM)
}

// Font_Glyph thumbnails -------------------------------------------------------------------------------------------

glyph_thumb :: proc(f: ^Font_Doc, idx, cell: i32) -> Texture {
	th, ok := f.thumbs[int(idx)]
	if ok && th.ver == f.glyphs[idx].ver && th.mver == f.metrics_ver && th.scale == ui.scale && tex_valid(th.tex) do return th.tex
	if ok do tex_destroy(&th.tex)
	s := int(cell * ui.scale)
	pix := make([]Color, s * s, context.temp_allocator)
	r: Raster
	raster_init(&r, s, s)
	defer raster_free(&r)
	em := f32(f.asc - f.desc)
	k := f32(s) * 0.72 / max(em, 1)
	g := &f.glyphs[idx]
	ox := (f32(s) - g.advance * k) / 2
	by := f32(s) * 0.12 + f32(f.asc) * k
	paint := paint_solid(Color{222, 226, 236, 255})
	draw_segs(&r, pix, g.segs[:], Mat{k, 0, 0, -k, ox, by}, &paint, .Non_Zero, 1)
	tex := tex_create(s, s, .Linear)
	tex_update(tex, pix)
	f.thumbs[int(idx)] = Thumb{tex, g.ver, f.metrics_ver, ui.scale}
	return tex
}

glyph_matches :: proc(g: ^Font_Glyph, filter: string) -> bool {
	if filter == "" do return true
	low := strings.to_lower(filter, context.temp_allocator)
	if strings.contains(strings.to_lower(name_str(&g.name), context.temp_allocator), low) do return true
	for u in g.unicodes {
		if strings.contains(strings.to_lower(fmt.tprintf("%04x", int(u)), context.temp_allocator), low) do return true
		if len(filter) <= 4 && fmt.tprintf("%c", u) == filter do return true
	}
	return false
}

// Panel ----------------------------------------------------------------------------------------------------------------

font_prop_scroll: i32
uni_buf: Name

panel_right_font :: proc() {
	d := doc
	f := d.font
	oui.element(uictx, "right", "sidepanel", {id = "right"})
	defer oui.end(uictx)
	osection("glyphs-head", "Glyphs")
	oui_slot("glyph-grid", "glyph_grid")
	oui.element(uictx, "glyph-buttons", "row", {id = "glyph-buttons"})
	if obutton("Add...", 56, "Add a set of glyphs") do run_cmd(.Font_Add_Glyphs)
	if obutton("Delete", 56, "Delete the current glyph") do font_delete_glyph(d)
	oui.element_leaf(uictx, "spacer", "spacer")
	otext("count", fmt.tprintf("%d glyphs", len(f.glyphs)), "dim")
	oui.end(uictx)
	osection("font-head", "Glyph and font")
	oui_slot("font-props", "font_props")
}

panel_glyph_grid :: proc(d: ^Doc, area: Rect) {
	ui.layer = 0
	f := d.font
	r := area
	bar := cut_top(&r, 20)
	fr := Rect{bar.x, bar.y + 2, bar.w, 14}
	text_field(fr, &f.filter, "Filter by name, character or hex code")
	if f.filter.n == 0 && ui.focus_id != make_id(fr, "text") {
		text(fr.x + 6, fr.y + 3, "filter...", C_TEXT_OFF)
	}
	ctl_well(r)

	CELL :: 40
	GAP :: 2
	cols := max(int(r.w - 8) / (CELL + GAP), 1)
	idx := make([dynamic]int, context.temp_allocator)
	filter := name_str(&f.filter)
	for i in 0 ..< len(f.glyphs) {
		if glyph_matches(&f.glyphs[i], filter) do append(&idx, i)
	}
	rows := (len(idx) + cols - 1) / cols
	visible := int(r.h) / (CELL + GAP)
	if ui_hover(r) && ui.wheel != 0 && ui.focus_id == 0 do f.grid_scroll -= int(ui.wheel)
	// keep the current glyph in view when it changes through the keyboard
	f.grid_scroll = clamp(f.grid_scroll, 0, max(rows - visible, 0))
	clip_begin(r)
	defer clip_end()
	for row in f.grid_scroll ..< min(f.grid_scroll + visible + 1, rows) {
		for c in 0 ..< cols {
			k := row * cols + c
			if k >= len(idx) do break
			gi := idx[k]
			cr := Rect{r.x + 4 + i32(c) * (CELL + GAP), r.y + 2 + i32(row - f.grid_scroll) * (CELL + GAP), CELL, CELL}
			cur := gi == f.cur
			hover := ui_hover(cr)
			draw_rrect(f32(cr.x), f32(cr.y), CELL, CELL, RADIUS, cur ? Color{80, 56, 40, 255} : (hover ? C_HOVER : C_PANEL_DK))
			if cur do draw_rrect_outline(f32(cr.x), f32(cr.y), CELL, CELL, RADIUS, C_ACCENT)
			tex := glyph_thumb(f, i32(gi), CELL)
			draw_tex(tex, {0, 0, f32(tex.w), f32(tex.h)}, {f32(cr.x), f32(cr.y), CELL, CELL})
			g := &f.glyphs[gi]
			if len(g.unicodes) > 0 && g.unicodes[0] > 32 && g.unicodes[0] < 0x250 {
				text(cr.x + 3, cr.y + 2, fmt.tprintf("%c", g.unicodes[0]), C_TEXT_DIM)
			}
			if hover {
				tooltip_hover(make_id(cr, "glyph"), fmt.tprintf("%s", name_str(&g.name)))
				if ui.pressed[0] do font_select_glyph(d, gi)
			}
		}
	}
}

font_row_int :: proc(x, w: i32, y: i32, name: string, v: ^int, lo, hi: int) -> bool {
	text(x, y + 3, name, C_TEXT_DIM)
	return field_int(Rect{x + 96, y, w - 96, 14}, v, lo, hi)
}

panel_font_props :: proc(d: ^Doc, r: Rect) {
	ui.layer = 0
	f := d.font
	g := font_cur(d)
	clip_begin(r)
	defer clip_end()
	if ui_hover(r) && ui.wheel != 0 && ui.focus_id == 0 && !popup.open do font_prop_scroll = max(font_prop_scroll - i32(ui.wheel * 24), 0)
	x := r.x + 8
	w := r.w - 16
	y := r.y + 6 - font_prop_scroll
	if g != nil {
		text(x, y + 3, "Name", C_TEXT_DIM)
		if ch, _ := text_field(Rect{x + 50, y, w - 50, 14}, &g.name, "Glyph name"); ch {
			f.ver += 1
			d.modified = true
		}
		y += 20
		// unicode as hex
		hr := Rect{x + 50, y, 80, 14}
		text(x, y + 3, "Unicode", C_TEXT_DIM)
		if ui.focus_id != make_id(hr, "text") {
			name_set(&uni_buf, len(g.unicodes) > 0 ? fmt.tprintf("%04X", int(g.unicodes[0])) : "")
		}
		if ch, _ := text_field(hr, &uni_buf, "Hex code point, e.g. 0041"); ch {
			if v, ok := strconv.parse_int(name_str(&uni_buf), 16); ok && v >= 0 && v <= 0x10ffff {
				if len(g.unicodes) > 0 do g.unicodes[0] = rune(v)
				else do append(&g.unicodes, rune(v))
				d.modified = true
				f.ver += 1
			} else if uni_buf.n == 0 {
				clear(&g.unicodes)
			}
		}
		y += 20
		adv := int(g.advance)
		if font_row_int(x, w, y, "Advance width", &adv, 0, 20000) {
			g.advance = f32(adv)
			g.ver += 1
			f.ver += 1
			d.modified = true
			render_invalidate()
		}
		y += 20
		b := path_bounds(g.segs[:])
		if !bounds_empty(b) {
			text(x, y + 3, fmt.tprintf("Bounds %d, %d  to  %d, %d", int(b.x0), int(b.y0), int(b.x1), int(b.y1)), C_TEXT_DIM)
			y += 16
		}
		half := (w - 4) / 2
		if button(Rect{x, y, half, 16}, "Fix direction", "Orient all contours the TrueType way") do font_fix_direction(d)
		if button(Rect{x + half + 4, y, half, 16}, "Remove overlap", "Merge overlapping contours of this glyph") do font_remove_overlap_current(d)
		y += 22
		if button(Rect{x, y, half, 16}, "Center glyph", "Center the outline in its advance width") {
			font_sync(d)
			bb := path_bounds(g.segs[:])
			if !bounds_empty(bb) {
				dx := (g.advance - (bb.x1 - bb.x0)) / 2 - bb.x0
				for &s in g.segs {
					s.p.x += dx
					s.c1.x += dx
					s.c2.x += dx
				}
				g.ver += 1
				f.ver += 1
				font_load_glyph(d, f.cur)
				d.modified = true
			}
		}
		if button(Rect{x + half + 4, y, half, 16}, "Fit advance", "Set the advance width to outline width + bearings") {
			font_sync(d)
			bb := path_bounds(g.segs[:])
			if !bounds_empty(bb) {
				lsb := max(bb.x0, 0)
				g.advance = bb.x1 + lsb
				g.ver += 1
				f.ver += 1
				font_load_glyph(d, f.cur)
				d.modified = true
			}
		}
		y += 26
	}

	// metrics
	text(x, y + 2, "Metrics", C_TEXT_DIM)
	hline(x + 46, y + 7, w - 46, C_BORDER)
	y += 16
	changed := false
	text(x, y + 3, "Units per em", C_TEXT_DIM)
	text(x + 96, y + 3, fmt.tprintf("%d", f.upm), C_TEXT)
	y += 18
	changed |= font_row_int(x, w, y, "Ascender", &f.asc, 0, 20000)
	y += 18
	changed |= font_row_int(x, w, y, "Descender", &f.desc, -20000, 0)
	y += 18
	changed |= font_row_int(x, w, y, "Cap height", &f.cap_height, 0, 20000)
	y += 18
	changed |= font_row_int(x, w, y, "x-height", &f.x_height, 0, 20000)
	y += 18
	if font_row_int(x, w, y, "Line gap", &f.line_gap, 0, 20000) do d.modified = true
	y += 22
	if changed do font_metrics_changed(d)

	// names
	text(x, y + 2, "Font", C_TEXT_DIM)
	hline(x + 28, y + 7, w - 28, C_BORDER)
	y += 16
	text(x, y + 3, "Family", C_TEXT_DIM)
	if ch, _ := text_field(Rect{x + 50, y, w - 50, 14}, &f.family, "Family name"); ch do d.modified = true
	y += 20
	text(x, y + 3, "Style", C_TEXT_DIM)
	if ch, _ := text_field(Rect{x + 50, y, w - 50, 14}, &f.style, "Style name, e.g. Regular"); ch do d.modified = true
	y += 20
	checkbox(x, y, "Remove overlaps on export", &f.remove_overlap)
	y += 20
	if button_primary(Rect{x, y, w, 18}, "Export TrueType...") do font_export(d)
	y += 28

	// preview
	text(x, y + 2, "Preview", C_TEXT_DIM)
	hline(x + 46, y + 7, w - 46, C_BORDER)
	y += 16
	if f.preview.n == 0 && ui.focus_id == 0 do name_set(&f.preview, "Hamburgefonstiv 0123")
	text_field(Rect{x, y, w, 14}, &f.preview, "Text to preview with this font")
	y += 20
	font_preview(f, Rect{x, y, w, 48})
	y += 56

	content := y + font_prop_scroll - r.y
	font_prop_scroll = clamp(font_prop_scroll, 0, max(content - r.h + 8, 0))
}

// Text set in the font being edited (committed outlines).
font_preview :: proc(f: ^Font_Doc, r: Rect) {
	fill_rect(r, C_PANEL_DK)
	outline_rect(r, C_RING)
	pw, ph := int(r.w * ui.scale), int(r.h * ui.scale)
	str := name_str(&f.preview)
	h := 0
	for ch in str do h = h * 31 + int(ch)
	key := [3]int{f.ver, int(ui.scale), h + pw}
	if f.prev_key != key || !tex_valid(f.prev_tex) {
		tex_destroy(&f.prev_tex)
		pix := make([]Color, pw * ph, context.temp_allocator)
		rs: Raster
		raster_init(&rs, pw, ph)
		em := f32(f.asc - f.desc)
		k := f32(ph) * 0.62 / max(em, 1)
		x := f32(6 * ui.scale)
		by := f32(ph) * 0.14 + f32(f.asc) * k
		paint := paint_solid(Color{230, 232, 240, 255})
		for ch in str {
			gi := -1
			for g, i in f.glyphs {
				for u in g.unicodes do if u == ch {
					gi = i
					break
				}
				if gi >= 0 do break
			}
			if gi < 0 {
				x += f32(f.upm) * 0.4 * k
				continue
			}
			g := &f.glyphs[gi]
			draw_segs(&rs, pix, g.segs[:], Mat{k, 0, 0, -k, x, by}, &paint, .Non_Zero, 1)
			x += g.advance * k
			if x > f32(pw) do break
		}
		raster_free(&rs)
		f.prev_tex = tex_create(pw, ph, .Linear)
		tex_update(f.prev_tex, pix)
		f.prev_key = key
	}
	draw_tex(f.prev_tex, {0, 0, f32(pw), f32(ph)}, {f32(r.x), f32(r.y), f32(r.w), f32(r.h)})
}
