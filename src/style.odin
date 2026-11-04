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

// Change Fill / Change Stroke -------------------------------------------------------------------------------

PAINT_KIND_NAMES := [Paint_Kind]string {
	.None   = "None",
	.Solid  = "Solid",
	.Linear = "Linear gradient",
	.Radial = "Radial gradient",
}

// The color a paint shows, or remembers while it is None. Transparent if it has none, as after reading fill="none".
paint_shown_color :: proc(p: Paint) -> Color {
	if (p.kind == .Linear || p.kind == .Radial) && p.nstops > 0 do return p.stops[0].color
	if p.color.a > 0 do return p.color
	return p.nstops > 0 ? p.stops[0].color : Color{}
}

// The same paint as another type. It keeps its color and gradient stops whatever the type, so a round through all
// the types comes back to where it started, apart from where a gradient's handles were. A color edited in the
// meantime starts a new gradient from that color.
paint_to_kind :: proc(p: Paint, kind: Paint_Kind, b: Bounds, fallback: Color) -> Paint {
	if p.kind == kind do return p
	c := paint_shown_color(p)
	if c.a == 0 do c = fallback
	np := p
	np.kind, np.color = kind, c
	if kind == .Linear || kind == .Radial {
		base := p
		is_gradient := p.kind == .Linear || p.kind == .Radial
		if !is_gradient && p.nstops >= 2 && p.stops[0].color == c {
			base.kind = .Linear // its stops are still good
		} else if !is_gradient {
			base.kind, base.color = .Solid, c
		}
		np = paint_make_gradient(base, b, kind == .Radial)
		np.color = c
	}
	return np
}

// The objects a style change reaches: inside a selected group, what it holds, since a group draws nothing itself.
@(private = "file")
paint_targets :: proc(n: ^Node, out: ^[dynamic]^Node) {
	if n.kind != .Group {
		append(out, n)
		return
	}
	for c in n.children {
		if !c.locked do paint_targets(c, out)
	}
}

// Steps the fill or stroke to its next type. The first object decides which type that is; each object changes with
// its own colors and its own bounds. With nothing selected it steps what new shapes get.
cmd_change_paint :: proc(d: ^Doc, stroke: bool) {
	DEFAULT_FILL :: Color{246, 170, 104, 255}
	DEFAULT_STROKE :: Color{40, 30, 24, 255}
	cur := stroke ? &cur_stroke : &cur_fill
	fallback := paint_shown_color(cur^)
	if fallback.a == 0 do fallback = stroke ? DEFAULT_STROKE : DEFAULT_FILL
	targets := make([dynamic]^Node, context.temp_allocator)
	for n in sel_nodes(d) do paint_targets(n, &targets)

	first := len(targets) > 0 ? (stroke ? targets[0].stroke : targets[0].fill) : cur^
	kind := Paint_Kind((int(first.kind) + 1) % len(Paint_Kind))
	if len(targets) > 0 {
		style_push(d)
		for n in targets {
			p := stroke ? &n.stroke : &n.fill
			p^ = paint_to_kind(p^, kind, node_local_bounds(n), fallback)
			if stroke && kind != .None && n.sw <= 0 do n.sw = cur_sw > 0 ? cur_sw : 1
		}
		cur^ = stroke ? targets[0].stroke : targets[0].fill
		doc_changed(d)
	} else {
		cur^ = paint_to_kind(cur^, kind, BOUNDS_EMPTY, fallback)
	}
	// Properties shows what changed, and the Select tool its gradient's handles
	prop_target = stroke ? 1 : 0
	grad_stop = 0
	set_statusf("%s: %s", stroke ? "Stroke" : "Fill", PAINT_KIND_NAMES[kind])
}

// A new object's gradient spans the object, wherever the gradient it was given came from.
node_fit_gradients :: proc(n: ^Node) {
	b := node_local_bounds(n)
	if bounds_empty(b) || bounds_w(b) <= 0 do return
	for p in ([?]^Paint{&n.fill, &n.stroke}) {
		if p.kind == .Linear || p.kind == .Radial do p^ = paint_make_gradient(p^, b, p.kind == .Radial)
	}
}

// Gradient helpers ----------------------------------------------------------------------------------------

// Makes a two-stop gradient across the object's bounds from a solid color.
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
