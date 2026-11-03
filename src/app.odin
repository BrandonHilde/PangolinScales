package pangolin

import "core:fmt"
import "core:math"

import oui "odinui:odinui"

APP_VERSION :: "0.1"

want_quit: bool
canvas_mode := false // Tab: hide the side panels, tabs and status bar, leaving only the top bars

status_msg: Name
status_t: f32

set_status :: proc(s: string) {
	name_set(&status_msg, s)
	status_t = 4
}

set_statusf :: proc(format: string, args: ..any) {
	set_status(fmt.tprintf(format, ..args))
}

// Layout -------------------------------------------------------------------------------------------------
// The theme places the areas (#menubar, #options, #body, #toolbar, #viewport ...) and each panel builds or
// draws into the box it gets. Areas still drawn by hand are "slots" (see oui.odin).

panels_init :: proc() {
	oui_slot_register("logo", proc(r: Rect, _: int) {
		ui.layer = 0
		logo_draw(r.x, r.y + (r.h - LOGO_SIZE) / 2, 1)
		tip_area(r, "logo", {"Pangolin Scales", "An SVG and font editor. Help > About has the details."})
	})
	oui_slot_register("viewport", proc(r: Rect, _: int) {panel_viewport(r)})
	oui_slot_register("groups_bar", proc(r: Rect, _: int) {panel_groups_bar(r)})
	oui_slot_register("paint_chips", proc(r: Rect, _: int) {panel_paint_chips(r)})
	oui_slot_register("cursor_info", proc(r: Rect, _: int) {panel_cursor_info(r)})
	oui_slot_register("grid_size", proc(r: Rect, _: int) {
		ui.layer = 0
		v := int(grid_size)
		if field_int(r, &v, 1, 1000, {"Grid size", "Spacing of the grid in document units, used for showing it and for snapping. Type a value or use the mouse wheel."}) do grid_size = f32(v)
	})
	oui_slot_register("objects", proc(r: Rect, _: int) {panel_objects(r)})
	oui_slot_register("properties", proc(r: Rect, _: int) {panel_properties(r)})
	oui_slot_register("glyph_grid", proc(r: Rect, _: int) {panel_glyph_grid(doc, r)})
	oui_slot_register("font_props", proc(r: Rect, _: int) {panel_font_props(doc, r)})
}

main_ui :: proc() {
	oui.element(uictx, "window", "screen", {id = "window"})
	defer oui.end(uictx)
	panel_menubar()
	panel_options()
	if canvas_mode {
		oui_slot("viewport", "viewport")
		oui_slot("groups-bar", "groups_bar")
		return
	}
	oui.element(uictx, "body", "row", {id = "body"})
	panel_toolbar()
	oui.element(uictx, "center", "column", {id = "center"})
	panel_tabs()
	oui_slot("viewport", "viewport")
	oui.end(uictx)
	if doc.kind == .Font do panel_font()
	panel_right()
	oui.end(uictx)
	panel_status()
}

panel_viewport :: proc(vp: Rect) {
	// keep the drawing where it was on screen when the viewport changes size
	@(static) prev_mode := false
	@(static) prev_vp: Rect
	if canvas_mode != prev_mode && doc.view_init && prev_vp.w > 0 {
		doc.ox += f32(vp.x + vp.w / 2 - prev_vp.x - prev_vp.w / 2)
		doc.oy += f32(vp.y + vp.h / 2 - prev_vp.y - prev_vp.h / 2)
	}
	prev_mode, prev_vp = canvas_mode, vp
	if doc.kind == .Font {
		font_viewport(vp)
	} else {
		viewport_update(vp)
		render_viewport(doc, vp)
		trace_draw(doc, vp)
		overlay_draw(vp)
	}
}

// Menu bar -----------------------------------------------------------------------------------------------

MENU_TITLES_SVG := [?]string{"File", "Edit", "Object", "Path", "Text", "View", "Help"}
MENU_TITLES_FONT := [?]string{"File", "Edit", "Object", "Path", "Text", "Font", "View", "Help"}

menu_titles :: proc() -> []string {
	if doc != nil && doc.kind == .Font do return MENU_TITLES_FONT[:]
	return MENU_TITLES_SVG[:]
}

