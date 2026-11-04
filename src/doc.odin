package pangolin

import "core:fmt"
import "core:math"
import "core:slice"

// ---------------------------------------------------------------------------
// Document model: a tree of nodes. Every node has a local transform; primitives (rect, ellipse) keep their
// parameters so they round-trip as <rect> / <ellipse>, and convert to a path for editing and path operations.
// ---------------------------------------------------------------------------

Node_Kind :: enum u8 {
	Group,
	Path,
	Rect,
	Ellipse,
	Text,
}

Node :: struct {
	uid:         u32,
	kind:        Node_Kind,
	name:        Name,
	visible:     bool,
	locked:      bool,
	xf:          Mat,
	fill:        Paint,
	stroke:      Paint,
	sw:          f32,
	cap:         Cap,
	join:        Join,
	miter:       f32,
	dash:        [4]f32,
	ndash:       int,
	dash_off:    f32,
	opacity:     f32,
	even_odd:    bool,
	// geometry
	segs:        Path, // Path
	x, y, w, h:  f32, // Rect: top-left and size; Ellipse: x, y = centre, w, h = radii; Text: baseline origin
	rx, ry:      f32, // Rect corner radii
	// text
	text:        [dynamic]u8,
	font:        Name,
	size:        f32,
	children:    [dynamic]^Node,
}

// Snapshot of what undo restores. One stack serves the whole document, so a state says which frame it belongs to,
// and undoing it goes to that frame. A change to the list of frames (`structure`) is more than one frame's drawing,
// so it holds a clone of every frame and the tags instead of `root`.
Doc_State :: struct {
	w, h:      f32,
	root:      ^Node,
	frame:     int,
	structure: bool,
	frames:    []Frame,
	tags:      []Tag,
}

Doc :: struct {
	kind:      Doc_Kind,
	title:     Name,
	path:      string, // empty if never saved
	w, h:      f32, // artboard size in user units
	root:      ^Node, // the live frame's drawing
	frames:    [dynamic]Frame,
	active_frame: int,
	tags:      [dynamic]Tag,
	next_uid:  u32,
	sel:       [dynamic]u32,
	undo:      [dynamic]Doc_State,
	redo:      [dynamic]Doc_State,
	version:   int, // bumped on every change; render caches compare against it
	modified:  bool,
	// view
	zoom:      f32,
	ox, oy:    f32, // screen position of artboard (0,0)
	view_init: bool,
	// font mode
	font:      ^Font_Doc,
	// reference image shown over the page (not saved)
	trace:     Texture,
	trace_a:   f32,
	trace_s:   f32, // document units per image pixel
	trace_pos: Vec2,
}

Doc_Kind :: enum {
	Svg,
	Font,
}

docs: [dynamic]^Doc
doc: ^Doc

UNDO_MAX :: 100

node_new :: proc(d: ^Doc, kind: Node_Kind) -> ^Node {
	n := new(Node)
	d.next_uid += 1
	n.uid = d.next_uid
	n.kind = kind
	n.visible = true
	n.xf = MAT_ID
	n.opacity = 1
	n.miter = 4
	n.sw = 1
	n.size = 16
	return n
}

node_free :: proc(n: ^Node) {
	if n == nil do return
	for c in n.children do node_free(c)
	delete(n.children)
	delete(n.segs)
	delete(n.text)
	free(n)
}

node_clone :: proc(n: ^Node) -> ^Node {
	c := new(Node)
	c^ = n^
	c.segs = path_clone(n.segs[:])
	c.text = make([dynamic]u8, len(n.text))
	copy(c.text[:], n.text[:])
	c.children = make([dynamic]^Node, 0, len(n.children))
	for ch in n.children do append(&c.children, node_clone(ch))
	return c
}

doc_new :: proc(kind: Doc_Kind, title: string, w, h: f32) -> ^Doc {
	d := new(Doc)
	d.kind = kind
	d.title = make_name(title)
	d.w, d.h = w, h
	d.zoom = 1
	d.root = node_new(d, .Group)
	name_set(&d.root.name, "root")
	append(&d.frames, Frame{root = d.root, duration = FRAME_DURATION, thumb_ver = -1})
	return d
}

add_doc :: proc(d: ^Doc) {
	append(&docs, d)
	doc = d
	stop_playback()
	play_tag = -1
}

doc_display_name :: proc(d: ^Doc) -> string {
	if d == nil do return "Pangolin Scales"
	return fmt.tprintf("%s%s", name_str(&d.title), d.modified ? "*" : "")
}

doc_changed :: proc(d: ^Doc) {
	d.version += 1
	d.modified = true
	if d.active_frame < len(d.frames) {
		f := &d.frames[d.active_frame]
		f.root = d.root
		f.ver += 1
	}
	stop_playback() // anything that edits stops the animation
}

// Undo --------------------------------------------------------------------------------------------------

// The drawing of frame `i`, as it is now.
state_of_frame :: proc(d: ^Doc, i: int) -> Doc_State {
	return Doc_State{w = d.w, h = d.h, root = node_clone(frame_root(d, i)), frame = i}
}

