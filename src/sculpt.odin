package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Sculpt: a brush that moves the outlines under it, fading towards its edge. Moving the control points of short
// curves with a smooth field keeps the curves smooth, so the segments near the brush are split until they are short;
// when the stroke ends, the split parts are fitted with a few curves again. Corners stay corners, and what the brush
// didn't reach keeps its exact points. With a selection only the selected objects are sculpted.
//
// Extend: continues an open line from one of its ends, as part of the same object.
// ---------------------------------------------------------------------------

sculpt_size := 60 // diameter in screen pixels, like the eraser
sculpt_strength := 100 // percent
sculpt_pressure := true

SCULPT_SIZE_MIN :: 4
SCULPT_SIZE_MAX :: 400
// Scrubbing over a shape stretches and folds its outline like kneading, so its length grows very fast. After a stroke
// has added this many segments, across all the objects it reached, the brush only moves what is there.
SCULPT_MAX_ADDED :: 20000

@(private = "file")
Sculpt_Target :: struct {
	uid:     u32,
	inv:     Mat, // document space to the object's own
	geom:    Path, // in document space
	worked:  [dynamic]bool, // for each segment of geom: the brush has split it, so it is fitted again at the end
	kept:    [dynamic]bool, // for each segment of geom: it ends on a point the object already had, which stays
	touched: bool,
	bounds:  Bounds,
}

@(private = "file")
sc: struct {
	targets:  [dynamic]Sculpt_Target,
	texts:    [dynamic]Bounds,
	text_hit: bool,
	last:     Vec2,
	r:        f32, // the brush's radius right now, in document units
	pen_p:    f32,
	added:    int, // segments this stroke has added
	// the next version of a target's lists, swapped with its own: a stroke can take thousands of steps per frame's
	// worth of a long path, and shouldn't allocate a copy of it for each
	out:      Path,
	worked:   [dynamic]bool,
	kept:     [dynamic]bool,
}

tool_sculpt :: proc(d: ^Doc, p: Vec2, pressed, over: bool) {
	if over do ui.cursor = .CROSSHAIR
	if pressed {
		sculpt_begin(d, p)
		tl.kind = .Sculpt
		return
	}
	if tl.kind != .Sculpt do return
	sculpt_apply(d, p)
	if !ui.down[0] {
		sculpt_end(d)
		tl_reset()
	}
}

sculpt_cursor :: proc(d: ^Doc) {
	sp := pointer()
	r := f32(sculpt_size) / 2
	draw_circle_outline(sp.x, sp.y, r + 1, Color{0, 0, 0, 180})
	draw_circle_outline(sp.x, sp.y, r, Color{255, 255, 255, 220})
}

@(private = "file")
sculpt_begin :: proc(d: ^Doc, p: Vec2) {
	pen_finish(true) // a path still being drawn would lose its points
	clear(&tl.anchors) // their indices don't survive a split
	tl.ctrl_on = false
	tl.pushed = false
	sculpt_clear()
	sc.last = p
	sc.added = 0
	sc.pen_p = max(pen.pressure, 0.05)
	for c in d.root.children do sculpt_collect(d, c, MAT_ID, len(d.sel) == 0)
}

// What the stroke can reach. A locked or hidden object keeps what is inside it safe too.
@(private = "file")
sculpt_collect :: proc(d: ^Doc, n: ^Node, m: Mat, in_sel: bool) {
	if !n.visible || n.locked do return
	w := mat_mul(m, n.xf)
	chosen := in_sel || sel_has(d, n.uid)
	if n.kind == .Group {
		for c in n.children do sculpt_collect(d, c, w, chosen)
		return
	}
	if !chosen do return
	if n.kind == .Text {
		append(&sc.texts, bounds_transform(text_bounds(n), w))
		return
	}
	inv, ok := mat_inv(w)
	segs := node_segs(n)
	if !ok || len(segs) == 0 do return
	t := Sculpt_Target {
		uid  = n.uid,
		inv  = inv,
		geom = path_clone(segs),
	}
	path_transform(t.geom[:], w)
	resize(&t.worked, len(t.geom))
	resize(&t.kept, len(t.geom))
	for &k in t.kept do k = true
	t.bounds = path_bounds(t.geom[:])
	append(&sc.targets, t)
}

