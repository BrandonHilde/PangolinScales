package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Path tools: node editing, the pen and freehand drawing.
// ---------------------------------------------------------------------------

Handle_Ref :: struct {
	seg:   int,
	which: int, // 0 anchor, 1 first control point, 2 second control point
}

Pen_Pt :: struct {
	p:         Vec2,
	hin, hout: Vec2, // control offsets from p
	has:       bool,
}

PICK_R :: 7

// Node tool ------------------------------------------------------------------------------------------------

edited_node :: proc(d: ^Doc) -> ^Node {
	if tl.edit_uid == 0 do return nil
	n := node_find(d.root, tl.edit_uid)
	if n == nil || n.kind != .Path {
		tl.edit_uid = 0
		return nil
	}
	return n
}

// Screen position of a point in the node's local space.
@(private = "file")
loc_to_scr :: proc(d: ^Doc, w: Mat, p: Vec2) -> Vec2 {
	return to_screen(d, mat_apply(w, p))
}

// Finds the anchor or handle under the pointer: returns ref and ok.
@(private = "file")
hit_node_point :: proc(d: ^Doc, n: ^Node, sp: Vec2) -> (ref: Handle_Ref, ok: bool) {
	w := node_world(d.root, n)
	best := f32(PICK_R)
	for g, i in n.segs {
		if g.kind == .Close do continue
		a := loc_to_scr(d, w, g.p)
		// handles first so they win over a coincident anchor
		if g.kind == .Cubic {
			if dd := v_len(loc_to_scr(d, w, g.c2) - sp); dd < best && g.c2 != g.p {
				best, ref, ok = dd, Handle_Ref{i, 2}, true
			}
			if dd := v_len(loc_to_scr(d, w, g.c1) - sp); dd < best && g.c1 != prev_point(n.segs[:], i) {
				best, ref, ok = dd, Handle_Ref{i, 1}, true
			}
		}
		if dd := v_len(a - sp); dd <= best {
			best, ref, ok = dd, Handle_Ref{i, 0}, true
		}
	}
	return
}

tool_node :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	n := edited_node(d)
	if over && tl.kind == .None do ui.cursor = .DEFAULT
	if pressed {
		tl.start, tl.start_scr, tl.cur, tl.moved, tl.pushed = p, sp, p, false, false
		if n != nil {
			if ref, ok := hit_node_point(d, n, sp); ok {
				copy_orig_path(n)
				if ref.which == 0 {
					if !anchor_selected(ref.seg) {
						if !ui.shift do clear(&tl.anchors)
						append(&tl.anchors, ref.seg)
					} else if ui.shift {
						remove_anchor_sel(ref.seg)
					}
					tl.kind = .Anchor
				} else {
					tl.kind = .Handle
					tl.hs = ref
				}
				return
			}
			// double click on a segment adds a node
			if ui.dbl_click {
				if seg_insert_at(d, n, sp) do return
			}
		}
		hit, picked := pick_path_to_edit(d, p)
		if picked do return
		if !ui.shift do clear(&tl.anchors)
		if hit == nil && n != nil {
			tl.kind = .Marquee
		}
		return
	}
	node_drag_update(d, n, p, sp)
}

// Starts editing the path under `p`. `picked` is false when there is nothing editable there.
@(private = "file")
pick_path_to_edit :: proc(d: ^Doc, p: Vec2) -> (hit: ^Node, picked: bool) {
	hit = pick_node(d, p, true)
	if hit == nil || (hit.kind != .Path && hit.kind != .Rect && hit.kind != .Ellipse) do return hit, false
	if hit.uid != tl.edit_uid {
		history_push(d)
		node_to_path(hit)
		doc_changed(d)
		tl.edit_uid = hit.uid
		clear(&tl.anchors)
	}
	sel_set(d, hit)
	return hit, true
}

