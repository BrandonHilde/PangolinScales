package pangolin

import "core:fmt"

// Node macros. The graph, file format and interpreter are shared (shared_macro.odin, shared_macro_io.odin);
// this file is the app's side of it. Pangolin Scales has no macro nodes yet: see PangolinShared/MacroPlan.md.

macro_app_id :: proc() -> string {
	return "scales"
}

macro_catalogue :: proc() -> []Macro_Def {
	return nil
}

macro_exec :: proc(def: ^Macro_Def, args: []Macro_Value) -> (ok: bool, msg: string) {
	return false, "Pangolin Scales has no macro nodes yet"
}

macro_begin :: proc() -> (ok: bool, msg: string) {
	return false, "Pangolin Scales can't run macros yet"
}

macro_end :: proc(keep: bool) {}

macro_dir :: proc() -> string {
	return fmt.tprintf("%smacros/", gfx_data_dir())
}

macro_info :: proc(what: int) -> f64 {
	return 0
}

macro_preview :: proc(r: Rect) {
	ctl_well(r)
}

macro_renamed :: proc(old, new: string) {}

macro_snapshot :: proc() -> rawptr {
	return nil
}

macro_restore :: proc(snap: rawptr) {}

macro_snapshot_free :: proc(snap: rawptr) {}

macro_suggest :: proc(what: string) -> []string {
	return nil
}
