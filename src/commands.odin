package pangolin

import "core:fmt"
import "core:strings"

// Menu / shortcut commands. Menu items carry one of these so the popup can show its shortcut.
Cmd :: enum {
	None,
	New,
	New_Font,
	Open,
	Save,
	Save_As,
	Export_PNG,
	Close_Doc,
	Quit,
	Undo,
	Redo,
	Cut,
	Copy,
	Paste,
	Paste_In_Place,
	Duplicate,
	Delete,
	Select_All,
	Deselect,
	Group,
	Ungroup,
	Raise,
	Lower,
	To_Front,
	To_Back,
	Flip_H,
	Flip_V,
	Rotate_CW,
	Rotate_CCW,
	Align_Left,
	Align_Center,
	Align_Right,
	Align_Top,
	Align_Middle,
	Align_Bottom,
	Distribute_H,
	Distribute_V,
	Object_To_Path,
	Stroke_To_Path,
	Union,
	Subtract,
	Intersect,
	Exclude,
	Combine,
	Break_Apart,
	Reverse,
	Simplify,
	Offset_Out,
	Offset_In,
	Text_To_Outlines,
	Fit_View,
	Actual_Size,
	Zoom_In,
	Zoom_Out,
	Toggle_Grid,
	Toggle_Snap,
	Toggle_Canvas_Mode,
	Reset_Tool_Groups,
	Page_Size,
	Fit_Page_To_Content,
	Trace_Load,
	Trace_Clear,
	Trace_More,
	Trace_Less,
	Font_Add_Glyphs,
	Font_Export,
	Font_Fix_Direction,
	Font_Remove_Overlap,
	Font_Prev_Glyph,
	Font_Next_Glyph,
	Shortcuts,
	About,
}

shortcut_text :: proc(c: Cmd) -> string {
	#partial switch c {
	case .New:            return "Ctrl+N"
	case .Open:           return "Ctrl+O"
	case .Save:           return "Ctrl+S"
	case .Save_As:        return "Ctrl+Shift+S"
	case .Export_PNG:     return "Ctrl+E"
	case .Close_Doc:      return "Ctrl+W"
	case .Quit:           return "Ctrl+Q"
	case .Undo:           return "Ctrl+Z"
	case .Redo:           return "Ctrl+Shift+Z"
	case .Cut:            return "Ctrl+X"
	case .Copy:           return "Ctrl+C"
	case .Paste:          return "Ctrl+V"
	case .Paste_In_Place: return "Ctrl+Shift+V"
	case .Duplicate:      return "Ctrl+D"
	case .Delete:         return "Del"
	case .Select_All:     return "Ctrl+A"
	case .Deselect:       return "Ctrl+Shift+A"
	case .Group:          return "Ctrl+G"
	case .Ungroup:        return "Ctrl+Shift+G"
	case .Raise:          return "PgUp"
	case .Lower:          return "PgDn"
	case .To_Front:       return "Home"
	case .To_Back:        return "End"
	case .Union:          return "Ctrl++"
	case .Subtract:       return "Ctrl+-"
	case .Intersect:      return "Ctrl+*"
	case .Combine:        return "Ctrl+K"
	case .Break_Apart:    return "Ctrl+Shift+K"
	case .Object_To_Path: return "Ctrl+Shift+C"
	case .Fit_View:       return "Ctrl+0"
	case .Actual_Size:    return "Ctrl+1"
	case .Zoom_In:        return "+"
	case .Zoom_Out:       return "-"
	case .Toggle_Grid:    return "Ctrl+;"
	case .Toggle_Snap:    return "Ctrl+Shift+;"
	case .Toggle_Canvas_Mode: return "Tab"
	case .Font_Prev_Glyph: return "["
	case .Font_Next_Glyph: return "]"
	}
	return ""
}

// Clipboard of cloned nodes (also published as SVG text for other apps).
clip_nodes: [dynamic]^Node