// Follows the pointer during a gesture that began on an anchor or a control point, and ends it on release.
@(private = "file")
node_drag_update :: proc(d: ^Doc, n: ^Node, p, sp: Vec2) {
	if tl.kind == .None do return
	tl.cur = p
	if !ui.down[0] {
		if tl.kind == .Marquee && n != nil {
			anchors_in_box(d, n, tl.start, p)
		}
		tl_reset()
		return
	}
	if !tl.moved && v_len(sp - tl.start_scr) < 3 do return
	tl.moved = true
	if n == nil do return
	w := node_world(d.root, n)
	iw, ok := mat_inv(w)
	if !ok do return
	switch tl.kind {
	case .Anchor:
		push_once(d)
		delta := mat_apply_dir(iw, snap_pt(p) - (snap_grid ? snap_pt(tl.start) : tl.start))
		copy(n.segs[:], tl_orig_path[:])
		move_anchors(n.segs[:], tl.anchors[:], delta)
		doc_changed(d)
	case .Handle:
		push_once(d)
		copy(n.segs[:], tl_orig_path[:])
		q := mat_apply(iw, snap_pt(p))
		move_handle(n.segs[:], tl.hs, q, ui.alt)
		doc_changed(d)
	case .None, .Move, .Scale, .Rotate, .Marquee, .Create, .Freehand, .Pen, .Gradient, .Erase, .Sculpt, .Extend:
	}
}

// Control point tool ---------------------------------------------------------------------------------------
//
// Picks control points only, so an anchor or another control point lying on top can never get in the way. Where
// several overlap, a click selects one, further clicks step through them and a drag moves the selected one.

@(private = "file")
Control_Hit :: struct {
	ref:  Handle_Ref,
	dist: f32,
}

// Every control point within reach of the pointer, nearest first, including those lying on their anchor.
@(private = "file")
control_points_at :: proc(d: ^Doc, n: ^Node, sp: Vec2) -> []Handle_Ref {
	add :: proc(hits: ^[dynamic]Control_Hit, ref: Handle_Ref, dist: f32) {
		if dist >= PICK_R do return
		append(hits, Control_Hit{ref, dist})
		for k := len(hits) - 1; k > 0 && hits[k - 1].dist > dist; k -= 1 {
			hits[k - 1], hits[k] = hits[k], hits[k - 1]
		}
	}
	w := node_world(d.root, n)
	hits := make([dynamic]Control_Hit, context.temp_allocator)
	for g, i in n.segs {
		if g.kind == .Cubic do add(&hits, Handle_Ref{i, 2}, v_len(loc_to_scr(d, w, g.c2) - sp))
		if g.kind == .Cubic || g.kind == .Quad do add(&hits, Handle_Ref{i, 1}, v_len(loc_to_scr(d, w, g.c1) - sp))
	}
	refs := make([]Handle_Ref, len(hits), context.temp_allocator)
	for h, i in hits do refs[i] = h.ref
	return refs
}

// The selected control point, if it still exists on this path (an undo can take it away).
control_selected :: proc(n: ^Node) -> (ref: Handle_Ref, ok: bool) {
	ref = tl.ctrl_sel
	if !tl.ctrl_on || ref.seg >= len(n.segs) do return ref, false
	k := n.segs[ref.seg].kind
	return ref, k == .Cubic || (k == .Quad && ref.which == 1)
}

@(private = "file")
control_select :: proc(ref: Handle_Ref, index, count: int) {
	tl.ctrl_sel, tl.ctrl_on = ref, true
	if count > 1 do set_statusf("Control point %d of %d: click for the next", index + 1, count)
}

tool_control :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	n := edited_node(d)
	if over && tl.kind == .None do ui.cursor = .DEFAULT
	if pressed {
		tl.start, tl.start_scr, tl.cur, tl.moved, tl.pushed = p, sp, p, false, false
		tl.ctrl_cycle = false
		if n != nil {
			refs := control_points_at(d, n, sp)
			if len(refs) > 0 {
				index := 0
				if cur, ok := control_selected(n); ok {
					for r, i in refs {
						if r == cur {
							index = i
							tl.ctrl_cycle = true
						}
					}
				}
				control_select(refs[index], index, len(refs))
				copy_orig_path(n)
				tl.hs = refs[index]
				tl.kind = .Handle
				return
			}
		}
		tl.ctrl_on = false
		pick_path_to_edit(d, p)
		return
	}
	if tl.kind == .Handle && !ui.down[0] && !tl.moved && tl.ctrl_cycle && n != nil {
		refs := control_points_at(d, n, tl.start_scr)
		for r, i in refs {
			if r == tl.ctrl_sel {
				next := (i + 1) % len(refs)
				control_select(refs[next], next, len(refs))
				break
			}
		}
	}
	node_drag_update(d, n, p, sp)
}

