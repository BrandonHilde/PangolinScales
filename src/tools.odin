package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Viewport interaction: pan / zoom, picking, the select, shape and eyedropper tools, and the shared overlay.
// All gestures work on document space; `pointer()` is the screen position in logical UI pixels.
// ---------------------------------------------------------------------------

Tool :: enum {
	Select,
	Node,
	Control,
	Pen,
	Freehand,
	Eraser,
	Sculpt,
	Extend,
	Rect,
	Ellipse,
	Line,
	Text,
	Picker,
	Hand,
	Zoom,
	// switches: a tool group can hold them, but they turn on and off instead of becoming the tool (switches.odin)
	Grid,
	Snap,
	Onion,
}

TOOL_NAMES := [Tool]string {
	.Select   = "Select (V)",
	.Node     = "Node Edit (A)",
	.Control  = "Control Points (Shift+A)",
	.Pen      = "Pen (P)",
	.Freehand = "Freehand (B)",
	.Eraser   = "Eraser (E)",
	.Sculpt   = "Sculpt (U)",
	.Extend   = "Extend (X)",
	.Rect     = "Rectangle (R)",
	.Ellipse  = "Ellipse (O)",
	.Line     = "Line (L)",
	.Text     = "Text (T)",
	.Picker   = "Eyedropper (I)",
	.Hand     = "Hand (H)",
	.Zoom     = "Zoom (Z)",
	.Grid     = "Grid (Ctrl+;)",
	.Snap     = "Snap to Grid (Ctrl+Shift+;)",
	.Onion    = "Onion Skin (Alt+O)",
}

TOOL_ICONS := [Tool]Icon {
	.Select   = .Pointer,
	.Node     = .Node_Edit,
	.Control  = .Control_Points,
	.Pen      = .Pencil,
	.Freehand = .Brush,
	.Eraser   = .Eraser,
	.Sculpt   = .Sculpt,
	.Extend   = .Extend,
	.Rect     = .Rect,
	.Ellipse  = .Ellipse,
	.Line     = .Line,
	.Text     = .Text,
	.Picker   = .Picker,
	.Hand     = .Hand,
	.Zoom     = .Zoom,
	.Grid     = .Grid,
	.Snap     = .Pixel_Grid,
	.Onion    = .Onion,
}

cur_tool: Tool = .Select

// Grid ---------------------------------------------------------------------------------------------------

show_grid := false
snap_grid := false
grid_size: f32 = 10
smoothing: f32 = 4 // freehand fitting tolerance in screen pixels

snap_pt :: proc(p: Vec2) -> Vec2 {
	if !snap_grid || grid_size <= 0 do return p
	return {math.round(p.x / grid_size) * grid_size, math.round(p.y / grid_size) * grid_size}
}

pointer :: proc() -> Vec2 {
	return ui.ptr / ui.scale
}

// Gesture state -------------------------------------------------------------------------------------------

Drag_Kind :: enum {
	None,
	Move,
	Scale,
	Rotate,
	Marquee,
	Create,
	Anchor,
	Handle,
	Freehand,
	Pen,
	Gradient,
	Erase,
	Sculpt,
	Extend,
}

Orig :: struct {
	uid: u32,
	xf:  Mat,
}

Tool_State :: struct {
	kind:        Drag_Kind,
	stand_in:    bool, // this gesture is using another tool than cur_tool: the pen's eraser end
	stand_tool:  Tool,
	start, cur:  Vec2, // document space
	start_scr:   Vec2,
	moved:       bool,
	pushed:      bool, // history entry made for this gesture
	orig:        [dynamic]Orig,
	bbox:        Bounds, // selection bounds when the gesture began
	handle:      int,
	create_uid:  u32,
	free_pts:    [dynamic]Vec2,
	// pen
	pen_uid:     u32,
	pen_pts:     [dynamic]Pen_Pt,
	// node editing
	anchors:     [dynamic]int, // selected segment indices of the edited path
	hs:          Handle_Ref, // dragged handle
	edit_uid:    u32,
	// control point tool
	ctrl_sel:    Handle_Ref, // selected control point, if ctrl_on
	ctrl_on:     bool,
	ctrl_cycle:  bool, // a click without a drag steps to the next overlapping control point
	// text
	text_uid:    u32,
}

tl: Tool_State