// Moves what is under the brush by the pointer's movement. A fast pointer is followed in steps, so it can't jump
// over a line without catching it.
@(private = "file")
sculpt_apply :: proc(d: ^Doc, p: Vec2) {
	strength := f32(sculpt_strength) / 100
	if sculpt_pressure && pen.touching {
		sc.pen_p += (max(pen.pressure, 0.05) - sc.pen_p) * 0.5
		strength *= sc.pen_p
	}
	sc.r = f32(sculpt_size) / 2 / d.zoom
	delta := p - sc.last
	dist := v_len(delta)
	if dist < 1e-4 do return
	steps := clamp(int(math.ceil(dist / (sc.r * 0.25))), 1, 256)
	changed := make([]bool, len(sc.targets), context.temp_allocator)
	for s in 0 ..< steps {
		c := sc.last + delta * ((f32(s) + 0.5) / f32(steps))
		for b in sc.texts {
			if bounds_contains(bounds_inflate(b, sc.r), c) do sc.text_hit = true
		}
		for &t, i in sc.targets {
			if !bounds_contains(bounds_inflate(t.bounds, sc.r), c) do continue
			if target_push(d, &t, c, sc.r, delta * (strength / f32(steps))) do changed[i] = true
		}
	}
	sc.last = p
	any_change := false
	for &t, i in sc.targets {
		if !changed[i] do continue
		any_change = true
		if n := node_find(d.root, t.uid); n != nil do sculpt_write(n, t.geom[:], &t)
	}
	if any_change do doc_changed(d)
}

// Puts `geom`, in document space, into the object.
@(private = "file")
sculpt_write :: proc(n: ^Node, geom: []Seg, t: ^Sculpt_Target) {
	delete(n.segs)
	n.segs = path_clone(geom)
	path_transform(n.segs[:], t.inv)
}

// The falloff is smooth, and has no slope at the edge of the brush, so no crease shows where it ends.
@(private = "file")
brush_weight :: proc(p, c: Vec2, r: f32) -> f32 {
	q := p - c
	k := v_dot(q, q) / (r * r)
	if k >= 1 do return 0
	return (1 - k) * (1 - k)
}

