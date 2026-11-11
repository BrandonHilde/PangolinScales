package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Eraser: cuts away the part of a shape under the stroke, and the shape stays vector. Filled shapes have the stroke
// subtracted, so the cut gets an edge of its own (and the object's stroke follows it). Lines and outlines without a
// fill are split instead, so they stay lines. With a selection only the selected objects are erased.
//
// The stroke is a chain of capsules in document space. Filled shapes are cut from their original outline each frame,
// so the cut edge never builds up; when the stroke ends they are cut once more with the stroke's outline fitted with
// curves, which leaves a few editable points instead of the many of a polygon. Lines only lose what is under each
// new capsule, and what is left keeps its exact curves.
// ---------------------------------------------------------------------------

eraser_size := 20 // diameter in screen pixels, like the Smoothing setting: the same tool for an icon and for a font
eraser_pressure := true

ERASER_SIZE_MIN :: 2
ERASER_SIZE_MAX :: 200

eraser_preset: Name // the eraser preset picked last (presets.odin)

// size, pressure (0 or 1)
eraser_builtins := [?]Preset_Builtin {
	{name = "Fine", vals = {6, 1}},
	{name = "Normal", vals = {20, 1}},
	{name = "Wide", vals = {60, 1}},
}

eraser_to_ints :: proc() -> [2]int {
	return {eraser_size, int(eraser_pressure)}
}

eraser_from_ints :: proc(v: []int) {
	if len(v) > 0 do eraser_size = clamp(v[0], ERASER_SIZE_MIN, ERASER_SIZE_MAX)
	if len(v) > 1 do eraser_pressure = v[1] != 0
}

@(private = "file")
Erase_Pt :: struct {
	p: Vec2,
	r: f32,
}

@(private = "file")
Erase_Target :: struct {
	uid:      u32,
	inv:      Mat, // document space to the object's own
	area:     bool, // subtract from the fill, or else split the line
	even_odd: bool,
	touched:  bool, // the object has changed
	extra:    f32, // how far a line's end caps reach past its end: the eraser clears them too
	geom:     Path, // in document space: a shape's original outline, or what is left of a line
	flat:     Polys, // a shape's flattened outline, to see when the stroke reaches it
	bounds:   Bounds, // of geom
}

@(private = "file")
er: struct {
	pts:       [dynamic]Erase_Pt,
	done:      int, // pts already applied
	targets:   [dynamic]Erase_Target,
	texts:     [dynamic]Bounds,
	text_hit:  bool,
	band:      Path, // outline of the whole stroke, scaled by `scale`
	uses_band: bool,
	scale:     f32, // path_boolean works on a fixed grid and drops tiny loops: at high zoom it needs more resolution
	pen_p:     f32,
}

tool_eraser :: proc(d: ^Doc, p: Vec2, pressed, over: bool) {
	if over do ui.cursor = .CROSSHAIR
	if pressed {
		eraser_begin(d)
		tl.kind = .Erase
	} else if tl.kind != .Erase {
		return
	}
	eraser_add(d, p)
	eraser_apply(d)
	if !ui.down[0] {
		eraser_end(d)
		tl_reset()
	}
}

// The brush outline under the pointer; during a stroke it follows the pen's pressure.
eraser_cursor :: proc(d: ^Doc) {
	sp := pointer()
	r := f32(eraser_size) / 2
	if tl.kind == .Erase && len(er.pts) > 0 do r = er.pts[len(er.pts) - 1].r * d.zoom
	draw_circle_outline(sp.x, sp.y, r + 1, Color{0, 0, 0, 180})
	draw_circle_outline(sp.x, sp.y, r, Color{255, 255, 255, 220})
}

@(private = "file")
eraser_begin :: proc(d: ^Doc) {
	pen_finish(true) // a path still being drawn would lose its points
	clear(&tl.anchors) // their indices don't survive a cut
	tl.ctrl_on = false
	tl.pushed = false
	eraser_clear()
	er.scale = max(d.zoom, 1)
	er.pen_p = max(pen.pressure, 0.05)
	for c in d.root.children do eraser_collect(d, c, MAT_ID, len(d.sel) == 0)
}

