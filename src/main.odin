package pangolin

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

choose_scale :: proc() -> i32 {
	if ui_scale_pref > 0 {
		return i32(ui_scale_pref)
	}
	mh := gfx_monitor_height()
	switch {
	case mh >= 2000:
		return 3
	case mh >= 1350:
		return 2
	}
	return 1
}

main :: proc() {
	shot_path := ""
	win_w, win_h := 0, 0
	shot_frame := 8
	demo := false
	args := os.args
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--shot" && i + 1 < len(args):
			shot_path = args[i + 1]
			i += 1
		case a == "--scale" && i + 1 < len(args):
			ui_scale_pref, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--size" && i + 1 < len(args):
			wh := strings.split(args[i + 1], "x", context.temp_allocator)
			if len(wh) == 2 {
				win_w, _ = strconv.parse_int(wh[0])
				win_h, _ = strconv.parse_int(wh[1])
			}
			i += 1
		case a == "--shot-frame" && i + 1 < len(args):
			shot_frame, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--render" && i + 2 < len(args):
			scale := i + 3 < len(args) ? args[i + 3] : "1"
			sc, _ := strconv.parse_f32(scale)
			os.exit(render_cli(args[i + 1], args[i + 2], sc > 0 ? sc : 1))
		case a == "--demo":
			demo = true
		case a == "--selftest":
			os.exit(selftest())
		}
	}

	if !gfx_init(APP_NAME, shot_path != "", win_w, win_h) {
		fmt.eprintln("could not start SDL:", gfx_error())
		os.exit(1)
	}
	defer gfx_shutdown()
	pen_init()
	prefs_load()
	ui.icons = icons_build_atlas()
	brand_init()

	fonts_scan()
	opened := false
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		if strings.has_prefix(a, "--") {
			if a == "--shot" || a == "--scale" || a == "--size" || a == "--shot-frame" || a == "--demo-file" do i += 1
			continue
		}
		open_path(a)
		opened = true
	}
	if !opened do add_doc(doc_new(.Svg, "Untitled", 1024, 768))
	if demo do demo_setup()

	frame_no := 0
	for !want_quit {
		free_all(context.temp_allocator)
		gfx_poll()
		if gfx.quit {
			gfx.quit = false
			want_quit = true
		}

		sw, sh := int(gfx.pw), int(gfx.ph)
		ui.scale = choose_scale()
		for ui.scale > 1 && (sw / int(ui.scale) < 900 || sh / int(ui.scale) < 560) {
			ui.scale -= 1
		}
		gfx_set_scale(ui.scale)
		ui.w, ui.h = max(sw / int(ui.scale), 1), max(sh / int(ui.scale), 1)

		ui_begin_frame()
		ui.input_layer = (dialog.kind != .None ? 2 : 0) + (popup.open ? 1 : 0)
		for p in gfx.dropped do open_path(p)
		shortcuts_update()
		if status_t > 0 do status_t -= ui.dt

		gfx_begin(C_BG)
		main_ui()
		dialogs_run()
		popup_run()
		tooltip_draw()
		if shot_path != "" && frame_no == shot_frame {
			gfx.screenshot = shot_path
		}
		gfx_present()
		ui_end_frame()

		title := fmt.tprintf("%s - %s", doc_display_name(doc), APP_NAME)
		gfx_set_title(title)

		frame_no += 1
		if shot_path != "" && frame_no == shot_frame + 4 do break
	}
	if shot_path == "" do prefs_save()
}