@(private = "file")
target_push :: proc(d: ^Doc, t: ^Sculpt_Target, c: Vec2, r: f32, move: Vec2) -> bool {
	box := Bounds{c.x - r, c.y - r, c.x + r, c.y + r}
	max_len := sc.added < SCULPT_MAX_ADDED ? r / 3 : max(f32)
	clear(&sc.out)
	clear(&sc.worked)
	clear(&sc.kept)

	Lists :: struct {
		out:    ^Path,
		worked: ^[dynamic]bool,
		kept:   ^[dynamic]bool,
	}
	lists := Lists{&sc.out, &sc.worked, &sc.kept}

	// `keep`: the segment's end is a point the object had; the new points between stay removable
	split :: proc(a, c1, c2, b: Vec2, box: Bounds, max_len: f32, depth: int, keep: bool, l: Lists) {
		hull := BOUNDS_EMPTY
		bounds_add(&hull, a)
		bounds_add(&hull, c1)
		bounds_add(&hull, c2)
		bounds_add(&hull, b)
		near := bounds_overlap(hull, box)
		length := v_len(c1 - a) + v_len(c2 - c1) + v_len(b - c2)
		if near && length > max_len && depth < 14 {
			ab, bc, cd := (a + c1) / 2, (c1 + c2) / 2, (c2 + b) / 2
			abc, bcd := (ab + bc) / 2, (bc + cd) / 2
			mid := (abc + bcd) / 2
			split(a, ab, abc, mid, box, max_len, depth + 1, false, l)
			split(mid, bcd, cd, b, box, max_len, depth + 1, keep, l)
			return
		}
		path_cubic(l.out, c1, c2, b)
		append(l.worked, true)
		append(l.kept, keep)
	}

	start, cur: Vec2
	for g, i in t.geom {
		// a segment the brush can't reach stays as it is
		was_worked, was_kept := t.worked[i], t.kept[i]
		a, c1, c2 := cur, g.c1, g.c2
		switch g.kind {
		case .Move:
			start, cur = g.p, g.p
			append(&sc.out, g)
			append(&sc.worked, false)
			append(&sc.kept, true)
			continue
		case .Close:
			if cur != start {
				// the straight closing edge becomes a real one: it has to bend like the others
				hull := BOUNDS_EMPTY
				bounds_add(&hull, cur)
				bounds_add(&hull, start)
				if bounds_overlap(hull, box) {
					split(cur, cur + (start - cur) / 3, cur + (start - cur) * (2.0 / 3), start, box, max_len, 0, true, lists)
				}
			}
			cur = start
			append(&sc.out, g)
			append(&sc.worked, false)
			append(&sc.kept, true)
			continue
		case .Line:
			c1, c2 = a + (g.p - a) / 3, a + (g.p - a) * (2.0 / 3)
		case .Quad:
			c1, c2 = a + (g.c1 - a) * (2.0 / 3), g.p + (g.c1 - g.p) * (2.0 / 3)
		case .Cubic:
		}
		hull := BOUNDS_EMPTY
		bounds_add(&hull, a)
		bounds_add(&hull, c1)
		bounds_add(&hull, c2)
		bounds_add(&hull, g.p)
		if bounds_overlap(hull, box) {
			split(a, c1, c2, g.p, box, max_len, 0, was_kept, lists)
		} else {
			append(&sc.out, g)
			append(&sc.worked, was_worked)
			append(&sc.kept, was_kept)
		}
		cur = g.p
	}

	moved := false
	for &g in sc.out {
		if g.kind == .Close do continue
		if w := brush_weight(g.p, c, r); w > 0 {
			g.p += move * w
			moved = true
		}
		if g.kind == .Cubic || g.kind == .Quad {
			g.c1 += move * brush_weight(g.c1, c, r)
			if g.kind == .Cubic do g.c2 += move * brush_weight(g.c2, c, r)
		}
	}
	if !moved do return false // the brush's box reached it, the brush didn't: nothing is split for no reason

	if !t.touched {
		t.touched = true
		push_once(d)
		if n := node_find(d.root, t.uid); n != nil && n.kind != .Path {
			node_to_path(n)
			name := name_str(&n.name)
			if name == "Rectangle" || name == "Ellipse" do name_set(&n.name, "Path")
		}
	}
	sc.added += len(sc.out) - len(t.geom)
	t.geom, sc.out = sc.out, t.geom
	t.worked, sc.worked = sc.worked, t.worked
	t.kept, sc.kept = sc.kept, t.kept
	t.bounds = path_bounds(t.geom[:])
	return true
}

// The direction a segment leaves its first point in, and arrives at its last in. Zero if it has none.
@(private = "file")
seg_leaving :: proc(segs: []Seg, k: int) -> Vec2 {
	g := segs[k]
	from := prev_point(segs, k)
	d := g.kind == .Line ? g.p - from : g.c1 - from
	if v_dot(d, d) < 1e-8 do d = g.p - from
	return v_dot(d, d) < 1e-8 ? Vec2{} : v_norm(d)
}

@(private = "file")
seg_arriving :: proc(segs: []Seg, k: int) -> Vec2 {
	g := segs[k]
	d := g.p - prev_point(segs, k)
	#partial switch g.kind {
	case .Quad:  d = g.p - g.c1
	case .Cubic: d = g.p - g.c2
	}
	if v_dot(d, d) < 1e-8 do d = g.p - prev_point(segs, k)
	return v_dot(d, d) < 1e-8 ? Vec2{} : v_norm(d)
}

