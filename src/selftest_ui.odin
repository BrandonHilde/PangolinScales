package pangolin

import "core:math"

// Interaction tests: tools are driven with simulated pointer input on a document whose view maps screen pixels
// to document units one to one.

sim_doc :: proc() -> ^Doc {
	d := doc_new(.Svg, "sim", 400, 300)
	d.zoom, d.ox, d.oy, d.view_init = 1, 0, 0, true
	doc = d
	ui.scale = 1
	tools_cancel()
	return d
}

// One simulated frame of pointer input.
sim :: proc(d: ^Doc, x, y: f32, pressed, down: bool) {
	ui.pressed[0], ui.down[0], ui.released[0] = pressed, down, false
	ui.ptr = {x, y}
	ui.mx, ui.my = i32(x), i32(y)
	tools_input(d, Rect{0, 0, 400, 300}, true, {x, y})
}

sim_drag :: proc(d: ^Doc, a, b: Vec2, steps := 6) {
	sim(d, a.x, a.y, true, true)
	for i in 1 ..= steps {
		p := a + (b - a) * (f32(i) / f32(steps))
		sim(d, p.x, p.y, false, true)
	}
	sim(d, b.x, b.y, false, false)
}

sim_click :: proc(d: ^Doc, p: Vec2) {
	sim(d, p.x, p.y, true, true)
	sim(d, p.x, p.y, false, false)
}

