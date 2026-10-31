package pangolin

import "core:fmt"
import "core:math"

APP_VERSION :: "0.1"

MENU_H :: 24
OPT_H :: 30
TAB_H :: 26
STATUS_H :: 20
TOOLBAR_W :: 52
RIGHT_W :: 236

want_quit: bool

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

main_ui :: proc() {
	W, H := i32(ui.w), i32(ui.h)
	fill_rect(Rect{0, 0, W, H}, C_BG)

	menubar := Rect{0, 0, W, MENU_H}
	optbar := Rect{0, MENU_H, W, OPT_H}
	status := Rect{0, H - STATUS_H, W, STATUS_H}
	body := Rect{0, MENU_H + OPT_H, W, H - MENU_H - OPT_H - STATUS_H}
	right := cut_right(&body, RIGHT_W)
	toolbar := cut_left(&body, TOOLBAR_W)
	tabs := cut_top(&body, TAB_H)

	if doc.kind == .Font {
		font_viewport(body)
	} else {
		viewport_update(body)
		render_viewport(doc, body)
		trace_draw(doc, body)
		overlay_draw(body)
	}

	panel_tabs(tabs)
	panel_toolbar(toolbar)
	if doc.kind == .Font do panel_right_font(right)
	else do panel_right(right)
	panel_status(status)
	panel_options(optbar)
	panel_menubar(menubar)
}

// Menu bar -----------------------------------------------------------------------------------------------

MENU_TITLES_SVG := [?]string{"File", "Edit", "Object", "Path", "Text", "View", "Help"}
MENU_TITLES_FONT := [?]string{"File", "Edit", "Font", "View", "Help"}

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
		popup_sep()
		item("Page Size...", cmd = .Page_Size)
		item("Fit Page to Content", cmd = .Fit_Page_To_Content)
	case "Path":
		item("Object to Path", cmd = .Object_To_Path)
		item("Stroke to Path", cmd = .Stroke_To_Path)
		popup_sep()
		item("Union", cmd = .Union)
		item("Subtract", cmd = .Subtract)
		item("Intersect", cmd = .Intersect)
		item("Exclude", cmd = .Exclude)
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
		popup_sep()
		item("Load Tracing Image...", cmd = .Trace_Load)
		item("Tracing Image More Visible", cmd = .Trace_More)
		item("Tracing Image Less Visible", cmd = .Trace_Less)
		item("Clear Tracing Image", cmd = .Trace_Clear)
	case "Help":
		item("Keyboard Shortcuts", cmd = .Shortcuts)
		item("About", cmd = .About)
	}
}

panel_menubar :: proc(r: Rect) {
	// The menubar stays interactive while a menu is open, but not under dialogs.
	ui.layer = ui.input_layer < 2 ? ui.input_layer : -1
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	logo_draw(r.x + 7, r.y + (r.h - LOGO_SIZE) / 2, 1)
	x := r.x + 30
	for title, i in menu_titles() {
		w := text_w(title) + 18
		br := Rect{x, r.y, w, r.h - 1}
		id := make_id(br, title)
		hover := ui_hover(br)
		is_open := popup.open && popup.menu_idx == i
		if hover || is_open {
			pill := Rect{br.x + 1, br.y + 3, br.w - 2, br.h - 6}
			draw_rrect(f32(pill.x), f32(pill.y), f32(pill.w), f32(pill.h), RADIUS, is_open ? C_ACTIVE : C_HOVER)
		}
		text(br.x + 9, br.y + (br.h - FONT_CAP) / 2, title, hover || is_open ? WHITE : C_TEXT)
		if hover {
			if ui.pressed[0] {
				if is_open {
					popup_close()
				} else {
					popup_begin(id, br, 0, i)
					menu_build(i)
				}
			} else if popup.open && popup.menu_idx >= 0 && popup.menu_idx != i {
				popup_begin(id, br, 0, i)
				menu_build(i)
			}
		}
		x += w
	}
	t := doc_display_name(doc)
	text(r.x + r.w - text_w(t) - 12, r.y + (r.h - 1 - FONT_CAP) / 2, t, C_TEXT_DIM)
}

// Tabs ---------------------------------------------------------------------------------------------------

panel_tabs :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 6
	clip_begin(r)
	close_doc: ^Doc
	switch_to: ^Doc
	for d in docs {
		name := doc_display_name(d)
		w := text_w(name) + 40
		tr := Rect{x, r.y + 4, w, r.h - 4}
		active := d == doc
		hover := ui_hover(tr)
		fill := active ? C_PANEL : (hover ? C_HOVER : C_PANEL_LT)
		draw_rrect(f32(tr.x), f32(tr.y), f32(tr.w), f32(tr.h + 6), RADIUS, fill)
		if active do fill_rect(Rect{tr.x + 3, tr.y, tr.w - 6, 2}, C_ACCENT)
		text(tr.x + 12, tr.y + (tr.h - FONT_CAP) / 2 + 1, name, active ? WHITE : C_TEXT_DIM)
		cr := Rect{tr.x + tr.w - 20, tr.y + 3, 14, 14}
		if icon_button(cr, .Close, "Close") do close_doc = d
		else if hover && ui.pressed[0] && !in_rect(cr, ui.mx, ui.my) do switch_to = d
		x += w + 3
	}
	clip_end()
	if switch_to != nil && switch_to != doc {
		tools_cancel()
		doc = switch_to
		render_invalidate()
	}
	if close_doc != nil {
		doc = close_doc
		doc_close(close_doc)
	}
}

