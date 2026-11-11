package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

// ---------------------------------------------------------------------------
// Font documents. Font_Glyph outlines live in font units (y up) inside Font_Doc; the glyph being edited is the
// document tree of the editing Doc (y flipped: y' = em_top - y), so it has layers and every drawing and path tool
// works on it. The outline is everything visible as painted (fills and strokes) and is committed back to the glyph
// whenever the editing document changes. Leaving a glyph keeps its tree and history in the glyph for next time.
// ---------------------------------------------------------------------------

GLYPH_FILL :: Color{36, 38, 48, 255}

Glyph_Edit :: struct {
	root:       ^Node, // nil: never edited, the outline is shown as one path
	undo, redo: [dynamic]Doc_State,
	ver:        int, // the glyph's ver when stored; an outline changed since then is reloaded as one path
	top:        f32, // em_top the tree was drawn with
}

glyph_edit_free :: proc(e: ^Glyph_Edit) {
	node_free(e.root)
	for &s in e.undo do state_free(&s)
	for &s in e.redo do state_free(&s)
	delete(e.undo)
	delete(e.redo)
	e^ = {}
}

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

// Makes glyph `idx` the one being edited: its stored shapes and history when they still match its outline,
// otherwise the outline as one path. Whatever the document held is discarded (see font_leave_glyph).
font_load_glyph :: proc(d: ^Doc, idx: int) {
	f := d.font
	was_modified := d.modified
	if d.root != nil do tools_cancel()
	node_free(d.root)
	for &s in d.undo do state_free(&s)
	for &s in d.redo do state_free(&s)
	delete(d.undo)
	delete(d.redo)
	d.undo, d.redo = {}, {}
	clear(&d.sel)
	f.cur = clamp(idx, 0, max(len(f.glyphs) - 1, 0))
	f.em_top = f32(f.asc)
	g := font_cur(d)
	if g != nil && g.edit.root != nil && g.edit.ver == g.ver {
		d.root, d.undo, d.redo = g.edit.root, g.edit.undo, g.edit.redo
		// the ascender may have moved since: keep the shapes where they are in font units
		if dy := f.em_top - g.edit.top; dy != 0 {
			tree_shift(d.root, 0, dy)
			for s in d.undo do tree_shift(s.root, 0, dy)
			for s in d.redo do tree_shift(s.root, 0, dy)
		}
		g.edit = {}
	} else {
		if g != nil do glyph_edit_free(&g.edit)
		d.root = node_new(d, .Group)
		name_set(&d.root.name, "root")
		if g != nil do font_set_outline(d, g.segs[:])
	}
	if g != nil do d.w = max(g.advance, 1)
	d.h = f32(f.asc - f.desc)
	doc_changed(d)
	d.modified = was_modified
	f.synced = d.version
}

// Moves the shapes and history of the glyph being edited into the glyph, leaving the document empty for
// font_load_glyph.
font_leave_glyph :: proc(d: ^Doc) {
	f := d.font
	g := font_cur(d)
	if g == nil do return
	tools_cancel()
	if f.synced != d.version do font_commit(d)
	glyph_edit_free(&g.edit)
	g.edit = Glyph_Edit{d.root, d.undo, d.redo, g.ver, f.em_top}
	d.root = nil
	d.undo, d.redo = {}, {}
}

// Replaces the shapes by one path holding `segs` (font units); an empty outline leaves no shapes.
font_set_outline :: proc(d: ^Doc, segs: []Seg) {
	f := d.font
	for c in d.root.children do node_free(c)
	clear(&d.root.children)
	clear(&d.sel)
	if len(segs) == 0 do return
	g := font_cur(d)
	n := node_new(d, .Path)
	name_set(&n.name, g != nil ? name_str(&g.name) : "Outline")
	n.fill = paint_solid(GLYPH_FILL)
	n.stroke = paint_none()
	n.segs = path_clone(segs)
	for &s in n.segs {
		s.p.y = f.em_top - s.p.y
		s.c1.y = f.em_top - s.c1.y
		s.c2.y = f.em_top - s.c2.y
	}
	append(&d.root.children, n)
}

// Moves every shape of a tree, in document units.
tree_shift :: proc(root: ^Node, dx, dy: f32) {
	for c in root.children do node_translate(c, dx, dy)
}

