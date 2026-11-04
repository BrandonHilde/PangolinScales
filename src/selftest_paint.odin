package pangolin

import "core:fmt"
import "core:strings"

// Tests of Change Fill and Change Stroke.

@(private = "file")
BLUE :: Color{20, 60, 200, 255}
@(private = "file")
GREEN :: Color{10, 180, 70, 255}

@(private = "file")
box :: proc(d: ^Doc, x, y: f32, c := BLUE) -> ^Node {
	n := new_shape(d, .Rect)
	n.x, n.y, n.w, n.h = x, y, 100, 50
	n.fill, n.stroke = paint_solid(c), paint_solid(GREEN)
	n.sw = 2
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

change_paint_selftest :: proc(t: ^Test_Run) {
	ui.shift, ui.alt, ui.ctrl, ui.dbl_click = false, false, false, false
	saved_fill, saved_stroke, saved_sw, saved_time := cur_fill, cur_stroke, cur_sw, ui.time
	defer {
		cur_fill, cur_stroke, cur_sw, ui.time = saved_fill, saved_stroke, saved_sw, saved_time
		prop_target = 0
		tool_groups_default()
		doc = nil
	}

	// a round through the types
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		prop_target = 1
		order := [?]Paint_Kind{.Linear, .Radial, .None, .Solid}
		names := [?]string{"Fill: Linear gradient", "Fill: Radial gradient", "Fill: None", "Fill: Solid"}
		for k, i in order {
			run_cmd(.Change_Fill)
			check(t, n.fill.kind == k, fmt.tprintf("Change Fill steps to %v", k))
			check(t, name_str(&status_msg) == names[i], fmt.tprintf("the status bar says %s", names[i]))
		}
		check(t, n.fill.color == BLUE, "a full round brings a solid color back")
		check(t, n.stroke.kind == .Solid && n.stroke.color == GREEN, "Change Fill leaves the stroke alone")
		check(t, prop_target == 0, "Properties shows the fill")
		run_cmd(.Change_Stroke)
		check(t, n.stroke.kind == .Linear && n.fill.kind == .Solid && prop_target == 1, "Change Stroke changes the stroke, and Properties follows")
		check(t, name_str(&status_msg) == "Stroke: Linear gradient", "the status bar says so")
		for _ in 0 ..< 3 do run_cmd(.Change_Stroke)
		check(t, n.stroke.kind == .Solid && n.stroke.color == GREEN, "a full round brings the stroke back too")
	}

	// a gradient fits the object, and comes from its color
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		run_cmd(.Change_Fill)
		check(t, n.fill.p0 == Vec2{50, 85} && n.fill.p1 == Vec2{150, 85}, "a linear gradient spans the object")
		check(t, n.fill.nstops == 2 && n.fill.stops[0].color == BLUE, "and starts from its color")
		pix, w, _ := render_to_pixels(d, 1, WHITE, true)
		left, right := pix[85 * w + 53], pix[85 * w + 147]
		check(t, left.b > right.b + 60, "and shows as one")
		run_cmd(.Change_Fill)
		check(t, n.fill.p0 == Vec2{100, 85} && n.fill.p1.x == 50, "a radial gradient is centered on the object")
	}

	// nothing is lost going round
	{
		d := sim_doc()
		n := box(d, 50, 60)
		n.fill = paint_make_gradient(paint_solid(BLUE), node_local_bounds(n), false)
		n.fill.nstops = 3
		n.fill.stops[1] = Stop{0.5, GREEN}
		n.fill.stops[2] = Stop{1, Color{200, 10, 10, 255}}
		stops := n.fill.stops
		sel_set(d, n)
		for _ in 0 ..< 4 do run_cmd(.Change_Fill)
		check(t, n.fill.kind == .Linear && n.fill.nstops == 3 && n.fill.stops == stops, "a full round keeps a gradient's stops")
		run_cmd(.Change_Fill) // radial
		run_cmd(.Change_Fill) // none
		run_cmd(.Change_Fill) // solid
		check(t, n.fill.kind == .Solid && n.fill.color == BLUE, "the first stop's color is the solid color")
		n.fill.color = GREEN // edited in Properties
		run_cmd(.Change_Fill)
		check(t, n.fill.kind == .Linear && n.fill.nstops == 2 && n.fill.stops[0].color == GREEN, "a color edited since then starts a new gradient")
	}

	// several objects keep their own colors and bounds
	{
		d := sim_doc()
		a := box(d, 20, 20, BLUE)
		b := box(d, 200, 200, GREEN)
		sel_set(d, a)
		append(&d.sel, b.uid)
		run_cmd(.Change_Fill)
		check(t, a.fill.kind == .Linear && b.fill.kind == .Linear, "all the selected objects change")
		check(t, a.fill.stops[0].color == BLUE && b.fill.stops[0].color == GREEN, "each keeps its own color")
		check(t, a.fill.p0.x == 20 && b.fill.p0.x == 200, "each gets a gradient across itself")

		// the first decides; the others catch up
		b.fill = paint_none()
		run_cmd(.Change_Fill)
		check(t, a.fill.kind == .Radial && b.fill.kind == .Radial, "objects of different types all go to the first one's next type")
		for _ in 0 ..< 2 do run_cmd(.Change_Fill)
		check(t, a.fill.color == BLUE && b.fill.kind == .Solid && b.fill.color.a == 255, "an object that had no color gets one")
	}

	// groups, locks, and objects with no color or stroke width
	{
		d := sim_doc()
		g := node_new(d, .Group)
		name_set(&g.name, "Group")
		in1 := new_shape(d, .Rect)
		in1.x, in1.y, in1.w, in1.h = 10, 10, 40, 40
		in1.fill = paint_solid(BLUE)
		in2 := new_shape(d, .Rect)
		in2.x, in2.y, in2.w, in2.h = 60, 10, 40, 40
		in2.fill = paint_solid(GREEN)
		in2.locked = true
		append(&g.children, in1, in2)
		append(&d.root.children, g)
		sel_set(d, g)
		run_cmd(.Change_Fill)
		check(t, in1.fill.kind == .Linear, "a selected group's objects change")
		check(t, in2.fill.kind == .Solid && in2.fill.color == GREEN, "but not a locked one")

		ds := sim_doc()
		cur_stroke, cur_sw = paint_solid(GREEN), 3
		parsed, ok := svg_parse(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="50" height="50" fill="none" stroke-width="0"/></svg>`)
		check(t, ok && len(parsed.root.children) == 1, "an object with no paint opens")
		if ok && len(parsed.root.children) == 1 {
			doc = parsed
			n := parsed.root.children[0]
			sel_set(parsed, n)
			run_cmd(.Change_Stroke)
			check(t, n.stroke.kind == .Solid && n.stroke.color == GREEN && n.sw == 3, "a stroke that wasn't there shows, with a width")
			run_cmd(.Change_Fill)
			check(t, n.fill.kind == .Solid && n.fill.color.a == 255, "and a fill that wasn't there shows")
			s := svg_string(parsed)
			check(t, strings.contains(s, "stroke=") && !strings.contains(s, "fill=\"none\""), "and they are saved")
			doc = ds
		}
		doc_free(parsed)
	}

	// undo: a burst of presses is one step, and with no selection there is nothing to undo
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		ui.time = 1000
		last_style_push = 0
		before := len(d.undo)
		run_cmd(.Change_Fill)
		ui.time += 0.2
		run_cmd(.Change_Fill)
		ui.time += 0.2
		run_cmd(.Change_Fill)
		check(t, len(d.undo) == before + 1, "quick presses are one undo step")
		history_undo(d)
		check(t, node_find(d.root, n.uid).fill.kind == .Solid, "undo goes back before them")
		clear(&d.sel)
		before = len(d.undo)
		ui.time += 5
		run_cmd(.Change_Fill)
		check(t, len(d.undo) == before, "with nothing selected there is no undo step")
	}

	// with nothing selected it sets what new shapes get, and their gradient spans them
	{
		cur_fill, cur_stroke = paint_solid(BLUE), paint_solid(GREEN)
		d := sim_doc()
		tools_cancel()
		run_cmd(.Change_Fill)
		check(t, cur_fill.kind == .Linear && cur_fill.stops[0].color == BLUE, "with nothing selected the new-shape fill changes")
		cur_tool = .Rect
		sim_drag(d, {200, 100}, {300, 160})
		r := d.root.children[0]
		check(t, r.fill.kind == .Linear && r.fill.p0 == Vec2{200, 130} && r.fill.p1 == Vec2{300, 130}, "a new rectangle's gradient spans it")
		pix, w, _ := render_to_pixels(d, 1, WHITE, true)
		check(t, pix[130 * w + 205].b > pix[130 * w + 295].b + 60, "so it shows")

		cur_tool = .Ellipse
		sim_drag(d, {20, 200}, {100, 280})
		e := d.root.children[1]
		check(t, e.kind == .Ellipse && e.fill.p0.x == 20 && e.fill.p1.x == 100, "a new ellipse's too")

		clear(&d.sel)
		cur_stroke = paint_make_gradient(paint_solid(GREEN), BOUNDS_EMPTY, false)
		cur_tool = .Freehand
		sim_drag(d, {120, 200}, {220, 240})
		fh := d.root.children[2]
		check(t, fh.stroke.kind == .Linear && fh.stroke.p0.x == 120 && fh.stroke.p1.x == 220, "a freehand stroke's too")

		clear(&d.sel)
		cur_tool = .Pen
		sim_click(d, {240, 200})
		sim_click(d, {340, 200})
		pen_finish(true)
		pn := d.root.children[3]
		check(t, pn.stroke.kind == .Linear && pn.stroke.p0.x == 240 && pn.stroke.p1.x == 340, "and a pen path's")

		// a straight up-and-down line has no width to span
		clear(&d.sel)
		cur_tool = .Line
		sim_drag(d, {380, 10}, {380, 100})
		ln := d.root.children[4]
		check(t, ln.kind == .Path && ln.stroke.kind == .Linear, "a vertical line with a gradient still draws")
		cur_tool = .Select
		cur_fill, cur_stroke = paint_solid(BLUE), paint_solid(GREEN)
	}

	// in a tool group
	{
		sim_doc()
		tool_groups_default()
		fill_op, has := path_op(.Change_Fill)
		_, has2 := path_op(.Change_Stroke)
		check(t, has && has2 && path_op_enabled(fill_op), "both can be added to a group, and work with nothing selected")
		check(t, cmd_help(.Change_Fill) != "" && cmd_help(.Change_Stroke) != "", "and have help text")
		d := doc
		n := box(d, 50, 60)
		sel_set(d, n)
		set_tool(.Select)

		fg := Tool_Group{key = .F, name = make_name("Paint"), last_op = .Change_Fill}
		append(&fg.ops, Cmd.Change_Fill, Cmd.Change_Stroke)
		append(&tool_groups, fg)
		gi := len(tool_groups) - 1
		tool_group_activate(gi)
		check(t, n.fill.kind == .Linear && cur_tool == .Select, "the group's hotkey changes the fill and keeps the tool")
		tool_group_activate(gi)
		check(t, n.fill.kind == .Radial, "pressing it again steps on")
		group_run_op(gi, .Change_Stroke)
		tool_group_activate(gi)
		check(t, n.stroke.kind == .Radial && n.fill.kind == .Radial, "after using the other one, the hotkey repeats that")

		s := tool_groups_serialize()
		tool_groups_parse(s)
		check(t, group_has_op(&tool_groups[gi], .Change_Fill) && group_has_op(&tool_groups[gi], .Change_Stroke) && tool_groups[gi].key == .F, "they are saved with the group")
	}

	// the hotkey, in a group with tools, through the real key handling
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		tool_groups_parse("49:Select,Node,Control:Select:;51:Rect,Ellipse,Node:Shapes:Change_Fill;52:Text,Picker:Text:Simplify;71:::Intersect,Subtract,Union")
		set_tool(.Select)
		key(.THREE)
		check(t, cur_tool == .Rect && n.fill.kind == .Solid, "coming to the group picks its tool, and leaves the fill alone")
		key(.THREE)
		check(t, cur_tool == .Ellipse, "the hotkey steps to the next tool")
		key(.THREE)
		check(t, cur_tool == .Node && n.fill.kind == .Solid, "and the next")
		key(.THREE)
		check(t, n.fill.kind == .Linear && cur_tool == .Node, "after the tools it is Change Fill's turn, and the tool stays")
		check(t, name_str(&status_msg) == "Fill: Linear gradient", "the status bar says what it did")
		check(t, tool_groups[1].turn_op == .Change_Fill, "the group knows where it is")
		key(.THREE)
		check(t, cur_tool == .Rect && n.fill.kind == .Linear, "the next press goes back to the first tool, without changing the fill again")
		check(t, tool_groups[1].turn_op == .None, "and the rotation has moved on")
		for _ in 0 ..< 3 do key(.THREE)
		check(t, cur_tool == .Node && n.fill.kind == .Radial, "the next round steps the fill once more")

		// a tool picked another way
		set_tool(.Rect)
		key(.THREE)
		check(t, cur_tool == .Ellipse, "the rotation carries on from a tool picked another way")
		key(.THREE)
		key(.THREE)
		check(t, n.fill.kind == .None, "and comes to Change Fill again")
		set_tool(.Ellipse)
		key(.THREE)
		check(t, cur_tool == .Node && n.fill.kind == .None, "a tool picked while on Change Fill moves the rotation there")

		// leaving and coming back
		key(.THREE)
		check(t, n.fill.kind == .Solid && tool_groups[1].turn_op == .Change_Fill, "Change Fill's turn again")
		key(.ONE)
		check(t, cur_tool == .Select && tool_groups[1].turn_op == .None, "another group's hotkey leaves the rotation")
		last := tool_groups[1].last
		key(.THREE)
		check(t, cur_tool == last && n.fill.kind == .Solid, "coming back picks the group's last tool and doesn't change the fill")

		// other operations are never run in passing
		before_segs := n.kind
		key(.FOUR)
		key(.FOUR)
		key(.FOUR)
		key(.FOUR)
		check(t, n.kind == before_segs && n.fill.kind == .Solid, "Simplify doesn't take a turn: the hotkey leaves the drawing alone")
		check(t, cur_tool == .Picker || cur_tool == .Text, "and only steps through its group's tools")
	}

	// both of them, and the order
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		tool_groups_parse("80:Pen:Paint:Change_Stroke,Union,Change_Fill")
		set_tool(.Select)
		key(.P)
		check(t, cur_tool == .Pen, "the only tool is picked")
		pen_finish(false)
		// the group holds P, so the single-key shortcut gave way to it: the next press is the first operation's turn
		key(.P)
		check(t, n.stroke.kind == .Linear && n.fill.kind == .Solid, "Change Stroke's turn comes first, as it is first in the group")
		key(.P)
		check(t, n.fill.kind == .Linear && n.stroke.kind == .Linear, "then Change Fill's, skipping Union")
		key(.P)
		check(t, cur_tool == .Pen && tool_groups[0].turn_op == .None, "then back to the tool")
		key(.P)
		check(t, n.stroke.kind == .Radial && n.fill.kind == .Linear, "and round again")

		// one that is taken out while it is its turn
		key(.P)
		check(t, tool_groups[0].turn_op == .Change_Fill, "on Change Fill")
		ordered_remove(&tool_groups[0].ops, 2)
		key(.P)
		check(t, n.stroke.kind == .None && n.fill.kind == .Radial, "taking it out of the group moves the rotation on to the next turn")

		// a group with no tools still repeats
		tool_groups_parse("70::Paint:Change_Fill,Change_Stroke")
		set_tool(.Select)
		dn := sim_doc()
		m := box(dn, 50, 60)
		sel_set(dn, m)
		key(.F)
		key(.F)
		check(t, m.fill.kind == .Radial && m.stroke.kind == .Solid && cur_tool == .Select, "with no tools in the group, the hotkey repeats the same one")

		// the pen eraser's group only sets the eraser end's tool
		tool_groups_parse("51:Rect,Ellipse:Pen:Change_Fill::1")
		set_tool(.Select)
		before := m.fill.kind
		for _ in 0 ..< 3 do key(.THREE)
		check(t, m.fill.kind == before && cur_tool == .Select, "the pen eraser's group doesn't run them")
		tool_groups_default()
	}

	// the file: a changed paint saves and reads back
	{
		d := sim_doc()
		n := box(d, 50, 60)
		sel_set(d, n)
		run_cmd(.Change_Fill)
		run_cmd(.Change_Fill)
		run_cmd(.Change_Stroke)
		back, ok := svg_parse(svg_string(d))
		check(t, ok && len(back.root.children) == 1, "changed paints open again")
		if ok && len(back.root.children) == 1 {
			c := back.root.children[0]
			check(t, c.fill.kind == .Radial && c.stroke.kind == .Linear && c.fill.stops[0].color == BLUE, "with their types and colors")
		}
		doc_free(back)
	}
}