// What the stroke can erase, as it was when it began. A locked or hidden object keeps what is inside it safe too.
@(private = "file")
eraser_collect :: proc(d: ^Doc, n: ^Node, m: Mat, in_sel: bool) {
	if !n.visible || n.locked do return
	w := mat_mul(m, n.xf)
	chosen := in_sel || sel_has(d, n.uid)
	if n.kind == .Group {
		for c in n.children do eraser_collect(d, c, w, chosen)
		return
	}
	if !chosen do return
	if n.kind == .Text {
		append(&er.texts, bounds_transform(text_bounds(n), w))
		return
	}
	inv, ok := mat_inv(w)
	segs := node_segs(n)
	if !ok || len(segs) == 0 do return
	t := Erase_Target {
		uid      = n.uid,
		inv      = inv,
		even_odd = n.even_odd,
		geom     = path_clone(segs),
	}
	path_transform(t.geom[:], w)
	t.bounds = path_bounds(t.geom[:])
	has_fill := n.fill.kind != .None
	has_stroke := n.stroke.kind != .None && n.sw > 0
	open := path_has_open_subpath(segs)
	// a closed outline with no fill shows only its line; an open path that has both shows its line too, and its
	// fill follows along. An open path with only a fill looks like a closed shape, so it is cut like one.
	t.area = has_fill ? !open || !has_stroke : !has_stroke && !open
	if t.area {
		er.uses_band = true
		path_flatten(t.geom[:], MAT_ID, 0.25 / d.zoom, &t.flat)
	} else if has_stroke && n.cap != .Butt {
		t.extra = n.sw / 2 * mat_scale_factor(w)
	}
	append(&er.targets, t)
}

// Adds the pointer's position to the stroke, unless it has barely moved.
@(private = "file")
eraser_add :: proc(d: ^Doc, p: Vec2) {
	r := f32(eraser_size) / 2
	if eraser_pressure && pen.touching {
		er.pen_p += (max(pen.pressure, 0.05) - er.pen_p) * 0.5
		r *= er.pen_p
	}
	r = max(r, 1) / d.zoom
	if n := len(er.pts); n > 0 {
		last := er.pts[n - 1]
		if v_len(p - last.p) < max(last.r * 0.25, 0.75 / d.zoom) do return
	}
	append(&er.pts, Erase_Pt{p, r})
}

@(private = "file")
eraser_apply :: proc(d: ^Doc) {
	n := len(er.pts)
	if er.done >= n do return
	from := er.done
	er.done = n
	// where this part of the stroke reaches
	reach := BOUNDS_EMPTY
	for i in max(from - 1, 0) ..< n {
		e := er.pts[i]
		bounds_add(&reach, e.p - e.r)
		bounds_add(&reach, e.p + e.r)
	}
	if er.uses_band do band_add(d, from, n)
	for b in er.texts {
		if bounds_overlap(b, reach) do er.text_hit = true
	}
	changed := false
	for &t in er.targets {
		if !bounds_overlap(bounds_inflate(t.bounds, t.extra), reach) do continue
		node := node_find(d.root, t.uid)
		if node == nil do continue
		if t.area {
			if !t.touched {
				for i in from ..< n {
					if target_reached(&t, er.pts[max(i - 1, 0)], er.pts[i]) {
						target_touch(d, &t, node)
						break
					}
				}
			}
			if t.touched {
				target_set_geom(node, area_cut(&t, er.band[:]))
				changed = true
			}
			continue
		}
		for i in from ..< n {
			out := make(Path)
			if line_cut(t.geom[:], er.pts[max(i - 1, 0)], er.pts[i], t.extra, 0.5 / d.zoom, &out) {
				target_touch(d, &t, node)
				delete(t.geom)
				t.geom = out
				changed = true
			} else {
				delete(out)
			}
		}
		if t.touched {
			local := path_clone(t.geom[:])
			path_transform(local[:], t.inv)
			target_set_geom(node, local)
			t.bounds = path_bounds(t.geom[:])
		}
	}
	if changed do doc_changed(d)
}

// The object is about to change: this is the undo step, and a rectangle or ellipse becomes a path.
@(private = "file")
target_touch :: proc(d: ^Doc, t: ^Erase_Target, n: ^Node) {
	if t.touched do return
	t.touched = true
	push_once(d)
	if n.kind != .Path {
		node_to_path(n)
		name := name_str(&n.name)
		if name == "Rectangle" || name == "Ellipse" do name_set(&n.name, "Path")
	}
}

