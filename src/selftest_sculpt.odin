package pangolin

import "core:fmt"
import "core:math"

// Tests of the Sculpt and Extend tools, driven with simulated pointer input.

@(private = "file")
RED :: Color{220, 30, 40, 255}

@(private = "file")
add_box :: proc(d: ^Doc, x, y, w, h: f32) -> ^Node {
	n := new_shape(d, .Rect)
	n.x, n.y, n.w, n.h = x, y, w, h
	n.fill, n.stroke = paint_solid(RED), paint_none()
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

@(private = "file")
add_line :: proc(d: ^Doc, a, b: Vec2) -> ^Node {
	n := new_shape(d, .Path)
	path_move(&n.segs, a)
	path_line(&n.segs, b)
	n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 2
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

@(private = "file")
count_kind :: proc(segs: []Seg, k: Seg_Kind) -> int {
	c := 0
	for g in segs do if g.kind == k do c += 1
	return c
}

// Where the line is at this x: the first crossing of a flattened path in document space.
@(private = "file")
line_y_at :: proc(d: ^Doc, n: ^Node, x: f32) -> f32 {
	flat: Polys
	defer polys_free(&flat)
	path_flatten(n.segs[:], node_world(d.root, n), 0.1, &flat)
	for sb in flat.subs {
		for i in sb.a ..< sb.b - 1 {
			a, b := flat.pts[i], flat.pts[i + 1]
			if (a.x <= x) != (b.x <= x) do return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
		}
	}
	return -1e6
}

@(private = "file")
pixel :: proc(d: ^Doc, x, y: int) -> Color {
	pix, w, _ := render_to_pixels(d, 1, WHITE, true)
	return pix[y * w + x]
}

@(private = "file")
fuzz_next :: proc(s: ^u32) -> f32 {
	s^ = s^ * 1664525 + 1013904223
	return f32(s^ >> 8) / f32(1 << 24)
}

@(private = "file")
finite :: proc(v: Vec2) -> bool {
	return !math.is_nan(v.x) && !math.is_nan(v.y) && !math.is_inf(v.x) && !math.is_inf(v.y)
}

sculpt_selftest :: proc(t: ^Test_Run) {
	ui.shift, ui.alt, ui.ctrl, ui.dbl_click = false, false, false, false
	saved_size, saved_strength, saved_pressure, saved_pen, saved_close := sculpt_size, sculpt_strength, sculpt_pressure, pen, close_open_paths
	defer {
		sculpt_size, sculpt_strength, sculpt_pressure, pen, close_open_paths = saved_size, saved_strength, saved_pressure, saved_pen, saved_close
		ui.pressed[0], ui.down[0] = false, false
		tool_groups_default()
		doc = nil
	}
	pen = {}
	sculpt_size, sculpt_strength, sculpt_pressure = 60, 100, true
	close_open_paths = false

	// pulling a straight line into a bend
	{
		d := sim_doc()
		n := add_line(d, {50, 100}, {350, 100})
		uid := n.uid
		before := len(d.undo)
		cur_tool = .Sculpt
		sim_drag(d, {200, 100}, {200, 130}, 12)
		m := node_find(d.root, uid)
		check(t, m != nil && m.kind == .Path, "a sculpted line stays the same object")
		check(t, len(d.undo) == before + 1, "a stroke is one undo step")
		check(t, abs(line_y_at(d, m, 200) - 130) < 2, fmt.tprintf("the line follows the brush's middle (at %.1f)", line_y_at(d, m, 200)))
		check(t, abs(line_y_at(d, m, 100) - 100) < 0.01 && abs(line_y_at(d, m, 300) - 100) < 0.01, "away from the brush it hasn't moved")
		check(t, m.segs[0].p == Vec2{50, 100} && m.segs[len(m.segs) - 1].p == Vec2{350, 100}, "its ends stay exactly where they were")
		check(t, count_kind(m.segs[:], .Move) == 1 && count_kind(m.segs[:], .Close) == 0, "it is still one open line")
		check(t, len(m.segs) <= 14, fmt.tprintf("the bend has few points (%d segments)", len(m.segs)))
		// smooth: no kink along the bend
		flat: Polys
		defer polys_free(&flat)
		path_flatten(m.segs[:], MAT_ID, 0.05, &flat)
		worst: f32 = 1
		for i in 1 ..< len(flat.pts) - 1 {
			a, b := flat.pts[i] - flat.pts[i - 1], flat.pts[i + 1] - flat.pts[i]
			if v_len(a) > 0.01 && v_len(b) > 0.01 do worst = min(worst, v_dot(v_norm(a), v_norm(b)))
		}
		check(t, worst > 0.95, fmt.tprintf("and no kink (worst %.4f)", worst))

		history_undo(d)
		u := node_find(d.root, uid)
		check(t, len(u.segs) == 2 && u.segs[1].kind == .Line && u.segs[1].p == Vec2{350, 100}, "undo brings the line back exactly")
		history_redo(d)
		check(t, abs(line_y_at(d, node_find(d.root, uid), 200) - 130) < 2, "redo bends it again")

		// missing it does nothing
		before = len(d.undo)
		sim_drag(d, {30, 280}, {100, 280}, 6)
		check(t, len(d.undo) == before, "a stroke that reaches nothing makes no undo step")
	}

	// shapes: an edge moves, the fill follows, corners stay
	{
		d := sim_doc()
		n := add_box(d, 100, 100, 200, 100)
		name_set(&n.name, "Rectangle")
		n.stroke, n.sw = paint_solid({0, 0, 255, 255}), 3
		cur_tool = .Sculpt
		sim_drag(d, {200, 100}, {200, 60}, 12)
		check(t, n.kind == .Path && name_str(&n.name) == "Path", "a sculpted rectangle becomes a path, and says so")
		check(t, count_kind(n.segs[:], .Close) == 1 && count_kind(n.segs[:], .Move) == 1, "it stays closed, in one piece")
		check(t, pixel(d, 200, 75) == RED, "the fill follows the moved edge")
		check(t, n.stroke.color == Color{0, 0, 255, 255} && n.sw == 3, "the style stays")
		corners := [?]Vec2{{100, 100}, {300, 100}, {300, 200}, {100, 200}}
		found := 0
		for c in corners {
			for g in n.segs do if g.kind != .Close && g.p == c {found += 1; break}
		}
		check(t, found == 4, fmt.tprintf("the corners stay where they are (%d of 4)", found))

		// a corner under the brush is moved, and stays a corner
		dc := sim_doc()
		b := add_box(dc, 100, 100, 200, 100)
		sim_drag(dc, {100, 100}, {80, 80}, 8)
		flat: Polys
		defer polys_free(&flat)
		path_flatten(b.segs[:], MAT_ID, 0.05, &flat)
		// the closing point repeats the first
		ring := make([dynamic]Vec2, context.temp_allocator)
		for q in flat.pts[flat.subs[0].a:flat.subs[0].b] {
			if len(ring) == 0 || v_len(q - ring[len(ring) - 1]) > 0.01 do append(&ring, q)
		}
		for len(ring) > 1 && v_len(ring[0] - ring[len(ring) - 1]) <= 0.01 do pop(&ring)
		sharp := false
		for q, i in ring {
			p0, p2 := ring[(i + len(ring) - 1) % len(ring)], ring[(i + 1) % len(ring)]
			if q.x < 95 && q.y < 95 && v_dot(v_norm(q - p0), v_norm(p2 - q)) < 0.5 do sharp = true
		}
		check(t, sharp, "a corner under the brush stays a corner")
		check(t, b.segs[0].p != Vec2{100, 100} && len(b.segs) < 30, "and moves with the brush")

		// the same for the straight edge that closes a path
		dl := sim_doc()
		p := new_shape(dl, .Path)
		path_move(&p.segs, {100, 200})
		path_line(&p.segs, {200, 100})
		path_line(&p.segs, {300, 200})
		path_close(&p.segs)
		p.fill, p.stroke = paint_solid(RED), paint_none()
		append(&dl.root.children, p)
		sim_drag(dl, {200, 200}, {200, 240}, 10)
		check(t, pixel(dl, 200, 220) == RED, "the edge that closes a path bends too")
		check(t, count_kind(p.segs[:], .Close) == 1 && p.segs[0].p == Vec2{100, 200}, "and the path is still closed")

		// holes and open fills stay as they are in structure
		de := sim_doc()
		e := new_shape(de, .Ellipse)
		e.x, e.y, e.w, e.h = 200, 150, 80, 80
		e.fill, e.stroke = paint_solid(RED), paint_none()
		append(&de.root.children, e)
		sim_drag(de, {280, 150}, {320, 150}, 10)
		check(t, e.kind == .Path && pixel(de, 300, 150) == RED && pixel(de, 200, 150) == RED, "an ellipse can be pulled out")
	}

	// what can and can't be sculpted
	{
		d := sim_doc()
		a := add_line(d, {50, 100}, {350, 100})
		b := add_line(d, {50, 110}, {350, 110})
		sel_set(d, b)
		cur_tool = .Sculpt
		sim_drag(d, {200, 105}, {200, 150}, 10)
		check(t, len(a.segs) == 2 && len(b.segs) > 2, "with a selection, only it moves")
		clear(&d.sel)
		sim_drag(d, {200, 100}, {200, 60}, 10)
		check(t, len(a.segs) > 2, "without one, the brush moves what it passes over")
		status_t = 0
		other := add_line(d, {50, 280}, {350, 280})
		sel_set(d, a)
		sim_drag(d, {200, 280}, {200, 260}, 6)
		check(t, len(other.segs) == 2 && status_t > 0, "a stroke that misses the selection says why")

		dl := sim_doc()
		l := add_line(dl, {50, 50}, {350, 50})
		l.locked = true
		h := add_line(dl, {50, 100}, {350, 100})
		h.visible = false
		g := node_new(dl, .Group)
		name_set(&g.name, "Group")
		g.locked = true
		in_g := new_shape(dl, .Path)
		path_move(&in_g.segs, {50, 150})
		path_line(&in_g.segs, {350, 150})
		append(&g.children, in_g)
		append(&dl.root.children, g)
		sim_drag(dl, {200, 50}, {200, 60}, 4)
		sim_drag(dl, {200, 100}, {200, 110}, 4)
		sim_drag(dl, {200, 150}, {200, 160}, 4)
		check(t, len(l.segs) == 2 && len(h.segs) == 2 && len(in_g.segs) == 2, "locked and hidden objects are safe")

		dt := sim_doc()
		tx := new_shape(dt, .Text)
		tx.x, tx.y, tx.size = 100, 100, 40
		append(&tx.text, ..transmute([]u8)string("Hi"))
		append(&dt.root.children, tx)
		doc_changed(dt)
		status_t = 0
		c := bounds_center(node_doc_bounds(dt, tx))
		sim_drag(dt, c, c + Vec2{10, 10}, 4)
		check(t, tx.kind == .Text && status_t > 0, "text stays text, and the status bar says what to do")
	}

	// transforms, strength, pressure, a fast pointer
	{
		d := sim_doc()
		g := node_new(d, .Group)
		name_set(&g.name, "Group")
		g.xf = mat_mul(mat_translate(200, 150), mat_rotate(deg2rad(90)))
		c := new_shape(d, .Path)
		path_move(&c.segs, {-50, 0})
		path_line(&c.segs, {50, 0})
		c.xf = mat_scale(2, 2)
		c.fill, c.stroke, c.sw = paint_none(), paint_solid(RED), 1
		append(&g.children, c)
		append(&d.root.children, g)
		gxf, cxf := g.xf, c.xf
		cur_tool = .Sculpt
		// on screen this line is vertical, through (200, 150)
		sim_drag(d, {200, 150}, {230, 150}, 10)
		check(t, g.xf == gxf && c.xf == cxf, "sculpting keeps the transforms")
		flat: Polys
		defer polys_free(&flat)
		path_flatten(c.segs[:], node_world(d.root, c), 0.1, &flat)
		furthest: f32 = 0
		for q in flat.pts do furthest = max(furthest, q.x)
		check(t, abs(furthest - 230) < 2, fmt.tprintf("the line moves on screen with the pointer (%.1f)", furthest))

		// half strength
		ds := sim_doc()
		sculpt_strength = 50
		hs := add_line(ds, {50, 100}, {350, 100})
		sim_drag(ds, {200, 100}, {200, 140}, 12)
		// it falls behind the brush, so it feels less of it as the brush moves on: less than half, but not much less
		half := line_y_at(ds, hs, 200)
		check(t, half > 106 && half < 120, fmt.tprintf("at 50%% it moves less (%.1f)", half))
		sculpt_strength = 100

		// pressure
		dp := sim_doc()
		lp := add_line(dp, {50, 100}, {350, 100})
		pen.touching, pen.pressure = true, 0.25
		sim(dp, 200, 100, true, true)
		for i in 1 ..= 12 do sim(dp, 200, 100 + f32(i) * 3, false, true)
		pen.touching = false
		sim(dp, 200, 136, false, false)
		light := line_y_at(dp, lp, 200)
		check(t, light > 100.5 && light < 120, fmt.tprintf("a light touch moves it less (%.1f)", light))
		dq := sim_doc()
		lq := add_line(dq, {50, 100}, {350, 100})
		sculpt_pressure = false
		pen.touching, pen.pressure = true, 0.25
		sim(dq, 200, 100, true, true)
		for i in 1 ..= 12 do sim(dq, 200, 100 + f32(i) * 3, false, true)
		pen.touching = false
		sim(dq, 200, 136, false, false)
		check(t, abs(line_y_at(dq, lq, 200) - 136) < 2, "with Pressure off the strength stays")
		sculpt_pressure = true
		pen = {}

		// a pointer that jumps over a line still catches it
		df := sim_doc()
		lf := add_line(df, {50, 100}, {350, 100})
		sim(df, 200, 50, true, true)
		sim(df, 200, 160, false, true)
		sim(df, 200, 160, false, false)
		check(t, line_y_at(df, lf, 200) > 140, fmt.tprintf("a fast pointer catches the line (%.1f)", line_y_at(df, lf, 200)))

		// zoomed in, the brush is its size on screen
		dz := sim_doc()
		lz := add_line(dz, {100, 100}, {300, 100})
		dz.zoom, dz.ox, dz.oy = 4, -600, -300
		a, b := to_screen(dz, {200, 100}), to_screen(dz, {200, 110})
		sim_drag(dz, a, b, 8)
		check(t, abs(line_y_at(dz, lz, 200) - 110) < 1 && abs(line_y_at(dz, lz, 180) - 100) < 0.01, "zoomed in, the brush's reach is smaller in the document")

		// an interrupted stroke is finished, as one step
		di := sim_doc()
		li := add_line(di, {50, 100}, {350, 100})
		before := len(di.undo)
		sim(di, 200, 100, true, true)
		sim(di, 200, 120, false, true)
		check(t, tl.kind == .Sculpt && len(li.segs) > 2, "the shape moves during the stroke")
		mid := len(li.segs)
		set_tool(.Select)
		check(t, tl.kind == .None && len(li.segs) < mid && len(di.undo) == before + 1, "switching tools ends the stroke")
		check(t, abs(line_y_at(di, li, 200) - 120) < 2, "and keeps what was done")

		// only the current frame, and files
		dfr := sim_doc()
		lfr := add_line(dfr, {50, 100}, {350, 100})
		_ = lfr
		run_cmd(.Frame_Dup)
		cur_tool = .Sculpt
		sim_drag(dfr, {200, 100}, {200, 130}, 8)
		check(t, len(dfr.frames[0].root.children[0].segs) == 2 && len(dfr.root.children[0].segs) > 2, "only the current frame is sculpted")
		back, ok := svg_parse(svg_string(dfr))
		check(t, ok && len(back.frames) == 2, "a sculpted drawing opens")
		if ok && len(back.frames) == 2 {
			check(t, count_kind(back.frames[1].root.children[0].segs[:], .Close) == 0, "and a sculpted line stays open")
			doc_free(back)
		}
	}

	// scrubbing kneads an outline, which makes it much longer: it stays in bounds, and comes out usable
	{
		d := sim_doc()
		n := add_box(d, 180, 130, 16, 16)
		sculpt_size = 60
		cur_tool = .Sculpt
		sim(d, 188, 138, true, true)
		for i in 1 ..= 1500 {
			a := f32(i) * 0.3
			sim(d, 200 + math.cos(a) * 60, 150 + math.sin(a * 1.3) * 45, false, true)
			if i % 100 == 0 do free_all(context.temp_allocator)
		}
		live := len(n.segs)
		// a split can run past the limit by what one step adds, which is small
		check(t, live <= SCULPT_MAX_ADDED + 200, fmt.tprintf("a long scrub stays under the limit (%d segments)", live))
		sim(d, 200, 150, false, false)
		check(t, tl.kind == .None && len(n.segs) > 0 && len(n.segs) <= live, fmt.tprintf("and ends cleanly (%d segments)", len(n.segs)))
		bad := 0
		for g in n.segs do if !finite(g.p) || !finite(g.c1) || !finite(g.c2) do bad += 1
		check(t, bad == 0 && count_kind(n.segs[:], .Close) == 1, "with valid numbers, still closed")
		uid := n.uid // undo frees n: look the object up again by its id
		history_undo(d)
		back := node_find(d.root, uid)
		check(t, back == nil || back.kind == .Rect, "and undo brings the rectangle back")
	}

	// a smooth point stays smooth, zoomed out too, where the samples for fitting are far apart
	{
		for zoom in ([]f32{1, 0.33}) {
			d := sim_doc()
			n := new_shape(d, .Path)
			path_move(&n.segs, {50, 150})
			path_cubic(&n.segs, {100, 60}, {150, 110}, {200, 150})
			path_cubic(&n.segs, {250, 190}, {300, 240}, {350, 150})
			n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 2
			append(&d.root.children, n)
			d.zoom, d.ox, d.oy = zoom, 200 * (1 - zoom), 150 * (1 - zoom)
			cur_tool = .Sculpt
			// the brush takes the smooth point along off its middle, where the falloff is steepest
			a := to_screen(d, {200 - 18 / zoom, 150 + 14 / zoom})
			sim_drag(d, a, a + Vec2{-10, 40}, 12)
			worst: f32 = 1
			for i in 1 ..< len(n.segs) - 1 {
				g, h := n.segs[i], n.segs[i + 1]
				if g.kind != .Cubic || h.kind != .Cubic do continue
				if v_len(g.p - g.c2) < 1e-3 || v_len(h.c1 - g.p) < 1e-3 do continue
				worst = min(worst, v_dot(v_norm(g.p - g.c2), v_norm(h.c1 - g.p)))
			}
			check(t, worst > 0.998, fmt.tprintf("a smooth point stays smooth at zoom %.2f (worst %.4f)", zoom, worst))
		}
	}

	// the wave that showed a kink in the running app, with the same stroke
	{
		d := doc_new(.Svg, "sim", 800, 500)
		doc = d
		ui.scale = 1
		tools_cancel()
		n := new_shape(d, .Path)
		path_move(&n.segs, {70, 330})
		path_cubic(&n.segs, {170, 250}, {270, 420}, {390, 330})
		path_cubic(&n.segs, {510, 240}, {620, 250}, {730, 340})
		n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 8
		append(&d.root.children, n)
		d.zoom, d.ox, d.oy, d.view_init = 0.3275, 0, 0, true
		sculpt_size = 60
		cur_tool = .Sculpt
		sim_drag(d, to_screen(d, {320, 357}), to_screen(d, {320, 447}), 8)
		worst: f32 = 1
		for i in 1 ..< len(n.segs) - 1 {
			g, h := n.segs[i], n.segs[i + 1]
			if g.kind != .Cubic || h.kind != .Cubic do continue
			if v_len(g.p - g.c2) < 1e-3 || v_len(h.c1 - g.p) < 1e-3 do continue
			c := v_dot(v_norm(g.p - g.c2), v_norm(h.c1 - g.p))
			if c < worst do worst = c
		}
		check(t, worst > 0.998, fmt.tprintf("the wave stays smooth (worst %.4f)", worst))
		sim_doc()
	}

	// the limit is for the whole stroke, however many objects it reaches
	{
		d := sim_doc()
		for y in 0 ..< 15 do for x in 0 ..< 20 do add_box(d, 10 + f32(x) * 19, 10 + f32(y) * 19, 16, 16)
		before := 0
		for c in d.root.children do before += len(node_segs(c))
		sculpt_size = 60
		cur_tool = .Sculpt
		sim(d, 200, 150, true, true)
		for i in 1 ..= 1500 {
			a := f32(i) * 0.05
			sim(d, 200 + math.cos(a) * (40 + f32(i) * 0.07), 150 + math.sin(a * 1.3) * (30 + f32(i) * 0.05), false, true)
			if i % 100 == 0 do free_all(context.temp_allocator)
		}
		live := 0
		for c in d.root.children do live += len(node_segs(c))
		check(t, live <= before + SCULPT_MAX_ADDED + 400, fmt.tprintf("a stroke over many objects stays under the limit too (%d segments)", live))
		sim(d, 200, 150, false, false)
		check(t, tl.kind == .None, "and ends cleanly")
	}

	// random strokes: nothing breaks, far points stay put, and the fitted result is what was shown
	{
		broken, moved_far, strayed, structure := 0, 0, 0, 0
		worst_stray: f32 = 0
		total, most := 0, 0
		for seed in 1 ..= 40 {
			s := u32(seed) * 2654435761
			d := sim_doc()
			n: ^Node
			switch seed % 4 {
			case 0:
				n = add_box(d, 80, 60, 240, 180)
			case 1:
				n = new_shape(d, .Ellipse)
				n.x, n.y, n.w, n.h = 200, 150, 120, 90
				n.fill, n.stroke = paint_solid(RED), paint_none()
				n.xf = mat_mul(mat_translate(200, 150), mat_mul(mat_rotate(deg2rad(25)), mat_translate(-200, -150)))
				append(&d.root.children, n)
			case 2:
				n = new_shape(d, .Path)
				path_move(&n.segs, {30, 150})
				path_cubic(&n.segs, {80, 10}, {160, 10}, {200, 150})
				path_quad(&n.segs, {280, 290}, {370, 150})
				path_line(&n.segs, {370, 40})
				n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 2
				append(&d.root.children, n)
			case 3:
				n = new_shape(d, .Path)
				path_rect(&n.segs, 80, 60, 240, 180, 0, 0)
				path_rect(&n.segs, 160, 120, 80, 60, 0, 0)
				n.fill, n.stroke, n.even_odd = paint_solid(RED), paint_none(), true
				append(&d.root.children, n)
			}
			doc_changed(d)
			uid := n.uid
			moves0, closes0 := count_kind(node_segs(n), .Move), count_kind(node_segs(n), .Close)
			w := node_world(d.root, n)
			orig := make([dynamic]Vec2, context.temp_allocator)
			for g in node_segs(n) do if g.kind != .Close do append(&orig, mat_apply(w, g.p))

			cur_tool = .Sculpt
			sculpt_size = 20 + int(fuzz_next(&s) * 90)
			r := f32(sculpt_size) / 2
			pts := make([dynamic]Vec2, context.temp_allocator)
			p := Vec2{60 + fuzz_next(&s) * 280, 60 + fuzz_next(&s) * 180}
			append(&pts, p)
			sim(d, p.x, p.y, true, true)
			for _ in 0 ..< 10 + int(fuzz_next(&s) * 60) {
				ang := fuzz_next(&s) * math.TAU
				q := p + Vec2{math.cos(ang), math.sin(ang)} * (2 + fuzz_next(&s) * 25)
				q = {clamp(q.x, 10, 390), clamp(q.y, 10, 290)}
				append(&pts, q)
				sim(d, q.x, q.y, false, true)
				p = q
			}
			// what the stroke shows just before it ends
			m := node_find(d.root, uid)
			live: Polys
			defer polys_free(&live)
			if m != nil do path_flatten(node_segs(m), w, 0.05, &live)
			sim(d, p.x, p.y, false, false)
			m = node_find(d.root, uid)
			if m == nil {
				broken += 1
				continue
			}
			for g in m.segs {
				if !finite(g.p) || !finite(g.c1) || !finite(g.c2) do broken += 1
			}
			if count_kind(node_segs(m), .Move) != moves0 || count_kind(node_segs(m), .Close) != closes0 do structure += 1
			// anchors the brush never came near are still there
			now := make([dynamic]Vec2, context.temp_allocator)
			for g in node_segs(m) do if g.kind != .Close do append(&now, mat_apply(w, g.p))
			for a in orig {
				dist := v_len(a - pts[0])
				for i in 0 ..< len(pts) - 1 do dist = min(dist, dist_to_segment(a, pts[i], pts[i + 1]))
				if dist <= r + 1 do continue
				there := false
				for b in now do if v_len(a - b) < 0.01 do there = true
				if !there do moved_far += 1
			}
			// the fitted curves are within a pixel of what was shown
			if len(live.subs) > 0 {
				fin: Polys
				defer polys_free(&fin)
				path_flatten(node_segs(m), w, 0.05, &fin)
				for q in fin.pts {
					e := polys_distance(&live, q)
					worst_stray = max(worst_stray, e)
					if e > 1 do strayed += 1
				}
			}
			c := len(m.segs)
			total += c
			most = max(most, c)
		}
		check(t, broken == 0, fmt.tprintf("random strokes leave valid numbers (%d bad)", broken))
		check(t, structure == 0, fmt.tprintf("and the same number of subpaths, closed or open (%d changed)", structure))
		check(t, moved_far == 0, fmt.tprintf("points the brush never reached don't move (%d moved)", moved_far))
		check(t, strayed == 0, fmt.tprintf("the fitted result is what was shown (%d points away, worst %.2f)", strayed, worst_stray))
		check(t, most < 300, fmt.tprintf("and it has a reasonable number of segments (avg %d, most %d)", total / 40, most))
		sculpt_size = 60
	}

	// Extend: from a line's last point
	{
		d := sim_doc()
		n := add_line(d, {50, 100}, {150, 100})
		uid := n.uid
		before := len(d.undo)
		cur_tool = .Extend
		sim_drag(d, {150, 100}, {300, 100}, 20)
		m := node_find(d.root, uid)
		check(t, len(d.root.children) == 1 && m != nil, "extending keeps one object")
		check(t, count_kind(m.segs[:], .Move) == 1 && count_kind(m.segs[:], .Close) == 0, "and one open line")
		check(t, m.segs[0].p == Vec2{50, 100} && m.segs[1].p == Vec2{150, 100} && m.segs[1].kind == .Line, "what was there is untouched")
		check(t, v_len(m.segs[len(m.segs) - 1].p - Vec2{300, 100}) < 1, "and it now reaches the pointer")
		check(t, m.fill.kind == .None && m.stroke.color == RED && m.sw == 2, "the style stays")
		check(t, len(d.undo) == before + 1 && len(d.sel) == 1 && d.sel[0] == uid, "one undo step, and it is selected")
		history_undo(d)
		u := node_find(d.root, uid)
		check(t, len(u.segs) == 2 && u.segs[1].p == Vec2{150, 100}, "undo takes the new part off")

		// from its first point
		ds := sim_doc()
		a := add_line(ds, {100, 100}, {200, 100})
		sim_drag(ds, {100, 100}, {20, 100}, 12)
		check(t, count_kind(a.segs[:], .Move) == 1 && count_kind(a.segs[:], .Close) == 0, "extending from the first point keeps one line")
		first, last := a.segs[0].p, a.segs[len(a.segs) - 1].p
		check(t, (first == Vec2{200, 100} && v_len(last - Vec2{20, 100}) < 1), "and reaches from the far end to the pointer")
		has_old := false
		for g in a.segs do if (g.p == Vec2{100, 100}) do has_old = true
		check(t, has_old, "through where it started")

		// near enough is near enough, away is not
		dn := sim_doc()
		b := add_line(dn, {100, 100}, {200, 100})
		before = len(dn.undo)
		status_t = 0
		sim_drag(dn, {260, 100}, {300, 100}, 6)
		check(t, len(b.segs) == 2 && len(dn.undo) == before && status_t > 0, "a press away from an end does nothing, and says why")
		sim_drag(dn, {208, 104}, {300, 104}, 10)
		check(t, len(b.segs) > 2 && b.segs[1].p == Vec2{200, 100}, "a press near an end snaps to it")
		sim_click(dn, {100, 100})
		check(t, count_kind(b.segs[:], .Move) == 1 && len(dn.root.children) == 1, "a click on an end adds nothing")
	}

	// joining smoothly, or turning
	{
		d := sim_doc()
		n := new_shape(d, .Path)
		path_move(&n.segs, {50, 150})
		path_cubic(&n.segs, {100, 150}, {150, 150}, {200, 150})
		n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 2
		append(&d.root.children, n)
		cur_tool = .Extend
		sim(d, 200, 150, true, true)
		for i in 1 ..= 30 {
			x := 200 + f32(i) * 5
			sim(d, x, 150 + f32(i) * f32(i) * 0.08, false, true)
		}
		sim(d, 350, 222, false, false)
		join := n.segs[2]
		check(t, join.kind == .Cubic, "the new part is curves")
		dir := v_norm(join.c1 - Vec2{200, 150})
		check(t, v_dot(dir, Vec2{1, 0}) > 0.999, "carrying on in about the same direction joins without a kink")

		dt := sim_doc()
		tn := add_line(dt, {50, 150}, {200, 150})
		sim_drag(dt, {200, 150}, {200, 280}, 20)
		td := v_norm(tn.segs[2].c1 - Vec2{200, 150})
		check(t, abs(v_dot(td, Vec2{1, 0})) < 0.3, "a sharp turn stays a turn")
	}

	// which ends, and closing
	{
		d := sim_doc()
		n := new_shape(d, .Path)
		path_move(&n.segs, {50, 50})
		path_line(&n.segs, {150, 50})
		path_move(&n.segs, {50, 150})
		path_line(&n.segs, {150, 150})
		n.fill, n.stroke, n.sw = paint_none(), paint_solid(RED), 2
		append(&d.root.children, n)
		cur_tool = .Extend
		sim_drag(d, {150, 150}, {300, 150}, 10)
		check(t, count_kind(n.segs[:], .Move) == 2 && n.segs[0].p == Vec2{50, 50} && n.segs[1].p == Vec2{150, 50} && n.segs[2].p == Vec2{50, 150} && n.segs[3].p == Vec2{150, 150}, "the right subpath is extended, the other is untouched")
		sim_drag(d, {50, 50}, {10, 50}, 6)
		check(t, n.segs[0].p == Vec2{150, 50} && v_len(n.segs[len(n.segs) - 1].p - Vec2{0, 0}) > 0, "the first subpath can be extended from its start")
		check(t, count_kind(n.segs[:], .Move) == 2, "and they stay two")

		// a selection limits it, and locks and closed shapes have no ends for it
		ds := sim_doc()
		a := add_line(ds, {50, 50}, {150, 50})
		b := add_line(ds, {50, 150}, {150, 150})
		sel_set(ds, a)
		sim_drag(ds, {150, 150}, {250, 150}, 6)
		check(t, len(b.segs) == 2, "with a selection, only its lines can be extended")
		clear(&ds.sel)
		b.locked = true
		sim_drag(ds, {150, 150}, {250, 150}, 6)
		check(t, len(b.segs) == 2, "a locked line can't")
		dc := sim_doc()
		box := add_box(dc, 100, 100, 100, 100)
		sim_drag(dc, {200, 200}, {300, 300}, 6)
		check(t, box.kind == .Rect, "a closed shape has no ends")

		// closing
		dz := sim_doc()
		z := add_line(dz, {100, 100}, {200, 100})
		path_of :: proc(d: ^Doc) {
			sim(d, 200, 100, true, true)
			for i in 1 ..= 16 {
				a := f32(i) / 16 * math.PI
				sim(d, 150 + math.cos(a) * 50, 100 + math.sin(a) * 50, false, true)
			}
			sim(d, 100, 100, false, false)
		}
		path_of(dz)
		check(t, count_kind(z.segs[:], .Close) == 0, "with Close Open Paths off, ending on the other end leaves it open")
		dy := sim_doc()
		y := add_line(dy, {100, 100}, {200, 100})
		close_open_paths = true
		path_of(dy)
		check(t, count_kind(y.segs[:], .Close) == 1, "with it on, it closes")
		check(t, y.fill.kind == .None, "and doesn't get a fill it didn't have")
		close_open_paths = false

		// under a transform
		dx := sim_doc()
		g := node_new(dx, .Group)
		name_set(&g.name, "Group")
		g.xf = mat_mul(mat_translate(100, 100), mat_scale(2, 2))
		l := new_shape(dx, .Path)
		path_move(&l.segs, {0, 0})
		path_line(&l.segs, {50, 0})
		l.fill, l.stroke, l.sw = paint_none(), paint_solid(RED), 1
		append(&g.children, l)
		append(&dx.root.children, g)
		sim_drag(dx, {200, 100}, {300, 100}, 8)
		end := mat_apply(node_world(dx.root, l), l.segs[len(l.segs) - 1].p)
		check(t, v_len(end - Vec2{300, 100}) < 1 && g.xf == mat_mul(mat_translate(100, 100), mat_scale(2, 2)), "the new part lands under the pointer inside a transformed group")

		// a line the eraser cut can be extended
		de := sim_doc()
		cut := add_line(de, {50, 200}, {350, 200})
		cur_tool = .Eraser
		sim_drag(de, {200, 180}, {200, 220}, 6)
		cur_tool = .Extend
		start_x := cut.segs[1].p.x
		sim_drag(de, {start_x, 200}, {start_x, 280}, 8)
		check(t, count_kind(cut.segs[:], .Move) == 2 && len(cut.segs) > 4, "a line the eraser cut can be extended")

		// and a freehand stroke, then sculpted
		dh := sim_doc()
		cur_tool = .Freehand
		sim(dh, 50, 100, true, true)
		for i in 1 ..= 20 do sim(dh, 50 + f32(i) * 5, 100 + math.sin(f32(i) * 0.3) * 10, false, true)
		sim(dh, 150, 100, false, false)
		fh := dh.root.children[0]
		e := fh.segs[len(fh.segs) - 1].p
		clear(&dh.sel)
		cur_tool = .Extend
		sim_drag(dh, e, {300, 120}, 12)
		check(t, v_len(fh.segs[len(fh.segs) - 1].p - Vec2{300, 120}) < 1, "a freehand stroke can be extended")
		cur_tool = .Sculpt
		sim_drag(dh, {220, 110}, {220, 180}, 12)
		check(t, line_y_at(dh, fh, 220) > 150, "and then sculpted")
	}

	// keys, groups, settings
	{
		d := sim_doc()
		tool_groups_default()
		set_tool(.Select)
		key(.U)
		check(t, cur_tool == .Sculpt, "U is sculpt")
		key(.X)
		check(t, cur_tool == .Extend, "X is extend")
		key(.X, ctrl = true)
		check(t, cur_tool == .Extend, "Ctrl+X is still cut")
		set_tool(.Sculpt)
		sculpt_size = 60
		key(.RIGHT_BRACKET)
		check(t, sculpt_size == 72, "] makes the brush bigger")
		key(.LEFT_BRACKET)
		check(t, sculpt_size < 72, "[ makes it smaller")
		sculpt_size = 60
		check(t, TOOL_NAMES[.Sculpt] == "Sculpt (U)" && TOOL_NAMES[.Extend] == "Extend (X)", "their names show their keys")
		check(t, tool_group_has(&tool_groups[0], .Sculpt) && tool_group_has(&tool_groups[1], .Extend), "they are in the default groups")
		check(t, !tool_is_toggle(.Sculpt) && !tool_is_toggle(.Extend), "they are tools, not switches")
		s := tool_groups_serialize()
		tool_groups_parse(s)
		check(t, tool_group_has(&tool_groups[0], .Sculpt) && tool_group_has(&tool_groups[1], .Extend), "and are saved with the groups")
		prefs_parse("sculpt_size=9999\nsculpt_strength=40\nsculpt_pressure=0\n")
		check(t, sculpt_size == SCULPT_SIZE_MAX && sculpt_strength == 40 && !sculpt_pressure, "their settings are read from the preferences, in range")
		sculpt_size, sculpt_strength, sculpt_pressure = 60, 100, true

		// the pen's eraser end erases from these too
		pen.in_range, pen.eraser = true, true
		tool_groups_default()
		set_tool(.Sculpt)
		check(t, eff_tool() == .Eraser, "the pen's eraser end erases while sculpting")
		set_tool(.Extend)
		check(t, eff_tool() == .Eraser, "and while extending")
		pen = {}
		set_tool(.Select)
		_ = d
	}
}