tl_reset :: proc() {
	tl.kind = .None
	tl.moved, tl.pushed = false, false
	clear(&tl.orig)
	clear(&tl.free_pts)
}

// Drops any half-finished gesture or editing session (tool switch, document switch).
tools_cancel :: proc() {
	if tl.kind == .Erase && doc != nil do eraser_end(doc)
	if tl.kind == .Sculpt && doc != nil do sculpt_end(doc)
	tl_reset()
	pen_finish(false)
	text_finish()
	tl.edit_uid = 0
	tl.ctrl_on = false
	clear(&tl.anchors)
}

set_tool :: proc(t: Tool) {
	if tool_is_toggle(t) {
		tool_toggle(t)
		return
	}
	options_switch_on = false // the options bar goes back to the tool's settings
	for &g in tool_groups do g.turn_op = .None // a group's hotkey carries on from this tool
	if t != cur_tool {
		// the two point editing tools work on the same path
		keep := is_point_tool(t) && is_point_tool(cur_tool) ? tl.edit_uid : 0
		tools_cancel()
		tl.edit_uid = keep
	}
	cur_tool = t
}

is_point_tool :: proc(t: Tool) -> bool {
	return t == .Node || t == .Control
}

// The tool in effect right now: the pen's eraser end can stand in for the current one. A gesture keeps the tool it
// began with, whichever end of the pen is reported as it ends.
eff_tool :: proc() -> Tool {
	if tl.kind != .None do return tl.stand_in ? tl.stand_tool : cur_tool
	if pen_eraser_active() && !text_editing() {
		if t, ok := pen_eraser_group_tool(); ok do return t
		// with no group assigned it erases with any tool that works on shapes
		#partial switch cur_tool {
		case .Select, .Node, .Control, .Pen, .Freehand, .Sculpt, .Extend, .Rect, .Ellipse, .Line:
			return .Eraser
		}
	}
	return cur_tool
}

push_once :: proc(d: ^Doc) {
	if !tl.pushed {
		history_push(d)
		tl.pushed = true
	}
}

// Picking -------------------------------------------------------------------------------------------------

// Returns the topmost node under `p` (document space). Groups return the group unless `deep`.
pick_node :: proc(d: ^Doc, p: Vec2, deep: bool) -> ^Node {
	tol := 3 / d.zoom
	#reverse for c in d.root.children {
		if hit := pick_in(c, p, tol, deep, true); hit != nil do return hit
	}
	return nil
}

@(private = "file")
pick_in :: proc(n: ^Node, p: Vec2, tol: f32, deep, top: bool) -> ^Node {
	if !n.visible || n.locked do return nil
	inv, ok := mat_inv(n.xf)
	if !ok do return nil
	q := mat_apply(inv, p)
	ltol := tol / max(mat_scale_factor(n.xf), 1e-6)
	if n.kind == .Group {
		#reverse for c in n.children {
			if hit := pick_in(c, q, ltol, deep, false); hit != nil {
				return deep ? hit : n
			}
		}
		return nil
	}
	hit := false
	if n.kind == .Text {
		b := text_bounds(n)
		hit = bounds_contains(bounds_inflate(b, ltol), q)
	} else {
		segs := node_segs(n)
		poly: Polys
		defer polys_free(&poly)
		path_flatten(segs, MAT_ID, ltol * 0.25, &poly)
		if n.fill.kind != .None && polys_contains(&poly, q, n.even_odd) do hit = true
		if !hit && n.stroke.kind != .None && polys_distance(&poly, q) <= n.sw / 2 + ltol do hit = true
		// an unfilled closed outline is also grabbed by its interior only when it has no stroke visible
		if !hit && n.fill.kind == .None && n.stroke.kind == .None && polys_contains(&poly, q, n.even_odd) do hit = true
	}
	return hit ? n : nil
}

// Selection geometry ---------------------------------------------------------------------------------------

node_parent_world :: proc(d: ^Doc, n: ^Node) -> Mat {
	par := node_parent(d.root, n)
	if par == nil || par == d.root do return MAT_ID
	return node_world(d.root, par)
}

// Bounds of a node in document space.
node_doc_bounds :: proc(d: ^Doc, n: ^Node) -> Bounds {
	b := node_local_bounds(n)
	if bounds_empty(b) do return b
	return bounds_transform(b, node_world(d.root, n))
}

