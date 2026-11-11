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
osection :: proc(key, title, tip: string) {
	oui_tip(oui.element(uictx, key, "section-head"), {title, tip})
	oui.label(uictx, "t", title)
	oui.element_leaf(uictx, "line", "section-line")
	oui.end(uictx)
}

obj_scroll: int
prop_scroll: i32

panel_right :: proc() {
	panel_element(.Right, "right", "sidepanel")
	defer oui.end(uictx)
	osection("objects-head", "Objects", "Everything in this document, frontmost at the top. Drag rows to change the stacking order or to move objects in and out of groups.")
	oui_slot("objects", "objects")
	oui.element(uictx, "object-buttons", "row", {id = "object-buttons"})
	ob :: proc(key: string, ic: Icon, name: string, c: Cmd) {
		if clicked, _ := oui_icon_button(key, ic, cmd_tip(name, c), {class = "panel-btn", enabled = true}); clicked do run_cmd(c)
	}
	ob("raise", .Up, "Raise", .Raise)
	ob("lower", .Down, "Lower", .Lower)
	ob("dup", .Copy, "Duplicate", .Duplicate)
	ob("group", .Layer, "Group", .Group)
	ob("del", .Trash, "Delete", .Delete)
	oui.element_leaf(uictx, "spacer", "spacer")
	otext("count", fmt.tprintf("%d objects", len(doc.root.children)), "dim", {"Object count", "How many objects are at the top level of this document. Objects inside a group are not counted."})
	oui.end(uictx)
	osection("props-head", "Properties", "The look and position of the selected objects. With nothing selected, the colors and stroke settings apply to new shapes.")
	oui_slot("properties", "properties")
	// a short window needs the room for the properties
	if show_navigator && ui.h >= 360 {
		osection("nav-head", "Navigator", "The whole page, with a box around what the view shows.")
		oui_slot("navigator", "navigator")
	}
}

// A panel that scrolls lays its widgets out past its own box, clipped away, where they could still catch the pointer
// over whatever is really there. Hides the pointer from them unless a widget is being dragged. Returns the position
// to give back with panel_pointer_end.
panel_pointer_begin :: proc(r: Rect) -> (mx, my: i32) {
	mx, my = ui.mx, ui.my
	if ui.active_id == 0 && !in_rect(r, mx, my) do ui.mx, ui.my = -100000, -100000
	return
}

panel_pointer_end :: proc(mx, my: i32) {
	ui.mx, ui.my = mx, my
}

// Navigator ----------------------------------------------------------------------------------------------------

show_navigator := true

@(private = "file")
Nav_Cache :: struct {
	tex:     Texture,
	doc:     ^Doc,
	version: int,
	time:    f64,
}

@(private = "file")
nav: Nav_Cache

// The whole page with the visible area marked. Click or drag to move the view.
panel_navigator :: proc(r: Rect) {
	ui.layer = 0
	d := doc
	ctl_well(r)
	if r.w <= 8 || r.h <= 8 || d.w <= 0 || d.h <= 0 do return
	z := min(f32(r.w - 8) / d.w, f32(r.h - 8) / d.h)
	w, h := d.w * z, d.h * z
	dst := FRect{math.floor(f32(r.x) + (f32(r.w) - w) / 2), math.floor(f32(r.y) + (f32(r.h) - h) / 2), w, h}
	pw, ph := max(int(math.round(w * ui.scale)), 1), max(int(math.round(h * ui.scale)), 1)
	// redrawn a few times a second at most: it shows the same drawing as the canvas, which comes first
	same_view := nav.doc == d && int(nav.tex.w) == pw && int(nav.tex.h) == ph
	if !same_view || (nav.version != d.version && ui.time - nav.time > 0.2) {
		pix := make([]Color, pw * ph, context.temp_allocator)
		rs: Raster
		raster_init(&rs, pw, ph)
		defer raster_free(&rs)
		k := f32(pw) / d.w
		render_doc_to(d, pix, pw, ph, Mat{k, 0, 0, k, 0, 0}, &rs, true)
		tex_destroy(&nav.tex)
		nav.tex = tex_from_pixels(pix, pw, ph, .Linear)
		nav.doc, nav.version, nav.time = d, d.version, ui.time
	}
	draw_tex(nav.tex, {0, 0, f32(nav.tex.w), f32(nav.tex.h)}, dst)
	vp := canvas_vp
	vr := FRect{dst.x + (f32(vp.x) - d.ox) / d.zoom * z, dst.y + (f32(vp.y) - d.oy) / d.zoom * z, f32(vp.w) / d.zoom * z, f32(vp.h) / d.zoom * z}
	clip_begin(r)
	draw_rrect_outline(vr.x, vr.y, vr.w, vr.h, 0, C_ACCENT)
	clip_end()
	tip_area(r, "navigator", {"Navigator", "Click or drag to move the view to that part of the page."})
	if act, fx, fy := drag_area(r, make_id(r, "nav")); act {
		// center the view on the clicked point
		px := (f32(r.x) + fx * f32(r.w - 1) - dst.x) / z
		py := (f32(r.y) + fy * f32(r.h - 1) - dst.y) / z
		d.ox = f32(vp.x) + f32(vp.w) / 2 - px * d.zoom
		d.oy = f32(vp.y) + f32(vp.h) / 2 - py * d.zoom
	}
}