ui_selftest :: proc(t: ^Test_Run) {
	ui.shift, ui.alt, ui.ctrl, ui.dbl_click = false, false, false, false

	// rectangle tool
	d := sim_doc()
	cur_tool = .Rect
	sim_drag(d, {10, 10}, {60, 40})
	check(t, len(d.root.children) == 1 && d.root.children[0].kind == .Rect, "rect tool creates a rect")
	if len(d.root.children) == 1 {
		n := d.root.children[0]
		check(t, near(n.x, 10) && near(n.y, 10) && near(n.w, 50) && near(n.h, 30), "rect geometry")
		check(t, len(d.sel) == 1, "new shape is selected")
	}
	// shift makes a square
	ui.shift = true
	sim_drag(d, {100, 100}, {160, 120})
	ui.shift = false
	if len(d.root.children) == 2 {
		n := d.root.children[1]
		check(t, near(n.w, n.h) && near(n.w, 60), "shift draws a square")
	}

	// ellipse
	cur_tool = .Ellipse
	sim_drag(d, {200, 50}, {260, 90})
	check(t, len(d.root.children) == 3 && d.root.children[2].kind == .Ellipse && near(d.root.children[2].w, 30), "ellipse tool")

	// select + move, undo
	cur_tool = .Select
	clear(&d.sel)
	sim_click(d, {30, 25})
	check(t, len(d.sel) == 1 && d.sel[0] == d.root.children[0].uid, "click selects")
	sim_drag(d, {30, 25}, {50, 45})
	r0 := d.root.children[0]
	check(t, near(r0.xf.e, 20) && near(r0.xf.f, 20), "drag moves the selection")
	history_undo(d)
	check(t, near(d.root.children[0].xf.e, 0), "undo of a move")
	history_redo(d)

	// marquee
	clear(&d.sel)
	sim_drag(d, {0, 0}, {400, 300})
	check(t, len(d.sel) == 3, "marquee selects everything")

	// scale with a corner handle
	d2 := sim_doc()
	cur_tool = .Rect
	sim_drag(d2, {100, 100}, {200, 150})
	cur_tool = .Select
	// the selection box corner (bottom right) is at (200,150)
	sim_drag(d2, {200, 150}, {300, 250})
	n2 := d2.root.children[0]
	b2 := node_doc_bounds(d2, n2)
	check(t, near(b2.x1, 300, 0.5) && near(b2.y1, 250, 0.5) && near(b2.x0, 100, 0.5), "corner handle scales")

	// pen tool: triangle then close by clicking the first point
	d3 := sim_doc()
	cur_tool = .Pen
	sim_click(d3, {50, 50})
	sim_click(d3, {150, 50})
	sim_drag(d3, {150, 150}, {190, 150}) // curved point
	sim_click(d3, {50, 50})
	check(t, len(d3.root.children) == 1 && !pen_drawing(), "pen finishes when closing")
	if len(d3.root.children) == 1 {
		p := d3.root.children[0]
		kinds := 0
		for g in p.segs do if g.kind == .Cubic do kinds += 1
		check(t, p.kind == .Path && p.segs[len(p.segs) - 1].kind == .Close && kinds >= 1, "pen path closes and keeps its curve")
	}

	// pen tool: a click draws a straight segment, whatever the points around it look like
	{
		pen_kinds :: proc(n: ^Node) -> (lines, cubics: int) {
			for g in n.segs {
				if g.kind == .Line do lines += 1
				if g.kind == .Cubic do cubics += 1
			}
			return
		}
		// two curves, then a straight line by clicking
		ds := sim_doc()
		cur_tool = .Pen
		sim_drag(ds, {50, 50}, {70, 30})
		sim_drag(ds, {150, 50}, {170, 70})
		sim_drag(ds, {250, 50}, {270, 30})
		sim_click(ds, {250, 150})
		ps := ds.root.children[0]
		c1, l1 := ps.segs[1], ps.segs[3]
		check(t, ps.segs[1].kind == .Cubic && ps.segs[2].kind == .Cubic, "pen: dragged points make curves")
		check(t, l1.kind == .Line && l1.p == Vec2{250, 150}, "pen: a click after a curve draws a straight line")
		check(t, c1.c1 == Vec2{70, 30} && c1.c2 == Vec2{130, 30}, "pen: curves use the handles of both ends")

		// clicking the first point closes straight, even though the first and last points were dragged
		sim_click(ds, {50, 50})
		lines, cubics := pen_kinds(ps)
		check(t, !pen_drawing() && ps.segs[len(ps.segs) - 1].kind == .Close, "pen: clicking the first point closes the path")
		check(t, cubics == 2 && lines == 1, "pen: clicking the first point closes with a straight line")

		dt := sim_doc()
		sim_drag(dt, {50, 50}, {70, 30})
		sim_drag(dt, {150, 50}, {170, 70})
		sim_click(dt, {50, 50})
		pt := dt.root.children[0]
		_, cubics = pen_kinds(pt)
		check(t, !pen_drawing() && cubics == 1, "pen: closing right after a curve is still straight")

		// dragging from the first point closes with a curve
		du := sim_doc()
		sim_click(du, {50, 50})
		sim_click(du, {150, 50})
		sim_drag(du, {50, 50}, {30, 70})
		pu := du.root.children[0]
		_, cubics = pen_kinds(pu)
		check(t, !pen_drawing() && cubics == 1 && pu.segs[len(pu.segs) - 1].kind == .Close, "pen: dragging the first point closes with a curve")
		if cubics == 1 do check(t, pu.segs[2].c2 == Vec2{70, 30} && pu.segs[2].p == Vec2{50, 50}, "pen: the closing drag sets the curve's handle")
		cur_tool = .Select
	}

	// node tool: drag the first anchor
	cur_tool = .Node
	if len(d3.root.children) == 1 {
		sim_click(d3, {100, 50}) // pick the path by its edge
		check(t, tl.edit_uid == d3.root.children[0].uid, "node tool picks the path")
		before := d3.root.children[0].segs[0].p
		sim_drag(d3, {50, 50}, {70, 80})
		after := d3.root.children[0].segs[0].p
		check(t, near(after.x, before.x + 20, 0.5) && near(after.y, before.y + 30, 0.5), "node drag moves the anchor")
	}
	tools_cancel()

	// control point tool: overlapping control points can each be picked, and anchors never are
	{
		dq := sim_doc()
		q := new_shape(dq, .Path)
		q.fill, q.stroke = paint_none(), paint_solid({40, 30, 24, 255})
		path_move(&q.segs, {100, 100})
		path_cubic(&q.segs, {150, 100}, {200, 200}, {200, 200}) // second control point on the anchor
		path_cubic(&q.segs, {200, 200}, {250, 200}, {300, 200}) // first control point on the same anchor
		path_quad(&q.segs, {340, 240}, {380, 200})
		append(&dq.root.children, q)
		set_tool(.Control)
		sim_click(dq, {100, 100}) // no control point here: picks the path by its edge
		check(t, tl.edit_uid == q.uid, "control tool picks the path")
		check(t, !tl.ctrl_on, "picking the path selects no control point")

		ref1, ref2 := Handle_Ref{1, 2}, Handle_Ref{2, 1}
		sim_click(dq, {200, 200})
		check(t, tl.ctrl_on && tl.ctrl_sel == ref1, "first click selects one of the overlapping control points")
		sim_click(dq, {200, 200})
		check(t, tl.ctrl_sel == ref2, "next click selects the other control point")
		sim_click(dq, {200, 200})
		check(t, tl.ctrl_sel == ref1, "clicks wrap around the overlapping control points")
		check(t, q.segs[1].p == Vec2{200, 200} && q.segs[1].c2 == Vec2{200, 200} && q.segs[2].c1 == Vec2{200, 200}, "clicking moves nothing")

		sim_click(dq, {200, 200})
		undo_q := len(dq.undo)
		sim_drag(dq, {200, 200}, {210, 230})
		check(t, q.segs[2].c1 == Vec2{210, 230}, "drag moves the selected control point")
		check(t, q.segs[1].c2 == Vec2{200, 200} && q.segs[1].p == Vec2{200, 200}, "drag leaves the anchor and the other control point")
		check(t, len(dq.undo) == undo_q + 1, "a drag is one undo step")
		history_undo(dq)
		q = dq.root.children[0]
		check(t, q.segs[2].c1 == Vec2{200, 200}, "undo restores the control point")

		// anchors do not react
		sim_drag(dq, {300, 200}, {320, 220})
		check(t, q.segs[2].p == Vec2{300, 200}, "the control tool cannot move an anchor")
		check(t, !tl.ctrl_on, "pressing away from control points clears the selection")

		// quadratic control points can be picked too
		sim_drag(dq, {340, 240}, {345, 250})
		check(t, q.segs[3].c1 == Vec2{345, 250}, "the control tool moves a quadratic control point")
		control_nudge(dq, {1, -1})
		check(t, q.segs[3].c1 == Vec2{346, 249}, "nudge moves the selected control point")

		set_tool(.Node)
		check(t, tl.edit_uid == q.uid, "node tool keeps the path from the control tool")
		sim_drag(dq, {300, 200}, {320, 220})
		check(t, q.segs[2].p == Vec2{320, 220}, "the node tool still moves anchors")
		set_tool(.Control)
		check(t, tl.edit_uid == q.uid, "control tool keeps the path from the node tool")
		set_tool(.Select)
		check(t, tl.edit_uid == 0, "other tools end the editing session")
	}

	// freehand: a curvy stroke becomes few cubic segments
	d4 := sim_doc()
	cur_tool = .Freehand
	sim(d4, 20, 150, true, true)
	for i in 1 ..= 60 {
		x := 20 + f32(i) * 5
		sim(d4, x, 150 + math.sin(f32(i) * 0.15) * 60, false, true)
	}
	sim(d4, 320, 150, false, false)
	check(t, len(d4.root.children) == 1, "freehand creates a path")
	if len(d4.root.children) == 1 do check(t, len(d4.root.children[0].segs) >= 2 && len(d4.root.children[0].segs) <= 14, "freehand is smoothed into few segments")

	// text tool
	d5 := sim_doc()
	cur_tool = .Text
	sim_click(d5, {40, 100})
	check(t, text_editing() && len(d5.root.children) == 1, "text tool starts editing")
	append(&ui.chars, 'H', 'i')
	if text_editing() do text_update(d5, {0, 0}, false)
	clear(&ui.chars)
	text_finish()
	check(t, len(d5.root.children) == 1 && text_str(d5.root.children[0]) == "Hi", "typed text")
	tb := node_doc_bounds(d5, d5.root.children[0])
	check(t, !bounds_empty(tb) && bounds_w(tb) > 5, "text has outlines")

	// the text tool drags text around; a click without a drag edits it
	c0 := bounds_center(tb)
	sim_drag(d5, c0, c0 + {40, 20})
	moved := node_doc_bounds(d5, d5.root.children[0])
	check(t, near(moved.x0, tb.x0 + 40, 0.01) && near(moved.y0, tb.y0 + 20, 0.01), "text tool drags text")
	check(t, !text_editing() && len(d5.root.children) == 1, "dragging text neither edits it nor adds text")
	sim_click(d5, c0 + {40, 20})
	check(t, text_editing() && tl.text_uid == d5.root.children[0].uid, "a click on text edits it")
	sim_drag(d5, c0 + {40, 20}, c0 + {50, 20})
	check(t, text_editing() && near(node_doc_bounds(d5, d5.root.children[0]).x0, tb.x0 + 50, 0.01), "the text being edited can be dragged")
	text_finish()
	history_undo(d5)
	history_undo(d5)
	check(t, near(node_doc_bounds(d5, d5.root.children[0]).x0, tb.x0, 0.01), "each text drag is one undo step")
	cmd_text_outlines(d5)
	d5.sel = {}
	append(&d5.sel, d5.root.children[0].uid)
	cmd_text_outlines(d5)
	check(t, d5.root.children[0].kind == .Path, "text converts to outlines")

	// booleans keep lines, which have no area
	{
		dl := sim_doc()
		add_line :: proc(d: ^Doc, a, b: Vec2) -> ^Node {
			n := new_shape(d, .Path)
			n.fill = paint_none()
			n.stroke = paint_solid({40, 30, 24, 255})
			path_move(&n.segs, a)
			path_line(&n.segs, b)
			append(&d.root.children, n)
			append(&d.sel, n.uid)
			return n
		}
		add_line(dl, {10, 10}, {60, 60})
		add_line(dl, {10, 60}, {60, 10})
		run_cmd(.Union)
		check(t, len(dl.root.children) == 1 && dl.root.children[0].kind == .Path, "union of two lines makes one path")
		if len(dl.root.children) == 1 {
			s := dl.root.children[0].segs
			check(t, len(s) == 4 && s[0].kind == .Move && s[2].kind == .Move, "union of two lines keeps both lines")
			check(t, len(dl.sel) == 1, "union of two lines selects the result")
		}
		run_cmd(.Intersect) // one object selected: refused for another reason, nothing changes
		check(t, len(dl.root.children) == 1, "boolean with one object changes nothing")

		dm := sim_doc()
		add_line(dm, {10, 10}, {60, 60})
		r := new_shape(dm, .Rect)
		r.x, r.y, r.w, r.h = 20, 20, 10, 10
		append(&dm.root.children, r)
		append(&dm.sel, r.uid)
		for op in ([?]Cmd{.Union, .Subtract, .Intersect, .Exclude}) {
			run_cmd(op)
			check(t, len(dm.root.children) == 2, "boolean of a line and a shape keeps both")
		}

		dd := sim_doc()
		add_line(dd, {10, 10}, {60, 60})
		add_line(dd, {10, 60}, {60, 10})
		run_cmd(.Intersect)
		check(t, len(dd.root.children) == 2, "intersect of two lines keeps both")

		// disjoint shapes still intersect to nothing
		de := sim_doc()
		ra := new_shape(de, .Rect)
		ra.x, ra.y, ra.w, ra.h = 0, 0, 10, 10
		rb := new_shape(de, .Rect)
		rb.x, rb.y, rb.w, rb.h = 40, 40, 10, 10
		append(&de.root.children, ra, rb)
		append(&de.sel, ra.uid, rb.uid)
		run_cmd(.Intersect)
		check(t, len(de.root.children) == 0, "intersect of disjoint shapes removes them")

		// freehand strokes: Close Open Paths decides whether a boolean joins their ends
		two_strokes :: proc() -> ^Doc {
			d := sim_doc()
			cur_tool = .Freehand
			stroke :: proc(d: ^Doc, sign: f32) {
				sim(d, 20, 150, true, true)
				for i in 1 ..= 60 {
					sim(d, 20 + f32(i) * 5, 150 + sign * math.sin(f32(i) * 0.15) * 60, false, true)
				}
				sim(d, 320, 170, false, false)
			}
			stroke(d, 1)
			stroke(d, -1)
			clear(&d.sel)
			for n in d.root.children do append(&d.sel, n.uid)
			return d
		}
		count_kind :: proc(segs: []Seg, k: Seg_Kind) -> int {
			c := 0
			for g in segs do if g.kind == k do c += 1
			return c
		}
		check(t, !close_open_paths, "Close Open Paths starts off")
		df := two_strokes()
		check(t, len(df.root.children) == 2, "two freehand strokes")
		run_cmd(.Union)
		check(t, len(df.root.children) == 1, "union of open strokes makes one path")
		if len(df.root.children) == 1 {
			s := df.root.children[0].segs[:]
			check(t, count_kind(s, .Close) == 0, "union leaves open strokes open")
			check(t, count_kind(s, .Move) == 2, "union keeps both strokes")
		}

		dc := two_strokes()
		add_rect := new_shape(dc, .Rect)
		add_rect.x, add_rect.y, add_rect.w, add_rect.h = 100, 100, 50, 50
		append(&dc.root.children, add_rect)
		append(&dc.sel, add_rect.uid)
		run_cmd(.Union)
		check(t, len(dc.root.children) == 3, "union of open strokes and a shape is refused while the setting is off")

		run_cmd(.Toggle_Close_Paths)
		check(t, close_open_paths, "toggle turns Close Open Paths on")
		dg := two_strokes()
		run_cmd(.Union)
		check(t, len(dg.root.children) == 1, "union with the setting on makes one path")
		if len(dg.root.children) == 1 do check(t, count_kind(dg.root.children[0].segs[:], .Close) > 0, "union with the setting on closes open strokes")
		dh := sim_doc()
		add_line(dh, {10, 10}, {60, 60})
		add_line(dh, {10, 60}, {60, 10})
		run_cmd(.Union)
		check(t, len(dh.root.children) == 1 && count_kind(dh.root.children[0].segs[:], .Move) == 2, "straight lines survive union with the setting on")
		run_cmd(.Toggle_Close_Paths)
		check(t, !close_open_paths, "toggle turns Close Open Paths off")

		// a freehand stroke that ends near its start closes only with the setting on
		loop_stroke :: proc() -> ^Node {
			d := sim_doc()
			cur_tool = .Freehand
			sim(d, 100, 100, true, true)
			for i in 1 ..= 30 {
				a := f32(i) / 30 * 2 * math.PI
				sim(d, 150 - 50 * math.cos(a), 100 + 50 * math.sin(a), false, true)
			}
			sim(d, 101, 100, false, false)
			return d.root.children[0]
		}
		lo := loop_stroke()
		check(t, count_kind(lo.segs[:], .Close) == 0 && lo.fill.kind == .None, "a freehand loop stays open by default")
		run_cmd(.Toggle_Close_Paths)
		lc := loop_stroke()
		check(t, count_kind(lc.segs[:], .Close) == 1, "a freehand loop closes with the setting on")
		run_cmd(.Toggle_Close_Paths)

		// offset does not close an open path unless the setting is on; simplify never does
		dj := two_strokes()
		undo_before := len(dj.undo)
		run_cmd(.Offset_Out)
		check(t, len(dj.undo) == undo_before && count_kind(dj.root.children[0].segs[:], .Close) == 0, "offset refuses open paths by default")
		run_cmd(.Simplify)
		check(t, count_kind(dj.root.children[0].segs[:], .Close) == 0, "simplify keeps a path open")
		run_cmd(.Toggle_Close_Paths)
		run_cmd(.Offset_Out)
		check(t, count_kind(dj.root.children[0].segs[:], .Close) > 0, "offset closes open paths with the setting on")

		// offset inward keeps an object it would shrink to nothing
		dv := sim_doc()
		add_line(dv, {10, 10}, {60, 60})
		undo_v := len(dv.undo)
		run_cmd(.Offset_In)
		check(t, len(dv.root.children) == 1 && len(dv.root.children[0].segs) == 2, "offset inward keeps a straight line")
		check(t, len(dv.undo) == undo_v, "offset that changes nothing adds no undo step")
		check(t, len(dv.sel) == 1, "offset that changes nothing keeps the selection")
		dw := sim_doc()
		tiny := new_shape(dw, .Rect)
		tiny.x, tiny.y, tiny.w, tiny.h = 50, 50, 2, 2
		big := new_shape(dw, .Rect)
		big.x, big.y, big.w, big.h = 100, 100, 80, 80
		append(&dw.root.children, tiny, big)
		append(&dw.sel, tiny.uid, big.uid)
		run_cmd(.Offset_In)
		check(t, len(dw.root.children) == 2 && len(node_render_segs(dw.root.children[0])) > 0, "offset inward keeps a shape too small to shrink")
		check(t, len(dw.root.children) == 2 && dw.root.children[1].kind == .Path, "offset inward still shrinks the other selected shapes")
		run_cmd(.Toggle_Close_Paths)
		cur_tool = .Select

		// close or open: an explicit command, whatever the Close Open Paths setting says
		dy := sim_doc()
		pa := add_line(dy, {10, 10}, {60, 60})
		path_line(&pa.segs, {10, 60})
		undo_y := len(dy.undo)
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pa.segs[:], .Close) == 1, "close or open closes an open path")
		check(t, len(dy.undo) == undo_y + 1, "close or open is one undo step")
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pa.segs[:], .Close) == 0 && len(pa.segs) == 3, "close or open opens it again, back as it was")

		// opening removes a straight line back to the start, but keeps a curve
		dz := sim_doc()
		ps1 := add_line(dz, {10, 10}, {60, 10})
		path_line(&ps1.segs, {60, 60})
		path_line(&ps1.segs, {10, 10})
		path_close(&ps1.segs)
		run_cmd(.Close_Or_Open)
		check(t, len(ps1.segs) == 3 && ps1.segs[2].p == Vec2{60, 60}, "opening drops a straight segment back to the start")
		dc2 := sim_doc()
		pc := add_line(dc2, {10, 10}, {60, 10})
		path_cubic(&pc.segs, {90, 60}, {10, 90}, {10, 10})
		path_close(&pc.segs)
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pc.segs[:], .Close) == 0 && count_kind(pc.segs[:], .Cubic) == 1, "opening keeps a curve back to the start")
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pc.segs[:], .Close) == 1, "a path whose ends touch can be closed again")

		// with a mix, it closes; a rectangle opens as a path; several subpaths all change
		dm2 := sim_doc()
		pm := add_line(dm2, {10, 10}, {60, 10})
		rm := new_shape(dm2, .Rect)
		rm.x, rm.y, rm.w, rm.h = 80, 80, 40, 40
		append(&dm2.root.children, rm)
		append(&dm2.sel, rm.uid)
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pm.segs[:], .Close) == 1 && count_kind(rm.segs[:], .Close) == 1, "with open and closed paths selected, all end up closed")
		run_cmd(.Close_Or_Open)
		check(t, rm.kind == .Path && count_kind(rm.segs[:], .Close) == 0 && count_kind(pm.segs[:], .Close) == 0, "opening reaches a rectangle too")
		dn := sim_doc()
		pn := add_line(dn, {10, 10}, {60, 10})
		path_move(&pn.segs, {10, 40})
		path_line(&pn.segs, {60, 40})
		run_cmd(.Close_Or_Open)
		check(t, count_kind(pn.segs[:], .Close) == 2, "closing reaches every subpath")

		// a selection with no paths changes nothing
		dq2 := sim_doc()
		tq := new_shape(dq2, .Text)
		append(&dq2.root.children, tq)
		append(&dq2.sel, tq.uid)
		undo_q2 := len(dq2.undo)
		run_cmd(.Close_Or_Open)
		check(t, tq.kind == .Text && len(dq2.undo) == undo_q2, "close or open ignores text")

		// a path that returns to its start has no gap to close, so it counts as a shape even without Close
		di := sim_doc()
		tri := new_shape(di, .Path)
		path_move(&tri.segs, {10, 10})
		path_line(&tri.segs, {50, 10})
		path_line(&tri.segs, {10, 50})
		path_line(&tri.segs, {10, 10})
		ri := new_shape(di, .Rect)
		ri.x, ri.y, ri.w, ri.h = 0, 0, 20, 20
		append(&di.root.children, tri, ri)
		append(&di.sel, tri.uid, ri.uid)
		run_cmd(.Union)
		check(t, len(di.root.children) == 1 && count_kind(di.root.children[0].segs[:], .Close) > 0, "a path back at its start unions as a shape")
	}

	// commands: union of two overlapping rects, group, duplicate, delete, align
	d6 := sim_doc()
	a := new_shape(d6, .Rect)
	a.x, a.y, a.w, a.h = 10, 10, 40, 40
	b := new_shape(d6, .Rect)
	b.x, b.y, b.w, b.h = 30, 30, 40, 40
	append(&d6.root.children, a, b)
	append(&d6.sel, a.uid, b.uid)
	run_cmd(.Union)
	check(t, len(d6.root.children) == 1 && d6.root.children[0].kind == .Path, "union replaces both with one path")
	if len(d6.root.children) == 1 {
		pa := path_area(d6.root.children[0].segs[:], 128, 128)
		check(t, near(pa, 2800, 3), "union area")
	}
	run_cmd(.Duplicate)
	check(t, len(d6.root.children) == 2, "duplicate")
	run_cmd(.Select_All)
	run_cmd(.Group)
	check(t, len(d6.root.children) == 1 && d6.root.children[0].kind == .Group, "group")
	run_cmd(.Ungroup)
	check(t, len(d6.root.children) == 2, "ungroup")
	run_cmd(.Align_Left)
	b0, b1 := node_doc_bounds(d6, d6.root.children[0]), node_doc_bounds(d6, d6.root.children[1])
	check(t, near(b0.x0, b1.x0), "align left")
	run_cmd(.Flip_H)
	run_cmd(.Delete)
	check(t, len(d6.root.children) == 0, "delete")
	run_cmd(.Undo)
	check(t, len(d6.root.children) == 2, "undo delete")

	// stroke to path keeps the visual area
	d7 := sim_doc()
	ln := new_shape(d7, .Path)
	path_move(&ln.segs, {20, 50})
	path_line(&ln.segs, {120, 50})
	ln.fill = paint_none()
	ln.stroke = paint_solid(BLACK)
	ln.sw = 10
	append(&d7.root.children, ln)
	append(&d7.sel, ln.uid)
	run_cmd(.Stroke_To_Path)
	if len(d7.root.children) == 1 {
		check(t, near(path_area(d7.root.children[0].segs[:], 200, 100), 1000, 3), "stroke to path area")
	} else do check(t, false, "stroke to path result")

	// offset outwards grows a square
	d8 := sim_doc()
	sq := new_shape(d8, .Rect)
	sq.x, sq.y, sq.w, sq.h = 50, 50, 50, 50
	append(&d8.root.children, sq)
	append(&d8.sel, sq.uid)
	cur_sw = 4
	run_cmd(.Offset_Out)
	if len(d8.root.children) == 1 {
		a8 := path_area(d8.root.children[0].segs[:], 200, 200)
		check(t, a8 > 2500 + 600 && a8 < 2500 + 1000, "offset grows the shape")
	}

	// simplify reduces nodes of a dense polyline
	d9 := sim_doc()
	pl := new_shape(d9, .Path)
	for i in 0 ..= 100 {
		pt := Vec2{f32(i) * 3, 100 + math.sin(f32(i) * 0.1) * 40}
		if i == 0 do path_move(&pl.segs, pt)
		else do path_line(&pl.segs, pt)
	}
	append(&d9.root.children, pl)
	append(&d9.sel, pl.uid)
	run_cmd(.Simplify)
	check(t, len(d9.root.children[0].segs) < 20, "simplify reduces nodes")

	// font mode: edit the current glyph with the tools and see it committed
	f := font_new_blank()
	fd := font_edit_doc(f, "t")
	doc = fd
	fd.zoom, fd.ox, fd.oy, fd.view_init = 0.5, 0, 0, true
	font_select_glyph(fd, 0)
	check(t, len(fd.root.children) == 1 && fd.root.children[0].kind == .Path, "font glyph loaded as a path")
	font_select_glyph(fd, 2)
	cur_tool = .Rect
	// a stroke would count towards the outline; draw a fill only so the bounds are the drag's
	saved_stroke := cur_stroke
	cur_stroke = paint_none()
	sim_drag(fd, {100, 100}, {200, 300})
	cur_stroke = saved_stroke
	font_sync(fd)
	g := font_cur(fd)
	check(t, g != nil && len(g.segs) >= 5, "font tool edit is committed to the glyph")
	if g != nil {
		bb := path_bounds(g.segs[:])
		// view zoom 0.5: screen (100,100) is document (200,200); baseline at em_top = 800
		check(t, near(bb.x0, 200, 1) && near(bb.x1, 400, 1) && near(bb.y1, 600, 1) && near(bb.y0, 200, 1), "glyph outline in font units")
	}
	font_select_glyph(fd, 0)
	font_select_glyph(fd, 2)
	check(t, len(font_cur(fd).segs) >= 5 && len(fd.root.children) == 1, "glyph edit survives switching")
	doc = nil
}

