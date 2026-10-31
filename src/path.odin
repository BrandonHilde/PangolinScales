package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Paths: a list of segments. Move starts a subpath, Close ends it (closing straight to its Move).
// Quad uses c1, Cubic uses c1 and c2; `p` is always the end point.
// ---------------------------------------------------------------------------

Seg_Kind :: enum u8 {
	Move,
	Line,
	Quad,
	Cubic,
	Close,
}

Seg :: struct {
	kind:   Seg_Kind,
	p:      Vec2,
	c1, c2: Vec2,
}

Path :: [dynamic]Seg

path_move :: proc(p: ^Path, to: Vec2) {
	append(p, Seg{kind = .Move, p = to})
}

path_line :: proc(p: ^Path, to: Vec2) {
	append(p, Seg{kind = .Line, p = to})
}

path_quad :: proc(p: ^Path, c, to: Vec2) {
	append(p, Seg{kind = .Quad, p = to, c1 = c})
}

path_cubic :: proc(p: ^Path, c1, c2, to: Vec2) {
	append(p, Seg{kind = .Cubic, p = to, c1 = c1, c2 = c2})
}

path_close :: proc(p: ^Path) {
	append(p, Seg{kind = .Close})
}

path_clone :: proc(s: []Seg) -> Path {
	r := make(Path, len(s))
	copy(r[:], s)
	return r
}

// Start point of the subpath containing segment i.
subpath_start :: proc(s: []Seg, i: int) -> Vec2 {
	for k := i; k >= 0; k -= 1 {
		if s[k].kind == .Move do return s[k].p
	}
	return {}
}

// End point of the segment before i (the current point while drawing segment i).
prev_point :: proc(s: []Seg, i: int) -> Vec2 {
	if i <= 0 do return {}
	if s[i - 1].kind == .Close do return subpath_start(s, i - 1)
	return s[i - 1].p
}

path_transform :: proc(s: []Seg, m: Mat) {
	for &g in s {
		g.p = mat_apply(m, g.p)
		g.c1 = mat_apply(m, g.c1)
		g.c2 = mat_apply(m, g.c2)
	}
}

path_bounds :: proc(s: []Seg) -> Bounds {
	b := BOUNDS_EMPTY
	cur: Vec2
	start: Vec2
	for g in s {
		switch g.kind {
		case .Move:
			bounds_add(&b, g.p)
			cur, start = g.p, g.p
		case .Line:
			bounds_add(&b, g.p)
			cur = g.p
		case .Quad:
			quad_bounds(cur, g.c1, g.p, &b)
			cur = g.p
		case .Cubic:
			cubic_bounds(cur, g.c1, g.c2, g.p, &b)
			cur = g.p
		case .Close:
			cur = start
		}
	}
	return b
}

// Appends shapes ------------------------------------------------------------------------------------------

KAPPA :: 0.5522847498

path_rect :: proc(p: ^Path, x, y, w, h: f32, rx := f32(0), ry := f32(0)) {
	rx, ry := min(rx, w / 2), min(ry, h / 2)
	if rx <= 0 || ry <= 0 {
		path_move(p, {x, y})
		path_line(p, {x + w, y})
		path_line(p, {x + w, y + h})
		path_line(p, {x, y + h})
		path_close(p)
		return
	}
	kx, ky := rx * KAPPA, ry * KAPPA
	path_move(p, {x + rx, y})
	path_line(p, {x + w - rx, y})
	path_cubic(p, {x + w - rx + kx, y}, {x + w, y + ry - ky}, {x + w, y + ry})
	path_line(p, {x + w, y + h - ry})
	path_cubic(p, {x + w, y + h - ry + ky}, {x + w - rx + kx, y + h}, {x + w - rx, y + h})
	path_line(p, {x + rx, y + h})
	path_cubic(p, {x + rx - kx, y + h}, {x, y + h - ry + ky}, {x, y + h - ry})
	path_line(p, {x, y + ry})
	path_cubic(p, {x, y + ry - ky}, {x + rx - kx, y}, {x + rx, y})
	path_close(p)
}

