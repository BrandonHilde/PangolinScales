package pangolin

import "core:math"
import "core:slice"

// ---------------------------------------------------------------------------
// Boolean operations on closed paths (union, intersect, subtract, exclude, remove overlap). Port of ScalarCanvas's
// PathBoolean:
//   1. flatten curves to edges on an integer grid, tagging each edge with its source segment and t-range
//   2. split edges at all mutual intersections, merge coincident edges
//   3. keep edges where the result's inside / outside changes (non-zero winding of each operand on both sides)
//   4. link kept edges into loops
//   5. rebuild curves from the tagged source segments, so untouched outlines keep their original curves
// Every subpath is treated as closed, and each operand is filled with the non-zero rule.
// ---------------------------------------------------------------------------

BOOL_SCALE :: 256

Bool_Op :: enum {
	Union,
	Intersect,
	Subtract,
	Exclude,
}

bool_pred :: proc(op: Bool_Op, a, b: bool) -> bool {
	switch op {
	case .Union:     return a || b
	case .Intersect: return a && b
	case .Subtract:  return a && !b
	case .Exclude:   return a != b
	}
	return false
}

@(private = "file")
Bsrc :: struct {
	n:       int, // control points: 2 line, 3 quad, 4 cubic
	pts:     [4][2]f64,
	contour: int,
}

@(private = "file")
Bedge :: struct {
	ax, ay, bx, by: i64,
	op, src:        int,
	t0, t1:         f64,
}

@(private = "file")
Btag :: struct {
	src:    int,
	t0, t1: f64,
}

@(private = "file")
Brec :: struct {
	ax, ay, bx, by: i64,
	dA, dB, count:  int,
	tag:            Btag,
}

@(private = "file")
Bout :: struct {
	ax, ay, bx, by: i64,
	tag:            Btag,
	used:           bool,
}

bez_point :: proc(pts: [][2]f64, t: f64) -> [2]f64 {
	tmp: [4][2]f64
	n := len(pts)
	for i in 0 ..< n do tmp[i] = pts[i]
	for k := n; k > 1; k -= 1 {
		for i in 0 ..< k - 1 {
			tmp[i] = tmp[i] + (tmp[i + 1] - tmp[i]) * t
		}
	}
	return tmp[0]
}

// Control points of the part of a Bezier between t0 and t1 (reversed when t0 > t1).
bez_slice :: proc(pts: [][2]f64, t0, t1: f64) -> [4][2]f64 {
	if t0 > t1 {
		r := bez_slice(pts, t1, t0)
		n := len(pts)
		for i in 0 ..< n / 2 do r[i], r[n - 1 - i] = r[n - 1 - i], r[i]
		return r
	}
	n := len(pts)
	cur: [4][2]f64
	for i in 0 ..< n do cur[i] = pts[i]
	// split at t0, keep the right part
	split :: proc(c: [4][2]f64, n: int, t: f64) -> (left, right: [4][2]f64) {
		tmp := c
		for k in 0 ..< n {
			left[k] = tmp[0]
			right[n - 1 - k] = tmp[n - 1 - k]
			for i in 0 ..< n - 1 - k do tmp[i] = tmp[i] + (tmp[i + 1] - tmp[i]) * t
		}
		return
	}
	if t0 > 0 {
		_, cur = split(cur, n, t0)
	}
	t := t0 < 1 ? (t1 - t0) / (1 - t0) : 1
	if t < 1 {
		cur, _ = split(cur, n, t)
	}
	return cur
}

