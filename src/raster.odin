package pangolin

import "core:math"
import "core:slice"

// ---------------------------------------------------------------------------
// Anti-aliased scanline polygon fill. Each pixel row is sampled at SUB sub-scanlines; every sub-scanline
// contributes exact horizontal coverage, so edges are smooth in both directions.
// ---------------------------------------------------------------------------

SUB :: 16

Fill_Rule :: enum u8 {
	Non_Zero,
	Even_Odd,
}

Edge :: struct {
	x0, y0, y1: f32, // y0 < y1
	slope:      f32, // dx/dy
	dir:        i32,
}

Crossing :: struct {
	x:   f32,
	dir: i32,
}

Raster :: struct {
	w, h:   int,
	cover:  []f32, // w*h coverage, zero between calls
	delta:  []f32, // w+2 scratch for one row
	edges:  [dynamic]Edge,
	active: [dynamic]int,
	cross:  [dynamic]Crossing,
	// bounds of the last fill (pixels, half open); empty when x1 <= x0
	x0, y0, x1, y1: int,
}

raster_init :: proc(r: ^Raster, w, h: int) {
	r.w, r.h = w, h
	delete(r.cover)
	delete(r.delta)
	r.cover = make([]f32, w * h)
	r.delta = make([]f32, w + 2)
}

raster_free :: proc(r: ^Raster) {
	delete(r.cover)
	delete(r.delta)
	delete(r.edges)
	delete(r.active)
	delete(r.cross)
	r^ = {}
}

edge_less :: proc(a, b: Edge) -> bool {
	return a.y0 < b.y0
}

// Fills the polygons into r.cover (clipped to the raster). Call raster_clear_last when done with the coverage.
raster_fill :: proc(r: ^Raster, p: ^Polys, rule: Fill_Rule) {
	r.x0, r.y0, r.x1, r.y1 = 0, 0, 0, 0
	clear(&r.edges)
	bx0, by0, bx1, by1 := max(f32), max(f32), -max(f32), -max(f32)
	for sb in p.subs {
		n := sb.b - sb.a
		if n < 2 do continue
		for i in 0 ..< n {
			a := p.pts[sb.a + i]
			b := p.pts[sb.a + (i + 1) % n]
			if a.y == b.y || math.is_nan(a.x) || math.is_nan(b.x) || math.is_nan(a.y) || math.is_nan(b.y) do continue
			bx0 = min(bx0, min(a.x, b.x))
			bx1 = max(bx1, max(a.x, b.x))
			by0 = min(by0, min(a.y, b.y))
			by1 = max(by1, max(a.y, b.y))
			e: Edge
			if a.y < b.y {
				e = Edge{a.x, a.y, b.y, (b.x - a.x) / (b.y - a.y), 1}
			} else {
				e = Edge{b.x, b.y, a.y, (a.x - b.x) / (a.y - b.y), -1}
			}
			append(&r.edges, e)
		}
	}
	if len(r.edges) == 0 do return
	px0 := max(int(math.floor(bx0)), 0)
	px1 := min(int(math.ceil(bx1)) + 1, r.w)
	py0 := max(int(math.floor(by0)), 0)
	py1 := min(int(math.ceil(by1)), r.h)
	if px1 <= px0 || py1 <= py0 do return
	r.x0, r.y0, r.x1, r.y1 = px0, py0, px1, py1
	slice.sort_by(r.edges[:], edge_less)

	clear(&r.active)
	next := 0
	inv := 1 / f32(SUB)
	for y in py0 ..< py1 {
		fy := f32(y)
		// activate edges starting before the end of this row, drop finished ones
		for next < len(r.edges) && r.edges[next].y0 < fy + 1 {
			append(&r.active, next)
			next += 1
		}
		k := 0
		for i in 0 ..< len(r.active) {
			if r.edges[r.active[i]].y1 > fy {
				r.active[k] = r.active[i]
				k += 1
			}
		}
		resize(&r.active, k)
		if k == 0 do continue

		for i in px0 ..< px1 + 2 do r.delta[i] = 0
		for s in 0 ..< SUB {
			ys := fy + (f32(s) + 0.5) * inv
			clear(&r.cross)
			for ei in r.active {
				e := &r.edges[ei]
				if ys >= e.y0 && ys < e.y1 {
					append(&r.cross, Crossing{e.x0 + (ys - e.y0) * e.slope, e.dir})
				}
			}
			// insertion sort: crossing lists are short
			c := r.cross[:]
			for i in 1 ..< len(c) {
				v := c[i]
				j := i - 1
				for j >= 0 && c[j].x > v.x {
					c[j + 1] = c[j]
					j -= 1
				}
				c[j + 1] = v
			}
			wind: i32
			for i in 0 ..< len(c) - 1 {
				wind += c[i].dir
				inside := rule == .Non_Zero ? wind != 0 : (wind & 1) != 0
				if inside do add_span(r, c[i].x, c[i + 1].x, inv)
			}
		}
		// resolve the row
		acc: f32
		row := r.cover[y * r.w:]
		for x in px0 ..< px1 {
			acc += r.delta[x]
			row[x] += acc
		}
	}
}

