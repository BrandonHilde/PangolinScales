package pangolin

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// Fonts for text objects: the bundled families plus every TTF / OTF installed on the system. System fonts are
// only listed (by file name) and loaded when first used.
// ---------------------------------------------------------------------------

ALICE_DATA :: #load("../assets/fonts/Alice-Regular.ttf")
JERSEY_DATA :: #load("../assets/fonts/Jersey10-Regular.ttf")

DEFAULT_FONT :: "Alice"

Ufont :: struct {
	name:  string,
	path:  string, // empty for bundled fonts
	data:  []u8,
	info:  stbtt.fontinfo,
	ok:    bool,
	tried: bool,
}

ufonts: [dynamic]^Ufont
ufonts_scanned: bool

ufont_add :: proc(name, path: string, data: []u8 = nil) {
	for f in ufonts {
		if f.name == name do return
	}
	f := new(Ufont)
	f.name = strings.clone(name)
	f.path = strings.clone(path)
	f.data = data
	append(&ufonts, f)
}

when ODIN_OS == .Windows {
	FONT_DIRS := [?]string{"C:/Windows/Fonts"}
} else when ODIN_OS == .Darwin {
	FONT_DIRS := [?]string{"/Library/Fonts", "/System/Library/Fonts"}
} else {
	FONT_DIRS := [?]string{"/usr/share/fonts", "/usr/local/share/fonts"}
}

scan_dir :: proc(dir: string, depth: int) {
	entries, err := os.read_directory_by_path(dir, 0, context.temp_allocator)
	if err != nil do return
	for e in entries {
		if e.type == .Directory {
			if depth < 3 do scan_dir(e.fullpath, depth + 1)
			continue
		}
		ext := strings.to_lower(filepath.ext(e.name), context.temp_allocator)
		if ext == ".ttf" || ext == ".otf" {
			ufont_add(filepath.stem(e.name), e.fullpath)
		}
	}
}

fonts_scan :: proc() {
	if ufonts_scanned do return
	ufonts_scanned = true
	ufont_add("Alice", "", ALICE_DATA)
	ufont_add("Jersey 10", "", JERSEY_DATA)
	for d in FONT_DIRS do scan_dir(d, 0)
}

font_find :: proc(name: string) -> ^Ufont {
	fonts_scan()
	for f in ufonts {
		if f.name == name do return f
	}
	return ufonts[0]
}

// Loads (once) and returns the font, or nil when the file cannot be read.
font_load :: proc(f: ^Ufont) -> ^Ufont {
	if !f.tried {
		f.tried = true
		if f.data == nil && f.path != "" {
			if d, err := os.read_entire_file(f.path, context.allocator); err == nil do f.data = d
		}
		if f.data != nil {
			f.ok = bool(stbtt.InitFont(&f.info, raw_data(f.data), stbtt.GetFontOffsetForIndex(raw_data(f.data), 0)))
		}
	}
	return f.ok ? f : nil
}

// Appends the outline of one codepoint at `scale` (em units to document units), with the origin at (ox, oy) on the
// baseline and y pointing down. Returns the advance in document units.
glyph_segs :: proc(f: ^Ufont, cp: rune, scale, ox, oy: f32, out: ^Path) -> f32 {
	adv, lsb: i32
	stbtt.GetCodepointHMetrics(&f.info, cp, &adv, &lsb)
	verts: [^]stbtt.vertex
	nv := stbtt.GetCodepointShape(&f.info, cp, &verts)
	if nv > 0 {
		P :: proc(x, y: stbtt.vertex_type, scale, ox, oy: f32) -> Vec2 {
			return {ox + f32(x) * scale, oy - f32(y) * scale}
		}
		open := false
		for i in 0 ..< int(nv) {
			v := verts[i]
			switch v.type {
			case 1:
				if open do path_close(out)
				path_move(out, P(v.x, v.y, scale, ox, oy))
				open = true
			case 2:
				path_line(out, P(v.x, v.y, scale, ox, oy))
			case 3:
				path_quad(out, P(v.cx, v.cy, scale, ox, oy), P(v.x, v.y, scale, ox, oy))
			case 4:
				path_cubic(out, P(v.cx, v.cy, scale, ox, oy), P(v.cx1, v.cy1, scale, ox, oy), P(v.x, v.y, scale, ox, oy))
			}
		}
		if open do path_close(out)
		stbtt.FreeShape(&f.info, verts)
	}
	return f32(adv) * scale
}

text_str :: proc(n: ^Node) -> string {
	return string(n.text[:])
}

// Outlines of a text node in its local space (temp allocated).
text_segs :: proc(n: ^Node) -> []Seg {
	f := font_load(font_find(name_str(&n.font)))
	out := make(Path, context.temp_allocator)
	if f == nil do return out[:]
	scale := stbtt.ScaleForMappingEmToPixels(&f.info, n.size)
	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&f.info, &asc, &desc, &gap)
	line_h := f32(asc - desc + gap) * scale
	x, y := n.x, n.y
	prev: rune
	for r in text_str(n) {
		if r == '\n' {
			x = n.x
			y += line_h
			prev = 0
			continue
		}
		if prev != 0 do x += f32(stbtt.GetCodepointKernAdvance(&f.info, prev, r)) * scale
		x += glyph_segs(f, r, scale, x, y, &out)
		prev = r
	}
	return out[:]
}

text_bounds :: proc(n: ^Node) -> Bounds {
	b := path_bounds(text_segs(n))
	if bounds_empty(b) {
		// empty text still has an insertion box
		return Bounds{n.x, n.y - n.size, n.x + n.size / 2, n.y}
	}
	return b
}

// Converts a text node into a group-less path node (Path > Convert to Outlines).
text_to_path :: proc(n: ^Node) {
	if n.kind != .Text do return
	segs := text_segs(n)
	n.segs = path_clone(segs)
	n.kind = .Path
	clear(&n.text)
	name_set(&n.name, "Outlines")
}

_ :: utf8
