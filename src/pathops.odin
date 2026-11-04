package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Path menu commands: booleans, combine / break apart, offset, stroke to path, simplify.
// Results are written in document coordinates (identity transform).
// ---------------------------------------------------------------------------

// Geometry of a node in document space (groups contribute all their children).
node_world_segs :: proc(d: ^Doc, n: ^Node, out: ^Path) {
	collect :: proc(n: ^Node, m: Mat, out: ^Path) {
		mm := mat_mul(m, n.xf)
		if n.kind == .Group {
			for c in n.children do collect(c, mm, out)
			return
		}
		segs := node_render_segs(n)
		start := len(out)
		append(out, ..segs)
		path_transform(out[start:], mm)
	}
	collect(n, node_parent_world(d, n), out)
}

// Replaces `n` by a path node with the given geometry, keeping its place in the stack and its style.
new_path_like :: proc(d: ^Doc, like: ^Node, segs: []Seg) -> ^Node {
	n := node_new(d, .Path)
	name_set(&n.name, "Path")
	n.fill, n.stroke, n.sw, n.cap, n.join, n.miter = like.fill, like.stroke, like.sw, like.cap, like.join, like.miter
	n.dash, n.ndash, n.dash_off, n.opacity, n.even_odd = like.dash, like.ndash, like.dash_off, like.opacity, like.even_odd
	n.segs = path_clone(segs)
	return n
}

// World-space copy of a node's gradient paints follow the baked geometry.
paint_to_world :: proc(p: ^Paint, m: Mat) {
	if p.kind == .Linear || p.kind == .Radial {
		p.p0 = mat_apply(m, p.p0)
		if p.kind == .Linear do p.p1 = mat_apply(m, p.p1)
		else do p.p1.x *= mat_scale_factor(m)
	}
}

replace_nodes :: proc(d: ^Doc, old: []^Node, result: ^Node) {
	// result takes the stack position of the lowest old node
	parent := node_parent(d.root, old[0])
	pos := len(parent.children)
	for n in old {
		if node_parent(d.root, n) == parent do pos = min(pos, node_index(parent, n))
	}
	for n in old {
		if p := node_parent(d.root, n); p != nil {
			if i := node_index(p, n); i >= 0 do ordered_remove(&p.children, i)
		}
		node_free(n)
	}
	pos = min(pos, len(parent.children))
	inject_at_node(&parent.children, pos, result)
	sel_set(d, result)
}

// Paths stay open unless this is on. It lets freehand strokes close when they end near their start, and lets
// booleans and offset run on open paths, which they treat as closed by joining the ends with a straight line.
close_open_paths := false

// True if a subpath has no Close and ends away from its start. A Move with nothing after it does not count.
path_has_open_subpath :: proc(segs: []Seg) -> bool {
	start, cur: Vec2
	drawn := false
	for g in segs {
		#partial switch g.kind {
		case .Move:
			if drawn && cur != start do return true
			start, cur = g.p, g.p
			drawn = false
		case .Close:
			cur = start
			drawn = false
		case:
			cur = g.p
			drawn = true
		}
	}
	return drawn && cur != start
}

// True if a drawn subpath has no Close, wherever it ends.
path_has_unclosed_subpath :: proc(segs: []Seg) -> bool {
	drawn := false
	for g in segs {
		#partial switch g.kind {
		case .Move:
			if drawn do return true
			drawn = false
		case .Close:
			drawn = false
		case:
			drawn = true
		}
	}
	return drawn
}

// Closes every subpath, or opens every subpath. Opening also drops a straight segment that only returned to the
// start, so it undoes what closing looks like; a curve back to the start stays.
path_set_closed :: proc(p: ^Path, closed: bool) {
	out := make(Path, context.temp_allocator)
	start: Vec2
	drawn := false
	for g in p {
		#partial switch g.kind {
		case .Move:
			if drawn && closed do path_close(&out)
			start = g.p
			drawn = false
			append(&out, g)
		case .Close:
			if closed {
				append(&out, g)
			} else if n := len(out); n >= 3 && out[n - 1].kind == .Line && out[n - 1].p == start {
				pop(&out)
			}
			drawn = false
		case:
			append(&out, g)
			drawn = true
		}
	}
	if drawn && closed do path_close(&out)
	clear(p)
	append(p, ..out[:])
}

// Closes the selected paths if any of them is open; otherwise opens them all. Rectangles and ellipses become paths.
cmd_close_or_open :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	any_path, any_open := false, false
	for n in nodes {
		if n.kind == .Group || n.kind == .Text do continue
		any_path = true
		if n.kind == .Path && path_has_unclosed_subpath(n.segs[:]) do any_open = true
	}
	if !any_path {
		set_status("Select a path to close or open")
		return
	}
	history_push(d)
	for n in nodes {
		if n.kind == .Group || n.kind == .Text do continue
		node_to_path(n)
		if n.kind == .Path do path_set_closed(&n.segs, any_open)
	}
	// the points of the edited path have new indices
	clear(&tl.anchors)
	tl.ctrl_on = false
	set_status(any_open ? "Paths closed" : "Paths opened")
	doc_changed(d)
}

