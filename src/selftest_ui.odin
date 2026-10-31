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
		check(t, p.kind == .Path && p.segs[len(p.segs) - 1].kind == .Close && kinds >= 1, "pen path closed with a curve")
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
	cmd_text_outlines(d5)
	d5.sel = {}
	append(&d5.sel, d5.root.children[0].uid)
	cmd_text_outlines(d5)
	check(t, d5.root.children[0].kind == .Path, "text converts to outlines")

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
	check(t, len(fd.root.children) == 1, "font glyph loaded as a path")
	font_select_glyph(fd, 2)
	cur_tool = .Rect
	sim_drag(fd, {100, 100}, {200, 300})
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