@(private = "file")
target_set_geom :: proc(n: ^Node, local: Path) {
	delete(n.segs)
	n.segs = local
}

// Whether a capsule of the stroke reaches a shape: its middle is inside, or the outline is within its radius.
@(private = "file")
target_reached :: proc(t: ^Erase_Target, a, b: Erase_Pt) -> bool {
	steps := clamp(int(math.ceil(v_len(b.p - a.p) / (min(a.r, b.r) * 0.5))), 1, 2048)
	for i in 0 ..= steps {
		u := f32(i) / f32(steps)
		q := a.p + (b.p - a.p) * u
		r := a.r + (b.r - a.r) * u
		if !bounds_contains(bounds_inflate(t.bounds, r), q) do continue
		if polys_contains(&t.flat, q, t.even_odd) || polys_distance(&t.flat, q) <= r do return true
	}
	return false
}

// A shape's original outline minus `band`, in the object's own space.
@(private = "file")
area_cut :: proc(t: ^Erase_Target, band: []Seg) -> Path {
	scaled := make(Path, len(t.geom), context.temp_allocator)
	copy(scaled[:], t.geom[:])
	path_transform(scaled[:], mat_scale(er.scale, er.scale))
	res, _ := path_boolean(scaled[:], band, .Subtract, t.even_odd)
	path_transform(res[:], mat_mul(t.inv, mat_scale(1 / er.scale, 1 / er.scale)))
	return res
}

// The stroke's outline ------------------------------------------------------------------------------------

// Adds a polygon with the orientation all the pieces share, so they fill as one under the non-zero rule.
@(private = "file")
band_piece :: proc(out: ^Path, pts: []Vec2) {
	n := len(pts)
	forward := poly_area(pts) >= 0
	for i in 0 ..< n {
		q := pts[forward ? i : n - 1 - i]
		if i == 0 do path_move(out, q)
		else do path_line(out, q)
	}
	path_close(out)
}

// The pieces of pts[from:to], each a circle and the side of the capsule from the sample before.
@(private = "file")
band_pieces :: proc(d: ^Doc, pts: []Erase_Pt, from, to: int, piece: ^Path) {
	s := er.scale
	for i in from ..< to {
		e := pts[i]
		c, r := e.p * s, e.r * s
		// a circle, within a tenth of a screen pixel
		px := e.r * d.zoom
		steps := clamp(int(math.ceil(math.PI / math.acos(max(1 - 0.1 / max(px, 0.11), -1)))), 8, 48)
		circle := make([]Vec2, steps, context.temp_allocator)
		for k in 0 ..< steps {
			ang := f32(k) / f32(steps) * math.TAU
			circle[k] = c + Vec2{math.cos(ang), math.sin(ang)} * r
		}
		band_piece(piece, circle)
		if i > 0 {
			prev := pts[i - 1]
			a := prev.p * s
			if v_len(c - a) > 1e-3 {
				nrm := v_perp(v_norm(c - a))
				pa, pb := nrm * (prev.r * s), nrm * r
				band_piece(piece, {a + pa, c + pb, c - pb, a - pa})
			}
		}
	}
}

@(private = "file")
band_add :: proc(d: ^Doc, from, to: int) {
	piece := make(Path, context.temp_allocator)
	band_pieces(d, er.pts[:], from, to, &piece)
	merged, _ := path_boolean(er.band[:], piece[:], .Union)
	delete(er.band)
	er.band = merged
}