// True for a node the boolean operations cannot use as a shape: its geometry encloses nothing, like a straight
// line, or it has an open path while Close Open Paths is off.
node_is_line :: proc(d: ^Doc, n: ^Node) -> bool {
	segs := make(Path, context.temp_allocator)
	node_world_segs(d, n, &segs)
	if len(segs) == 0 do return false
	if !close_open_paths && path_has_open_subpath(segs[:]) do return true
	filled := path_remove_overlap(segs[:])
	defer delete(filled)
	return len(filled) == 0
}

cmd_bool :: proc(d: ^Doc, op: Bool_Op) {
	nodes := sel_nodes(d)
	if len(nodes) < 2 {
		set_status("Select two or more objects")
		return
	}
	// The boolean closes every subpath, which would erase a line and add a straight edge to an open path. Union
	// merges such objects into one path; anything else that involves them is refused.
	lines := 0
	for n in nodes do if node_is_line(d, n) do lines += 1
	if lines == len(nodes) && op == .Union {
		cmd_combine(d)
		return
	}
	if lines > 0 {
		if close_open_paths {
			set_status("Lines have no area: try Stroke to Path")
		} else {
			set_status("Open path: turn on Close Open Paths")
		}
		return
	}
	history_push(d)
	acc := make(Path, context.temp_allocator)
	node_world_segs(d, nodes[0], &acc)
	for i in 1 ..< len(nodes) {
		other := make(Path, context.temp_allocator)
		node_world_segs(d, nodes[i], &other)
		res, _ := path_boolean(acc[:], other[:], op)
		acc = make(Path, context.temp_allocator)
		append(&acc, ..res[:])
		delete(res)
	}
	if len(acc) == 0 {
		// nothing is left: remove the operands
		for n in nodes {
			if p := node_parent(d.root, n); p != nil {
				if k := node_index(p, n); k >= 0 do ordered_remove(&p.children, k)
			}
			node_free(n)
		}
		clear(&d.sel)
		doc_changed(d)
		return
	}
	like := nodes[0]
	res := new_path_like(d, like, acc[:])
	if like.kind == .Group {
		res.fill = cur_fill
		res.stroke = paint_none()
	} else {
		// gradients in the style of the first object move to world space
		w := mat_mul(node_parent_world(d, like), like.xf)
		paint_to_world(&res.fill, w)
		paint_to_world(&res.stroke, w)
		res.sw *= mat_scale_factor(w)
	}
	name_set(&res.name, "Path")
	replace_nodes(d, nodes, res)
	doc_changed(d)
}

cmd_combine :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) < 2 {
		set_status("Select two or more objects")
		return
	}
	history_push(d)
	acc := make(Path, context.temp_allocator)
	for n in nodes do node_world_segs(d, n, &acc)
	like := nodes[len(nodes) - 1]
	res := new_path_like(d, like, acc[:])
	if like.kind != .Group {
		w := mat_mul(node_parent_world(d, like), like.xf)
		paint_to_world(&res.fill, w)
		paint_to_world(&res.stroke, w)
		res.sw *= mat_scale_factor(w)
	}
	replace_nodes(d, nodes, res)
	doc_changed(d)
}

cmd_break_apart :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	clear(&d.sel)
	for n in nodes {
		if n.kind == .Group do continue
		w := mat_mul(node_parent_world(d, n), n.xf)
		all := make(Path, context.temp_allocator)
		node_world_segs(d, n, &all)
		// subpath ranges
		ranges := make([dynamic][2]int, context.temp_allocator)
		i := 0
		for i < len(all) {
			j := i + 1
			for j < len(all) && all[j].kind != .Move do j += 1
			append(&ranges, [2]int{i, j})
			i = j
		}
		if len(ranges) < 2 {
			append(&d.sel, n.uid)
			continue
		}
		parent := node_parent(d.root, n)
		pos := node_index(parent, n)
		for r, k in ranges {
			c := new_path_like(d, n, all[r[0]:r[1]])
			paint_to_world(&c.fill, w)
			paint_to_world(&c.stroke, w)
			c.sw *= mat_scale_factor(w)
			inject_at_node(&parent.children, pos + 1 + k, c)
			append(&d.sel, c.uid)
		}
		ordered_remove(&parent.children, pos)
		node_free(n)
	}
	doc_changed(d)
}

// Offsets (grows / shrinks) a path by `dist` document units using stroke geometry and booleans.
offset_path :: proc(segs: []Seg, dist: f32) -> Path {
	st := Stroke_Style{width = abs(dist) * 2, cap = .Round, join = .Round, miter = 4}
	pieces: Polys
	defer polys_free(&pieces)
	stroke_path(segs, st, 1, &pieces)
	band := make(Path, context.temp_allocator)
	for sb in pieces.subs {
		for i in sb.a ..< sb.b {
			if i == sb.a do path_move(&band, pieces.pts[i])
			else do path_line(&band, pieces.pts[i])
		}
		path_close(&band)
	}
	merged := path_remove_overlap(band[:])
	defer delete(merged)
	res, _ := path_boolean(segs, merged[:], dist > 0 ? .Union : .Subtract)
	return res
}

