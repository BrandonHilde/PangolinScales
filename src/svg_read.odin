package pangolin

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

// ---------------------------------------------------------------------------
// SVG reader. Supported: svg, g, path, rect, circle, ellipse, line, polyline, polygon, text / tspan, use, defs,
// symbol, linear / radial gradients, transforms, inline style, a basic <style> sheet (tag, .class, #id), colors
// in all common notations. Unsupported elements (filters, masks, clip paths, images, patterns) are skipped
// and counted in `svg_skipped`.
// ---------------------------------------------------------------------------

svg_skipped: [dynamic]string

Css_Rule :: struct {
	sel:   string,
	decls: [dynamic]XAttr,
}

Svg_Ctx :: struct {
	d:       ^Doc,
	ids:     map[string]^XNode,
	rules:   [dynamic]Css_Rule,
	use_depth: int,
}

// Style that is inherited down the tree.
Rstyle :: struct {
	fill:         string,
	stroke:       string,
	fill_op:      f32,
	stroke_op:    f32,
	sw:           f32,
	cap:          Cap,
	join:         Join,
	miter:        f32,
	dash:         string,
	dash_off:     f32,
	even_odd:     bool,
	font:         string,
	size:         f32,
	color:        Color,
}

rstyle_default :: proc() -> Rstyle {
	return Rstyle{fill = "black", stroke = "none", fill_op = 1, stroke_op = 1, sw = 1, miter = 4, size = 16, color = {0, 0, 0, 255}}
}

// Number parsing --------------------------------------------------------------------------------------------

// Parses a number at the start of s; returns the value and the rest. Handles "1e-3", ".5", "-.5.5".
scan_num :: proc(s: string) -> (v: f32, rest: string, ok: bool) {
	i := 0
	n := len(s)
	for i < n && (is_space(s[i]) || s[i] == ',') do i += 1
	st := i
	if i < n && (s[i] == '+' || s[i] == '-') do i += 1
	digits := 0
	for i < n && s[i] >= '0' && s[i] <= '9' {
		i += 1
		digits += 1
	}
	if i < n && s[i] == '.' {
		i += 1
		for i < n && s[i] >= '0' && s[i] <= '9' {
			i += 1
			digits += 1
		}
	}
	if digits == 0 do return 0, s, false
	if i < n && (s[i] == 'e' || s[i] == 'E') {
		j := i + 1
		if j < n && (s[j] == '+' || s[j] == '-') do j += 1
		if j < n && s[j] >= '0' && s[j] <= '9' {
			for j < n && s[j] >= '0' && s[j] <= '9' do j += 1
			i = j
		}
	}
	f, pok := strconv.parse_f32(s[st:i])
	if !pok do return 0, s, false
	return f, s[i:], true
}

// Length with optional unit -> user units.
parse_length :: proc(s: string, def: f32 = 0, pct_of: f32 = 0) -> f32 {
	v, rest, ok := scan_num(strings.trim_space(s))
	if !ok do return def
	u := strings.trim_space(rest)
	switch u {
	case "px", "":
	case "pt": v *= 4.0 / 3.0
	case "pc": v *= 16
	case "mm": v *= 96 / 25.4
	case "cm": v *= 96 / 2.54
	case "in": v *= 96
	case "em": v *= 16
	case "%":  v = v / 100 * pct_of
	}
	return v
}

parse_num_list :: proc(s: string) -> []f32 {
	out := make([dynamic]f32, context.temp_allocator)
	rest := s
	for {
		v, r, ok := scan_num(rest)
		if !ok do break
		append(&out, v)
		rest = r
	}
	return out[:]
}

// Colors ---------------------------------------------------------------------------------------------------

NAMED_COLORS := [?]struct {
	n: string,
	c: u32,
}{
	{"black", 0x000000}, {"white", 0xffffff}, {"red", 0xff0000}, {"green", 0x008000}, {"blue", 0x0000ff},
	{"yellow", 0xffff00}, {"cyan", 0x00ffff}, {"aqua", 0x00ffff}, {"magenta", 0xff00ff}, {"fuchsia", 0xff00ff},
	{"gray", 0x808080}, {"grey", 0x808080}, {"silver", 0xc0c0c0}, {"maroon", 0x800000}, {"olive", 0x808000},
	{"lime", 0x00ff00}, {"teal", 0x008080}, {"navy", 0x000080}, {"purple", 0x800080}, {"orange", 0xffa500},
	{"pink", 0xffc0cb}, {"brown", 0xa52a2a}, {"gold", 0xffd700}, {"indigo", 0x4b0082}, {"violet", 0xee82ee},
	{"coral", 0xff7f50}, {"salmon", 0xfa8072}, {"khaki", 0xf0e68c}, {"crimson", 0xdc143c}, {"turquoise", 0x40e0d0},
	{"tan", 0xd2b48c}, {"beige", 0xf5f5dc}, {"ivory", 0xfffff0}, {"lavender", 0xe6e6fa}, {"orchid", 0xda70d6},
	{"plum", 0xdda0dd}, {"sienna", 0xa0522d}, {"skyblue", 0x87ceeb}, {"steelblue", 0x4682b4}, {"tomato", 0xff6347},
	{"wheat", 0xf5deb3}, {"darkgray", 0xa9a9a9}, {"darkgrey", 0xa9a9a9}, {"lightgray", 0xd3d3d3}, {"lightgrey", 0xd3d3d3},
	{"darkgreen", 0x006400}, {"darkblue", 0x00008b}, {"darkred", 0x8b0000}, {"lightblue", 0xadd8e6}, {"lightgreen", 0x90ee90},
	{"dimgray", 0x696969}, {"dimgrey", 0x696969}, {"slategray", 0x708090}, {"slategrey", 0x708090}, {"chocolate", 0xd2691e},
	{"firebrick", 0xb22222}, {"forestgreen", 0x228b22}, {"hotpink", 0xff69b4}, {"limegreen", 0x32cd32}, {"midnightblue", 0x191970},
	{"royalblue", 0x4169e1}, {"seagreen", 0x2e8b57}, {"darkorange", 0xff8c00}, {"deepskyblue", 0x00bfff}, {"gainsboro", 0xdcdcdc},
}

