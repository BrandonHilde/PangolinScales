package pangolin

import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// ---------------------------------------------------------------------------
// Minimal non-validating XML parser (enough for SVG). Everything is allocated on the temp allocator.
// ---------------------------------------------------------------------------

XAttr :: struct {
	k, v: string,
}

XNode :: struct {
	tag:     string, // without namespace prefix; empty for text nodes
	attrs:   [dynamic]XAttr,
	kids:    [dynamic]^XNode,
	text:    string, // text nodes only
	is_text: bool,
	parent:  ^XNode,
}

xattr :: proc(n: ^XNode, key: string) -> (string, bool) {
	for a in n.attrs {
		if a.k == key do return a.v, true
	}
	return "", false
}

xattr_or :: proc(n: ^XNode, key: string, def := "") -> string {
	v, ok := xattr(n, key)
	return ok ? v : def
}

local_name :: proc(s: string) -> string {
	if i := strings.last_index_byte(s, ':'); i >= 0 do return s[i + 1:]
	return s
}

is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

decode_entities :: proc(s: string) -> string {
	if strings.index_byte(s, '&') < 0 do return s
	sb := strings.builder_make(context.temp_allocator)
	i := 0
	for i < len(s) {
		if s[i] == '&' {
			if semi := strings.index_byte(s[i:], ';'); semi > 1 && semi < 12 {
				ent := s[i + 1:i + semi]
				done := true
				switch ent {
				case "amp":  strings.write_byte(&sb, '&')
				case "lt":   strings.write_byte(&sb, '<')
				case "gt":   strings.write_byte(&sb, '>')
				case "quot": strings.write_byte(&sb, '"')
				case "apos": strings.write_byte(&sb, '\'')
				case:
					done = false
					if len(ent) > 1 && ent[0] == '#' {
						v: u64
						ok: bool
						if ent[1] == 'x' || ent[1] == 'X' do v, ok = strconv.parse_u64_of_base(ent[2:], 16)
						else do v, ok = strconv.parse_u64_of_base(ent[1:], 10)
						if ok {
							strings.write_rune(&sb, rune(v))
							done = true
						}
					}
				}
				if done {
					i += semi + 1
					continue
				}
			}
		}
		strings.write_byte(&sb, s[i])
		i += 1
	}
	return strings.to_string(sb)
}

// A node in the temp allocator, lists and all: left as their zero value the lists would go on the heap and stay there.
@(private = "file")
xnode_new :: proc() -> ^XNode {
	n := new(XNode, context.temp_allocator)
	n.attrs = make([dynamic]XAttr, context.temp_allocator)
	n.kids = make([dynamic]^XNode, context.temp_allocator)
	return n
}

xml_parse :: proc(src: string) -> ^XNode {
	root := xnode_new()
	cur := root
	i := 0
	n := len(src)
	// skip BOM
	if n >= 3 && src[0] == 0xEF && src[1] == 0xBB && src[2] == 0xBF do i = 3
	for i < n {
		if src[i] != '<' {
			j := strings.index_byte(src[i:], '<')
			end := j < 0 ? n : i + j
			txt := src[i:end]
			if len(strings.trim_space(txt)) > 0 || cur.tag == "text" || cur.tag == "tspan" || cur.tag == "style" {
				t := xnode_new()
				t.is_text = true
				t.text = decode_entities(txt)
				t.parent = cur
				append(&cur.kids, t)
			}
			i = end
			continue
		}
		rest := src[i:]
		switch {
		case strings.has_prefix(rest, "<!--"):
			e := strings.index(rest, "-->")
			i = e < 0 ? n : i + e + 3
		case strings.has_prefix(rest, "<![CDATA["):
			e := strings.index(rest, "]]>")
			end := e < 0 ? n : i + e
			t := xnode_new()
			t.is_text = true
			t.text = src[i + 9:end]
			t.parent = cur
			append(&cur.kids, t)
			i = e < 0 ? n : end + 3
		case strings.has_prefix(rest, "<?"):
			e := strings.index(rest, "?>")
			i = e < 0 ? n : i + e + 2
		case strings.has_prefix(rest, "<!"):
			// doctype, possibly with an internal subset in brackets
			depth := 0
			k := i
			for k < n {
				if src[k] == '[' do depth += 1
				if src[k] == ']' do depth -= 1
				if src[k] == '>' && depth <= 0 do break
				k += 1
			}
			i = k + 1
		case strings.has_prefix(rest, "</"):
			e := strings.index_byte(rest, '>')
			i = e < 0 ? n : i + e + 1
			if cur.parent != nil do cur = cur.parent
		case:
			// start tag
			k := i + 1
			for k < n && !is_space(src[k]) && src[k] != '>' && src[k] != '/' do k += 1
			el := xnode_new()
			el.tag = local_name(src[i + 1:k])
			el.parent = cur
			append(&cur.kids, el)
			// attributes
			self_close := false
			for k < n {
				for k < n && is_space(src[k]) do k += 1
				if k >= n do break
				if src[k] == '>' {
					k += 1
					break
				}
				if src[k] == '/' {
					self_close = true
					k += 1
					continue
				}
				a0 := k
				for k < n && src[k] != '=' && !is_space(src[k]) && src[k] != '>' && src[k] != '/' do k += 1
				name := src[a0:k]
				for k < n && is_space(src[k]) do k += 1
				val := ""
				if k < n && src[k] == '=' {
					k += 1
					for k < n && is_space(src[k]) do k += 1
					if k < n && (src[k] == '"' || src[k] == '\'') {
						q := src[k]
						k += 1
						v0 := k
						for k < n && src[k] != q do k += 1
						val = decode_entities(src[v0:k])
						k += 1
					} else {
						v0 := k
						for k < n && !is_space(src[k]) && src[k] != '>' do k += 1
						val = src[v0:k]
					}
				}
				if len(name) > 0 {
					// keep "xlink:href" distinguishable from "href" only by local name
					append(&el.attrs, XAttr{local_name(name), val})
				}
			}
			i = k
			if !self_close do cur = el
		}
	}
	// the document element
	for c in root.kids {
		if !c.is_text do return c
	}
	return nil
}

_ :: utf8