// Toolbar ------------------------------------------------------------------------------------------------

panel_toolbar :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	vline(r.x + r.w - 1, r.y, r.h, C_BORDER)
	cell :: 22
	cols := max(int(r.w - 6) / (cell + 2), 1)
	for t, i in Tool {
		if doc.kind == .Font && (t == .Text || t == .Picker) do continue
		bx := r.x + 4 + i32(i % cols) * (cell + 2)
		by := r.y + 6 + i32(i / cols) * (cell + 2)
		if icon_button(Rect{bx, by, cell, cell}, TOOL_ICONS[t], TOOL_NAMES[t], cur_tool == t) {
			set_tool(t)
		}
	}
}

// Options bar and status ---------------------------------------------------------------------------------

panel_options :: proc(r: Rect) {
	ui.layer = ui.input_layer < 2 ? 0 : -1
	fill_rect(r, C_PANEL)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	ty := r.y + (r.h - FONT_CAP) / 2
	text(r.x + 10, ty, TOOL_NAMES[cur_tool], C_TEXT)
	x := r.x + 190
	#partial switch cur_tool {
	case .Freehand:
		text(x, ty, "Smoothing", C_TEXT_DIM)
		v := int(smoothing * 10)
		if slider(Rect{x + 70, r.y + 8, 110, 14}, &v, 5, 200, "", "", "", 1, 10) do smoothing = f32(v) / 10
	case .Text:
		text(x, ty, "Size", C_TEXT_DIM)
		v := int(cur_text_size)
		if field_int(Rect{x + 30, r.y + 8, 46, 14}, &v, 1, 2000) {
			cur_text_size = f32(v)
			if tl.text_uid != 0 {
				if n := node_find(doc.root, tl.text_uid); n != nil {
					n.size = cur_text_size
					doc_changed(doc)
				}
			}
		}
		font_picker(Rect{x + 90, r.y + 8, 170, 14})
	case .Select, .Node, .Pen, .Rect, .Ellipse, .Line:
		checkbox(x, ty - 2, "Grid", &show_grid)
		checkbox(x + 56, ty - 2, "Snap", &snap_grid)
		text(x + 116, ty, "Size", C_TEXT_DIM)
		v := int(grid_size)
		if field_int(Rect{x + 146, r.y + 8, 46, 14}, &v, 1, 1000) do grid_size = f32(v)
	}
	if cur_tool == .Node {
		bx := x + 210
		if button(Rect{bx, r.y + 8, 50, 14}, "Smooth", "Make selected nodes smooth (S)") do node_cmd_smooth(doc)
		if button(Rect{bx + 54, r.y + 8, 50, 14}, "Corner", "Make selected nodes corner (C)") do node_cmd_corner(doc)
		if button(Rect{bx + 108, r.y + 8, 50, 14}, "Delete", "Delete selected nodes (Del)") do node_cmd_delete(doc)
	}
}

// Prev / next buttons and a name field choosing the font of new / edited text.
font_picker :: proc(r: Rect) {
	fonts_scan()
	cur := 0
	nm := cur_font.n > 0 ? name_str(&cur_font) : DEFAULT_FONT
	for f, i in ufonts {
		if f.name == nm do cur = i
	}
	step := 0
	if icon_button(Rect{r.x, r.y, 16, r.h}, .Left, "Previous font") do step = -1
	if icon_button(Rect{r.x + r.w - 16, r.y, 16, r.h}, .Right, "Next font") do step = 1
	ctl_well(Rect{r.x + 18, r.y, r.w - 36, r.h})
	text_clipped(Rect{r.x + 22, r.y + (r.h - FONT_CAP) / 2, r.w - 44, FONT_CAP + 2}, nm, C_TEXT)
	if ui_hover(r) && ui.wheel != 0 do step = ui.wheel > 0 ? -1 : 1
	if step != 0 {
		ni := clamp(cur + step, 0, len(ufonts) - 1)
		cur_font = make_name(ufonts[ni].name)
		if tl.text_uid != 0 {
			if n := node_find(doc.root, tl.text_uid); n != nil {
				n.font = cur_font
				doc_changed(doc)
			}
		}
	}
}

panel_status :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y, r.w, C_BORDER)
	ty := r.y + (r.h - FONT_CAP) / 2
	if status_t > 0 {
		text(r.x + 10, ty, name_str(&status_msg), C_TEXT)
	} else {
		text(r.x + 10, ty, APP_TAGLINE, C_TEXT_DIM)
	}
	if doc != nil {
		z := fmt.tprintf("%d%%", int(math.round(doc.zoom * 100)))
		x := r.x + r.w - text_w(z) - 10
		text(x, ty, z, C_TEXT_DIM)
		if doc.kind == .Svg {
			p := to_doc(doc, pointer())
			s := fmt.tprintf("%d, %d", int(p.x), int(p.y))
			text(x - text_w(s) - 24, ty, s, C_TEXT_DIM)
		}
	}
	if s := pen_status(); s != "" do text(r.x + r.w / 2, ty, s, C_TEXT_DIM)
}