menu_build :: proc(idx: int) {
	item :: popup_item
	name := menu_titles()[idx]
	switch name {
	case "File":
		item("New SVG...", cmd = .New)
		item("New Font", cmd = .New_Font)
		item("Open...", cmd = .Open)
		popup_sep()
		item("Save", cmd = .Save)
		item("Save As...", cmd = .Save_As)
		if doc.kind == .Svg {
			item("Export PNG...", cmd = .Export_PNG)
		} else {
			item("Export TrueType...", cmd = .Font_Export)
		}
		popup_sep()
		item("Close", cmd = .Close_Doc)
		item("Quit", cmd = .Quit)
	case "Edit":
		item("Undo", cmd = .Undo)
		item("Redo", cmd = .Redo)
		popup_sep()
		item("Cut", cmd = .Cut)
		item("Copy", cmd = .Copy)
		item("Paste", cmd = .Paste)
		item("Paste in Place", cmd = .Paste_In_Place)
		item("Duplicate", cmd = .Duplicate)
		item("Delete", cmd = .Delete)
		popup_sep()
		item("Select All", cmd = .Select_All)
		item("Deselect", cmd = .Deselect)
	case "Object":
		item("Group", cmd = .Group)
		item("Ungroup", cmd = .Ungroup)
		popup_sep()
		item("Raise", cmd = .Raise)
		item("Lower", cmd = .Lower)
		item("To Front", cmd = .To_Front)
		item("To Back", cmd = .To_Back)
		popup_sep()
		item("Flip Horizontal", cmd = .Flip_H)
		item("Flip Vertical", cmd = .Flip_V)
		item("Rotate 90 CW", cmd = .Rotate_CW)
		item("Rotate 90 CCW", cmd = .Rotate_CCW)
		popup_sep()
		item("Align Left", cmd = .Align_Left)
		item("Align Center", cmd = .Align_Center)
		item("Align Right", cmd = .Align_Right)
		item("Align Top", cmd = .Align_Top)
		item("Align Middle", cmd = .Align_Middle)
		item("Align Bottom", cmd = .Align_Bottom)
		item("Distribute Horizontally", cmd = .Distribute_H)
		item("Distribute Vertically", cmd = .Distribute_V)
		if doc.kind == .Svg {
			// a glyph's page is its advance width and the em, set in the font panel
			popup_sep()
			item("Page Size...", cmd = .Page_Size)
			item("Fit Page to Content", cmd = .Fit_Page_To_Content)
		}
	case "Path":
		item("Object to Path", cmd = .Object_To_Path)
		item("Stroke to Path", cmd = .Stroke_To_Path)
		popup_sep()
		item("Union", cmd = .Union)
		item("Subtract", cmd = .Subtract)
		item("Intersect", cmd = .Intersect)
		item("Exclude", cmd = .Exclude)
		item("Close Open Paths", cmd = .Toggle_Close_Paths, checked = close_open_paths)
		popup_sep()
		item("Combine", cmd = .Combine)
		item("Break Apart", cmd = .Break_Apart)
		item("Reverse Direction", cmd = .Reverse)
		popup_sep()
		item("Simplify", cmd = .Simplify)
		item("Offset Outward", cmd = .Offset_Out)
		item("Offset Inward", cmd = .Offset_In)
	case "Text":
		item("Convert to Outlines", cmd = .Text_To_Outlines)
	case "Font":
		item("Add Glyphs...", cmd = .Font_Add_Glyphs)
		item("Fix Contour Direction", cmd = .Font_Fix_Direction)
		item("Remove Overlap (glyph)", cmd = .Font_Remove_Overlap)
		item("Previous Glyph", cmd = .Font_Prev_Glyph)
		item("Next Glyph", cmd = .Font_Next_Glyph)
		popup_sep()
		item("Export TrueType...", cmd = .Font_Export)
	case "View":
		item("Zoom In", cmd = .Zoom_In)
		item("Zoom Out", cmd = .Zoom_Out)
		item("Fit", cmd = .Fit_View)
		item("Actual Size", cmd = .Actual_Size)
		popup_sep()
		item("Grid", cmd = .Toggle_Grid, checked = show_grid)
		item("Snap to Grid", cmd = .Toggle_Snap, checked = snap_grid)
		item("Canvas Mode", cmd = .Toggle_Canvas_Mode, checked = canvas_mode)
		popup_sep()
		item("Load Tracing Image...", cmd = .Trace_Load)
		item("Tracing Image More Visible", cmd = .Trace_More)
		item("Tracing Image Less Visible", cmd = .Trace_Less)
		item("Clear Tracing Image", cmd = .Trace_Clear)
		popup_sep()
		item("Reset Tool Groups", cmd = .Reset_Tool_Groups)
	case "Help":
		item("Keyboard Shortcuts", cmd = .Shortcuts)
		item("About", cmd = .About)
	}
}