cmd_offset :: proc(d: ^Doc, dir: f32) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	// offset treats every subpath as closed, which would add a straight edge to an open path
	if !close_open_paths {
		for n in nodes {
			if n.kind == .Group do continue
			segs := make(Path, context.temp_allocator)
			node_world_segs(d, n, &segs)
			if path_has_open_subpath(segs[:]) {
				set_status("Open path: turn on Close Open Paths")
				return
			}
		}
	}
	history_push(d)
	amount := dir * max(5 / d.zoom, 1)
	if cur_sw > 0 do amount = dir * cur_sw
	clear(&d.sel)
	changed, kept := false, false
	for n in nodes {
		if n.kind == .Group do continue
		w := mat_mul(node_parent_world(d, n), n.xf)
		all := make(Path, context.temp_allocator)
		node_world_segs(d, n, &all)
		res := offset_path(all[:], amount)
		if len(res) == 0 {
			// shrunk to nothing: the object stays as it is rather than vanishing
			delete(res)
			append(&d.sel, n.uid)
			kept = true
			continue
		}
		changed = true
		c := new_path_like(d, n, res[:])
		delete(res)
		paint_to_world(&c.fill, w)
		paint_to_world(&c.stroke, w)
		c.sw *= mat_scale_factor(w)
		parent := node_parent(d.root, n)
		pos := node_index(parent, n)
		inject_at_node(&parent.children, pos + 1, c)
		ordered_remove(&parent.children, pos)
		node_free(n)
		append(&d.sel, c.uid)
	}
	if kept do set_status("Nothing would be left, so it was kept")
	if !changed {
		if len(d.undo) > 0 {
			s := pop(&d.undo)
			state_free(&s)
		}
		return
	}
	doc_changed(d)
}

cmd_stroke_to_path :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	clear(&d.sel)
	for n in nodes {
		if n.kind == .Group || n.stroke.kind == .None || n.sw <= 0 {
			append(&d.sel, n.uid)
			continue
		}
		w := mat_mul(node_parent_world(d, n), n.xf)
		// stroke in local space, then to document space
		local := node_render_segs(n)
		pieces: Polys
		stroke_path(local, stroke_style_of(n), mat_scale_factor(w), &pieces)
		polys_transform(&pieces, w)
		band := make(Path, context.temp_allocator)
		for sb in pieces.subs {
			for i in sb.a ..< sb.b {
				if i == sb.a do path_move(&band, pieces.pts[i])
				else do path_line(&band, pieces.pts[i])
			}
			path_close(&band)
		}
		polys_free(&pieces)
		outline := path_remove_overlap(band[:])
		parent := node_parent(d.root, n)
		pos := node_index(parent, n)
		stroke_node := node_new(d, .Path)
		name_set(&stroke_node.name, "Stroke")
		stroke_node.fill = n.stroke
		paint_to_world(&stroke_node.fill, w)
		stroke_node.segs = outline
		stroke_node.opacity = n.opacity
		if n.fill.kind != .None {
			// keep the fill as its own object under the new outline
			fill_node := new_path_like(d, n, nil)
			all := make(Path, context.temp_allocator)
			node_world_segs(d, n, &all)
			delete(fill_node.segs)
			fill_node.segs = path_clone(all[:])
			fill_node.stroke = paint_none()
			paint_to_world(&fill_node.fill, w)
			inject_at_node(&parent.children, pos, fill_node)
			pos += 1
		}
		inject_at_node(&parent.children, pos + 1, stroke_node)
		ordered_remove(&parent.children, pos)
		node_free(n)
		append(&d.sel, stroke_node.uid)
	}
	doc_changed(d)
}

cmd_simplify :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	tol := max(1.5 / d.zoom, 0.25)
	for n in nodes {
		if n.kind == .Group do continue
		if n.kind == .Text do text_to_path(n)
		node_to_path(n)
		if n.kind != .Path do continue
		flat: Polys
		path_flatten(n.segs[:], MAT_ID, tol * 0.25, &flat)
		out := make(Path)
		for sb in flat.subs {
			pts := make([dynamic]Vec2, context.temp_allocator)
			simplify_poly(flat.pts[sb.a:sb.b], tol * 0.3, &pts)
			if len(pts) < 2 {
				continue
			}
			path_move(&out, pts[0])
			if sb.closed && len(pts) > 2 {
				// fit as an open curve returning to the start
				append(&pts, pts[0])
			}
			fit_curve(pts[:], tol * tol, &out)
			if sb.closed do path_close(&out)
		}
		polys_free(&flat)
		delete(n.segs)
		n.segs = out
	}
	doc_changed(d)
}

_ :: math