// Ramer-Douglas-Peucker on the stroke, measuring how far both the position and the radius stray: a pointer at whole
// pixels makes a straight drag into stairs, which an outline would follow, but a change of pressure has to stay.
@(private = "file")
stroke_simplify :: proc(pts: []Erase_Pt, tol: f32, out: ^[dynamic]Erase_Pt) {
	n := len(pts)
	if n < 3 {
		append(out, ..pts)
		return
	}
	a, b := pts[0], pts[n - 1]
	best: f32
	bi := 0
	for i in 1 ..< n - 1 {
		e := pts[i]
		ab := b.p - a.p
		l2 := v_dot(ab, ab)
		u := l2 > 0 ? clamp(v_dot(e.p - a.p, ab) / l2, 0, 1) : 0
		dev := max(v_len(e.p - (a.p + ab * u)), abs(e.r - (a.r + (b.r - a.r) * u)))
		if dev > best {
			best = dev
			bi = i
		}
	}
	if best <= tol {
		append(out, a, b)
		return
	}
	stroke_simplify(pts[:bi + 1], tol, out)
	pop(out)
	stroke_simplify(pts[bi:], tol, out)
}

// The finished stroke's outline, simplified and with curves fitted to it, in the temp allocator.
@(private = "file")
band_fit :: proc(d: ^Doc) -> Path {
	out := make(Path, context.temp_allocator)
	clean := make([dynamic]Erase_Pt, context.temp_allocator)
	stroke_simplify(er.pts[:], 0.6 / er.scale, &clean)
	pieces := make(Path, context.temp_allocator)
	band_pieces(d, clean[:], 0, len(clean), &pieces)
	outline, _ := path_boolean(nil, pieces[:], .Union)
	defer delete(outline)
	flat: Polys
	defer polys_free(&flat)
	path_flatten(outline[:], MAT_ID, 0.05, &flat)
	TOL: f32 = 0.35 // in the scaled space: about a third of a screen pixel when zoomed in
	SPACING: f32 = 3
	CORNER := math.cos(f32(deg2rad(25)))
	for sb in flat.subs {
		// rounding leaves tiny edges pointing anywhere, which would look like sharp corners
		kept := make([dynamic]Vec2, context.temp_allocator)
		for q in flat.pts[sb.a:sb.b] {
			if len(kept) == 0 || v_len(q - kept[len(kept) - 1]) > 0.3 do append(&kept, q)
		}
		for len(kept) > 1 && v_len(kept[0] - kept[len(kept) - 1]) <= 0.3 do pop(&kept)
		pts := kept[:]
		n := len(pts)
		if n < 3 do continue
		// sharp corners stay sharp: each stretch between them gets its own curves
		corners := make([dynamic]int, context.temp_allocator)
		for i in 0 ..< n {
			a := v_norm(pts[i] - pts[(i + n - 1) % n])
			b := v_norm(pts[(i + 1) % n] - pts[i])
			if v_dot(a, b) < CORNER do append(&corners, i)
		}
		if len(corners) == 0 do append(&corners, 0)
		path_move(&out, pts[corners[0]])
		for c, ci in corners {
			next := corners[(ci + 1) % len(corners)]
			count := (next - c + n - 1) % n + 1 // edges in this stretch; a lone corner goes all the way round
			// fitting only measures its error at the points it is given, so a long edge needs points along it
			stretch := make([dynamic]Vec2, context.temp_allocator)
			append(&stretch, pts[c])
			for k in 0 ..< count {
				p, q := pts[(c + k) % n], pts[(c + k + 1) % n]
				parts := max(int(math.ceil(v_len(q - p) / SPACING)), 1)
				for s in 1 ..= parts do append(&stretch, p + (q - p) * (f32(s) / f32(parts)))
			}
			if count == 1 {
				path_line(&out, pts[next])
			} else {
				fit_curve(stretch[:], TOL * TOL, &out)
			}
		}
		path_close(&out)
	}
	return out
}

// Lines -----------------------------------------------------------------------------------------------------

@(private = "file")
capsule_hit :: proc(p: Vec2, a, b: Erase_Pt, extra: f32) -> bool {
	ab := b.p - a.p
	l2 := v_dot(ab, ab)
	u := l2 > 0 ? clamp(v_dot(p - a.p, ab) / l2, 0, 1) : 0
	q := p - (a.p + ab * u)
	r := a.r + (b.r - a.r) * u + extra
	return v_dot(q, q) <= r * r
}

@(private = "file")
Bez :: struct {
	n: int, // control points: 2 line, 3 quad, 4 cubic
	p: [4]Vec2,
}

@(private = "file")
bez_f64 :: proc(b: Bez) -> (out: [4][2]f64) {
	for i in 0 ..< b.n do out[i] = {f64(b.p[i].x), f64(b.p[i].y)}
	return
}