tool_groups_selftest :: proc(t: ^Test_Run) {
	sim_doc()
	tool_groups_default()
	set_tool(.Select)

	// a group's hotkey picks its last tool, then cycles through the group
	tool_group_activate(1)
	check(t, cur_tool == .Pen && current_group() == 1, "group hotkey picks the group's first tool")
	tool_group_activate(1)
	check(t, cur_tool == .Freehand, "pressing the hotkey again cycles")
	tool_group_activate(1)
	tool_group_activate(1)
	check(t, cur_tool == .Eraser, "the eraser is in the draw group")
	tool_group_activate(1)
	check(t, cur_tool == .Pen, "cycling wraps around")
	tool_group_activate(1)
	tool_group_activate(0)
	tool_group_activate(1)
	check(t, cur_tool == .Freehand, "coming back to a group picks its last tool")

	// a tool in two groups stays with the group it was picked from
	append(&tool_groups[4].tools, Tool.Select)
	select_tool_in_group(.Select, 4)
	check(t, current_group() == 4, "shared tool keeps the group it was picked from")
	set_tool(.Rect)
	check(t, current_group() == 2, "a tool picked by its own shortcut finds its group")

	// preferences round trip
	name_set(&tool_groups[0].name, "Pick: me; now")
	tool_groups[0].name = make_name(group_clean_name(name_str(&tool_groups[0].name)))
	tool_groups[2].key = .KEY_NULL
	append(&tool_groups, Tool_Group{})
	s := tool_groups_serialize()
	tool_groups_parse(s)
	check(t, len(tool_groups) == 7, "groups round trip: count")
	check(t, name_str(&tool_groups[0].name) == "Pick me now", "group names drop : and ;")
	check(t, tool_groups[1].key == .TWO && tool_groups[2].key == .KEY_NULL, "groups round trip: hotkeys")
	check(t, len(tool_groups[4].tools) == 5 && tool_groups[4].tools[4] == .Select, "groups round trip: tools")
	check(t, len(tool_groups[6].tools) == 0 && len(tool_groups[6].ops) == 0, "groups round trip: empty group")
	check(t, len(tool_groups[5].ops) == 8 && tool_groups[5].ops[7] == .Toggle_Close_Paths && tool_groups[5].ops[1] == .Subtract && len(tool_groups[5].tools) == 0, "groups round trip: path operations")
	tool_groups_parse("65:Pen,Nonsense,Pen:X;7:Rect")
	check(t, len(tool_groups) == 2 && len(tool_groups[0].tools) == 1 && tool_groups[0].key == .A, "unknown tools and duplicates are dropped")
	check(t, tool_groups[1].key == .KEY_NULL, "keys that are not letters or digits are dropped")

	check(t, len(tool_groups) == 2 && tool_groups[0].name.n == 1, "groups saved before path operations still load")
	tool_groups_parse("0::Ops:Union,Pen,Union,Offset_In")
	check(t, len(tool_groups[0].ops) == 2 && tool_groups[0].ops[1] == .Offset_In, "only known path operations load, once each")

	// interface scale: automatic sizes by display, never below the system's setting, and always fits the window
	check(t, ui_scale_auto(1920, 1080, 1) == 150, "a 1080p display gets 150%")
	check(t, ui_scale_auto(2560, 1440, 1) == 200 && ui_scale_auto(3840, 2160, 1) == 300, "larger displays get more")
	check(t, ui_scale_auto(1066, 600, 1) == 100, "small displays stay at 100%")
	check(t, ui_scale_auto(15360, 8640, 1) == UI_SCALE_MAX, "Auto stops at the end of the slider")
	check(t, ui_scale_auto(1920, 1080, 2) == 200, "the system's display scale is a lower limit")
	saved_pref := ui_scale_pref
	prefs_parse("ui_scale=2\n")
	check(t, ui_scale_pref == 200, "older preference files counted whole multiples")
	prefs_parse("ui_scale=0\n")
	check(t, ui_scale_pref == 0, "0 is Auto")
	prefs_parse("ui_scale_percent=163\n")
	check(t, ui_scale_pref == 163, "the slider's value is kept, under the old key too")
	prefs_parse("ui_scale=9000\n")
	check(t, ui_scale_pref == UI_SCALE_MAX, "a saved scale stays on the slider")
	ui_scale_pref = saved_pref
	sd := doc_new(.Svg, "scale", 400, 300)
	sd.zoom, sd.ox, sd.oy, sd.view_init = 0.8, 120, 60, true
	append(&docs, sd)
	before := to_screen(sd, {100, 50}) * 1.5
	views_keep_on_screen(1.5, 2.25)
	check(t, v_len(to_screen(sd, {100, 50}) * 2.25 - before) < 0.01, "a drawing stays put on the screen when the interface scale changes")
	pop(&docs)

	// tooltips: every command and tool explains itself, long text wraps, and the innermost control wins
	for c in Cmd {
		if c != .None do check(t, len(cmd_help(c)) > 15, "every command has help text")
	}
	for tool in Tool do check(t, len(TOOL_HELP[tool]) > 15, "every tool has help text")
	check(t, cmd_tip("Union", .Union).title == "Union (Ctrl+Alt+=)" && cmd_tip("Union", .Union).desc == cmd_help(.Union), "a command's tooltip: name and shortcut, then what it does")
	check(t, tip_for_label({"Cancel", "d"}, "Cancel") == Tip{"", "d"}, "a title that repeats a button's text is dropped")
	check(t, tip_for_label({"Export TrueType", "d"}, "Export TrueType...") == Tip{"", "d"}, "a button's trailing dots do not count")
	check(t, tip_for_label({"Smooth (S)", "d"}, "Smooth").title == "Smooth (S)", "a title that adds something stays")
	for title in MENU_TITLES_FONT do check(t, menu_title_tip(title).desc != "", "every menu title has help text")
	{
		measure :: proc(s: string) -> i32 {return i32(len(s)) * 10}
		lines := tooltip_wrap("aaa bbb ccc", 75, measure)
		check(t, len(lines) == 2 && lines[0] == "aaa bbb" && lines[1] == "ccc", "tooltips wrap at spaces")
		lines = tooltip_wrap("aaa", 75, measure)
		check(t, len(lines) == 1 && lines[0] == "aaa", "a short tooltip stays on one line")
		lines = tooltip_wrap("aaaaaaaaaaaaaaaaaaaa bb", 75, measure)
		check(t, len(lines) == 2 && lines[0] == "aaaaaaaaaaaaaaaaaaaa" && lines[1] == "bb", "a word wider than a line stays whole")

		saved_id, saved_t, saved_tip := ui.hover_id, ui.hover_t, ui.tip
		ui.hover_id, ui.hover_t, ui.tip, ui.tip_desc = 0, 0, {}, false
		ui.hover_seen = false
		outer, inner := Tip{"outer", "outer text"}, Tip{"inner", "inner text"}
		tooltip_hover(11, outer)
		tooltip_hover(22, inner)
		tooltip_resolve()
		check(t, ui.hover_id == 22 && ui.tip.title == "", "the innermost control takes the hover, and its tooltip waits")
		ui.hover_t = f32(TIP_TITLE_DELAY) + 0.01
		tooltip_hover(11, outer)
		tooltip_hover(22, inner)
		tooltip_resolve()
		check(t, ui.tip.title == "inner" && ui.hover_id == 22, "overlapping controls do not reset the wait")
		check(t, !ui.tip_desc, "a tooltip starts with just its title")
		ui.hover_t = f32(TIP_DESC_DELAY) + 0.01
		tooltip_hover(22, inner)
		tooltip_resolve()
		check(t, ui.tip_desc && ui.tip.desc == "inner text", "the description appears if the pointer stays")
		tooltip_hover(33, outer)
		ui.tip, ui.tip_desc = {}, false
		tooltip_resolve()
		check(t, ui.hover_t == 0 && ui.tip.title == "" && !ui.tip_desc, "moving to another control starts again from nothing")
		ui.hover_id, ui.hover_t, ui.tip, ui.tip_desc, ui.hover_seen = saved_id, saved_t, saved_tip, false, false
	}

	// a group of operations: its hotkey runs the operation last used from it on the selection
	tool_groups_default()
	set_tool(.Select)
	d2 := sim_doc()
	a := new_shape(d2, .Rect)
	a.x, a.y, a.w, a.h = 10, 10, 40, 40
	b := new_shape(d2, .Rect)
	b.x, b.y, b.w, b.h = 30, 30, 40, 40
	append(&d2.root.children, a, b)
	append(&d2.sel, a.uid, b.uid)
	pg := 5
	check(t, len(tool_groups[pg].ops) > 0 && len(tool_groups[pg].tools) == 0, "default Path group holds operations")
	op, _ := path_op(.Union)
	check(t, path_op_enabled(op), "union is enabled with two objects selected")
	tool_groups[pg].last_op = .Subtract
	tool_group_activate(pg)
	check(t, len(d2.root.children) == 1 && d2.root.children[0].kind == .Path && cur_tool == .Select, "operation group hotkey runs its last operation, tool unchanged")
	clear(&d2.sel)
	check(t, !path_op_enabled(op), "union is disabled with nothing selected")
	group_run_op(pg, .Break_Apart)
	check(t, tool_groups[pg].last_op == .Break_Apart, "running an operation makes it the group's last")
	close_op, _ := path_op(.Toggle_Close_Paths)
	check(t, path_op_enabled(close_op), "Close Open Paths works with any selection")
	group_run_op(pg, .Toggle_Close_Paths)
	check(t, close_open_paths && tool_groups[pg].last_op == .Break_Apart, "the toggle is not remembered for the group's hotkey")
	group_run_op(pg, .Toggle_Close_Paths)

	tool_groups_default()
	set_tool(.Select)
}