hex_val :: proc(c: u8) -> (int, bool) {
	switch c {
	case '0' ..= '9': return int(c - '0'), true
	case 'a' ..= 'f': return int(c - 'a') + 10, true
	case 'A' ..= 'F': return int(c - 'A') + 10, true
	}
	return 0, false
}

// Parses an SVG color. Returns ok=false for unknown values.
parse_color :: proc(s: string, current: Color) -> (c: Color, ok: bool) {
	t := strings.trim_space(s)
	if len(t) == 0 do return {}, false
	if t[0] == '#' {
		h := t[1:]
		v: [8]int
		for i in 0 ..< len(h) {
			if i >= 8 do return {}, false
			x, hk := hex_val(h[i])
			if !hk do return {}, false
			v[i] = x
		}
		switch len(h) {
		case 3: return Color{u8(v[0] * 17), u8(v[1] * 17), u8(v[2] * 17), 255}, true
		case 4: return Color{u8(v[0] * 17), u8(v[1] * 17), u8(v[2] * 17), u8(v[3] * 17)}, true
		case 6: return Color{u8(v[0] * 16 + v[1]), u8(v[2] * 16 + v[3]), u8(v[4] * 16 + v[5]), 255}, true
		case 8: return Color{u8(v[0] * 16 + v[1]), u8(v[2] * 16 + v[3]), u8(v[4] * 16 + v[5]), u8(v[6] * 16 + v[7])}, true
		}
		return {}, false
	}
	low := strings.to_lower(t, context.temp_allocator)
	if strings.has_prefix(low, "rgb") {
		lp := strings.index_byte(low, '(')
		rp := strings.index_byte(low, ')')
		if lp < 0 || rp < lp do return {}, false
		body := low[lp + 1:rp]
		out: [4]f32 = {0, 0, 0, 1}
		rest := body
		for i in 0 ..< 4 {
			v, r, nok := scan_num(rest)
			if !nok do break
			rest = strings.trim_left_space(r)
			if len(rest) > 0 && rest[0] == '%' {
				v = i < 3 ? v * 2.55 : v / 100
				rest = rest[1:]
			}
			rest = strings.trim_left(rest, " ,/")
			out[i] = v
		}
		return Color{u8(clamp(out[0], 0, 255)), u8(clamp(out[1], 0, 255)), u8(clamp(out[2], 0, 255)), u8(clamp(out[3] * 255, 0, 255))}, true
	}
	if low == "currentcolor" do return current, true
	if low == "transparent" do return Color{}, true
	for e in NAMED_COLORS {
		if e.n == low do return Color{u8(e.c >> 16), u8(e.c >> 8), u8(e.c), 255}, true
	}
	return {}, false
}

// Transforms ------------------------------------------------------------------------------------------------

parse_transform :: proc(s: string) -> Mat {
	m := MAT_ID
	rest := s
	for {
		rest = strings.trim_left(rest, " \t\r\n,")
		lp := strings.index_byte(rest, '(')
		if lp < 0 do break
		name := strings.trim_space(rest[:lp])
		rp := strings.index_byte(rest, ')')
		if rp < lp do break
		a := parse_num_list(rest[lp + 1:rp])
		rest = rest[rp + 1:]
		t := MAT_ID
		switch name {
		case "translate":
			if len(a) >= 1 do t = mat_translate(a[0], len(a) > 1 ? a[1] : 0)
		case "scale":
			if len(a) >= 1 do t = mat_scale(a[0], len(a) > 1 ? a[1] : a[0])
		case "rotate":
			if len(a) >= 1 {
				r := mat_rotate(deg2rad(a[0]))
				if len(a) >= 3 do t = mat_mul(mat_translate(a[1], a[2]), mat_mul(r, mat_translate(-a[1], -a[2])))
				else do t = r
			}
		case "skewX":
			if len(a) >= 1 do t = Mat{1, 0, math.tan(deg2rad(a[0])), 1, 0, 0}
		case "skewY":
			if len(a) >= 1 do t = Mat{1, math.tan(deg2rad(a[0])), 0, 1, 0, 0}
		case "matrix":
			if len(a) >= 6 do t = Mat{a[0], a[1], a[2], a[3], a[4], a[5]}
		}
		m = mat_mul(m, t)
	}
	return m
}

