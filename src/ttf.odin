package pangolin

import "core:math"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf16"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// TrueType writing and reading.
// Writing: simple (non-composite) glyphs with quadratic outlines; tables cmap, glyf, head, hhea, hmtx, loca, maxp,
// name, OS/2, post (format 3) and kern (when pairs exist). Port of ScalarCanvas's TTFWriter.
// Reading: outlines and advances come from stb_truetype (TrueType and CFF, composites resolved); the cmap, names and
// metrics are parsed here.
// ---------------------------------------------------------------------------

BW :: struct {
	b: [dynamic]u8,
}

bw_u8 :: proc(w: ^BW, v: u8) {
	append(&w.b, v)
}

bw_u16 :: proc(w: ^BW, v: u16) {
	append(&w.b, u8(v >> 8), u8(v))
}

bw_i16 :: proc(w: ^BW, v: i16) {
	bw_u16(w, u16(v))
}

bw_u32 :: proc(w: ^BW, v: u32) {
	append(&w.b, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
}

bw_fixed :: proc(w: ^BW, v: f32) {
	bw_u32(w, u32(i32(math.round(v * 65536))))
}

bw_bytes :: proc(w: ^BW, s: []u8) {
	append(&w.b, ..s)
}

bw_tag :: proc(w: ^BW, s: string) {
	for i in 0 ..< 4 do append(&w.b, s[i])
}

ttf_checksum :: proc(b: []u8) -> u32 {
	sum: u32
	for i := 0; i < len(b); i += 4 {
		v: u32
		for k in 0 ..< 4 {
			v <<= 8
			if i + k < len(b) do v |= u32(b[i + k])
		}
		sum += v
	}
	return sum
}

// Font model -----------------------------------------------------------------------------------------------

Font_Glyph :: struct {
	name:     Name,
	unicodes: [dynamic]rune,
	advance:  f32,
	segs:     Path, // font units, y up
	ver:      int, // bumped on every change (thumbnail cache)
	edit:     Glyph_Edit, // shapes the outline was drawn with, kept while another glyph is edited
}

Kern_Pair :: struct {
	left, right: int, // glyph indices
	value:       int,
}

Font_Doc :: struct {
	upm:          int,
	glyphs:       [dynamic]Font_Glyph,
	cur:          int,
	asc, desc:    int,
	line_gap:     int,
	x_height:     int,
	cap_height:   int,
	family:       Name,
	style:        Name,
	ver:          int, // bumped when anything changes (preview cache)
	synced:       int, // doc.version last committed
	em_top:       f32, // y' = em_top - y maps font units to editing space
	remove_overlap: bool,
	kerning:      [dynamic]Kern_Pair,
	// view state of the panel
	grid_scroll:  int,
	filter:       Name,
	preview:      Name,
	metrics_ver:  int, // bumped when the metrics change (thumbnails scale with them)
	thumbs:       map[int]Thumb,
	prev_tex:     Texture,
	prev_key:     [3]int,
	prev_text:    string,
}

glyph_free :: proc(g: ^Font_Glyph) {
	delete(g.unicodes)
	delete(g.segs)
	glyph_edit_free(&g.edit)
}

// Quadratic approximation of cubics ------------------------------------------------------------------------

@(private = "file")
tangent_intersection :: proc(p0, c1, c2, p1: Vec2) -> Vec2 {
	d0 := c1 - p0
	d1 := c2 - p1
	denom := d0.x * d1.y - d0.y * d1.x
	if abs(denom) < 1e-9 do return (c1 + c2) / 2
	r := p1 - p0
	t := (r.x * d1.y - r.y * d1.x) / denom
	return p0 + d0 * t
}

@(private = "file")
quad_error :: proc(p0, c, p1, c1, c2, c3: Vec2) -> f32 {
	worst: f32
	N :: 12
	for i in 1 ..< N {
		t := f32(i) / N
		a := cubic_at(p0, c1, c2, c3, t)
		b := quad_at(p0, c, p1, t)
		d := a - b
		worst = max(worst, d.x * d.x + d.y * d.y)
	}
	return math.sqrt(worst)
}

// Appends quadratics approximating the cubic to `out` as (control, end) pairs.
cubic_to_quads :: proc(p0, c1, c2, p1: Vec2, tol: f32, out: ^[dynamic][2]Vec2) {
	recurse :: proc(a, b, c, d: Vec2, tol: f32, depth: int, out: ^[dynamic][2]Vec2) {
		control := tangent_intersection(a, b, c, d)
		err := quad_error(a, control, d, b, c, d)
		if err <= tol || depth >= 8 {
			append(out, [2]Vec2{control, d})
			return
		}
		p01, p12, p23 := lerp(a, b, 0.5), lerp(b, c, 0.5), lerp(c, d, 0.5)
		p012, p123 := lerp(p01, p12, 0.5), lerp(p12, p23, 0.5)
		m := lerp(p012, p123, 0.5)
		recurse(a, p01, p012, m, tol, depth + 1, out)
		recurse(m, p123, p23, d, tol, depth + 1, out)
	}
	if v_len(c1 - p0) < 1e-9 && v_len(c2 - p1) < 1e-9 {
		append(out, [2]Vec2{(c1 + c2) / 2, p1})
		return
	}
	recurse(p0, c1, c2, p1, tol, 0, out)
}

// Contours as on / off curve points ----------------------------------------------------------------------

TT_Pt :: struct {
	x, y: i32,
	on:   bool,
}

// Converts a path (lines, quads, cubics) to TrueType contours.
path_to_contours :: proc(segs: []Seg, tol: f32) -> [dynamic][dynamic]TT_Pt {
	out: [dynamic][dynamic]TT_Pt
	cur: [dynamic]TT_Pt
	start: Vec2
	pos: Vec2
	flush :: proc(out: ^[dynamic][dynamic]TT_Pt, cur: ^[dynamic]TT_Pt) {
		// a closed contour does not repeat its first point
		if len(cur) > 1 {
			f, l := cur[0], cur[len(cur) - 1]
			if f.x == l.x && f.y == l.y && l.on do pop(cur)
		}
		if len(cur) >= 3 do append(out, cur^)
		else do delete(cur^)
		cur^ = nil
	}
	rnd :: proc(p: Vec2, on: bool) -> TT_Pt {
		return TT_Pt{i32(math.round(p.x)), i32(math.round(p.y)), on}
	}
	for g in segs {
		switch g.kind {
		case .Move:
			flush(&out, &cur)
			start, pos = g.p, g.p
			append(&cur, rnd(g.p, true))
		case .Line:
			if len(cur) == 0 do append(&cur, rnd(pos, true))
			append(&cur, rnd(g.p, true))
			pos = g.p
		case .Quad:
			if len(cur) == 0 do append(&cur, rnd(pos, true))
			append(&cur, rnd(g.c1, false), rnd(g.p, true))
			pos = g.p
		case .Cubic:
			if len(cur) == 0 do append(&cur, rnd(pos, true))
			quads := make([dynamic][2]Vec2, context.temp_allocator)
			cubic_to_quads(pos, g.c1, g.c2, g.p, tol, &quads)
			for q in quads do append(&cur, rnd(q[0], false), rnd(q[1], true))
			pos = g.p
		case .Close:
			flush(&out, &cur)
			pos = start
		}
	}
	flush(&out, &cur)
	return out
}

Glyph_Box :: struct {
	x0, y0, x1, y1: i32,
	empty:          bool,
}

contours_box :: proc(cs: [][dynamic]TT_Pt) -> Glyph_Box {
	b := Glyph_Box{max(i32), max(i32), min(i32), min(i32), true}
	for c in cs {
		for p in c {
			b.empty = false
			b.x0, b.y0, b.x1, b.y1 = min(b.x0, p.x), min(b.y0, p.y), max(b.x1, p.x), max(b.y1, p.y)
		}
	}
	if b.empty do return Glyph_Box{empty = true}
	return b
}

write_simple_glyph :: proc(contours: [][dynamic]TT_Pt, box: Glyph_Box) -> []u8 {
	w: BW
	bw_i16(&w, i16(len(contours)))
	bw_i16(&w, i16(clamp(box.x0, -32768, 32767)))
	bw_i16(&w, i16(clamp(box.y0, -32768, 32767)))
	bw_i16(&w, i16(clamp(box.x1, -32768, 32767)))
	bw_i16(&w, i16(clamp(box.y1, -32768, 32767)))
	last := -1
	for c in contours {
		last += len(c)
		bw_u16(&w, u16(last))
	}
	bw_u16(&w, 0) // no instructions
	flags := make([dynamic]u8, context.temp_allocator)
	xb := make([dynamic]u8, context.temp_allocator)
	yb := make([dynamic]u8, context.temp_allocator)
	px, py: i32
	for c in contours {
		for p in c {
			x, y := clamp(p.x, -32768, 32767), clamp(p.y, -32768, 32767)
			dx, dy := x - px, y - py
			px, py = x, y
			flag: u8 = p.on ? 0x01 : 0
			if dx == 0 {
				flag |= 0x10
			} else if dx >= -255 && dx <= 255 {
				flag |= 0x02
				if dx > 0 do flag |= 0x10
				append(&xb, u8(abs(dx)))
			} else {
				append(&xb, u8(u16(i16(dx)) >> 8), u8(dx))
			}
			if dy == 0 {
				flag |= 0x20
			} else if dy >= -255 && dy <= 255 {
				flag |= 0x04
				if dy > 0 do flag |= 0x20
				append(&yb, u8(abs(dy)))
			} else {
				append(&yb, u8(u16(i16(dy)) >> 8), u8(dy))
			}
			append(&flags, flag)
		}
	}
	i := 0
	for i < len(flags) {
		f := flags[i]
		run := 1
		for i + run < len(flags) && flags[i + run] == f && run < 255 do run += 1
		if run > 1 {
			bw_u8(&w, f | 0x08)
			bw_u8(&w, u8(run - 1))
		} else {
			bw_u8(&w, f)
		}
		i += run
	}
	bw_bytes(&w, xb[:])
	bw_bytes(&w, yb[:])
	return w.b[:]
}

utf16be :: proc(s: string) -> []u8 {
	out := make([dynamic]u8, context.temp_allocator)
	for r in s {
		if r >= 0x10000 {
			r1, r2 := utf16.encode_surrogate_pair(r)
			append(&out, u8(r1 >> 8), u8(r1), u8(r2 >> 8), u8(r2))
		} else {
			append(&out, u8(r >> 8), u8(r))
		}
	}
	return out[:]
}

// Builds the font file. Returns the bytes (temp allocated) or nil with a message.
ttf_write :: proc(f: ^Font_Doc) -> (data: []u8, err: string) {
	n := len(f.glyphs)
	if n == 0 do return nil, "The font has no glyphs."
	glyf: BW
	loca := make([dynamic]u32, context.temp_allocator)
	max_pts, max_contours: int
	bbox := Glyph_Box{max(i32), max(i32), min(i32), min(i32), true}
	lsbs := make([]i32, n, context.temp_allocator)
	widest: u16
	min_lsb, min_rsb, max_extent := i32(max(i16)), i32(max(i16)), i32(min(i16))
	for g, i in f.glyphs {
		append(&loca, u32(len(glyf.b)))
		outline := g.segs[:]
		cleaned: Path
		if f.remove_overlap && len(outline) > 0 {
			cleaned = path_remove_overlap(outline)
			outline = cleaned[:]
		}
		contours := path_to_contours(outline, 0.6)
		box := contours_box(contours[:])
		if !box.empty {
			bytes := write_simple_glyph(contours[:], box)
			bw_bytes(&glyf, bytes)
			pts := 0
			for c in contours do pts += len(c)
			max_pts = max(max_pts, pts)
			max_contours = max(max_contours, len(contours))
			for len(glyf.b) % 4 != 0 do bw_u8(&glyf, 0)
			lsbs[i] = box.x0
			bbox.empty = false
			bbox.x0, bbox.y0, bbox.x1, bbox.y1 = min(bbox.x0, box.x0), min(bbox.y0, box.y0), max(bbox.x1, box.x1), max(bbox.y1, box.y1)
		}
		adv := u16(clamp(int(math.round(g.advance)), 0, 65535))
		widest = max(widest, adv)
		min_lsb = min(min_lsb, lsbs[i])
		extent := lsbs[i] + (box.empty ? 0 : box.x1 - box.x0)
		max_extent = max(max_extent, extent)
		min_rsb = min(min_rsb, i32(adv) - extent)
		for c in contours do delete(c)
		delete(contours)
		delete(cleaned)
	}
	append(&loca, u32(len(glyf.b)))
	if bbox.empty do bbox = Glyph_Box{0, 0, 0, 0, false}
	long_loca := false
	for o in loca do if o > 0x1fffe do long_loca = true

	tables := make(map[string][]u8, 16, context.temp_allocator)
	tables["glyf"] = glyf.b[:]

	// loca
	{
		w: BW
		for o in loca {
			if long_loca do bw_u32(&w, o)
			else do bw_u16(&w, u16(o / 2))
		}
		tables["loca"] = w.b[:]
	}
	// head
	{
		w: BW
		bw_fixed(&w, 1)
		bw_fixed(&w, 1)
		bw_u32(&w, 0)
		bw_u32(&w, 0x5f0f3cf5)
		bw_u16(&w, 3)
		bw_u16(&w, u16(f.upm))
		now := u64(time.now()._nsec / 1_000_000_000) + 2082844800
		bw_u32(&w, u32(now >> 32))
		bw_u32(&w, u32(now))
		bw_u32(&w, u32(now >> 32))
		bw_u32(&w, u32(now))
		bw_i16(&w, i16(bbox.x0))
		bw_i16(&w, i16(bbox.y0))
		bw_i16(&w, i16(bbox.x1))
		bw_i16(&w, i16(bbox.y1))
		bw_u16(&w, 0)
		bw_u16(&w, 8)
		bw_i16(&w, 2)
		bw_i16(&w, long_loca ? 1 : 0)
		bw_i16(&w, 0)
		tables["head"] = w.b[:]
	}
	// hhea
	{
		w: BW
		bw_fixed(&w, 1)
		bw_i16(&w, i16(f.asc))
		bw_i16(&w, i16(f.desc))
		bw_i16(&w, i16(f.line_gap))
		bw_u16(&w, widest)
		bw_i16(&w, i16(min_lsb))
		bw_i16(&w, i16(min_rsb))
		bw_i16(&w, i16(max_extent))
		bw_i16(&w, 1)
		bw_i16(&w, 0)
		bw_i16(&w, 0)
		for _ in 0 ..< 5 do bw_i16(&w, 0)
		bw_u16(&w, u16(n))
		tables["hhea"] = w.b[:]
	}
	// maxp
	{
		w: BW
		bw_fixed(&w, 1)
		bw_u16(&w, u16(n))
		bw_u16(&w, u16(max_pts))
		bw_u16(&w, u16(max_contours))
		bw_u16(&w, 0)
		bw_u16(&w, 0)
		bw_u16(&w, 2)
		for _ in 0 ..< 8 do bw_u16(&w, 0)
		tables["maxp"] = w.b[:]
	}
	// hmtx
	{
		w: BW
		for g, i in f.glyphs {
			bw_u16(&w, u16(clamp(int(math.round(g.advance)), 0, 65535)))
			bw_i16(&w, i16(lsbs[i]))
		}
		tables["hmtx"] = w.b[:]
	}
	// mapping
	mapping := make([dynamic][2]int, context.temp_allocator)
	for g, i in f.glyphs {
		for cp in g.unicodes {
			if cp >= 0 && cp <= 0x10ffff && cp != 0xffff do append(&mapping, [2]int{int(cp), i})
		}
	}
	slice.sort_by(mapping[:], proc(a, b: [2]int) -> bool { return a[0] < b[0] })
	// OS/2
	{
		w: BW
		first, last := 0xffff, 0
		total, count := 0, 0
		for m in mapping {
			if m[0] <= 0xffff {
				first = min(first, m[0])
				last = max(last, m[0])
			}
		}
		if first > last do first, last = 0, 0
		for g in f.glyphs {
			if g.advance > 0 {
				total += int(g.advance)
				count += 1
			}
		}
		bw_u16(&w, 4)
		bw_i16(&w, i16(count > 0 ? total / count : 0))
		bw_u16(&w, 400)
		bw_u16(&w, 5)
		bw_u16(&w, 0)
		sub_sup := [?]i16{650, 600, 0, 75, 650, 600, 0, 350, 50, 250}
		for v in sub_sup do bw_i16(&w, v)
		bw_i16(&w, 0)
		for _ in 0 ..< 10 do bw_u8(&w, 0)
		for _ in 0 ..< 4 do bw_u32(&w, 0)
		bw_bytes(&w, transmute([]u8)string("NONE"))
		bw_u16(&w, 0x0040)
		bw_u16(&w, u16(first))
		bw_u16(&w, u16(last))
		bw_i16(&w, i16(f.asc))
		bw_i16(&w, i16(f.desc))
		bw_i16(&w, i16(f.line_gap))
		bw_u16(&w, u16(max(f.asc, 0)))
		bw_u16(&w, u16(abs(min(f.desc, 0))))
		bw_u32(&w, 0)
		bw_u32(&w, 0)
		bw_i16(&w, i16(f.x_height))
		bw_i16(&w, i16(f.cap_height))
		bw_u16(&w, 0)
		bw_u16(&w, 32)
		bw_u16(&w, 0)
		tables["OS/2"] = w.b[:]
	}
	// name
	{
		family := name_str(&f.family)
		style := name_str(&f.style)
		if family == "" do family = "Untitled"
		if style == "" do style = "Regular"
		full := strings.concatenate({family, " ", style}, context.temp_allocator)
		ps_raw := strings.concatenate({family, "-", style}, context.temp_allocator)
		ps := strings.builder_make(context.temp_allocator)
		for ch in ps_raw {
			if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' do strings.write_rune(&ps, ch)
			else if ch == ' ' do strings.write_rune(&ps, '-')
		}
		ids := [?]struct {
			id:   u16,
			text: string,
		}{
			{0, "Generated by Pangolin Scales"},
			{1, family},
			{2, style},
			{3, strings.concatenate({family, ";", style, ";1.0"}, context.temp_allocator)},
			{4, full},
			{5, "Version 1.0"},
			{6, strings.to_string(ps)},
		}
		w: BW
		bw_u16(&w, 0)
		bw_u16(&w, u16(len(ids)))
		bw_u16(&w, u16(6 + len(ids) * 12))
		off := 0
		strs: BW
		for e in ids {
			enc := utf16be(e.text)
			bw_u16(&w, 3)
			bw_u16(&w, 1)
			bw_u16(&w, 0x0409)
			bw_u16(&w, e.id)
			bw_u16(&w, u16(len(enc)))
			bw_u16(&w, u16(off))
			bw_bytes(&strs, enc)
			off += len(enc)
		}
		bw_bytes(&w, strs.b[:])
		tables["name"] = w.b[:]
	}
	// post
	{
		w: BW
		bw_fixed(&w, 3)
		bw_fixed(&w, 0)
		bw_i16(&w, -100)
		bw_i16(&w, 50)
		for _ in 0 ..< 5 do bw_u32(&w, 0)
		tables["post"] = w.b[:]
	}
	// cmap
	{
		fmt4 := make([dynamic]u8, context.temp_allocator)
		{
			Segment :: struct {
				start, end, delta: int,
			}
			segs := make([dynamic]Segment, context.temp_allocator)
			bmp := make([dynamic][2]int, context.temp_allocator)
			for m in mapping do if m[0] <= 0xffff do append(&bmp, m)
			i := 0
			for i < len(bmp) {
				e := i
				for e + 1 < len(bmp) && bmp[e + 1][0] == bmp[e][0] + 1 && bmp[e + 1][1] == bmp[e][1] + 1 do e += 1
				append(&segs, Segment{bmp[i][0], bmp[e][0], (bmp[i][1] - bmp[i][0]) & 0xffff})
				i = e + 1
			}
			append(&segs, Segment{0xffff, 0xffff, 1})
			sc := len(segs)
			entry_sel := 0
			for (1 << uint(entry_sel + 1)) <= sc do entry_sel += 1
			search := 2 * (1 << uint(entry_sel))
			w: BW
			bw_u16(&w, 4)
			bw_u16(&w, u16(16 + sc * 8))
			bw_u16(&w, 0)
			bw_u16(&w, u16(sc * 2))
			bw_u16(&w, u16(search))
			bw_u16(&w, u16(entry_sel))
			bw_u16(&w, u16(sc * 2 - search))
			for s in segs do bw_u16(&w, u16(s.end))
			bw_u16(&w, 0)
			for s in segs do bw_u16(&w, u16(s.start))
			for s in segs do bw_u16(&w, u16(s.delta))
			for _ in 0 ..< sc do bw_u16(&w, 0)
			append(&fmt4, ..w.b[:])
		}
		fmt12 := make([dynamic]u8, context.temp_allocator)
		{
			Group :: struct {
				sc, ec, sg: int,
			}
			groups := make([dynamic]Group, context.temp_allocator)
			i := 0
			for i < len(mapping) {
				e := i
				for e + 1 < len(mapping) && mapping[e + 1][0] == mapping[e][0] + 1 && mapping[e + 1][1] == mapping[e][1] + 1 do e += 1
				append(&groups, Group{mapping[i][0], mapping[e][0], mapping[i][1]})
				i = e + 1
			}
			w: BW
			bw_u16(&w, 12)
			bw_u16(&w, 0)
			bw_u32(&w, u32(16 + len(groups) * 12))
			bw_u32(&w, 0)
			bw_u32(&w, u32(len(groups)))
			for g in groups {
				bw_u32(&w, u32(g.sc))
				bw_u32(&w, u32(g.ec))
				bw_u32(&w, u32(g.sg))
			}
			append(&fmt12, ..w.b[:])
		}
		records := [?][3]int{{0, 3, 4}, {0, 4, 12}, {3, 1, 4}, {3, 10, 12}}
		header := 4 + len(records) * 8
		off4 := header
		off12 := off4 + len(fmt4)
		pad := off12 % 2
		off12 += pad
		w: BW
		bw_u16(&w, 0)
		bw_u16(&w, u16(len(records)))
		for r in records {
			bw_u16(&w, u16(r[0]))
			bw_u16(&w, u16(r[1]))
			bw_u32(&w, u32(r[2] == 4 ? off4 : off12))
		}
		bw_bytes(&w, fmt4[:])
		if pad == 1 do bw_u8(&w, 0)
		bw_bytes(&w, fmt12[:])
		tables["cmap"] = w.b[:]
	}
	// kern
	if len(f.kerning) > 0 {
		pairs := make([dynamic][3]int, context.temp_allocator)
		for k in f.kerning {
			if k.value == 0 do continue
			l, r := -1, -1
			if len(f.glyphs[k.left].unicodes) > 0 do l = int(f.glyphs[k.left].unicodes[0])
			if len(f.glyphs[k.right].unicodes) > 0 do r = int(f.glyphs[k.right].unicodes[0])
			_ = l
			_ = r
			append(&pairs, [3]int{k.left, k.right, k.value})
		}
		if len(pairs) > 0 {
			slice.sort_by(pairs[:], proc(a, b: [3]int) -> bool { return a[0] < b[0] || (a[0] == b[0] && a[1] < b[1]) })
			np := len(pairs)
			search := 6
			sel := 0
			for search * 2 <= np * 6 {
				search *= 2
				sel += 1
			}
			w: BW
			bw_u16(&w, 0)
			bw_u16(&w, 1)
			bw_u16(&w, 0)
			bw_u16(&w, u16(14 + np * 6))
			bw_u16(&w, 0)
			bw_u16(&w, u16(np))
			bw_u16(&w, u16(search))
			bw_u16(&w, u16(sel))
			bw_u16(&w, u16(np * 6 - search))
			for p in pairs {
				bw_u16(&w, u16(p[0]))
				bw_u16(&w, u16(p[1]))
				bw_i16(&w, i16(p[2]))
			}
			tables["kern"] = w.b[:]
		}
	}

	tags := make([dynamic]string, context.temp_allocator)
	for k in tables do append(&tags, k)
	slice.sort(tags[:])
	nt := len(tags)
	header_size := 12 + nt * 16
	Entry :: struct {
		tag:            string,
		sum, off, len_: u32,
		bytes:          []u8,
	}
	dir := make([dynamic]Entry, context.temp_allocator)
	offset := header_size
	for tg in tags {
		b := tables[tg]
		padded := make([]u8, (len(b) + 3) / 4 * 4, context.temp_allocator)
		copy(padded, b)
		append(&dir, Entry{tg, ttf_checksum(padded), u32(offset), u32(len(b)), padded})
		offset += len(padded)
	}
	font := make([]u8, offset, context.temp_allocator)
	put32 :: proc(b: []u8, at: int, v: u32) {
		b[at], b[at + 1], b[at + 2], b[at + 3] = u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)
	}
	put16 :: proc(b: []u8, at: int, v: u16) {
		b[at], b[at + 1] = u8(v >> 8), u8(v)
	}
	put32(font, 0, 0x00010000)
	put16(font, 4, u16(nt))
	sr := 1
	es := 0
	for sr * 2 <= nt {
		sr *= 2
		es += 1
	}
	put16(font, 6, u16(sr * 16))
	put16(font, 8, u16(es))
	put16(font, 10, u16(nt * 16 - sr * 16))
	pos := 12
	head_off := 0
	for e in dir {
		for i in 0 ..< 4 do font[pos + i] = e.tag[i]
		put32(font, pos + 4, e.sum)
		put32(font, pos + 8, e.off)
		put32(font, pos + 12, e.len_)
		copy(font[e.off:], e.bytes)
		if e.tag == "head" do head_off = int(e.off)
		pos += 16
	}
	put32(font, head_off + 8, 0xb1b0afba - ttf_checksum(font))
	return font, ""
}