// Object list drag and drop: node_reorder places the dragged object next to the drop target.
reorder_selftest :: proc(t: ^Test_Run) {
	d := sim_doc()
	mk :: proc(d: ^Doc, x: f32) -> ^Node {
		n := new_shape(d, .Rect)
		n.x, n.y, n.w, n.h = x, 10, 10, 10
		return n
	}
	a, b, c := mk(d, 0), mk(d, 20), mk(d, 40)
	append(&d.root.children, a, b, c) // a at the back, c in front
	check(t, node_reorder(d, a, c, true), "reorder: drop above the front object")
	check(t, d.root.children[0] == b && d.root.children[1] == c && d.root.children[2] == a, "reorder: dragged object is now in front")
	undo_n := len(d.undo)
	check(t, !node_reorder(d, a, c, true) && len(d.undo) == undo_n, "reorder: dropping where it already is changes nothing")
	node_reorder(d, a, b, false)
	check(t, d.root.children[0] == a, "reorder: drop below the back object")

	// into a moved group: the object stays where it is on the page
	g := new_shape(d, .Group)
	g.xf = mat_translate(100, 50)
	x := mk(d, 0)
	append(&g.children, x)
	append(&d.root.children, g)
	before := node_doc_bounds(d, b)
	check(t, node_reorder(d, b, x, true), "reorder: into a group")
	after := node_doc_bounds(d, b)
	check(t, node_parent(d.root, b) == g && g.children[1] == b, "reorder: lands in the group, above the target")
	check(t, near(after.x0, before.x0, 0.01) && near(after.y0, before.y0, 0.01), "reorder: keeps its place on the page")
	check(t, !node_reorder(d, g, x, true), "reorder: a group cannot go inside itself")
	history_undo(d)
	check(t, len(d.root.children) == 4 && len(d.root.children[3].children) == 1, "reorder: undo")
}

