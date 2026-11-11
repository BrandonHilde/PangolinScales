package pangolin

import "core:math"

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

// Line patterns, sized from the stroke width: 0 solid, 1 dashed, 2 dotted, 3 dash-dot.
LINE_PATTERNS := [?]string{"Solid line", "Dashed", "Dotted", "Dash-dot"}

// Which of LINE_PATTERNS a dash list looks like.
line_pattern_of :: proc(dash: [4]f32, ndash: int) -> int {
	if ndash == 2 && dash[1] > dash[0] * 3 do return 2
	if ndash == 2 do return 1
	if ndash == 4 do return 3
	return 0
}

@(private = "file")
set_line_pattern :: proc(pattern: int, sw: f32, dash: ^[4]f32, ndash: ^int, cap: ^Cap) {
	w := max(sw, 1)
	switch pattern {
	case 0: ndash^ = 0
	case 1: ndash^, dash^ = 2, {w * 4, w * 2, 0, 0}
	case 2: ndash^, dash^ = 2, {0.01, w * 2, 0, 0}
	case 3: ndash^, dash^ = 4, {w * 4, w * 2, 0.01, w * 2}
	}
	// a dot is a very short dash, which only a round cap shows
	if pattern == 2 do cap^ = .Round
}

style_set_line_pattern :: proc(d: ^Doc, pattern: int) {
	set_line_pattern(pattern, cur_sw, &cur_dash, &cur_ndash, &cur_cap)
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) do set_line_pattern(pattern, n.sw, &n.dash, &n.ndash, &n.cap)
	doc_changed(d)
}

// Sets the whole stroke style (not its color), like the stroke controls do one setting.
style_set_stroke_style :: proc(d: ^Doc, st: Stroke_Style) {
	cur_sw, cur_cap, cur_join, cur_miter = st.width, st.cap, st.join, st.miter
	cur_dash, cur_ndash, cur_dash_off = st.dash, st.ndash, st.offset
	if len(d.sel) == 0 do return
	style_push(d)
	for n in sel_nodes(d) {
		n.sw, n.cap, n.join, n.miter = st.width, st.cap, st.join, st.miter
		n.dash, n.ndash, n.dash_off = st.dash, st.ndash, st.offset
	}
	doc_changed(d)
}

// The stroke style the properties panel shows: the first selected object's, or the one new shapes get.
stroke_style_current :: proc(d: ^Doc) -> Stroke_Style {
	if sel := first_selected(d); sel != nil do return stroke_style_of(sel)
	return {width = cur_sw, cap = cur_cap, join = cur_join, miter = cur_miter, dash = cur_dash, ndash = cur_ndash, offset = cur_dash_off}
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

// Stroke presets --------------------------------------------------------------------------------------------

stroke_preset: Name // the stroke preset picked last (presets.odin)

// A stroke style as the shared presets take it: lengths in hundredths, the cap and join as numbers.
stroke_to_ints :: proc(st: Stroke_Style) -> [10]int {
	h :: proc(v: f32) -> int {return int(math.round(v * 100))}
	s := st
	// a solid line keeps the dashes it had before, unused; they mustn't make it differ from a preset
	if s.ndash == 0 do s.dash, s.offset = {}, 0
	return {h(s.width), int(s.cap), int(s.join), h(s.miter), h(s.dash[0]), h(s.dash[1]), h(s.dash[2]), h(s.dash[3]), s.ndash, h(s.offset)}
}

// The style from a preset's values. One saved with fewer values keeps the rest from `base`.
stroke_from_ints :: proc(base: Stroke_Style, v: []int) -> Stroke_Style {
	f :: proc(v: []int, i: int, old: f32) -> f32 {return i < len(v) ? f32(v[i]) / 100 : old}
	st := base
	st.width = max(f(v, 0, st.width), 0)
	if len(v) > 1 do st.cap = Cap(clamp(v[1], 0, len(Cap) - 1))
	if len(v) > 2 do st.join = Join(clamp(v[2], 0, len(Join) - 1))
	st.miter = max(f(v, 3, st.miter), 1)
	for i in 0 ..< 4 do st.dash[i] = max(f(v, 4 + i, st.dash[i]), 0)
	if len(v) > 8 do st.ndash = clamp(v[8], 0, 4)
	st.offset = f(v, 9, st.offset)
	return st
}

// width, cap (0 butt, 1 round, 2 square), join (0 miter, 1 round, 2 bevel), miter limit, dash ×4, dash count, dash offset
stroke_builtins := [?]Preset_Builtin {
	{name = "Hairline 1", vals = {100, 0, 0, 400, 0, 0, 0, 0, 0, 0}},
	{name = "Medium 2 round", vals = {200, 1, 1, 400, 0, 0, 0, 0, 0, 0}},
	{name = "Bold 4 round", vals = {400, 1, 1, 400, 0, 0, 0, 0, 0, 0}},
	{name = "Square caps 2", vals = {200, 2, 0, 400, 0, 0, 0, 0, 0, 0}},
	{name = "Dashed 2", vals = {200, 0, 0, 400, 800, 400, 0, 0, 2, 0}},
	{name = "Dotted 3", vals = {300, 1, 1, 400, 1, 600, 0, 0, 2, 0}},
}

STROKE_PRESET_TIP :: Tip{"Stroke preset", "A ready-made or saved stroke: its width, line ends, corners and pattern, not its color. Picking one sets them on the selected objects, and for new shapes. The ... menu saves your own."}