// Moves the selected control point by `delta` in document space.
control_nudge :: proc(d: ^Doc, delta: Vec2) {
	n := edited_node(d)
	if n == nil do return
	ref, ok := control_selected(n)
	if !ok do return
	iw, iok := mat_inv(node_world(d.root, n))
	if !iok do return
	g := n.segs[ref.seg]
	move_handle(n.segs[:], ref, (ref.which == 2 ? g.c2 : g.c1) + mat_apply_dir(iw, delta), ui.alt)
	doc_changed(d)
}

tl_orig_path: Path

copy_orig_path :: proc(n: ^Node) {
	delete(tl_orig_path)
	tl_orig_path = path_clone(n.segs[:])
}

anchor_selected :: proc(i: int) -> bool {
	for a in tl.anchors {
		if a == i do return true
	}
	return false
}

remove_anchor_sel :: proc(i: int) {
	for a, k in tl.anchors {
		if a == i {
			ordered_remove(&tl.anchors, k)
			return
		}
	}
}

anchors_in_box :: proc(d: ^Doc, n: ^Node, a, b: Vec2) {
	box := Bounds{min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y)}
	w := node_world(d.root, n)
	for g, i in n.segs {
		if g.kind == .Close do continue
		if bounds_contains(box, mat_apply(w, g.p)) && !anchor_selected(i) do append(&tl.anchors, i)
	}
}

// Moves anchors (with the control points attached to them) by `delta`. Coincident end points move together.
move_anchors :: proc(s: []Seg, sel: []int, delta: Vec2) {
	marked := make([]bool, len(s), context.temp_allocator)
	for i in sel {
		if i >= len(s) do continue
		marked[i] = true
		start := subpath_start(s, i)
		_ = start
		for j in 0 ..< len(s) {
			if j != i && s[j].kind != .Close && s[j].p == s[i].p && same_subpath(s, i, j) do marked[j] = true
		}
	}
	for j in 0 ..< len(s) {
		if !marked[j] || s[j].kind == .Close do continue
		s[j].p += delta
		if s[j].kind == .Cubic do s[j].c2 += delta
		if j + 1 < len(s) && s[j + 1].kind == .Cubic do s[j + 1].c1 += delta
	}
}

@(private = "file")
same_subpath :: proc(s: []Seg, i, j: int) -> bool {
	a, b := min(i, j), max(i, j)
	for k in a + 1 ..= b {
		if s[k].kind == .Move do return false
	}
	return true
}

// Drags a control point; the opposite one on the same anchor mirrors its direction when the node was smooth.
move_handle :: proc(s: []Seg, ref: Handle_Ref, to: Vec2, alt: bool) {
	i := ref.seg
	anchor: Vec2
	cseg := -1
	if ref.which == 2 {
		anchor = s[i].p
		if i + 1 < len(s) && s[i + 1].kind == .Cubic do cseg = i + 1
	} else {
		anchor = prev_point(s, i)
		if i - 1 >= 0 && s[i - 1].kind == .Cubic do cseg = i - 1
	}
	old := ref.which == 2 ? s[i].c2 : s[i].c1
	// smooth if the two handles pointed in opposite directions
	smooth := false
	copy_h: Vec2
	if cseg >= 0 {
		copy_h = ref.which == 2 ? s[cseg].c1 : s[cseg].c2
		a, b := old - anchor, copy_h - anchor
		la, lb := v_len(a), v_len(b)
		if la > 1e-4 && lb > 1e-4 {
			c := v_dot(a, b) / (la * lb)
			smooth = c < -0.995
		}
	}
	if ref.which == 2 do s[i].c2 = to
	else do s[i].c1 = to
	if smooth && !alt {
		dir := v_norm(to - anchor)
		l := v_len(copy_h - anchor)
		nh := anchor - dir * l
		if ref.which == 2 do s[cseg].c1 = nh
		else do s[cseg].c2 = nh
	}
}

