package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Stroker: turns flattened polylines into a set of simple convex pieces (segment quads, join wedges, caps) that
// are unioned by filling them together with the non-zero rule. Every piece has the same orientation.
// ---------------------------------------------------------------------------

Cap :: enum u8 {
	Butt,
	Round,
	Square,
}

Join :: enum u8 {
	Miter,
	Round,
	Bevel,
}

Stroke_Style :: struct {
	width:  f32,
	cap:    Cap,
	join:   Join,
	miter:  f32,
	dash:   [4]f32, // pairs of on / off lengths; unused when ndash == 0
	ndash:  int,
	offset: f32,
}

// Emits a piece with positive orientation.
@(private = "file")
emit :: proc(out: ^Polys, pts: ..Vec2) {
	a := len(out.pts)
	append(&out.pts, ..pts)
	if poly_area(out.pts[a:]) < 0 {
		// reverse in place
		n := len(pts)
		for i in 0 ..< n / 2 {
			out.pts[a + i], out.pts[a + n - 1 - i] = out.pts[a + n - 1 - i], out.pts[a + i]
		}
	}
	append(&out.subs, Sub{a, len(out.pts), true})
}

@(private = "file")
emit_circle :: proc(out: ^Polys, c: Vec2, r: f32, scale: f32) {
	n := clamp(int(math.ceil(math.PI / math.acos(max(1 - 0.1 / max(r * scale, 0.11), -1)))), 8, 64)
	a := len(out.pts)
	for i in 0 ..< n {
		t := f32(i) / f32(n) * 2 * math.PI
		append(&out.pts, c + Vec2{math.cos(t), math.sin(t)} * r)
	}
	if poly_area(out.pts[a:]) < 0 {
		for i in 0 ..< n / 2 {
			out.pts[a + i], out.pts[a + n - 1 - i] = out.pts[a + n - 1 - i], out.pts[a + i]
		}
	}
	append(&out.subs, Sub{a, len(out.pts), true})
}

// Splits polylines into dashes. Closed subpaths are treated as open polylines including the closing segment.
dash_polys :: proc(src: ^Polys, st: Stroke_Style, out: ^Polys) {
	total: f32
	for i in 0 ..< st.ndash do total += st.dash[i]
	if st.ndash == 0 || total <= 1e-6 {
		for sb in src.subs {
			a := len(out.pts)
			append(&out.pts, ..src.pts[sb.a:sb.b])
			append(&out.subs, Sub{a, len(out.pts), sb.closed})
		}
		return
	}
	for sb in src.subs {
		pts := make([dynamic]Vec2, context.temp_allocator)
		append(&pts, ..src.pts[sb.a:sb.b])
		if sb.closed && len(pts) > 1 do append(&pts, pts[0])
		// phase
		idx := 0
		rem := st.dash[0]
		on := true
		ph := math.mod(st.offset, total)
		if ph < 0 do ph += total
		for ph > 0 {
			if ph >= rem {
				ph -= rem
				idx = (idx + 1) % st.ndash
				rem = st.dash[idx]
				on = !on
				if rem <= 0 && ph <= 0 do break
			} else {
				rem -= ph
				ph = 0
			}
		}
		cur := -1
		for i in 0 ..< len(pts) - 1 {
			a, b := pts[i], pts[i + 1]
			seg := v_len(b - a)
			pos: f32
			for seg - pos > 1e-6 {
				step := min(rem, seg - pos)
				p0 := lerp(a, b, pos / seg)
				p1 := lerp(a, b, (pos + step) / seg)
				if on {
					if cur < 0 {
						cur = len(out.pts)
						append(&out.pts, p0)
					}
					append(&out.pts, p1)
				}
				pos += step
				rem -= step
				if rem <= 1e-6 {
					if on && cur >= 0 {
						append(&out.subs, Sub{cur, len(out.pts), false})
						cur = -1
					}
					idx = (idx + 1) % st.ndash
					rem = max(st.dash[idx], 1e-4)
					on = !on
				}
			}
		}
		if cur >= 0 do append(&out.subs, Sub{cur, len(out.pts), false})
	}
}

