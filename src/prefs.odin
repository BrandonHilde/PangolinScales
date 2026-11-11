package pangolin

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Tiny key=value preferences file, in the user's data folder (gfx_data_dir: next to the program
// when that can be written).

prefs_path :: proc() -> string {
	return fmt.tprintf("%sscales.cfg", gfx_data_dir())
}

prefs_save :: proc() {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "ui_scale=%d\n", ui_scale_pref)
	fmt.sbprintf(&sb, "groups=%s\n", tool_groups_serialize())
	fmt.sbprintf(&sb, "onion=%d\nonion_prev=%d\nonion_next=%d\nonion_alpha=%d\n", onion ? 1 : 0, onion_prev, onion_next, onion_alpha)
	fmt.sbprintf(&sb, "navigator=%d\n", show_navigator ? 1 : 0)
	fmt.sbprintf(&sb, "eraser_size=%d\neraser_pressure=%d\n", eraser_size, eraser_pressure ? 1 : 0)
	fmt.sbprintf(&sb, "sculpt_size=%d\nsculpt_strength=%d\nsculpt_pressure=%d\n", sculpt_size, sculpt_strength, sculpt_pressure ? 1 : 0)
	fmt.sbprintf(&sb, "eraser_preset=%s\nsculpt_preset=%s\n", name_str(&eraser_preset), name_str(&sculpt_preset))
	files_prefs_write(&sb)
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
		if files_prefs_read(key, sval) do continue
		if key == "eraser_preset" || key == "sculpt_preset" {
			name_set(key == "eraser_preset" ? &eraser_preset : &sculpt_preset, sval)
			continue
		}
		val, vok := strconv.parse_int(sval)
		if !vok do continue
		switch key {
		case "ui_scale_percent", "ui_scale":
			ui_scale_pref = ui_scale_parse(val)
		case "onion":
			onion = val != 0
		case "onion_prev":
			onion_prev = clamp(val, 0, 5)
		case "onion_next":
			onion_next = clamp(val, 0, 5)
		case "onion_alpha":
			onion_alpha = clamp(val, 5, 100)
		case "navigator":
			show_navigator = val != 0
		case "eraser_size":
			eraser_size = clamp(val, ERASER_SIZE_MIN, ERASER_SIZE_MAX)
		case "eraser_pressure":
			eraser_pressure = val != 0
		case "sculpt_size":
			sculpt_size = clamp(val, SCULPT_SIZE_MIN, SCULPT_SIZE_MAX)
		case "sculpt_strength":
			sculpt_strength = clamp(val, 5, 100)
		case "sculpt_pressure":
			sculpt_pressure = val != 0
		}
	}
}