// The segment before segment i, and after segment j, going round the join of a closed subpath. -1 at an open end.
@(private = "file")
segment_before :: proc(segs: []Seg, i: int) -> int {
	if i > 0 && segs[i - 1].kind != .Move && segs[i - 1].kind != .Close do return i - 1
	k := i
	for k < len(segs) && segs[k].kind != .Move && segs[k].kind != .Close do k += 1
	if k < len(segs) && segs[k].kind == .Close && k > i && segs[k - 1].p == prev_point(segs, i) do return k - 1
	return -1
}

@(private = "file")
segment_after :: proc(segs: []Seg, j: int) -> int {
	if j + 1 >= len(segs) || segs[j + 1].kind == .Move do return -1
	if segs[j + 1].kind != .Close do return j + 1
	k := j
	for k >= 0 && segs[k].kind != .Move do k -= 1
	if k >= 0 && k < j && segs[k].p == segs[j].p do return k + 1
	return -1
}

// The one direction for the point between two segments, if they meet smoothly. The brush's uneven falloff bends the
// two sides of a smooth point a little differently; a real corner turns further than that. A side the brush didn't
// split keeps its exact direction, and the other follows it.
@(private = "file")
joint_direction :: proc(t: ^Sculpt_Target, a, b: int) -> (Vec2, bool) {
	segs := t.geom[:]
	into, from := seg_arriving(segs, a), seg_leaving(segs, b)
	if into == {} || from == {} || v_dot(into, from) < math.cos(f32(deg2rad(15))) do return {}, false
	if t.worked[a] && t.worked[b] do return v_norm(into + from), true
	return t.worked[a] ? from : into, true
}

// Fits the parts the brush split with few curves again, between the points the object already had. Those points
// stay, so corners stay corners and a drawing keeps the points it was made with. A part that is still straight
// becomes a straight line again.
@(private = "file")
sculpt_refit :: proc(t: ^Sculpt_Target, zoom: f32) -> Path {
	out := make(Path, context.temp_allocator)
	segs := t.geom[:]
	tol := 0.3 / zoom
	fit_tol := 0.6 / zoom
	cur: Vec2
	i := 0
	for i < len(segs) {
		g := segs[i]
		if !t.worked[i] || g.kind != .Cubic {
			append(&out, g)
			if g.kind != .Close do cur = g.p
			i += 1
			continue
		}
		j := i
		for !t.kept[j] && j + 1 < len(segs) && t.worked[j + 1] && segs[j + 1].kind == .Cubic do j += 1
		// sampled closely, since fitting only measures its error at the points it is given
		pts := make([dynamic]Vec2, context.temp_allocator)
		append(&pts, cur)
		a := cur
		for k in i ..= j {
			s := segs[k]
			length := v_len(s.c1 - a) + v_len(s.c2 - s.c1) + v_len(s.p - s.c2)
			n := clamp(int(math.ceil(length * zoom / 2)), 3, 48)
			for q in 1 ..= n do append(&pts, cubic_at(a, s.c1, s.c2, s.p, f32(q) / f32(n)))
			a = s.p
		}
		straight := true
		for q in pts {
			if dist_to_segment(q, cur, a) > tol {
				straight = false
				break
			}
		}
		before := len(out)
		if !straight {
			// the directions at these points come from the path, not from the samples, and two curves that meet
			// smoothly on one of them share it
			leave := seg_leaving(segs, i)
			if b := segment_before(segs, i); b >= 0 {
				if d, smooth := joint_direction(t, b, i); smooth do leave = d
			}
			arrive := seg_arriving(segs, j)
			if n := segment_after(segs, j); n >= 0 {
				if d, smooth := joint_direction(t, j, n); smooth do arrive = d
			}
			fit_curve(pts[:], fit_tol * fit_tol, &out, leave, -arrive)
		}
		if len(out) == before do path_line(&out, a) // straight, or too short to fit: the point still has to be there
		// fitting is there to simplify: a badly crumpled part can come out with more segments than it went in with
		if len(out) - before > j - i + 1 {
			resize(&out, before)
			append(&out, ..segs[i:j + 1])
		}
		cur = a
		i = j + 1
	}
	return out
}

