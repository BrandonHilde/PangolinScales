package pangolin

// Tracing image: a reference picture laid over the page for drawing on top of (View menu). It is not saved.

trace_load :: proc(d: ^Doc) {
	filters := [?]Filter{{"Images", "*.png;*.jpg;*.jpeg;*.bmp;*.tga;*.gif"}, {"All files", "*.*"}}
	path, ok := native_dialog(false, "Tracing image", filters[:], "", "")
	if !ok do return
	data, rok := read_file(path)
	if !rok {
		message("Tracing image", "Could not read the file.")
		return
	}
	defer delete(data)
	pix, w, h, dok := stb_decode(data)
	if !dok {
		message("Tracing image", "Unsupported image file.")
		return
	}
	tex_destroy(&d.trace)
	d.trace = tex_from_pixels(pix, w, h, .Linear)
	// fit inside the page, keeping the aspect ratio
	d.trace_s = min(d.w / f32(w), d.h / f32(h))
	d.trace_pos = {(d.w - f32(w) * d.trace_s) / 2, (d.h - f32(h) * d.trace_s) / 2}
	d.trace_a = 0.4
}

trace_draw :: proc(d: ^Doc, vp: Rect) {
	if !tex_valid(d.trace) do return
	a := to_screen(d, d.trace_pos)
	w, h := f32(d.trace.w) * d.trace_s * d.zoom, f32(d.trace.h) * d.trace_s * d.zoom
	clip_begin(vp)
	draw_tex(d.trace, {0, 0, f32(d.trace.w), f32(d.trace.h)}, {a.x, a.y, w, h}, Color{255, 255, 255, u8(d.trace_a * 255)})
	clip_end()
}