menu_request := -1 // a menu to open (--menu)

panel_menubar :: proc() {
	bar := oui.element(uictx, "menubar", "menubar", {id = "menubar"})
	defer oui.end(uictx)
	oui_slot("logo", "logo")
	menu_open := popup.open && popup.menu_idx >= 0
	for title, i in menu_titles() {
		is_open := menu_open && popup.menu_idx == i
		n := oui.button_begin(uictx, title, {class = is_open ? "menu-title open" : "menu-title"})
		oui.label(uictx, "t", title)
		oui.end(uictx)
		oui_tip(n, menu_title_tip(title))
		// menus drop from the bottom of the bar
		r := oui_rect(n)
		br := oui_rect(bar)
		anchor := Rect{r.x, br.y, r.w, br.h - 1}
		id := make_id(anchor, title)
		if n.pressed || menu_request == i {
			menu_request = -1
			popup_begin(id, anchor, 0, i)
			menu_build(i)
		} else if menu_open && ui.input_layer < 2 && in_rect(anchor, ui.mx, ui.my) {
			// while a menu is open the bar takes no clicks: moving along it switches menus,
			// clicking the open one's title closes it
			if ui.pressed[0] && is_open {
				popup_close()
			} else if !is_open {
				popup_begin(id, anchor, 0, i)
				menu_build(i)
			}
		}
	}
	oui.element_leaf(uictx, "spacer", "spacer")
	if c, _ := oui_icon_button("grid", .Grid, cmd_tip("Grid", .Toggle_Grid), {lit = show_grid, enabled = true}); c {
		run_cmd(.Toggle_Grid)
	}
	if c, _ := oui_icon_button("canvas-mode", .Canvas_Mode, cmd_tip("Canvas mode", .Toggle_Canvas_Mode), {lit = canvas_mode, enabled = true}); c {
		run_cmd(.Toggle_Canvas_Mode)
	}
	oui_tip(oui.label(uictx, "doc", doc_display_name(doc), {id = "doc-name"}), {"Current document", doc_status(doc)})
}

// Tabs ---------------------------------------------------------------------------------------------------

panel_tabs :: proc() {
	oui.element(uictx, "tabs", "tabbar", {id = "tabs"})
	defer oui.end(uictx)
	close_doc: ^Doc
	switch_to: ^Doc
	for d in docs {
		active := d == doc
		t := oui.button_begin(uictx, fmt.tprintf("tab%x", uintptr(d)), {class = active ? "tab active" : "tab"})
		oui_tip(t, {doc_display_name(d), fmt.tprintf("%s Click to switch to it, middle-click to close it.", doc_status(d))})
		if active do oui.element_leaf(uictx, "accent", "tab-accent")
		oui.label(uictx, "name", doc_display_name(d))
		if c, _ := oui_icon_button("close", .Close, {"Close document", "Close this document. If it has unsaved changes you are asked first."}, {class = "tab-close", enabled = true}); c {
			close_doc = d
		}
		oui.end(uictx)
		if t.pressed do switch_to = d // a press on the tab itself, not its close button
		if t.hovered && ui.pressed[2] do close_doc = d
	}
	if c, _ := oui_icon_button("new", .Plus, cmd_tip("New SVG", .New), {id = "new-tab", enabled = true}); c {
		run_cmd(.New)
	}
	if close_doc != nil {
		doc = close_doc
		doc_close(close_doc)
	} else if switch_to != nil && switch_to != doc {
		tools_cancel()
		doc = switch_to
		render_invalidate()
	}
}

// Toolbar: tool groups -----------------------------------------------------------------------------------