@(private = "file")
bez_at :: proc(b: Bez, t: f32) -> Vec2 {
	pts := bez_f64(b)
	q := bez_point(pts[:b.n], f64(t))
	return {f32(q[0]), f32(q[1])}
}

// Appends the part of a segment between t0 and t1; the path is already at its start.
@(private = "file")
bez_emit :: proc(b: Bez, t0, t1: f32, out: ^Path) {
	p := b.p
	if t0 > 0 || t1 < 1 {
		pts := bez_f64(b)
		s := bez_slice(pts[:b.n], f64(t0), f64(t1))
		for i in 0 ..< b.n do p[i] = {f32(s[i][0]), f32(s[i][1])}
	}
	switch b.n {
	case 2: path_line(out, p[1])
	case 3: path_quad(out, p[1], p[2])
	case 4: path_cubic(out, p[1], p[2], p[3])
	}
}

@(private = "file")
Keep :: struct {
	piece:  int,
	t0, t1: f32,
}

// The parts of `segs` outside one capsule go to `out`. Subpaths it doesn't reach are copied as they are. False if
// nothing was cut.
@(private = "file")
line_cut :: proc(segs: []Seg, a, b: Erase_Pt, extra, min_len: f32, out: ^Path) -> (changed: bool) {
	i := 0
	for i < len(segs) {
		j := i + 1
		for j < len(segs) && segs[j].kind != .Move do j += 1
		if subpath_cut(segs[i:j], a, b, extra, min_len, out) do changed = true
		else do append(out, ..segs[i:j])
		i = j
	}
	return
}

@(private = "file")
subpath_cut :: proc(sub: []Seg, a, b: Erase_Pt, extra, min_len: f32, out: ^Path) -> bool {
	// the subpath as separate segments, with the straight closing one
	pieces := make([dynamic]Bez, context.temp_allocator)
	start := sub[0].p
	cur := start
	closed := false
	for g in sub[1:] {
		#partial switch g.kind {
		case .Line:
			append(&pieces, Bez{2, {cur, g.p, {}, {}}})
			cur = g.p
		case .Quad:
			append(&pieces, Bez{3, {cur, g.c1, g.p, {}}})
			cur = g.p
		case .Cubic:
			append(&pieces, Bez{4, {cur, g.c1, g.c2, g.p}})
			cur = g.p
		case .Close:
			if cur != start do append(&pieces, Bez{2, {cur, start, {}, {}}})
			cur = start
			closed = true
		}
	}
	reach := BOUNDS_EMPTY
	bounds_add(&reach, a.p - (a.r + extra))
	bounds_add(&reach, a.p + (a.r + extra))
	bounds_add(&reach, b.p - (b.r + extra))
	bounds_add(&reach, b.p + (b.r + extra))
	step := max(min(a.r, b.r) + extra, 1e-3) * 0.5

	// what stays of each segment
	keeps := make([dynamic]Keep, context.temp_allocator)
	cut := false
	for pc, pi in pieces {
		hull := BOUNDS_EMPTY
		length: f32
		for k in 0 ..< pc.n {
			bounds_add(&hull, pc.p[k])
			if k > 0 do length += v_len(pc.p[k] - pc.p[k - 1])
		}
		if !bounds_overlap(hull, reach) {
			append(&keeps, Keep{pi, 0, 1})
			continue
		}
		steps := clamp(int(math.ceil(length / step)), 1, 4096)
		in_prev := capsule_hit(pc.p[0], a, b, extra)
		t_prev: f32 = 0
		from: f32 = in_prev ? -1 : 0
		if in_prev do cut = true
		for k in 1 ..= steps {
			t := f32(k) / f32(steps)
			in_now := capsule_hit(bez_at(pc, t), a, b, extra)
			if in_now != in_prev {
				// the edge of the capsule, narrowed down
				lo, hi := t_prev, t
				for _ in 0 ..< 16 {
					mid := (lo + hi) / 2
					if capsule_hit(bez_at(pc, mid), a, b, extra) == in_prev do lo = mid
					else do hi = mid
				}
				if in_now {
					append(&keeps, Keep{pi, from, lo})
					from = -1
					cut = true
				} else {
					from = hi
				}
			}
			in_prev, t_prev = in_now, t
		}
		if from >= 0 do append(&keeps, Keep{pi, from, 1})
	}
	if !cut do return false

	// unbroken runs of what stays
	runs := make([dynamic][2]int, context.temp_allocator)
	for k, ki in keeps {
		if ki > 0 && keeps[ki - 1].t1 == 1 && k.t0 == 0 && k.piece == keeps[ki - 1].piece + 1 {
			runs[len(runs) - 1][1] = ki + 1
		} else {
			append(&runs, [2]int{ki, ki + 1})
		}
	}
	// a closed path now starts after a cut, unless its start point is erased
	wrap := false
	if closed && len(runs) >= 2 {
		f, l := keeps[0], keeps[len(keeps) - 1]
		wrap = f.piece == 0 && f.t0 == 0 && l.piece == len(pieces) - 1 && l.t1 == 1
	}
	run_len :: proc(pieces: []Bez, keeps: []Keep) -> f32 {
		total: f32
		for k in keeps {
			pc := pieces[k.piece]
			prev := bez_at(pc, k.t0)
			for s in 1 ..= 8 {
				q := bez_at(pc, k.t0 + (k.t1 - k.t0) * f32(s) / 8)
				total += v_len(q - prev)
				prev = q
			}
		}
		return total
	}
	emit :: proc(pieces: []Bez, keeps: []Keep, move: bool, out: ^Path) {
		for k, ki in keeps {
			pc := pieces[k.piece]
			if ki == 0 && move do path_move(out, bez_at(pc, k.t0))
			bez_emit(pc, k.t0, k.t1, out)
		}
	}
	for r, ri in runs {
		if wrap && ri == 0 do continue // goes after the last run
		part := keeps[r[0]:r[1]]
		length := run_len(pieces[:], part)
		first := wrap && ri == len(runs) - 1 ? keeps[runs[0][0]:runs[0][1]] : nil
		if first != nil do length += run_len(pieces[:], first)
		if length < min_len do continue // a speck is not worth keeping
		emit(pieces[:], part, true, out)
		if first != nil do emit(pieces[:], first, false, out)
	}
	return true
}