run_cmd :: proc(c: Cmd) {
	d := doc
	if d == nil && c != .New && c != .Open && c != .Quit && c != .New_Font && c != .About && c != .Shortcuts do return
	switch c {
	case .None:
	case .New:
		dialog_open(.New_Doc)
	case .New_Font:
		font_new_doc()
	case .Open:
		if path, ok := native_dialog(false, "Open", FILTERS_OPEN[:], "", ""); ok {
			open_path(path)
		}
	case .Save:
		doc_save(d, false)
	case .Save_As:
		doc_save(d, true)
	case .Export_PNG:
		dialog_open(.Export_PNG)
	case .Close_Doc:
		doc_close(d)
	case .Quit:
		want_quit = true
	case .Undo:
		tools_cancel()
		history_undo(d)
	case .Redo:
		tools_cancel()
		history_redo(d)
	case .Cut:
		cmd_copy(d)
		cmd_delete(d)
	case .Copy:
		cmd_copy(d)
	case .Paste:
		cmd_paste(d, false)
	case .Paste_In_Place:
		cmd_paste(d, true)
	case .Duplicate:
		cmd_duplicate(d)
	case .Delete:
		cmd_delete(d)
	case .Select_All:
		clear(&d.sel)
		for n in d.root.children {
			if n.visible && !n.locked do append(&d.sel, n.uid)
		}
	case .Deselect:
		clear(&d.sel)
	case .Group:
		cmd_group(d)
	case .Ungroup:
		cmd_ungroup(d)
	case .Raise:
		cmd_order(d, 1)
	case .Lower:
		cmd_order(d, -1)
	case .To_Front:
		cmd_order(d, 1000000)
	case .To_Back:
		cmd_order(d, -1000000)
	case .Flip_H:
		cmd_transform_sel(d, .Flip_H)
	case .Flip_V:
		cmd_transform_sel(d, .Flip_V)
	case .Rotate_CW:
		cmd_transform_sel(d, .Rot_CW)
	case .Rotate_CCW:
		cmd_transform_sel(d, .Rot_CCW)
	case .Align_Left, .Align_Center, .Align_Right, .Align_Top, .Align_Middle, .Align_Bottom:
		cmd_align(d, c)
	case .Distribute_H, .Distribute_V:
		cmd_distribute(d, c == .Distribute_H)
	case .Object_To_Path:
		cmd_to_path(d)
	case .Stroke_To_Path:
		cmd_stroke_to_path(d)
	case .Union:
		cmd_bool(d, .Union)
	case .Subtract:
		cmd_bool(d, .Subtract)
	case .Intersect:
		cmd_bool(d, .Intersect)
	case .Exclude:
		cmd_bool(d, .Exclude)
	case .Combine:
		cmd_combine(d)
	case .Break_Apart:
		cmd_break_apart(d)
	case .Reverse:
		cmd_reverse(d)
	case .Simplify:
		cmd_simplify(d)
	case .Offset_Out:
		cmd_offset(d, 1)
	case .Offset_In:
		cmd_offset(d, -1)
	case .Text_To_Outlines:
		cmd_text_outlines(d)
	case .Fit_View:
		view_fit(d, view_vp)
	case .Actual_Size:
		view_actual(d, view_vp)
	case .Zoom_In:
		zoom_at(d, {f32(view_vp.x + view_vp.w / 2), f32(view_vp.y + view_vp.h / 2)}, 1.25)
	case .Zoom_Out:
		zoom_at(d, {f32(view_vp.x + view_vp.w / 2), f32(view_vp.y + view_vp.h / 2)}, 0.8)
	case .Toggle_Grid:
		show_grid = !show_grid
	case .Toggle_Snap:
		snap_grid = !snap_grid
	case .Toggle_Canvas_Mode:
		canvas_mode = !canvas_mode
	case .Reset_Tool_Groups:
		tool_groups_default()
		set_status("Tool groups reset")
	case .Page_Size:
		dialog_open(.Page_Size)
	case .Fit_Page_To_Content:
		cmd_fit_page(d)
	case .Trace_Load:
		trace_load(d)
	case .Trace_Clear:
		tex_destroy(&d.trace)
	case .Trace_More:
		d.trace_a = min(d.trace_a + 0.1, 1)
	case .Trace_Less:
		d.trace_a = max(d.trace_a - 0.1, 0.05)
	case .Font_Add_Glyphs:
		dialog_open(.Add_Glyphs)
	case .Font_Export:
		font_export(d)
	case .Font_Fix_Direction:
		font_fix_direction(d)
	case .Font_Remove_Overlap:
		font_remove_overlap_current(d)
	case .Font_Prev_Glyph:
		font_select_glyph(d, d.font.cur - 1)
	case .Font_Next_Glyph:
		font_select_glyph(d, d.font.cur + 1)
	case .Shortcuts:
		dialog_open(.Shortcuts)
	case .About:
		dialog_open(.About)
	}
}