@(private = "file")
add_span :: proc(r: ^Raster, xa, xb, wgt: f32) {
	xa := clamp(xa, f32(r.x0), f32(r.x1))
	xb := clamp(xb, f32(r.x0), f32(r.x1))
	if xb <= xa do return
	ia, ib := int(xa), int(xb)
	if ia == ib {
		r.delta[ia] += (xb - xa) * wgt
		r.delta[ia + 1] -= (xb - xa) * wgt
		return
	}
	fa := f32(ia + 1) - xa
	r.delta[ia] += fa * wgt
	r.delta[ia + 1] += (1 - fa) * wgt
	// coverage of whole pixels between ia+1 and ib, then the partial last pixel
	r.delta[ib] -= (1 - (xb - f32(ib))) * wgt
	r.delta[ib + 1] -= (xb - f32(ib)) * wgt
}

// Zeroes the area touched by the last fill.
raster_clear_last :: proc(r: ^Raster) {
	for y in r.y0 ..< r.y1 {
		row := r.cover[y * r.w:]
		for x in r.x0 ..< r.x1 do row[x] = 0
	}
}

// Paint sources -------------------------------------------------------------------------------------------

MAX_STOPS :: 8

Stop :: struct {
	t:     f32,
	color: Color,
}

Paint_Kind :: enum u8 {
	None,
	Solid,
	Linear,
	Radial,
}

// Gradient geometry is in the owning object's local space.
Paint :: struct {
	kind:   Paint_Kind,
	color:  Color,
	p0, p1: Vec2, // linear: start / end; radial: centre / (radius, 0)
	nstops: int,
	stops:  [MAX_STOPS]Stop,
	spread: u8, // 0 pad, 1 reflect, 2 repeat
}

paint_solid :: proc(c: Color) -> Paint {
	return Paint{kind = .Solid, color = c}
}

paint_none :: proc() -> Paint {
	return Paint{}
}

lerp_color :: proc(a, b: Color, t: f32) -> Color {
	r: Color
	for i in 0 ..< 4 do r[i] = u8(clamp(f32(a[i]) + (f32(b[i]) - f32(a[i])) * t + 0.5, 0, 255))
	return r
}

paint_stop_color :: proc(p: ^Paint, t: f32) -> Color {
	if p.nstops == 0 do return p.color
	if t <= p.stops[0].t do return p.stops[0].color
	for i in 1 ..< p.nstops {
		if t <= p.stops[i].t {
			a, b := p.stops[i - 1], p.stops[i]
			d := b.t - a.t
			return lerp_color(a.color, b.color, d <= 1e-6 ? 1 : (t - a.t) / d)
		}
	}
	return p.stops[p.nstops - 1].color
}

// Evaluated paint for one object: `inv` maps device pixels to the object's local space.
Shader :: struct {
	paint:   ^Paint,
	inv:     Mat,
	opacity: f32,
}

shader_at :: proc(s: ^Shader, x, y: f32) -> Color {
	p := s.paint
	if p.kind == .Solid do return p.color
	q := mat_apply(s.inv, {x, y})
	t: f32
	#partial switch p.kind {
	case .Linear:
		d := p.p1 - p.p0
		l2 := v_dot(d, d)
		t = l2 < 1e-9 ? 0 : v_dot(q - p.p0, d) / l2
	case .Radial:
		r := p.p1.x
		t = r < 1e-9 ? 0 : v_len(q - p.p0) / r
	}
	switch p.spread {
	case 1:
		t = abs(math.mod(t, 2))
		if t > 1 do t = 2 - t
	case 2:
		t -= math.floor(t)
	case:
		t = clamp(t, 0, 1)
	}
	return paint_stop_color(p, t)
}

// Source-over composite of the last fill into the framebuffer.
raster_composite :: proc(r: ^Raster, fb: []Color, sh: ^Shader) {
	solid := sh.paint.kind == .Solid
	sc := sh.paint.color
	for y in r.y0 ..< r.y1 {
		cov := r.cover[y * r.w:]
		dst := fb[y * r.w:]
		for x in r.x0 ..< r.x1 {
			c := cov[x]
			if c <= 0.002 do continue
			if c > 1 do c = 1
			col := sc
			if !solid do col = shader_at(sh, f32(x) + 0.5, f32(y) + 0.5)
			a := c * sh.opacity * f32(col.a) / 255
			if a <= 0 do continue
			d := dst[x]
			da := f32(d.a) / 255
			oa := a + da * (1 - a)
			if oa <= 0 do continue
			// non-premultiplied "over"
			for k in 0 ..< 3 {
				dst[x][k] = u8(clamp((f32(col[k]) * a + f32(d[k]) * da * (1 - a)) / oa + 0.5, 0, 255))
			}
			dst[x].a = u8(clamp(oa * 255 + 0.5, 0, 255))
		}
	}
}