@(private = "file")
flatten_operand :: proc(path: []Seg, operand: int, contour_id: ^int, sources: ^[dynamic]Bsrc, edges: ^[dynamic]Bedge) {
	add_src :: proc(sources: ^[dynamic]Bsrc, edges: ^[dynamic]Bedge, operand, contour: int, pts: [][2]f64) {
		s := Bsrc{n = len(pts), contour = contour}
		for p, i in pts do s.pts[i] = p
		append(sources, s)
		src := len(sources) - 1
		steps := 1
		if len(pts) > 2 {
			l: f64
			for i in 1 ..< len(pts) {
				dx, dy := pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
				l += math.sqrt(dx * dx + dy * dy)
			}
			steps = clamp(int(math.ceil(math.sqrt(l) * 2)), 6, 128)
		}
		prev_x, prev_y: i64
		prev_t: f64
		have_prev := false
		last := -1
		for i in 0 ..= steps {
			t := f64(i) / f64(steps)
			p: [2]f64
			if i == 0 do p = pts[0]
			else if i == steps do p = pts[len(pts) - 1]
			else do p = bez_point(pts, t)
			qx, qy := i64(math.round(p[0] * BOOL_SCALE)), i64(math.round(p[1] * BOOL_SCALE))
			if !have_prev {
				prev_x, prev_y, prev_t, have_prev = qx, qy, t, true
				continue
			}
			if qx == prev_x && qy == prev_y {
				if i == steps && last >= 0 do edges[last].t1 = 1
				continue
			}
			append(edges, Bedge{prev_x, prev_y, qx, qy, operand, src, prev_t, t})
			last = len(edges) - 1
			prev_x, prev_y, prev_t = qx, qy, t
		}
	}
	cur, start: [2]f64
	open := false
	has_geom := false
	close_sub :: proc(sources: ^[dynamic]Bsrc, edges: ^[dynamic]Bedge, operand: int, cid: int, cur, start: [2]f64, has_geom: bool) {
		if has_geom && (cur[0] != start[0] || cur[1] != start[1]) {
			add_src(sources, edges, operand, cid, {cur, start})
		}
	}
	for g in path {
		switch g.kind {
		case .Move:
			if open do close_sub(sources, edges, operand, contour_id^, cur, start, has_geom)
			if open do contour_id^ += 1
			cur = {f64(g.p.x), f64(g.p.y)}
			start = cur
			open = true
			has_geom = false
		case .Line:
			np := [2]f64{f64(g.p.x), f64(g.p.y)}
			if np != cur do add_src(sources, edges, operand, contour_id^, {cur, np})
			cur = np
			has_geom = true
		case .Quad:
			np := [2]f64{f64(g.p.x), f64(g.p.y)}
			add_src(sources, edges, operand, contour_id^, {cur, {f64(g.c1.x), f64(g.c1.y)}, np})
			cur = np
			has_geom = true
		case .Cubic:
			np := [2]f64{f64(g.p.x), f64(g.p.y)}
			add_src(sources, edges, operand, contour_id^, {cur, {f64(g.c1.x), f64(g.c1.y)}, {f64(g.c2.x), f64(g.c2.y)}, np})
			cur = np
			has_geom = true
		case .Close:
			if open {
				close_sub(sources, edges, operand, contour_id^, cur, start, has_geom)
				contour_id^ += 1
				cur = start
				open = false
				has_geom = false
			}
		}
	}
	if open {
		close_sub(sources, edges, operand, contour_id^, cur, start, has_geom)
		contour_id^ += 1
	}
}

@(private = "file")
Split :: struct {
	s:    f64,
	x, y: i64,
}

@(private = "file")
add_split :: proc(list: ^[dynamic]Split, e: ^Bedge, x, y: i64) {
	if (x == e.ax && y == e.ay) || (x == e.bx && y == e.by) do return
	rx, ry := f64(e.bx - e.ax), f64(e.by - e.ay)
	s := (f64(x - e.ax) * rx + f64(y - e.ay) * ry) / (rx * rx + ry * ry)
	if s <= 0 || s >= 1 do return
	append(list, Split{s, x, y})
}

