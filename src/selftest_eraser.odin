package pangolin

import "core:fmt"
import "core:math"
import "core:strings"

// Tests of the eraser, driven with simulated pointer and pen input. Results are judged by what renders.

@(private = "file")
RED :: Color{220, 30, 40, 255}

@(private = "file")
add_box :: proc(d: ^Doc, x, y, w, h: f32, fill := RED) -> ^Node {
	n := new_shape(d, .Rect)
	n.x, n.y, n.w, n.h = x, y, w, h
	n.fill, n.stroke = paint_solid(fill), paint_none()
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

@(private = "file")
add_line :: proc(d: ^Doc, a, b: Vec2, cap := Cap.Butt) -> ^Node {
	n := new_shape(d, .Path)
	path_move(&n.segs, a)
	path_line(&n.segs, b)
	n.fill, n.stroke = paint_none(), paint_solid(RED)
	n.sw, n.cap = 4, cap
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

@(private = "file")
pixel :: proc(d: ^Doc, x, y: int) -> Color {
	pix, w, _ := render_to_pixels(d, 1, WHITE, true)
	return pix[y * w + x]
}

@(private = "file")
count_kind :: proc(segs: []Seg, k: Seg_Kind) -> int {
	c := 0
	for g in segs do if g.kind == k do c += 1
	return c
}

@(private = "file")
fuzz_next :: proc(s: ^u32) -> f32 {
	s^ = s^ * 1664525 + 1013904223
	return f32(s^ >> 8) / f32(1 << 24)
}

eraser_selftest :: proc(t: ^Test_Run) {
	ui.shift, ui.alt, ui.ctrl, ui.dbl_click = false, false, false, false
	saved_size, saved_pressure, saved_pen := eraser_size, eraser_pressure, pen
	defer {
		eraser_size, eraser_pressure, pen = saved_size, saved_pressure, saved_pen
		ui.pressed[0], ui.down[0] = false, false
		doc = nil
	}
	pen = {}
	eraser_size = 20

	// a stroke across a shape cuts it in two, as one object
	{
		d := sim_doc()
		n := add_box(d, 100, 100, 200, 100)
		name_set(&n.name, "Box")
		n.stroke, n.sw = paint_solid({0, 0, 255, 255}), 3
		uid := n.uid
		undo_before := len(d.undo)
		cur_tool = .Eraser
		sim_drag(d, {50, 150}, {350, 150}, 30)
		check(t, len(d.root.children) == 1 && d.root.children[0].uid == uid, "a cut shape stays the same object")
		check(t, len(d.undo) == undo_before + 1, "a stroke is one undo step")
		m := d.root.children[0]
		check(t, m.kind == .Path && count_kind(m.segs[:], .Move) == 2 && count_kind(m.segs[:], .Close) == 2, "a stroke across a shape leaves two closed parts")
		check(t, len(m.segs) <= 20, fmt.tprintf("the cut has few points (%d segments)", len(m.segs)))
		check(t, name_str(&m.name) == "Box" && m.stroke.color == Color{0, 0, 255, 255} && m.sw == 3 && m.fill.color == RED, "a cut shape keeps its name and style")
		check(t, pixel(d, 200, 150) == WHITE, "what the stroke covered is gone")
		check(t, pixel(d, 200, 125) == RED && pixel(d, 200, 175) == RED, "what it did not cover stays")
		check(t, pixel(d, 150, 137) == RED && pixel(d, 150, 144) == WHITE, "the cut is as wide as the eraser")
		history_undo(d)
		u := d.root.children[0]
		check(t, u.kind == .Rect && name_str(&u.name) == "Box" && pixel(d, 200, 150) == RED, "undo brings the shape back")
		history_redo(d)
		check(t, d.root.children[0].kind == .Path && pixel(d, 200, 150) == WHITE, "redo cuts it again")
	}

	// a slanted stroke at whole pixels, as a mouse gives, is still a clean cut
	{
		d := sim_doc()
		n := add_box(d, 40, 80, 300, 140)
		cur_tool = .Eraser
		sim(d, 20, 120, true, true)
		for i in 1 ..= 80 {
			x, y := 20 + f32(i) * 4, 120 + f32(i) * 0.75
			sim(d, math.round(x), math.round(y), false, true)
		}
		sim(d, 340, 180, false, false)
		anchors := len(n.segs) - count_kind(n.segs[:], .Move) - count_kind(n.segs[:], .Close)
		check(t, count_kind(n.segs[:], .Move) == 2 && anchors <= 22, fmt.tprintf("a stroke at whole pixels leaves few points (%d)", anchors))
	}

	// partial cuts, and untouched shapes
	{
		d := sim_doc()
		bite := add_box(d, 20, 20, 100, 100)
		hole := add_box(d, 150, 20, 100, 100)
		away := add_box(d, 280, 20, 100, 100)
		name_set(&bite.name, "Rectangle")
		bite_id, away_id := bite.uid, away.uid
		cur_tool = .Eraser
		sim_drag(d, {70, 0}, {70, 60}, 10)
		bn := node_find(d.root, bite_id)
		check(t, count_kind(bn.segs[:], .Move) == 1 && pixel(d, 70, 40) == WHITE && pixel(d, 70, 90) == RED && pixel(d, 40, 40) == RED, "a stroke from outside takes a bite")
		check(t, name_str(&bn.name) == "Path", "a rectangle that became a path says so")
		sim_click(d, {200, 70})
		check(t, pixel(d, 200, 70) == WHITE && pixel(d, 200, 50) == RED && pixel(d, 180, 70) == RED, "a click makes a hole")
		check(t, node_find(d.root, away_id).kind == .Rect, "a shape the stroke misses stays a rectangle")
		before := len(d.undo)
		sim_drag(d, {10, 290}, {390, 290}, 8)
		check(t, len(d.undo) == before, "a stroke that erases nothing makes no undo step")
		_ = hole

		// a stroke that encloses a part leaves it there
		di := sim_doc()
		add_box(di, 100, 100, 200, 150)
		ring := make([dynamic]Vec2, context.temp_allocator)
		for i in 0 ..= 48 {
			a := f32(i) / 48 * math.TAU
			append(&ring, Vec2{200, 175} + Vec2{math.cos(a), math.sin(a)} * 50)
		}
		sim(di, ring[0].x, ring[0].y, true, true)
		for q in ring[1:] do sim(di, q.x, q.y, false, true)
		sim(di, ring[0].x, ring[0].y, false, false)
		check(t, pixel(di, 200, 175) == RED && pixel(di, 250, 175) == WHITE && pixel(di, 110, 110) == RED, "an island inside a ring stays")
	}

	// erasing everything removes the object, and a group left empty
	{
		d := sim_doc()
		g := node_new(d, .Group)
		name_set(&g.name, "Group")
		c := new_shape(d, .Rect)
		c.x, c.y, c.w, c.h = 100, 100, 8, 8
		c.fill, c.stroke = paint_solid(RED), paint_none()
		append(&g.children, c)
		append(&d.root.children, g)
		add_box(d, 300, 200, 20, 20)
		sel_set(d, g)
		append(&d.sel, d.root.children[1].uid)
		cur_tool = .Eraser
		sim_click(d, {104, 104})
		check(t, len(d.root.children) == 1 && d.root.children[0].kind == .Rect, "an object with nothing left goes, and so does its empty group")
		check(t, len(d.sel) == 1, "and it leaves the selection")
		history_undo(d)
		check(t, len(d.root.children) == 2 && d.root.children[0].kind == .Group && len(d.root.children[0].children) == 1, "undo brings them back")
	}

	// lines are split, and stay lines
	{
		d := sim_doc()
		n := add_line(d, {50, 50}, {350, 50})
		cur_tool = .Eraser
		sim_drag(d, {200, 10}, {200, 90}, 10)
		check(t, count_kind(n.segs[:], .Move) == 2 && count_kind(n.segs[:], .Close) == 0, "a line is split in two lines, with no closing edge")
		check(t, n.fill.kind == .None && n.stroke.kind == .Solid, "the parts keep the line's style")
		check(t, len(n.segs) == 4 && n.segs[0].p == Vec2{50, 50} && n.segs[3].p == Vec2{350, 50}, "the far ends don't move")
		check(t, near(n.segs[1].p.x, 190) && near(n.segs[2].p.x, 210), "the cut is where the eraser's edge was")
		check(t, pixel(d, 200, 50) == WHITE && pixel(d, 150, 50) == RED, "the gap shows")

		// round caps would poke into the gap
		dr := sim_doc()
		rn := add_line(dr, {50, 50}, {350, 50}, .Round)
		sim_drag(dr, {200, 10}, {200, 90}, 10)
		check(t, near(rn.segs[1].p.x, 188) && near(rn.segs[2].p.x, 212), "the eraser clears a line's round caps too")

		// a stroke along a line removes it
		da := sim_doc()
		add_line(da, {50, 50}, {150, 50})
		sim_drag(da, {30, 50}, {170, 50}, 12)
		check(t, len(da.root.children) == 0, "a line erased from end to end goes")

		// curves keep their exact shape outside the cut
		dc := sim_doc()
		cn := new_shape(dc, .Path)
		path_move(&cn.segs, {20, 150})
		path_cubic(&cn.segs, {60, 40}, {120, 40}, {160, 150})
		path_cubic(&cn.segs, {200, 260}, {260, 260}, {300, 150})
		cn.fill, cn.stroke, cn.sw = paint_none(), paint_solid(RED), 2
		append(&dc.root.children, cn)
		second := cn.segs[2]
		sim_drag(dc, {90, 20}, {90, 150}, 10)
		check(t, count_kind(cn.segs[:], .Cubic) == 3 && count_kind(cn.segs[:], .Line) == 0, "a curve is cut into curves")
		check(t, cn.segs[len(cn.segs) - 1] == second, "a segment the eraser misses is untouched")

		// an outline with no fill is a line too
		dl := sim_doc()
		box := add_box(dl, 100, 100, 200, 100)
		box.fill, box.stroke, box.sw = paint_none(), paint_solid(RED), 4
		sim_drag(dl, {200, 80}, {200, 120}, 6)
		check(t, box.kind == .Path && count_kind(box.segs[:], .Close) == 0 && count_kind(box.segs[:], .Move) == 1, "a closed outline with no fill opens up where it is cut")
		check(t, box.segs[0].p != box.segs[len(box.segs) - 1].p && pixel(dl, 200, 100) == WHITE && pixel(dl, 100, 150) == RED, "and the rest of it stays in one piece")
		sim_drag(dl, {200, 180}, {200, 220}, 6)
		check(t, count_kind(box.segs[:], .Move) == 2, "a second cut makes two pieces")
	}

	// what can and can't be erased
	{
		d := sim_doc()
		under := add_box(d, 100, 100, 100, 100)
		over_box := add_box(d, 100, 100, 100, 100, {0, 200, 0, 255})
		sel_set(d, under)
		cur_tool = .Eraser
		sim_click(d, {150, 150})
		check(t, under.kind == .Path && over_box.kind == .Rect, "with a selection, only it is erased")
		clear(&d.sel)
		sim_click(d, {120, 120})
		check(t, over_box.kind == .Path && pixel(d, 120, 120) == WHITE, "without one, the stroke erases what it passes over")
		status_t = 0
		other := add_box(d, 300, 200, 50, 50)
		sel_set(d, under)
		sim_click(d, {325, 225})
		check(t, other.kind == .Rect && status_t > 0, "a stroke that misses the selection says why nothing happened")

		dl := sim_doc()
		locked := add_box(dl, 20, 20, 50, 50)
		locked.locked = true
		hidden := add_box(dl, 90, 20, 50, 50)
		hidden.visible = false
		lg := node_new(dl, .Group)
		name_set(&lg.name, "Group")
		lg.locked = true
		inner := new_shape(dl, .Rect)
		inner.x, inner.y, inner.w, inner.h = 160, 20, 50, 50
		inner.fill, inner.stroke = paint_solid(RED), paint_none()
		append(&lg.children, inner)
		append(&dl.root.children, lg)
		sim_drag(dl, {0, 45}, {230, 45}, 30)
		check(t, locked.kind == .Rect && hidden.kind == .Rect && inner.kind == .Rect, "locked and hidden objects, and what's in a locked group, are safe")

		dt := sim_doc()
		tx := new_shape(dt, .Text)
		tx.x, tx.y, tx.size = 100, 100, 40
		append(&tx.text, ..transmute([]u8)string("Hi"))
		append(&dt.root.children, tx)
		doc_changed(dt)
		status_t = 0
		b := node_doc_bounds(dt, tx)
		c := bounds_center(b)
		sim_click(dt, c)
		check(t, tx.kind == .Text && text_str(tx) == "Hi", "text stays text")
		check(t, status_t > 0 && strings.contains(name_str(&status_msg), "Text"), "and the status bar says what to do")
	}

	// the cut lands in the right place under transforms and zoom, and gradients stay put
	{
		d := sim_doc()
		g := node_new(d, .Group)
		name_set(&g.name, "Group")
		g.xf = mat_mul(mat_translate(200, 150), mat_rotate(deg2rad(30)))
		c := new_shape(d, .Rect)
		c.x, c.y, c.w, c.h = -40, -20, 40, 20
		c.xf = mat_scale(2, 2)
		c.fill = paint_make_gradient(paint_solid(RED), Bounds{-40, -20, 0, 0}, false)
		c.stroke = paint_none()
		g0, g1 := c.fill.p0, c.fill.p1
		append(&g.children, c)
		append(&d.root.children, g)
		xf, gxf := c.xf, g.xf
		cur_tool = .Eraser
		sim_click(d, {200, 150})
		check(t, c.xf == xf && g.xf == gxf, "a cut keeps the object's transform")
		check(t, c.fill.kind == .Linear && c.fill.p0 == g0 && c.fill.p1 == g1, "and its gradient")
		check(t, pixel(d, 200, 150) == WHITE, "the cut is under the pointer")
		corner := mat_apply(node_world(d.root, c), Vec2{-30, -15})
		check(t, pixel(d, int(corner.x), int(corner.y)).a == 255 && pixel(d, int(corner.x), int(corner.y)) != WHITE, "the rest stays")

		// the size is in screen pixels
		dz := sim_doc()
		add_box(dz, 100, 100, 100, 100)
		dz.zoom, dz.ox, dz.oy = 4, -300, -300
		sp := to_screen(dz, {150, 150})
		sim(dz, sp.x, sp.y, true, true)
		sim(dz, sp.x, sp.y, false, false)
		// 20 screen pixels across at 4x zoom is a radius of 2.5 in the document
		check(t, pixel(dz, 150, 150) == WHITE && pixel(dz, 150, 148) == WHITE, "zoomed in, the cut is the eraser's size on screen")
		check(t, pixel(dz, 150, 145) == RED && pixel(dz, 150, 155) == RED, "and no bigger")

		// tiny documents work: path_boolean's grid and its smallest loop are in absolute units
		di := sim_doc()
		add_box(di, 4, 4, 4, 4)
		di.zoom, di.ox, di.oy = 40, 0, 0
		sim(di, 240, 240, true, true)
		sim(di, 240, 240, false, false)
		ic := di.root.children[0]
		check(t, ic.kind == .Path && count_kind(ic.segs[:], .Move) == 2, "a fine cut in a tiny shape works")
		fp, fw, _ := render_to_pixels(di, 20, WHITE, true)
		check(t, fp[120 * fw + 120] == WHITE && fp[90 * fw + 90] == RED, "and lands in the right place")
	}

	// the even-odd rule: a hole stays a hole
	{
		d := sim_doc()
		n := new_shape(d, .Path)
		path_rect(&n.segs, 100, 100, 200, 100, 0, 0)
		path_rect(&n.segs, 150, 125, 100, 50, 0, 0)
		n.fill, n.stroke, n.even_odd = paint_solid(RED), paint_none(), true
		append(&d.root.children, n)
		doc_changed(d)
		check(t, pixel(d, 200, 150) == WHITE, "an even-odd shape has a hole")
		cur_tool = .Eraser
		sim_click(d, {120, 150})
		check(t, pixel(d, 200, 150) == WHITE && pixel(d, 120, 150) == WHITE && pixel(d, 110, 110) == RED, "a cut keeps an even-odd shape's hole")
		check(t, pixel(d, 275, 150) == RED, "and the rest of it")
	}

	// interrupted strokes, frames and files
	{
		d := sim_doc()
		add_box(d, 100, 100, 4, 4)
		big := add_box(d, 200, 100, 100, 100)
		undo_before := len(d.undo)
		cur_tool = .Eraser
		sim(d, 102, 102, true, true)
		sim(d, 250, 150, false, true)
		check(t, tl.kind == .Erase && len(d.root.children[0].segs) == 0, "the cut shows during the stroke")
		set_tool(.Select)
		check(t, len(d.root.children) == 1 && d.root.children[0] == big && tl.kind == .None, "switching tools ends the stroke, leaving nothing half erased")
		check(t, len(d.undo) == undo_before + 1, "and it is one undo step")

		df := sim_doc()
		add_box(df, 100, 100, 100, 100)
		run_cmd(.Frame_Dup)
		cur_tool = .Eraser
		sim_click(df, {150, 150})
		check(t, df.root.children[0].kind == .Path && df.frames[0].root.children[0].kind == .Rect, "only the current frame is erased")

		// saved and read back
		dr := sim_doc()
		add_box(dr, 100, 100, 200, 100)
		lin := add_line(dr, {50, 50}, {350, 50})
		sim_drag(dr, {200, 30}, {200, 150}, 20)
		s := svg_string(dr)
		back, ok := svg_parse(s)
		check(t, ok && len(back.root.children) == 2, "an erased drawing opens")
		if ok && len(back.root.children) == 2 {
			check(t, count_kind(back.root.children[1].segs[:], .Move) == 2 && count_kind(back.root.children[1].segs[:], .Close) == 0, "a cut line is still open after a save")
			check(t, pixel(back, 200, 140) == WHITE && pixel(back, 150, 140) == RED, "a cut shape looks the same after a save")
		}
		doc_free(back)
		_ = lin
	}

	// the pen's eraser end
	{
		pen.in_range, pen.eraser = true, true
		tool_groups_default()
		d := sim_doc()
		for tool in ([]Tool{.Select, .Node, .Control, .Pen, .Freehand, .Rect, .Ellipse, .Line}) {
			cur_tool = tool
			check(t, eff_tool() == .Eraser, fmt.tprintf("the eraser end erases with the %v tool", tool))
		}
		for tool in ([]Tool{.Text, .Picker, .Hand, .Zoom}) {
			cur_tool = tool
			check(t, eff_tool() == tool, fmt.tprintf("the eraser end leaves the %v tool alone", tool))
		}

		// a stroke with it, with the tip's tool kept
		n := add_box(d, 100, 100, 200, 100)
		cur_tool = .Rect
		sim_drag(d, {50, 150}, {350, 150}, 20)
		check(t, len(d.root.children) == 1 && n.kind == .Path && pixel(d, 200, 150) == WHITE, "the eraser end erases instead of drawing a rectangle")
		check(t, cur_tool == .Rect, "and the pen tip keeps its tool")
		pen.eraser = false
		check(t, eff_tool() == .Rect, "the pen tip works as before")
		sim_drag(d, {10, 10}, {60, 60})
		check(t, len(d.root.children) == 2 && d.root.children[1].kind == .Rect, "and draws its rectangle")

		// flipping the pen mid-stroke doesn't change the gesture's tool
		pen.eraser = true
		clear(&d.sel)
		sim(d, 320, 250, true, true)
		pen.eraser = false
		check(t, eff_tool() == .Eraser, "a stroke keeps its tool if the pen stops reporting the eraser end")
		sim(d, 325, 250, false, false)
		check(t, eff_tool() == .Rect, "until it ends")

		// a path being drawn is finished, not corrupted
		dp := sim_doc()
		pen.eraser = false
		cur_tool = .Pen
		sim_click(dp, {50, 50})
		sim_click(dp, {150, 50})
		sim_click(dp, {250, 50})
		pen.eraser = true
		sim_drag(dp, {150, 30}, {150, 70}, 6)
		check(t, tl.pen_uid == 0 && len(tl.pen_pts) == 0, "the eraser end finishes a path being drawn")
		check(t, len(dp.root.children) == 1 && count_kind(dp.root.children[0].segs[:], .Move) == 2, "and cuts it like any other line")

		// pressure sets the width
		pen.touching, pen.pressure = true, 0.2
		eraser_pressure = true
		cur_tool = .Select
		dw := sim_doc()
		add_box(dw, 100, 100, 100, 100)
		sim(dw, 150, 150, true, true)
		for _ in 0 ..< 3 do sim(dw, 150, 150, false, true)
		pen.touching = false
		sim(dw, 150, 150, false, false)
		check(t, pixel(dw, 150, 150) == WHITE && pixel(dw, 150, 142) == RED, "a light touch erases narrowly")
		dw2 := sim_doc()
		add_box(dw2, 100, 100, 100, 100)
		eraser_pressure = false
		pen.touching, pen.pressure = true, 0.2
		sim(dw2, 150, 150, true, true)
		pen.touching = false
		sim(dw2, 150, 150, false, false)
		check(t, pixel(dw2, 150, 142) == WHITE, "with Pressure off the width stays")
		eraser_pressure = true
		pen = {}

		// a group for the eraser end, as in Paints and Pixels
		tool_groups_default()
		set_tool(.Select)
		group_set_pen_eraser(0)
		group_set_pen_eraser(2)
		check(t, !tool_groups[0].pen_eraser && tool_groups[2].pen_eraser, "only one group serves the pen eraser")
		check(t, name_str(&tool_groups[2].name) == "Shapes", "it keeps its name")
		tool_groups[2].last = .Ellipse
		pen.in_range, pen.eraser = true, true
		pt, has := pen_eraser_group_tool()
		check(t, has && pt == .Ellipse && eff_tool() == .Ellipse && cur_tool == .Select, "the eraser end uses that group's tool, the tip keeps its own")
		dg := sim_doc()
		sim_drag(dg, {10, 10}, {60, 60})
		check(t, len(dg.root.children) == 1 && dg.root.children[0].kind == .Ellipse && cur_tool == .Select, "and that tool really runs")
		tool_group_activate(2)
		check(t, tool_groups[2].last == .Rect && cur_tool == .Select, "the group's hotkey only changes the eraser end's tool")
		sim_drag(dg, {100, 100}, {160, 160})
		check(t, len(dg.root.children) == 2 && dg.root.children[1].kind == .Rect, "and the next stroke uses it")
		set_tool(.Rect)
		check(t, current_group() != 2, "the eraser's group doesn't hold the pen tip's tool")
		s := tool_groups_serialize()
		tool_groups_parse(s)
		check(t, tool_groups[2].pen_eraser && !tool_groups[0].pen_eraser, "the pen eraser group is saved with the groups")
		tool_groups_parse("49:Pen:Old:")
		check(t, len(tool_groups) == 1 && !tool_groups[0].pen_eraser && name_str(&tool_groups[0].name) == "Old", "groups saved before the pen eraser option still load")
		tool_groups_parse("49:Pen:A:::1;50:Rect:B:::1")
		check(t, tool_groups[0].pen_eraser && !tool_groups[1].pen_eraser, "at most one group loads as the pen eraser's")
		group_set_pen_eraser(0)
		check(t, !tool_groups[0].pen_eraser, "choosing it again clears it")
		pen = {}
		tool_groups_default()
		set_tool(.Select)
	}

	// settings
	{
		prefs_parse("eraser_size=33\neraser_pressure=0\n")
		check(t, eraser_size == 33 && !eraser_pressure, "the eraser's settings are read from the preferences")
		prefs_parse("eraser_size=99999\n")
		check(t, eraser_size == ERASER_SIZE_MAX, "and kept in range")
		eraser_size, eraser_pressure = 20, true
		check(t, !tool_is_toggle(.Eraser), "the eraser is a tool, not a switch")
	}

	// random scribbles over shapes: everything the stroke covered is gone, nothing else is, during and after it
	{
		bad_live, bad_end := 0, 0
		seeds := make([dynamic]int, context.temp_allocator)
		for seed in 1 ..= 24 do append(&seeds, seed)
		// these broke the boolean's links between edges, until it repeated its search for crossings
		append(&seeds, 69, 148, 222, 396, 413, 465, 483, 501, 581, 586)
		for seed in seeds {
			s := u32(seed) * 2654435761
			d := sim_doc()
			zooms := [3]f32{1, 2.5, 0.5}
			d.zoom = zooms[seed % 3]
			d.ox, d.oy = (1 - d.zoom) * 200, (1 - d.zoom) * 150
			kind := seed % 4
			n: ^Node
			switch kind {
			case 0:
				n = add_box(d, 80, 60, 240, 180)
			case 1:
				n = new_shape(d, .Ellipse)
				n.x, n.y, n.w, n.h = 200, 150, 130, 90
				n.fill, n.stroke = paint_solid(RED), paint_none()
				n.xf = mat_mul(mat_translate(200, 150), mat_mul(mat_rotate(deg2rad(25)), mat_translate(-200, -150)))
				append(&d.root.children, n)
			case 2:
				n = new_shape(d, .Path)
				path_move(&n.segs, {80, 240})
				path_cubic(&n.segs, {60, 40}, {340, 40}, {320, 240})
				path_quad(&n.segs, {200, 120}, {80, 240})
				path_close(&n.segs)
				n.fill, n.stroke = paint_solid(RED), paint_none()
				append(&d.root.children, n)
			case 3:
				n = new_shape(d, .Path)
				path_rect(&n.segs, 80, 60, 240, 180, 0, 0)
				path_rect(&n.segs, 160, 120, 80, 60, 0, 0)
				n.fill, n.stroke, n.even_odd = paint_solid(RED), paint_none(), true
				append(&d.root.children, n)
			}
			doc_changed(d)
			orig: Polys
			defer polys_free(&orig)
			path_flatten(node_segs(n), node_world(d.root, n), 0.1, &orig)
			even_odd := n.even_odd

			cur_tool = .Eraser
			eraser_size = 10 + int(fuzz_next(&s) * 50)
			r := f32(eraser_size) / 2 / d.zoom
			pts := make([dynamic]Vec2, context.temp_allocator)
			p := Vec2{40 + fuzz_next(&s) * 320, 40 + fuzz_next(&s) * 220}
			append(&pts, p)
			for _ in 0 ..< 10 + int(fuzz_next(&s) * 90) {
				ang := fuzz_next(&s) * math.TAU
				q := p + Vec2{math.cos(ang), math.sin(ang)} * (3 + fuzz_next(&s) * 45)
				q = {clamp(q.x, 10, 390), clamp(q.y, 10, 290)}
				if v_len(q - p) > 1 / d.zoom {
					append(&pts, q)
					p = q
				}
			}
			check_now :: proc(d: ^Doc, pts: []Vec2, r: f32, orig: ^Polys, even_odd: bool, zoom: f32) -> int {
				pix, w, h := render_to_pixels(d, 1, WHITE, true)
				bad := 0
				// the eraser drops points closer than this, so its stroke can differ from pts by as much
				m := max(1.6, r * 0.3)
				for y := 2; y < h - 2; y += 3 {
					for x := 2; x < w - 2; x += 3 {
						q := Vec2{f32(x) + 0.5, f32(y) + 0.5}
						edge := polys_distance(orig, q)
						if edge < 2 do continue
						inside := polys_contains(orig, q, even_odd)
						want := WHITE
						if inside {
							dist := max(f32)
							for i in 0 ..< len(pts) - 1 do dist = min(dist, dist_to_segment(q, pts[i], pts[i + 1]))
							if len(pts) == 1 do dist = v_len(q - pts[0])
							if abs(dist - r) < m do continue
							if dist > r do want = RED
						}
						if pix[y * w + x] != want do bad += 1
					}
				}
				return bad
			}
			sp := to_screen(d, pts[0])
			sim(d, sp.x, sp.y, true, true)
			for i in 1 ..< len(pts) {
				sp = to_screen(d, pts[i])
				sim(d, sp.x, sp.y, false, true)
				if i == len(pts) / 2 do bad_live += check_now(d, pts[:i + 1], r, &orig, even_odd, d.zoom)
			}
			sim(d, sp.x, sp.y, false, false)
			bad_end += check_now(d, pts[:], r, &orig, even_odd, d.zoom)
		}
		check(t, bad_live == 0, fmt.tprintf("random strokes are right during the stroke (%d pixels wrong)", bad_live))
		check(t, bad_end == 0, fmt.tprintf("random strokes are right after the stroke (%d pixels wrong)", bad_end))
		eraser_size = 20
	}

	// random strokes over lines: nothing is left under the stroke, and everything away from it is still there
	{
		left_under, lost, closed_edges := 0, 0, 0
		for seed in 1 ..= 40 {
			s := u32(seed) * 2654435761
			d := sim_doc()
			n := new_shape(d, .Path)
			n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 1
			n.cap = seed % 2 == 0 ? Cap.Butt : Cap.Round
			switch seed % 3 {
			case 0:
				path_move(&n.segs, {30, 150})
				path_cubic(&n.segs, {80, 10}, {160, 10}, {200, 150})
				path_quad(&n.segs, {280, 290}, {370, 150})
				path_line(&n.segs, {370, 40})
			case 1:
				path_rect(&n.segs, 60, 50, 280, 200, 0, 0)
			case 2:
				path_move(&n.segs, {40, 60})
				path_line(&n.segs, {360, 90})
				path_line(&n.segs, {50, 200})
				path_line(&n.segs, {350, 260})
				path_move(&n.segs, {200, 20})
				path_cubic(&n.segs, {300, 80}, {100, 200}, {200, 280})
			}
			n.xf = mat_mul(mat_translate(200, 150), mat_mul(mat_rotate(deg2rad(f32(seed))), mat_translate(-200, -150)))
			append(&d.root.children, n)
			doc_changed(d)
			orig: Polys
			defer polys_free(&orig)
			path_flatten(n.segs[:], node_world(d.root, n), 0.1, &orig)
			uid := n.uid
			extra := n.cap == .Round ? n.sw / 2 : 0

			cur_tool = .Eraser
			eraser_size = 8 + int(fuzz_next(&s) * 40)
			r := f32(eraser_size) / 2
			pts := make([dynamic]Vec2, context.temp_allocator)
			p := Vec2{40 + fuzz_next(&s) * 320, 40 + fuzz_next(&s) * 220}
			append(&pts, p)
			sim(d, p.x, p.y, true, true)
			for _ in 0 ..< 8 + int(fuzz_next(&s) * 40) {
				ang := fuzz_next(&s) * math.TAU
				q := p + Vec2{math.cos(ang), math.sin(ang)} * (3 + fuzz_next(&s) * 40)
				q = {clamp(q.x, 10, 390), clamp(q.y, 10, 290)}
				if v_len(q - p) < 1 do continue
				append(&pts, q)
				sim(d, q.x, q.y, false, true)
				p = q
			}
			sim(d, p.x, p.y, false, false)

			stroke_dist :: proc(q: Vec2, pts: []Vec2) -> f32 {
				dist := v_len(q - pts[0])
				for i in 0 ..< len(pts) - 1 do dist = min(dist, dist_to_segment(q, pts[i], pts[i + 1]))
				return dist
			}
			// the eraser drops points closer than a quarter of its radius, so its stroke differs from pts by that much
			m := max(r * 0.3, 1.0)
			left: Polys
			defer polys_free(&left)
			if cn := node_find(d.root, uid); cn != nil {
				if len(cn.segs) > 0 do path_flatten(cn.segs[:], node_world(d.root, cn), 0.1, &left)
				// a cut closed outline has no closing edge; one with no cut keeps its own
				if len(pts) > 0 && count_kind(cn.segs[:], .Move) != count_kind(cn.segs[:], .Close) && count_kind(cn.segs[:], .Close) > 0 && seed % 3 == 1 do closed_edges += 1
			}
			for v in left.pts {
				if stroke_dist(v, pts[:]) < r + extra - m do left_under += 1
			}
			for sb in orig.subs {
				n_pts := sb.b - sb.a
				count := sb.closed ? n_pts : n_pts - 1
				for i in 0 ..< count {
					a, b := orig.pts[sb.a + i], orig.pts[sb.a + (i + 1) % n_pts]
					steps := max(int(v_len(b - a) / 6), 1)
					for k in 0 ..= steps {
						v := a + (b - a) * (f32(k) / f32(steps))
						if stroke_dist(v, pts[:]) > r + extra + m && polys_distance(&left, v) > 0.5 do lost += 1
					}
				}
			}
		}
		check(t, left_under == 0, fmt.tprintf("nothing of a line is left under the stroke (%d points)", left_under))
		check(t, lost == 0, fmt.tprintf("a line away from the stroke stays (%d points lost)", lost))
		check(t, closed_edges == 0, fmt.tprintf("a cut outline has no closing edge (%d)", closed_edges))
		eraser_size = 20
	}
}
