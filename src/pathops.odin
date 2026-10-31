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

cmd_bool :: proc(d: ^Doc, op: Bool_Op) {
	nodes := sel_nodes(d)
	if len(nodes) < 2 {
		set_status("Select two or more objects")
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
	history_push(d)
	amount := dir * max(5 / d.zoom, 1)
	if cur_sw > 0 do amount = dir * cur_sw
	clear(&d.sel)
	for n in nodes {
		if n.kind == .Group do continue
		w := mat_mul(node_parent_world(d, n), n.xf)
		all := make(Path, context.temp_allocator)
		node_world_segs(d, n, &all)
		res := offset_path(all[:], amount)
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
