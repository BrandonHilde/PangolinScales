package pangolin

// ---------------------------------------------------------------------------
// Style editing: changes go to the selected objects and also become the style new objects start with.
// ---------------------------------------------------------------------------

last_style_push: f64

// One undo step per burst of edits (dragging a slider fires many changes).
style_push :: proc(d: ^Doc) {
	if len(d.sel) == 0 do return
	if ui.time - last_style_push > 0.6 do history_push(d)
	last_style_push = ui.time
}

style_each :: proc(d: ^Doc, f: proc(n: ^Node, paint: Paint), paint: Paint) {
	for n in sel_nodes(d) do f(n, paint)
}

@(private = "file")
set_fill_fn :: proc(n: ^Node, p: Paint) {
	n.fill = p
}

@(private = "file")
set_stroke_fn :: proc(n: ^Node, p: Paint) {
	n.stroke = p
}

style_set_fill :: proc(d: ^Doc, p: Paint, push := true) {
	cur_fill = p
	if len(d.sel) == 0 do return
	if push do style_push(d)
	style_each(d, set_fill_fn, p)
	doc_changed(d)
}

style_set_stroke :: proc(d: ^Doc, p: Paint, push := true) {
	cur_stroke = p
	if len(d.sel) == 0 do return
	if push do style_push(d)
	style_each(d, set_stroke_fn, p)
	doc_changed(d)
}

style_set_width :: proc(d: ^Doc, w: f32) {
	cur_sw = w
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) do n.sw = w
	doc_changed(d)
}

style_set_cap :: proc(d: ^Doc, c: Cap) {
	cur_cap = c
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) do n.cap = c
	doc_changed(d)
}

style_set_join :: proc(d: ^Doc, j: Join) {
	cur_join = j
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) do n.join = j
	doc_changed(d)
}

style_set_opacity :: proc(d: ^Doc, o: f32) {
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) do n.opacity = o
	doc_changed(d)
}

// Gradient helpers ----------------------------------------------------------------------------------------

// Makes a two-stop gradient across the object's bounds from a solid colour.
paint_make_gradient :: proc(base: Paint, bounds: Bounds, radial: bool) -> Paint {
	b := bounds
	g: Paint
	c0 := base.kind == .Solid ? base.color : Color{246, 170, 104, 255}
	c1 := Color{c0.r / 3, c0.g / 3, c0.b / 3, 255}
	if base.kind == .Linear || base.kind == .Radial {
		g = base
		g.kind = radial ? .Radial : .Linear
	} else {
		g.nstops = 2
		g.stops[0] = Stop{0, c0}
		g.stops[1] = Stop{1, c1}
	}
	g.kind = radial ? .Radial : .Linear
	if bounds_empty(b) {
		b = Bounds{0, 0, 100, 100}
	}
	c := bounds_center(b)
	if radial {
		g.p0 = c
		g.p1 = {max(bounds_w(b), bounds_h(b)) / 2, 0}
	} else {
		g.p0 = {b.x0, c.y}
		g.p1 = {b.x1, c.y}
	}
	return g
}