@(private = "file")
intersect_edges :: proc(e, f: ^Bedge, se, sf: ^[dynamic]Split) {
	rx, ry := f64(e.bx - e.ax), f64(e.by - e.ay)
	qx, qy := f64(f.bx - f.ax), f64(f.by - f.ay)
	wx, wy := f64(f.ax - e.ax), f64(f.ay - e.ay)
	d := rx * qy - ry * qx
	if d == 0 {
		if wx * ry - wy * rx != 0 do return
		add_split(se, e, f.ax, f.ay)
		add_split(se, e, f.bx, f.by)
		add_split(sf, f, e.ax, e.ay)
		add_split(sf, f, e.bx, e.by)
		return
	}
	s := (wx * qy - wy * qx) / d
	u := (wx * ry - wy * rx) / d
	es := 0.75 / math.sqrt(rx * rx + ry * ry)
	eu := 0.75 / math.sqrt(qx * qx + qy * qy)
	if s < -es || s > 1 + es || u < -eu || u > 1 + eu do return
	x, y: i64
	switch {
	case u <= eu:     x, y = f.ax, f.ay
	case u >= 1 - eu: x, y = f.bx, f.by
	case s <= es:     x, y = e.ax, e.ay
	case s >= 1 - es: x, y = e.bx, e.by
	case:
		x = i64(math.round(f64(e.ax) + s * rx))
		y = i64(math.round(f64(e.ay) + s * ry))
	}
	add_split(se, e, x, y)
	add_split(sf, f, x, y)
}

@(private = "file")
split_edges :: proc(edges: []Bedge) -> (pieces: [dynamic]Bedge, did_split: bool) {
	n := len(edges)
	splits := make([][dynamic]Split, n, context.temp_allocator)
	for &s in splits do s = make([dynamic]Split, context.temp_allocator) // (left as zero values they would go on the heap)
	order := make([]int, n, context.temp_allocator)
	for i in 0 ..< n do order[i] = i
	min_x := make([]i64, n, context.temp_allocator)
	max_x := make([]i64, n, context.temp_allocator)
	for e, i in edges {
		min_x[i], max_x[i] = min(e.ax, e.bx), max(e.ax, e.bx)
	}
	sort_min_x = min_x
	slice.sort_by(order, proc(a, b: int) -> bool { return sort_min_x[a] < sort_min_x[b] })
	for oi in 0 ..< n {
		i := order[oi]
		e := &edges[i]
		e_min_y, e_max_y := min(e.ay, e.by), max(e.ay, e.by)
		for oj in oi + 1 ..< n {
			j := order[oj]
			if min_x[j] > max_x[i] + 1 do break
			f := &edges[j]
			if max(f.ay, f.by) < e_min_y - 1 || min(f.ay, f.by) > e_max_y + 1 do continue
			intersect_edges(e, f, &splits[i], &splits[j])
		}
	}
	for e, i in edges {
		list := &splits[i]
		if len(list) == 0 {
			append(&pieces, e)
			continue
		}
		did_split = true
		slice.sort_by(list[:], proc(a, b: Split) -> bool { return a.s < b.s })
		ax, ay, t0 := e.ax, e.ay, e.t0
		for sp in list {
			if sp.x == ax && sp.y == ay do continue
			t := e.t0 + sp.s * (e.t1 - e.t0)
			append(&pieces, Bedge{ax, ay, sp.x, sp.y, e.op, e.src, t0, t})
			ax, ay, t0 = sp.x, sp.y, t
		}
		if ax != e.bx || ay != e.by do append(&pieces, Bedge{ax, ay, e.bx, e.by, e.op, e.src, t0, e.t1})
	}
	return
}

@(private = "file")
sort_min_x: []i64

@(private = "file")
merge_edges :: proc(pieces: []Bedge) -> (recs: [dynamic]Brec, merged: bool) {
	idx := make(map[[4]i64]int, len(pieces), context.temp_allocator)
	for p in pieces {
		forward := p.ax < p.bx || (p.ax == p.bx && p.ay < p.by)
		ax, ay, bx, by := p.ax, p.ay, p.bx, p.by
		if !forward do ax, ay, bx, by = p.bx, p.by, p.ax, p.ay
		key := [4]i64{ax, ay, bx, by}
		ri, found := idx[key]
		if !found {
			tag := forward ? Btag{p.src, p.t0, p.t1} : Btag{p.src, p.t1, p.t0}
			append(&recs, Brec{ax = ax, ay = ay, bx = bx, by = by, tag = tag})
			ri = len(recs) - 1
			idx[key] = ri
		} else {
			merged = true
		}
		sign := forward ? 1 : -1
		if p.op == 0 do recs[ri].dA += sign
		else do recs[ri].dB += sign
		recs[ri].count += 1
	}
	return
}

