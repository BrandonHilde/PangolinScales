package pangolin

import "core:fmt"
import "core:math"
import "core:strings"

// Headless tests: `PangolinScales-console --selftest`. Returns the process exit code.
Test_Run :: struct {
	passed, failed: int,
}

check :: proc(t: ^Test_Run, ok: bool, what: string) {
	if ok {
		t.passed += 1
	} else {
		t.failed += 1
		fmt.println("FAIL:", what)
	}
}

near :: proc(a, b: f32, tol: f32 = 1e-3) -> bool {
	return abs(a - b) <= tol
}

// Area covered by a path when filled (sum of coverage over a raster).
path_area :: proc(segs: []Seg, w, h: int, rule := Fill_Rule.Non_Zero) -> f32 {
	r: Raster
	raster_init(&r, w, h)
	defer raster_free(&r)
	poly: Polys
	defer polys_free(&poly)
	path_flatten(segs, MAT_ID, 0.05, &poly)
	raster_fill(&r, &poly, rule)
	total: f32
	for c in r.cover do total += c
	return total
}

selftest :: proc() -> int {
	t: Test_Run

	// document basics
	d := doc_new(.Svg, "t", 100, 50)
	check(&t, d.w == 100 && d.h == 50, "doc size")
	check(&t, name_str(&d.title) == "t", "doc title")

	// matrices
	m := mat_mul(mat_translate(10, 20), mat_scale(2, 3))
	p := mat_apply(m, {1, 1})
	check(&t, near(p.x, 12) && near(p.y, 23), "mat_mul / apply")
	inv, ok := mat_inv(m)
	q := mat_apply(inv, p)
	check(&t, ok && near(q.x, 1) && near(q.y, 1), "mat_inv")

	// rasterizer: exact area of a pixel-aligned and a fractional rectangle
	rect := make(Path, context.temp_allocator)
	path_rect(&rect, 10, 10, 20, 30)
	check(&t, near(path_area(rect[:], 64, 64), 600, 0.5), "raster area aligned")
	rect2 := make(Path, context.temp_allocator)
	path_rect(&rect2, 10.5, 10.25, 20, 30)
	check(&t, near(path_area(rect2[:], 64, 64), 600, 1.0), "raster area fractional")
	circ := make(Path, context.temp_allocator)
	path_ellipse(&circ, 32, 32, 20, 20)
	check(&t, near(path_area(circ[:], 64, 64), math.PI * 400, 8), "raster circle area")
	ring := make(Path, context.temp_allocator)
	path_rect(&ring, 10, 10, 40, 40)
	path_rect(&ring, 20, 20, 20, 20)
	check(&t, near(path_area(ring[:], 64, 64, .Even_Odd), 1600 - 400, 1), "even-odd ring")
	check(&t, near(path_area(ring[:], 64, 64, .Non_Zero), 1600, 1), "non-zero ring")

	// path bounds
	b := path_bounds(circ[:])
	check(&t, near(b.x0, 12, 0.01) && near(b.x1, 52, 0.01), "ellipse bounds")

	// arcs: a half circle arc should have the right extent
	arc := make(Path, context.temp_allocator)
	path_move(&arc, {0, 0})
	path_arc(&arc, {0, 0}, 10, 10, 0, false, true, {20, 0})
	ab := path_bounds(arc[:])
	check(&t, near(ab.y0, -10, 0.05) && near(ab.x1, 20, 0.01), "arc half circle")

	// boolean operations on two overlapping 20x20 squares offset by 10
	a := make(Path, context.temp_allocator)
	bb := make(Path, context.temp_allocator)
	path_rect(&a, 10, 10, 20, 20)
	path_rect(&bb, 20, 20, 20, 20)
	u, _ := path_boolean(a[:], bb[:], .Union)
	check(&t, near(path_area(u[:], 64, 64), 700, 1), "boolean union area")
	delete(u)
	i, _ := path_boolean(a[:], bb[:], .Intersect)
	check(&t, near(path_area(i[:], 64, 64), 100, 1), "boolean intersect area")
	delete(i)
	s, _ := path_boolean(a[:], bb[:], .Subtract)
	check(&t, near(path_area(s[:], 64, 64), 300, 1), "boolean subtract area")
	delete(s)
	x, _ := path_boolean(a[:], bb[:], .Exclude)
	check(&t, near(path_area(x[:], 64, 64), 600, 1), "boolean exclude area")
	delete(x)
	// a circle with a square corner cut away keeps its curves where untouched
	hole := make(Path, context.temp_allocator)
	path_rect(&hole, 32, 32, 30, 30)
	cs, _ := path_boolean(circ[:], hole[:], .Subtract)
	check(&t, cs != nil && len(cs) > 4, "circle minus square")
	curves := 0
	for g in cs do if g.kind == .Cubic do curves += 1
	check(&t, curves >= 2, "boolean keeps curves")
	delete(cs)
	// remove overlap of a self-overlapping figure (two squares in one path)
	both := make(Path, context.temp_allocator)
	path_rect(&both, 10, 10, 20, 20)
	path_rect(&both, 20, 20, 20, 20)
	ro := path_remove_overlap(both[:])
	check(&t, near(path_area(ro[:], 64, 64), 700, 1), "remove overlap")
	delete(ro)

	// stroker: area of a stroked straight line = length * width
	line := make(Path, context.temp_allocator)
	path_move(&line, {10, 32})
	path_line(&line, {50, 32})
	sp: Polys
	stroke_path(line[:], Stroke_Style{width = 6, miter = 4}, 1, &sp)
	r: Raster
	raster_init(&r, 64, 64)
	raster_fill(&r, &sp, .Non_Zero)
	area: f32
	for c in r.cover do area += c
	check(&t, near(area, 240, 1), "stroke area butt")
	raster_free(&r)
	polys_free(&sp)

	// SVG: write and read back
	doc_t := doc_new(.Svg, "rt", 200, 100)
	rn := new_shape(doc_t, .Rect)
	rn.x, rn.y, rn.w, rn.h = 10, 20, 50, 40
	rn.fill = paint_solid({255, 0, 0, 255})
	rn.stroke = paint_solid({0, 0, 255, 255})
	rn.sw = 3
	append(&doc_t.root.children, rn)
	pn := new_shape(doc_t, .Path)
	path_move(&pn.segs, {0, 0})
	path_cubic(&pn.segs, {10, 0}, {20, 10}, {30, 30})
	path_close(&pn.segs)
	pn.fill = paint_make_gradient(paint_solid({10, 200, 30, 255}), Bounds{0, 0, 30, 30}, false)
	append(&doc_t.root.children, pn)
	out_text := svg_string(doc_t)
	back, bok := svg_parse(out_text)
	check(&t, bok, "svg parse of own output")
	if bok {
		check(&t, back.w == 200 && back.h == 100, "svg size")
		check(&t, len(back.root.children) == 2, "svg children")
		if len(back.root.children) == 2 {
			r0 := back.root.children[0]
			check(&t, r0.kind == .Rect && r0.w == 50 && r0.fill.color == Color{255, 0, 0, 255}, "svg rect roundtrip")
			p1 := back.root.children[1]
			check(&t, p1.kind == .Path && len(p1.segs) == 3 && p1.fill.kind == .Linear && p1.fill.nstops == 2, "svg path + gradient roundtrip")
		}
	}

	// SVG reader features
	svg := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
	<style>.a { fill: #00ff00; stroke: black; stroke-width: 2 } #b { fill: rgb(255, 0, 0) }</style>
	<defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
	<circle id="c" r="5"/></defs>
	<g transform="translate(10 20)"><rect class="a" width="10" height="10"/><rect id="b" width="5" height="5" transform="scale(2)"/></g>
	<use href="#c" x="50" y="50" fill="url(#g)"/>
	<path d="M10 10 h10 v10 h-10 z m 30 0 l 5.5-5.5.5.5" fill="none" stroke="#123"/>
	<polygon points="0,0 10,0 10,10" />
	<text x="5" y="90" font-size="12">Hi <tspan>there</tspan></text>
	</svg>`
	sd, sok := svg_parse(svg)
	check(&t, sok, "svg feature parse")
	if sok {
		g := sd.root.children[0]
		check(&t, g.kind == .Group && len(g.children) == 2, "svg group")
		if g.kind == .Group && len(g.children) == 2 {
			check(&t, g.children[0].fill.color == Color{0, 255, 0, 255} && g.children[0].sw == 2, "css class")
			check(&t, g.children[1].fill.color == Color{255, 0, 0, 255}, "css id + rgb()")
			check(&t, near(g.xf.e, 10) && near(g.xf.f, 20), "group transform")
		}
		check(&t, len(sd.root.children) == 5, "svg element count")
		if len(sd.root.children) >= 2 {
			uu := sd.root.children[1]
			check(&t, uu.kind == .Group && len(uu.children) == 1 && uu.children[0].kind == .Ellipse, "use clone")
		}
		if len(sd.root.children) >= 3 {
			pth := sd.root.children[2]
			check(&t, pth.kind == .Path && len(pth.segs) >= 8, "path commands")
		}
		if len(sd.root.children) >= 5 {
			tx := sd.root.children[4]
			check(&t, tx.kind == .Text && strings.contains(text_str(tx), "there"), "text + tspan")
		}
	}

	// undo / redo
	ud := doc_new(.Svg, "u", 10, 10)
	history_push(ud)
	append(&ud.root.children, new_shape(ud, .Rect))
	check(&t, len(ud.root.children) == 1, "undo setup")
	history_undo(ud)
	check(&t, len(ud.root.children) == 0, "undo")
	history_redo(ud)
	check(&t, len(ud.root.children) == 1, "redo")

	// curve fitting reproduces a smooth stroke with few segments
	pts := make([dynamic]Vec2, context.temp_allocator)
	for k in 0 ..= 40 {
		ang := f32(k) / 40 * math.PI
		append(&pts, Vec2{math.cos(ang) * 50, math.sin(ang) * 50})
	}
	fit := make(Path, context.temp_allocator)
	fit_curve(pts[:], 1, &fit)
	check(&t, len(fit) >= 1 && len(fit) <= 4, "curve fit segment count")

	font_selftest(&t)
	ui_selftest(&t)
	tool_groups_selftest(&t)
	reorder_selftest(&t)

	fmt.printf("%d passed, %d failed\n", t.passed, t.failed)
	return t.failed == 0 ? 0 : 1
}

// --render in.svg out.png [scale]
render_cli :: proc(in_path, out_path: string, scale: f32) -> int {
	d, ok := svg_load(in_path)
	if !ok {
		fmt.eprintln("cannot read", in_path)
		return 1
	}
	if !png_save(d, out_path, scale, true) {
		fmt.eprintln("cannot write", out_path)
		return 1
	}
	if len(svg_skipped) > 0 do fmt.println("skipped elements:", svg_skipped[:])
	return 0
}

// Sample drawing for screenshots (--demo).
demo_setup :: proc() {
	d := doc_new(.Svg, "Demo", 800, 600)
	n := new_shape(d, .Rect)
	n.x, n.y, n.w, n.h, n.rx, n.ry = 60, 60, 300, 200, 24, 24
	n.fill = paint_make_gradient(paint_solid({70, 120, 190, 255}), Bounds{60, 60, 360, 260}, false)
	n.stroke = paint_solid({30, 40, 70, 255})
	n.sw = 4
	append(&d.root.children, n)
	e := new_shape(d, .Ellipse)
	e.x, e.y, e.w, e.h = 520, 170, 130, 90
	e.fill = paint_make_gradient(paint_solid({246, 170, 104, 255}), Bounds{390, 80, 650, 260}, true)
	e.stroke = paint_none()
	append(&d.root.children, e)
	star := new_shape(d, .Path)
	for i in 0 ..< 10 {
		a := f32(i) * math.PI / 5 - math.PI / 2
		r: f32 = i % 2 == 0 ? 110 : 45
		pt := Vec2{200 + math.cos(a) * r, 440 + math.sin(a) * r}
		if i == 0 do path_move(&star.segs, pt)
		else do path_line(&star.segs, pt)
	}
	path_close(&star.segs)
	star.fill = paint_solid({240, 196, 60, 255})
	star.stroke = paint_solid({120, 72, 40, 255})
	star.sw = 6
	star.join = .Round
	append(&d.root.children, star)
	curve := new_shape(d, .Path)
	path_move(&curve.segs, {400, 480})
	path_cubic(&curve.segs, {460, 330}, {560, 600}, {700, 420})
	curve.fill = paint_none()
	curve.stroke = paint_solid({150, 70, 40, 255})
	curve.sw = 8
	curve.cap = .Round
	curve.ndash = 2
	curve.dash = {14, 14, 0, 0}
	append(&d.root.children, curve)
	t := new_shape(d, .Text)
	t.x, t.y, t.size = 400, 340, 48
	t.font = make_name(DEFAULT_FONT)
	append(&t.text, ..transmute([]u8)string("Scales"))
	t.stroke = paint_none()
	t.fill = paint_solid({40, 30, 24, 255})
	append(&d.root.children, t)
	sel_set(d, n)
	d.modified = false
	add_doc(d)
}

// Renders every icon at the sizes the interface uses (and two larger ones), light on the panel colour (--icon-sheet).
icon_sheet :: proc(path: string) -> int {
	SIZES :: [?]int{12, 16, 24, 32, 48}
	CELL :: 180
	PER_ROW :: 5
	row_h := 48 + 12
	rows := (len(Icon) + PER_ROW - 1) / PER_ROW
	w, h := PER_ROW * CELL + 20, rows * row_h + 20
	pix := make([]Color, w * h)
	defer delete(pix)
	for &p in pix do p = C_PANEL
	for ic in Icon {
		i := int(ic)
		x := 10 + (i % PER_ROW) * CELL
		y := 10 + (i / PER_ROW) * row_h
		for s in SIZES {
			cell := icon_render(ICON_SVG[ic], s, context.temp_allocator)
			for yy in 0 ..< s {
				for xx in 0 ..< s {
					k := f32(cell[yy * s + xx].a) / 255
					d := &pix[(y + 48 - s + yy) * w + x + xx]
					for ch in 0 ..< 3 do d[ch] = u8(f32(d[ch]) * (1 - k) + f32(C_TEXT[ch]) * k + 0.5)
				}
			}
			x += s + 6
		}
	}
	if !write_file(path, encode_png(pix, w, h)) {
		fmt.eprintln("cannot write", path)
		return 1
	}
	return 0
}