drag_area :: proc(r: Rect, id: u32) -> (active: bool, fx, fy: f32) {
	if ui_hover(r) && ui.pressed[0] do ui.active_id = id
	if ui.active_id == id && ui.down[0] {
		fx = clamp(f32(ui.mx - r.x) / f32(max(r.w - 1, 1)), 0, 1)
		fy = clamp(f32(ui.my - r.y) / f32(max(r.h - 1, 1)), 0, 1)
		active = true
	}
	return
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
	tip_area(area, "objects", {"Objects", "Everything in this document, frontmost at the top. Scroll with the mouse wheel."})
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
		tip_area(rr, "object-row", {"", "Click to select this object, Shift-click to add it to the selection or take it out. Drag to change its stacking order or move it in or out of a group. Drop beside the list to cancel."})
		if icon_button(Rect{x, y + 1, 14, 14}, .Eye, {"Show or hide", "Hidden objects stay in the document but are not drawn or picked."}, n.visible) {
			history_push(d)
			n.visible = !n.visible
			doc_changed(d)
		}
		if icon_button(Rect{x + 15, y + 1, 14, 14}, .Lock, {"Lock or unlock", "A locked object can't be picked on the canvas, so it won't be moved by accident."}, n.locked) {
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

// Color editing ---------------------------------------------------------------------------------------------

DEFAULT_SWATCHES := [?]Color {
	{0, 0, 0, 255}, {64, 64, 64, 255}, {128, 128, 128, 255}, {192, 192, 192, 255}, {255, 255, 255, 255}, {214, 64, 52, 255},
	{246, 170, 104, 255}, {240, 196, 60, 255}, {70, 150, 90, 255}, {60, 160, 200, 255}, {70, 90, 190, 255}, {150, 80, 170, 255},
}

@(private = "file")
swatches: [dynamic]Color

swatches_list :: proc() -> []Color {
	@(static) filled := false
	if !filled {
		filled = true
		append(&swatches, ..DEFAULT_SWATCHES[:])
	}
	return swatches[:]
}

// Colors picked lately, newest first.
RECENT_MAX :: 16
recent: [dynamic]Color

recent_push :: proc(c: Color) {
	for x, i in recent {
		if x == c {
			ordered_remove(&recent, i)
			break
		}
	}
	inject_at(&recent, 0, c)
	if len(recent) > RECENT_MAX do resize(&recent, RECENT_MAX)
}

hex_buf: Name

color_hex_string :: proc(c: Color) -> string {
	if c.a == 255 do return fmt.tprintf("%02x%02x%02x", c.r, c.g, c.b)
	return fmt.tprintf("%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
}

// The picker's position, kept apart from the color so the hue survives grays and black.
@(private = "file")
Picker_State :: struct {
	h, s, v: f32,
	rgb:     [3]u8, // the color these belong to
}

@(private = "file")
picker: Picker_State

@(private = "file")
recent_pending: Maybe(Color) // edited just now: joins the recent colors when the pointer lets go

// Saturation / value field and hue strip. Returns true when the color changed.
@(private = "file")
color_picker :: proc(r: Rect, col: ^Color) -> bool {
	if picker.rgb != {col.r, col.g, col.b} {
		h, s, v := rgb_to_hsv(col^)
		if s > 0.001 && v > 0.001 do picker.h = h
		picker.s, picker.v = s, v
		picker.rgb = {col.r, col.g, col.b}
	}
	sv := Rect{r.x, r.y, r.w - 20, r.h}
	hue := Rect{r.x + r.w - 12, r.y, 12, r.h}
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), WHITE, hsv_to_rgb(picker.h, 1, 1), false)
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), Color{0, 0, 0, 0}, Color{0, 0, 0, 255})
	outline_rect(sv, C_RING_HI)
	tip_area(sv, "sv", {"Saturation and value", "Drag to set the color: left to right from gray to full color, top to bottom from bright to dark."})
	tip_area(hue, "hue", {"Hue", "Drag up or down to choose the hue."})
	changed := false
	if act, fx, fy := drag_area(sv, make_id(sv, "sv")); act {
		picker.s, picker.v = fx, 1 - fy
		changed = true
	}
	cx := sv.x + i32(picker.s * f32(sv.w - 1))
	cy := sv.y + i32((1 - picker.v) * f32(sv.h - 1))
	draw_circle_outline(f32(cx) + 0.5, f32(cy) + 0.5, 4, BLACK)
	draw_circle_outline(f32(cx) + 0.5, f32(cy) + 0.5, 5, WHITE)
	for i in 0 ..< 6 {
		seg_h := hue.h / 6
		draw_gradient(f32(hue.x), f32(hue.y + i32(i) * seg_h), f32(hue.w), f32(seg_h + 1), hsv_to_rgb(f32(i) * 60, 1, 1), hsv_to_rgb(f32(i + 1) * 60, 1, 1))
	}
	outline_rect(hue, C_RING_HI)
	if act, _, fy := drag_area(hue, make_id(hue, "hue")); act {
		picker.h = fy * 359.9
		changed = true
	}
	hy := hue.y + i32(picker.h / 360 * f32(hue.h - 1))
	draw_rrect(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, WHITE)
	draw_rrect_outline(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, Color{0, 0, 0, 160})
	if changed {
		c := hsv_to_rgb(picker.h, picker.s, picker.v, col.a)
		col^ = c
		picker.rgb = {c.r, c.g, c.b}
	}
	return changed
}

