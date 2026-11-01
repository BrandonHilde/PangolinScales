package pangolin

import "core:fmt"
import "core:math"

import oui "odinui:odinui"

// ---------------------------------------------------------------------------
// Right-hand panels for SVG documents: object list and the properties (fill / stroke, transform, text...).
// The panel, its headings and buttons are OdinUI nodes; the list and the properties are drawn by hand
// into slots the theme sizes.
// ---------------------------------------------------------------------------

// Section heading: a dim caption with a hairline running to the right edge.
osection :: proc(key, title: string) {
	oui.element(uictx, key, "section-head")
	oui.label(uictx, "t", title)
	oui.element_leaf(uictx, "line", "section-line")
	oui.end(uictx)
}

obj_scroll: int
prop_scroll: i32

panel_right :: proc() {
	oui.element(uictx, "right", "sidepanel", {id = "right"})
	defer oui.end(uictx)
	osection("objects-head", "Objects")
	oui_slot("objects", "objects")
	oui.element(uictx, "object-buttons", "row", {id = "object-buttons"})
	ob :: proc(key: string, ic: Icon, tip: string, c: Cmd) {
		if clicked, _ := oui_icon_button(key, ic, tip, {class = "panel-btn", enabled = true}); clicked do run_cmd(c)
	}
	ob("raise", .Up, "Raise (PgUp)", .Raise)
	ob("lower", .Down, "Lower (PgDn)", .Lower)
	ob("dup", .Copy, "Duplicate (Ctrl+D)", .Duplicate)
	ob("group", .Layer, "Group (Ctrl+G)", .Group)
	ob("del", .Trash, "Delete (Del)", .Delete)
	oui.element_leaf(uictx, "spacer", "spacer")
	otext("count", fmt.tprintf("%d objects", len(doc.root.children)), "dim")
	oui.end(uictx)
	osection("props-head", "Properties")
	oui_slot("properties", "properties")
}

// Object list ------------------------------------------------------------------------------------------------

Obj_Row :: struct {
	n:     ^Node,
	depth: int,
}

flatten_tree :: proc(n: ^Node, depth: int, out: ^[dynamic]Obj_Row) {
	#reverse for c in n.children {
		append(out, Obj_Row{c, depth})
		if c.kind == .Group do flatten_tree(c, depth + 1, out)
	}
}