// Path data -------------------------------------------------------------------------------------------------

parse_path_data :: proc(s: string, out: ^Path) {
	rest := s
	cmd: u8
	cur, start, last_c: Vec2
	last_cmd: u8
	first := true
	for {
		rest = strings.trim_left(rest, " \t\r\n,")
		if len(rest) == 0 do break
		c := rest[0]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			cmd = c
			rest = rest[1:]
		} else if cmd == 0 || cmd == 'z' || cmd == 'Z' {
			break
		}
		rel := cmd >= 'a'
		up := cmd & ~u8(0x20) // upper case
		if up == 'Z' {
			path_close(out)
			cur = start
			last_cmd = 'Z'
			last_c = cur
			continue
		}
		nargs := 0
		switch up {
		case 'M', 'L', 'T': nargs = 2
		case 'H', 'V':      nargs = 1
		case 'C':           nargs = 6
		case 'S', 'Q':      nargs = 4
		case 'A':           nargs = 7
		case:
			return
		}
		args: [7]f32
		okp := true
		for i in 0 ..< nargs {
			if up == 'A' && (i == 3 || i == 4) {
				// flags are single characters and may be unseparated
				r := strings.trim_left(rest, " \t\r\n,")
				if len(r) == 0 || (r[0] != '0' && r[0] != '1') {
					okp = false
					break
				}
				args[i] = r[0] == '1' ? 1 : 0
				rest = r[1:]
				continue
			}
			v, r, nok := scan_num(rest)
			if !nok {
				okp = false
				break
			}
			args[i] = v
			rest = r
		}
		if !okp do break
		off := rel ? cur : Vec2{}
		switch up {
		case 'M':
			p := Vec2{args[0], args[1]} + off
			path_move(out, p)
			cur, start = p, p
			// further coordinate pairs are implicit lineto
			cmd = rel ? 'l' : 'L'
			last_c = p
		case 'L':
			p := Vec2{args[0], args[1]} + off
			path_line(out, p)
			cur = p
			last_c = p
		case 'H':
			p := Vec2{args[0] + (rel ? cur.x : 0), cur.y}
			path_line(out, p)
			cur = p
			last_c = p
		case 'V':
			p := Vec2{cur.x, args[0] + (rel ? cur.y : 0)}
			path_line(out, p)
			cur = p
			last_c = p
		case 'C':
			c1, c2, p := Vec2{args[0], args[1]} + off, Vec2{args[2], args[3]} + off, Vec2{args[4], args[5]} + off
			path_cubic(out, c1, c2, p)
			last_c = c2
			cur = p
		case 'S':
			c1 := cur
			if last_cmd == 'C' || last_cmd == 'S' do c1 = 2 * cur - last_c
			c2, p := Vec2{args[0], args[1]} + off, Vec2{args[2], args[3]} + off
			path_cubic(out, c1, c2, p)
			last_c = c2
			cur = p
		case 'Q':
			c1, p := Vec2{args[0], args[1]} + off, Vec2{args[2], args[3]} + off
			path_quad(out, c1, p)
			last_c = c1
			cur = p
		case 'T':
			c1 := cur
			if last_cmd == 'Q' || last_cmd == 'T' do c1 = 2 * cur - last_c
			p := Vec2{args[0], args[1]} + off
			path_quad(out, c1, p)
			last_c = c1
			cur = p
		case 'A':
			p := Vec2{args[5], args[6]} + off
			path_arc(out, cur, args[0], args[1], args[2], args[3] != 0, args[4] != 0, p)
			cur = p
			last_c = p
		}
		last_cmd = up
		first = false
	}
	_ = first
}

// CSS -------------------------------------------------------------------------------------------------------

parse_decls :: proc(s: string, out: ^[dynamic]XAttr) {
	for part in strings.split(s, ";", context.temp_allocator) {
		colon := strings.index_byte(part, ':')
		if colon < 0 do continue
		k := strings.trim_space(part[:colon])
		v := strings.trim_space(part[colon + 1:])
		if i := strings.index(v, "!important"); i >= 0 do v = strings.trim_space(v[:i])
		if len(k) > 0 do append(out, XAttr{k, v})
	}
}

