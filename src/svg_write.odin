package pangolin

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// SVG writer. Gradients become <linearGradient> / <radialGradient> in <defs> in userSpaceOnUse units.
// ---------------------------------------------------------------------------

Svg_Opts :: struct {
	minify:    bool, // no indentation
	precision: int, // decimals
}

svg_opts := Svg_Opts{false, 3}

fnum :: proc(v: f32) -> string {
	p := svg_opts.precision
	s := fmt.tprintf("%.*f", p, v)
	if strings.index_byte(s, '.') >= 0 {
		s = strings.trim_right(s, "0")
		s = strings.trim_right(s, ".")
	}
	if s == "-0" || s == "" do return "0"
	return s
}

color_hex :: proc(c: Color) -> string {
	return fmt.tprintf("#%02x%02x%02x", c.r, c.g, c.b)
}

xml_escape :: proc(sb: ^strings.Builder, s: string) {
	for ch in s {
		switch ch {
		case '&': strings.write_string(sb, "&amp;")
		case '<': strings.write_string(sb, "&lt;")
		case '>': strings.write_string(sb, "&gt;")
		case '"': strings.write_string(sb, "&quot;")
		case:     strings.write_rune(sb, ch)
		}
	}
}

path_data :: proc(segs: []Seg) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for g, i in segs {
		if i > 0 do strings.write_byte(&sb, ' ')
		switch g.kind {
		case .Move:  fmt.sbprintf(&sb, "M%s %s", fnum(g.p.x), fnum(g.p.y))
		case .Line:  fmt.sbprintf(&sb, "L%s %s", fnum(g.p.x), fnum(g.p.y))
		case .Quad:  fmt.sbprintf(&sb, "Q%s %s %s %s", fnum(g.c1.x), fnum(g.c1.y), fnum(g.p.x), fnum(g.p.y))
		case .Cubic: fmt.sbprintf(&sb, "C%s %s %s %s %s %s", fnum(g.c1.x), fnum(g.c1.y), fnum(g.c2.x), fnum(g.c2.y), fnum(g.p.x), fnum(g.p.y))
		case .Close: strings.write_byte(&sb, 'Z')
		}
	}
	return strings.to_string(sb)
}

xf_attr :: proc(m: Mat) -> string {
	if mat_is_identity(m) do return ""
	if m.a == 1 && m.b == 0 && m.c == 0 && m.d == 1 {
		return fmt.tprintf(" transform=\"translate(%s %s)\"", fnum(m.e), fnum(m.f))
	}
	// matrix needs more precision than coordinates
	save := svg_opts.precision
	svg_opts.precision = max(save, 5)
	s := fmt.tprintf(" transform=\"matrix(%s %s %s %s %s %s)\"", fnum(m.a), fnum(m.b), fnum(m.c), fnum(m.d), fnum(m.e), fnum(m.f))
	svg_opts.precision = save
	return s
}