panel_objects :: proc(area: Rect) {
	ui.layer = 0
	d := doc
	rows := make([dynamic]Obj_Row, context.temp_allocator)
	flatten_tree(d.root, 0, &rows)
	ctl_well(area)
	r := rect_inset(area, 1)

	ROW :: 16
	visible := int(r.h) / ROW
	if ui_hover(r) && ui.wheel != 0 do obj_scroll -= int(ui.wheel)
	// dragging a row: past the edges the list scrolls, the release drops it between rows
	gap := -1
	if obj_drag.uid != 0 {
		dn := node_find(d.root, obj_drag.uid)
		if dn == nil || len(rows) == 0 {
			obj_drag = {}
		} else if !obj_drag.active && abs(ui.my - obj_drag.y0) > 4 && ui.down[0] {
			obj_drag.active = true
		}
		if obj_drag.active {
			ui.cursor = .RESIZE_NS
			if ui.time - obj_drag.scroll_t > 0.06 {
				if ui.my < r.y + 4 do obj_scroll -= 1
				if ui.my > r.y + r.h - 4 do obj_scroll += 1
				obj_drag.scroll_t = ui.time
			}
			obj_scroll = clamp(obj_scroll, 0, max(len(rows) - visible, 0))
			gap = clamp(int(math.round(f32(ui.my - r.y) / ROW)) + obj_scroll, 0, len(rows))
		}
		if !ui.down[0] {
			// a drop beside the list cancels
			if obj_drag.active && ui.mx >= r.x && ui.mx < r.x + r.w {
				if gap < len(rows) do node_reorder(d, dn, rows[gap].n, true)
				else do node_reorder(d, dn, rows[len(rows) - 1].n, false)
			}
			obj_drag = {}
			gap = -1
		}
	}
	obj_scroll = clamp(obj_scroll, 0, max(len(rows) - visible, 0))
	clip_begin(r)
	defer clip_end()
	y := r.y
	for i in obj_scroll ..< min(obj_scroll + visible + 1, len(rows)) {
		row := rows[i]
		n := row.n
		rr := Rect{r.x, y, r.w, ROW}
		selected := sel_has(d, n.uid)
		hover := ui_hover(rr)
		if selected do fill_rect(rr, with_alpha(C_ACTIVE, 120))
		else if hover do fill_rect(rr, C_HOVER)
		x := r.x + 4
		if icon_button(Rect{x, y + 1, 14, 14}, .Eye, "Show / hide", n.visible) {
			history_push(d)
			n.visible = !n.visible
			doc_changed(d)
		}
		if icon_button(Rect{x + 15, y + 1, 14, 14}, .Lock, "Lock / unlock", n.locked) {
			history_push(d)
			n.locked = !n.locked
			doc_changed(d)
		}
		tx := x + 36 + i32(row.depth) * 10
		kind_ic := Icon.Pencil
		switch n.kind {
		case .Group:   kind_ic = .Layer
		case .Path:    kind_ic = .Curve
		case .Rect:    kind_ic = .Rect
		case .Ellipse: kind_ic = .Ellipse
		case .Text:    kind_ic = .Text
		}
		icon(kind_ic, tx, y + 2, selected ? WHITE : C_TEXT_DIM)
		label_s := name_str(&n.name)
		if n.kind == .Text && len(n.text) > 0 do label_s = text_str(n)
		text_clipped(Rect{tx + 16, y + (ROW - FONT_CAP) / 2, r.x + r.w - tx - 20, FONT_CAP + 2}, label_s, selected ? WHITE : C_TEXT)
		if obj_drag.active && n.uid == obj_drag.uid do fill_rect(rr, with_alpha(C_PANEL_DK, 150))
		if hover && ui.pressed[0] && ui.mx > r.x + 34 {
			if ui.shift {
				sel_toggle(d, n)
			} else {
				sel_set(d, n)
				obj_drag = {uid = n.uid, y0 = ui.my}
			}
		}
		y += ROW
	}
	if gap >= 0 {
		// where the row would land, indented to the group it would join
		depth := gap < len(rows) ? rows[gap].depth : rows[len(rows) - 1].depth
		lx := r.x + 34 + i32(depth) * 10
		ly := r.y + i32(gap - obj_scroll) * ROW
		fill_rect(Rect{lx, ly - 1, r.x + r.w - lx - 4, 2}, C_ACCENT)
	}
}

// A row being dragged in the object list (pressed, then active once it has moved a few pixels).
Obj_Drag :: struct {
	uid:      u32,
	y0:       i32,
	active:   bool,
	scroll_t: f64,
}

obj_drag: Obj_Drag

// Moves `n` next to `target`, into target's parent: in front of it (above it in the list) or behind it.
// The object keeps its place on the page when it changes groups. Returns whether anything moved.
node_reorder :: proc(d: ^Doc, n, target: ^Node, in_front: bool) -> bool {
	if n == target do return false
	// a group cannot go inside itself
	for p := node_parent(d.root, target); p != nil; p = node_parent(d.root, p) {
		if p == n do return false
	}
	op := node_parent(d.root, n)
	np := node_parent(d.root, target)
	if op == nil || np == nil do return false
	oi := node_index(op, n)
	ti := node_index(np, target)
	dest := in_front ? ti + 1 : ti
	if op == np {
		if dest > oi do dest -= 1
		if dest == oi do return false
	}
	world := mat_mul(node_parent_world(d, n), n.xf)
	history_push(d)
	ordered_remove(&op.children, oi)
	inject_at(&np.children, dest, n)
	if inv, ok := mat_inv(node_parent_world(d, n)); ok do n.xf = mat_mul(inv, world)
	doc_changed(d)
	return true
}