state_take :: proc(d: ^Doc) -> Doc_State {
	return state_of_frame(d, d.active_frame)
}

// Every frame and the tags, as they are now.
state_take_frames :: proc(d: ^Doc) -> Doc_State {
	s := Doc_State {
		w         = d.w,
		h         = d.h,
		frame     = d.active_frame,
		structure = true,
		frames    = make([]Frame, len(d.frames)),
		tags      = slice.clone(d.tags[:]),
	}
	for f, i in d.frames {
		s.frames[i] = Frame{root = node_clone(frame_root(d, i)), duration = f.duration, thumb_ver = -1}
	}
	return s
}

state_free :: proc(s: ^Doc_State) {
	node_free(s.root)
	s.root = nil
	for f in s.frames do node_free(f.root)
	delete(s.frames)
	delete(s.tags)
	s.frames, s.tags = nil, nil
}

history_add :: proc(d: ^Doc, s: Doc_State) {
	append(&d.undo, s)
	if len(d.undo) > UNDO_MAX {
		state_free(&d.undo[0])
		ordered_remove(&d.undo, 0)
	}
	for &r in d.redo do state_free(&r)
	clear(&d.redo)
}

// Call before a change: remembers the current state.
history_push :: proc(d: ^Doc) {
	history_add(d, state_take(d))
}

// Call before changing the frames or the tags.
frames_history_push :: proc(d: ^Doc) {
	history_add(d, state_take_frames(d))
}

state_restore :: proc(d: ^Doc, s: Doc_State) {
	if s.structure {
		for &f, i in d.frames {
			node_free(frame_root(d, i))
			tex_destroy(&f.thumb)
		}
		clear(&d.frames)
		append(&d.frames, ..s.frames)
		delete(s.frames)
		clear(&d.tags)
		append(&d.tags, ..s.tags)
		delete(s.tags)
		d.active_frame = clamp(s.frame, 0, len(d.frames) - 1)
		d.root = d.frames[d.active_frame].root
		if play_tag >= len(d.tags) do play_tag = -1
	} else {
		if s.frame != d.active_frame && s.frame >= 0 && s.frame < len(d.frames) {
			d.frames[d.active_frame].root = d.root
			d.active_frame = s.frame
			d.root = d.frames[s.frame].root
			clear(&d.sel)
		}
		node_free(d.root)
		d.root = s.root
	}
	d.w, d.h = s.w, s.h
	// drop selection entries that no longer exist
	k := 0
	for uid in d.sel {
		if node_find(d.root, uid) != nil {
			d.sel[k] = uid
			k += 1
		}
	}
	resize(&d.sel, k)
	doc_changed(d)
}

// Moves one step from one stack to the other, leaving behind what brings it back: the same kind of state, for the
// same frame.
@(private = "file")
history_step :: proc(d: ^Doc, from, to: ^[dynamic]Doc_State) {
	if len(from) == 0 do return
	s := pop(from)
	if s.structure {
		append(to, state_take_frames(d))
	} else {
		append(to, state_of_frame(d, clamp(s.frame, 0, len(d.frames) - 1)))
	}
	state_restore(d, s)
}

history_undo :: proc(d: ^Doc) {
	history_step(d, &d.undo, &d.redo)
}

history_redo :: proc(d: ^Doc) {
	history_step(d, &d.redo, &d.undo)
}

// Tree helpers ------------------------------------------------------------------------------------------

node_find :: proc(root: ^Node, uid: u32) -> ^Node {
	if root.uid == uid do return root
	for c in root.children {
		if r := node_find(c, uid); r != nil do return r
	}
	return nil
}

// Parent of `n` inside `root` (nil for the root).
node_parent :: proc(root, n: ^Node) -> ^Node {
	for c in root.children {
		if c == n do return root
		if r := node_parent(c, n); r != nil do return r
	}
	return nil
}

node_index :: proc(parent, n: ^Node) -> int {
	for c, i in parent.children {
		if c == n do return i
	}
	return -1
}

// Transform from the node's local space to document space.
node_world :: proc(root, n: ^Node) -> Mat {
	chain := make([dynamic]^Node, context.temp_allocator)
	cur := n
	for cur != nil && cur != root {
		append(&chain, cur)
		cur = node_parent(root, cur)
	}
	m := MAT_ID
	#reverse for c in chain do m = mat_mul(m, c.xf)
	return m
}

sel_has :: proc(d: ^Doc, uid: u32) -> bool {
	for u in d.sel {
		if u == uid do return true
	}
	return false
}

sel_set :: proc(d: ^Doc, n: ^Node) {
	clear(&d.sel)
	if n != nil do append(&d.sel, n.uid)
}

sel_toggle :: proc(d: ^Doc, n: ^Node) {
	for u, i in d.sel {
		if u == n.uid {
			ordered_remove(&d.sel, i)
			return
		}
	}
	append(&d.sel, n.uid)
}

