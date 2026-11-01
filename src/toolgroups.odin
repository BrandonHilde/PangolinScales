package pangolin

import "core:fmt"
import "core:strconv"
import "core:strings"

// User-editable tool groups shown in the left toolbar. A group's hotkey selects its first tool
// (or the one last used from it); pressing it again cycles through the group's tools.
// The single-key tool shortcuts (V, P, R ...) keep working; a group hotkey on the same key wins.
// Groups can also hold path operations (union, offset ...): buttons that act on the selection at once.
// The hotkey of a group with operations but no tools runs the operation last used from it.

MAX_TOOL_GROUPS :: 12

Tool_Group :: struct {
	key:   KeyboardKey, // KEY_NULL: no hotkey
	tools: [dynamic]Tool,
	last:  Tool, // last tool picked from this group
	ops:   [dynamic]Cmd, // path operations (from PATH_OPS)
	last_op: Cmd, // last operation run from this group
	name:  Name, // empty: "Group"
}

// Path operations a group can hold, with the selection size they need.
Path_Op :: struct {
	cmd:     Cmd,
	icon:    Icon,
	name:    string,
	min_sel: int,
}

PATH_OPS := [?]Path_Op {
	{.Union, .Union, "Union", 2},
	{.Subtract, .Subtract, "Subtract", 2},
	{.Intersect, .Intersect, "Intersect", 2},
	{.Exclude, .Exclude, "Exclude", 2},
	{.Combine, .Combine, "Combine", 2},
	{.Break_Apart, .Break_Apart, "Break Apart", 1},
	{.Reverse, .Reverse, "Reverse Direction", 1},
	{.Simplify, .Simplify, "Simplify", 1},
	{.Offset_Out, .Offset_Out, "Offset Outward", 1},
	{.Offset_In, .Offset_In, "Offset Inward", 1},
	{.Object_To_Path, .To_Path, "Object to Path", 1},
	{.Stroke_To_Path, .Stroke_Path, "Stroke to Path", 1},
}

path_op :: proc(c: Cmd) -> (Path_Op, bool) {
	for op in PATH_OPS do if op.cmd == c do return op, true
	return {}, false
}

// Button tooltip: the name and the shortcut, if it has one.
path_op_tip :: proc(op: Path_Op) -> string {
	sc := shortcut_text(op.cmd)
	return sc == "" ? op.name : fmt.tprintf("%s (%s)", op.name, sc)
}

path_op_enabled :: proc(op: Path_Op) -> bool {
	return doc != nil && len(doc.sel) >= op.min_sel
}

// Runs a group's operation and remembers it for the group's hotkey.
group_run_op :: proc(gi: int, c: Cmd) {
	tool_groups[gi].last_op = c
	run_cmd(c)
}

group_has_op :: proc(g: ^Tool_Group, c: Cmd) -> bool {
	for x in g.ops do if x == c do return true
	return false
}

tool_groups: [dynamic]Tool_Group
active_group := -1 // group the current tool was last picked from, or -1
group_key_wait := -1 // group waiting for a hotkey press, or -1

// Tools the current document can use (font glyphs have no text objects or colours to pick).
tool_available :: proc(t: Tool) -> bool {
	if doc != nil && doc.kind == .Font do return t != .Text && t != .Picker
	return true
}

tool_group_has :: proc(g: ^Tool_Group, t: Tool) -> bool {
	for x in g.tools {
		if x == t do return true
	}
	return false
}

// Whether the group shows in the toolbar: it is empty (so tools can be added), holds operations or a usable tool.
group_visible :: proc(g: ^Tool_Group) -> bool {
	if len(g.tools) == 0 || len(g.ops) > 0 do return true
	for t in g.tools {
		if tool_available(t) do return true
	}
	return false
}

group_title :: proc(g: ^Tool_Group) -> string {
	return g.name.n > 0 ? name_str(&g.name) : "Group"
}

// Group names go into the preferences file, whose fields are split on : and ;
group_clean_name :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.trim_space(s) {
		if r != ':' && r != ';' && r >= ' ' do strings.write_rune(&sb, r)
	}
	return strings.trim_space(strings.to_string(sb))
}

// Group the current tool belongs to: the active group if it holds the tool, else the first that does.
current_group :: proc() -> int {
	if active_group >= 0 && active_group < len(tool_groups) && tool_group_has(&tool_groups[active_group], cur_tool) {
		return active_group
	}
	for &g, i in tool_groups {
		if tool_group_has(&g, cur_tool) do return i
	}
	return -1
}

// Picks `t` as a member of group `gi`.
select_tool_in_group :: proc(t: Tool, gi: int) {
	active_group = gi
	if gi >= 0 && gi < len(tool_groups) do tool_groups[gi].last = t
	set_tool(t)
}

tool_groups_clear :: proc() {
	active_group = -1
	group_key_wait = -1
	for &g in tool_groups {
		delete(g.tools)
		delete(g.ops)
	}
	clear(&tool_groups)
}