// HSV picker, RGB(A) sliders, a hex field, swatches and recent colors. Returns true when the color changed.
// `y` is advanced.
color_edit :: proc(x, w: i32, y: ^i32, col: ^Color, alpha: bool) -> bool {
	changed := color_picker(Rect{x, y^, w, 84}, col)
	y^ += 90
	rv, gv, bv, av := int(col.r), int(col.g), int(col.b), int(col.a)
	if slider(Rect{x, y^, w, 12}, &rv, 0, 255, "R", {"Red", "How much red is in this color, from 0 (none) to 255 (full). Drag, or use the mouse wheel."}, tint_in = Color{226, 96, 96, 255}) {col.r = u8(rv); changed = true}
	y^ += 14
	if slider(Rect{x, y^, w, 12}, &gv, 0, 255, "G", {"Green", "How much green is in this color, from 0 (none) to 255 (full). Drag, or use the mouse wheel."}, tint_in = Color{96, 200, 110, 255}) {col.g = u8(gv); changed = true}
	y^ += 14
	if slider(Rect{x, y^, w, 12}, &bv, 0, 255, "B", {"Blue", "How much blue is in this color, from 0 (none) to 255 (full). Drag, or use the mouse wheel."}, tint_in = Color{100, 140, 240, 255}) {col.b = u8(bv); changed = true}
	y^ += 14
	if alpha {
		if slider(Rect{x, y^, w, 12}, &av, 0, 255, "A", {"Alpha", "How solid this color is, from 0 (see-through) to 255 (solid). Drag, or use the mouse wheel."}) {col.a = u8(av); changed = true}
		y^ += 14
	}
	hr := Rect{x + 24, y^, w - 24, 14}
	tip_text(x, y^ + 3, "Hex", C_TEXT_DIM, {"Hex color", "This color as a hex code."})
	focused := ui.focus_id == make_id(hr, "text")
	if !focused do name_set(&hex_buf, color_hex_string(col^))
	if ch, _ := text_field(hr, &hex_buf, {"Hex color", "This color as a hex code: RGB, RRGGBB, or RRGGBBAA to include alpha. Type or paste one here."}); ch {
		s := name_str(&hex_buf)
		if c, ok := parse_color(fmt.tprintf("#%s", s), col^); ok && (len(s) == 6 || len(s) == 8 || len(s) == 3) {
			if !alpha || len(s) < 8 do c.a = col.a
			col^ = c
			changed = true
		}
	}
	y^ += 20

	// swatches: colors kept ready to use, for this session
	tip_text(x, y^ + 3, "Swatches", C_TEXT_DIM, {"Swatches", "Colors kept ready to use. Click one to use it, right-click to remove it. A color group's + can add them all."})
	if icon_button(Rect{x + w - 16, y^, 16, 14}, .Plus, {"Add swatch", "Add this color to the swatches."}) {
		swatches_list()
		append(&swatches, Color{col.r, col.g, col.b, 255})
	}
	y^ += 16
	CELL :: 18
	cols := max(w / CELL, 1)
	list := swatches_list()
	remove := -1
	for c, i in list {
		sr := Rect{x + i32(i) % cols * CELL, y^ + i32(i) / cols * CELL, CELL - 2, CELL - 2}
		draw_rrect(f32(sr.x), f32(sr.y), f32(sr.w), f32(sr.h), 2, c)
		draw_rrect_outline(f32(sr.x), f32(sr.y), f32(sr.w), f32(sr.h), 2, ui_hover(sr) ? WHITE : C_RING_HI)
		if ui_hover(sr) {
			tooltip_hover(make_id(sr, "swatch"), {color_hex(c), "Click to use this color. The opacity stays as it is. Right-click to remove it."})
			if ui.pressed[0] {
				col.r, col.g, col.b = c.r, c.g, c.b
				changed = true
			} else if ui.pressed[1] {
				remove = i
			}
		}
	}
	if remove >= 0 do ordered_remove(&swatches, remove)
	y^ += (i32(len(list)) + cols - 1) / cols * CELL + 4
	if changed do recent_pending = Color{col.r, col.g, col.b, 255}

	// recent colors, newest first; using one doesn't reorder them under the pointer
	tip_text(x, y^ + 3, "Recent", C_TEXT_DIM, {"Recent colors", "The colors you have picked lately, newest first."})
	rx := x + 44
	for c in recent {
		if rx + 12 > x + w do break
		sr := Rect{rx, y^ + 1, 12, 12}
		draw_rrect(f32(sr.x), f32(sr.y), 12, 12, 2, c)
		draw_rrect_outline(f32(sr.x), f32(sr.y), 12, 12, 2, ui_hover(sr) ? WHITE : C_RING_HI)
		if ui_hover(sr) {
			tooltip_hover(make_id(sr, "recent"), {color_hex(c), "Click to use this color. The opacity stays as it is."})
			if ui.pressed[0] {
				col.r, col.g, col.b = c.r, c.g, c.b
				changed = true
			}
		}
		rx += 14
	}
	y^ += 20
	if pending, ok := recent_pending.?; ok && !ui.down[0] && ui.focus_id == 0 {
		recent_push(pending)
		recent_pending = nil
	}
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
	real_mx, real_my := panel_pointer_begin(r)
	defer panel_pointer_end(real_mx, real_my)
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
		tip_area(br, "paint-target", k == 0 ? Tip{"Edit fill", "Edit the color inside the object. The controls below change to match."} : Tip{"Edit stroke", "Edit the color of the object's outline. The controls below change to match."})
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
	if nv, ch := combo(Rect{x, y, w, 14}, kinds[:], int(paint.kind), {"Paint type", "None: nothing is drawn. Solid: one color. Linear gradient: colors blend along a line. Radial gradient: colors blend outwards from a center. On the canvas, the Select tool shows a gradient's handles."}); ch {
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
	tip_text(x, y + 2, "Stroke", C_TEXT_DIM, {"Stroke settings", "How the outline is drawn. To change its color, pick Stroke at the top of this panel."})
	hline(x + 44, y + 7, w - 44, C_BORDER)
	y += 16
	{
		st := stroke_style_current(d)
		sv := stroke_to_ints(st)
		tip_text(x, y + 3, "Preset", C_TEXT_DIM, STROKE_PRESET_TIP)
		if v, ok := preset_row(Rect{x + 44, y, w - 44, 14}, "stroke", stroke_builtins[:], &stroke_preset, sv[:], tip = STROKE_PRESET_TIP); ok {
			style_set_stroke_style(d, stroke_from_ints(st, v.vals))
		}
		y += 18
	}
	wv := int(cur_sw * 10)
	if sel != nil do wv = int(sel.sw * 10)
	if slider(Rect{x, y, w, 14}, &wv, 0, 1000, "Width", {"Stroke width", "Thickness of the outline in document units. Drag, or use the mouse wheel. 0 draws no outline."}, "", 1, 10) do style_set_width(d, f32(wv) / 10)
	y += 18
	caps := [?]string{"Butt cap", "Round cap", "Square cap"}
	joins := [?]string{"Miter join", "Round join", "Bevel join"}
	cv := int(sel != nil ? sel.cap : cur_cap)
	jv := int(sel != nil ? sel.join : cur_join)
	hw := (w - 4) / 2
	if nv, ch := combo(Rect{x, y, hw, 14}, caps[:], cv, {"Line ends", "How the ends of an open path look. Butt: cut off at the end point. Round: a half circle past the end. Square: a square past the end."}); ch do style_set_cap(d, Cap(nv))
	if nv, ch := combo(Rect{x + hw + 4, y, hw, 14}, joins[:], jv, {"Corners", "How the outline turns at corners. Miter: a sharp point. Round: rounded off. Bevel: the point is cut flat."}); ch do style_set_join(d, Join(nv))
	y += 18
	dv := sel != nil ? line_pattern_of(sel.dash, sel.ndash) : line_pattern_of(cur_dash, cur_ndash)
	if nv, ch := combo(Rect{x, y, hw, 14}, LINE_PATTERNS[:], dv, {"Line pattern", "A solid line, dashes, dots, or alternating dashes and dots. The pattern is sized from the stroke width."}); ch do style_set_line_pattern(d, nv)
	if sel != nil {
		ov := int(sel.opacity * 100 + 0.5)
		if slider(Rect{x + hw + 4, y, hw, 14}, &ov, 0, 100, "Opacity", {"Opacity", "How solid the whole object is, fill and stroke together: 100% is solid, 0% invisible. Drag, or use the mouse wheel."}, "%") do style_set_opacity(d, f32(ov) / 100)
	}
	y += 18
	if sel != nil {
		check_even := sel.even_odd
		if checkbox(x, y, "Even-odd fill", &check_even, {"Even-odd fill", "How overlapping parts of a path fill. On: areas overlapped an even number of times become holes. Off: the drawing direction decides, so overlaps usually stay filled."}) {
			style_push(d)
			for n in sel_nodes(d) do n.even_odd = check_even
			doc_changed(d)
		}
		y += 18
	}

	// transform
	if sel != nil {
		tip_text(x, y + 2, "Transform", C_TEXT_DIM, {"Transform", "The position and size of the selection as a whole."})
		hline(x + 58, y + 7, w - 58, C_BORDER)
		y += 16
		b := sel_bounds(d)
		if !bounds_empty(b) {
			vals := [4]int{int(math.round(b.x0)), int(math.round(b.y0)), int(math.round(bounds_w(b))), int(math.round(bounds_h(b)))}
			names := [4]string{"X", "Y", "W", "H"}
			tips := [4]Tip {
				{"X position", "Distance from the left of the page to the left edge of the selection. Type a value or use the mouse wheel."},
				{"Y position", "Distance from the top of the page to the top edge of the selection. Type a value or use the mouse wheel."},
				{"Width", "Width of the selection. Changing it stretches the selection from its left edge. Type a value or use the mouse wheel."},
				{"Height", "Height of the selection. Changing it stretches the selection from its top edge. Type a value or use the mouse wheel."},
			}
			for i in 0 ..< 4 {
				cx := x + i32(i % 2) * (hw + 4)
				cy := y + i32(i / 2) * 18
				tip_text(cx, cy + 3, names[i], C_TEXT_DIM, tips[i])
				nv := vals[i]
				if field_int(Rect{cx + 14, cy, hw - 14, 14}, &nv, -100000, 100000, tips[i]) && nv != vals[i] {
					transform_to(d, b, i, f32(nv))
				}
			}
			y += 38
		}
		// object specific
		if sel.kind == .Rect {
			rx := int(sel.rx)
			RADIUS_TIP :: "How rounded this rectangle's corners are, in document units. 0 makes square corners. Type a value or use the mouse wheel."
			tip_text(x, y + 3, "Corner radius", C_TEXT_DIM, {"Corner radius", RADIUS_TIP})
			if field_int(Rect{x + 90, y, 50, 14}, &rx, 0, 10000, {"Corner radius", RADIUS_TIP}) {
				style_push(d)
				for n in sel_nodes(d) do if n.kind == .Rect {
					n.rx, n.ry = f32(rx), f32(rx)
				}
				doc_changed(d)
			}
			y += 20
		}
		if sel.kind == .Text {
			if button(Rect{x, y, w, 14}, sel.font.n > 0 ? name_str(&sel.font) : DEFAULT_FONT, {"Font", "The font of this text. Click to choose from the bundled and installed fonts."}) {
				cur_font = sel.font
				font_pick_open()
			}
			y += 18
			sz := int(sel.size + 0.5)
			if slider(Rect{x, y, w, 14}, &sz, 1, 1000, "Size", {"Text size", "The size of this text in pixels. Drag, or use the mouse wheel. Shift steps through round values."}, "px", 2) {
				style_push(d)
				for n in sel_nodes(d) do if n.kind == .Text do n.size = f32(sz)
				doc_changed(d)
			}
			y += 20
			if button(Rect{x, y, w, 16}, "Convert to outlines", cmd_tip("Convert to outlines", .Text_To_Outlines)) do run_cmd(.Text_To_Outlines)
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
	tip_area(bar, "gradient-bar", {"Gradient preview", "How this gradient looks. The markers below it are its color stops."})
	for i in 0 ..< paint.nstops {
		mx := bar.x + i32(paint.stops[i].t * f32(bar.w - 1))
		mr := Rect{mx - 3, bar.y + bar.h - 2, 7, 8}
		fill_rect(mr, i == grad_stop ? WHITE : C_TEXT_DIM)
		tip_area(mr, "gradient-stop", {"Color stop", "Click to select it, then edit its position and color below."})
		if ui_hover(mr) && ui.pressed[0] do grad_stop = i
	}
	y^ += 24
	np := paint^
	changed := false
	if paint.nstops > 0 {
		tv := int(paint.stops[grad_stop].t * 100 + 0.5)
		hw := (w - 4) / 2
		if slider(Rect{x, y^, hw, 14}, &tv, 0, 100, "Stop", {"Stop position", "Where the selected color stop sits along the gradient. It can't pass the stops on either side. Drag, or use the mouse wheel."}, "%") {
			lo := grad_stop > 0 ? paint.stops[grad_stop - 1].t : 0
			hi := grad_stop < paint.nstops - 1 ? paint.stops[grad_stop + 1].t : 1
			np.stops[grad_stop].t = clamp(f32(tv) / 100, lo, hi)
			changed = true
		}
		if button(Rect{x + hw + 4, y^, hw / 2 - 2, 14}, "+ Stop", {"", "Add a color stop next to the selected one, halfway to its neighbor and with the blended color."}) && paint.nstops < MAX_STOPS {
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
		if button(Rect{x + hw + 4 + hw / 2 + 2, y^, hw / 2 - 2, 14}, "- Stop", {"", "Remove the selected color stop. A gradient always keeps at least two."}) && paint.nstops > 2 {
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
		if nv, ch := combo(Rect{x, y^, (w - 4) / 2, 14}, spreads[:], int(paint.spread), {"Spread", "What happens past the ends of the gradient. Pad: the end colors carry on. Reflect: it repeats, mirrored each time. Repeat: it starts over."}); ch {
			np.spread = u8(nv)
			changed = true
		}
		if button(Rect{x + (w - 4) / 2 + 4, y^, (w - 4) / 2, 14}, "Fit to object", {"Fit to object", "Reset the gradient's position so it spans the selected object. Its colors are kept."}) {
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