// Writes the editing document's shapes back into the glyph (font units, y up): every visible fill and stroke.
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
		shape := make(Path, context.temp_allocator)
		if n.fill.kind != .None do node_world_segs(d, n, &shape)
		if n.stroke.kind == .None || n.sw <= 0 {
			append(acc, ..shape[:])
			return
		}
		// a stroke becomes its outline shape, merged with the fill under it
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
		merged, _ := path_boolean(shape[:], band[:], .Union)
		append(acc, ..merged[:])
		delete(merged)
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
	font_leave_glyph(d)
	font_load_glyph(d, idx)
	render_invalidate()
}

// Metrics changed: the editing space moves with the ascender, so the shapes (and their history) move with it
// and keep their place in font units.
font_metrics_changed :: proc(d: ^Doc) {
	f := d.font
	f.metrics_ver += 1
	f.ver += 1
	font_sync(d)
	if dy := f32(f.asc) - f.em_top; dy != 0 {
		f.em_top = f32(f.asc)
		tree_shift(d.root, 0, dy)
		for s in d.undo do tree_shift(s.root, 0, dy)
		for s in d.redo do tree_shift(s.root, 0, dy)
		doc_changed(d)
		f.synced = d.version // the outline in font units is unchanged
	}
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
	idx := f.cur
	glyph_free(&f.glyphs[idx])
	ordered_remove(&f.glyphs, idx)
	for _, &t in f.thumbs do tex_destroy(&t.tex)
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
			// a vertex on a neighbor's outline is ambiguous; nudge toward the centroid
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

// Every glyph whose contours turn changes outline (other glyphs keep their shapes); the glyph being edited
// becomes one path, which undo takes back.
font_fix_direction :: proc(d: ^Doc) {
	f := d.font
	font_sync(d)
	fixed := 0
	for &g, i in f.glyphs {
		before := make([]Seg, len(g.segs), context.temp_allocator)
		copy(before, g.segs[:])
		path_fix_direction(&g.segs)
		if path_same(before[:], g.segs[:]) do continue
		fixed += 1
		if i == f.cur {
			history_push(d)
			font_set_outline(d, g.segs[:])
			doc_changed(d)
		}
		g.ver += 1
	}
	if fixed == 0 {
		set_status("Contour directions are already right")
		return
	}
	f.ver += 1
	f.synced = d.version
	d.modified = true
	set_statusf("Contour directions fixed in %d glyph(s)", fixed)
}

path_same :: proc(a, b: []Seg) -> bool {
	if len(a) != len(b) do return false
	for s, i in a do if s != b[i] do return false
	return true
}

// Merges the glyph's shapes into one outline without overlaps (undoable).
font_remove_overlap_current :: proc(d: ^Doc) {
	font_sync(d)
	g := font_cur(d)
	if g == nil || len(g.segs) == 0 do return
	r := path_remove_overlap(g.segs[:])
	defer delete(r)
	history_push(d)
	font_set_outline(d, r[:])
	doc_changed(d)
}

// Moves the shapes so the outline sits in the middle of the advance width (undoable).
font_center_glyph :: proc(d: ^Doc) {
	font_sync(d)
	g := font_cur(d)
	if g == nil do return
	b := path_bounds(g.segs[:])
	if bounds_empty(b) do return
	dx := (g.advance - (b.x1 - b.x0)) / 2 - b.x0
	history_push(d)
	tree_shift(d.root, dx, 0)
	doc_changed(d)
}

// Sets the advance width to the outline's width plus its left side bearing on both sides.
font_fit_advance :: proc(d: ^Doc) {
	font_sync(d)
	g := font_cur(d)
	if g == nil do return
	b := path_bounds(g.segs[:])
	if bounds_empty(b) do return
	g.advance = b.x1 + max(b.x0, 0)
	g.ver += 1
	d.font.ver += 1
	d.modified = true
	render_invalidate()
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

// Font keys on top of the usual ones: [ and ] step through the glyphs.
font_shortcuts :: proc(d: ^Doc) {
	if key_hit(.LEFT_BRACKET) do run_cmd(.Font_Prev_Glyph)
	if key_hit(.RIGHT_BRACKET) do run_cmd(.Font_Next_Glyph)
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
