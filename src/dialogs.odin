package pangolin

import "core:fmt"

Dialog_Kind :: enum {
	None,
	New_Doc,
	Export,
	Page_Size,
	Add_Glyphs,
	Confirm_Close,
	Message,
	Shortcuts,
	About,
	Group_Rename,
	Font,
	UI_Scale,
	Tags,
	Frame_Props,
	Workspaces,
}

Dialog :: struct {
	kind:      Dialog_Kind,
	a, b, c:   int,
	flag:      bool,
	name:      Name,
	msg_title: Name,
	msg_text:  Name,
}

dialog: Dialog

SIZE_PRESETS := [?]struct {
	name: string,
	w, h: int,
}{
	{"Icon 64 x 64", 64, 64},
	{"Square 512 x 512", 512, 512},
	{"Square 1000 x 1000", 1000, 1000},
	{"Screen 1024 x 768", 1024, 768},
	{"HD 1920 x 1080", 1920, 1080},
	{"A4 portrait 794 x 1123", 794, 1123},
	{"A4 landscape 1123 x 794", 1123, 794},
}

dialog_open :: proc(k: Dialog_Kind) {
	dialog = Dialog {
		kind      = k,
		msg_title = dialog.msg_title,
		msg_text  = dialog.msg_text,
	}
	switch k {
	case .New_Doc:
		dialog.a, dialog.b = 1024, 768
	case .Export:
		dialog.a = 100
		dialog.flag = true
	case .Frame_Props:
		dialog.a = doc.frames[doc.active_frame].duration
	case .Workspaces:
		ws_refresh()
	case .Page_Size:
		dialog.a, dialog.b = int(doc.w), int(doc.h)
	case .Add_Glyphs:
		dialog.a = 0
	case .None, .Confirm_Close, .Message, .Shortcuts, .About, .Group_Rename, .Font, .UI_Scale, .Tags:
	}
}

message :: proc(title, text: string) {
	name_set(&dialog.msg_title, title)
	name_set(&dialog.msg_text, text)
	dialog_open(.Message)
}

dialog_close :: proc() {
	dialog.kind = .None
}

// OK / Cancel row at the bottom of the content area.
dialog_buttons :: proc(c: Rect, ok_tip: string, ok_label := "OK", cancel_label := "Cancel") -> (ok, cancel: bool) {
	y := c.y + c.h - 18
	r := Rect{c.x + c.w - 64, y, 64, 18}
	if button_primary(r, ok_label, {ok_label, ok_tip}) do ok = true
	if cancel_label != "" {
		if button(Rect{r.x - 70, y, 64, 18}, cancel_label, {cancel_label, "Close this dialog without changing anything (Esc)."}) do cancel = true
	}
	if ui.focus_id == 0 && !popup.open {
		if IsKeyPressed(.ENTER) || IsKeyPressed(.KP_ENTER) do ok = true
		if IsKeyPressed(.ESCAPE) && cancel_label != "" do cancel = true
		if IsKeyPressed(.ESCAPE) && cancel_label == "" do ok = true
	}
	return
}

row_int :: proc(c: Rect, y: i32, name: string, v: ^int, lo, hi: int, desc: string) {
	tip_text(c.x, y + 3, name, C_TEXT, {name, desc})
	field_int(Rect{c.x + 110, y, 70, 14}, v, lo, hi, {name, desc})
}