parse_stylesheet :: proc(ctx: ^Svg_Ctx, css: string) {
	// strip comments
	text := css
	sb := strings.builder_make(context.temp_allocator)
	for len(text) > 0 {
		i := strings.index(text, "/*")
		if i < 0 {
			strings.write_string(&sb, text)
			break
		}
		strings.write_string(&sb, text[:i])
		j := strings.index(text[i:], "*/")
		if j < 0 do break
		text = text[i + j + 2:]
	}
	text = strings.to_string(sb)
	for {
		lb := strings.index_byte(text, '{')
		if lb < 0 do break
		rb := strings.index_byte(text[lb:], '}')
		if rb < 0 do break
		sels := text[:lb]
		body := text[lb + 1:lb + rb]
		text = text[lb + rb + 1:]
		if strings.index_byte(sels, '@') >= 0 do continue
		for sel in strings.split(sels, ",", context.temp_allocator) {
			r := Css_Rule{sel = strings.trim_space(sel)}
			parse_decls(body, &r.decls)
			if len(r.sel) > 0 do append(&ctx.rules, r)
		}
	}
}

selector_matches :: proc(sel: string, el: ^XNode) -> bool {
	// compound selector without combinators: tag, .class, #id, tag.class, ...
	if strings.index_any(sel, " >+~[:") >= 0 {
		// only the last compound of a descendant selector is considered
		if i := strings.last_index_byte(sel, ' '); i >= 0 && strings.index_any(sel, ">+~[:") < 0 {
			return selector_matches(sel[i + 1:], el)
		}
		return false
	}
	if sel == "*" do return true
	i := 0
	tag := ""
	for i < len(sel) && sel[i] != '.' && sel[i] != '#' do i += 1
	tag = sel[:i]
	if tag != "" && tag != el.tag do return false
	classes, _ := xattr(el, "class")
	id, _ := xattr(el, "id")
	for i < len(sel) {
		k := i + 1
		for k < len(sel) && sel[k] != '.' && sel[k] != '#' do k += 1
		part := sel[i + 1:k]
		if sel[i] == '.' {
			found := false
			for cl in strings.fields(classes, context.temp_allocator) {
				if cl == part do found = true
			}
			if !found do return false
		} else if id != part {
			return false
		}
		i = k
	}
	return true
}

// All declarations applying to an element, lowest priority first: presentation attributes, sheet, style attribute.
element_props :: proc(ctx: ^Svg_Ctx, el: ^XNode) -> [dynamic]XAttr {
	props := make([dynamic]XAttr, context.temp_allocator)
	for a in el.attrs {
		switch a.k {
		case "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
		     "stroke-dashoffset", "fill-rule", "opacity", "fill-opacity", "stroke-opacity", "font-family", "font-size",
		     "color", "stop-color", "stop-opacity", "display", "visibility":
			append(&props, a)
		}
	}
	for r in ctx.rules {
		if selector_matches(r.sel, el) do append(&props, ..r.decls[:])
	}
	if st, ok := xattr(el, "style"); ok do parse_decls(st, &props)
	return props
}

prop_get :: proc(props: []XAttr, key: string) -> (string, bool) {
	#reverse for p in props {
		if p.k == key do return p.v, true
	}
	return "", false
}

// Building nodes -------------------------------------------------------------------------------------------

svg_load :: proc(path: string) -> (d: ^Doc, ok: bool) {
	data, rok := read_file(path)
	if !rok do return nil, false
	defer delete(data)
	d, ok = svg_parse(string(data))
	if ok {
		d.path = strings.clone(path)
		stem := path
		if i := strings.last_index_any(stem, "/\\"); i >= 0 do stem = stem[i + 1:]
		if i := strings.last_index_byte(stem, '.'); i > 0 do stem = stem[:i]
		d.title = make_name(stem)
		d.modified = false
	}
	return
}

svg_parse :: proc(src: string) -> (d: ^Doc, ok: bool) {
	root := xml_parse(src)
	if root == nil || root.tag != "svg" do return nil, false
	clear(&svg_skipped)
	ctx: Svg_Ctx
	ctx.ids = make(map[string]^XNode, 16, context.temp_allocator)
	collect_ids(&ctx, root)
	collect_styles(&ctx, root)

	// size and view box
	vb := parse_num_list(xattr_or(root, "viewBox"))
	w := parse_length(xattr_or(root, "width"), 0, 0)
	h := parse_length(xattr_or(root, "height"), 0, 0)
	if len(vb) == 4 {
		if w <= 0 do w = vb[2]
		if h <= 0 do h = vb[3]
	}
	if w <= 0 do w = 800
	if h <= 0 do h = 600
	d = doc_new(.Svg, "Untitled", w, h)
	ctx.d = d
	vb_off: Vec2
	if len(vb) == 4 && vb[2] > 0 && vb[3] > 0 {
		// document space is the viewBox space scaled to the declared size: keep user units, resize the page
		d.w, d.h = vb[2], vb[3]
		vb_off = {vb[0], vb[1]}
	}
	st := rstyle_default()
	props := element_props(&ctx, root)
	apply_rstyle(&st, props[:])
	first_frame := true
	for k in root.kids {
		if k.is_text do continue
		dur, is_frame := xattr(k, "data-pangolin-frame")
		if !is_frame {
			// anything beside the frames, from another editor, goes into the first one
			build_element(&ctx, k, d.frames[0].root, st)
			continue
		}
		if !first_frame {
			fr := node_new(d, .Group)
			name_set(&fr.name, "root")
			append(&d.frames, Frame{root = fr, thumb_ver = -1})
		}
		first_frame = false
		f := &d.frames[len(d.frames) - 1]
		ms, msok := strconv.parse_int(strings.trim_space(dur))
		f.duration = msok ? max(ms, 10) : FRAME_DURATION
		// not build_element: a frame after the first says display="none", and its group is the frame itself
		fst := st
		fprops := element_props(&ctx, k)
		apply_rstyle(&fst, fprops[:])
		for c in k.kids {
			if !c.is_text do build_element(&ctx, c, f.root, fst)
		}
	}
	if tags, ok := xattr(root, "data-pangolin-tags"); ok do tags_parse(d, tags)
	if vb_off != {} {
		for f in d.frames {
			for c in f.root.children do node_translate(c, -vb_off.x, -vb_off.y)
		}
	}
	return d, true
}

