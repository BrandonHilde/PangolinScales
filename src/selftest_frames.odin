package pangolin

import "core:fmt"
import "core:os"
import "core:strings"

// Tests of frames, their files and exports, tool group colors and switches, keys, workspaces and the file browser.

@(private = "file")
tmp_path :: proc(name: string) -> string {
	return fmt.tprintf("%sselftest_tmp_%s", gfx_app_dir(), name)
}

@(private = "file")
add_rect :: proc(d: ^Doc, x: f32, c := Color{0, 0, 0, 255}) -> ^Node {
	n := new_shape(d, .Rect)
	n.x, n.y, n.w, n.h = x, 10, 40, 40
	n.fill, n.stroke = paint_solid(c), paint_none()
	append(&d.root.children, n)
	doc_changed(d)
	return n
}

frames_selftest :: proc(t: ^Test_Run) {
	// one frame saves exactly as before frames existed
	{
		d := doc_new(.Svg, "one", 100, 50)
		n := new_shape(d, .Rect)
		n.x, n.y, n.w, n.h = 1, 2, 3, 4
		n.fill, n.stroke = paint_solid({255, 0, 0, 255}), paint_none()
		append(&d.root.children, n)
		want := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\" viewBox=\"0 0 100 50\">\n  <rect x=\"1\" y=\"2\" width=\"3\" height=\"4\" fill=\"#ff0000\"/>\n</svg>\n"
		check(t, svg_string(d) == want, "single-frame output is unchanged")
		back, ok := svg_parse(want)
		check(t, ok && len(back.frames) == 1 && back.frames[0].root == back.root && back.frames[0].duration == FRAME_DURATION, "a plain SVG is one frame")
		doc_free(back)
		doc_free(d)
	}

	// adding frames, and moving between them without touching the document
	d := sim_doc()
	cur_tool = .Select
	first := add_rect(d, 10)
	check(t, len(d.frames) == 1 && d.frames[0].root == d.root, "a new document has one frame")
	run_cmd(.Frame_Dup)
	check(t, len(d.frames) == 2 && d.active_frame == 1, "duplicate adds a frame and goes to it")
	check(t, d.root == d.frames[1].root && d.root != d.frames[0].root && len(d.root.children) == 1, "the duplicate is a drawing of its own")
	check(t, d.root.children[0].uid != first.uid, "a duplicated frame's objects get new ids")
	run_cmd(.Frame_New)
	check(t, len(d.frames) == 3 && d.active_frame == 2 && len(d.root.children) == 0, "new adds an empty frame after the current one")
	d.modified = false
	sel_set(d, first)
	ver := d.version
	set_frame(0)
	check(t, !d.modified, "changing frame doesn't mark the document modified")
	check(t, d.version != ver, "changing frame redraws")
	check(t, d.root == d.frames[0].root && d.root.children[0] == first, "changing frame shows that frame's drawing")
	check(t, len(d.sel) == 0, "changing frame clears the selection")
	set_frame(99)
	check(t, d.active_frame == 2, "a frame past the end goes to the last")

	// one undo stack for the whole document
	{
		du := sim_doc()
		add_rect(du, 10)
		run_cmd(.Frame_Dup)
		for &s in du.undo do state_free(&s)
		clear(&du.undo)
		history_push(du)
		add_rect(du, 60)
		check(t, len(du.root.children) == 2 && du.active_frame == 1, "an edit on frame 2")
		set_frame(0)
		history_undo(du)
		check(t, du.active_frame == 1, "undoing a change from another frame goes to that frame")
		check(t, len(du.root.children) == 1 && len(du.frames[0].root.children) == 1, "undo changes only that frame")
		check(t, du.frames[1].root == du.root, "the frame list stays in step with the live root")
		set_frame(0)
		history_redo(du)
		check(t, du.active_frame == 1 && len(du.root.children) == 2, "redo goes to the frame too")

		history_push(du)
		add_rect(du, 120)
		set_frame(0)
		history_push(du)
		add_rect(du, 180)
		history_undo(du)
		check(t, du.active_frame == 0 && len(du.root.children) == 1, "undo steps back through frames in order: first")
		history_undo(du)
		check(t, du.active_frame == 1 && len(du.root.children) == 2, "undo steps back through frames in order: second")
		history_redo(du)
		history_redo(du)
		check(t, du.active_frame == 0 && len(du.root.children) == 2 && len(du.frames[1].root.children) == 3, "redo brings both back")

		// a burst of style edits shares an undo step, but not across a frame change
		r0 := du.root.children[0]
		sel_set(du, r0)
		ui.time = 100
		last_style_push = 100
		n0 := len(du.undo)
		style_set_width(du, 3)
		check(t, len(du.undo) == n0, "edits in a burst share an undo step")
		set_frame(1)
		sel_set(du, du.root.children[0])
		style_set_width(du, 4)
		check(t, len(du.undo) == n0 + 1 && du.undo[n0].frame == 1, "the first edit on another frame starts its own undo step")
		ui.time = 0
	}

	// changes to the frame list undo too
	{
		ds := sim_doc()
		a := add_rect(ds, 10)
		ids := a.uid
		for &s in ds.undo do state_free(&s)
		clear(&ds.undo)
		run_cmd(.Frame_New)
		check(t, len(ds.undo) == 1 && ds.undo[0].structure, "a new frame is one undo step")
		history_undo(ds)
		check(t, len(ds.frames) == 1 && ds.active_frame == 0 && ds.root == ds.frames[0].root, "undo takes the new frame away")
		check(t, len(ds.root.children) == 1 && ds.root.children[0].uid == ids, "undo keeps the other frame's drawing")
		history_redo(ds)
		check(t, len(ds.frames) == 2 && ds.active_frame == 1, "redo brings the new frame back")
		add_rect(ds, 30)
		run_cmd(.Frame_Del)
		check(t, len(ds.frames) == 1 && ds.active_frame == 0, "delete removes the current frame")
		run_cmd(.Frame_Del)
		check(t, len(ds.frames) == 1, "the last frame can't be deleted")
		run_cmd(.Undo)
		check(t, len(ds.frames) == 2 && len(ds.frames[1].root.children) == 1, "undo brings a deleted frame back, with its drawing")

		run_cmd(.Frame_First)
		ds.frames[0].duration, ds.frames[1].duration = 111, 222
		root0 := ds.root
		run_cmd(.Frame_Right)
		check(t, ds.active_frame == 1 && ds.frames[1].duration == 111 && ds.frames[0].duration == 222 && ds.root == root0, "move right takes the frame along")
		run_cmd(.Frame_Right)
		check(t, ds.active_frame == 1, "the last frame can't move right")
		run_cmd(.Undo)
		check(t, ds.frames[0].duration == 111 && ds.active_frame == 0, "undo of a move")

		frames_set_duration(ds, 500, false)
		check(t, ds.frames[0].duration == 500 && ds.frames[1].duration == 222, "duration of one frame")
		frames_set_duration(ds, 40, true)
		check(t, ds.frames[0].duration == 40 && ds.frames[1].duration == 40, "duration of all frames")
		history_undo(ds)
		history_undo(ds)
		check(t, ds.frames[0].duration == 111 && ds.frames[1].duration == 222, "durations undo")

		check(t, frame_drop_index(0, 2) == 1 && frame_drop_index(2, 0) == 0 && frame_drop_index(1, 1) == 1 && frame_drop_index(1, 2) == 1, "a dragged frame lands where the gap says")
		check(t, frame_move_to(ds, 1, 0) && ds.frames[0].duration == 222 && ds.active_frame == 1, "dragging another frame leaves the document on its frame")

		// the Tags window: closing it makes one undo step if something changed, none if not
		undo_n := len(ds.undo)
		ds.modified = false
		tags_dialog_opened(ds)
		ds.modified = true // what the window does when it closes
		tags_dialog_closed(ds)
		check(t, len(ds.undo) == undo_n && !ds.modified, "the Tags window changing nothing adds no undo step")
		tags_dialog_opened(ds)
		tg := Tag {
			from = 0,
			to   = 1,
		}
		name_set(&tg.name, "walk")
		append(&ds.tags, tg)
		tags_dialog_closed(ds)
		check(t, len(ds.undo) == undo_n + 1 && ds.modified, "a tag added in the window is one undo step")
		history_undo(ds)
		check(t, len(ds.tags) == 0, "undo takes the tag away")
		history_redo(ds)
		check(t, len(ds.tags) == 1 && name_str(&ds.tags[0].name) == "walk", "redo brings it back")

		for _ in 0 ..< UNDO_MAX + 20 do frames_history_push(ds)
		check(t, len(ds.undo) == UNDO_MAX, "the undo limit covers frame changes")
		history_undo(ds)
		check(t, len(ds.redo) == 1, "undo of a frame change can be redone")
		history_push(ds)
		check(t, len(ds.redo) == 0, "a new change clears redo")
	}

	// tags follow the frames
	{
		dt := sim_doc()
		for _ in 0 ..< 5 do run_cmd(.Frame_New)
		tg := Tag {
			from = 2,
			to   = 3,
		}
		append(&dt.tags, tg)
		frame_set(dt, 0)
		run_cmd(.Frame_New)
		check(t, dt.tags[0].from == 3 && dt.tags[0].to == 4, "inserting before a tag shifts it")
		frame_set(dt, 3)
		run_cmd(.Frame_Del)
		check(t, dt.tags[0].from == 3 && dt.tags[0].to == 3, "deleting inside a tag shrinks it")
		frame_set(dt, 3)
		run_cmd(.Frame_Del)
		check(t, len(dt.tags) == 0, "deleting a tag's last frame removes the tag")
	}

	// playback
	{
		dp := sim_doc()
		for _ in 0 ..< 3 do run_cmd(.Frame_New)
		for &f in dp.frames do f.duration = 100
		frame_set(dp, 0)
		dp.modified = false
		run_cmd(.Play)
		check(t, playing, "play starts")
		playback_update(0.15)
		check(t, dp.active_frame == 1 && playing && !dp.modified, "playback steps through frames without modifying")
		playback_update(0.2)
		check(t, dp.active_frame == 3, "playback goes by the durations")
		playback_update(0.1)
		check(t, dp.active_frame == 0, "playback loops")
		tg := Tag {
			from = 1,
			to   = 2,
		}
		append(&dp.tags, tg)
		play_tag = 0
		playback_update(0.1)
		check(t, dp.active_frame == 1, "playback keeps to the tag's frames")
		playback_update(0.1)
		playback_update(0.1)
		check(t, dp.active_frame == 1, "playback loops within the tag")
		play_tag = -1
		add_rect(dp, 10)
		check(t, !playing, "editing stops playback")
		run_cmd(.Play)
		sim(dp, 5, 5, true, true)
		sim(dp, 5, 5, false, false)
		check(t, !playing, "pressing on the canvas stops playback")
		ds := sim_doc()
		run_cmd(.Play)
		check(t, !playing && len(ds.frames) == 1, "one frame has nothing to play")
	}

	// onion skin
	{
		do_ := sim_doc()
		add_rect(do_, 10)
		run_cmd(.Frame_New)
		run_cmd(.Frame_New)
		add_rect(do_, 200)
		frame_set(do_, 1)
		W, H :: 300, 60
		fb := make([]Color, W * H, context.temp_allocator)
		r: Raster
		raster_init(&r, W, H)
		defer raster_free(&r)
		render_at :: proc(d: ^Doc, fb: []Color, r: ^Raster) {
			for &c in fb do c = {}
			render_page(d, fb, MAT_ID, r)
			render_onion(d, fb, MAT_ID, r)
			render_node(r, fb, d.root, MAT_ID, 1)
		}
		saved := [4]int{onion ? 1 : 0, onion_prev, onion_next, onion_alpha}
		onion = false
		render_at(do_, fb, &r)
		check(t, fb[30 * W + 30].r == 255 && fb[30 * W + 220].r == 255, "without the onion skin only this frame shows")
		onion, onion_prev, onion_next, onion_alpha = true, 1, 0, 50
		render_at(do_, fb, &r)
		mid := fb[30 * W + 30].r
		check(t, mid > 100 && mid < 160, "the previous frame shows at the set opacity")
		check(t, fb[30 * W + 220].r == 255, "the next frame stays hidden when its count is 0")
		onion_prev, onion_next = 0, 1
		render_at(do_, fb, &r)
		check(t, fb[30 * W + 30].r == 255 && fb[30 * W + 220].r < 160, "the next frame shows")
		frame_set(do_, 0)
		onion_prev, onion_next = 1, 0
		render_at(do_, fb, &r)
		check(t, fb[30 * W + 220].r == 255, "the first frame has no previous frame: the skin doesn't wrap around")
		k0 := onion_key(do_)
		onion_alpha = 60
		check(t, k0 != onion_key(do_), "a new opacity redraws the canvas")
		playing = true
		check(t, onion_key(do_)[0] == 0, "no onion skin during playback")
		playing = false
		onion, onion_prev, onion_next, onion_alpha = saved[0] != 0, saved[1], saved[2], saved[3]
		prefs_parse("onion=1\nonion_prev=2\nonion_next=9\nonion_alpha=70\nnavigator=0\n")
		check(t, onion && onion_prev == 2 && onion_next == 5 && onion_alpha == 70 && !show_navigator, "onion and navigator settings load")
		onion, onion_prev, onion_next, onion_alpha = saved[0] != 0, saved[1], saved[2], saved[3]
		show_navigator = true
	}

	// files: save, read back, and open for real
	{
		da := sim_doc()
		grad := add_rect(da, 10)
		grad.fill = paint_make_gradient(paint_solid({10, 200, 30, 255}), Bounds{10, 10, 50, 50}, false)
		run_cmd(.Frame_New)
		add_rect(da, 100, {0, 0, 255, 255})
		g2 := add_rect(da, 150)
		g2.fill = paint_make_gradient(paint_solid({200, 20, 30, 255}), Bounds{150, 10, 190, 50}, true)
		run_cmd(.Frame_New)
		da.frames[0].duration, da.frames[1].duration, da.frames[2].duration = 100, 250, 150
		tg := Tag {
			from  = 1,
			to    = 2,
			dir   = .Ping_Pong,
			color = {10, 20, 30, 255},
		}
		name_set(&tg.name, "a & b: c;")
		append(&da.tags, tg)
		text_out := svg_string(da)
		check(t, strings.contains(text_out, "data-pangolin-frame=\"100\">") && strings.contains(text_out, "data-pangolin-frame=\"250\" display=\"none\""), "frames after the first are hidden for viewers without animation")
		check(t, strings.contains(text_out, "values=\"inline;none\" keyTimes=\"0;0.200000\" calcMode=\"discrete\" dur=\"500ms\" repeatCount=\"indefinite\""), "the first frame's animation")
		check(t, strings.contains(text_out, "values=\"none;inline;none\" keyTimes=\"0;0.200000;0.700000\""), "a middle frame's animation")
		check(t, strings.contains(text_out, "values=\"none;inline\" keyTimes=\"0;0.700000\""), "the last frame's animation")

		path := tmp_path("frames.svg")
		check(t, svg_save(da, path), "a document with frames saves")
		frame_set(da, 1)
		n_before := len(docs)
		open_path(path)
		check(t, len(docs) == n_before + 1, "a file with frames opens")
		if len(docs) == n_before + 1 {
			back := docs[len(docs) - 1]
			check(t, len(svg_skipped) == 0, "animate isn't counted as an unsupported element")
			check(t, len(back.frames) == 3 && back.active_frame == 0 && back.root == back.frames[0].root, "frames survive a save")
			if len(back.frames) == 3 {
				check(t, back.frames[0].duration == 100 && back.frames[1].duration == 250 && back.frames[2].duration == 150, "durations survive a save")
				check(t, len(back.frames[0].root.children) == 1 && len(back.frames[1].root.children) == 2 && len(back.frames[2].root.children) == 0, "each frame keeps its objects")
				check(t, back.frames[1].root.children[0].fill.color == Color{0, 0, 255, 255}, "objects in a hidden frame keep their style")
				check(t, back.frames[1].root.children[1].fill.kind == .Radial, "a gradient in a later frame survives")
				check(t, back.frames[0].root.children[0].fill.kind == .Linear, "a gradient in the first frame survives")
			}
			check(t, len(back.tags) == 1, "tags survive a save")
			if len(back.tags) == 1 {
				bt := back.tags[0]
				check(t, bt.from == 1 && bt.to == 2 && bt.dir == .Ping_Pong && bt.color == Color{10, 20, 30, 255}, "a tag's range, direction and color survive")
				check(t, name_str(&bt.name) == "a & b c", "a tag's name survives, without the separators")
			}
			check(t, !back.modified, "an opened file isn't modified")
			frame_set(back, 1)
			check(t, svg_string(back) != "" && !back.modified, "a frame of an opened file can be shown")
			pop(&docs)
		}
		os.remove(path)

		vb := `<svg xmlns="http://www.w3.org/2000/svg" viewBox="10 20 100 100"><g data-pangolin-frame="50"><rect x="10" y="20" width="5" height="5"/></g><g data-pangolin-frame="5" display="none"><rect x="30" y="20" width="5" height="5"/></g><rect x="40" y="20" width="5" height="5"/></svg>`
		dv, vok := svg_parse(vb)
		check(t, vok && len(dv.frames) == 2, "frames parse with a view box")
		if vok && len(dv.frames) == 2 {
			check(t, near(dv.frames[1].root.children[0].xf.e, -10), "the view box moves every frame")
			check(t, dv.frames[1].duration == 10, "a frame's duration is at least 10 ms")
			check(t, len(dv.frames[0].root.children) == 2, "an object beside the frames joins the first one")
		}
		doc_free(dv)
	}

	// names: an id appears once in a file, but names repeat in a new frame or a duplicate
	{
		dn := sim_doc()
		name_set(&add_rect(dn, 10).name, "Ball")
		name_set(&add_rect(dn, 20).name, "Ball") // a repeat in the same frame
		name_set(&add_rect(dn, 30).name, "Ball-2") // a name that looks like the id the repeat gets
		add_rect(dn, 40) // keeps its default name, so it has no id
		run_cmd(.Frame_Dup)
		out := svg_string(dn)
		for id in ([]string{"Ball", "Ball-2", "Ball-3", "Ball-4", "Ball-2-2", "Ball-2-3"}) {
			check(t, strings.count(out, fmt.tprintf(" id=\"%s\"", id)) == 1, fmt.tprintf("the id %s appears once in the file", id))
		}
		check(t, strings.count(out, " id=\"") == 6, "every repeated name has an id, and default names have none")
		check(t, strings.count(out, " data-pangolin-name=\"Ball\"") == 3 && strings.count(out, " data-pangolin-name=\"Ball-2\"") == 2, "a repeat keeps its name beside its id")

		back, ok := svg_parse(out)
		check(t, ok && len(back.frames) == 2, "a file with repeated names opens")
		if ok && len(back.frames) == 2 {
			want := [4]string{"Ball", "Ball", "Ball-2", "Rectangle"}
			for f in back.frames {
				check(t, len(f.root.children) == 4, "each frame keeps its named objects")
				if len(f.root.children) != 4 do continue
				for c, i in f.root.children {
					check(t, name_str(&c.name) == want[i], fmt.tprintf("object %d keeps its name, not its id", i))
				}
			}
			check(t, svg_string(back) == out, "saving again gives the same file")
		}
		doc_free(back)

		grouped, gok := svg_parse(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><g id="Arm"><rect id="Arm-2" data-pangolin-name="Arm" width="1" height="1"/></g><rect id="Plain" width="1" height="1"/><rect id="x" inkscape:label="Label" width="1" height="1"/></svg>`)
		check(t, gok && len(grouped.root.children) == 3, "named objects parse")
		if gok && len(grouped.root.children) == 3 {
			g := grouped.root.children[0]
			check(t, name_str(&g.name) == "Arm" && len(g.children) == 1 && name_str(&g.children[0].name) == "Arm", "a group and an object inside it can share a name")
			check(t, name_str(&grouped.root.children[1].name) == "Plain", "a plain id is still the name")
			check(t, name_str(&grouped.root.children[2].name) == "x", "an id still comes before a label")
		}
		doc_free(grouped)

		// names an id can't hold
		odd := []string{"Layer 1", "a & b <c> \"d\"", "1st", "Größe"}
		ds, sok := svg_parse(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect id="x" width="1" height="1"/><rect id="y" width="1" height="1"/><rect id="z" width="1" height="1"/><rect id="w" width="1" height="1"/></svg>`)
		check(t, sok && len(ds.root.children) == len(odd), "objects to rename parse")
		if sok && len(ds.root.children) == len(odd) {
			for c, i in ds.root.children do name_set(&c.name, odd[i])
			s1 := svg_string(ds)
			check(t, !strings.contains(s1, " id=\""), "a name an id can't hold doesn't become an id")
			sb, sbok := svg_parse(s1)
			check(t, sbok && len(sb.root.children) == len(odd), "a file with such names opens")
			if sbok && len(sb.root.children) == len(odd) {
				for c, i in sb.root.children {
					check(t, name_str(&c.name) == odd[i], fmt.tprintf("the name %s survives a save", odd[i]))
				}
				check(t, svg_string(sb) == s1, "saving such names again gives the same file")
			}
			doc_free(sb)
		}
		doc_free(ds)
		label, lok := svg_parse(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect inkscape:label="Layer 1" width="1" height="1"/></svg>`)
		if lok && len(label.root.children) == 1 {
			lb, lbok := svg_parse(svg_string(label))
			check(t, lbok && len(lb.root.children) == 1 && name_str(&lb.root.children[0].name) == "Layer 1", "an imported label survives a save")
			doc_free(lb)
		}
		doc_free(label)
	}

	// hidden objects: not drawn, but kept
	{
		src := `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="20">
		<rect id="seen" x="0" y="0" width="10" height="10" fill="#ff0000"/>
		<rect id="gone" x="20" y="0" width="10" height="10" fill="#00ff00" display="none"/>
		<g id="box" style="display:none"><rect id="inside" x="40" y="0" width="10" height="10" fill="#0000ff"/></g>
		<use href="#seen" x="60" display="none"/>
		<rect x="80" y="0" width="10" height="10" fill="#00ffff" visibility="hidden"/></svg>`
		dh, ok := svg_parse(src)
		check(t, ok && len(dh.root.children) == 5, "hidden objects open")
		if ok && len(dh.root.children) == 5 {
			kids := dh.root.children
			check(t, kids[0].visible && !kids[1].visible && !kids[2].visible && !kids[3].visible && !kids[4].visible, "hidden objects open hidden")
			check(t, kids[2].kind == .Group && len(kids[2].children) == 1 && kids[2].children[0].visible, "what's inside a hidden group isn't hidden itself")
			check(t, kids[3].kind == .Group, "a hidden use is a hidden group")
			check(t, kids[1].fill.color == Color{0, 255, 0, 255}, "a hidden object keeps its style")

			pix, w, _ := render_to_pixels(dh, 1, WHITE, true)
			at := proc(pix: []Color, w, x: int) -> Color {return pix[5 * w + x]}
			check(t, at(pix, w, 5) == Color{255, 0, 0, 255}, "a shown object is drawn")
			check(t, at(pix, w, 25) == WHITE && at(pix, w, 45) == WHITE && at(pix, w, 65) == WHITE && at(pix, w, 85) == WHITE, "hidden objects aren't drawn")

			s1 := svg_string(dh)
			back, bok := svg_parse(s1)
			check(t, bok && len(back.root.children) == 5, "hidden objects survive a save")
			if bok && len(back.root.children) == 5 {
				k := back.root.children
				check(t, k[0].visible && !k[1].visible && !k[2].visible && !k[3].visible && !k[4].visible, "hidden objects stay hidden after a save")
				check(t, svg_string(back) == s1, "saving hidden objects again gives the same file")
			}
			doc_free(back)
		}
		doc_free(dh)

		// in frames
		df := sim_doc()
		add_rect(df, 10)
		add_rect(df, 60).visible = false
		run_cmd(.Frame_Dup)
		fb, fok := svg_parse(svg_string(df))
		check(t, fok && len(fb.frames) == 2, "hidden objects open in frames")
		if fok && len(fb.frames) == 2 {
			for f in fb.frames {
				check(t, len(f.root.children) == 2 && f.root.children[0].visible && !f.root.children[1].visible, "each frame keeps its hidden object, hidden")
			}
		}
		doc_free(fb)
	}

	// locked objects stay locked
	{
		dl := sim_doc()
		add_rect(dl, 10)
		add_rect(dl, 60).locked = true
		both := add_rect(dl, 110)
		both.locked, both.visible = true, false
		grp := node_new(dl, .Group)
		name_set(&grp.name, "Group")
		grp.locked = true
		inner := new_shape(dl, .Rect)
		inner.x, inner.y, inner.w, inner.h = 160, 10, 40, 40
		inner.fill, inner.stroke = paint_solid({0, 0, 0, 255}), paint_none()
		append(&grp.children, inner)
		append(&dl.root.children, grp)
		run_cmd(.Frame_Dup)
		s1 := svg_string(dl)
		check(t, strings.count(s1, " data-pangolin-locked=\"true\"") == 6, "only locked objects are marked locked in the file")
		lb, lok := svg_parse(s1)
		check(t, lok && len(lb.frames) == 2, "locked objects open")
		if lok && len(lb.frames) == 2 {
			for f in lb.frames {
				k := f.root.children
				check(t, len(k) == 4, "each frame keeps its locked objects")
				if len(k) != 4 do continue
				check(t, !k[0].locked && k[0].visible, "an unlocked object stays unlocked")
				check(t, k[1].locked && k[1].visible, "a locked object stays locked")
				check(t, k[2].locked && !k[2].visible, "an object can stay both locked and hidden")
				check(t, k[3].kind == .Group && k[3].locked && len(k[3].children) == 1 && !k[3].children[0].locked, "a locked group stays locked, what's inside it doesn't become locked itself")
			}
			check(t, svg_string(lb) == s1, "saving locked objects again gives the same file")
			check(t, pick_node(lb, {30, 30}, false) != nil, "an unlocked object from a file can be picked")
			check(t, pick_node(lb, {80, 30}, false) == nil, "a locked object from a file can't be picked")

			dest := sim_doc()
			added := doc_add_objects(dest, lb.root.children[:])
			check(t, added == 4 && dest.root.children[1].locked && !dest.root.children[0].locked, "pasting from SVG text keeps the lock")
		}
		doc_free(lb)
	}

	// export
	{
		de := sim_doc()
		add_rect(de, 10, {255, 0, 0, 255})
		run_cmd(.Frame_New)
		add_rect(de, 100, {0, 0, 255, 255})
		run_cmd(.Frame_New)
		frame_set(de, 0)
		de.frames[0].duration = 80
		data, w, h := export_gif_bytes(de, 0.5, true, true)
		check(t, len(data) > 6 && string(data[:6]) == "GIF89a", "the GIF starts with GIF89a")
		check(t, w == 200 && h == 150, "the GIF has the page's size at this scale")
		pix, gw, gh, gok := stb_decode(data)
		check(t, gok && gw == 200 && gh == 150, "the GIF decodes to the right size")
		if gok do check(t, pix[15 * gw + 15].r > 200 && pix[15 * gw + 15].b < 60, "the GIF starts with the first frame")
		delete(pix)
		png0, _, _ := render_to_pixels(de, 1, WHITE, true, 1)
		check(t, png0[30 * 400 + 110].b == 255 && png0[30 * 400 + 110].r == 0, "a frame other than the live one can be rendered")

		stem := tmp_path("seq")
		check(t, export_sequence(de, stem, 0.25, false) == 3, "a sequence writes one file per frame")
		first := fmt.tprintf("%s_0001.png", stem)
		fdata, fok := read_file(first)
		check(t, fok, "a sequence numbers its files from 0001")
		if fok {
			ip, iw, ih, iok := stb_decode(fdata)
			check(t, iok && iw == 100 && ih == 75, "a sequence's files have the right size")
			delete(ip)
			delete(fdata)
		}
		for i in 1 ..= 3 do os.remove(fmt.tprintf("%s_%04d.png", stem, i))

		tg := Tag {
			from = 1,
			to   = 2,
		}
		append(&de.tags, tg)
		lo, hi := export_frame_range(de)
		check(t, lo == 0 && hi == 2, "export takes every frame by default")
		play_tag, export_range_tag = 0, true
		lo, hi = export_frame_range(de)
		check(t, lo == 1 && hi == 2, "export can keep to the selected tag")
		check(t, export_sequence(de, stem, 0.25, false) == 2, "a sequence honors the tag's range")
		for i in 1 ..= 2 do os.remove(fmt.tprintf("%s_%04d.png", stem, i))
		play_tag, export_range_tag = -1, false
	}

	// a font document stays one frame, and its glyphs work as before
	{
		f := font_new_blank()
		fd := font_edit_doc(f, "t")
		doc = fd
		run_cmd(.Frame_New)
		run_cmd(.Frame_Dup)
		run_cmd(.Play)
		check(t, len(fd.frames) == 1 && !playing, "a font has no frames to add or play")
		font_select_glyph(fd, 3)
		check(t, frame_root(fd, 0) == fd.root, "a font's one frame follows the glyph being edited")
		history_push(fd)
		history_undo(fd)
		check(t, len(fd.frames) == 1 && fd.root != nil, "undo in a font")
		check(t, !bottom_has_timeline(), "a font has no timeline")
		doc = nil
	}
}

groups_more_selftest :: proc(t: ^Test_Run) {
	d := sim_doc()
	tool_groups_default()
	set_tool(.Select)

	// the saved file of an earlier version still loads
	old := "49:Select,Node,Control:Select:;50:Pen,Freehand,Line:Draw:;51:Rect,Ellipse,Node:Shapes:;52:Text,Picker:Text:Simplify;53:Hand,Zoom:View:Simplify;71:::Intersect,Subtract,Union"
	tool_groups_parse(old)
	check(t, len(tool_groups) == 6 && len(tool_groups[0].tools) == 3 && tool_groups[0].key == .ONE && name_str(&tool_groups[0].name) == "Select", "groups saved by an earlier version load")
	check(t, len(tool_groups[3].ops) == 1 && tool_groups[3].ops[0] == .Simplify && len(tool_groups[5].ops) == 3 && tool_groups[5].key == .G, "their operations and hotkeys too")
	check(t, tool_groups_serialize() == old, "and they save the same as before")

	// switches sit among the tools without becoming the tool
	tool_groups_default()
	vg := 4
	check(t, len(tool_groups[vg].tools) == 4 && tool_groups[vg].tools[2] == .Grid && tool_groups[vg].tools[3] == .Snap, "the View group holds Hand, Zoom, Grid and Snap")
	set_tool(.Rect)
	show_grid, snap_grid = false, false
	select_tool_in_group(.Grid, vg)
	check(t, show_grid && cur_tool == .Rect && options_switch_on && options_switch == .Grid, "clicking a switch turns it on and shows its settings")
	set_tool(.Ellipse)
	check(t, !options_switch_on && show_grid, "picking a tool brings its settings back and leaves the switch on")
	select_tool_in_group(.Grid, vg)
	check(t, show_grid && options_switch_on, "clicking a switch that is on but not shown shows its settings")
	select_tool_in_group(.Grid, vg)
	check(t, !show_grid && !options_switch_on, "clicking it again turns it off")
	run_cmd(.Toggle_Snap)
	check(t, snap_grid && options_switch == .Snap && options_switch_on, "the menu and shortcut keep the options bar in step")
	run_cmd(.Toggle_Snap)
	check(t, !snap_grid && !options_switch_on, "and turn it off")
	set_tool(.Grid)
	check(t, show_grid && cur_tool == .Ellipse, "a switch never becomes the current tool")
	switch_set(.Grid, false)
	for tool in Tool do check(t, tool_is_toggle(tool) || TOOL_HINT[tool] != "", "every tool has a hint for the status bar")

	// the hotkey steps through the real tools only
	tool_group_activate(vg)
	check(t, cur_tool == .Hand, "the hotkey picks the group's tool, not a switch")
	tool_group_activate(vg)
	tool_group_activate(vg)
	check(t, cur_tool == .Hand && !show_grid, "the hotkey steps over the switches")
	append(&tool_groups, Tool_Group{key = .NINE})
	append(&tool_groups[len(tool_groups) - 1].tools, Tool.Grid, Tool.Snap)
	tool_group_activate(len(tool_groups) - 1)
	check(t, show_grid && cur_tool == .Hand, "the hotkey of a group of only switches flips its first one")
	switch_set(.Grid, false)
	s := tool_groups_serialize()
	check(t, strings.contains(s, "Hand,Zoom,Grid,Snap"), "switches are saved by name")
	tool_groups_parse(s)
	check(t, tool_groups[len(tool_groups) - 1].tools[1] == .Snap && tool_groups[vg].last == .Hand, "switches load, and a group's last tool is a real one")

	// color groups
	tool_groups_default()
	set_tool(.Rect)
	red, green, blue := Color{255, 0, 0, 255}, Color{0, 255, 0, 255}, Color{0, 0, 255, 255}
	cg := Tool_Group {
		key  = .C,
		name = make_name("Paint"),
	}
	group_add_colors(&cg, {red, green, blue})
	append(&tool_groups, cg)
	ci := len(tool_groups) - 1
	saved_fill := cur_fill
	cur_fill = paint_solid(green)
	tool_group_activate(ci)
	check(t, cur_fill.color == blue && cur_tool == .Rect, "a color group's hotkey steps the fill for new shapes, and leaves the tool")
	tool_group_activate(ci)
	check(t, cur_fill.color == red, "it wraps around")
	cur_fill = paint_solid({1, 2, 3, 255})
	tool_group_activate(ci)
	check(t, cur_fill.color == red, "from a color outside the group it starts at the first")
	r := add_rect(d, 10, green)
	sel_set(d, r)
	last_style_push = -100
	undo_n := len(d.undo)
	tool_group_activate(ci)
	check(t, r.fill.color == blue, "with a selection, it changes the selection's fill")
	check(t, len(d.undo) == undo_n + 1, "that can be undone")
	group_color_pick(red)
	check(t, r.fill.color == red && group_color_is_current(red) && !group_color_is_current(blue), "clicking a color in the group picks it")
	s = tool_groups_serialize()
	check(t, strings.contains(s, ":ff0000,00ff00,0000ff"), "colors are saved in the group's string")
	check(t, strings.contains(s, "49:Select,Node,Control:Select:;"), "other groups are saved as before")
	tool_groups_parse(s)
	cgl := tool_groups[len(tool_groups) - 1]
	check(t, len(cgl.colors) == 3 && cgl.colors[2] == blue && cgl.key == .C && name_str(&cgl.name) == "Paint", "a color group round trip")
	check(t, len(tool_groups[0].colors) == 0, "tool groups have no colors")
	tool_groups_parse("48:::: ,zz,12345,ff0000")
	check(t, len(tool_groups[0].colors) == 1, "colors that make no sense are dropped")
	tool_groups_parse("48:Pen:::ff0000")
	check(t, len(tool_groups[0].colors) == 0 && len(tool_groups[0].tools) == 1, "a group with tools holds no colors")
	check(t, len(swatches_list()) == len(DEFAULT_SWATCHES), "the swatches start with the default colors")
	cur_fill = saved_fill

	clear(&recent)
	recent_push(red)
	recent_push(blue)
	recent_push(red)
	check(t, len(recent) == 2 && recent[0] == red && recent[1] == blue, "recent colors: newest first, once each")
	h, sv, v := rgb_to_hsv({255, 128, 0, 255})
	back := hsv_to_rgb(h, sv, v)
	check(t, back.r == 255 && abs(int(back.g) - 128) <= 1 && back.b == 0, "hsv round trip")

	tool_groups_default()
	set_tool(.Select)
}

key :: proc(k: KeyboardKey, ctrl := false, shift := false, alt := false) {
	gfx.key_pressed = {}
	gfx.key_repeat = {}
	gfx.key_pressed[key_scancode(k)] = true
	ui.ctrl, ui.shift, ui.alt = ctrl, shift, alt
	shortcuts_update()
	gfx.key_pressed = {}
	ui.ctrl, ui.shift, ui.alt = false, false, false
}

keys_selftest :: proc(t: ^Test_Run) {
	d := sim_doc()
	tool_groups_default()
	set_tool(.Select)
	key(.B)
	check(t, cur_tool == .Freehand, "B is freehand")
	set_tool(.Select)
	key(.F)
	check(t, cur_tool == .Freehand, "F still is")
	key(.A, shift = true)
	check(t, cur_tool == .Control, "Shift+A is control points")
	key(.A)
	check(t, cur_tool == .Node, "A is node edit")
	key(.O)
	check(t, cur_tool == .Ellipse, "O is ellipse")
	set_tool(.Select)
	key(.E)
	check(t, cur_tool == .Eraser, "E is the eraser")
	set_tool(.Select)
	for pair in ([?]struct {
			k: KeyboardKey,
			t: Tool,
		}{{.R, .Rect}, {.L, .Line}, {.T, .Text}, {.P, .Pen}, {.V, .Select}}) {
		key(pair.k)
		check(t, cur_tool == pair.t, "the other tool keys stay")
	}
	check(t, TOOL_NAMES[.Control] == "Control Points (Shift+A)" && TOOL_NAMES[.Freehand] == "Freehand (B)" && TOOL_NAMES[.Ellipse] == "Ellipse (O)", "tool names show their keys")

	a := add_rect(d, 10)
	sel_set(d, a)
	key(.J, ctrl = true)
	check(t, len(d.root.children) == 2, "Ctrl+J duplicates")
	key(.D, ctrl = true)
	check(t, len(d.sel) == 0 && len(d.root.children) == 2, "Ctrl+D deselects, and no longer duplicates")
	run_cmd(.Select_All)
	key(.A, ctrl = true, shift = true)
	check(t, len(d.sel) == 0, "Ctrl+Shift+A still deselects")
	key(.A, ctrl = true)
	check(t, len(d.sel) == 2, "Ctrl+A selects all")

	z := d.zoom
	key(.EQUAL, ctrl = true)
	check(t, d.zoom > z && len(d.root.children) == 2, "Ctrl+= zooms in, and no longer unites")
	z = d.zoom
	key(.MINUS, ctrl = true)
	check(t, d.zoom < z && len(d.root.children) == 2, "Ctrl+- zooms out")
	z = d.zoom
	key(.EQUAL)
	check(t, d.zoom > z, "plain + still zooms in")
	key(.TWO, ctrl = true)
	check(t, d.zoom == 2, "Ctrl+2 is 200%")
	key(.ONE, ctrl = true)
	check(t, d.zoom == 1, "Ctrl+1 is 100%")

	// the booleans moved to Ctrl+Alt
	two :: proc(d: ^Doc) {
		for c in d.root.children do node_free(c)
		clear(&d.root.children)
		clear(&d.sel)
		x := add_rect(d, 10)
		y := add_rect(d, 30)
		append(&d.sel, x.uid, y.uid)
	}
	two(d)
	key(.EQUAL, ctrl = true, alt = true)
	check(t, len(d.root.children) == 1 && near(path_area(d.root.children[0].segs[:], 200, 200), 2400, 3), "Ctrl+Alt+= unites")
	two(d)
	key(.MINUS, ctrl = true, alt = true)
	check(t, len(d.root.children) == 1 && near(path_area(d.root.children[0].segs[:], 200, 200), 800, 3), "Ctrl+Alt+- subtracts")
	two(d)
	key(.EIGHT, ctrl = true, alt = true)
	check(t, len(d.root.children) == 1 && near(path_area(d.root.children[0].segs[:], 200, 200), 800, 3), "Ctrl+Alt+8 intersects")
	two(d)
	key(.EIGHT, ctrl = true, shift = true)
	check(t, len(d.root.children) == 2, "Ctrl+Shift+8 no longer intersects")
	check(t, cmd_tip("Union", .Union).title == "Union (Ctrl+Alt+=)" && shortcut_text(.Export) == "Ctrl+Shift+E" && shortcut_text(.Duplicate) == "Ctrl+J" && shortcut_text(.Deselect) == "Ctrl+D", "the menus show the new keys")

	// windows
	key(.E, ctrl = true)
	check(t, dialog.kind == .None, "Ctrl+E is free")
	key(.E, ctrl = true, shift = true)
	check(t, dialog.kind == .Export, "Ctrl+Shift+E exports")
	dialog_close()
	key(.F1)
	check(t, dialog.kind == .Shortcuts, "F1 lists the shortcuts")
	dialog_close()

	// z-order keeps Home and End
	two(d)
	first := d.root.children[0]
	sel_set(d, first)
	key(.HOME)
	check(t, d.root.children[1] == first, "Home brings to front")
	key(.END)
	check(t, d.root.children[0] == first && d.active_frame == 0, "End sends to back, and doesn't change frame")

	// frames
	key(.N, alt = true)
	check(t, len(d.frames) == 2 && d.active_frame == 1, "Alt+N adds a frame")
	key(.N)
	check(t, len(d.frames) == 2, "N alone doesn't")
	run_cmd(.Frame_New)
	key(.COMMA)
	check(t, d.active_frame == 1, ", goes to the previous frame")
	key(.PERIOD)
	check(t, d.active_frame == 2, ". goes to the next frame")
	key(.PERIOD)
	check(t, d.active_frame == 0, ". wraps around")
	key(.PERIOD, shift = true)
	check(t, d.active_frame == 2, "Shift+. goes to the last frame")
	key(.COMMA, shift = true)
	check(t, d.active_frame == 0, "Shift+, goes to the first frame")
	key(.ENTER)
	check(t, playing, "Enter plays")
	key(.ENTER)
	check(t, !playing, "Enter stops")
	saved_onion := onion
	key(.O, alt = true)
	check(t, onion != saved_onion && cur_tool != .Ellipse, "Alt+O flips the onion skin, and doesn't pick the ellipse")
	switch_set(.Onion, saved_onion)

	// Enter belongs to the pen and to text being edited
	set_tool(.Pen)
	sim_click(d, {50, 50})
	sim_click(d, {90, 50})
	check(t, pen_drawing(), "the pen is drawing")
	key(.ENTER)
	check(t, !pen_drawing() && !playing, "Enter finishes the pen's path and doesn't play")
	set_tool(.Text)
	sim_click(d, {40, 100})
	check(t, text_editing(), "the text tool is editing")
	key(.ENTER)
	key(.COMMA)
	check(t, !playing && d.active_frame == 0, "keys go to the text being edited")
	text_finish()

	// S and C belong to the node tool, unless a group takes the letter
	nd := sim_doc()
	p := new_shape(nd, .Path)
	path_move(&p.segs, {10, 10})
	path_line(&p.segs, {50, 50})
	path_line(&p.segs, {90, 10})
	append(&nd.root.children, p)
	set_tool(.Node)
	sim_click(nd, {30, 30})
	sim_click(nd, {50, 50})
	check(t, len(tl.anchors) == 1, "a node is selected")
	key(.S)
	check(t, cur_tool == .Node && p.segs[2].kind == .Cubic, "S smooths the node")
	key(.C)
	check(t, cur_tool == .Node && p.segs[2].c1 == p.segs[1].p, "C makes it a corner")
	tool_groups[0].key = .S
	key(.S)
	check(t, cur_tool == .Control, "a group hotkey on S takes the letter")
	tool_groups_default()
	set_tool(.Select)
	doc = nil
}

workspaces_selftest :: proc(t: ^Test_Run) {
	d := sim_doc()
	check(t, len(WS_BUILTIN_NAMES) == 4 && WS_BUILTIN_NAMES[1] == "Illustration" && WS_BUILTIN_NAMES[2] == "Font Design" && WS_BUILTIN_NAMES[3] == "Animation", "the built-in workspaces")
	check(t, MENU_TITLES_SVG[5] == "Frame" && MENU_TITLES_SVG[6] == "View" && MENU_TITLES_SVG[7] == "Workspaces" && MENU_TITLES_SVG[8] == "Help", "the menus of a drawing, in order")
	check(t, MENU_TITLES_FONT[5] == "Font" && MENU_TITLES_FONT[6] == "View" && MENU_TITLES_FONT[7] == "Workspaces", "the menus of a font, with no Frame menu")
	for title in MENU_TITLES_SVG do check(t, menu_title_tip(title).desc != "", "every menu title has help text")
	for i in 0 ..< len(WS_BUILTIN_NAMES) {
		check(t, WS_BUILTIN_HELP[i] != "", "every built-in workspace has help text")
		workspace_builtin(i)
		check(t, len(tool_groups) > 2 && !tool_is_toggle(cur_tool), "a built-in workspace has groups and picks a real tool")
		for &g in tool_groups do check(t, len(g.tools) + len(g.ops) + len(g.colors) > 0 && g.key != .KEY_NULL && g.name.n > 0, "its groups are filled, named and have hotkeys")
	}
	workspace_builtin(0)
	dflt := strings.clone(tool_groups_serialize(), context.temp_allocator)
	tool_groups_default()
	check(t, tool_groups_serialize() == dflt, "Default is the default tool groups")

	// a saved workspace, with colors, comes back whole
	workspace_builtin(1)
	sv := strings.clone(tool_groups_serialize(), context.temp_allocator)
	check(t, strings.contains(sv, "Colors:") && strings.contains(sv, "Union,Subtract"), "Illustration holds colors and operations")
	txt := strings.clone(workspace_text(), context.temp_allocator)
	check(t, strings.has_prefix(txt, "scws=1\n"), "the workspace file format")
	workspace_builtin(0)
	check(t, !workspace_apply_text("not a workspace") && tool_groups_serialize() == dflt, "text without groups changes nothing")
	check(t, workspace_apply_text(txt) && tool_groups_serialize() == sv, "a workspace round trip")
	check(t, ws_clean_name(` a/b:c*?"<>| `) == "abc", "workspace names lose what a file name can't hold")

	// the folder
	name := "selftest workspace"
	check(t, workspace_save_named(name), "a workspace saves")
	check(t, ws_current == name, "the saved workspace is the current one")
	ws_refresh()
	found := -1
	for e, i in ws_entries do if e.name == name do found = i
	check(t, found >= len(WS_BUILTIN_NAMES), "saved workspaces follow the built-in ones")
	if found >= 0 {
		workspace_builtin(0)
		run_cmd(Cmd(int(Cmd.Ws_First) + found))
		check(t, tool_groups_serialize() == sv, "the menu's item loads the saved workspace")
		workspace_delete_index(found)
		ws_refresh()
		for e in ws_entries do check(t, e.name != name, "deleting a workspace removes its file")
		workspace_delete_index(0)
		ws_refresh()
		check(t, ws_entries[0].name == "Default", "a built-in workspace can't be deleted")
	}
	workspace_builtin(0)
	delete(ws_current)
	ws_current = ""
	_ = d
	doc = nil
}

files_selftest :: proc(t: ^Test_Run) {
	check(t, files_listed("a.SVG") && files_listed("b.ttf") && files_listed("c.OTF") && files_listed("d.png") && files_listed("e.webp") && files_listed("f.jpeg"), "the browser lists drawings, fonts and images")
	check(t, !files_listed("g.txt") && !files_listed("h"), "and nothing else")
	check(t, files_preview_on_main("a.svg") && !files_preview_on_main("a.ttf") && !files_preview_on_main("a.png"), "only SVG previews need the main thread")

	d := sim_doc()
	check(t, bottom_has_timeline(), "a drawing has a timeline")
	src := doc_new(.Svg, "src", 100, 100)
	n1 := new_shape(src, .Rect)
	n1.x, n1.y, n1.w, n1.h = 0, 0, 20, 20
	n1.fill, n1.stroke = paint_solid({255, 0, 0, 255}), paint_none()
	n2 := new_shape(src, .Rect)
	n2.x, n2.y, n2.w, n2.h = 40, 0, 20, 20
	n2.fill, n2.stroke = paint_solid({0, 255, 0, 255}), paint_none()
	append(&src.root.children, n1, n2)
	svg_file := tmp_path("drop.svg")
	check(t, svg_save(src, svg_file), "a drawing to drop")
	doc_free(src)

	// previews
	pix, w, h, ok := files_preview(svg_file)
	check(t, ok && w == THUMB_MAX && h == THUMB_MAX, "an SVG preview fits the thumbnail")
	if ok {
		check(t, pix[10].r == 255 && pix[10].g == 0, "an SVG preview shows the drawing")
		check(t, pix[(h - 1) * w + w - 1] == WHITE, "on a white page")
		delete(pix) // it must be on the heap
	}
	font_file := tmp_path("font.ttf")
	font_data := FONT_DATA
	write_file(font_file, font_data[:])
	pix, w, h, ok = files_preview(font_file)
	check(t, ok && w > 0 && h > 0, "a font has a preview")
	if ok {
		dark, light := 0, 0
		for p in pix {
			if p.r < 64 do dark += 1
			if p.r > 200 do light += 1
		}
		check(t, dark > 100 && light > 100 && pix[0] == WHITE, "a font's preview is black on white")
		delete(pix)
	}
	img := [4]Color{{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}, {255, 255, 255, 255}}
	png_file := tmp_path("img.png")
	write_file(png_file, encode_png(img[:], 2, 2))
	pix, w, h, ok = files_preview(png_file)
	check(t, ok && w == 2 && h == 2 && pix[2] == img[2], "an image's preview is the image")
	if ok do delete(pix)
	bad_file := tmp_path("bad.ttf")
	write_file(bad_file, transmute([]u8)string("not a font"))
	_, _, _, ok = files_preview(bad_file)
	check(t, !ok, "a broken file has no preview")

	// hints
	check(t, files_drop_hint(svg_file, true) != "" && files_drop_hint(svg_file, false) != "" && files_drop_hint(font_file, false) != "" && files_drop_hint(png_file, true) != "", "every kind of file says what a drop does")
	check(t, files_drop_hint("x.txt", false) == "", "other files say nothing")

	// an SVG dropped on the canvas: its objects, centered at the drop point, selected, undoable
	add_rect(d, 300)
	ui.mx, ui.my = 200, 150
	undo_n := len(d.undo)
	files_drop(svg_file, false)
	check(t, len(d.root.children) == 3 && len(d.sel) == 2, "a drop on the canvas adds the objects and selects them")
	b := sel_bounds(d)
	check(t, near(bounds_center(b).x, 200, 0.01) && near(bounds_center(b).y, 150, 0.01), "centered at the drop point")
	check(t, len(d.undo) == undo_n + 1, "as one undo step")
	check(t, d.root.children[1].uid != d.root.children[2].uid && d.root.children[1].uid != d.root.children[0].uid, "with their own ids")
	history_undo(d)
	check(t, len(d.root.children) == 1, "undo takes them away")

	// on the tabs it opens; so does a font, either way
	n_docs := len(docs)
	files_drop(svg_file, true)
	check(t, len(docs) == n_docs + 1 && doc.kind == .Svg, "a drop on the tabs opens the drawing")
	if len(docs) > n_docs do pop(&docs)
	doc = d
	files_drop(font_file, false)
	check(t, len(docs) == n_docs + 1 && doc.kind == .Font, "a font opens")
	if len(docs) > n_docs do pop(&docs)
	doc = d

	// an image becomes the tracing image
	files_drop(png_file, true)
	check(t, near(d.trace_s, 150) && near(d.trace_pos.x, 50) && near(d.trace_pos.y, 0) && near(d.trace_a, 0.4), "a drop on the tabs fits the tracing image to the page")
	files_drop(png_file, false)
	check(t, near(d.trace_pos.x, 200 - 150) && near(d.trace_pos.y, 150 - 150), "a drop on the canvas centers it at the drop point")
	check(t, !trace_load_path(d, bad_file) && dialog.kind == .Message, "a file that isn't an image says so")
	dialog_close()

	for f in ([?]string{svg_file, font_file, png_file, bad_file}) do os.remove(f)
	doc = nil
}