tool_groups_default :: proc() {
	tool_groups_clear()
	add :: proc(name: string, key: KeyboardKey, tools: ..Tool) {
		g := Tool_Group {
			key  = key,
			last = tools[0],
			name = make_name(name),
		}
		append(&g.tools, ..tools)
		append(&tool_groups, g)
	}
	add("Select", .ONE, .Select, .Node)
	add("Draw", .TWO, .Pen, .Freehand, .Line)
	add("Shapes", .THREE, .Rect, .Ellipse)
	add("Text", .FOUR, .Text, .Picker)
	add("View", .FIVE, .Hand, .Zoom)
	path := Tool_Group {
		key     = .SIX,
		name    = make_name("Path"),
		last_op = .Union,
	}
	append(&path.ops, Cmd.Union, Cmd.Subtract, Cmd.Intersect, Cmd.Exclude, Cmd.Combine, Cmd.Break_Apart)
	append(&tool_groups, path)
}

// The group's hotkey: the first time it picks the group's last tool, then it steps through the group.
tool_group_activate :: proc(gi: int) {
	g := &tool_groups[gi]
	tools := make([dynamic]Tool, context.temp_allocator)
	for t in g.tools do if tool_available(t) do append(&tools, t)
	n := len(tools)
	if n == 0 {
		if len(g.ops) > 0 do group_run_op(gi, group_has_op(g, g.last_op) ? g.last_op : g.ops[0])
		return
	}
	if current_group() == gi {
		for t, i in tools {
			if t == cur_tool {
				select_tool_in_group(tools[(i + 1) % n], gi)
				return
			}
		}
	}
	pick := tools[0]
	for t in tools do if t == g.last do pick = t
	select_tool_in_group(pick, gi)
}

// Runs the hotkeys of all groups; returns true if one was handled.
tool_groups_hotkeys :: proc() -> bool {
	if ui.ctrl || ui.alt || ui.shift do return false
	for &g, i in tool_groups {
		if g.key != .KEY_NULL && IsKeyPressed(g.key) {
			tool_group_activate(i)
			return true
		}
	}
	return false
}

// While a group is waiting for a hotkey, swallows the next key press. Returns true while waiting.
tool_groups_key_capture :: proc() -> bool {
	if group_key_wait < 0 do return false
	if group_key_wait >= len(tool_groups) || IsKeyPressed(.ESCAPE) {
		group_key_wait = -1
		return true
	}
	assign :: proc(k: KeyboardKey) {
		for &o in tool_groups {
			if o.key == k do o.key = .KEY_NULL
		}
		tool_groups[group_key_wait].key = k
		group_key_wait = -1
		set_status(k == .KEY_NULL ? "Group hotkey cleared" : fmt.tprintf("Group hotkey: %s", key_name(k)))
	}
	if IsKeyPressed(.BACKSPACE) || IsKeyPressed(.DELETE) {
		assign(.KEY_NULL)
		return true
	}
	for i in 0 ..< 128 {
		if key_assignable(KeyboardKey(i)) && IsKeyPressed(KeyboardKey(i)) {
			assign(KeyboardKey(i))
			return true
		}
	}
	return true
}

// Group hotkeys are digits and letters.
key_assignable :: proc(k: KeyboardKey) -> bool {
	return (k >= .ZERO && k <= .NINE) || (k >= .A && k <= .Z)
}

key_name :: proc(k: KeyboardKey) -> string {
	#partial switch k {
	case .A ..= .Z, .ZERO ..= .NINE:
		return fmt.tprintf("%c", rune(int(k)))
	case .F1 ..= .F12:
		return fmt.tprintf("F%d", int(k) - int(KeyboardKey.F1) + 1)
	case .TAB:
		return "Tab"
	}
	return "?"
}

// Preferences: "groups=<key>:<Tool>,<Tool>:<name>:<Cmd>,<Cmd>;<key>:..." (key = key code, 0 for none; tools and
// path operations by name).
tool_groups_serialize :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	for &g, i in tool_groups {
		fmt.sbprintf(&sb, "%s%d:", i > 0 ? ";" : "", int(g.key))
		for t, j in g.tools do fmt.sbprintf(&sb, "%s%v", j > 0 ? "," : "", t)
		fmt.sbprintf(&sb, ":%s:", name_str(&g.name))
		for c, j in g.ops do fmt.sbprintf(&sb, "%s%v", j > 0 ? "," : "", c)
	}
	return strings.to_string(sb)
}

tool_groups_parse :: proc(s: string) {
	tool_groups_clear()
	for part in strings.split(s, ";", context.temp_allocator) {
		fields := strings.split(part, ":", context.temp_allocator)
		if len(fields) < 2 || len(tool_groups) >= MAX_TOOL_GROUPS do continue
		g: Tool_Group
		if k, ok := strconv.parse_int(fields[0]); ok && key_assignable(KeyboardKey(k)) {
			g.key = KeyboardKey(k)
		}
		for ts in strings.split(fields[1], ",", context.temp_allocator) {
			for t in Tool {
				if fmt.tprintf("%v", t) == ts && !tool_group_has(&g, t) do append(&g.tools, t)
			}
		}
		if len(fields) > 2 do name_set(&g.name, group_clean_name(fields[2]))
		if len(fields) > 3 {
			for cs in strings.split(fields[3], ",", context.temp_allocator) {
				for op in PATH_OPS {
					if fmt.tprintf("%v", op.cmd) == cs && !group_has_op(&g, op.cmd) do append(&g.ops, op.cmd)
				}
			}
		}
		if len(g.tools) > 0 do g.last = g.tools[0]
		if len(g.ops) > 0 do g.last_op = g.ops[0]
		append(&tool_groups, g)
	}
}