// Commits the stroke. Also runs if it is interrupted.
sculpt_end :: proc(d: ^Doc) {
	any_touched := false
	for &t in sc.targets {
		if !t.touched do continue
		any_touched = true
		if n := node_find(d.root, t.uid); n != nil {
			fitted := sculpt_refit(&t, d.zoom)
			sculpt_write(n, fitted[:], &t)
		}
	}
	if any_touched {
		doc_changed(d)
	} else if sc.text_hit {
		set_status("Text can't be sculpted: use Object to Path on it first")
	} else if len(d.sel) > 0 {
		set_status("Only the selected objects are sculpted. Ctrl+D clears the selection")
	}
	sculpt_clear()
}

@(private = "file")
sculpt_clear :: proc() {
	for &t in sc.targets {
		delete(t.geom)
		delete(t.worked)
		delete(t.kept)
	}
	clear(&sc.targets)
	clear(&sc.texts)
	sc.text_hit = false
	delete(sc.out)
	delete(sc.worked)
	delete(sc.kept)
	sc.out, sc.worked, sc.kept = nil, nil, nil
}

// Extend ------------------------------------------------------------------------------------------------------

EXTEND_GRAB :: 12 // how close to an end a press has to be, in screen pixels

@(private = "file")
Line_End :: struct {
	uid:    u32,
	sub:    int, // which subpath of the object
	at_end: bool, // its last point, or else its first
	p:      Vec2, // in document space
}

@(private = "file")
ex: Line_End

// Every open end that can be extended: of the selection if there is one, or else of everything.
@(private = "file")
line_ends :: proc(d: ^Doc, out: ^[dynamic]Line_End) {
	walk :: proc(d: ^Doc, n: ^Node, m: Mat, in_sel: bool, out: ^[dynamic]Line_End) {
		if !n.visible || n.locked do return
		w := mat_mul(m, n.xf)
		chosen := in_sel || sel_has(d, n.uid)
		if n.kind == .Group {
			for c in n.children do walk(d, c, w, chosen, out)
			return
		}
		if !chosen || n.kind != .Path do return
		sub := 0
		i := 0
		for i < len(n.segs) {
			j := i + 1
			for j < len(n.segs) && n.segs[j].kind != .Move do j += 1
			last := n.segs[j - 1]
			if j - i >= 2 && last.kind != .Close && last.p != n.segs[i].p {
				append(out, Line_End{n.uid, sub, false, mat_apply(w, n.segs[i].p)})
				append(out, Line_End{n.uid, sub, true, mat_apply(w, last.p)})
			}
			sub += 1
			i = j
		}
	}
	for c in d.root.children do walk(d, c, MAT_ID, len(d.sel) == 0, out)
}

// The end under the pointer. The object on top wins where ends meet.
@(private = "file")
line_end_at :: proc(d: ^Doc, sp: Vec2) -> (Line_End, bool) {
	ends := make([dynamic]Line_End, context.temp_allocator)
	line_ends(d, &ends)
	best := f32(EXTEND_GRAB)
	found: Line_End
	ok := false
	#reverse for e in ends {
		dist := v_len(to_screen(d, e.p) - sp)
		if dist < best {
			best, found, ok = dist, e, true
		}
	}
	return found, ok
}