// Replaces the anchor's handles with smooth ones along the neighbours' chord.
anchor_make_smooth :: proc(n: ^Node, i: int) {
	s := n.segs[:]
	if s[i].kind == .Close || s[i].kind == .Quad do return
	p := s[i].p
	a := i > 0 && s[i].kind != .Move ? prev_point(s, i) : p
	b := p
	if i + 1 < len(s) && s[i + 1].kind != .Move && s[i + 1].kind != .Close do b = s[i + 1].p
	if a == p && b == p do return
	dir := v_norm(b - a)
	if a == p do dir = v_norm(b - p)
	if b == p do dir = v_norm(p - a)
	if s[i].kind == .Line {
		s[i].kind = .Cubic
		s[i].c1 = lerp(a, p, 1.0 / 3)
	}
	if s[i].kind == .Cubic do s[i].c2 = p - dir * (v_len(p - a) / 3)
	if i + 1 < len(s) && (s[i + 1].kind == .Line || s[i + 1].kind == .Cubic) {
		if s[i + 1].kind == .Line {
			s[i + 1].kind = .Cubic
			s[i + 1].c2 = lerp(p, s[i + 1].p, 2.0 / 3)
		}
		s[i + 1].c1 = p + dir * (v_len(b - p) / 3)
	}
}

anchor_make_corner :: proc(n: ^Node, i: int) {
	s := n.segs[:]
	if s[i].kind == .Cubic do s[i].c2 = s[i].p
	if i + 1 < len(s) && s[i + 1].kind == .Cubic do s[i + 1].c1 = s[i].p
}

// Splits the segment nearest to the pointer. Returns true when a node was added.
seg_insert_at :: proc(d: ^Doc, n: ^Node, sp: Vec2) -> bool {
	w := node_world(d.root, n)
	best := f32(8)
	bi := -1
	bt: f32
	for g, i in n.segs {
		if g.kind == .Move || g.kind == .Close do continue
		p0 := prev_point(n.segs[:], i)
		N :: 32
		for k in 0 ..< N {
			t0, t1 := f32(k) / N, f32(k + 1) / N
			a := loc_to_scr(d, w, seg_at(g, p0, t0))
			b := loc_to_scr(d, w, seg_at(g, p0, t1))
			dd := dist_to_segment(sp, a, b)
			if dd < best {
				best, bi = dd, i
				// refine within this piece
				ab := b - a
				l2 := v_dot(ab, ab)
				u := l2 < 1e-9 ? f32(0) : clamp(v_dot(sp - a, ab) / l2, 0, 1)
				bt = t0 + (t1 - t0) * u
			}
		}
	}
	if bi < 0 do return false
	history_push(d)
	segs := &n.segs
	g := segs[bi]
	p0 := prev_point(segs[:], bi)
	t := bt
	#partial switch g.kind {
	case .Line:
		mid := lerp(p0, g.p, t)
		inject_at(segs, bi, Seg{kind = .Line, p = mid})
	case .Quad:
		q0, q1 := lerp(p0, g.c1, t), lerp(g.c1, g.p, t)
		s := lerp(q0, q1, t)
		segs[bi] = Seg{kind = .Quad, c1 = q0, p = s}
		inject_at(segs, bi + 1, Seg{kind = .Quad, c1 = q1, p = g.p})
	case .Cubic:
		q0, q1, q2 := lerp(p0, g.c1, t), lerp(g.c1, g.c2, t), lerp(g.c2, g.p, t)
		r0, r1 := lerp(q0, q1, t), lerp(q1, q2, t)
		s := lerp(r0, r1, t)
		segs[bi] = Seg{kind = .Cubic, c1 = q0, c2 = r0, p = s}
		inject_at(segs, bi + 1, Seg{kind = .Cubic, c1 = r1, c2 = q2, p = g.p})
	}
	clear(&tl.anchors)
	append(&tl.anchors, bi)
	doc_changed(d)
	return true
}

