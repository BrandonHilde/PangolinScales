package pangolin

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Tiny key=value preferences file stored next to the executable.

ui_scale_pref := 0

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
	fmt.sbprintf(&sb, "ui_scale=%d\n", ui_scale_pref)
	write_file(prefs_path(), transmute([]u8)strings.to_string(sb))
}

prefs_load :: proc() {
	data, ok := read_file(prefs_path())
	if !ok do return
	defer delete(data)
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		eq := strings.index_byte(line, '=')
		if eq < 0 do continue
		key := strings.trim_space(line[:eq])
		val, vok := strconv.parse_int(strings.trim_space(line[eq + 1:]))
		if !vok do continue
		switch key {
		case "ui_scale":
			ui_scale_pref = clamp(val, 0, 4)
		}
	}
}