@(private = "file")
classify :: proc(recs: []Brec, op: Bool_Op, a_even_odd: bool) -> (out: [dynamic]Bout, changed: bool) {
	n := len(recs)
	in_a :: proc(w: int, even_odd: bool) -> bool {
		return even_odd ? w & 1 != 0 : w != 0
	}
	// bucket by y extent so ray casts only look at edges that can cross the ray
	min_y, max_y := max(i64), min(i64)
	for r in recs {
		min_y = min(min_y, min(r.ay, r.by))
		max_y = max(max_y, max(r.ay, r.by))
	}
	bands := clamp(n / 4, 1, 512)
	size := max(f64(max_y - min_y) / f64(bands), 1)
	band_of :: proc(v: i64, min_y: i64, size: f64, bands: int) -> int {
		return clamp(int(math.floor(f64(v - min_y) / size)), 0, bands - 1)
	}
	buckets := make([][dynamic]int, bands, context.temp_allocator)
	for &b in buckets do b = make([dynamic]int, context.temp_allocator)
	for r, i in recs {
		for b in band_of(min(r.ay, r.by), min_y, size, bands) ..= band_of(max(r.ay, r.by), min_y, size, bands) {
			append(&buckets[b], i)
		}
	}
	// x-bands for horizontal edges
	min_x, max_x := max(i64), min(i64)
	for r in recs {
		min_x = min(min_x, min(r.ax, r.bx))
		max_x = max(max_x, max(r.ax, r.bx))
	}
	xsize := max(f64(max_x - min_x) / f64(bands), 1)
	xbuckets := make([][dynamic]int, bands, context.temp_allocator)
	for &b in xbuckets do b = make([dynamic]int, context.temp_allocator)
	for r, i in recs {
		for b in band_of(min(r.ax, r.bx), min_x, xsize, bands) ..= band_of(max(r.ax, r.bx), min_x, xsize, bands) {
			append(&xbuckets[b], i)
		}
	}
	for e, ei in recs {
		if e.dA == 0 && e.dB == 0 {
			changed = true
			continue
		}
		mx, my := f64(e.ax + e.bx) / 2, f64(e.ay + e.by) / 2
		wA, wB := 0, 0
		cE: int
		neg_is_left: bool
		if e.ay != e.by {
			for gi in buckets[band_of(i64(math.floor(my)), min_y, size, bands)] {
				g := recs[gi]
				if gi == ei || (f64(g.ay) <= my) == (f64(g.by) <= my) do continue
				xi := f64(g.ax) + (my - f64(g.ay)) * f64(g.bx - g.ax) / f64(g.by - g.ay)
				if xi <= mx do continue
				s := g.by > g.ay ? 1 : -1
				wA += s * g.dA
				wB += s * g.dB
			}
			cE = e.by > e.ay ? 1 : -1
			neg_is_left = e.by > e.ay
		} else {
			for gi in xbuckets[band_of(i64(math.floor(mx)), min_x, xsize, bands)] {
				g := recs[gi]
				if gi == ei || (f64(g.ax) <= mx) == (f64(g.bx) <= mx) do continue
				yi := f64(g.ay) + (mx - f64(g.ax)) * f64(g.by - g.ay) / f64(g.bx - g.ax)
				if yi <= my do continue
				s := g.bx < g.ax ? 1 : -1
				wA += s * g.dA
				wB += s * g.dB
			}
			cE = e.bx < e.ax ? 1 : -1
			neg_is_left = e.bx < e.ax
		}
		in_neg := bool_pred(op, in_a(wA + cE * e.dA, a_even_odd), wB + cE * e.dB != 0)
		in_pos := bool_pred(op, in_a(wA, a_even_odd), wB != 0)
		if in_neg == in_pos {
			changed = true
			continue
		}
		interior_left := in_neg ? neg_is_left : !neg_is_left
		original_forward := e.dA + e.dB > 0
		if e.count != 1 || interior_left == original_forward do changed = true
		if interior_left {
			append(&out, Bout{ax = e.bx, ay = e.by, bx = e.ax, by = e.ay, tag = Btag{e.tag.src, e.tag.t1, e.tag.t0}})
		} else {
			append(&out, Bout{ax = e.ax, ay = e.ay, bx = e.bx, by = e.by, tag = e.tag})
		}
	}
	return
}

