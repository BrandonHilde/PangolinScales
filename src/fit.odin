package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Least-squares Bezier curve fitting for freehand strokes (Schneider, "An Algorithm for Automatically Fitting
// Digitized Curves"). Appends cubic segments to `out`; the caller has already moved to pts[0].
// ---------------------------------------------------------------------------

// `start_tangent`, if given, is the direction the curve leaves pts[0] in, so it can carry on from another one.
// `end_tangent`, if given, points back into the curve from its last point, so another one can carry on from it.
fit_curve :: proc(pts: []Vec2, err: f32, out: ^Path, start_tangent := Vec2{}, end_tangent := Vec2{}) {
	// drop repeated points
	d := make([dynamic]Vec2, context.temp_allocator)
	for p in pts {
		if len(d) == 0 || v_len(p - d[len(d) - 1]) > 1e-4 do append(&d, p)
	}
	if len(d) < 2 do return
	t1 := start_tangent != {} ? start_tangent : v_norm(d[1] - d[0])
	t2 := end_tangent != {} ? end_tangent : v_norm(d[len(d) - 2] - d[len(d) - 1])
	fit_cubic(d[:], t1, t2, err, out)
}

@(private = "file")
fit_cubic :: proc(d: []Vec2, t1, t2: Vec2, err: f32, out: ^Path) {
	n := len(d)
	if n == 2 {
		dist := v_len(d[1] - d[0]) / 3
		path_cubic(out, d[0] + t1 * dist, d[1] + t2 * dist, d[1])
		return
	}
	u := chord_params(d)
	bez := gen_bezier(d, u, t1, t2)
	max_err, split := max_error(d, bez, u)
	if max_err < err {
		path_cubic(out, bez[1], bez[2], bez[3])
		return
	}
	if max_err < err * 4 {
		for _ in 0 ..< 4 {
			u2 := reparam(d, u, bez)
			bez = gen_bezier(d, u2, t1, t2)
			max_err, split = max_error(d, bez, u2)
			if max_err < err {
				path_cubic(out, bez[1], bez[2], bez[3])
				return
			}
			u = u2
		}
	}
	split = clamp(split, 1, n - 2)
	tc := v_norm(d[split - 1] - d[split + 1])
	fit_cubic(d[:split + 1], t1, tc, err, out)
	fit_cubic(d[split:], -tc, t2, err, out)
}

@(private = "file")
chord_params :: proc(d: []Vec2) -> []f32 {
	u := make([]f32, len(d), context.temp_allocator)
	for i in 1 ..< len(d) do u[i] = u[i - 1] + v_len(d[i] - d[i - 1])
	total := u[len(d) - 1]
	for i in 1 ..< len(d) do u[i] = total > 0 ? u[i] / total : f32(i) / f32(len(d) - 1)
	return u
}

@(private = "file")
gen_bezier :: proc(d: []Vec2, u: []f32, t1, t2: Vec2) -> [4]Vec2 {
	n := len(d)
	p0, p3 := d[0], d[n - 1]
	c: [2][2]f32
	x: [2]f32
	for i in 0 ..< n {
		t := u[i]
		mt := 1 - t
		b0, b1, b2, b3 := mt * mt * mt, 3 * mt * mt * t, 3 * mt * t * t, t * t * t
		a1, a2 := t1 * b1, t2 * b2
		c[0][0] += v_dot(a1, a1)
		c[0][1] += v_dot(a1, a2)
		c[1][1] += v_dot(a2, a2)
		tmp := d[i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
		x[0] += v_dot(a1, tmp)
		x[1] += v_dot(a2, tmp)
	}
	c[1][0] = c[0][1]
	det := c[0][0] * c[1][1] - c[1][0] * c[0][1]
	seg := v_len(p3 - p0)
	alpha1, alpha2: f32
	if abs(det) > 1e-12 {
		alpha1 = (x[0] * c[1][1] - x[1] * c[0][1]) / det
		alpha2 = (c[0][0] * x[1] - c[1][0] * x[0]) / det
	}
	eps := 1e-6 * seg
	// The error is only measured at the points, and a very long handle can loop far out between them while passing
	// close to all of them. A handle longer than the stretch it covers is never a good fit.
	arc: f32
	for i in 1 ..< n do arc += v_len(d[i] - d[i - 1])
	if alpha1 < eps || alpha2 < eps || alpha1 > arc || alpha2 > arc {
		alpha1 = seg / 3
		alpha2 = alpha1
	}
	return {p0, p0 + t1 * alpha1, p3 + t2 * alpha2, p3}
}

@(private = "file")
max_error :: proc(d: []Vec2, b: [4]Vec2, u: []f32) -> (f32, int) {
	best: f32
	idx := len(d) / 2
	for i in 1 ..< len(d) - 1 {
		p := cubic_at(b[0], b[1], b[2], b[3], u[i])
		dd := v_dot(p - d[i], p - d[i])
		if dd >= best {
			best = dd
			idx = i
		}
	}
	return best, idx
}

@(private = "file")
reparam :: proc(d: []Vec2, u: []f32, b: [4]Vec2) -> []f32 {
	r := make([]f32, len(u), context.temp_allocator)
	for i in 0 ..< len(u) {
		t := u[i]
		mt := 1 - t
		p := cubic_at(b[0], b[1], b[2], b[3], t)
		// first and second derivative
		d1 := 3 * (mt * mt * (b[1] - b[0]) + 2 * mt * t * (b[2] - b[1]) + t * t * (b[3] - b[2]))
		d2 := 6 * (mt * (b[2] - 2 * b[1] + b[0]) + t * (b[3] - 2 * b[2] + b[1]))
		diff := p - d[i]
		num := v_dot(diff, d1)
		den := v_dot(d1, d1) + v_dot(diff, d2)
		r[i] = abs(den) < 1e-12 ? t : clamp(t - num / den, 0, 1)
	}
	return r
}

// Ramer-Douglas-Peucker simplification of a polyline.
simplify_poly :: proc(pts: []Vec2, tol: f32, out: ^[dynamic]Vec2) {
	if len(pts) < 3 {
		append(out, ..pts)
		return
	}
	best: f32
	bi := 0
	for i in 1 ..< len(pts) - 1 {
		dd := dist_to_segment(pts[i], pts[0], pts[len(pts) - 1])
		if dd > best {
			best = dd
			bi = i
		}
	}
	if best <= tol {
		append(out, pts[0], pts[len(pts) - 1])
		return
	}
	simplify_poly(pts[:bi + 1], tol, out)
	pop(out)
	simplify_poly(pts[bi:], tol, out)
}

_ :: math