sel_bounds :: proc(d: ^Doc) -> Bounds {
	b := BOUNDS_EMPTY
	for n in sel_nodes(d) do b = bounds_union(b, node_doc_bounds(d, n))
	return b
}

// Applies a document-space transform `m` to `n`, starting from its original local transform `xf0`.
node_apply_world :: proc(d: ^Doc, n: ^Node, xf0: Mat, m: Mat) {
	pw := node_parent_world(d, n)
	ipw, ok := mat_inv(pw)
	if !ok do return
	n.xf = mat_mul(ipw, mat_mul(m, mat_mul(pw, xf0)))
}

sel_remember :: proc(d: ^Doc) {
	clear(&tl.orig)
	for n in sel_nodes(d) do append(&tl.orig, Orig{n.uid, n.xf})
	tl.bbox = sel_bounds(d)
}

sel_apply :: proc(d: ^Doc, m: Mat) {
	for o in tl.orig {
		if n := node_find(d.root, o.uid); n != nil do node_apply_world(d, n, o.xf, m)
	}
	doc_changed(d)
}

// Handles of the selection box: 0 TL, 1 T, 2 TR, 3 R, 4 BR, 5 B, 6 BL, 7 L.
handle_point :: proc(b: Bounds, i: int) -> Vec2 {
	cx, cy := (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2
	switch i {
	case 0: return {b.x0, b.y0}
	case 1: return {cx, b.y0}
	case 2: return {b.x1, b.y0}
	case 3: return {b.x1, cy}
	case 4: return {b.x1, b.y1}
	case 5: return {cx, b.y1}
	case 6: return {b.x0, b.y1}
	}
	return {b.x0, cy}
}

HANDLE_R :: 4
ROTATE_ZONE :: 16

// What the pointer is over for the selection box: 0..7 handle, 8 rotate zone, -1 nothing.
sel_handle_at :: proc(d: ^Doc, b: Bounds, sp: Vec2) -> int {
	if bounds_empty(b) do return -1
	for i in 0 ..< 8 {
		hp := to_screen(d, handle_point(b, i))
		if abs(hp.x - sp.x) <= HANDLE_R + 2 && abs(hp.y - sp.y) <= HANDLE_R + 2 do return i
	}
	for i in ([?]int{0, 2, 4, 6}) {
		hp := to_screen(d, handle_point(b, i))
		if abs(hp.x - sp.x) <= ROTATE_ZONE && abs(hp.y - sp.y) <= ROTATE_ZONE do return 8
	}
	return -1
}

// Viewport update -----------------------------------------------------------------------------------------

viewport_update :: proc(vp: Rect) {
	ui.layer = 0
	d := doc
	if d == nil do return
	if !d.view_init {
		d.view_init = true
		view_fit(d, vp)
	}
	over := ui_hover(vp) && !files_dragging()
	sp := pointer()
	// wheel zooms around the pointer
	if over && ui.wheel != 0 && !ui.ctrl {
		zoom_at(d, sp, math.pow(1.15, ui.wheel))
	} else if over && ui.wheel != 0 {
		d.oy += ui.wheel * 40
	}
	if over && ui.wheel_h != 0 do d.ox += ui.wheel_h * 40
	// middle drag, or space / Hand tool + left drag, pans
	hand := eff_tool() == .Hand
	panning := ui.down[2] || (ui.down[0] && tl.kind == .None && (hand || IsKeyDown(.SPACE)) && over)
	if panning && over || (panning && ui.active_id == 0 && tl.kind == .None) {
		d.ox += f32(ui.mx - ui.pmx)
		d.oy += f32(ui.my - ui.pmy)
		ui.cursor = .RESIZE_ALL
		return
	}
	if hand && over {
		ui.cursor = .RESIZE_ALL
	}
	tools_input(d, vp, over, sp)
}

// The interface scale is changing: every drawing stays the same size and in the same place on the screen.
views_keep_on_screen :: proc(old_scale, new_scale: f32) {
	for d in docs {
		if d.view_init do zoom_at(d, {}, old_scale / new_scale)
	}
}

zoom_at :: proc(d: ^Doc, sp: Vec2, f: f32) {
	nz := clamp(d.zoom * f, 0.02, 128)
	d.ox = sp.x - (sp.x - d.ox) * nz / d.zoom
	d.oy = sp.y - (sp.y - d.oy) * nz / d.zoom
	d.zoom = nz
}

view_fit :: proc(d: ^Doc, vp: Rect) {
	d.zoom = clamp(min(f32(vp.w) / (d.w + 80), f32(vp.h) / (d.h + 80)), 0.02, 8)
	d.ox = f32(vp.x) + (f32(vp.w) - d.w * d.zoom) / 2
	d.oy = f32(vp.y) + (f32(vp.h) - d.h * d.zoom) / 2
}

view_actual :: proc(d: ^Doc, vp: Rect, zoom: f32 = 1) {
	d.zoom = zoom
	d.ox = f32(vp.x) + (f32(vp.w) - d.w * zoom) / 2
	d.oy = f32(vp.y) + (f32(vp.h) - d.h * zoom) / 2
}

view_vp: Rect // last viewport rectangle, for commands that need it

tools_input :: proc(d: ^Doc, vp: Rect, over: bool, sp: Vec2) {
	view_vp = vp
	p := to_doc(d, sp)
	pressed := ui.pressed[0] && over
	if pressed do stop_playback() // the animation would pull the frame out from under the gesture
	t := eff_tool()
	if pressed && tl.kind == .None {
		tl.stand_in, tl.stand_tool = t != cur_tool, t
	}
	if text_editing() {
		text_update(d, p, pressed)
		// the text tool still takes presses on the edited text, to drag it around
		if tl.text_uid != 0 && cur_tool != .Text do return
	}
	switch t {
	case .Select:
		tool_select(d, p, sp, pressed, over)
	case .Node:
		tool_node(d, p, sp, pressed, over)
	case .Control:
		tool_control(d, p, sp, pressed, over)
	case .Pen:
		tool_pen(d, p, sp, pressed, over)
	case .Freehand:
		tool_freehand(d, p, sp, pressed, over)
	case .Eraser:
		tool_eraser(d, p, pressed, over)
	case .Sculpt:
		tool_sculpt(d, p, pressed, over)
	case .Extend:
		tool_extend(d, p, sp, pressed, over)
	case .Rect, .Ellipse, .Line:
		tool_shape(d, t, p, sp, pressed, over)
	case .Text:
		tool_text(d, p, sp, pressed, over)
	case .Picker:
		if pressed do tool_picker(d, p)
		if over do ui.cursor = .CROSSHAIR
	case .Zoom:
		if over do ui.cursor = .POINTING_HAND
		if pressed do zoom_at(d, sp, ui.alt || ui.shift ? 1 / 1.6 : 1.6)
	case .Hand, .Grid, .Snap, .Onion:
	}
}

// Select tool ---------------------------------------------------------------------------------------------

tool_select :: proc(d: ^Doc, p, sp: Vec2, pressed, over: bool) {
	if pressed {
		sel_b := sel_bounds(d)
		h := sel_handle_at(d, sel_b, sp)
		tl.start, tl.cur, tl.start_scr, tl.moved, tl.pushed = p, p, sp, false, false
		if h >= 0 && len(d.sel) > 0 {
			sel_remember(d)
			tl.kind = h == 8 ? .Rotate : .Scale
			tl.handle = h
			return
		}
		if gn, gp := grad_target(d); gn != nil {
			if hi := grad_handle_at(d, gn, gp, sp); hi >= 0 {
				tl.kind = .Gradient
				tl.handle = hi
				return
			}
		}
		hit := pick_node(d, p, ui.ctrl)
		if hit != nil {
			if ui.shift {
				sel_toggle(d, hit)
			} else if !sel_has(d, hit.uid) {
				sel_set(d, hit)
			}
			if sel_has(d, hit.uid) {
				sel_remember(d)
				tl.kind = .Move
			}
		} else {
			if !ui.shift do clear(&d.sel)
			tl.kind = .Marquee
		}
		return
	}
	if tl.kind == .None {
		if over {
			h := sel_handle_at(d, sel_bounds(d), sp)
			if h >= 0 && h < 8 {
				cursors := [8]MouseCursor{.RESIZE_NWSE, .RESIZE_NS, .RESIZE_NESW, .RESIZE_EW, .RESIZE_NWSE, .RESIZE_NS, .RESIZE_NESW, .RESIZE_EW}
				ui.cursor = cursors[h]
			} else if h == 8 {
				ui.cursor = .CROSSHAIR
			}
		}
		return
	}
	tl.cur = p
	if !ui.down[0] {
		if tl.kind == .Marquee {
			marquee_select(d, tl.start, p)
		}
		tl_reset()
		return
	}
	if !tl.moved && v_len(sp - tl.start_scr) < 3 do return
	tl.moved = true
	switch tl.kind {
	case .Move:
		push_once(d)
		delta := p - tl.start
		if snap_grid {
			// snap the selection's top-left corner
			target := snap_pt(Vec2{tl.bbox.x0, tl.bbox.y0} + delta)
			delta = target - Vec2{tl.bbox.x0, tl.bbox.y0}
		}
		if ui.shift {
			if abs(delta.x) > abs(delta.y) do delta.y = 0
			else do delta.x = 0
		}
		sel_apply(d, mat_translate(delta.x, delta.y))
	case .Scale:
		push_once(d)
		b := tl.bbox
		hp := handle_point(b, tl.handle)
		anchor := handle_point(b, (tl.handle + 4) % 8)
		q := snap_pt(p)
		sx, sy: f32 = 1, 1
		hx := tl.handle != 1 && tl.handle != 5
		hy := tl.handle != 3 && tl.handle != 7
		if hx && abs(hp.x - anchor.x) > 1e-6 do sx = (q.x - anchor.x) / (hp.x - anchor.x)
		if hy && abs(hp.y - anchor.y) > 1e-6 do sy = (q.y - anchor.y) / (hp.y - anchor.y)
		if ui.shift && hx && hy {
			s := abs(sx) > abs(sy) ? sx : sy
			sx, sy = s, s
		} else if ui.shift {
			if !hx do sx = sy
			if !hy do sy = sx
		}
		if abs(sx) < 1e-4 do sx = 1e-4
		if abs(sy) < 1e-4 do sy = 1e-4
		m := mat_mul(mat_translate(anchor.x, anchor.y), mat_mul(mat_scale(sx, sy), mat_translate(-anchor.x, -anchor.y)))
		sel_apply(d, m)
	case .Rotate:
		push_once(d)
		c := bounds_center(tl.bbox)
		a0 := math.atan2(tl.start.y - c.y, tl.start.x - c.x)
		a1 := math.atan2(p.y - c.y, p.x - c.x)
		da := a1 - a0
		if ui.shift do da = math.round(da / deg2rad(15)) * deg2rad(15)
		m := mat_mul(mat_translate(c.x, c.y), mat_mul(mat_rotate(da), mat_translate(-c.x, -c.y)))
		sel_apply(d, m)
	case .Gradient:
		push_once(d)
		if gn, gp := grad_target(d); gn != nil {
			iw, ok := mat_inv(node_world(d.root, gn))
			if ok {
				q := mat_apply(iw, snap_pt(p))
				if tl.handle == 0 {
					gp.p0 = q
				} else if gp.kind == .Linear {
					gp.p1 = q
				} else {
					gp.p1.x = max(v_len(q - gp.p0), 0.01)
				}
				doc_changed(d)
				cur_fill, cur_stroke = prop_target == 0 ? gp^ : cur_fill, prop_target == 1 ? gp^ : cur_stroke
			}
		}
	case .None, .Marquee, .Create, .Anchor, .Handle, .Freehand, .Pen, .Erase, .Sculpt, .Extend:
	}
}

// The selected object and its fill / stroke when that paint is a gradient (the one the panel edits).
grad_target :: proc(d: ^Doc) -> (^Node, ^Paint) {
	n := first_selected(d)
	if n == nil || n.kind == .Group do return nil, nil
	p := prop_target == 0 ? &n.fill : &n.stroke
	if p.kind == .Linear || p.kind == .Radial do return n, p
	return nil, nil
}

grad_points :: proc(d: ^Doc, n: ^Node, p: ^Paint) -> (a, b: Vec2) {
	w := node_world(d.root, n)
	a = to_screen(d, mat_apply(w, p.p0))
	if p.kind == .Linear {
		b = to_screen(d, mat_apply(w, p.p1))
	} else {
		b = to_screen(d, mat_apply(w, p.p0 + Vec2{p.p1.x, 0}))
	}
	return
}

grad_handle_at :: proc(d: ^Doc, n: ^Node, p: ^Paint, sp: Vec2) -> int {
	a, b := grad_points(d, n, p)
	if v_len(b - sp) <= 7 do return 1
	if v_len(a - sp) <= 7 do return 0
	return -1
}

marquee_select :: proc(d: ^Doc, a, b: Vec2) {
	box := Bounds{min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y)}
	if box.x1 - box.x0 < 2 / d.zoom && box.y1 - box.y0 < 2 / d.zoom do return
	for c in d.root.children {
		if !c.visible || c.locked do continue
		nb := node_doc_bounds(d, c)
		if bounds_empty(nb) do continue
		if nb.x0 >= box.x0 && nb.x1 <= box.x1 && nb.y0 >= box.y0 && nb.y1 <= box.y1 {
			if !sel_has(d, c.uid) do append(&d.sel, c.uid)
		}
	}
}