@(private = "file")
inject_at :: proc(p: ^Path, i: int, s: Seg) {
	inject_at_elem(p, i, s)
}

seg_at :: proc(g: Seg, p0: Vec2, t: f32) -> Vec2 {
	#partial switch g.kind {
	case .Line:
		return lerp(p0, g.p, t)
	case .Quad:
		return quad_at(p0, g.c1, g.p, t)
	case .Cubic:
		return cubic_at(p0, g.c1, g.c2, g.p, t)
	}
	return g.p
}

// Removes the selected anchors.
delete_anchors :: proc(d: ^Doc, n: ^Node) {
	if len(tl.anchors) == 0 do return
	history_push(d)
	idx := make([dynamic]int, context.temp_allocator)
	append(&idx, ..tl.anchors[:])
	// descending
	for a in 0 ..< len(idx) {
		for b in a + 1 ..< len(idx) {
			if idx[b] > idx[a] do idx[a], idx[b] = idx[b], idx[a]
		}
	}
	for i in idx {
		if i >= len(n.segs) do continue
		if n.segs[i].kind == .Move {
			if i + 1 < len(n.segs) && n.segs[i + 1].kind != .Move && n.segs[i + 1].kind != .Close {
				n.segs[i + 1] = Seg{kind = .Move, p = n.segs[i + 1].p}
				ordered_remove(&n.segs, i)
			} else {
				ordered_remove(&n.segs, i)
			}
		} else {
			ordered_remove(&n.segs, i)
		}
	}
	// drop empty subpaths (Move followed by Move / Close / end)
	k := 0
	out := make(Path, context.temp_allocator)
	for i in 0 ..< len(n.segs) {
		g := n.segs[i]
		if g.kind == .Move && (i + 1 >= len(n.segs) || n.segs[i + 1].kind == .Move) do continue
		if g.kind == .Close && (len(out) == 0 || out[len(out) - 1].kind == .Move || out[len(out) - 1].kind == .Close) do continue
		append(&out, g)
		k += 1
	}
	clear(&n.segs)
	append(&n.segs, ..out[:])
	clear(&tl.anchors)
	doc_changed(d)
}

node_overlay :: proc(d: ^Doc) {
	n := edited_node(d)
	if n == nil do return
	w := node_world(d.root, n)
	poly: Polys
	defer polys_free(&poly)
	path_flatten(n.segs[:], w, 0.5 / d.zoom, &poly)
	for sb in poly.subs {
		for i in sb.a + 1 ..< sb.b {
			draw_line(to_screen(d, poly.pts[i - 1]), to_screen(d, poly.pts[i]), C_SEL)
		}
		if sb.closed && sb.b - sb.a > 1 do draw_line(to_screen(d, poly.pts[sb.b - 1]), to_screen(d, poly.pts[sb.a]), C_SEL)
	}
	control := eff_tool() == .Control
	if control {
		// anchors cannot be picked with this tool, so they are small marks under the control points
		for g in n.segs {
			if g.kind == .Close do continue
			a := loc_to_scr(d, w, g.p)
			draw_rect(a.x - 2, a.y - 2, 4, 4, C_SEL)
		}
	}
	for g, i in n.segs {
		if g.kind == .Close do continue
		a := loc_to_scr(d, w, g.p)
		if g.kind == .Cubic || (control && g.kind == .Quad) {
			if g.kind == .Cubic {
				c2 := loc_to_scr(d, w, g.c2)
				draw_line(a, c2, Color{200, 200, 220, 150})
				draw_handle_dot(c2, Color{230, 230, 245, 255})
			}
			c1 := loc_to_scr(d, w, g.c1)
			pp := loc_to_scr(d, w, prev_point(n.segs[:], i))
			draw_line(pp, c1, Color{200, 200, 220, 150})
			draw_handle_dot(c1, Color{230, 230, 245, 255})
		}
		if !control do draw_handle_sq(a, anchor_selected(i), C_SEL)
	}
	if ref, ok := control_selected(n); ok && control {
		g := n.segs[ref.seg]
		c := loc_to_scr(d, w, ref.which == 2 ? g.c2 : g.c1)
		draw_rrect(c.x - 6, c.y - 6, 13, 13, 6.5, Color{20, 22, 28, 255}) // a thicker ring than the others
		draw_handle_dot(c, C_ACCENT)
	}
}