// Documents -------------------------------------------------------------------------------------------------

open_path :: proc(path: string) {
	low := strings.to_lower(path, context.temp_allocator)
	switch {
	case strings.has_suffix(low, ".svg"):
		if d, ok := svg_load(path); ok {
			add_doc(d)
			if len(svg_skipped) > 0 {
				set_statusf("Opened with %d unsupported element(s) skipped (e.g. <%s>)", len(svg_skipped), svg_skipped[0])
			} else {
				set_status("Opened")
			}
		} else {
			message("Open", fmt.tprintf("Could not read %s as an SVG file.", path))
		}
	case strings.has_suffix(low, ".ttf"), strings.has_suffix(low, ".otf"):
		if d, ok := font_open_doc(path); ok {
			add_doc(d)
			set_status("Font opened")
		} else {
			message("Open", fmt.tprintf("Could not read %s as a TrueType font.", path))
		}
	case:
		message("Open", "Unsupported file type.")
	}
}

doc_save :: proc(d: ^Doc, as: bool) {
	tools_cancel()
	if d.kind == .Font {
		font_export(d)
		return
	}
	path := d.path
	if as || path == "" {
		initial := fmt.tprintf("%s.svg", name_str(&d.title))
		p, ok := native_dialog(true, "Save SVG", FILTERS_SVG[:], "svg", initial)
		if !ok do return
		path = p
	}
	if svg_save(d, path) {
		d.path = strings.clone(path)
		d.modified = false
		stem := path
		if i := strings.last_index_any(stem, "/\\"); i >= 0 do stem = stem[i + 1:]
		if i := strings.last_index_byte(stem, '.'); i > 0 do stem = stem[:i]
		d.title = make_name(stem)
		set_status("Saved")
	} else {
		message("Save", "Could not write the file.")
	}
}

doc_close :: proc(d: ^Doc) {
	if d.modified {
		dialog_open(.Confirm_Close)
		return
	}
	doc_close_now(d)
}

doc_close_now :: proc(d: ^Doc) {
	tools_cancel()
	for x, i in docs {
		if x == d {
			ordered_remove(&docs, i)
			break
		}
	}
	if len(docs) == 0 {
		add_doc(doc_new(.Svg, "Untitled", 1024, 768))
	} else if doc == d {
		doc = docs[len(docs) - 1]
	}
	render_invalidate()
}

// Editing commands ---------------------------------------------------------------------------------------------

cmd_delete :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	for n in nodes {
		if p := node_parent(d.root, n); p != nil {
			if i := node_index(p, n); i >= 0 do ordered_remove(&p.children, i)
		}
		node_free(n)
	}
	clear(&d.sel)
	doc_changed(d)
}

cmd_copy :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	for n in clip_nodes do node_free(n)
	clear(&clip_nodes)
	for n in nodes {
		c := node_clone(n)
		// keep the world position so pasting in place works regardless of nesting
		c.xf = mat_mul(node_parent_world(d, n), n.xf)
		append(&clip_nodes, c)
	}
	// publish as SVG for other applications
	tmp := doc_new(.Svg, "clip", d.w, d.h)
	defer doc_free(tmp)
	for n in clip_nodes do append(&tmp.root.children, node_clone(n))
	s := svg_string(tmp)
	gfx_clipboard_set(s)
	set_statusf("Copied %d object(s)", len(clip_nodes))
}

