package pangolin

// Tracing image: a reference picture laid over the page for drawing on top of (View menu). It is not saved.

trace_load :: proc(d: ^Doc) {
	filters := [?]Filter{{"Images", COMMON_IMAGE_PATTERN}, {"All files", "*.*"}}
	path, ok := native_dialog(false, "Tracing image", filters[:], "", "")
	if ok do trace_load_path(d, path)
}

// Makes the image at `path` the tracing image, fitted inside the page with its aspect ratio kept: centered on
// the page, or at `at` (document units) when given.
trace_load_path :: proc(d: ^Doc, path: string, at: Maybe(Vec2) = nil) -> bool {
	data, rok := read_file(path)
	if !rok {
		message("Tracing image", "Could not read the file.")
		return false
	}
	defer delete(data)
	pix, w, h, dok := decode_common_image(data)
	if !dok {
		message("Tracing image", "Unsupported image file.")
		return false
	}
	defer delete(pix)
	tex_destroy(&d.trace)
	d.trace = tex_from_pixels(pix, w, h, .Linear)
	d.trace_s = min(d.w / f32(w), d.h / f32(h))
	center := at.? or_else Vec2{d.w / 2, d.h / 2}
	d.trace_pos = center - Vec2{f32(w), f32(h)} * d.trace_s / 2
	d.trace_a = 0.4
	return true
}

trace_draw :: proc(d: ^Doc, vp: Rect) {
	if !tex_valid(d.trace) do return
	a := to_screen(d, d.trace_pos)
	w, h := f32(d.trace.w) * d.trace_s * d.zoom, f32(d.trace.h) * d.trace_s * d.zoom
	clip_begin(vp)
	draw_tex(d.trace, {0, 0, f32(d.trace.w), f32(d.trace.h)}, {a.x, a.y, w, h}, Color{255, 255, 255, u8(d.trace_a * 255)})
	clip_end()
}