// The tags written by tags_attr; ones that make no sense for this file's frames are left out.
tags_parse :: proc(d: ^Doc, s: string) {
	for part in strings.split(s, ";", context.temp_allocator) {
		fields := strings.split(part, ":", context.temp_allocator)
		if len(fields) != 5 do continue
		from, fok := strconv.parse_int(fields[1])
		to, tok := strconv.parse_int(fields[2])
		dir, dok := strconv.parse_int(fields[3])
		col, cok := parse_color(fmt.tprintf("#%s", fields[4]), BLACK)
		if !fok || !tok || !dok || !cok || from < 0 || to < from || from >= len(d.frames) do continue
		t := Tag {
			from  = from,
			to    = min(to, len(d.frames) - 1),
			dir   = Tag_Dir(clamp(dir, 0, len(Tag_Dir) - 1)),
			color = col,
		}
		name_set(&t.name, fields[0])
		append(&d.tags, t)
	}
}

collect_ids :: proc(ctx: ^Svg_Ctx, el: ^XNode) {
	if id, ok := xattr(el, "id"); ok && id != "" do ctx.ids[id] = el
	for k in el.kids {
		if !k.is_text do collect_ids(ctx, k)
	}
}

collect_styles :: proc(ctx: ^Svg_Ctx, el: ^XNode) {
	if el.tag == "style" {
		for k in el.kids {
			if k.is_text do parse_stylesheet(ctx, k.text)
		}
	}
	for k in el.kids {
		if !k.is_text do collect_styles(ctx, k)
	}
}

apply_rstyle :: proc(st: ^Rstyle, props: []XAttr) {
	if v, ok := prop_get(props, "color"); ok {
		if c, cok := parse_color(v, st.color); cok do st.color = c
	}
	if v, ok := prop_get(props, "fill"); ok do st.fill = v
	if v, ok := prop_get(props, "stroke"); ok do st.stroke = v
	if v, ok := prop_get(props, "fill-opacity"); ok do st.fill_op = clamp(parse_length(v, 1), 0, 1)
	if v, ok := prop_get(props, "stroke-opacity"); ok do st.stroke_op = clamp(parse_length(v, 1), 0, 1)
	if v, ok := prop_get(props, "stroke-width"); ok do st.sw = parse_length(v, 1)
	if v, ok := prop_get(props, "stroke-linecap"); ok {
		switch v {
		case "round":  st.cap = .Round
		case "square": st.cap = .Square
		case:          st.cap = .Butt
		}
	}
	if v, ok := prop_get(props, "stroke-linejoin"); ok {
		switch v {
		case "round": st.join = .Round
		case "bevel": st.join = .Bevel
		case:         st.join = .Miter
		}
	}
	if v, ok := prop_get(props, "stroke-miterlimit"); ok do st.miter = parse_length(v, 4)
	if v, ok := prop_get(props, "stroke-dasharray"); ok do st.dash = v
	if v, ok := prop_get(props, "stroke-dashoffset"); ok do st.dash_off = parse_length(v, 0)
	if v, ok := prop_get(props, "fill-rule"); ok do st.even_odd = v == "evenodd"
	if v, ok := prop_get(props, "font-family"); ok do st.font = v
	if v, ok := prop_get(props, "font-size"); ok do st.size = parse_length(v, 16)
}

// "url(#id)" -> id
url_ref :: proc(s: string) -> (string, bool) {
	t := strings.trim_space(s)
	if !strings.has_prefix(t, "url(") do return "", false
	rp := strings.index_byte(t, ')')
	if rp < 0 do return "", false
	inner := strings.trim(t[4:rp], " \t'\"")
	if len(inner) > 0 && inner[0] == '#' do return inner[1:], true
	return "", true
}