panel_toolbar :: proc() {
	oui.element(uictx, "toolbar", "toolbar", {id = "toolbar"})
	defer oui.end(uictx)
	rem_g, rem_t, rem_o := -1, -1, -1
	OP_ITEM :: 1000 // popup values of path operations: OP_ITEM + index into PATH_OPS
	cg := current_group()
	for &g, gi in tool_groups {
		oui.element(uictx, fmt.tprintf("g%d", gi), "tool-group")
		// header: the name on the left, the hotkey as a keycap on the right
		// (click the keycap for options; right-click the header for rename / remove)
		hdr := oui.element(uictx, "head", "group-head")
		oui_tip(hdr, {group_title(&g), "A tool group: tools and path operations kept together. Right-click to rename or remove it."})
		oui.label(uictx, "title", group_title(&g), {class = "group-title"})
		waiting := group_key_wait == gi
		label := waiting ? "..." : (g.key == .KEY_NULL ? "-" : key_name(g.key))
		kc := oui.button_begin(uictx, "key", {class = label == "-" ? "keycap none" : "keycap", checked = waiting})
		oui.label(uictx, "t", label)
		oui.end(uictx)
		oui_tip(kc, {"Group hotkey", "Press this key to pick the group's last tool, and again to step through its tools. A group with only operations repeats the last one. Click to change the key, rename or remove the group."})
		oui.end(uictx)
		bid := make_id({}, fmt.tprintf("grpbadge%d", gi))
		if kc.clicked {
			popup_begin(bid, oui_rect(kc), 120)
			popup_item("Assign hotkey...", 0, tip = "Choose the key for this group: press a letter or digit next. Esc cancels, Backspace removes the hotkey.")
			popup_item("Rename...", 3, tip = "Give this tool group a different name.")
			popup_item("Remove group", 1, tip = "Remove this tool group from the toolbar. Its tools stay available from their shortcuts and other groups.")
		}
		if ui.popup_result_id == bid {
			switch ui.popup_result_val {
			case 0:
				group_key_wait = gi
				set_status("Press a letter or digit for this tool group (Esc cancels, Backspace clears)")
			case 3:
				group_rename_open(gi)
			case:
				rem_g = gi
			}
			ui.popup_result_id = 0
		}
		// right-click anywhere on the header for a menu (opened on release,
		// since a popup opened on the press would be closed by that same click)
		hid := make_id({}, fmt.tprintf("grphdr%d", gi))
		if hdr.hovered && ui.released[1] && !popup.open {
			popup_begin(hid, Rect{ui.mx, ui.my, 1, 1}, 110)
			popup_item("Rename...", 3, tip = "Give this tool group a different name.")
			popup_item("Remove group", 1, tip = "Remove this tool group from the toolbar. Its tools stay available from their shortcuts and other groups.")
		}
		if ui.popup_result_id == hid {
			if ui.popup_result_val == 3 do group_rename_open(gi)
			else do rem_g = gi
			ui.popup_result_id = 0
		}
		oui.element(uictx, "items", "group-items")
		for tool, ti in g.tools {
			lit := cur_tool == tool && cg == gi
			clicked, bn := oui_icon_button(fmt.tprintf("t%d", int(tool)), TOOL_ICONS[tool], tool_tip(tool), {class = "tool", lit = lit, enabled = true, icon_lg = true})
			if clicked {
				select_tool_in_group(tool, gi)
			} else if bn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, ti
			}
		}
		for c, oi in g.ops {
			op, _ := path_op(c)
			clicked, bn := oui_icon_button(fmt.tprintf("o%d", int(c)), op.icon, cmd_tip(op.name, c), {class = "tool op", lit = c == .Toggle_Close_Paths && close_open_paths, enabled = path_op_enabled(op), icon_lg = true})
			if clicked {
				group_run_op(gi, c)
			} else if bn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_o = gi, oi
			}
		}
		if len(g.tools) < len(Tool) || len(g.ops) < len(PATH_OPS) {
			pid := make_id({}, fmt.tprintf("grpadd%d", gi))
			add_clicked, add_node := oui_icon_button("add", .Plus, {"Add to group", "Add a tool or path operation to this group. To take one out again, right-click its button."}, {class = "tool quiet", enabled = true, icon_lg = true})
			if add_clicked {
				popup_begin(pid, oui_rect(add_node))
				popup_grid(4)
				for tool in Tool {
					if !tool_group_has(&g, tool) do popup_item_icon(TOOL_NAMES[tool], int(tool), TOOL_ICONS[tool], TOOL_HELP[tool])
				}
				if len(g.ops) < len(PATH_OPS) {
					popup_sep()
					for op, i in PATH_OPS {
						if !group_has_op(&g, op.cmd) do popup_item_icon(path_op_tip(op), OP_ITEM + i, op.icon, cmd_help(op.cmd))
					}
				}
			}
			if ui.popup_result_id == pid {
				v := ui.popup_result_val
				if v >= OP_ITEM {
					append(&g.ops, PATH_OPS[v - OP_ITEM].cmd)
					if len(g.ops) == 1 do g.last_op = g.ops[0]
				} else {
					append(&g.tools, Tool(v))
					if len(g.tools) == 1 do g.last = Tool(v)
				}
				ui.popup_result_id = 0
			}
		}
		oui.end(uictx) // items
		oui.end(uictx) // group
	}
	if rem_g >= 0 {
		if rem_t >= 0 {
			ordered_remove(&tool_groups[rem_g].tools, rem_t)
		} else if rem_o >= 0 {
			ordered_remove(&tool_groups[rem_g].ops, rem_o)
		} else {
			active_group = -1 // indices shift
			delete(tool_groups[rem_g].tools)
			delete(tool_groups[rem_g].ops)
			ordered_remove(&tool_groups, rem_g)
			group_key_wait = -1
		}
	}
	if len(tool_groups) < MAX_TOOL_GROUPS {
		if obutton("+ New Group", 0, {"New group", "Add an empty tool group to the toolbar, then use its + button to fill it. You can have up to 12 groups."}, id = "new-group") {
			append(&tool_groups, Tool_Group{})
		}
	}
	oui.separator(uictx, "chips-sep")
	oui_slot("paint-chips", "paint_chips")
}

