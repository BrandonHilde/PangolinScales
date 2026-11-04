package pangolin

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

main :: proc() {
	shot_path := ""
	win_w, win_h := 0, 0
	shot_frame := 8
	demo := false
	menu_arg := -1
	Script_Click :: struct {
		frame: int,
		pos:   Vec2,
		btn:   int,
	}
	Script_Drag :: struct {
		frame: int,
		a, b:  Vec2,
	}
	clicks := make([dynamic]Script_Click)
	drags := make([dynamic]Script_Drag)
	hover: Script_Click // moves the pointer without clicking, for checking tooltips with --shot
	args := os.args
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--shot" && i + 1 < len(args):
			shot_path = args[i + 1]
			i += 1
		case a == "--scale" && i + 1 < len(args):
			if v, ok := strconv.parse_int(args[i + 1]); ok && v > 0 do ui_scale_arg = ui_scale_parse(v)
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
		case a == "--clicks" && i + 1 < len(args):
			// "frame:x,y;frame:x,y": left clicks in window pixels (frame:x,y,r for a right click),
			// for checking the interface with --shot
			for part in strings.split(args[i + 1], ";", context.temp_allocator) {
				fp := strings.split(part, ":", context.temp_allocator)
				if len(fp) != 2 do continue
				xy := strings.split(fp[1], ",", context.temp_allocator)
				if len(xy) < 2 do continue
				f, _ := strconv.parse_int(fp[0])
				x, _ := strconv.parse_f32(xy[0])
				y, _ := strconv.parse_f32(xy[1])
				append(&clicks, Script_Click{f, {x, y}, len(xy) > 2 && xy[2] == "r" ? 1 : 0})
			}
			i += 1
		case a == "--drag" && i + 1 < len(args):
			// "frame:x0,y0,x1,y1;...": a left drag in window pixels over 8 frames
			for part in strings.split(args[i + 1], ";", context.temp_allocator) {
				fp := strings.split(part, ":", context.temp_allocator)
				if len(fp) != 2 do continue
				v := strings.split(fp[1], ",", context.temp_allocator)
				if len(v) != 4 do continue
				f, _ := strconv.parse_int(fp[0])
				x0, _ := strconv.parse_f32(v[0])
				y0, _ := strconv.parse_f32(v[1])
				x1, _ := strconv.parse_f32(v[2])
				y1, _ := strconv.parse_f32(v[3])
				append(&drags, Script_Drag{f, {x0, y0}, {x1, y1}})
			}
			i += 1
		case a == "--hover" && i + 1 < len(args):
			// "frame:x,y": from that frame on, the pointer rests there
			fp := strings.split(args[i + 1], ":", context.temp_allocator)
			if len(fp) == 2 {
				xy := strings.split(fp[1], ",", context.temp_allocator)
				if len(xy) == 2 {
					hover.frame, _ = strconv.parse_int(fp[0])
					hover.pos.x, _ = strconv.parse_f32(xy[0])
					hover.pos.y, _ = strconv.parse_f32(xy[1])
				}
			}
			i += 1
		case a == "--menu" && i + 1 < len(args):
			menu_arg, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--icon-sheet" && i + 1 < len(args):
			os.exit(icon_sheet(args[i + 1]))
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
	tool_groups_default()
	prefs_load()
	brand_init()
	oui_init()
	panels_init()

	fonts_scan()
	opened := false
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		if strings.has_prefix(a, "--") {
			if a == "--shot" || a == "--scale" || a == "--size" || a == "--shot-frame" || a == "--demo-file" || a == "--clicks" || a == "--drag" || a == "--hover" || a == "--menu" do i += 1
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
		for c in clicks {
			switch frame_no {
			case c.frame - 2 ..< c.frame:
				gfx.mouse = c.pos
			case c.frame:
				gfx.mouse = c.pos
				gfx.m_pressed[c.btn], gfx.m_down[c.btn] = true, true
			case c.frame + 1:
				gfx.mouse = c.pos
				gfx.m_released[c.btn], gfx.m_down[c.btn] = true, false
			}
		}
		for dr in drags {
			STEPS :: 8
			at := frame_no - dr.frame
			if at < -2 || at > STEPS do continue
			gfx.mouse = dr.a + (dr.b - dr.a) * (f32(clamp(at, 0, STEPS)) / STEPS)
			if at == 0 do gfx.m_pressed[0], gfx.m_down[0] = true, true
			if at == STEPS do gfx.m_released[0], gfx.m_down[0] = true, false
		}
		if hover.frame > 0 && frame_no >= hover.frame do gfx.mouse = hover.pos
		if gfx.quit {
			gfx.quit = false
			want_quit = true
		}

		sw, sh := int(gfx.pw), int(gfx.ph)
		scale := f32(ui_scale_wanted()) / 100
		if ui.scale > 0 && scale != ui.scale do views_keep_on_screen(ui.scale, scale)
		ui.scale = scale
		gfx_set_scale(ui.scale)
		ui.w, ui.h = max(int(f32(sw) / ui.scale), 1), max(int(f32(sh) / ui.scale), 1)

		ui_begin_frame()
		ui.input_layer = (dialog.kind != .None ? 2 : 0) + (popup.open ? 1 : 0)
		for p in gfx.dropped do open_path(p)
		shortcuts_update()
		playback_update(ui.dt)
		if status_t > 0 do status_t -= ui.dt
		if menu_arg >= 0 && frame_no == 3 do menu_request = menu_arg

		gfx_begin(C_BG)
		oui_begin_frame()
		main_ui()
		oui_end_frame()
		oui_render()
		dialogs_run()
		dialog_frame_end()
		popup_run()
		files_drag_run()
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