// Shape tools ---------------------------------------------------------------------------------------------

tool_shape :: proc(d: ^Doc, tool: Tool, p, sp: Vec2, pressed, over: bool) {
	if over do ui.cursor = .CROSSHAIR
	if pressed {
		tl.kind = .Create
		q := snap_pt(p)
		tl.start, tl.cur, tl.start_scr, tl.moved, tl.pushed, tl.create_uid = q, q, sp, false, false, 0
		return
	}
	if tl.kind != .Create do return
	q := snap_pt(p)
	tl.cur = q
	if !ui.down[0] {
		if tl.moved && tl.create_uid != 0 {
			n := node_find(d.root, tl.create_uid)
			if n != nil do sel_set(d, n)
		}
		tl_reset()
		return
	}
	if !tl.moved && v_len(sp - tl.start_scr) < 3 do return
	tl.moved = true
	push_once(d)
	var_n: ^Node
	if tl.create_uid == 0 {
		kind := tool == .Rect ? Node_Kind.Rect : (tool == .Ellipse ? Node_Kind.Ellipse : Node_Kind.Path)
		var_n = new_shape(d, kind)
		if tool == .Line {
			name_set(&var_n.name, "Line")
			var_n.fill = paint_none()
			if var_n.stroke.kind == .None do var_n.stroke = paint_solid({40, 30, 24, 255})
		}
		append(&d.root.children, var_n)
		tl.create_uid = var_n.uid
	} else {
		var_n = node_find(d.root, tl.create_uid)
	}
	if var_n == nil do return
	a, b := tl.start, q
	if tool == .Line {
		if ui.shift {
			dv := b - a
			ang := math.round(math.atan2(dv.y, dv.x) / deg2rad(15)) * deg2rad(15)
			b = a + Vec2{math.cos(ang), math.sin(ang)} * v_len(dv)
		}
		clear(&var_n.segs)
		path_move(&var_n.segs, a)
		path_line(&var_n.segs, b)
		node_fit_gradients(var_n)
		doc_changed(d)
		return
	}
	dx, dy := b.x - a.x, b.y - a.y
	if ui.shift {
		s := max(abs(dx), abs(dy))
		dx = dx < 0 ? -s : s
		dy = dy < 0 ? -s : s
	}
	x0, y0, x1, y1 := a.x, a.y, a.x + dx, a.y + dy
	if ui.alt {
		x0, y0 = a.x - dx, a.y - dy
	}
	lx, ly, hx, hy := min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)
	if tool == .Rect {
		var_n.x, var_n.y, var_n.w, var_n.h = lx, ly, hx - lx, hy - ly
	} else {
		var_n.x, var_n.y = (lx + hx) / 2, (ly + hy) / 2
		var_n.w, var_n.h = (hx - lx) / 2, (hy - ly) / 2
	}
	node_fit_gradients(var_n)
	doc_changed(d)
}