cmd_paste :: proc(d: ^Doc, in_place: bool) {
	history_push(d)
	clear(&d.sel)
	added := 0
	// prefer SVG text on the system clipboard (from another app or an earlier copy)
	txt := gfx_clipboard_get()
	if strings.contains(txt, "<svg") {
		if src, ok := svg_parse(txt); ok {
			defer doc_free(src)
			for c in src.root.children {
				n := node_clone(c)
				renumber(d, n)
				append(&d.root.children, n)
				append(&d.sel, n.uid)
				added += 1
			}
		}
	}
	if added == 0 {
		for c in clip_nodes {
			n := node_clone(c)
			renumber(d, n)
			append(&d.root.children, n)
			append(&d.sel, n.uid)
			added += 1
		}
	}
	if added == 0 {
		if len(d.undo) > 0 {
			s := pop(&d.undo)
			state_free(&s)
		}
		return
	}
	if !in_place {
		// nudge into the view centre
		b := sel_bounds(d)
		if !bounds_empty(b) {
			c := to_doc(d, {f32(view_vp.x + view_vp.w / 2), f32(view_vp.y + view_vp.h / 2)})
			bc := bounds_center(b)
			for n in sel_nodes(d) do node_translate(n, c.x - bc.x, c.y - bc.y)
		}
	}
	doc_changed(d)
}

// Gives a cloned subtree fresh ids.
renumber :: proc(d: ^Doc, n: ^Node) {
	d.next_uid += 1
	n.uid = d.next_uid
	for c in n.children do renumber(d, c)
}

doc_free :: proc(d: ^Doc) {
	node_free(d.root)
	for &s in d.undo do state_free(&s)
	for &s in d.redo do state_free(&s)
	delete(d.undo)
	delete(d.redo)
	delete(d.sel)
	free(d)
}

cmd_duplicate :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	clear(&d.sel)
	off := 10 / d.zoom
	for n in nodes {
		c := node_clone(n)
		renumber(d, c)
		node_translate(c, off, off)
		if p := node_parent(d.root, n); p != nil {
			i := node_index(p, n)
			inject_at_node(&p.children, i + 1, c)
		}
		append(&d.sel, c.uid)
	}
	doc_changed(d)
}

inject_at_node :: proc(a: ^[dynamic]^Node, i: int, n: ^Node) {
	append(a, nil)
	for k := len(a) - 1; k > i; k -= 1 do a[k] = a[k - 1]
	a[i] = n
}

cmd_group :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) < 1 do return
	history_push(d)
	// group siblings of the first node's parent only
	parent := node_parent(d.root, nodes[0])
	g := node_new(d, .Group)
	name_set(&g.name, "Group")
	top := 0
	moved := make([dynamic]^Node, context.temp_allocator)
	for n in nodes {
		if node_parent(d.root, n) != parent do continue
		append(&moved, n)
		top = max(top, node_index(parent, n))
	}
	for n in moved {
		i := node_index(parent, n)
		ordered_remove(&parent.children, i)
		if i < top do top -= 1
		append(&g.children, n)
	}
	inject_at_node(&parent.children, min(top + 1, len(parent.children)), g)
	sel_set(d, g)
	doc_changed(d)
}

cmd_ungroup :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	any_group := false
	for n in nodes do if n.kind == .Group do any_group = true
	if !any_group do return
	history_push(d)
	clear(&d.sel)
	for n in nodes {
		if n.kind != .Group {
			append(&d.sel, n.uid)
			continue
		}
		parent := node_parent(d.root, n)
		i := node_index(parent, n)
		ordered_remove(&parent.children, i)
		for c, k in n.children {
			c.xf = mat_mul(n.xf, c.xf)
			c.opacity *= n.opacity
			inject_at_node(&parent.children, i + k, c)
			append(&d.sel, c.uid)
		}
		clear(&n.children)
		node_free(n)
	}
	doc_changed(d)
}

cmd_order :: proc(d: ^Doc, delta: int) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	for n in nodes {
		p := node_parent(d.root, n)
		i := node_index(p, n)
		ni := clamp(i + delta, 0, len(p.children) - 1)
		if ni == i do continue
		ordered_remove(&p.children, i)
		inject_at_node(&p.children, ni, n)
	}
	doc_changed(d)
}

Xform_Kind :: enum {
	Flip_H,
	Flip_V,
	Rot_CW,
	Rot_CCW,
}