@(private = "file")
link_loops :: proc(edges: []Bout) -> [dynamic][dynamic]int {
	outgoing := make(map[[2]i64][dynamic]int, len(edges), context.temp_allocator)
	for e, i in edges {
		k := [2]i64{e.ax, e.ay}
		l, had := outgoing[k]
		if !had do l = make([dynamic]int, context.temp_allocator)
		append(&l, i)
		outgoing[k] = l
	}
	loops: [dynamic][dynamic]int
	for fi in 0 ..< len(edges) {
		if edges[fi].used do continue
		loop: [dynamic]int
		start := [2]i64{edges[fi].ax, edges[fi].ay}
		cur := fi
		for {
			edges[cur].used = true
			append(&loop, cur)
			k := [2]i64{edges[cur].bx, edges[cur].by}
			if k == start do break
			cands := outgoing[k]
			back := math.atan2(f64(edges[cur].ay - edges[cur].by), f64(edges[cur].ax - edges[cur].bx))
			best := -1
			best_delta := math.INF_F64
			for ci in cands {
				c := edges[ci]
				if c.used do continue
				delta := math.atan2(f64(c.by - c.ay), f64(c.bx - c.ax)) - back
				for delta <= 1e-12 do delta += math.PI * 2
				for delta > math.PI * 2 do delta -= math.PI * 2
				if delta < best_delta {
					best_delta = delta
					best = ci
				}
			}
			if best < 0 do break
			cur = best
		}
		append(&loops, loop)
	}
	return loops
}

@(private = "file")
is_end :: proc(t: f64) -> bool {
	return t == 0 || t == 1
}

@(private = "file")
loop_to_path :: proc(loop: []int, edges: []Bout, sources: []Bsrc, out: ^Path) {
	area: f64
	for ei in loop {
		e := edges[ei]
		area += f64(e.ax) * f64(e.by) - f64(e.bx) * f64(e.ay)
	}
	if abs(area / 2) / (BOOL_SCALE * BOOL_SCALE) < 1 do return
	n := len(loop)
	contiguous :: proc(a, b: Bout) -> bool {
		return a.tag.src == b.tag.src && a.tag.t1 == b.tag.t0
	}
	start := 0
	for i in 0 ..< n {
		if !contiguous(edges[loop[(i - 1 + n) % n]], edges[loop[i]]) {
			start = i
			break
		}
	}
	Group :: struct {
		first, last: int,
	}
	groups := make([dynamic]Group, context.temp_allocator)
	for k in 0 ..< n {
		ei := loop[(start + k) % n]
		if len(groups) > 0 && contiguous(edges[groups[len(groups) - 1].last], edges[ei]) {
			groups[len(groups) - 1].last = ei
		} else {
			append(&groups, Group{ei, ei})
		}
	}
	S := f64(BOOL_SCALE)
	rd :: proc(v: f64) -> f32 {
		return f32(math.round(v * 100) / 100)
	}
	first := edges[groups[0].first]
	sub := make(Path, context.temp_allocator)
	path_move(&sub, {rd(f64(first.ax) / S), rd(f64(first.ay) / S)})
	for g, gi in groups {
		f, l := edges[g.first], edges[g.last]
		src := sources[f.tag.src]
		sx, sy := f64(f.ax) / S, f64(f.ay) / S
		ex, ey := f64(l.bx) / S, f64(l.by) / S
		chord := math.sqrt((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy))
		is_last := gi == len(groups) - 1
		end := Vec2{rd(ex), rd(ey)}
		if is_last do end = sub[0].p
		if src.n > 2 && chord > 2 / S {
			pts_in: [4][2]f64 = src.pts
			pts := bez_slice(pts_in[:src.n], f.tag.t0, l.tag.t1)
			d0 := [2]f64{sx - pts[0][0], sy - pts[0][1]}
			d1 := [2]f64{ex - pts[src.n - 1][0], ey - pts[src.n - 1][1]}
			if src.n == 4 {
				path_cubic(&sub, {rd(pts[1][0] + d0[0]), rd(pts[1][1] + d0[1])}, {rd(pts[2][0] + d1[0]), rd(pts[2][1] + d1[1])}, end)
			} else {
				path_quad(&sub, {rd(pts[1][0] + (d0[0] + d1[0]) / 2), rd(pts[1][1] + (d0[1] + d1[1]) / 2)}, end)
			}
		} else {
			if !is_last do path_line(&sub, end)
		}
	}
	// merge consecutive collinear lines
	pts := make(Path, context.temp_allocator)
	for g in sub do append(&pts, g)
	changed := true
	for changed {
		changed = false
		for i in 1 ..< len(pts) - 1 {
			a, b, c := pts[i - 1], pts[i], pts[i + 1]
			if b.kind != .Line || c.kind != .Line do continue
			u, v := b.p - a.p, c.p - b.p
			lu, lv := v_len(u), v_len(v)
			if lu == 0 || lv == 0 || (abs(v_cross(u, v)) / (lu * lv) < 1e-4 && v_dot(u, v) > 0) {
				ordered_remove(&pts, i)
				changed = true
				break
			}
		}
	}
	if len(pts) < 2 do return
	append(out, ..pts[:])
	path_close(out)
}

