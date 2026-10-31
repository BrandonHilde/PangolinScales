package pangolin

import "core:math"

// 2x3 affine matrix: x' = a*x + c*y + e, y' = b*x + d*y + f (same layout as SVG matrix(a b c d e f)).
Mat :: struct {
	a, b, c, d, e, f: f32,
}

MAT_ID :: Mat{1, 0, 0, 1, 0, 0}

// m * n: applies n first, then m.
mat_mul :: proc(m, n: Mat) -> Mat {
	return Mat {
		a = m.a * n.a + m.c * n.b,
		b = m.b * n.a + m.d * n.b,
		c = m.a * n.c + m.c * n.d,
		d = m.b * n.c + m.d * n.d,
		e = m.a * n.e + m.c * n.f + m.e,
		f = m.b * n.e + m.d * n.f + m.f,
	}
}

mat_apply :: proc(m: Mat, p: Vec2) -> Vec2 {
	return {m.a * p.x + m.c * p.y + m.e, m.b * p.x + m.d * p.y + m.f}
}

// Transforms a direction (no translation).
mat_apply_dir :: proc(m: Mat, p: Vec2) -> Vec2 {
	return {m.a * p.x + m.c * p.y, m.b * p.x + m.d * p.y}
}

mat_det :: proc(m: Mat) -> f32 {
	return m.a * m.d - m.b * m.c
}

mat_inv :: proc(m: Mat) -> (r: Mat, ok: bool) {
	det := mat_det(m)
	if abs(det) < 1e-12 do return MAT_ID, false
	id := 1 / det
	r.a = m.d * id
	r.b = -m.b * id
	r.c = -m.c * id
	r.d = m.a * id
	r.e = -(r.a * m.e + r.c * m.f)
	r.f = -(r.b * m.e + r.d * m.f)
	return r, true
}

mat_translate :: proc(x, y: f32) -> Mat {
	return Mat{1, 0, 0, 1, x, y}
}

mat_scale :: proc(sx, sy: f32) -> Mat {
	return Mat{sx, 0, 0, sy, 0, 0}
}

mat_rotate :: proc(rad: f32) -> Mat {
	c, s := math.cos(rad), math.sin(rad)
	return Mat{c, s, -s, c, 0, 0}
}

// Average scale factor of the matrix (for tolerances and stroke widths).
mat_scale_factor :: proc(m: Mat) -> f32 {
	return math.sqrt(abs(mat_det(m)))
}

mat_is_identity :: proc(m: Mat) -> bool {
	return m == MAT_ID
}

// Axis-aligned bounds.
Bounds :: struct {
	x0, y0, x1, y1: f32,
}

BOUNDS_EMPTY :: Bounds{max(f32), max(f32), -max(f32), -max(f32)}

bounds_empty :: proc(b: Bounds) -> bool {
	return b.x1 < b.x0 || b.y1 < b.y0
}

bounds_add :: proc(b: ^Bounds, p: Vec2) {
	b.x0 = min(b.x0, p.x)
	b.y0 = min(b.y0, p.y)
	b.x1 = max(b.x1, p.x)
	b.y1 = max(b.y1, p.y)
}

bounds_union :: proc(a, b: Bounds) -> Bounds {
	if bounds_empty(a) do return b
	if bounds_empty(b) do return a
	return Bounds{min(a.x0, b.x0), min(a.y0, b.y0), max(a.x1, b.x1), max(a.y1, b.y1)}
}

bounds_inflate :: proc(b: Bounds, d: f32) -> Bounds {
	return Bounds{b.x0 - d, b.y0 - d, b.x1 + d, b.y1 + d}
}

bounds_contains :: proc(b: Bounds, p: Vec2) -> bool {
	return p.x >= b.x0 && p.x <= b.x1 && p.y >= b.y0 && p.y <= b.y1
}

bounds_overlap :: proc(a, b: Bounds) -> bool {
	return a.x0 <= b.x1 && b.x0 <= a.x1 && a.y0 <= b.y1 && b.y0 <= a.y1
}

bounds_w :: proc(b: Bounds) -> f32 {
	return b.x1 - b.x0
}