// Pen -----------------------------------------------------------------------------------------------------

pen_closed: bool
pen_close_curved: bool // the closing segment was dragged out from the first point

pen_drawing :: proc() -> bool {
	return len(tl.pen_pts) > 0
}

pen_rebuild :: proc(d: ^Doc) {
	n := node_find(d.root, tl.pen_uid)
	if n == nil do return
	clear(&n.segs)
	pts := tl.pen_pts
	for pt, i in pts {
		if i == 0 {
			path_move(&n.segs, pt.p)
			continue
		}
		// a segment curves only if it was dragged at the point it ends on: a click always draws a straight line
		prev := pts[i - 1]
		if pt.has {
			path_cubic(&n.segs, prev.p + prev.hout, pt.p + pt.hin, pt.p)
		} else {
			path_line(&n.segs, pt.p)
		}
	}
	if pen_closed && len(pts) > 1 {
		last, first := pts[len(pts) - 1], pts[0]
		if pen_close_curved do path_cubic(&n.segs, last.p + last.hout, first.p + first.hin, first.p)
		path_close(&n.segs)
	}
	doc_changed(d)
}

// Ends the path being drawn; `keep` false discards it.
pen_finish :: proc(keep: bool) {
	d := doc
	if d == nil || tl.pen_uid == 0 {
		clear(&tl.pen_pts)
		tl.pen_uid = 0
		return
	}
	n := node_find(d.root, tl.pen_uid)
	if n != nil {
		if keep && len(tl.pen_pts) >= 2 {
			if pen_closed do n.fill = cur_fill
			node_fit_gradients(n)
			sel_set(d, n)
		} else {
			if p := node_parent(d.root, n); p != nil {
				if i := node_index(p, n); i >= 0 do ordered_remove(&p.children, i)
			}
			node_free(n)
			if len(d.undo) > 0 {
				s := pop(&d.undo)
				state_free(&s)
			}
		}
		doc_changed(d)
	}
	clear(&tl.pen_pts)
	tl.pen_uid = 0
	pen_closed, pen_close_curved = false, false
	tl.kind = .None
}

tool_pen :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if over do ui_tool_cursor(TOOL_ICONS[.Pen])
	q := snap_pt(p)
	if pressed {
		if len(tl.pen_pts) >= 2 && v_len(to_screen(d, tl.pen_pts[0].p) - sp) < 9 {
			// closes when the button is released: a drag from here curves the closing segment
			pen_closed = true
			tl.kind = .Pen
			tl.start_scr = sp
			pen_rebuild(d)
			return
		}
		if tl.pen_uid == 0 {
			history_push(d)
			n := new_shape(d, .Path)
			n.fill = paint_none()
			if n.stroke.kind == .None do n.stroke = paint_solid({40, 30, 24, 255})
			append(&d.root.children, n)
			tl.pen_uid = n.uid
			clear(&tl.pen_pts)
			pen_closed = false
		}
		if ui.dbl_click && len(tl.pen_pts) >= 2 {
			// the first click of the double click already placed this point
			pen_finish(true)
			return
		}
		append(&tl.pen_pts, Pen_Pt{p = q})
		tl.kind = .Pen
		tl.start_scr = sp
		tl.start = q
		pen_rebuild(d)
		return
	}
	if tl.kind == .Pen {
		if !ui.down[0] {
			tl.kind = .None
			if pen_closed do pen_finish(true)
			return
		}
		if v_len(sp - tl.start_scr) > 3 && pen_closed {
			first := &tl.pen_pts[0]
			first.hin = first.p - q
			pen_close_curved = true
			pen_rebuild(d)
		} else if v_len(sp - tl.start_scr) > 3 && len(tl.pen_pts) > 0 {
			pt := &tl.pen_pts[len(tl.pen_pts) - 1]
			off := q - pt.p
			pt.hout, pt.hin, pt.has = off, -off, true
			pen_rebuild(d)
		}
	}
}