// Eyedropper ----------------------------------------------------------------------------------------------

tool_picker :: proc(d: ^Doc, p: Vec2) {
	n := pick_node(d, p, true)
	if n == nil do return
	if ui.alt {
		if n.stroke.kind != .None do style_set_stroke(d, n.stroke, false)
		if n.stroke.kind == .Solid do recent_push(n.stroke.color)
	} else if n.fill.kind != .None {
		style_set_fill(d, n.fill, false)
		if n.fill.kind == .Solid do recent_push(n.fill.color)
	}
}

// Overlay ---------------------------------------------------------------------------------------------------

C_SEL :: Color{60, 160, 255, 255}

draw_handle_sq :: proc(c: Vec2, filled: bool, col: Color) {
	r := Rect{i32(c.x) - HANDLE_R, i32(c.y) - HANDLE_R, HANDLE_R * 2 + 1, HANDLE_R * 2 + 1}
	fill_rect(r, filled ? col : Color{20, 22, 28, 255})
	outline_rect(r, col)
}

draw_handle_dot :: proc(c: Vec2, col: Color) {
	draw_rrect(c.x - 4, c.y - 4, 9, 9, 4.5, Color{20, 22, 28, 255}) // keeps it visible on any background
	draw_rrect(c.x - 3, c.y - 3, 7, 7, 3.5, col)
}

