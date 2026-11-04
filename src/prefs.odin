package pangolin

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Tiny key=value preferences file stored next to the executable.

// Interface scale, in percent of one physical pixel per logical pixel.
UI_SCALE_MIN :: 75
UI_SCALE_MAX :: 400
UI_SCALE_STEP :: 25
UI_AUTO_HEIGHT :: 720 // the automatic scale leaves about this many logical pixels up the whole screen
UI_MIN_W :: 900 // the interface needs at least this much room, in logical pixels
UI_MIN_H :: 560

ui_scale_pref := 0 // what the user set; 0 sizes the interface automatically
ui_scale_arg := 0 // --scale, for this run only: never saved

ui_scale_snap :: proc(percent: int) -> int {
	return clamp((percent + UI_SCALE_STEP / 2) / UI_SCALE_STEP * UI_SCALE_STEP, UI_SCALE_MIN, UI_SCALE_MAX)
}

// The automatic scale for a display: large enough for its pixel height, and never below the system's own setting.
ui_scale_auto :: proc(display_h: int, system_scale: f32) -> int {
	return max(ui_scale_snap(display_h * 100 / UI_AUTO_HEIGHT), ui_scale_snap(int(system_scale * 100 + 0.5)), 100)
}

// The scale asked for, before fitting it to the window.
ui_scale_wanted :: proc() -> int {
	if ui_scale_arg > 0 do return ui_scale_arg
	if ui_scale_pref > 0 do return ui_scale_pref
	h, system_scale := gfx_display_info()
	return ui_scale_auto(h, system_scale)
}

// The largest step up to `percent` that leaves the interface enough room in a window of `pw` x `ph` physical pixels.
ui_scale_fit :: proc(percent, pw, ph: int) -> int {
	room := min(pw * 100 / UI_MIN_W, ph * 100 / UI_MIN_H) / UI_SCALE_STEP * UI_SCALE_STEP
	return min(percent, max(room, 100))
}

prefs_path :: proc() -> string {
	return fmt.tprintf("%sscales.cfg", gfx_app_dir())
}

read_file :: proc(path: string) -> (data: []u8, ok: bool) {
	d, err := os.read_entire_file(path, context.allocator)
	return d, err == nil
}

write_file :: proc(path: string, data: []u8) -> bool {
	return os.write_entire_file(path, data) == nil
}

prefs_save :: proc() {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "ui_scale_percent=%d\n", ui_scale_pref)
	fmt.sbprintf(&sb, "groups=%s\n", tool_groups_serialize())
	write_file(prefs_path(), transmute([]u8)strings.to_string(sb))
}

prefs_load :: proc() {
	data, ok := read_file(prefs_path())
	if !ok do return
	defer delete(data)
	prefs_parse(string(data))
}

prefs_parse :: proc(contents: string) {
	text := contents
	for line in strings.split_lines_iterator(&text) {
		eq := strings.index_byte(line, '=')
		if eq < 0 do continue
		key := strings.trim_space(line[:eq])
		sval := strings.trim_space(line[eq + 1:])
		if key == "groups" {
			tool_groups_parse(sval)
			continue
		}
		val, vok := strconv.parse_int(sval)
		if !vok do continue
		switch key {
		case "ui_scale_percent":
			ui_scale_pref = val > 0 ? ui_scale_snap(val) : 0
		case "ui_scale":
			// files from before the slider counted whole multiples
			ui_scale_pref = val > 0 ? ui_scale_snap(val * 100) : 0
		}
	}
}