// Resolves a fill / stroke value to a paint. Gradients need the geometry bounds (local space).
resolve_paint :: proc(ctx: ^Svg_Ctx, val: string, opacity: f32, st: ^Rstyle, bounds: Bounds) -> Paint {
	t := strings.trim_space(val)
	if t == "none" || t == "" do return paint_none()
	if id, isurl := url_ref(t); isurl {
		if el, found := ctx.ids[id]; found && (el.tag == "linearGradient" || el.tag == "radialGradient") {
			if p, ok := build_gradient(ctx, el, opacity, bounds, st); ok do return p
		}
		// fallback color after the url
		rp := strings.index_byte(t, ')')
		if rp >= 0 && rp + 1 < len(t) {
			if c, ok := parse_color(t[rp + 1:], st.color); ok {
				c.a = u8(f32(c.a) * opacity)
				return paint_solid(c)
			}
		}
		return paint_none()
	}
	c, ok := parse_color(t, st.color)
	if !ok do return paint_none()
	c.a = u8(f32(c.a) * opacity)
	if c.a == 0 && strings.to_lower(t, context.temp_allocator) == "transparent" do return paint_none()
	return paint_solid(c)
}

// Follows href chains for gradient attributes and stops.
grad_attr :: proc(ctx: ^Svg_Ctx, el: ^XNode, key: string) -> (string, bool) {
	cur := el
	for _ in 0 ..< 8 {
		if v, ok := xattr(cur, key); ok do return v, true
		href := xattr_or(cur, "href")
		if len(href) > 1 && href[0] == '#' {
			nxt, found := ctx.ids[href[1:]]
			if !found do break
			cur = nxt
		} else do break
	}
	return "", false
}

grad_stops_el :: proc(ctx: ^Svg_Ctx, el: ^XNode) -> ^XNode {
	cur := el
	for _ in 0 ..< 8 {
		for k in cur.kids {
			if !k.is_text && k.tag == "stop" do return cur
		}
		href := xattr_or(cur, "href")
		if len(href) > 1 && href[0] == '#' {
			nxt, found := ctx.ids[href[1:]]
			if !found do break
			cur = nxt
		} else do break
	}
	return el
}

build_gradient :: proc(ctx: ^Svg_Ctx, el: ^XNode, opacity: f32, bounds: Bounds, st: ^Rstyle) -> (p: Paint, ok: bool) {
	radial := el.tag == "radialGradient"
	units, _ := grad_attr(ctx, el, "gradientUnits")
	bbox := units != "userSpaceOnUse"
	bw, bh := bounds_w(bounds), bounds_h(bounds)
	if bbox && (bounds_empty(bounds) || bw <= 0 || bh <= 0) do return {}, false
	num :: proc(ctx: ^Svg_Ctx, el: ^XNode, key: string, def: f32, bbox: bool) -> f32 {
		v, found := grad_attr(ctx, el, key)
		if !found do return def
		t := strings.trim_space(v)
		if strings.has_suffix(t, "%") {
			x, _, nok := scan_num(t)
			return nok ? x / 100 : def
		}
		return parse_length(t, def)
	}
	// stops
	se := grad_stops_el(ctx, el)
	for k in se.kids {
		if k.is_text || k.tag != "stop" || p.nstops >= MAX_STOPS do continue
		props := element_props(ctx, k)
		off_s := xattr_or(k, "offset", "0")
		off: f32
		if strings.has_suffix(strings.trim_space(off_s), "%") {
			x, _, _ := scan_num(off_s)
			off = x / 100
		} else do off = parse_length(off_s, 0)
		col := Color{0, 0, 0, 255}
		if v, found := prop_get(props[:], "stop-color"); found {
			if c, cok := parse_color(v, st.color); cok do col = c
		}
		op := f32(1)
		if v, found := prop_get(props[:], "stop-opacity"); found do op = clamp(parse_length(v, 1), 0, 1)
		col.a = u8(f32(col.a) * op * opacity)
		off = clamp(off, 0, 1)
		if p.nstops > 0 do off = max(off, p.stops[p.nstops - 1].t)
		p.stops[p.nstops] = Stop{off, col}
		p.nstops += 1
	}
	if p.nstops == 0 do return {}, false
	if p.nstops == 1 {
		return paint_solid(p.stops[0].color), true
	}
	sp, _ := grad_attr(ctx, el, "spreadMethod")
	switch sp {
	case "reflect": p.spread = 1
	case "repeat":  p.spread = 2
	}
	fx :: proc(v: f32, bbox: bool, b: Bounds) -> f32 {
		return bbox ? b.x0 + v * (b.x1 - b.x0) : v
	}
	fy :: proc(v: f32, bbox: bool, b: Bounds) -> f32 {
		return bbox ? b.y0 + v * (b.y1 - b.y0) : v
	}
	// userSpaceOnUse percentages refer to the viewport, approximated by the page
	pg_w, pg_h := ctx.d.w, ctx.d.h
	if radial {
		p.kind = .Radial
		cxv := num(ctx, el, "cx", bbox ? 0.5 : 0.5 * pg_w, bbox)
		cyv := num(ctx, el, "cy", bbox ? 0.5 : 0.5 * pg_h, bbox)
		rv := num(ctx, el, "r", bbox ? 0.5 : 0.5 * math.sqrt((pg_w * pg_w + pg_h * pg_h) / 2), bbox)
		p.p0 = {fx(cxv, bbox, bounds), fy(cyv, bbox, bounds)}
		p.p1 = {bbox ? rv * (bw + bh) / 2 : rv, 0}
	} else {
		p.kind = .Linear
		x1 := num(ctx, el, "x1", 0, bbox)
		y1 := num(ctx, el, "y1", 0, bbox)
		x2 := num(ctx, el, "x2", bbox ? 1 : pg_w, bbox)
		y2 := num(ctx, el, "y2", 0, bbox)
		p.p0 = {fx(x1, bbox, bounds), fy(y1, bbox, bounds)}
		p.p1 = {fx(x2, bbox, bounds), fy(y2, bbox, bounds)}
	}
	if gt, found := grad_attr(ctx, el, "gradientTransform"); found {
		m := parse_transform(gt)
		p.p0 = mat_apply(m, p.p0)
		if p.kind == .Linear do p.p1 = mat_apply(m, p.p1)
		else do p.p1.x *= mat_scale_factor(m)
	}
	return p, true
}