// Combines two paths. `changed` is false when nothing needed to change (then `result` is a copy of a + b).
// `a_even_odd` fills `a` with the even-odd rule. The result looks right with either rule.
path_boolean :: proc(a, b: []Seg, op: Bool_Op, a_even_odd := false) -> (result: Path, changed: bool) {
	sources := make([dynamic]Bsrc, context.temp_allocator)
	edges := make([dynamic]Bedge, context.temp_allocator)
	cid := 0
	flatten_operand(a, 0, &cid, &sources, &edges)
	flatten_operand(b, 1, &cid, &sources, &edges)
	if len(edges) == 0 do return {}, len(a) + len(b) > 0
	pieces, did_split := split_edges(edges[:])
	defer delete(pieces)
	// a split snaps to the grid, which moves the edge a little and can make it cross another: repeat until none do,
	// or the links between edges come out broken
	for pass := 0; pass < 8; pass += 1 {
		again, split_more := split_edges(pieces[:])
		delete(pieces)
		pieces = again
		if !split_more do break
	}
	recs, merged := merge_edges(pieces[:])
	defer delete(recs)
	out, class_changed := classify(recs[:], op, a_even_odd)
	defer delete(out)
	changed = did_split || merged || class_changed
	if !changed {
		result = make(Path)
		append(&result, ..a)
		append(&result, ..b)
		return
	}
	loops := link_loops(out[:])
	defer {
		for l in loops do delete(l)
		delete(loops)
	}
	for l in loops do loop_to_path(l[:], out[:], sources[:], &result)
	return result, true
}

path_remove_overlap :: proc(a: []Seg) -> Path {
	r, _ := path_boolean(a, nil, .Union)
	return r
}

// Reverses the direction of every subpath.
path_reverse :: proc(p: ^Path) {
	out := make(Path, context.temp_allocator)
	i := 0
	for i < len(p) {
		// find the subpath [i, j)
		j := i + 1
		for j < len(p) && p[j].kind != .Move do j += 1
		sub := p[i:j]
		closed := sub[len(sub) - 1].kind == .Close
		body := closed ? sub[:len(sub) - 1] : sub
		if len(body) > 0 && body[0].kind == .Move {
			// points of the anchors in order
			n := len(body)
			path_move(&out, body[n - 1].p)
			for k := n - 1; k >= 1; k -= 1 {
				g := body[k]
				prev := body[k - 1].p
				switch g.kind {
				case .Line:  path_line(&out, prev)
				case .Quad:  path_quad(&out, g.c1, prev)
				case .Cubic: path_cubic(&out, g.c2, g.c1, prev)
				case .Move, .Close:
				}
			}
			if closed do path_close(&out)
		}
		i = j
	}
	clear(p)
	append(p, ..out[:])
}