cmd_transform_sel :: proc(d: ^Doc, k: Xform_Kind) {
	if len(d.sel) == 0 do return
	history_push(d)
	sel_remember(d)
	c := bounds_center(tl.bbox)
	m: Mat
	switch k {
	case .Flip_H: m = mat_scale(-1, 1)
	case .Flip_V: m = mat_scale(1, -1)
	case .Rot_CW: m = mat_rotate(deg2rad(90))
	case .Rot_CCW: m = mat_rotate(deg2rad(-90))
	}
	m = mat_mul(mat_translate(c.x, c.y), mat_mul(m, mat_translate(-c.x, -c.y)))
	sel_apply(d, m)
	tl_reset()
}

cmd_align :: proc(d: ^Doc, c: Cmd) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	// one object aligns to the page, several align to their common bounds
	ref := Bounds{0, 0, d.w, d.h}
	if len(nodes) > 1 do ref = sel_bounds(d)
	for n in nodes {
		b := node_doc_bounds(d, n)
		if bounds_empty(b) do continue
		dx, dy: f32
		#partial switch c {
		case .Align_Left:   dx = ref.x0 - b.x0
		case .Align_Right:  dx = ref.x1 - b.x1
		case .Align_Center: dx = (ref.x0 + ref.x1) / 2 - (b.x0 + b.x1) / 2
		case .Align_Top:    dy = ref.y0 - b.y0
		case .Align_Bottom: dy = ref.y1 - b.y1
		case .Align_Middle: dy = (ref.y0 + ref.y1) / 2 - (b.y0 + b.y1) / 2
		}
		node_apply_world(d, n, n.xf, mat_translate(dx, dy))
	}
	doc_changed(d)
}

cmd_distribute :: proc(d: ^Doc, horizontal: bool) {
	nodes := sel_nodes(d)
	if len(nodes) < 3 do return
	history_push(d)
	// sort by centre
	order := make([dynamic]^Node, context.temp_allocator)
	append(&order, ..nodes)
	centre :: proc(d: ^Doc, n: ^Node, h: bool) -> f32 {
		b := node_doc_bounds(d, n)
		return h ? (b.x0 + b.x1) / 2 : (b.y0 + b.y1) / 2
	}
	for i in 0 ..< len(order) {
		for j in i + 1 ..< len(order) {
			if centre(d, order[j], horizontal) < centre(d, order[i], horizontal) do order[i], order[j] = order[j], order[i]
		}
	}
	first, last := centre(d, order[0], horizontal), centre(d, order[len(order) - 1], horizontal)
	for n, i in order {
		target := first + (last - first) * f32(i) / f32(len(order) - 1)
		delta := target - centre(d, n, horizontal)
		node_apply_world(d, n, n.xf, horizontal ? mat_translate(delta, 0) : mat_translate(0, delta))
	}
	doc_changed(d)
}

cmd_to_path :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	if len(nodes) == 0 do return
	history_push(d)
	for n in nodes {
		if n.kind == .Text do text_to_path(n)
		else do node_to_path(n)
	}
	doc_changed(d)
}

cmd_text_outlines :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	changed := false
	for n in nodes do if n.kind == .Text do changed = true
	if !changed do return
	history_push(d)
	for n in nodes do text_to_path(n)
	doc_changed(d)
}

cmd_fit_page :: proc(d: ^Doc) {
	b := BOUNDS_EMPTY
	for c in d.root.children {
		if c.visible do b = bounds_union(b, bounds_transform(node_visual_bounds(c), MAT_ID))
	}
	if bounds_empty(b) do return
	history_push(d)
	for c in d.root.children do node_translate(c, -b.x0, -b.y0)
	d.w, d.h = max(bounds_w(b), 1), max(bounds_h(b), 1)
	view_fit(d, view_vp)
	doc_changed(d)
}

cmd_reverse :: proc(d: ^Doc) {
	nodes := sel_nodes(d)
	history_push(d)
	for n in nodes {
		if n.kind == .Group do continue
		node_to_path(n)
		if n.kind == .Path do path_reverse(&n.segs)
	}
	doc_changed(d)
}
