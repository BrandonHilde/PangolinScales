package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Renders the document into a CPU framebuffer at physical resolution, uploaded as one texture that covers the
// viewport. The render is cached and redone only when the document, the view or the viewport changes.
// ---------------------------------------------------------------------------

Render :: struct {
	r:       Raster,
	fb:      []Color,
	tex:     Texture,
	w, h:    int,
	doc:     ^Doc,
	version: int,
	zoom:    f32,
	ox, oy:  f32,
	scale:   f32,
	valid:   bool,
	tmp:     Polys,
	tmp2:    Polys,
}

rnd: Render

// Document -> screen (logical UI pixels) and back.
to_screen :: proc(d: ^Doc, p: Vec2) -> Vec2 {
	return {d.ox + p.x * d.zoom, d.oy + p.y * d.zoom}
}

to_doc :: proc(d: ^Doc, p: Vec2) -> Vec2 {
	return {(p.x - d.ox) / d.zoom, (p.y - d.oy) / d.zoom}
}

// Renders a document into an arbitrary framebuffer (also used for PNG export).
// `view` maps document space to framebuffer pixels.
render_doc_to :: proc(d: ^Doc, fb: []Color, w, h: int, view: Mat, r: ^Raster, with_page: bool) {
	if with_page {
		page := paint_solid(WHITE)
		segs := Path{}
		defer delete(segs)
		path_rect(&segs, 0, 0, d.w, d.h)
		draw_segs(r, fb, segs[:], view, &page, .Non_Zero, 1)
	}
	render_node(r, fb, d.root, view, 1)
}

draw_segs :: proc(r: ^Raster, fb: []Color, segs: []Seg, m: Mat, paint: ^Paint, rule: Fill_Rule, opacity: f32, local: Mat = MAT_ID) {
	poly: Polys
	defer polys_free(&poly)
	path_flatten(segs, m, 0.1, &poly)
	raster_fill(r, &poly, rule)
	inv, _ := mat_inv(m)
	sh := Shader{paint, inv, opacity}
	raster_composite(r, fb, &sh)
	raster_clear_last(r)
}

render_node :: proc(r: ^Raster, fb: []Color, n: ^Node, parent: Mat, opacity: f32) {
	if !n.visible do return
	m := mat_mul(parent, n.xf)
	op := opacity * n.opacity
	if n.kind == .Group {
		for c in n.children do render_node(r, fb, c, m, op)
		return
	}
	segs := node_render_segs(n)
	if len(segs) == 0 do return
	if n.fill.kind != .None {
		p := n.fill
		draw_segs(r, fb, segs, m, &p, n.even_odd ? .Even_Odd : .Non_Zero, op)
	}
	if n.stroke.kind != .None && n.sw > 0 {
		st := stroke_style_of(n)
		scale := mat_scale_factor(m)
		out: Polys
		defer polys_free(&out)
		stroke_path(segs, st, scale, &out)
		polys_transform(&out, m)
		raster_fill(r, &out, .Non_Zero)
		inv, _ := mat_inv(m)
		p := n.stroke
		sh := Shader{&p, inv, op}
		raster_composite(r, fb, &sh)
		raster_clear_last(r)
	}
}

// Segments drawn for a node: its geometry, or the glyph outlines of a text node.
node_render_segs :: proc(n: ^Node) -> []Seg {
	if n.kind == .Text do return text_segs(n)
	return node_segs(n)
}

// Viewport render -----------------------------------------------------------------------------------------

// `x`, `y`: the logical position of the framebuffer's corner on the screen.
view_matrix :: proc(d: ^Doc, x, y, s: f32) -> Mat {
	return Mat{d.zoom * s, 0, 0, d.zoom * s, (d.ox - x) * s, (d.oy - y) * s}
}

render_viewport :: proc(d: ^Doc, vp: Rect) {
	if vp.w <= 0 || vp.h <= 0 do return
	s := ui.scale
	// the framebuffer covers whole physical pixels, so it maps one to one onto the screen at any scale
	x, y, lw, lh := snap_box(f32(vp.x), f32(vp.y), f32(vp.w), f32(vp.h))
	w, h := int(math.round(lw * s)), int(math.round(lh * s))
	same := rnd.valid && rnd.doc == d && rnd.version == d.version && rnd.zoom == d.zoom && rnd.ox == d.ox && rnd.oy == d.oy && rnd.scale == s && rnd.w == w && rnd.h == h
	if !same {
		if rnd.w != w || rnd.h != h {
			raster_init(&rnd.r, w, h)
			delete(rnd.fb)
			rnd.fb = make([]Color, w * h)
			tex_destroy(&rnd.tex)
			rnd.tex = tex_create(w, h, .Point)
			rnd.w, rnd.h = w, h
		}
		for &c in rnd.fb do c = {}
		render_doc_to(d, rnd.fb, w, h, view_matrix(d, x, y, s), &rnd.r, true)
		tex_update(rnd.tex, rnd.fb)
		rnd.doc, rnd.version, rnd.zoom, rnd.ox, rnd.oy, rnd.scale, rnd.valid = d, d.version, d.zoom, d.ox, d.oy, s, true
	}
	draw_tex(rnd.tex, {0, 0, f32(w), f32(h)}, {x, y, lw, lh})
}

render_invalidate :: proc() {
	rnd.valid = false
}
