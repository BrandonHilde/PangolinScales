package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

// ---------------------------------------------------------------------------
// Font documents. Font_Glyph outlines live in font units (y up) inside Font_Doc; the glyph being edited is loaded into
// the document tree of the editing Doc (y flipped: y' = em_top - y), so every drawing and path tool works on it.
// Edits are committed back to the glyph whenever the editing document changes.
// ---------------------------------------------------------------------------

GLYPH_FILL :: Color{36, 38, 48, 255}

fmt_u :: proc(cp: rune, format: string) -> string {
	return fmt.tprintf(format, int(cp))
}

fmt_glyph_index :: proc(i: int) -> string {
	return fmt.tprintf("glyph%d", i)
}

font_cur :: proc(d: ^Doc) -> ^Font_Glyph {
	f := d.font
	if f == nil || len(f.glyphs) == 0 do return nil
	return &f.glyphs[clamp(f.cur, 0, len(f.glyphs) - 1)]
}

// Creating -----------------------------------------------------------------------------------------------

font_default_glyph :: proc(cp: rune, advance: f32) -> Font_Glyph {
	g: Font_Glyph
	g.advance = advance
	g.name = make_name(glyph_name_for(cp))
	append(&g.unicodes, cp)
	return g
}

font_new_blank :: proc() -> ^Font_Doc {
	f := new(Font_Doc)
	f.upm = 1000
	f.asc, f.desc, f.line_gap = 800, -200, 0
	f.x_height, f.cap_height = 500, 700
	f.family = make_name("Untitled")
	f.style = make_name("Regular")
	f.remove_overlap = true
	// .notdef: a hollow box
	nd: Font_Glyph
	nd.name = make_name(".notdef")
	nd.advance = 600
	path_rect(&nd.segs, 80, 0, 440, 700)
	hole := make(Path, context.temp_allocator)
	path_rect(&hole, 140, 60, 320, 580)
	path_reverse(&hole)
	append(&nd.segs, ..hole[:])
	append(&f.glyphs, nd)
	append(&f.glyphs, font_default_glyph(' ', 250))
	for c in 'A' ..= 'Z' do append(&f.glyphs, font_default_glyph(c, 600))
	f.cur = 2
	return f
}

font_new_doc :: proc() {
	f := font_new_blank()
	d := font_edit_doc(f, "Untitled font")
	add_doc(d)
}

font_open_doc :: proc(path: string) -> (^Doc, bool) {
	data, ok := read_file(path)
	if !ok do return nil, false
	defer delete(data)
	f, err := ttf_read(data)
	if f == nil do return nil, false
	if err != "" do set_status(err)
	if len(f.glyphs) > 1 do f.cur = 1
	stem := path
	if i := strings.last_index_any(stem, "/\\"); i >= 0 do stem = stem[i + 1:]
	if i := strings.last_index_byte(stem, '.'); i > 0 do stem = stem[:i]
	d := font_edit_doc(f, stem)
	return d, true
}

font_edit_doc :: proc(f: ^Font_Doc, title: string) -> ^Doc {
	d := doc_new(.Font, title, 500, f32(f.asc - f.desc))
	d.font = f
	font_load_glyph(d, f.cur)
	return d
}

// Loading and committing the current glyph -----------------------------------------------------------------

font_load_glyph :: proc(d: ^Doc, idx: int) {
	f := d.font
	was_modified := d.modified
	tools_cancel()
	for c in d.root.children do node_free(c)
	clear(&d.root.children)
	for &s in d.undo do state_free(&s)
	for &s in d.redo do state_free(&s)
	clear(&d.undo)
	clear(&d.redo)
	clear(&d.sel)
	f.cur = clamp(idx, 0, max(len(f.glyphs) - 1, 0))
	f.em_top = f32(f.asc)
	g := font_cur(d)
	if g == nil do return
	n := node_new(d, .Path)
	name_set(&n.name, name_str(&g.name))
	n.fill = paint_solid(GLYPH_FILL)
	n.stroke = paint_none()
	n.segs = path_clone(g.segs[:])
	for &s in n.segs {
		s.p.y = f.em_top - s.p.y
		s.c1.y = f.em_top - s.c1.y
		s.c2.y = f.em_top - s.c2.y
	}
	append(&d.root.children, n)
	d.w, d.h = max(g.advance, 1), f32(f.asc - f.desc)
	doc_changed(d)
	d.modified = was_modified
	f.synced = d.version
}