path_ellipse :: proc(p: ^Path, cx, cy, rx, ry: f32) {
	kx, ky := rx * KAPPA, ry * KAPPA
	path_move(p, {cx + rx, cy})
	path_cubic(p, {cx + rx, cy + ky}, {cx + kx, cy + ry}, {cx, cy + ry})
	path_cubic(p, {cx - kx, cy + ry}, {cx - rx, cy + ky}, {cx - rx, cy})
	path_cubic(p, {cx - rx, cy - ky}, {cx - kx, cy - ry}, {cx, cy - ry})
	path_cubic(p, {cx + kx, cy - ry}, {cx + rx, cy - ky}, {cx + rx, cy})
	path_close(p)
}

// SVG elliptical arc from `from` to `to`, appended as cubics.
path_arc :: proc(p: ^Path, from: Vec2, rx, ry, rot_deg: f32, large, sweep: bool, to: Vec2) {
	rx, ry := abs(rx), abs(ry)
	if from == to do return
	if rx < 1e-6 || ry < 1e-6 {
		path_line(p, to)
		return
	}
	phi := deg2rad(rot_deg)
	cp, sp := math.cos(phi), math.sin(phi)
	dx, dy := (from.x - to.x) / 2, (from.y - to.y) / 2
	x1p := cp * dx + sp * dy
	y1p := -sp * dx + cp * dy
	lam := (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1 {
		s := math.sqrt(lam)
		rx *= s
		ry *= s
	}
	num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	co := den == 0 ? f32(0) : math.sqrt(max(num / den, 0))
	if large == sweep do co = -co
	cxp := co * rx * y1p / ry
	cyp := -co * ry * x1p / rx
	cx := cp * cxp - sp * cyp + (from.x + to.x) / 2
	cy := sp * cxp + cp * cyp + (from.y + to.y) / 2
	ang :: proc(ux, uy, vx, vy: f32) -> f32 {
		return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	}
	th1 := ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
	dth := ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
	if !sweep && dth > 0 do dth -= 2 * math.PI
	if sweep && dth < 0 do dth += 2 * math.PI
	n := max(int(math.ceil(abs(dth) / (math.PI / 2) - 1e-4)), 1)
	step := dth / f32(n)
	t := 4.0 / 3.0 * math.tan(step / 4)
	a := th1
	for i in 0 ..< n {
		c0, s0 := math.cos(a), math.sin(a)
		c1, s1 := math.cos(a + step), math.sin(a + step)
		e0 := Vec2{c0 - t * s0, s0 + t * c0}
		e1 := Vec2{c1 + t * s1, s1 - t * c1}
		e2 := Vec2{c1, s1}
		tp :: proc(v: Vec2, rx, ry, cp, sp, cx, cy: f32) -> Vec2 {
			x, y := v.x * rx, v.y * ry
			return {cp * x - sp * y + cx, sp * x + cp * y + cy}
		}
		end := tp(e2, rx, ry, cp, sp, cx, cy)
		if i == n - 1 do end = to
		path_cubic(p, tp(e0, rx, ry, cp, sp, cx, cy), tp(e1, rx, ry, cp, sp, cx, cy), end)
		a += step
	}
}

// Flattening ----------------------------------------------------------------------------------------------

Sub :: struct {
	a, b:   int, // pts[a:b]
	closed: bool,
}

Polys :: struct {
	pts:  [dynamic]Vec2,
	subs: [dynamic]Sub,
}

polys_free :: proc(p: ^Polys) {
	delete(p.pts)
	delete(p.subs)
}

polys_clear :: proc(p: ^Polys) {
	clear(&p.pts)
	clear(&p.subs)
}

polys_transform :: proc(p: ^Polys, m: Mat) {
	for &v in p.pts do v = mat_apply(m, v)
}

polys_bounds :: proc(p: ^Polys) -> Bounds {
	b := BOUNDS_EMPTY
	for v in p.pts do bounds_add(&b, v)
	return b
}

// Flattens `s` (optionally transformed by `m`) into polylines within `tol` of the curves.
path_flatten :: proc(s: []Seg, m: Mat, tol: f32, out: ^Polys) {
	cur: Vec2
	start: Vec2
	sub_a := -1
	finish :: proc(out: ^Polys, a: int, closed: bool) {
		if a < 0 do return
		if len(out.pts) - a >= 1 {
			append(&out.subs, Sub{a, len(out.pts), closed})
		}
	}
	for g in s {
		switch g.kind {
		case .Move:
			finish(out, sub_a, false)
			sub_a = len(out.pts)
			cur = mat_apply(m, g.p)
			start = cur
			append(&out.pts, cur)
		case .Line:
			if sub_a < 0 {
				sub_a = len(out.pts)
				append(&out.pts, cur)
			}
			cur = mat_apply(m, g.p)
			append(&out.pts, cur)
		case .Quad:
			if sub_a < 0 {
				sub_a = len(out.pts)
				append(&out.pts, cur)
			}
			c, e := mat_apply(m, g.c1), mat_apply(m, g.p)
			d := v_len(cur - 2 * c + e)
			n := clamp(int(math.ceil(math.sqrt(0.25 * d / tol))), 1, 200)
			for i in 1 ..= n do append(&out.pts, quad_at(cur, c, e, f32(i) / f32(n)))
			cur = e
		case .Cubic:
			if sub_a < 0 {
				sub_a = len(out.pts)
				append(&out.pts, cur)
			}
			c1, c2, e := mat_apply(m, g.c1), mat_apply(m, g.c2), mat_apply(m, g.p)
			d := max(v_len(cur - 2 * c1 + c2), v_len(c1 - 2 * c2 + e))
			n := clamp(int(math.ceil(math.sqrt(0.75 * d / tol))), 1, 200)
			for i in 1 ..= n do append(&out.pts, cubic_at(cur, c1, c2, e, f32(i) / f32(n)))
			cur = e
		case .Close:
			if sub_a >= 0 {
				finish(out, sub_a, true)
				sub_a = -1
				cur = start
			}
		}
	}
	finish(out, sub_a, false)
}

// Signed area of a polyline treated as closed (positive when counter-clockwise in a y-up system,
// clockwise on screen where y points down).
poly_area :: proc(pts: []Vec2) -> f32 {
	a: f32
	for i in 0 ..< len(pts) {
		j := (i + 1) % len(pts)
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	}
	return a / 2
}

// Nearest distance from p to the flattened outline.
polys_distance :: proc(p: ^Polys, pt: Vec2) -> f32 {
	best := max(f32)
	for sb in p.subs {
		n := sb.b - sb.a
		for i in 0 ..< n - 1 {
			best = min(best, dist_to_segment(pt, p.pts[sb.a + i], p.pts[sb.a + i + 1]))
		}
		if sb.closed && n > 1 {
			best = min(best, dist_to_segment(pt, p.pts[sb.b - 1], p.pts[sb.a]))
		}
		if n == 1 do best = min(best, v_len(pt - p.pts[sb.a]))
	}
	return best
}

// Point-in-shape test with the given fill rule (every subpath is implicitly closed).
polys_contains :: proc(p: ^Polys, pt: Vec2, even_odd: bool) -> bool {
	wind := 0
	for sb in p.subs {
		n := sb.b - sb.a
		for i in 0 ..< n {
			a := p.pts[sb.a + i]
			b := p.pts[sb.a + (i + 1) % n]
			if (a.y <= pt.y) != (b.y <= pt.y) {
				x := a.x + (pt.y - a.y) / (b.y - a.y) * (b.x - a.x)
				if x > pt.x do wind += b.y > a.y ? 1 : -1
			}
		}
	}
	return even_odd ? (wind & 1) != 0 : wind != 0
}