write_gradient :: proc(defs: ^strings.Builder, id: string, p: ^Paint) {
	nl := svg_opts.minify ? "" : "\n"
	if p.kind == .Linear {
		fmt.sbprintf(defs, "    <linearGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"", id, fnum(p.p0.x), fnum(p.p0.y), fnum(p.p1.x), fnum(p.p1.y))
	} else {
		fmt.sbprintf(defs, "    <radialGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" cx=\"%s\" cy=\"%s\" r=\"%s\"", id, fnum(p.p0.x), fnum(p.p0.y), fnum(p.p1.x))
	}
	switch p.spread {
	case 1: strings.write_string(defs, " spreadMethod=\"reflect\"")
	case 2: strings.write_string(defs, " spreadMethod=\"repeat\"")
	}
	strings.write_string(defs, ">")
	strings.write_string(defs, nl)
	for i in 0 ..< p.nstops {
		s := p.stops[i]
		fmt.sbprintf(defs, "      <stop offset=\"%s\" stop-color=\"%s\"", fnum(s.t), color_hex(s.color))
		if s.color.a != 255 do fmt.sbprintf(defs, " stop-opacity=\"%s\"", fnum(f32(s.color.a) / 255))
		strings.write_string(defs, "/>")
		strings.write_string(defs, nl)
	}
	strings.write_string(defs, p.kind == .Linear ? "    </linearGradient>" : "    </radialGradient>")
	strings.write_string(defs, nl)
}

paint_attr :: proc(sb, defs: ^strings.Builder, attr: string, p: ^Paint, id: string, default_none: bool) {
	switch p.kind {
	case .None:
		if !default_none do fmt.sbprintf(sb, " %s=\"none\"", attr)
	case .Solid:
		fmt.sbprintf(sb, " %s=\"%s\"", attr, color_hex(p.color))
		if p.color.a != 255 do fmt.sbprintf(sb, " %s-opacity=\"%s\"", attr, fnum(f32(p.color.a) / 255))
	case .Linear, .Radial:
		write_gradient(defs, id, p)
		fmt.sbprintf(sb, " %s=\"url(#%s)\"", attr, id)
	}
}

valid_id :: proc(s: string) -> bool {
	if len(s) == 0 do return false
	for ch, i in s {
		ok := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' || (i > 0 && ((ch >= '0' && ch <= '9') || ch == '-' || ch == '.'))
		if !ok do return false
	}
	return true
}

default_names := [?]string{"Group", "Path", "Rectangle", "Ellipse", "Text", "Line", "Polygon", "Polyline", "Outlines", "Use"}

// An object's name is saved as its id. An id can't hold every name: it has limits on its characters, so a name like
// "Layer 1" goes in data-pangolin-name alone. It also appears only once in a file, but names repeat, because a new
// frame and Duplicate copy them: a repeat gets a free id (Ball-2) and keeps its name in data-pangolin-name. `used_ids`
// counts what each id has been used for, so many copies of a name don't each search from the start.
write_name :: proc(attrs: ^strings.Builder, name: string, used_ids: ^map[string]int) {
	if name == "" do return
	for dn in default_names {
		if dn == name do return
	}
	if !valid_id(name) {
		strings.write_string(attrs, " data-pangolin-name=\"")
		xml_escape(attrs, name)
		strings.write_byte(attrs, '"')
		return
	}
	id := name
	if count := used_ids[name]; count > 0 {
		i := count + 1
		for {
			id = fmt.tprintf("%s-%d", name, i)
			if used_ids[id] == 0 do break
			i += 1
		}
		used_ids[strings.clone(name, context.temp_allocator)] = i
	}
	used_ids[strings.clone(id, context.temp_allocator)] = 1
	fmt.sbprintf(attrs, " id=\"%s\"", id)
	if id != name do fmt.sbprintf(attrs, " data-pangolin-name=\"%s\"", name)
}

write_node :: proc(sb, defs: ^strings.Builder, n: ^Node, depth: int, used_ids: ^map[string]int) {
	if !n.visible && n.kind != .Group {
		// hidden objects are kept, flagged with display="none"
	}
	ind := svg_opts.minify ? "" : strings.repeat("  ", depth + 1, context.temp_allocator)
	nl := svg_opts.minify ? "" : "\n"
	strings.write_string(sb, ind)
	attrs := strings.builder_make(context.temp_allocator)
	write_name(&attrs, name_str(&n.name), used_ids)
	strings.write_string(&attrs, xf_attr(n.xf))
	if n.opacity < 1 do fmt.sbprintf(&attrs, " opacity=\"%s\"", fnum(n.opacity))
	if !n.visible do strings.write_string(&attrs, " display=\"none\"")
	if n.locked do strings.write_string(&attrs, " data-pangolin-locked=\"true\"")
	if n.kind == .Group {
		fmt.sbprintf(sb, "<g%s>%s", strings.to_string(attrs), nl)
		for c in n.children do write_node(sb, defs, c, depth + 1, used_ids)
		fmt.sbprintf(sb, "%s</g>%s", ind, nl)
		return
	}
	// style
	gid := fmt.tprintf("g%d", n.uid)
	paint_attr(&attrs, defs, "fill", &n.fill, fmt.tprintf("%sf", gid), false)
	if n.fill.kind == .None && false do strings.write_string(&attrs, "")
	paint_attr(&attrs, defs, "stroke", &n.stroke, fmt.tprintf("%ss", gid), true)
	if n.stroke.kind != .None {
		if n.sw != 1 do fmt.sbprintf(&attrs, " stroke-width=\"%s\"", fnum(n.sw))
		switch n.cap {
		case .Round:  strings.write_string(&attrs, " stroke-linecap=\"round\"")
		case .Square: strings.write_string(&attrs, " stroke-linecap=\"square\"")
		case .Butt:
		}
		switch n.join {
		case .Round: strings.write_string(&attrs, " stroke-linejoin=\"round\"")
		case .Bevel: strings.write_string(&attrs, " stroke-linejoin=\"bevel\"")
		case .Miter:
		}
		if n.join == .Miter && n.miter != 4 do fmt.sbprintf(&attrs, " stroke-miterlimit=\"%s\"", fnum(n.miter))
		if n.ndash > 0 {
			strings.write_string(&attrs, " stroke-dasharray=\"")
			for i in 0 ..< n.ndash {
				if i > 0 do strings.write_byte(&attrs, ' ')
				strings.write_string(&attrs, fnum(n.dash[i]))
			}
			strings.write_byte(&attrs, '"')
			if n.dash_off != 0 do fmt.sbprintf(&attrs, " stroke-dashoffset=\"%s\"", fnum(n.dash_off))
		}
	}
	if n.even_odd do strings.write_string(&attrs, " fill-rule=\"evenodd\"")
	a := strings.to_string(attrs)
	switch n.kind {
	case .Path:
		fmt.sbprintf(sb, "<path d=\"%s\"%s/>%s", path_data(n.segs[:]), a, nl)
	case .Rect:
		fmt.sbprintf(sb, "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\"", fnum(n.x), fnum(n.y), fnum(n.w), fnum(n.h))
		if n.rx > 0 do fmt.sbprintf(sb, " rx=\"%s\"", fnum(n.rx))
		if n.ry > 0 && n.ry != n.rx do fmt.sbprintf(sb, " ry=\"%s\"", fnum(n.ry))
		fmt.sbprintf(sb, "%s/>%s", a, nl)
	case .Ellipse:
		if n.w == n.h {
			fmt.sbprintf(sb, "<circle cx=\"%s\" cy=\"%s\" r=\"%s\"%s/>%s", fnum(n.x), fnum(n.y), fnum(n.w), a, nl)
		} else {
			fmt.sbprintf(sb, "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"%s/>%s", fnum(n.x), fnum(n.y), fnum(n.w), fnum(n.h), a, nl)
		}
	case .Text:
		fmt.sbprintf(sb, "<text x=\"%s\" y=\"%s\" font-family=\"%s\" font-size=\"%s\"%s>", fnum(n.x), fnum(n.y), name_str(&n.font), fnum(n.size), a)
		lines := strings.split(text_str(n), "\n", context.temp_allocator)
		for l, i in lines {
			if i == 0 {
				xml_escape(sb, l)
			} else {
				fmt.sbprintf(sb, "<tspan x=\"%s\" dy=\"1.2em\">", fnum(n.x))
				xml_escape(sb, l)
				strings.write_string(sb, "</tspan>")
			}
		}
		fmt.sbprintf(sb, "</text>%s", nl)
	case .Group:
	}
}

// Each frame is a top-level group. Frames after the first are hidden, so a viewer without animation shows frame 1,
// and a discrete <animate> in each makes the file play in a browser.
write_frames :: proc(d: ^Doc, body, defs: ^strings.Builder, used: ^map[string]int) {
	nl := svg_opts.minify ? "" : "\n"
	ind := svg_opts.minify ? "" : "  "
	inner := svg_opts.minify ? "" : "    "
	total := 0
	for f in d.frames do total += max(f.duration, 10)
	at := 0
	n := len(d.frames)
	for f, i in d.frames {
		dur := max(f.duration, 10)
		t0, t1 := f64(at) / f64(total), f64(at + dur) / f64(total)
		values, times: string
		// the times need more decimals than coordinates: a short frame in a long animation must keep its own time
		switch {
		case i == 0:
			values, times = "inline;none", fmt.tprintf("0;%.6f", t1)
		case i == n - 1:
			values, times = "none;inline", fmt.tprintf("0;%.6f", t0)
		case:
			values, times = "none;inline;none", fmt.tprintf("0;%.6f;%.6f", t0, t1)
		}
		fmt.sbprintf(body, "%s<g data-pangolin-frame=\"%d\"%s>%s", ind, f.duration, i > 0 ? " display=\"none\"" : "", nl)
		fmt.sbprintf(body, "%s<animate attributeName=\"display\" values=\"%s\" keyTimes=\"%s\" calcMode=\"discrete\" dur=\"%dms\" repeatCount=\"indefinite\"/>%s", inner, values, times, total, nl)
		for c in frame_root(d, i).children do write_node(body, defs, c, 1, used)
		fmt.sbprintf(body, "%s</g>%s", ind, nl)
		at += dur
	}
}

// The tags as an attribute of the svg element: name:from:to:direction:color, separated by ;
tags_attr :: proc(d: ^Doc) -> string {
	if len(d.frames) < 2 || len(d.tags) == 0 do return ""
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, " data-pangolin-tags=\"")
	for &t, i in d.tags {
		if i > 0 do strings.write_byte(&sb, ';')
		xml_escape(&sb, group_clean_name(name_str(&t.name)))
		fmt.sbprintf(&sb, ":%d:%d:%d:%02x%02x%02x", t.from, t.to, int(t.dir), t.color.r, t.color.g, t.color.b)
	}
	strings.write_byte(&sb, '"')
	return strings.to_string(sb)
}

svg_string :: proc(d: ^Doc) -> string {
	out := strings.builder_make(context.temp_allocator)
	body := strings.builder_make(context.temp_allocator)
	defs := strings.builder_make(context.temp_allocator)
	used := make(map[string]int, 16, context.temp_allocator)
	nl := svg_opts.minify ? "" : "\n"
	if len(d.frames) > 1 {
		write_frames(d, &body, &defs, &used)
	} else {
		for c in d.root.children do write_node(&body, &defs, c, 0, &used)
	}
	fmt.sbprintf(&out, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%s\" height=\"%s\" viewBox=\"0 0 %s %s\"%s>%s", fnum(d.w), fnum(d.h), fnum(d.w), fnum(d.h), tags_attr(d), nl)
	if strings.builder_len(defs) > 0 {
		fmt.sbprintf(&out, "  <defs>%s%s  </defs>%s", nl, strings.to_string(defs), nl)
	}
	strings.write_string(&out, strings.to_string(body))
	strings.write_string(&out, "</svg>\n")
	return strings.to_string(out)
}

svg_save :: proc(d: ^Doc, path: string) -> bool {
	s := svg_string(d)
	return write_file(path, transmute([]u8)s)
}

// Renders the document at `scale` into RGBA pixels (transparent background unless `with_bg`): the live frame, or
// frame number `frame`.
render_to_pixels :: proc(d: ^Doc, scale: f32, bg: Color, with_bg: bool, frame := -1) -> (pix: []Color, w, h: int) {
	w = max(int(d.w * scale + 0.5), 1)
	h = max(int(d.h * scale + 0.5), 1)
	pix = make([]Color, w * h, context.temp_allocator)
	if with_bg do for &c in pix do c = bg
	r: Raster
	raster_init(&r, w, h)
	defer raster_free(&r)
	render_doc_to(d, pix, w, h, mat_scale(scale, scale), &r, false, frame >= 0 ? frame_root(d, frame) : nil)
	return
}

png_save :: proc(d: ^Doc, path: string, scale: f32, with_bg: bool) -> bool {
	pix, w, h := render_to_pixels(d, scale, WHITE, with_bg)
	data := encode_png(pix, w, h)
	return write_file(path, data)
}