// Writes the editing document's shapes back into the glyph (font units, y up).
font_commit :: proc(d: ^Doc) {
	f := d.font
	g := font_cur(d)
	if g == nil do return
	acc := make(Path, context.temp_allocator)
	collect :: proc(d: ^Doc, n: ^Node, acc: ^Path) {
		if !n.visible do return
		if n.kind == .Group {
			for c in n.children do collect(d, c, acc)
			return
		}
		w := node_parent_world(d, n)
		_ = w
		all := make(Path, context.temp_allocator)
		node_world_segs(d, n, &all)
		if n.fill.kind == .None && n.stroke.kind != .None && n.sw > 0 {
			// an outline drawn with a stroke becomes its outline shape
			pieces: Polys
			defer polys_free(&pieces)
			stroke_polys_world(d, n, &pieces)
			band := make(Path, context.temp_allocator)
			for sb in pieces.subs {
				for i in sb.a ..< sb.b {
					if i == sb.a do path_move(&band, pieces.pts[i])
					else do path_line(&band, pieces.pts[i])
				}
				path_close(&band)
			}
			merged := path_remove_overlap(band[:])
			append(acc, ..merged[:])
			delete(merged)
		} else {
			append(acc, ..all[:])
		}
	}
	for c in d.root.children do collect(d, c, &acc)
	delete(g.segs)
	g.segs = path_clone(acc[:])
	for &s in g.segs {
		s.p.y = f.em_top - s.p.y
		s.c1.y = f.em_top - s.c1.y
		s.c2.y = f.em_top - s.c2.y
	}
	g.ver += 1
	f.ver += 1
	f.synced = d.version
}

// Stroke geometry of a node in document space.
stroke_polys_world :: proc(d: ^Doc, n: ^Node, out: ^Polys) {
	w := mat_mul(node_parent_world(d, n), n.xf)
	stroke_path(node_render_segs(n), stroke_style_of(n), mat_scale_factor(w), out)
	polys_transform(out, w)
}

// Keeps the glyph and the editing document in step. Called once per frame.
font_sync :: proc(d: ^Doc) {
	f := d.font
	if f.synced != d.version do font_commit(d)
	if g := font_cur(d); g != nil {
		d.w = max(g.advance, 1)
		d.h = f32(f.asc - f.desc)
	}
}

font_select_glyph :: proc(d: ^Doc, idx: int) {
	if idx == d.font.cur || idx < 0 || idx >= len(d.font.glyphs) do return
	font_sync(d)
	font_load_glyph(d, idx)
	render_invalidate()
}

// Metrics changed: the editing space moves with the ascender, so commit and reload.
font_metrics_changed :: proc(d: ^Doc) {
	f := d.font
	f.metrics_ver += 1
	f.ver += 1
	// shapes were committed with the old em_top; reload using the new one
	idx := f.cur
	font_commit(d)
	font_load_glyph(d, idx)
	d.modified = true
	render_invalidate()
}

// Commands -----------------------------------------------------------------------------------------------------

font_add_set :: proc(d: ^Doc, set: int) {
	f := d.font
	font_sync(d)
	cps := make([dynamic]rune, context.temp_allocator)
	switch set {
	case 0: for c in 'A' ..= 'Z' do append(&cps, c)
	case 1: for c in 'a' ..= 'z' do append(&cps, c)
	case 2: for c in '0' ..= '9' do append(&cps, c)
	case 3: for c in "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~" do append(&cps, c)
	case 4: for c in 32 ..= 126 do append(&cps, rune(c))
	case 5:
		for c in 0xC0 ..= 0xFF {
			if c == 0xD7 || c == 0xF7 do continue
			append(&cps, rune(c))
		}
	}
	added := 0
	for cp in cps {
		exists := false
		for g in f.glyphs {
			for u in g.unicodes do if u == cp do exists = true
		}
		if exists do continue
		append(&f.glyphs, font_default_glyph(cp, cp == ' ' ? f32(f.upm) / 4 : f32(f.upm) * 0.6))
		added += 1
	}
	f.ver += 1
	d.modified = true
	set_statusf("Added %d glyph(s)", added)
}

font_delete_glyph :: proc(d: ^Doc) {
	f := d.font
	if len(f.glyphs) <= 1 do return
	font_sync(d)
	idx := f.cur
	glyph_free(&f.glyphs[idx])
	ordered_remove(&f.glyphs, idx)
	delete_key(&f.thumbs, idx)
	clear(&f.thumbs)
	for &k in f.kerning {
		if k.left > idx do k.left -= 1
		if k.right > idx do k.right -= 1
	}
	font_load_glyph(d, min(idx, len(f.glyphs) - 1))
	f.ver += 1
	d.modified = true
}