// Reader ------------------------------------------------------------------------------------------------------

be16 :: proc(b: []u8, i: int) -> int {
	if i < 0 || i + 2 > len(b) do return 0
	return int(b[i]) << 8 | int(b[i + 1])
}

be32 :: proc(b: []u8, i: int) -> int {
	return be16(b, i) << 16 | be16(b, i + 2)
}

ttf_table :: proc(b: []u8, tag: string) -> (off, length: int, ok: bool) {
	base := 0
	// TrueType collections: use the first font
	if len(b) > 12 && string(b[0:4]) == "ttcf" do base = be32(b, 12)
	n := be16(b, base + 4)
	for i in 0 ..< n {
		e := base + 12 + i * 16
		if e + 16 > len(b) do break
		if string(b[e:e + 4]) == tag do return be32(b, e + 8), be32(b, e + 12), true
	}
	return 0, 0, false
}

// Reads a name record (prefers Windows Unicode, then Mac Roman).
ttf_name :: proc(b: []u8, id: int) -> string {
	off, length, ok := ttf_table(b, "name")
	if !ok do return ""
	t := b[off:min(off + length, len(b))]
	count := be16(t, 2)
	so := be16(t, 4)
	best := ""
	for i in 0 ..< count {
		r := 6 + i * 12
		if be16(t, r + 6) != id do continue
		plat, l, o := be16(t, r), be16(t, r + 8), be16(t, r + 10)
		if so + o + l > len(t) do continue
		raw := t[so + o:so + o + l]
		if plat == 3 || plat == 0 {
			sb := strings.builder_make(context.temp_allocator)
			for k := 0; k + 1 < len(raw); k += 2 {
				u := u16(raw[k]) << 8 | u16(raw[k + 1])
				strings.write_rune(&sb, rune(u))
			}
			return strings.clone(strings.to_string(sb), context.temp_allocator)
		}
		if plat == 1 && best == "" do best = strings.clone(string(raw), context.temp_allocator)
	}
	return best
}