parse_dash :: proc(n: ^Node, s: string) {
	n.ndash = 0
	t := strings.trim_space(s)
	if t == "" || t == "none" do return
	vals := parse_num_list(t)
	if len(vals) == 0 do return
	// odd lists repeat to make pairs
	cnt := len(vals) % 2 == 1 ? len(vals) * 2 : len(vals)
	if cnt > 4 do cnt = 4
	sum: f32
	for i in 0 ..< cnt {
		n.dash[i] = vals[i % len(vals)]
		sum += n.dash[i]
	}
	if sum <= 0 do return
	n.ndash = cnt
}

apply_style_to_node :: proc(ctx: ^Svg_Ctx, n: ^Node, st: ^Rstyle) {
	b := node_local_bounds(n)
	n.fill = resolve_paint(ctx, st.fill, st.fill_op, st, b)
	n.stroke = resolve_paint(ctx, st.stroke, st.stroke_op, st, b)
	n.sw = st.sw
	n.cap, n.join, n.miter = st.cap, st.join, st.miter
	n.dash_off = st.dash_off
	parse_dash(n, st.dash)
	n.even_odd = st.even_odd
}

build_element :: proc(ctx: ^Svg_Ctx, el: ^XNode, parent: ^Node, inherited: Rstyle) {
	props := element_props(ctx, el)
	// a hidden object stays in the document, as it does when hidden in the Objects panel
	dv, has_display := prop_get(props[:], "display")
	hidden := has_display && dv == "none"
	st := inherited
	apply_rstyle(&st, props[:])
	d := ctx.d

	xf := MAT_ID
	if t, ok := xattr(el, "transform"); ok do xf = parse_transform(t)
	opacity := f32(1)
	if v, ok := prop_get(props[:], "opacity"); ok do opacity = clamp(parse_length(v, 1), 0, 1)

	n: ^Node
	switch el.tag {
	case "g", "a", "switch":
		n = node_new(d, .Group)
		name_set(&n.name, "Group")
		n.xf, n.opacity = xf, opacity
		for k in el.kids {
			if !k.is_text do build_element(ctx, k, n, st)
		}
		if len(n.children) == 0 {
			node_free(n)
			return
		}
	case "defs", "symbol", "linearGradient", "radialGradient", "style", "title", "desc", "metadata", "namedview", "stop", "animate":
		return
	case "path":
		n = node_new(d, .Path)
		name_set(&n.name, "Path")
		parse_path_data(xattr_or(el, "d"), &n.segs)
		if len(n.segs) == 0 {
			node_free(n)
			return
		}
	case "rect":
		n = node_new(d, .Rect)
		name_set(&n.name, "Rectangle")
		n.x = parse_length(xattr_or(el, "x"), 0, d.w)
		n.y = parse_length(xattr_or(el, "y"), 0, d.h)
		n.w = parse_length(xattr_or(el, "width"), 0, d.w)
		n.h = parse_length(xattr_or(el, "height"), 0, d.h)
		rxs, hasrx := xattr(el, "rx")
		rys, hasry := xattr(el, "ry")
		if hasrx do n.rx = parse_length(rxs)
		if hasry do n.ry = parse_length(rys)
		if hasrx && !hasry do n.ry = n.rx
		if hasry && !hasrx do n.rx = n.ry
		if n.w <= 0 || n.h <= 0 {
			node_free(n)
			return
		}
	case "circle", "ellipse":
		n = node_new(d, .Ellipse)
		name_set(&n.name, "Ellipse")
		n.x = parse_length(xattr_or(el, "cx"), 0, d.w)
		n.y = parse_length(xattr_or(el, "cy"), 0, d.h)
		if el.tag == "circle" {
			n.w = parse_length(xattr_or(el, "r"), 0, d.w)
			n.h = n.w
		} else {
			n.w = parse_length(xattr_or(el, "rx"), 0, d.w)
			n.h = parse_length(xattr_or(el, "ry"), 0, d.h)
		}
		if n.w <= 0 || n.h <= 0 {
			node_free(n)
			return
		}
	case "line":
		n = node_new(d, .Path)
		name_set(&n.name, "Line")
		path_move(&n.segs, {parse_length(xattr_or(el, "x1")), parse_length(xattr_or(el, "y1"))})
		path_line(&n.segs, {parse_length(xattr_or(el, "x2")), parse_length(xattr_or(el, "y2"))})
	case "polyline", "polygon":
		n = node_new(d, .Path)
		name_set(&n.name, el.tag == "polygon" ? "Polygon" : "Polyline")
		pts := parse_num_list(xattr_or(el, "points"))
		for i := 0; i + 1 < len(pts); i += 2 {
			if i == 0 do path_move(&n.segs, {pts[0], pts[1]})
			else do path_line(&n.segs, {pts[i], pts[i + 1]})
		}
		if el.tag == "polygon" do path_close(&n.segs)
		if len(n.segs) < 2 {
			node_free(n)
			return
		}
	case "text":
		n = build_text(ctx, el, &st)
		if n == nil do return
	case "use":
		href := xattr_or(el, "href")
		if len(href) < 2 || href[0] != '#' || ctx.use_depth > 8 do return
		ref, found := ctx.ids[href[1:]]
		if !found do return
		g := node_new(d, .Group)
		name_set(&g.name, "Use")
		ux, uy := parse_length(xattr_or(el, "x")), parse_length(xattr_or(el, "y"))
		g.xf = mat_mul(xf, mat_translate(ux, uy))
		g.opacity = opacity
		ctx.use_depth += 1
		if ref.tag == "symbol" {
			for k in ref.kids {
				if !k.is_text do build_element(ctx, k, g, st)
			}
		} else {
			build_element(ctx, ref, g, st)
		}
		ctx.use_depth -= 1
		if len(g.children) == 0 {
			node_free(g)
			return
		}
		if hidden do g.visible = false
		append(&parent.children, g)
		return
	case:
		append(&svg_skipped, el.tag)
		return
	}
	if n.kind != .Group {
		n.xf, n.opacity = xf, opacity
		if v, ok := prop_get(props[:], "visibility"); ok && v == "hidden" do n.visible = false
		apply_style_to_node(ctx, n, &st)
	}
	if hidden do n.visible = false
	if xattr_or(el, "data-pangolin-locked") == "true" do n.locked = true
	if nm, nok := xattr(el, "data-pangolin-name"); nok && nm != "" do name_set(&n.name, nm) // a name an id can't hold, see write_name
	else if id, ok := xattr(el, "id"); ok && id != "" do name_set(&n.name, id)
	else if lbl, lok := xattr(el, "label"); lok do name_set(&n.name, lbl)
	append(&parent.children, n)
}

