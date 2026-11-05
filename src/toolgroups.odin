package pangolin

import "core:fmt"
import "core:strconv"
import "core:strings"

// User-editable tool groups shown in the left toolbar. A group's hotkey selects its first tool
// (or the one last used from it); pressing it again cycles through the group's tools.
// The single-key tool shortcuts (V, P, R ...) keep working; a group hotkey on the same key wins.
// Groups can also hold path operations (union, offset ...): buttons that act on the selection at once.
// The hotkey of a group with operations but no tools runs the operation last used from it. In a group with tools
// it steps through the tools, and Change Fill and Change Stroke take their turn after them.
// Switches (Grid, Snap, Onion Skin) sit among the tools and flip on and off.
// A group holding colors instead is a color group: its hotkey steps the fill color, of the selection or for new
// shapes, and leaves the tool alone.

MAX_TOOL_GROUPS :: 12
MAX_GROUP_COLORS :: 64

Tool_Group :: struct {
	key:   KeyboardKey, // KEY_NULL: no hotkey
	tools: [dynamic]Tool,
	last:  Tool, // last tool picked from this group
	ops:   [dynamic]Cmd, // path operations (from PATH_OPS)
	last_op: Cmd, // last operation run from this group
	turn_op: Cmd, // where the hotkey's rotation is when it is on an operation, not on the current tool (op_takes_turn)
	colors: [dynamic]Color, // a color group holds nothing else
	name:  Name, // empty: "Group"
	pen_eraser: bool, // the pen's eraser end uses this group's last tool (at most one group)
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
	{.Close_Or_Open, .Close_Path, "Close or Open Path", 1},
	{.Simplify, .Simplify, "Simplify", 1},
	{.Offset_Out, .Offset_Out, "Offset Outward", 1},
	{.Offset_In, .Offset_In, "Offset Inward", 1},
	{.Object_To_Path, .To_Path, "Object to Path", 1},
	{.Stroke_To_Path, .Stroke_Path, "Stroke to Path", 1},
	{.Toggle_Close_Paths, .Close_Paths, "Close Open Paths", 0},
	{.Change_Fill, .Change_Fill, "Change Fill", 0},
	{.Change_Stroke, .Change_Stroke, "Change Stroke", 0},
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

// Runs a group's operation and remembers it for the group's hotkey (a setting's toggle is not remembered).
group_run_op :: proc(gi: int, c: Cmd) {
	if c != .Toggle_Close_Paths do tool_groups[gi].last_op = c
	run_cmd(c)
}

// Operations a hotkey can land on while it steps through a group's tools. Only ones that are safe to run in passing
// and can be stepped back: Simplify or Union would change a drawing just by being on the way to the next tool.
op_takes_turn :: proc(c: Cmd) -> bool {
	return c == .Change_Fill || c == .Change_Stroke
}

group_has_op :: proc(g: ^Tool_Group, c: Cmd) -> bool {
	for x in g.ops do if x == c do return true
	return false
}

tool_groups: [dynamic]Tool_Group
active_group := -1 // group the current tool was last picked from, or -1
group_key_wait := -1 // group waiting for a hotkey press, or -1

tool_group_has :: proc(g: ^Tool_Group, t: Tool) -> bool {
	for x in g.tools {
		if x == t do return true
	}
	return false
}

// The fill color a color group compares with: the selection's, or the one new shapes get.
current_fill_color :: proc() -> Color {
	sel := first_selected(doc)
	p := sel != nil ? sel.fill : cur_fill
	return p.kind == .Solid ? p.color : Color{}
}

group_color_is_current :: proc(c: Color) -> bool {
	f := current_fill_color()
	return f.a > 0 && f.r == c.r && f.g == c.g && f.b == c.b
}

// Makes `c` the fill color, of the selection or for new shapes.
group_color_pick :: proc(c: Color) {
	if doc == nil do return
	style_set_fill(doc, paint_solid(Color{c.r, c.g, c.b, 255}))
	recent_push(c)
}

group_add_colors :: proc(g: ^Tool_Group, colors: []Color) {
	for c in colors {
		if len(g.colors) >= MAX_GROUP_COLORS do break
		append(&g.colors, Color{c.r, c.g, c.b, 255})
	}
}

group_title :: proc(g: ^Tool_Group) -> string {
	if g.name.n > 0 do return name_str(&g.name)
	return g.pen_eraser ? "Pen" : "Group"
}

// The tool the pen's eraser end uses, if a group is assigned to it. Switches can't be drawn with.
pen_eraser_group_tool :: proc() -> (Tool, bool) {
	for &g in tool_groups {
		if !g.pen_eraser do continue
		if !tool_is_toggle(g.last) && tool_group_has(&g, g.last) do return g.last, true
		for t in g.tools {
			if !tool_is_toggle(t) do return t, true
		}
	}
	return {}, false
}

// Makes group `gi` the pen eraser's, or none if it already is.
group_set_pen_eraser :: proc(gi: int) {
	on := !tool_groups[gi].pen_eraser
	if on && gi == active_group do active_group = -1
	for &o in tool_groups do o.pen_eraser = false
	tool_groups[gi].pen_eraser = on
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
	if active_group >= 0 && active_group < len(tool_groups) {
		g := &tool_groups[active_group]
		if !g.pen_eraser && tool_group_has(g, cur_tool) do return active_group
	}
	for &g, i in tool_groups {
		if !g.pen_eraser && tool_group_has(&g, cur_tool) do return i
	}
	return -1
}

// Picks `t` as a member of group `gi`.
select_tool_in_group :: proc(t: Tool, gi: int) {
	if tool_is_toggle(t) {
		tool_toggle(t)
		return
	}
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
		delete(g.colors)
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
	options_switch_on = false
	add("Select", .ONE, .Select, .Node, .Control, .Sculpt)
	add("Draw", .TWO, .Pen, .Freehand, .Line, .Eraser, .Extend)
	add("Shapes", .THREE, .Rect, .Ellipse)
	add("Text", .FOUR, .Text, .Picker)
	add("View", .FIVE, .Hand, .Zoom, .Grid, .Snap)
	path := Tool_Group {
		key     = .SIX,
		name    = make_name("Path"),
		last_op = .Union,
	}
	append(&path.ops, Cmd.Union, Cmd.Subtract, Cmd.Intersect, Cmd.Exclude, Cmd.Combine, Cmd.Break_Apart, Cmd.Close_Or_Open, Cmd.Toggle_Close_Paths)
	append(&tool_groups, path)
}

// The group's hotkey: the first time it picks the group's last tool, then it steps through the group.
tool_group_activate :: proc(gi: int) {
	g := &tool_groups[gi]
	if len(g.colors) > 0 {
		next := 0
		for c, i in g.colors {
			if group_color_is_current(c) {
				next = (i + 1) % len(g.colors)
				break
			}
		}
		group_color_pick(g.colors[next])
		set_statusf("Fill color: %s", color_hex(g.colors[next]))
		return
	}
	// the hotkey steps through the real tools; a group of only switches flips its first one
	real := make([dynamic]Tool, context.temp_allocator)
	for t in g.tools do if !tool_is_toggle(t) do append(&real, t)
	tools := real[:]
	n := len(tools)
	if n == 0 {
		if len(g.ops) > 0 {
			group_run_op(gi, group_has_op(g, g.last_op) ? g.last_op : g.ops[0])
		} else if len(g.tools) > 0 {
			tool_toggle(g.tools[0])
		}
		return
	}
	if g.pen_eraser {
		// only changes the pen's eraser end, never the current tool
		next := tools[0]
		for t, i in tools {
			if t == g.last do next = tools[(i + 1) % n]
		}
		g.last = next
		return
	}
	if current_group() == gi {
		// Change Fill and Change Stroke take their turn after the tools; landing on one runs it once
		turns := make([dynamic]Cmd, context.temp_allocator)
		for c in g.ops do if op_takes_turn(c) do append(&turns, c)
		at := -1
		for c, i in turns do if c == g.turn_op do at = n + i
		if at < 0 {
			for t, i in tools do if t == cur_tool do at = i
		}
		if at >= 0 {
			next := (at + 1) % (n + len(turns))
			if next < n {
				select_tool_in_group(tools[next], gi)
			} else {
				g.turn_op = turns[next - n]
				group_run_op(gi, g.turn_op)
			}
			return
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

// Preferences: "groups=<key>:<Tool>,<Tool>:<name>:<Cmd>,<Cmd>[:<color>,<color>[:1]];<key>:..." (key = key code, 0 for
// none; tools and path operations by name; colors as RRGGBB, and the field only when there are any or the 1 follows,
// which marks the pen eraser's group, so any other group reads the same as in older files).
tool_groups_serialize :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	for &g, i in tool_groups {
		fmt.sbprintf(&sb, "%s%d:", i > 0 ? ";" : "", int(g.key))
		for t, j in g.tools do fmt.sbprintf(&sb, "%s%v", j > 0 ? "," : "", t)
		fmt.sbprintf(&sb, ":%s:", name_str(&g.name))
		for c, j in g.ops do fmt.sbprintf(&sb, "%s%v", j > 0 ? "," : "", c)
		if len(g.colors) > 0 || g.pen_eraser {
			strings.write_byte(&sb, ':')
			for c, j in g.colors do fmt.sbprintf(&sb, "%s%02x%02x%02x", j > 0 ? "," : "", c.r, c.g, c.b)
		}
		if g.pen_eraser do strings.write_string(&sb, ":1")
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
		if len(fields) > 4 && len(g.tools) == 0 && len(g.ops) == 0 {
			for cs in strings.split(fields[4], ",", context.temp_allocator) {
				if c, ok := parse_color(fmt.tprintf("#%s", cs), BLACK); ok && len(cs) == 6 && len(g.colors) < MAX_GROUP_COLORS {
					append(&g.colors, c)
				}
			}
		}
		for t in g.tools {
			if !tool_is_toggle(t) {
				g.last = t
				break
			}
		}
		if len(g.ops) > 0 do g.last_op = g.ops[0]
		if len(fields) > 5 && fields[5] == "1" {
			taken := false
			for &o in tool_groups do taken ||= o.pen_eraser
			g.pen_eraser = !taken
		}
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
	tip_text(x, ty, "Groups:", C_TEXT_DIM, {"Tool groups", "Each one shows its hotkey and the tool it will pick. Press Tab to bring the full interface back."})
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
		if len(g.tools) == 0 && len(g.ops) == 0 && len(g.colors) == 0 do continue
		active := cg == gi
		shown_icon: Icon
		shown_color: Color
		if len(g.colors) > 0 {
			shown_color = g.colors[0]
			for c in g.colors {
				if group_color_is_current(c) {
					shown_color, active = c, true
				}
			}
		} else if len(g.tools) > 0 {
			shown := active ? cur_tool : (tool_group_has(&g, g.last) && !tool_is_toggle(g.last) ? g.last : g.tools[0])
			// a group of only switches shows its first one, lit while it is on
			if tool_is_toggle(shown) do active = tool_toggle_on(shown)
			if g.pen_eraser {
				if pt, ok := pen_eraser_group_tool(); ok do shown = pt
				active = pen_eraser_active()
			}
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
		tip := key == "" ? Tip{title, "Click to use this group's tool, repeat its last operation, or step to its next color."} : Tip{fmt.tprintf("%s (%s)", title, key), "Click or press the key to use this group's tool, repeat its last operation, or step to its next color. Again steps to its next tool."}
		if g.pen_eraser do tip.desc = "The tool on the pen's eraser end. Click or press the key to step through this group's tools."
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
		if len(g.colors) > 0 {
			sw := Rect{lx + 1, cell.y + 4, 16, cell.h - 8}
			draw_rrect(f32(sw.x), f32(sw.y), f32(sw.w), f32(sw.h), 2, shown_color)
			draw_rrect_outline(f32(sw.x), f32(sw.y), f32(sw.w), f32(sw.h), 2, active ? WHITE : C_RING_HI)
		} else {
			icon_centered(shown_icon, Rect{lx, cell.y, 18, cell.h}, active ? C_ACCENT : C_TEXT)
		}
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
	tip_text(c.x, c.y + 3, "Name", C_TEXT, {"Group name", "The name shown above this tool group."})
	text_field(Rect{c.x + 50, c.y, c.w - 50, 14}, &dialog.name, {"Group name", "The name shown above this tool group. Leave it empty for the default name, \"Group\"."})
	ok, cancel := dialog_buttons(c, "Use this name for the group (Enter).")
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