// glyph index -> codepoints from the best Unicode cmap subtable.
ttf_cmap :: proc(b: []u8, num_glyphs: int) -> [][dynamic]rune {
	res := make([][dynamic]rune, num_glyphs, context.temp_allocator)
	off, length, ok := ttf_table(b, "cmap")
	if !ok do return res
	t := b[off:min(off + length, len(b))]
	n := be16(t, 2)
	best_off, best_score := -1, -1
	for i in 0 ..< n {
		r := 4 + i * 8
		plat, enc, so := be16(t, r), be16(t, r + 2), be32(t, r + 4)
		score := -1
		if plat == 3 && enc == 10 do score = 4
		else if plat == 0 && (enc == 4 || enc == 6) do score = 3
		else if plat == 3 && enc == 1 do score = 2
		else if plat == 0 do score = 1
		if score > best_score && so < len(t) {
			best_score, best_off = score, so
		}
	}
	if best_off < 0 do return res
	st := t[best_off:]
	add :: proc(res: [][dynamic]rune, g: int, cp: int) {
		if g > 0 && g < len(res) do append(&res[g], rune(cp))
	}
	switch be16(st, 0) {
	case 4:
		sc := be16(st, 6) / 2
		for s in 0 ..< sc {
			end := be16(st, 14 + s * 2)
			start := be16(st, 16 + sc * 2 + s * 2)
			delta := be16(st, 16 + sc * 4 + s * 2)
			ro_pos := 16 + sc * 6 + s * 2
			ro := be16(st, ro_pos)
			if start == 0xffff do continue
			for c in start ..= end {
				g: int
				if ro == 0 {
					g = (c + delta) & 0xffff
				} else {
					gp := ro_pos + ro + (c - start) * 2
					g = be16(st, gp)
					if g != 0 do g = (g + delta) & 0xffff
				}
				add(res, g, c)
			}
		}
	case 12:
		ng := be32(st, 12)
		for i in 0 ..< ng {
			p := 16 + i * 12
			sc, ec, sg := be32(st, p), be32(st, p + 4), be32(st, p + 8)
			if ec - sc > 0x20000 do continue
			for c in sc ..= ec do add(res, sg + (c - sc), c)
		}
	case 6:
		first, cnt := be16(st, 6), be16(st, 8)
		for i in 0 ..< cnt do add(res, be16(st, 10 + i * 2), first + i)
	case 0:
		for c in 0 ..< 256 do if 6 + c < len(st) do add(res, int(st[6 + c]), c)
	}
	return res
}