overlay_draw :: proc(vp: Rect) {
	d := doc
	if d == nil do return
	clip_begin(vp)
	defer clip_end()
	// grid
	if show_grid && grid_size * d.zoom >= 4 {
		step := grid_size * d.zoom
		x0 := d.ox + math.ceil((f32(vp.x) - d.ox) / step) * step
		for x := max(x0, d.ox); x <= d.ox + d.w * d.zoom + 0.5 && x < f32(vp.x + vp.w); x += step {
			draw_rect(math.round(x), max(d.oy, f32(vp.y)), 1, min(d.h * d.zoom, f32(vp.y + vp.h) - max(d.oy, f32(vp.y))), Color{120, 130, 150, 60})
		}
		y0 := d.oy + math.ceil((f32(vp.y) - d.oy) / step) * step
		for y := max(y0, d.oy); y <= d.oy + d.h * d.zoom + 0.5 && y < f32(vp.y + vp.h); y += step {
			draw_rect(max(d.ox, f32(vp.x)), math.round(y), min(d.w * d.zoom, f32(vp.x + vp.w) - max(d.ox, f32(vp.x))), 1, Color{120, 130, 150, 60})
		}
	}
	tool := eff_tool()
	// selection
	if !is_point_tool(tool) && tool != .Pen {
		nodes := sel_nodes(d)
		for n in nodes {
			b := node_doc_bounds(d, n)
			if bounds_empty(b) do continue
			a, c := to_screen(d, {b.x0, b.y0}), to_screen(d, {b.x1, b.y1})
			outline_rect(Rect{i32(a.x), i32(a.y), i32(c.x - a.x), i32(c.y - a.y)}, Color{60, 160, 255, 120})
		}
		if len(nodes) > 0 && (tool == .Select) {
			b := sel_bounds(d)
			if !bounds_empty(b) {
				a, c := to_screen(d, {b.x0, b.y0}), to_screen(d, {b.x1, b.y1})
				outline_rect(Rect{i32(a.x), i32(a.y), i32(c.x - a.x), i32(c.y - a.y)}, C_SEL)
				for i in 0 ..< 8 do draw_handle_sq(to_screen(d, handle_point(b, i)), true, C_SEL)
			}
		}
	}
	if tl.kind == .Marquee && tl.moved {
		a, c := to_screen(d, tl.start), to_screen(d, tl.cur)
		r := Rect{i32(min(a.x, c.x)), i32(min(a.y, c.y)), i32(abs(c.x - a.x)), i32(abs(c.y - a.y))}
		fill_rect(r, Color{60, 160, 255, 30})
		outline_rect(r, C_SEL)
	}
	if tool == .Select {
		if gn, gp := grad_target(d); gn != nil {
			a, b := grad_points(d, gn, gp)
			draw_line(a, b, Color{255, 255, 255, 200})
			draw_line(a + Vec2{0, 1}, b + Vec2{0, 1}, Color{0, 0, 0, 160})
			draw_handle_dot(a, Color{255, 220, 120, 255})
			draw_handle_dot(b, Color{255, 255, 255, 255})
		}
	}
	if is_point_tool(tool) do node_overlay(d)
	if tool == .Pen do pen_overlay(d)
	if tool == .Eraser && in_rect(vp, ui.mx, ui.my) && !files_dragging() do eraser_cursor(d)
	if tool == .Sculpt && in_rect(vp, ui.mx, ui.my) && !files_dragging() do sculpt_cursor(d)
	if tool == .Extend do extend_overlay(d, vp)
	if tl.kind == .Freehand || tl.kind == .Extend {
		for i in 1 ..< len(tl.free_pts) {
			draw_line(to_screen(d, tl.free_pts[i - 1]), to_screen(d, tl.free_pts[i]), Color{246, 170, 104, 200})
		}
	}
	if text_editing() do text_overlay(d)
}

