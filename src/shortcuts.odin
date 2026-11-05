package pangolin

// Keyboard shortcuts. Skipped while a text field, the text tool or a dialog has the keyboard.

shortcuts_update :: proc() {
	d := doc
	if d == nil do return
	if ui.focus_id != 0 || popup.open || dialog.kind != .None || text_editing() do return
	if tool_groups_key_capture() do return
	ctrl, shift, alt := ui.ctrl, ui.shift, ui.alt

	if IsKeyPressed(.F1) {
		run_cmd(.Shortcuts)
		return
	}
	if ctrl {
		switch {
		case key_hit(.Z):
			run_cmd(shift ? .Redo : .Undo)
		case key_hit(.Y):
			run_cmd(.Redo)
		case key_hit(.N):
			run_cmd(.New)
		case key_hit(.O):
			run_cmd(.Open)
		case key_hit(.S):
			run_cmd(shift ? .Save_As : .Save)
		case key_hit(.E) && shift:
			run_cmd(.Export)
		case key_hit(.W):
			run_cmd(.Close_Doc)
		case key_hit(.Q):
			run_cmd(.Quit)
		case key_hit(.X):
			run_cmd(.Cut)
		case key_hit(.C):
			run_cmd(shift ? .Object_To_Path : .Copy)
		case key_hit(.V):
			run_cmd(shift ? .Paste_In_Place : .Paste)
		case key_hit(.J):
			run_cmd(.Duplicate)
		case key_hit(.D):
			run_cmd(.Deselect)
		case key_hit(.A): // Ctrl+Shift+A was Deselect before Ctrl+D, and hands remember it
			run_cmd(shift ? .Deselect : .Select_All)
		case key_hit(.G):
			run_cmd(shift ? .Ungroup : .Group)
		case key_hit(.K):
			run_cmd(shift ? .Break_Apart : .Combine)
		case key_hit(.EQUAL), key_hit(.KP_ADD):
			run_cmd(alt ? .Union : .Zoom_In)
		case key_hit(.MINUS), key_hit(.KP_SUBTRACT):
			run_cmd(alt ? .Subtract : .Zoom_Out)
		case key_hit(.EIGHT) && alt:
			run_cmd(.Intersect)
		case key_hit(.ZERO):
			run_cmd(.Fit_View)
		case key_hit(.ONE):
			run_cmd(.Actual_Size)
		case key_hit(.TWO):
			run_cmd(.Zoom_200)
		case key_hit(.SEMICOLON):
			run_cmd(shift ? .Toggle_Snap : .Toggle_Grid)
		}
		return
	}

	if IsKeyPressed(.TAB) && !shift && !alt {
		run_cmd(.Toggle_Canvas_Mode)
		return
	}
	if alt && key_hit(.N) {
		run_cmd(.Frame_New)
		return
	}
	if alt && key_hit(.O) {
		run_cmd(.Toggle_Onion)
		return
	}
	// group hotkeys come before the single-key tool shortcuts, so a group can take over a letter
	if tool_groups_hotkeys() do return

	if d.kind == .Font do font_shortcuts(d)

	// frames. Only the start of a press: a held Enter must not flip playback on and off, and the Enter that
	// closed a dialog must not start it. The pen tool has Enter for itself, and in a font these do nothing.
	if key_hit(.COMMA) do run_cmd(shift ? .Frame_First : .Frame_Prev)
	if key_hit(.PERIOD) do run_cmd(shift ? .Frame_Last : .Frame_Next)
	if IsKeyPressed(.ENTER) && cur_tool != .Pen && tl.kind == .None do run_cmd(.Play)

	// tools
	switch {
	case key_hit(.V): set_tool(.Select)
	case shift && key_hit(.A): set_tool(.Control)
	case key_hit(.A): set_tool(.Node)
	case key_hit(.B), key_hit(.F): set_tool(.Freehand) // F was its key once, and still works
	case key_hit(.E): set_tool(.Eraser)
	case key_hit(.U): set_tool(.Sculpt)
	case key_hit(.X): set_tool(.Extend)
	case key_hit(.P): set_tool(.Pen)
	case key_hit(.R): set_tool(.Rect)
	case key_hit(.O): set_tool(.Ellipse)
	case key_hit(.L): set_tool(.Line)
	case key_hit(.T): set_tool(.Text)
	case key_hit(.I): set_tool(.Picker)
	case key_hit(.H): set_tool(.Hand)
	case key_hit(.Z): set_tool(.Zoom)
	case key_hit(.EQUAL), key_hit(.KP_ADD): run_cmd(.Zoom_In)
	case key_hit(.MINUS), key_hit(.KP_SUBTRACT): run_cmd(.Zoom_Out)
	}

	// the same keys as the brushes in the other tools; in a font they step through the glyphs
	if eff_tool() == .Eraser && d.kind != .Font {
		if key_hit(.LEFT_BRACKET) do eraser_size = max(eraser_size - max(eraser_size / 5, 1), ERASER_SIZE_MIN)
		if key_hit(.RIGHT_BRACKET) do eraser_size = min(eraser_size + max(eraser_size / 5, 1), ERASER_SIZE_MAX)
	}
	if eff_tool() == .Sculpt && d.kind != .Font {
		if key_hit(.LEFT_BRACKET) do sculpt_size = max(sculpt_size - max(sculpt_size / 5, 1), SCULPT_SIZE_MIN)
		if key_hit(.RIGHT_BRACKET) do sculpt_size = min(sculpt_size + max(sculpt_size / 5, 1), SCULPT_SIZE_MAX)
	}
	if cur_tool == .Pen {
		if key_hit(.ENTER) || key_hit(.ESCAPE) do pen_finish(true)
		if key_hit(.BACKSPACE) do pen_undo_point(d)
		return
	}
	if cur_tool == .Node {
		if key_hit(.DELETE) || key_hit(.BACKSPACE) do node_cmd_delete(d)
		if key_hit(.S) do node_cmd_smooth(d)
		if key_hit(.C) do node_cmd_corner(d)
		if key_hit(.ESCAPE) {
			clear(&tl.anchors)
			tl.edit_uid = 0
		}
		nudge_anchors(d)
		return
	}
	if cur_tool == .Control {
		if key_hit(.ESCAPE) {
			tl.ctrl_on = false
			tl.edit_uid = 0
		}
		nudge_control(d)
		return
	}
	if key_hit(.ESCAPE) {
		if tl.kind == .Erase do eraser_end(d) // what is already erased stays, as one undo step
		if tl.kind == .Sculpt do sculpt_end(d)
		clear(&d.sel)
		tl_reset()
	}
	if key_hit(.DELETE) || key_hit(.BACKSPACE) do run_cmd(.Delete)
	if key_hit(.PAGE_UP) do run_cmd(.Raise)
	if key_hit(.PAGE_DOWN) do run_cmd(.Lower)
	if key_hit(.HOME) do run_cmd(.To_Front)
	if key_hit(.END) do run_cmd(.To_Back)
	// nudge
	step: f32 = shift ? 10 : 1
	dx, dy: f32
	if key_hit(.LEFT) do dx = -step
	if key_hit(.RIGHT) do dx = step
	if key_hit(.UP) do dy = -step
	if key_hit(.DOWN) do dy = step
	if (dx != 0 || dy != 0) && len(d.sel) > 0 {
		if ui.time - xf_push_t > 0.6 do history_push(d)
		xf_push_t = ui.time
		sel_remember(d)
		sel_apply(d, mat_translate(dx, dy))
		tl_reset()
	}
}