MAX_IMPORT_GLYPHS :: 3000

ttf_read :: proc(data: []u8) -> (f: ^Font_Doc, err: string) {
	info: stbtt.fontinfo
	if !stbtt.InitFont(&info, raw_data(data), stbtt.GetFontOffsetForIndex(raw_data(data), 0)) {
		return nil, "Not a valid TrueType / OpenType font."
	}
	ng := int(info.numGlyphs)
	f = new(Font_Doc)
	f.remove_overlap = true
	f.upm = 1000
	if off, _, ok := ttf_table(data, "head"); ok do f.upm = max(be16(data, off + 18), 16)
	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&info, &asc, &desc, &gap)
	f.asc, f.desc, f.line_gap = int(asc), int(desc), int(gap)
	f.x_height, f.cap_height = f.upm / 2, f.upm * 7 / 10
	if off, length, ok := ttf_table(data, "OS/2"); ok && length >= 90 && be16(data, off) >= 2 {
		xh, ch := be16(data, off + 86), be16(data, off + 88)
		if xh >= 0x8000 do xh -= 0x10000
		if ch >= 0x8000 do ch -= 0x10000
		if xh > 0 do f.x_height = xh
		if ch > 0 do f.cap_height = ch
	}
	fam := ttf_name(data, 16)
	if fam == "" do fam = ttf_name(data, 1)
	sty := ttf_name(data, 17)
	if sty == "" do sty = ttf_name(data, 2)
	f.family = make_name(fam == "" ? "Untitled" : fam)
	f.style = make_name(sty == "" ? "Regular" : sty)
	cmap := ttf_cmap(data, ng)
	for gi in 0 ..< min(ng, MAX_IMPORT_GLYPHS) {
		g: Font_Glyph
		adv, lsb: i32
		stbtt.GetGlyphHMetrics(&info, i32(gi), &adv, &lsb)
		g.advance = f32(adv)
		verts: [^]stbtt.vertex
		nv := stbtt.GetGlyphShape(&info, i32(gi), &verts)
		if nv > 0 {
			P :: proc(x, y: stbtt.vertex_type) -> Vec2 {
				return {f32(x), f32(y)}
			}
			open := false
			for i in 0 ..< int(nv) {
				v := verts[i]
				switch v.type {
				case 1:
					if open do path_close(&g.segs)
					path_move(&g.segs, P(v.x, v.y))
					open = true
				case 2:
					path_line(&g.segs, P(v.x, v.y))
				case 3:
					path_quad(&g.segs, P(v.cx, v.cy), P(v.x, v.y))
				case 4:
					path_cubic(&g.segs, P(v.cx, v.cy), P(v.cx1, v.cy1), P(v.x, v.y))
				}
			}
			if open do path_close(&g.segs)
			stbtt.FreeShape(&info, verts)
		}
		for cp in cmap[gi] do append(&g.unicodes, cp)
		name := "glyph"
		if gi == 0 do name = ".notdef"
		else if len(g.unicodes) > 0 do name = glyph_name_for(g.unicodes[0])
		else do name = fmt_glyph_index(gi)
		g.name = make_name(name)
		append(&f.glyphs, g)
	}
	// keep the cmap codepoints of glyphs beyond the import limit out; mention it to the caller
	if ng > MAX_IMPORT_GLYPHS do err = "large font: only the first glyphs were loaded"
	return f, err
}