build_text :: proc(ctx: ^Svg_Ctx, el: ^XNode, st: ^Rstyle) -> ^Node {
	d := ctx.d
	n := node_new(d, .Text)
	name_set(&n.name, "Text")
	n.x = parse_length(xattr_or(el, "x"), 0, d.w)
	n.y = parse_length(xattr_or(el, "y"), 0, d.h)
	n.size = st.size
	fam := st.font
	if c := strings.index_byte(fam, ','); c >= 0 do fam = fam[:c]
	fam = strings.trim(fam, " '\"")
	n.font = make_name(fam)
	// resolve the family against installed fonts, falling back to the default
	if fam == "" || font_find(fam).name != fam do n.font = make_name(DEFAULT_FONT)
	first := true
	collect :: proc(el: ^XNode, n: ^Node, first: ^bool) {
		for k in el.kids {
			if k.is_text {
				t := strings.join(strings.fields(k.text, context.temp_allocator), " ", context.temp_allocator)
				if strings.has_prefix(k.text, " ") && len(n.text) > 0 && n.text[len(n.text) - 1] != '\n' do append(&n.text, ' ')
				append(&n.text, ..transmute([]u8)t)
				if strings.has_suffix(k.text, " ") && len(t) > 0 do append(&n.text, ' ')
			} else if k.tag == "tspan" {
				// a tspan with its own y starts a new line
				if _, has_y := xattr(k, "y"); has_y && !first^ && len(n.text) > 0 && n.text[len(n.text) - 1] != '\n' {
					append(&n.text, '\n')
				} else if _, has_dy := xattr(k, "dy"); has_dy && !first^ && len(n.text) > 0 && n.text[len(n.text) - 1] != '\n' {
					append(&n.text, '\n')
				}
				collect(k, n, first)
			}
			first^ = false
		}
	}
	collect(el, n, &first)
	for len(n.text) > 0 && (n.text[len(n.text) - 1] == ' ') do pop(&n.text)
	if len(n.text) == 0 {
		node_free(n)
		return nil
	}
	return n
}