// Selected nodes, in document (z) order. Allocated on the temp allocator.
sel_nodes :: proc(d: ^Doc) -> []^Node {
	out := make([dynamic]^Node, context.temp_allocator)
	collect :: proc(d: ^Doc, n: ^Node, out: ^[dynamic]^Node) {
		for c in n.children {
			if sel_has(d, c.uid) do append(out, c)
			else do collect(d, c, out)
		}
	}
	collect(d, d.root, &out)
	return out[:]
}

// Geometry ----------------------------------------------------------------------------------------------

// Path segments of a primitive or path node, in the node's local space (temp allocated for primitives).
node_segs :: proc(n: ^Node) -> []Seg {
	switch n.kind {
	case .Path:
		return n.segs[:]
	case .Rect:
		p := make(Path, context.temp_allocator)
		path_rect(&p, n.x, n.y, n.w, n.h, n.rx, n.ry)
		return p[:]
	case .Ellipse:
		p := make(Path, context.temp_allocator)
		path_ellipse(&p, n.x, n.y, n.w, n.h)
		return p[:]
	case .Group, .Text:
	}
	return nil
}

// Turns a rect / ellipse into a plain path (editing, path operations).
node_to_path :: proc(n: ^Node) {
	if n.kind == .Rect || n.kind == .Ellipse {
		s := node_segs(n)
		n.segs = path_clone(s)
		n.kind = .Path
	}
}

// Local bounds of the geometry (without stroke).
node_local_bounds :: proc(n: ^Node) -> Bounds {
	if n.kind == .Group {
		b := BOUNDS_EMPTY
		for c in n.children {
			if c.visible do b = bounds_union(b, node_bounds(c))
		}
		return b
	}
	if n.kind == .Text {
		return text_bounds(n)
	}
	return path_bounds(node_segs(n))
}

// Bounds in the parent's space (after the node's own transform).
node_bounds :: proc(n: ^Node) -> Bounds {
	b := node_local_bounds(n)
	if bounds_empty(b) do return b
	return bounds_transform(b, n.xf)
}

// Visual bounds including stroke width.
node_visual_bounds :: proc(n: ^Node) -> Bounds {
	if n.kind == .Group {
		b := BOUNDS_EMPTY
		for c in n.children {
			if c.visible do b = bounds_union(b, bounds_transform(node_visual_bounds(c), n.xf))
		}
		return bounds_empty(b) ? b : b
	}
	b := node_local_bounds(n)
	if bounds_empty(b) do return b
	if n.stroke.kind != .None {
		b = bounds_inflate(b, n.sw * (n.join == .Miter ? max(n.miter, 1) : 1) / 2)
	}
	return bounds_transform(b, n.xf)
}

// Moves a node by a delta in its parent's space.
node_translate :: proc(n: ^Node, dx, dy: f32) {
	n.xf = mat_mul(mat_translate(dx, dy), n.xf)
}

// Applies `m` (in the parent's space) to the node.
node_apply :: proc(n: ^Node, m: Mat) {
	n.xf = mat_mul(m, n.xf)
}

// Bakes the node's transform into its geometry (paths only), keeping the visual result.
node_bake :: proc(n: ^Node) {
	if n.kind == .Group || n.kind == .Text do return
	node_to_path(n)
	path_transform(n.segs[:], n.xf)
	// gradients follow the geometry
	for p in ([?]^Paint{&n.fill, &n.stroke}) {
		if p.kind == .Linear || p.kind == .Radial {
			p.p0 = mat_apply(n.xf, p.p0)
			if p.kind == .Linear {
				p.p1 = mat_apply(n.xf, p.p1)
			} else {
				p.p1.x *= mat_scale_factor(n.xf)
			}
		}
	}
	n.sw *= mat_scale_factor(n.xf)
	n.xf = MAT_ID
}

stroke_style_of :: proc(n: ^Node) -> Stroke_Style {
	return Stroke_Style{width = n.sw, cap = n.cap, join = n.join, miter = n.miter, dash = n.dash, ndash = n.ndash, offset = n.dash_off}
}

// Creates a styled path node with the app's current colors.
new_shape :: proc(d: ^Doc, kind: Node_Kind) -> ^Node {
	n := node_new(d, kind)
	n.fill = cur_fill
	n.stroke = cur_stroke
	n.sw = cur_sw
	n.cap, n.join = cur_cap, cur_join
	label := [Node_Kind]string {
		.Group   = "Group",
		.Path    = "Path",
		.Rect    = "Rectangle",
		.Ellipse = "Ellipse",
		.Text    = "Text",
	}
	name_set(&n.name, label[kind])
	return n
}

// Current drawing style, edited by the fill / stroke panel.
cur_fill: Paint = {kind = .Solid, color = {246, 170, 104, 255}}
cur_stroke: Paint = {kind = .Solid, color = {40, 30, 24, 255}}
cur_sw: f32 = 2
cur_cap: Cap = .Butt
cur_join: Join = .Miter

_ :: math