ASCII_NAMES := [?]string {
	"space", "exclam", "quotedbl", "numbersign", "dollar", "percent", "ampersand", "quotesingle", "parenleft", "parenright",
	"asterisk", "plus", "comma", "hyphen", "period", "slash", "zero", "one", "two", "three", "four", "five", "six", "seven",
	"eight", "nine", "colon", "semicolon", "less", "equal", "greater", "question", "at",
}

glyph_name_for :: proc(cp: rune) -> string {
	switch {
	case cp >= 'A' && cp <= 'Z', cp >= 'a' && cp <= 'z':
		return strings.clone_from_bytes([]u8{u8(cp)}, context.temp_allocator)
	case cp >= 32 && cp <= 64:
		return ASCII_NAMES[int(cp) - 32]
	case cp == '[':  return "bracketleft"
	case cp == '\\': return "backslash"
	case cp == ']':  return "bracketright"
	case cp == '^':  return "asciicircum"
	case cp == '_':  return "underscore"
	case cp == '`':  return "grave"
	case cp == '{':  return "braceleft"
	case cp == '|':  return "bar"
	case cp == '}':  return "braceright"
	case cp == '~':  return "asciitilde"
	}
	if cp > 0xffff do return fmt_u(cp, "u%05X")
	return fmt_u(cp, "uni%04X")
}