// A glyph is edited like a drawing: its shapes, layers and history survive moving to another glyph and back,
// and its outline is every visible fill and stroke.
font_edit_selftest :: proc(t: ^Test_Run) {
	f := font_new_blank()
	d := font_edit_doc(f, "glyphs")
	doc = d
	tools_cancel()
	a := f.cur // "A", empty
	check(t, len(d.root.children) == 0, "font: an empty glyph has no shapes")

	history_push(d)
	r := new_shape(d, .Rect)
	r.x, r.y, r.w, r.h = 100, 100, 200, 700 // editing space: font y 0 ..= 700
	r.fill, r.stroke = paint_solid(GLYPH_FILL), paint_none()
	append(&d.root.children, r)
	ln := new_shape(d, .Path)
	path_move(&ln.segs, {400, 300})
	path_line(&ln.segs, {400, 700})
	ln.fill, ln.stroke, ln.sw = paint_none(), paint_solid(BLACK), 20
	g := new_shape(d, .Group)
	append(&g.children, ln)
	append(&d.root.children, g)
	doc_changed(d)
	font_sync(d)
	b := path_bounds(f.glyphs[a].segs[:])
	check(t, near(b.x0, 100, 0.5) && near(b.y0, 0, 0.5) && near(b.y1, 700, 0.5), "font: a filled shape becomes outline")
	check(t, near(b.x1, 410, 0.5), "font: a stroke-only shape becomes outline")

	font_select_glyph(d, a + 1)
	check(t, len(d.root.children) == 0 && len(d.undo) == 0, "font: another glyph starts with its own shapes and history")
	font_select_glyph(d, a)
	check(t, len(d.root.children) == 2 && d.root.children[1].kind == .Group && len(d.root.children[1].children) == 1, "font: shapes and groups come back with the glyph")
	check(t, len(d.undo) == 1, "font: history comes back with the glyph")

	// the ascender moves the editing space; the outline stays put in font units, here and in a stored glyph
	f.asc = 900
	font_metrics_changed(d)
	font_sync(d)
	b2 := path_bounds(f.glyphs[a].segs[:])
	check(t, near(b2.y0, 0, 0.5) && near(b2.y1, 700, 0.5), "font: metrics change keeps the outline")
	font_select_glyph(d, a + 1)
	f.asc = 750
	font_metrics_changed(d)
	font_select_glyph(d, a)
	font_sync(d)
	b3 := path_bounds(f.glyphs[a].segs[:])
	check(t, len(d.root.children) == 2 && near(b3.y0, 0, 0.5) && near(b3.y1, 700, 0.5), "font: a stored glyph follows the metrics")

	font_center_glyph(d)
	font_sync(d)
	b4 := path_bounds(f.glyphs[a].segs[:])
	adv := f.glyphs[a].advance
	check(t, near(b4.x0, adv - b4.x1, 0.5), "font: center glyph")
	history_undo(d)
	font_sync(d)
	check(t, near(path_bounds(f.glyphs[a].segs[:]).x0, 100, 0.5), "font: center glyph undoes")

	// an outline changed from outside (overlap removal) replaces the shapes, undoably
	font_remove_overlap_current(d)
	check(t, len(d.root.children) == 1 && d.root.children[0].kind == .Path, "font: remove overlap merges the shapes")
	history_undo(d)
	check(t, len(d.root.children) == 2, "font: remove overlap undoes")
	tools_cancel()
}