tool_extend :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if over do ui.cursor = .CROSSHAIR
	if pressed {
		pen_finish(true)
		clear(&tl.anchors)
		tl.ctrl_on = false
		e, ok := line_end_at(d, sp)
		if !ok {
			set_status(len(d.sel) > 0 ? "Start on an end of a selected line. Ctrl+D clears the selection" : "Start on an end of an open line")
			return
		}
		ex = e
		tl.kind = .Extend
		tl.start_scr = sp
		clear(&tl.free_pts)
		append(&tl.free_pts, e.p)
		return
	}
	if tl.kind != .Extend do return
	if ui.down[0] {
		q := snap_pt(p)
		if v_len(q - tl.free_pts[len(tl.free_pts) - 1]) * d.zoom > 2 do append(&tl.free_pts, q)
		return
	}
	defer tl_reset()
	extend_finish(d)
}

// Fits the drawn stroke with curves and joins it to the line's end. Starting from a line's first point turns that
// subpath round, so what is added is always at its end.
@(private = "file")
extend_finish :: proc(d: ^Doc) {
	if len(tl.free_pts) < 2 do return
	n := node_find(d.root, ex.uid)
	if n == nil || n.kind != .Path do return
	w := node_world(d.root, n)
	inv, ok := mat_inv(w)
	if !ok do return
	// the subpath
	a, b, sub := 0, 0, 0
	for a < len(n.segs) {
		b = a + 1
		for b < len(n.segs) && n.segs[b].kind != .Move do b += 1
		if sub == ex.sub do break
		sub += 1
		a = b
	}
	if a >= len(n.segs) do return

	line := make(Path, context.temp_allocator)
	append(&line, ..n.segs[a:b])
	if !ex.at_end do path_reverse(&line)
	if len(line) < 2 do return

	// in the object's own space
	pts := make([]Vec2, len(tl.free_pts), context.temp_allocator)
	for q, i in tl.free_pts do pts[i] = mat_apply(inv, q)
	end := line[len(line) - 1].p
	first := line[0].p
	pts[0] = end
	k := mat_scale_factor(w)
	closes := close_open_paths && len(pts) > 3 && v_len(tl.free_pts[len(pts) - 1] - mat_apply(w, first)) * d.zoom < 10
	if closes do pts[len(pts) - 1] = first

	// a stroke that carries on in about the same direction joins without a kink; a turn stays a turn
	tangent: Vec2
	{
		l := line[len(line) - 1]
		prev := line[len(line) - 2].p
		into := end - prev
		#partial switch l.kind {
		case .Cubic: into = end - l.c2
		case .Quad:  into = end - l.c1
		}
		probe := pts[min(3, len(pts) - 1)]
		if v_dot(into, into) > 1e-8 && v_dot(probe - end, probe - end) > 1e-8 {
			if v_dot(v_norm(into), v_norm(probe - end)) > math.cos(f32(deg2rad(35))) do tangent = v_norm(into)
		}
	}
	tol := smoothing / d.zoom / max(k, 1e-6)
	history_push(d)
	fit_curve(pts, tol * tol, &line, tangent)
	if closes do path_close(&line)

	out := make(Path)
	append(&out, ..n.segs[:a])
	append(&out, ..line[:])
	append(&out, ..n.segs[b:])
	delete(n.segs)
	n.segs = out
	sel_set(d, n)
	doc_changed(d)
}

// Marks the ends that can be extended, and the one a press would take.
extend_overlay :: proc(d: ^Doc, vp: Rect) {
	if tl.kind == .Extend {
		draw_handle_sq(to_screen(d, tl.free_pts[0]), true, C_SEL)
		return
	}
	ends := make([dynamic]Line_End, context.temp_allocator)
	line_ends(d, &ends)
	for e in ends do draw_handle_dot(to_screen(d, e.p), C_SEL)
	if in_rect(vp, ui.mx, ui.my) && !files_dragging() {
		if e, ok := line_end_at(d, pointer()); ok do draw_handle_sq(to_screen(d, e.p), true, C_SEL)
	}
}