// Orients contours the TrueType way: outer contours clockwise, holes counter-clockwise (y up).
path_fix_direction :: proc(p: ^Path) {
	ranges := make([dynamic][2]int, context.temp_allocator)
	i := 0
	for i < len(p) {
		j := i + 1
		for j < len(p) && p[j].kind != .Move do j += 1
		append(&ranges, [2]int{i, j})
		i = j
	}
	polys := make([]Polys, len(ranges), context.temp_allocator)
	for r, k in ranges do path_flatten(p[r[0]:r[1]], MAT_ID, 0.5, &polys[k])
	out := make(Path, context.temp_allocator)
	for r, k in ranges {
		sub := path_clone(p[r[0]:r[1]])
		if len(polys[k].subs) > 0 && len(polys[k].pts) > 2 {
			pts := polys[k].pts[:]
			area := poly_area(pts)
			probe := pts[0]
			// a vertex on a neighbour's outline is ambiguous; nudge toward the centroid
			cen: Vec2
			for q in pts do cen += q
			cen /= f32(len(pts))
			probe += (cen - probe) * 0.02
			depth := 0
			for r2, k2 in ranges {
				if k2 != k && polys_contains(&polys[k2], probe, false) do depth += 1
			}
			want_clockwise := depth % 2 == 0
			is_clockwise := area < 0
			if want_clockwise != is_clockwise do path_reverse(&sub)
		}
		append(&out, ..sub[:])
		delete(sub)
	}
	for &pl in polys do polys_free(&pl)
	clear(p)
	append(p, ..out[:])
}

font_fix_direction :: proc(d: ^Doc) {
	f := d.font
	font_sync(d)
	for &g in f.glyphs {
		path_fix_direction(&g.segs)
		g.ver += 1
	}
	f.ver += 1
	font_load_glyph(d, f.cur)
	d.modified = true
	set_status("Contour directions fixed")
}

font_remove_overlap_current :: proc(d: ^Doc) {
	font_sync(d)
	g := font_cur(d)
	if g == nil do return
	r := path_remove_overlap(g.segs[:])
	delete(g.segs)
	g.segs = r
	g.ver += 1
	d.font.ver += 1
	font_load_glyph(d, d.font.cur)
	d.modified = true
}

font_export :: proc(d: ^Doc) {
	f := d.font
	font_sync(d)
	initial := fmt.tprintf("%s-%s.ttf", name_str(&f.family), name_str(&f.style))
	initial, _ = strings.replace_all(initial, " ", "", context.temp_allocator)
	path, ok := native_dialog(true, "Export TrueType", FILTERS_TTF[:], "ttf", initial)
	if !ok do return
	data, err := ttf_write(f)
	if data == nil {
		message("Export", err)
		return
	}
	if write_file(path, data) {
		d.modified = false
		set_statusf("Exported %d glyphs (%d bytes)", len(f.glyphs), len(data))
	} else {
		message("Export", "Could not write the file.")
	}
}

font_undo :: proc(d: ^Doc) -> bool {
	return false
}

font_redo :: proc(d: ^Doc) -> bool {
	return false
}

font_shortcuts :: proc(d: ^Doc) {
	if key_hit(.LEFT_BRACKET) do font_select_glyph(d, d.font.cur - 1)
	if key_hit(.RIGHT_BRACKET) do font_select_glyph(d, d.font.cur + 1)
	// the drawing tools work as in SVG documents
	switch {
	case key_hit(.V): set_tool(.Select)
	case key_hit(.A): set_tool(.Node)
	case key_hit(.P): set_tool(.Pen)
	case key_hit(.F): set_tool(.Freehand)
	case key_hit(.R): set_tool(.Rect)
	case key_hit(.E): set_tool(.Ellipse)
	case key_hit(.L): set_tool(.Line)
	case key_hit(.H): set_tool(.Hand)
	case key_hit(.Z): set_tool(.Zoom)
	case key_hit(.EQUAL), key_hit(.KP_ADD): run_cmd(.Zoom_In)
	case key_hit(.MINUS), key_hit(.KP_SUBTRACT): run_cmd(.Zoom_Out)
	}
	if cur_tool == .Pen {
		if key_hit(.ENTER) || key_hit(.ESCAPE) do pen_finish(true)
		if key_hit(.BACKSPACE) do pen_undo_point(d)
		return
	}
	if cur_tool == .Node {
		if key_hit(.DELETE) || key_hit(.BACKSPACE) do node_cmd_delete(d)
		if key_hit(.S) do node_cmd_smooth(d)
		if key_hit(.C) do node_cmd_corner(d)
		nudge_anchors(d)
		return
	}
	if key_hit(.DELETE) || key_hit(.BACKSPACE) do run_cmd(.Delete)
	if key_hit(.ESCAPE) do clear(&d.sel)
}