// Fill and stroke chips below the tool groups: the selection's paints (or the drawing defaults).
// Clicking one makes it the paint the properties panel edits.
panel_paint_chips :: proc(r: Rect) {
	ui.layer = 0
	d := doc
	sel := first_selected(d)
	fill := sel != nil ? sel.fill : cur_fill
	stroke := sel != nil ? sel.stroke : cur_stroke
	fr := Rect{r.x, r.y, 24, 24}
	sr := Rect{r.x + 13, r.y + 14, 24, 24}
	// stroke behind, drawn as a thick ring
	draw_paint_swatch(sr, stroke)
	inner := Rect{sr.x + 6, sr.y + 6, sr.w - 12, sr.h - 12}
	fill_rect(inner, C_PANEL)
	outline_rect(inner, C_RING_HI)
	if prop_target == 1 do outline_rect(sr, WHITE)
	draw_shadow(f32(fr.x), f32(fr.y + 1), 24, 24, 2, 5, Color{0, 0, 0, 140})
	draw_paint_swatch(fr, fill)
	if prop_target == 0 do outline_rect(fr, WHITE)
	pick := -1
	if ui_hover(fr) {
		tooltip_hover(make_id(fr, "fillchip"), {"Fill", "The selected object's inside colour, or the one new shapes get when nothing is selected. Click to edit it in Properties."})
		if ui.pressed[0] do pick = 0
	} else if ui_hover(sr) {
		tooltip_hover(make_id(sr, "strokechip"), {"Stroke", "The selected object's outline colour, or the one new shapes get when nothing is selected. Click to edit it in Properties."})
		if ui.pressed[0] do pick = 1
	}
	if pick >= 0 && pick != prop_target {
		prop_target = pick
		grad_stop = 0
	}
}

// Options bar --------------------------------------------------------------------------------------------