// ---------------------------------------------------------------------------
// Hotkey badge, canvas-mode bar and rename dialog
// ---------------------------------------------------------------------------

// Keyboard-key look for hotkey badges, so they read differently from the tool buttons.
keycap :: proc(r: Rect, label: string, lit, hover: bool) {
	fill := lit ? C_ACTIVE : (hover ? shade(C_HOVER, 1.15) : shade(C_PANEL_LT, 1.18))
	face := Rect{r.x, r.y, r.w, r.h - 2}
	draw_rrect(f32(r.x), f32(r.y + 2), f32(r.w), f32(r.h - 2), RADIUS, C_BORDER) // the key's lower edge
	draw_rrect(f32(face.x), f32(face.y), f32(face.w), f32(face.h), RADIUS, fill)
	draw_rrect_outline(f32(face.x), f32(face.y), f32(face.w), f32(face.h), RADIUS, C_RING_HI)
	text_centered(face, label, lit ? WHITE : C_TEXT)
}

keycap_w :: proc(label: string) -> i32 {
	return max(18, text_w(label) + 10)
}

// Shown in canvas mode in place of the side panels: every group as `[key] -> current tool`,
// with the group that holds the current tool highlighted. Clicking a cell works like its hotkey.
panel_groups_bar :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y, r.w, C_BORDER)
	ty := r.y + (r.h - FONT_CAP) / 2
	x := r.x + 10
	text(x, ty, "Groups:", C_TEXT_DIM)
	x += text_w("Groups:") + 10
	limit := r.x + r.w - 10
	if status_t > 0 {
		msg := name_str(&status_msg)
		limit -= text_w(msg) + 16
		text(r.x + r.w - 10 - text_w(msg), ty, msg, C_ACCENT)
	}
	ARROW :: "->"
	cg := current_group()
	for &g, gi in tool_groups {
		if !group_visible(&g) || (len(g.tools) == 0 && len(g.ops) == 0) do continue
		active := cg == gi
		shown_icon: Icon
		if len(g.tools) > 0 {
			shown := active ? cur_tool : (tool_group_has(&g, g.last) ? g.last : g.tools[0])
			shown_icon = TOOL_ICONS[shown]
		} else {
			op, _ := path_op(group_has_op(&g, g.last_op) ? g.last_op : g.ops[0])
			shown_icon = op.icon
		}
		title := group_title(&g)
		key := g.key == .KEY_NULL ? "" : key_name(g.key)
		// label: the hotkey as a keycap, or the group's name when it has none
		label_w := key == "" ? text_w(title) : keycap_w(key)
		cw := 8 + label_w + 6 + text_w(ARROW) + 6 + 18 + 8
		if x + cw > limit do break
		cell := Rect{x, r.y + 3, cw, r.h - 6}
		tip := key == "" ? title : fmt.tprintf("%s (%s)", title, key)
		clicked, _, hover := button_behavior(make_id(cell, "grpcell"), cell, tip)
		if active {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_ACCENT_TINT)
			draw_rrect_outline(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, with_alpha(C_ACCENT, 150))
		} else {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, hover ? C_HOVER : C_PANEL)
			draw_rrect_outline(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_RING)
		}
		lx := cell.x + 8
		if key == "" {
			text(lx, ty, title, C_TEXT_DIM)
		} else {
			keycap(Rect{lx, cell.y + 2, label_w, cell.h - 4}, key, active, hover)
		}
		lx += label_w + 6
		text(lx, ty, ARROW, C_TEXT_DIM)
		lx += text_w(ARROW) + 6
		icon_centered(shown_icon, Rect{lx, cell.y, 18, cell.h}, active ? C_ACCENT : C_TEXT)
		if clicked do tool_group_activate(gi)
		x += cw + 6
	}
}

dlg_group_rename :: proc() {
	c := dialog_frame("Rename Group", 280, 84)
	if dialog.a < 0 || dialog.a >= len(tool_groups) {
		dialog_close()
		return
	}
	text(c.x, c.y + 3, "Name", C_TEXT)
	text_field(Rect{c.x + 50, c.y, c.w - 50, 14}, &dialog.name, "Leave empty for the default name")
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		name_set(&tool_groups[dialog.a].name, group_clean_name(name_str(&dialog.name)))
		dialog_close()
	}
}

group_rename_open :: proc(gi: int) {
	dialog_open(.Group_Rename)
	dialog.a = gi
	dialog.name = tool_groups[gi].name
}