// Builds stroke pieces in the polylines' space. `scale` (device pixels per unit) only sets curve quality.
stroke_polys :: proc(src: ^Polys, st: Stroke_Style, scale: f32, out: ^Polys) {
	hw := st.width / 2
	if hw <= 0 do return
	for sb in src.subs {
		// drop repeated points
		pts := make([dynamic]Vec2, context.temp_allocator)
		for i in sb.a ..< sb.b {
			p := src.pts[i]
			if len(pts) == 0 || v_len(p - pts[len(pts) - 1]) > 1e-5 do append(&pts, p)
		}
		closed := sb.closed
		if closed && len(pts) > 1 && v_len(pts[0] - pts[len(pts) - 1]) <= 1e-5 do pop(&pts)
		n := len(pts)
		if n == 0 do continue
		if n == 1 {
			// a dot: only round and square caps leave a mark
			p := pts[0]
			if st.cap == .Round {
				emit_circle(out, p, hw, scale)
			} else if st.cap == .Square {
				emit(out, p + {-hw, -hw}, p + {hw, -hw}, p + {hw, hw}, p + {-hw, hw})
			}
			continue
		}
		nseg := closed ? n : n - 1
		for i in 0 ..< nseg {
			a, b := pts[i], pts[(i + 1) % n]
			d := v_norm(b - a)
			nrm := v_perp(d) * hw
			ea, eb := a, b
			if !closed && st.cap == .Square {
				if i == 0 do ea = a - d * hw
				if i == nseg - 1 do eb = b + d * hw
			}
			emit(out, ea + nrm, eb + nrm, eb - nrm, ea - nrm)
		}
		if !closed && st.cap == .Round {
			emit_circle(out, pts[0], hw, scale)
			emit_circle(out, pts[n - 1], hw, scale)
		}
		// joins
		jstart, jend := 1, n - 1
		if closed {
			jstart, jend = 0, n
		}
		for i in jstart ..< jend {
			p := pts[i]
			prev := pts[(i - 1 + n) % n]
			nxt := pts[(i + 1) % n]
			d0 := v_norm(p - prev)
			d1 := v_norm(nxt - p)
			cr := v_cross(d0, d1)
			dt := v_dot(d0, d1)
			if abs(cr) < 1e-6 && dt > 0 do continue
			if st.join == .Round {
				emit_circle(out, p, hw, scale)
				continue
			}
			// outer side is opposite to the turn direction
			side: f32 = cr > 0 ? -1 : 1
			o0 := p + v_perp(d0) * hw * side
			o1 := p + v_perp(d1) * hw * side
			if st.join == .Miter {
				// miter length ratio = 1 / sin(theta/2) where theta is the angle between segments
				cos_t := -dt
				sin_half := math.sqrt(max((1 - cos_t) / 2, 0))
				if sin_half > 1e-6 && 1 / sin_half <= st.miter {
					m := v_norm(v_perp(d0) * side + v_perp(d1) * side)
					ml := hw / max(v_dot(m, v_perp(d0) * side), 1e-6)
					emit(out, p, o0, p + m * ml, o1)
					continue
				}
			}
			emit(out, p, o0, o1)
		}
	}
}

// Whole pipeline for one path: flatten, dash, stroke. Output stays in the path's own coordinates.
stroke_path :: proc(s: []Seg, st: Stroke_Style, scale: f32, out: ^Polys) {
	flat: Polys
	defer polys_free(&flat)
	path_flatten(s, MAT_ID, 0.25 / max(scale, 1e-3), &flat)
	if st.ndash > 0 {
		dashed: Polys
		defer polys_free(&dashed)
		dash_polys(&flat, st, &dashed)
		stroke_polys(&dashed, st, scale, out)
	} else {
		stroke_polys(&flat, st, scale, out)
	}
}