panel_options :: proc() {
	oui.element(uictx, "options", "optionsbar", {id = "options"})
	defer oui.end(uictx)
	oicon("tool-icon", TOOL_ICONS[cur_tool], "tool-icon", tool_tip(cur_tool))
	otext("tool-name", TOOL_NAMES[cur_tool], "tool-name", tool_tip(cur_tool))
	#partial switch cur_tool {
	case .Freehand:
		v := int(smoothing * 10)
		if oslider("Smoothing", 120, &v, 5, 200, {"Smoothing", "How far the fitted curves may stray from your stroke, in screen pixels. Higher is smoother with fewer points, lower follows your hand more closely."}, "", 1, 10) do smoothing = f32(v) / 10
		options_grid()
		ohint("Drag to draw; the stroke is fitted with smooth curves")
	case .Text:
		options_text()
	case .Select:
		options_grid()
		ohint("Drag to move, handles scale, outside the corners rotates. Shift: keep proportions")
	case .Node:
		options_grid()
		oui.element(uictx, "node-cmds", "button-group")
		if obutton("Smooth", 50, {"Smooth (S)", "Give the selected points control points in line with each other, so the path curves through them."}) do node_cmd_smooth(doc)
		if obutton("Corner", 50, {"Corner (C)", "Pull the selected points' control points back onto them, making a sharp corner."}) do node_cmd_corner(doc)
		if obutton("Delete", 50, {"Delete (Del)", "Remove the selected points. The path joins up across the gap."}) do node_cmd_delete(doc)
		oui.end(uictx)
		ohint("Double click a segment to add a node. Alt breaks handle symmetry")
	case .Control:
		options_grid()
		ohint("Drag a control point. Where they overlap, click to step through them. Arrows nudge. Alt breaks symmetry")
	case .Pen:
		options_grid()
		ohint("Click: straight line   Drag: curve   First point: click to close straight, drag to close curved   Enter finishes")
	case .Rect, .Ellipse, .Line:
		options_grid()
		ohint("Shift: square / 15 degree steps   Alt: from the centre")
	case .Picker:
		ohint("Click an object to take its fill, Alt-click to take its stroke")
	case .Hand:
		ohint("Drag to pan. Space or middle mouse works with any tool")
	case .Zoom:
		ohint("Click to zoom in, Alt or Shift click to zoom out. The wheel zooms anywhere")
	}
	oui.element_leaf(uictx, "spacer", "spacer")
}

options_grid :: proc() {
	ocheck("Grid", &show_grid, cmd_tip("Grid", .Toggle_Grid))
	ocheck("Snap", &snap_grid, cmd_tip("Snap", .Toggle_Snap))
	otext("grid-l", "Size", "dim", {"Grid size", "Spacing of the grid in document units, used for showing it and for snapping."})
	oui_slot("grid-size", "grid_size")
}

// Status bar ---------------------------------------------------------------------------------------------

panel_status :: proc() {
	d := doc
	oui.element(uictx, "status", "statusbar", {id = "status"})
	defer oui.end(uictx)
	msg: ^oui.Node
	if status_t > 0 {
		msg = oui.label(uictx, "msg", name_str(&status_msg), {id = "status-msg", class = "message"})
	} else {
		msg = oui.label(uictx, "msg", APP_TAGLINE, {id = "status-msg"})
	}
	oui_tip(msg, {"Messages", "Messages from the program appear here, such as why an action could not be done."})
	oui.separator(uictx, "sep0")
	// the readout under the pointer changes every frame, so it is drawn by hand
	oui_slot("cursor-info", "cursor_info")
	if len(d.sel) > 0 {
		oui.separator(uictx, "sep1")
		oui_tip(oui.label(uictx, "sel", fmt.tprintf("%d selected", len(d.sel))), {"Selection", "How many objects are selected. Ctrl+Shift+A clears the selection."})
	}
	oui.element_leaf(uictx, "spacer", "spacer")
	if s := pen_status(); s != "" {
		oui_tip(oui.label(uictx, "pen", s), {"Tablet pen", "A drawing tablet pen has been detected. This shows whether it is close enough to the tablet to be read."})
		oui.separator(uictx, "sep2")
	}
	oui_tip(oui.label(uictx, "size", fmt.tprintf("%d x %d", int(math.round(d.w)), int(math.round(d.h)))), {"Page size", "Width by height. Change it with Object > Page Size."})
	oui.separator(uictx, "sep3")
	oui_tip(oui.label(uictx, "zoom", fmt.tprintf("%d%%", int(math.round(d.zoom * 100))), {class = "strong"}), {"Zoom", "Use the mouse wheel to zoom, Ctrl+0 to fit the page and Ctrl+1 for 100%."})
}

// Pointer position in document units (font units, y up, for a glyph), in the status bar.
panel_cursor_info :: proc(r: Rect) {
	d := doc
	ui.layer = 0
	tip_area(r, "cursor-info", {"Pointer position", d.kind == .Font ? "In font units: x, then y upwards from the baseline." : "On the page: x, then y, in document units from the top left corner."})
	p := to_doc(d, pointer())
	if d.kind == .Font do p.y = d.font.em_top - p.y
	text(r.x, r.y + (r.h - FONT_CAP) / 2, fmt.tprintf("%d, %d", int(p.x), int(p.y)), C_TEXT)
}