pen_overlay :: proc(d: ^Doc) {
	if tl.pen_uid == 0 do return
	n := node_find(d.root, tl.pen_uid)
	if n == nil do return
	poly: Polys
	defer polys_free(&poly)
	path_flatten(n.segs[:], MAT_ID, 0.5 / d.zoom, &poly)
	for sb in poly.subs {
		for i in sb.a + 1 ..< sb.b do draw_line(to_screen(d, poly.pts[i - 1]), to_screen(d, poly.pts[i]), C_SEL)
	}
	if !pen_closed && len(tl.pen_pts) > 0 {
		last := tl.pen_pts[len(tl.pen_pts) - 1]
		cur := to_doc(d, pointer())
		cur = snap_pt(cur)
		// rubber band: the straight line a click would draw
		draw_line(to_screen(d, last.p), to_screen(d, cur), Color{60, 160, 255, 110})
	}
	for pt, i in tl.pen_pts {
		a := to_screen(d, pt.p)
		if pt.has {
			draw_line(a, to_screen(d, pt.p + pt.hin), Color{200, 200, 220, 150})
			draw_line(a, to_screen(d, pt.p + pt.hout), Color{200, 200, 220, 150})
			draw_handle_dot(to_screen(d, pt.p + pt.hin), Color{230, 230, 245, 255})
			draw_handle_dot(to_screen(d, pt.p + pt.hout), Color{230, 230, 245, 255})
		}
		draw_handle_sq(a, i == 0 || i == len(tl.pen_pts) - 1, C_SEL)
	}
}

pen_undo_point :: proc(d: ^Doc) {
	if len(tl.pen_pts) == 0 do return
	pop(&tl.pen_pts)
	if len(tl.pen_pts) == 0 {
		pen_finish(false)
	} else {
		pen_rebuild(d)
	}
}

// Freehand ------------------------------------------------------------------------------------------------

tool_freehand :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if over do ui_tool_cursor(TOOL_ICONS[.Freehand])
	if pressed {
		tl.kind = .Freehand
		tl.start_scr = sp
		clear(&tl.free_pts)
		append(&tl.free_pts, snap_pt(p))
		return
	}
	if tl.kind != .Freehand do return
	if ui.down[0] {
		q := snap_pt(p)
		if v_len(q - tl.free_pts[len(tl.free_pts) - 1]) * d.zoom > 2 do append(&tl.free_pts, q)
		return
	}
	// released: fit curves
	defer tl_reset()
	pts := tl.free_pts[:]
	if len(pts) < 2 do return
	tol := smoothing / d.zoom
	closed := close_open_paths && len(pts) > 3 && v_len(pts[0] - pts[len(pts) - 1]) * d.zoom < 10
	history_push(d)
	n := new_shape(d, .Path)
	n.fill = paint_none()
	if n.stroke.kind == .None do n.stroke = paint_solid({40, 30, 24, 255})
	path_move(&n.segs, pts[0])
	if closed {
		pts[len(pts) - 1] = pts[0]
	}
	fit_curve(pts, tol * tol, &n.segs)
	if closed {
		path_close(&n.segs)
		n.fill = cur_fill
	}
	node_fit_gradients(n)
	append(&d.root.children, n)
	sel_set(d, n)
	doc_changed(d)
}

// Insert helper used above
inject_at_elem :: proc(p: ^Path, i: int, s: Seg) {
	inject_at_dyn(p, i, s)
}

inject_at_dyn :: proc(p: ^Path, i: int, s: Seg) {
	append(p, Seg{})
	for k := len(p) - 1; k > i; k -= 1 do p[k] = p[k - 1]
	p[i] = s
}

_ :: math