nudge_anchors :: proc(d: ^Doc) {
	n := edited_node(d)
	if n == nil || len(tl.anchors) == 0 do return
	step: f32 = ui.shift ? 10 : 1
	dx, dy: f32
	if key_hit(.LEFT) do dx = -step
	if key_hit(.RIGHT) do dx = step
	if key_hit(.UP) do dy = -step
	if key_hit(.DOWN) do dy = step
	if dx == 0 && dy == 0 do return
	if ui.time - xf_push_t > 0.6 do history_push(d)
	xf_push_t = ui.time
	iw, ok := mat_inv(node_world(d.root, n))
	if !ok do return
	move_anchors(n.segs[:], tl.anchors[:], mat_apply_dir(iw, {dx, dy}))
	doc_changed(d)
}

nudge_control :: proc(d: ^Doc) {
	step: f32 = ui.shift ? 10 : 1
	dx, dy: f32
	if key_hit(.LEFT) do dx = -step
	if key_hit(.RIGHT) do dx = step
	if key_hit(.UP) do dy = -step
	if key_hit(.DOWN) do dy = step
	if dx == 0 && dy == 0 do return
	n := edited_node(d)
	if n == nil do return
	if _, ok := control_selected(n); !ok do return
	if ui.time - xf_push_t > 0.6 do history_push(d)
	xf_push_t = ui.time
	control_nudge(d, {dx, dy})
}

node_cmd_delete :: proc(d: ^Doc) {
	if n := edited_node(d); n != nil do delete_anchors(d, n)
}

node_cmd_smooth :: proc(d: ^Doc) {
	n := edited_node(d)
	if n == nil || len(tl.anchors) == 0 do return
	history_push(d)
	for i in tl.anchors do if i < len(n.segs) do anchor_make_smooth(n, i)
	doc_changed(d)
}

node_cmd_corner :: proc(d: ^Doc) {
	n := edited_node(d)
	if n == nil || len(tl.anchors) == 0 do return
	history_push(d)
	for i in tl.anchors do if i < len(n.segs) do anchor_make_corner(n, i)
	doc_changed(d)
}
