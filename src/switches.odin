package pangolin

// ---------------------------------------------------------------------------
// Switches: Grid, Snap and Onion Skin are `Tool` values so they can sit in tool groups next to the tools. Clicking
// one turns it on or off instead of becoming the active tool, and while it is on, its settings can take over the
// options bar.
// ---------------------------------------------------------------------------

tool_is_toggle :: proc(t: Tool) -> bool {
	return t >= .Grid
}

tool_toggle_on :: proc(t: Tool) -> bool {
	#partial switch t {
	case .Grid:
		return show_grid
	case .Snap:
		return snap_grid
	case .Onion:
		return onion
	}
	return false
}

// Turns a switch on or off, keeping the options bar in step.
switch_set :: proc(t: Tool, on: bool) {
	#partial switch t {
	case .Grid:
		show_grid = on
	case .Snap:
		snap_grid = on
	case .Onion:
		onion = on
	}
	if tool_toggle_on(t) {
		options_switch, options_switch_on = t, true
	} else if options_switch == t {
		options_switch_on = false
	}
}

// The options bar shows the last thing picked: a tool, or one of the switches.
options_switch: Tool // the switch whose settings are shown while options_switch_on
options_switch_on: bool

// Clicking a switch: off -> on (showing its settings); on but not shown -> show its settings;
// on and shown -> off (the tool's settings come back).
tool_toggle :: proc(t: Tool) {
	if tool_toggle_on(t) && !(options_switch_on && options_switch == t) {
		options_switch, options_switch_on = t, true
		return
	}
	switch_set(t, !tool_toggle_on(t))
}

// Settings of the switch shown in the options bar; false if the tool's settings should show instead.
options_switch_ui :: proc() -> bool {
	if !options_switch_on || !tool_toggle_on(options_switch) do return false
	t := options_switch
	oicon("icon", TOOL_ICONS[t], "switch-icon")
	#partial switch t {
	case .Grid:
		otext("title", "Grid", "switch-title")
		options_grid_size()
		ocheck("Snap", &snap_grid, cmd_tip("Snap to grid", .Toggle_Snap))
		if obutton("Grid Off", 60, cmd_tip("Grid Off", .Toggle_Grid)) do switch_set(.Grid, false)
	case .Snap:
		otext("title", "Snap to Grid", "switch-title")
		options_grid_size()
		ocheck("Show grid", &show_grid, cmd_tip("Show grid", .Toggle_Grid))
		if obutton("Snap Off", 60, cmd_tip("Snap Off", .Toggle_Snap)) do switch_set(.Snap, false)
	case .Onion:
		otext("title", "Onion Skin", "switch-title")
		oslider("Before", 86, &onion_prev, 0, 5, {"Frames before", "How many earlier frames show under this one."})
		oslider("After", 86, &onion_next, 0, 5, {"Frames after", "How many later frames show under this one."})
		oslider("Opacity", 100, &onion_alpha, 5, 100, {"Onion skin opacity", "How strongly the neighboring frames show. Those further away fade more."}, "%")
		if obutton("Onion Off", 64, cmd_tip("Onion Off", .Toggle_Onion)) do switch_set(.Onion, false)
	}
	return true
}

options_grid_size :: proc() {
	otext("grid-l", "Size", "dim", {"Grid size", "Spacing of the grid in document units, used for showing it and for snapping."})
	oui_slot("grid-size", "grid_size")
}
