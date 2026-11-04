package pangolin

import "core:fmt"
import stbtt "vendor:stb/truetype"

// What the shared file browser (shared_files.odin) needs to know about Scales: SVG drawings, fonts and images.
// A drawing adds its objects where it is dropped, a font opens, and an image becomes the tracing image.

FILES_HINT :: "Drag an SVG onto the canvas to add its objects, or onto the tab bar to open it. An image becomes the tracing image."

files_listed :: proc(name: string) -> bool {
	ext := lower_ext(name)
	return ext == ".svg" || is_font_ext(ext) || is_common_image_ext(ext)
}

is_font_ext :: proc(ext: string) -> bool {
	return ext == ".ttf" || ext == ".otf"
}

// SVG parsing and text rendering use globals (svg_skipped, ufonts).
files_preview_on_main :: proc(path: string) -> bool {
	return lower_ext(path) == ".svg"
}

bottom_has_timeline :: proc() -> bool {
	return doc != nil && doc.kind == .Svg
}

// The result is heap allocated: the browser frees it. Everything but SVG runs on the browser's worker thread.
files_preview :: proc(path: string) -> (pix: []Color, w, h: int, ok: bool) {
	ext := lower_ext(path)
	switch {
	case ext == ".svg":
		return svg_preview(path)
	case is_font_ext(ext):
		return font_preview_file(path)
	}
	data, rok := read_file(path)
	if !rok do return
	defer delete(data)
	return decode_common_image(data)
}

@(private = "file")
svg_preview :: proc(path: string) -> (pix: []Color, w, h: int, ok: bool) {
	d, lok := svg_load(path)
	if !lok do return
	defer doc_free(d)
	// fitted to the thumbnail both ways: a vector drawing is as sharp at any size
	scale := f32(THUMB_MAX) / max(d.w, d.h, 1)
	tmp: []Color
	tmp, w, h = render_to_pixels(d, scale, WHITE, true)
	pix = make([]Color, len(tmp))
	copy(pix, tmp)
	return pix, w, h, true
}

// "Aa" black on white. Uses no shared state, so it is safe on the worker thread.
@(private = "file")
font_preview_file :: proc(path: string) -> (pix: []Color, w, h: int, ok: bool) {
	data, rok := read_file(path)
	if !rok do return
	defer delete(data)
	info: stbtt.fontinfo
	offset := stbtt.GetFontOffsetForIndex(raw_data(data), 0)
	if offset < 0 || !stbtt.InitFont(&info, raw_data(data), offset) do return
	SIZE :: 128
	w, h = SIZE, SIZE
	pix = make([]Color, SIZE * SIZE)
	for &p in pix do p = WHITE
	scale := stbtt.ScaleForPixelHeight(&info, SIZE * 0.72)
	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&info, &asc, &desc, &gap)
	baseline := SIZE / 2 + i32(f32(asc + desc) * scale / 2)
	adv_a, adv_b, lsb: i32
	stbtt.GetCodepointHMetrics(&info, 'A', &adv_a, &lsb)
	stbtt.GetCodepointHMetrics(&info, 'a', &adv_b, &lsb)
	pen := (SIZE - f32(adv_a + adv_b) * scale) / 2
	for cp, i in ([?]rune{'A', 'a'}) {
		gw, gh, xoff, yoff: i32
		bm := stbtt.GetCodepointBitmap(&info, 0, scale, cp, &gw, &gh, &xoff, &yoff)
		if bm != nil {
			defer stbtt.FreeBitmap(bm, nil)
			ox, oy := i32(pen) + xoff, baseline + yoff
			for y in 0 ..< gh {
				for x in 0 ..< gw {
					px, py := ox + x, oy + y
					if px < 0 || py < 0 || px >= SIZE || py >= SIZE do continue
					v := 255 - bm[y * gw + x]
					pix[py * SIZE + px] = Color{v, v, v, 255}
				}
			}
		}
		pen += f32(i == 0 ? adv_a : adv_b) * scale
	}
	return pix, w, h, true
}

files_drop_hint :: proc(path: string, on_tabs: bool) -> string {
	ext := lower_ext(path)
	switch {
	case ext == ".svg":
		return on_tabs ? "Open this drawing in a new tab" : "Add this drawing's objects here"
	case is_font_ext(ext):
		return "Open this font in a new tab"
	case is_common_image_ext(ext):
		if doc == nil do return ""
		return on_tabs ? "Use as the tracing image, fitted to the page" : "Use as the tracing image, centered here"
	}
	return ""
}

files_drop :: proc(path: string, on_tabs: bool) {
	ext := lower_ext(path)
	switch {
	case ext == ".svg":
		if on_tabs {
			open_path(path)
		} else {
			doc_add_svg_file(doc, path, to_doc(doc, {f32(ui.mx), f32(ui.my)}))
		}
	case is_font_ext(ext):
		open_path(path)
	case is_common_image_ext(ext):
		if on_tabs {
			trace_load_path(doc, path)
		} else {
			trace_load_path(doc, path, to_doc(doc, {f32(ui.mx), f32(ui.my)}))
		}
	}
}

// Adds a drawing's objects to the document, centered at `center` and selected, as one undo step.
doc_add_svg_file :: proc(d: ^Doc, path: string, center: Vec2) {
	src, ok := svg_load(path)
	if !ok {
		message("Add drawing", fmt.tprintf("Could not read %s as an SVG file.", path_basename(path)))
		return
	}
	defer doc_free(src)
	tools_cancel()
	if doc_add_objects(d, src.root.children[:]) == 0 {
		set_status("That drawing has no objects to add")
		return
	}
	sel_center_at(d, center)
	doc_changed(d)
}

// No preview on the canvas: the thumbnail follows the pointer.
files_ghost :: proc(thumb: Texture, img_w, img_h: int) -> bool {
	return false
}