// End of the stroke -----------------------------------------------------------------------------------------

// Commits the stroke. Also runs if it is interrupted, so no half-cut object stays behind.
eraser_end :: proc(d: ^Doc) {
	cut := false
	fitted: Path
	have_fit := false
	for &t in er.targets {
		node := node_find(d.root, t.uid)
		if !t.touched || node == nil do continue
		cut = true
		if t.area {
			if !have_fit {
				fitted = band_fit(d)
				have_fit = true
			}
			res := area_cut(&t, fitted[:])
			// the fitted outline is a touch different: it can't be what erases a shape entirely
			if len(res) > 0 || len(node.segs) == 0 do target_set_geom(node, res)
			else do delete(res)
		}
		if len(node.segs) == 0 do eraser_remove(d, node)
	}
	if cut {
		doc_changed(d)
	} else if er.text_hit {
		set_status("Text can't be erased: use Object to Path on it first")
	} else if len(d.sel) > 0 && len(er.pts) > 0 {
		set_status("Only the selected objects are erased. Ctrl+D clears the selection")
	}
	eraser_clear()
}

// Removes an object with nothing left, and any groups that leaves empty.
@(private = "file")
eraser_remove :: proc(d: ^Doc, n: ^Node) {
	cur := n
	for cur != nil && cur != d.root {
		parent := node_parent(d.root, cur)
		if parent == nil do break
		if i := node_index(parent, cur); i >= 0 do ordered_remove(&parent.children, i)
		for u, k in d.sel {
			if u == cur.uid {
				ordered_remove(&d.sel, k)
				break
			}
		}
		node_free(cur)
		if parent == d.root || len(parent.children) > 0 do break
		cur = parent
	}
}

@(private = "file")
eraser_clear :: proc() {
	for &t in er.targets {
		delete(t.geom)
		polys_free(&t.flat)
	}
	clear(&er.targets)
	clear(&er.texts)
	clear(&er.pts)
	delete(er.band)
	er.band = nil
	er.done = 0
	er.uses_band, er.text_hit = false, false
}