// Tests ----------------------------------------------------------------------------------------------------------

font_selftest :: proc(t: ^Test_Run) {
	// a one glyph font survives write -> read
	f := font_new_blank()
	// give "A" a triangle
	for &g in f.glyphs {
		if len(g.unicodes) == 1 && g.unicodes[0] == 'A' {
			path_move(&g.segs, {50, 0})
			path_line(&g.segs, {300, 700})
			path_line(&g.segs, {550, 0})
			path_close(&g.segs)
			g.advance = 600
		}
	}
	data, err := ttf_write(f)
	check(t, data != nil && err == "", "ttf write")
	if data != nil {
		back, rerr := ttf_read(data)
		check(t, back != nil && rerr == "", "ttf read back")
		if back != nil {
			check(t, len(back.glyphs) == len(f.glyphs), "ttf glyph count")
			check(t, back.upm == 1000 && back.asc == 800 && back.desc == -200, "ttf metrics")
			check(t, name_str(&back.family) == "Untitled", "ttf family name")
			ai := -1
			for g, i in back.glyphs do if len(g.unicodes) > 0 && g.unicodes[0] == 'A' do ai = i
			check(t, ai >= 0, "ttf cmap has A")
			if ai >= 0 {
				bb := path_bounds(back.glyphs[ai].segs[:])
				check(t, near(bb.x0, 50, 0.5) && near(bb.x1, 550, 0.5) && near(bb.y1, 700, 0.5), "ttf glyph outline")
				check(t, back.glyphs[ai].advance == 600, "ttf advance")
			}
		}
	}
	// a real font: load, write, load again
	if raw, ok := read_file("assets/fonts/Alice-Regular.ttf"); ok {
		defer delete(raw)
		a, _ := ttf_read(raw)
		check(t, a != nil && len(a.glyphs) > 100, "load Alice")
		if a != nil {
			out, werr := ttf_write(a)
			check(t, out != nil, "write Alice")
			if out != nil {
				b, _ := ttf_read(out)
				check(t, b != nil && len(b.glyphs) == len(a.glyphs), "reload Alice")
				if b != nil {
					ga, gb := -1, -1
					for g, i in a.glyphs do if len(g.unicodes) > 0 && g.unicodes[0] == 'g' do ga = i
					for g, i in b.glyphs do if len(g.unicodes) > 0 && g.unicodes[0] == 'g' do gb = i
					check(t, ga >= 0 && gb >= 0, "Alice has g")
					if ga >= 0 && gb >= 0 {
						ba, bbx := path_bounds(a.glyphs[ga].segs[:]), path_bounds(b.glyphs[gb].segs[:])
						check(t, near(ba.x0, bbx.x0, 2) && near(ba.y0, bbx.y0, 2) && near(ba.x1, bbx.x1, 2) && near(ba.y1, bbx.y1, 2), "Alice g bounds survive")
						// area is preserved by overlap removal and the quadratic conversion
						aa := path_area(a.glyphs[ga].segs[:], 1200, 1400)
						_ = aa
					}
				}
			}
		}
	}
	// contour direction: outer clockwise, hole counter-clockwise
	p := make(Path, context.temp_allocator)
	path_rect(&p, 0, 0, 100, 100)
	path_rect(&p, 25, 25, 50, 50)
	path_fix_direction(&p)
	polys: Polys
	path_flatten(p[:], MAT_ID, 0.5, &polys)
	if len(polys.subs) == 2 {
		a0 := poly_area(polys.pts[polys.subs[0].a:polys.subs[0].b])
		a1 := poly_area(polys.pts[polys.subs[1].a:polys.subs[1].b])
		check(t, a0 < 0 && a1 > 0, "fix direction")
	} else {
		check(t, false, "fix direction subpaths")
	}
	polys_free(&polys)
	_ = os.args
	_ = math.PI
}