// Colour editing ---------------------------------------------------------------------------------------------

PALETTE := [?]Color {
	{0, 0, 0, 255}, {64, 64, 64, 255}, {128, 128, 128, 255}, {192, 192, 192, 255}, {255, 255, 255, 255}, {214, 64, 52, 255},
	{246, 170, 104, 255}, {240, 196, 60, 255}, {70, 150, 90, 255}, {60, 160, 200, 255}, {70, 90, 190, 255}, {150, 80, 170, 255},
}

hex_buf: Name

color_hex_string :: proc(c: Color) -> string {
	if c.a == 255 do return fmt.tprintf("%02x%02x%02x", c.r, c.g, c.b)
	return fmt.tprintf("%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
}

// Palette, RGB(A) sliders and a hex field. Returns true when the colour changed. `y` is advanced.
color_edit :: proc(x, w: i32, y: ^i32, col: ^Color, alpha: bool) -> bool {
	changed := false
	cw := (w - 2) / i32(len(PALETTE))
	for c, i in PALETTE {
		sr := Rect{x + i32(i) * cw, y^, cw - 1, 12}
		fill_rect(sr, c)
		if ui_hover(sr) {
			outline_rect(sr, WHITE)
			if ui.pressed[0] {
				a := col.a
				col^ = c
				col.a = a
				changed = true
			}
		}
	}
	y^ += 16
	rv, gv, bv, av := int(col.r), int(col.g), int(col.b), int(col.a)
	if slider(Rect{x, y^, w, 12}, &rv, 0, 255, "R", "", "") {col.r = u8(rv); changed = true}
	y^ += 14
	if slider(Rect{x, y^, w, 12}, &gv, 0, 255, "G", "", "") {col.g = u8(gv); changed = true}
	y^ += 14
	if slider(Rect{x, y^, w, 12}, &bv, 0, 255, "B", "", "") {col.b = u8(bv); changed = true}
	y^ += 14
	if alpha {
		if slider(Rect{x, y^, w, 12}, &av, 0, 255, "A", "", "") {col.a = u8(av); changed = true}
		y^ += 14
	}
	hr := Rect{x + 24, y^, w - 24, 14}
	text(x, y^ + 3, "Hex", C_TEXT_DIM)
	focused := ui.focus_id == make_id(hr, "text")
	if !focused do name_set(&hex_buf, color_hex_string(col^))
	if ch, _ := text_field(hr, &hex_buf, "RRGGBB or RRGGBBAA"); ch {
		s := name_str(&hex_buf)
		if c, ok := parse_color(fmt.tprintf("#%s", s), col^); ok && (len(s) == 6 || len(s) == 8 || len(s) == 3) {
			if !alpha || len(s) < 8 do c.a = col.a
			col^ = c
			changed = true
		}
	}
	y^ += 18
	return changed
}

// Properties --------------------------------------------------------------------------------------------------

prop_target: int // 0 fill, 1 stroke
grad_stop: int
xf_push_t: f64

first_selected :: proc(d: ^Doc) -> ^Node {
	nodes := sel_nodes(d)
	if len(nodes) > 0 do return nodes[0]
	return nil
}

// Applies one edited paint to the selection (and the drawing defaults).
apply_paint :: proc(d: ^Doc, p: Paint) {
	if prop_target == 0 do style_set_fill(d, p)
	else do style_set_stroke(d, p)
}

panel_properties :: proc(r: Rect) {
	d := doc
	ui.layer = 0
	clip_begin(r)
	defer clip_end()
	over := ui_hover(r)
	if over && ui.wheel != 0 && ui.focus_id == 0 && !popup.open do prop_scroll = max(prop_scroll - i32(ui.wheel * 24), 0)
	x := r.x + 8
	w := r.w - 16
	y := r.y + 6 - prop_scroll
	sel := first_selected(d)

	// fill / stroke switch
	half := (w - 4) / 2
	for k in 0 ..< 2 {
		br := Rect{x + i32(k) * (half + 4), y, half, 18}
		on := prop_target == k
		p: Paint
		if sel != nil do p = k == 0 ? sel.fill : sel.stroke
		else do p = k == 0 ? cur_fill : cur_stroke
		ctl_well(br, on ? C_ACCENT : C_RING)
		sw := Rect{br.x + 3, br.y + 3, 14, 12}
		draw_paint_swatch(sw, p)
		text(sw.x + 20, br.y + (br.h - FONT_CAP) / 2, k == 0 ? "Fill" : "Stroke", on ? WHITE : C_TEXT_DIM)
		if ui_hover(br) && ui.pressed[0] {
			prop_target = k
			grad_stop = 0
		}
	}
	y += 24

	paint: Paint
	if sel != nil do paint = prop_target == 0 ? sel.fill : sel.stroke
	else do paint = prop_target == 0 ? cur_fill : cur_stroke

	kinds := [?]string{"None", "Solid", "Linear gradient", "Radial gradient"}
	if nv, ch := combo(Rect{x, y, w, 14}, kinds[:], int(paint.kind)); ch {
		np := paint
		switch Paint_Kind(nv) {
		case .None:
			np = paint_none()
		case .Solid:
			c := paint.kind == .Solid ? paint.color : (paint.nstops > 0 ? paint.stops[0].color : Color{246, 170, 104, 255})
			np = paint_solid(c)
		case .Linear, .Radial:
			b := sel != nil ? node_local_bounds(sel) : BOUNDS_EMPTY
			np = paint_make_gradient(paint, b, Paint_Kind(nv) == .Radial)
		}
		apply_paint(d, np)
		paint = np
	}
	y += 20

	switch paint.kind {
	case .None:
	case .Solid:
		c := paint.color
		if color_edit(x, w, &y, &c, true) {
			np := paint
			np.color = c
			apply_paint(d, np)
		}
	case .Linear, .Radial:
		gradient_edit(d, x, w, &y, &paint)
	}

	// stroke settings
	text(x, y + 2, "Stroke", C_TEXT_DIM)
	hline(x + 44, y + 7, w - 44, C_BORDER)
	y += 16
	wv := int(cur_sw * 10)
	if sel != nil do wv = int(sel.sw * 10)
	if slider(Rect{x, y, w, 14}, &wv, 0, 1000, "Width", "", "", 1, 10) do style_set_width(d, f32(wv) / 10)
	y += 18
	caps := [?]string{"Butt cap", "Round cap", "Square cap"}
	joins := [?]string{"Miter join", "Round join", "Bevel join"}
	cv := int(sel != nil ? sel.cap : cur_cap)
	jv := int(sel != nil ? sel.join : cur_join)
	hw := (w - 4) / 2
	if nv, ch := combo(Rect{x, y, hw, 14}, caps[:], cv); ch do style_set_cap(d, Cap(nv))
	if nv, ch := combo(Rect{x + hw + 4, y, hw, 14}, joins[:], jv); ch do style_set_join(d, Join(nv))
	y += 18
	if sel != nil {
		dashes := [?]string{"Solid line", "Dashed", "Dotted", "Dash-dot"}
		dv := 0
		if sel.ndash == 2 && sel.dash[1] > sel.dash[0] * 3 do dv = 2
		else if sel.ndash == 2 do dv = 1
		else if sel.ndash == 4 do dv = 3
		if nv, ch := combo(Rect{x, y, hw, 14}, dashes[:], dv); ch {
			style_push(d)
			for n in sel_nodes(d) {
				sw := max(n.sw, 1)
				switch nv {
				case 0: n.ndash = 0
				case 1: n.ndash, n.dash = 2, {sw * 4, sw * 2, 0, 0}
				case 2: n.ndash, n.dash = 2, {0.01, sw * 2, 0, 0}
				case 3: n.ndash, n.dash = 4, {sw * 4, sw * 2, 0.01, sw * 2}
				}
				if nv == 2 do n.cap = .Round
			}
			doc_changed(d)
		}
		ov := int(sel.opacity * 100 + 0.5)
		if slider(Rect{x + hw + 4, y, hw, 14}, &ov, 0, 100, "Opacity", "", "%") do style_set_opacity(d, f32(ov) / 100)
		y += 18
		check_even := sel.even_odd
		if checkbox(x, y, "Even-odd fill", &check_even) {
			style_push(d)
			for n in sel_nodes(d) do n.even_odd = check_even
			doc_changed(d)
		}
		y += 18
	}

	// transform
	if sel != nil {
		text(x, y + 2, "Transform", C_TEXT_DIM)
		hline(x + 58, y + 7, w - 58, C_BORDER)
		y += 16
		b := sel_bounds(d)
		if !bounds_empty(b) {
			vals := [4]int{int(math.round(b.x0)), int(math.round(b.y0)), int(math.round(bounds_w(b))), int(math.round(bounds_h(b)))}
			names := [4]string{"X", "Y", "W", "H"}
			for i in 0 ..< 4 {
				cx := x + i32(i % 2) * (hw + 4)
				cy := y + i32(i / 2) * 18
				text(cx, cy + 3, names[i], C_TEXT_DIM)
				nv := vals[i]
				if field_int(Rect{cx + 14, cy, hw - 14, 14}, &nv, -100000, 100000) && nv != vals[i] {
					transform_to(d, b, i, f32(nv))
				}
			}
			y += 38
		}
		// object specific
		if sel.kind == .Rect {
			rx := int(sel.rx)
			text(x, y + 3, "Corner radius", C_TEXT_DIM)
			if field_int(Rect{x + 90, y, 50, 14}, &rx, 0, 10000) {
				style_push(d)
				for n in sel_nodes(d) do if n.kind == .Rect {
					n.rx, n.ry = f32(rx), f32(rx)
				}
				doc_changed(d)
			}
			y += 20
		}
		if sel.kind == .Text {
			if button(Rect{x, y, w, 14}, sel.font.n > 0 ? name_str(&sel.font) : DEFAULT_FONT, "Font (click to choose)") {
				cur_font = sel.font
				font_pick_open()
			}
			y += 18
			sz := int(sel.size + 0.5)
			if slider(Rect{x, y, w, 14}, &sz, 1, 1000, "Size", "Text size", "px", 2) {
				style_push(d)
				for n in sel_nodes(d) do if n.kind == .Text do n.size = f32(sz)
				doc_changed(d)
			}
			y += 20
			if button(Rect{x, y, w, 16}, "Convert to outlines") do run_cmd(.Text_To_Outlines)
			y += 22
		}
	}
	// the content height decides how far the panel can scroll
	content := y + prop_scroll - r.y
	prop_scroll = clamp(prop_scroll, 0, max(content - r.h + 8, 0))
}

draw_paint_swatch :: proc(r: Rect, pp: Paint) {
	p := pp
	switch p.kind {
	case .None:
		fill_rect(r, C_PANEL_DK)
		draw_line({f32(r.x), f32(r.y + r.h)}, {f32(r.x + r.w), f32(r.y)}, C_DANGER)
	case .Solid:
		fill_rect(r, Color{p.color.r, p.color.g, p.color.b, 255})
	case .Linear, .Radial:
		if p.nstops >= 2 {
			// strip of the gradient
			for i in 0 ..< r.w {
				t := f32(i) / f32(max(r.w - 1, 1))
				c := paint_stop_color(&p, t)
				fill_rect(Rect{r.x + i, r.y, 1, r.h}, Color{c.r, c.g, c.b, 255})
			}
		}
	}
	outline_rect(r, C_RING_HI)
}

gradient_edit :: proc(d: ^Doc, x, w: i32, y: ^i32, paint: ^Paint) {
	grad_stop = clamp(grad_stop, 0, max(paint.nstops - 1, 0))
	// preview bar
	bar := Rect{x, y^, w, 14}
	draw_paint_swatch(bar, Paint{kind = .Linear, nstops = paint.nstops, stops = paint.stops})
	for i in 0 ..< paint.nstops {
		mx := bar.x + i32(paint.stops[i].t * f32(bar.w - 1))
		mr := Rect{mx - 3, bar.y + bar.h - 2, 7, 8}
		fill_rect(mr, i == grad_stop ? WHITE : C_TEXT_DIM)
		if ui_hover(mr) && ui.pressed[0] do grad_stop = i
	}
	y^ += 24
	np := paint^
	changed := false
	if paint.nstops > 0 {
		tv := int(paint.stops[grad_stop].t * 100 + 0.5)
		hw := (w - 4) / 2
		if slider(Rect{x, y^, hw, 14}, &tv, 0, 100, "Stop", "", "%") {
			lo := grad_stop > 0 ? paint.stops[grad_stop - 1].t : 0
			hi := grad_stop < paint.nstops - 1 ? paint.stops[grad_stop + 1].t : 1
			np.stops[grad_stop].t = clamp(f32(tv) / 100, lo, hi)
			changed = true
		}
		if button(Rect{x + hw + 4, y^, hw / 2 - 2, 14}, "+ Stop", "Add a stop") && paint.nstops < MAX_STOPS {
			i := grad_stop
			j := min(i + 1, paint.nstops - 1)
			if j == i do i = max(i - 1, 0)
			t := (paint.stops[i].t + paint.stops[j].t) / 2
			c := lerp_color(paint.stops[i].color, paint.stops[j].color, 0.5)
			pos := j
			for k := np.nstops; k > pos; k -= 1 do np.stops[k] = np.stops[k - 1]
			np.stops[pos] = Stop{t, c}
			np.nstops += 1
			grad_stop = pos
			changed = true
		}
		if button(Rect{x + hw + 4 + hw / 2 + 2, y^, hw / 2 - 2, 14}, "- Stop", "Remove the stop") && paint.nstops > 2 {
			for k in grad_stop ..< np.nstops - 1 do np.stops[k] = np.stops[k + 1]
			np.nstops -= 1
			grad_stop = clamp(grad_stop, 0, np.nstops - 1)
			changed = true
		}
		y^ += 20
		c := paint.stops[grad_stop].color
		if color_edit(x, w, y, &c, true) {
			np.stops[grad_stop].color = c
			changed = true
		}
		spreads := [?]string{"Pad", "Reflect", "Repeat"}
		if nv, ch := combo(Rect{x, y^, (w - 4) / 2, 14}, spreads[:], int(paint.spread)); ch {
			np.spread = u8(nv)
			changed = true
		}
		if button(Rect{x + (w - 4) / 2 + 4, y^, (w - 4) / 2, 14}, "Fit to object") {
			sel := first_selected(d)
			if sel != nil {
				b := node_local_bounds(sel)
				if !bounds_empty(b) {
					g := paint_make_gradient(np, b, paint.kind == .Radial)
					np.p0, np.p1 = g.p0, g.p1
					changed = true
				}
			}
		}
		y^ += 20
	}
	if changed {
		apply_paint(d, np)
		paint^ = np
	}
}

// Changes one of x, y, w, h of the selection's bounds.
transform_to :: proc(d: ^Doc, b: Bounds, which: int, v: f32) {
	if ui.time - xf_push_t > 0.6 do history_push(d)
	xf_push_t = ui.time
	sel_remember(d)
	m := MAT_ID
	switch which {
	case 0: m = mat_translate(v - b.x0, 0)
	case 1: m = mat_translate(0, v - b.y0)
	case 2:
		if bounds_w(b) > 1e-6 && v > 0 do m = mat_mul(mat_translate(b.x0, 0), mat_mul(mat_scale(v / bounds_w(b), 1), mat_translate(-b.x0, 0)))
	case 3:
		if bounds_h(b) > 1e-6 && v > 0 do m = mat_mul(mat_translate(0, b.y0), mat_mul(mat_scale(1, v / bounds_h(b)), mat_translate(0, -b.y0)))
	}
	sel_apply(d, m)
	tl_reset()
}