dialogs_run :: proc() {
	if dialog.kind == .None do return
	switch dialog.kind {
	case .None:
	case .New_Doc:
		c := dialog_frame("New SVG", 300, 150)
		y := c.y
		PRESET_TIP :: "Fill in the width and height with a common page size."
		tip_text(c.x, y + 3, "Preset", C_TEXT, {"Size preset", PRESET_TIP})
		names: [len(SIZE_PRESETS)]string
		for p, i in SIZE_PRESETS do names[i] = p.name
		cur := -1
		for p, i in SIZE_PRESETS {
			if p.w == dialog.a && p.h == dialog.b do cur = i
		}
		if nv, ch := combo(Rect{c.x + 110, y, c.w - 110, 14}, names[:], cur, {"Size preset", PRESET_TIP}); ch {
			dialog.a, dialog.b = SIZE_PRESETS[nv].w, SIZE_PRESETS[nv].h
		}
		row_int(c, y + 22, "Width (px)", &dialog.a, 1, 20000, "The width of the new page in pixels.")
		row_int(c, y + 42, "Height (px)", &dialog.b, 1, 20000, "The height of the new page in pixels.")
		ok, cancel := dialog_buttons(c, "Create the drawing in a new tab (Enter).")
		if ok {
			add_doc(doc_new(.Svg, "Untitled", f32(dialog.a), f32(dialog.b)))
			dialog_close()
		} else if cancel {
			dialog_close()
		}
	case .Export:
		dlg_export()
	case .Page_Size:
		c := dialog_frame("Page Size", 280, 110)
		row_int(c, c.y, "Width", &dialog.a, 1, 20000, "The new width of the page in document units. Objects stay where they are.")
		row_int(c, c.y + 20, "Height", &dialog.b, 1, 20000, "The new height of the page in document units. Objects stay where they are.")
		ok, cancel := dialog_buttons(c, "Apply this page size (Enter). You can undo it.")
		if ok {
			history_push(doc)
			doc.w, doc.h = f32(dialog.a), f32(dialog.b)
			doc_changed(doc)
			dialog_close()
		} else if cancel {
			dialog_close()
		}
	case .Add_Glyphs:
		c := dialog_frame("Add Glyphs", 300, 130)
		SET_TIP :: "Which characters to add. Basic Latin is all of the standard keyboard characters, Latin-1 letters are accented letters such as e with an acute accent."
		tip_text(c.x, c.y + 3, "Character set", C_TEXT, {"Character set", SET_TIP})
		items := [?]string{"A - Z", "a - z", "0 - 9", "Punctuation", "Basic Latin (ASCII)", "Latin-1 letters"}
		if nv, ch := combo(Rect{c.x + 110, c.y, c.w - 110, 14}, items[:], dialog.a, {"Character set", SET_TIP}); ch do dialog.a = nv
		ok, cancel := dialog_buttons(c, "Add glyphs for these characters (Enter). Characters the font already has are skipped.", "Add")
		if ok {
			font_add_set(doc, dialog.a)
			dialog_close()
		} else if cancel {
			dialog_close()
		}
	case .Confirm_Close:
		c := dialog_frame("Unsaved changes", 320, 90)
		text(c.x, c.y + 4, fmt.tprintf("Save changes to %s?", name_str(&doc.title)), C_TEXT)
		y := c.y + c.h - 18
		quitting := dialog.flag // asked on the way out: the answer goes on to the next unsaved document, then quits
		if button_primary(Rect{c.x + c.w - 64, y, 64, 18}, "Save", {"Save", quitting ? "Save your changes, then go on quitting." : "Save your changes, then close the document."}) {
			dialog_close()
			doc_save(doc, false)
			// (a save that failed or was cancelled leaves the document open, and has said why)
			if !doc.modified {
				if quitting do request_quit()
				else do doc_close_now(doc)
			}
		}
		if button(Rect{c.x + c.w - 150, y, 80, 18}, "Don't save", {"Don't save", quitting ? "Quit and lose this document's changes since you last saved. This can't be undone." : "Close the document and lose the changes since you last saved. This can't be undone."}) {
			dialog_close()
			if quitting {
				doc.modified = false
				request_quit()
			} else {
				doc_close_now(doc)
			}
		}
		if button(Rect{c.x + c.w - 220, y, 64, 18}, "Cancel", {"Cancel", "Keep the document open and go back to it (Esc)."}) || (IsKeyPressed(.ESCAPE) && ui.focus_id == 0) {
			dialog_close()
		}
	case .Message:
		c := dialog_frame(name_str(&dialog.msg_title), 340, 90)
		text_clipped(Rect{c.x, c.y + 2, c.w, 14}, name_str(&dialog.msg_text), C_TEXT)
		if ok, _ := dialog_buttons(c, "Close this message (Enter).", "OK", ""); ok do dialog_close()
	case .Shortcuts:
		c := dialog_frame("Keyboard Shortcuts", 540, 470)
		lines := [?][2]string {
			{"1 - 6 (tool groups)", "pick a group, press again to cycle its tools"},
			{"V / A / Shift+A / P / B", "select / node edit / control points / pen / freehand"},
			{"R / O / L / T / I", "rectangle / ellipse / line / text / eyedropper"},
			{"E, [ / ]", "eraser, smaller / bigger eraser"},
			{"U, [ / ]", "sculpt, smaller / bigger brush"},
			{"X", "extend a line from its end"},
			{"H, Space (hold), middle drag", "pan"},
			{"Wheel, Ctrl+= / Ctrl+-", "zoom in and out"},
			{"Ctrl+0 / Ctrl+1 / Ctrl+2", "fit to window / 100% / 200%"},
			{"Ctrl+Z / Ctrl+Shift+Z", "undo / redo"},
			{"Ctrl+C / X / V / J", "copy / cut / paste / duplicate"},
			{"Ctrl+A / Ctrl+D", "select all / deselect"},
			{"Ctrl+G / Ctrl+Shift+G", "group / ungroup"},
			{"PgUp / PgDn / Home / End", "raise / lower / to front / to back"},
			{"Ctrl+Alt+= / - / 8", "union / subtract / intersect"},
			{"Ctrl+K / Ctrl+Shift+K", "combine / break apart"},
			{"Ctrl+Shift+C", "object to path"},
			{"Ctrl+; / Ctrl+Shift+;", "grid / snap to grid"},
			{"Shift while dragging", "keep proportions, 15 degree steps"},
			{"Alt while dragging", "draw from the center / break handle symmetry"},
			{"Pen: Enter / Esc / Backspace", "finish / finish / remove last point"},
			{"Node tool: Del, C, S, dbl-click", "delete node / corner / smooth / add node"},
			{"Arrows (Shift)", "nudge 1 (10) units"},
			{"Tab", "canvas mode: only the drawing and the tool groups"},
			{"Alt+N", "new frame"},
			{", / . (Shift: first / last)", "previous / next frame"},
			{"Enter", "play or stop the animation"},
			{"Alt+O", "onion skin"},
			{"Ctrl+S / Ctrl+Shift+S / Ctrl+Shift+E", "save / save as / export"},
			{"F1", "this list"},
		}
		y := c.y
		for l in lines {
			text(c.x, y, l[0], C_ACCENT)
			text(c.x + 220, y, l[1], C_TEXT)
			y += 14
		}
		if ok, _ := dialog_buttons(c, "Close this list (Enter or Esc).", "Close", ""); ok do dialog_close()
	case .About:
		c := dialog_frame("About", 300, 150)
		logo_draw(c.x, c.y + 4, 4)
		text(c.x + 80, c.y + 6, APP_NAME, WHITE)
		text(c.x + 80, c.y + 22, fmt.tprintf("Version %s", APP_VERSION), C_TEXT_DIM)
		text(c.x + 80, c.y + 38, APP_TAGLINE, C_TEXT)
		text(c.x + 80, c.y + 58, "Part of the Pangolin suite. BSD 3-Clause.", C_TEXT_DIM)
		if ok, _ := dialog_buttons(c, "Close this window (Enter or Esc).", "OK", ""); ok do dialog_close()
	case .Group_Rename:
		dlg_group_rename()
	case .Font:
		dlg_font()
	case .UI_Scale:
		dlg_ui_scale()
	case .Tags:
		dlg_tags()
		if dialog.kind != .Tags do tags_dialog_closed(doc)
	case .Frame_Props:
		dlg_frame_props()
	case .Workspaces:
		dlg_workspaces()
	}
}