bounds_h :: proc(b: Bounds) -> f32 {
	return b.y1 - b.y0
}

bounds_center :: proc(b: Bounds) -> Vec2 {
	return {(b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2}
}

// Bounds of the four corners of `b` after `m`.
bounds_transform :: proc(b: Bounds, m: Mat) -> Bounds {
	r := BOUNDS_EMPTY
	bounds_add(&r, mat_apply(m, {b.x0, b.y0}))
	bounds_add(&r, mat_apply(m, {b.x1, b.y0}))
	bounds_add(&r, mat_apply(m, {b.x1, b.y1}))
	bounds_add(&r, mat_apply(m, {b.x0, b.y1}))
	return r
}

// Vector helpers ------------------------------------------------------------------------------------------

v_dot :: proc(a, b: Vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

v_cross :: proc(a, b: Vec2) -> f32 {
	return a.x * b.y - a.y * b.x
}

v_len :: proc(a: Vec2) -> f32 {
	return math.sqrt(a.x * a.x + a.y * a.y)
}

v_norm :: proc(a: Vec2) -> Vec2 {
	l := v_len(a)
	if l < 1e-12 do return {}
	return a / l
}

v_perp :: proc(a: Vec2) -> Vec2 {
	return {-a.y, a.x}
}

lerp :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return a + (b - a) * t
}

// Distance from p to segment ab.
dist_to_segment :: proc(p, a, b: Vec2) -> f32 {
	ab := b - a
	l2 := v_dot(ab, ab)
	if l2 < 1e-12 do return v_len(p - a)
	t := clamp(v_dot(p - a, ab) / l2, 0, 1)
	return v_len(p - (a + ab * t))
}

quad_at :: proc(p0, c, p1: Vec2, t: f32) -> Vec2 {
	mt := 1 - t
	return p0 * (mt * mt) + c * (2 * mt * t) + p1 * (t * t)
}

cubic_at :: proc(p0, c1, c2, p1: Vec2, t: f32) -> Vec2 {
	mt := 1 - t
	return p0 * (mt * mt * mt) + c1 * (3 * mt * mt * t) + c2 * (3 * mt * t * t) + p1 * (t * t * t)
}

// Exact bounds of a cubic (extrema from the derivative's roots).
cubic_bounds :: proc(p0, c1, c2, p1: Vec2, b: ^Bounds) {
	bounds_add(b, p0)
	bounds_add(b, p1)
	for axis in 0 ..< 2 {
		a0, a1, a2, a3 := p0[axis], c1[axis], c2[axis], p1[axis]
		// derivative: 3[(a1-a0)(1-t)^2 + 2(a2-a1)(1-t)t + (a3-a2)t^2]
		qa := -a0 + 3 * a1 - 3 * a2 + a3
		qb := 2 * (a0 - 2 * a1 + a2)
		qc := a1 - a0
		roots: [2]f32
		n := 0
		if abs(qa) < 1e-9 {
			if abs(qb) > 1e-9 {
				roots[0] = -qc / qb
				n = 1
			}
		} else {
			disc := qb * qb - 4 * qa * qc
			if disc >= 0 {
				sq := math.sqrt(disc)
				roots[0] = (-qb + sq) / (2 * qa)
				roots[1] = (-qb - sq) / (2 * qa)
				n = 2
			}
		}
		for i in 0 ..< n {
			t := roots[i]
			if t > 0 && t < 1 do bounds_add(b, cubic_at(p0, c1, c2, p1, t))
		}
	}
}

quad_bounds :: proc(p0, c, p1: Vec2, b: ^Bounds) {
	bounds_add(b, p0)
	bounds_add(b, p1)
	for axis in 0 ..< 2 {
		d := p0[axis] - 2 * c[axis] + p1[axis]
		if abs(d) < 1e-9 do continue
		t := (p0[axis] - c[axis]) / d
		if t > 0 && t < 1 do bounds_add(b, quad_at(p0, c, p1, t))
	}
}

deg2rad :: proc(d: f32) -> f32 {
	return d * math.PI / 180
}
