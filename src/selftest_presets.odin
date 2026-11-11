package pangolin

import "core:fmt"
import "core:strings"

// Tests of the saveable presets: the stroke style, eraser and sculpt presets, and the user's presets in the prefs.

presets_selftest :: proc(t: ^Test_Run) {
	saved_presets := user_presets
	user_presets = {}
	saved_sw, saved_cap, saved_join, saved_miter := cur_sw, cur_cap, cur_join, cur_miter
	saved_dash, saved_ndash, saved_off, saved_time := cur_dash, cur_ndash, cur_dash_off, ui.time
	saved_eraser, saved_sculpt := eraser_to_ints(), sculpt_to_ints()
	defer {
		for len(user_presets) > 0 do preset_remove(len(user_presets) - 1)
		delete(user_presets)
		user_presets = saved_presets
		cur_sw, cur_cap, cur_join, cur_miter = saved_sw, saved_cap, saved_join, saved_miter
		cur_dash, cur_ndash, cur_dash_off, ui.time = saved_dash, saved_ndash, saved_off, saved_time
		eraser_from_ints(saved_eraser[:])
		sculpt_from_ints(saved_sculpt[:])
		doc = nil
	}

	// a user preset survives being written to the prefs and read back
	{
		vals := [?]int{350, 1, 2, 400, 700, 300, 0, 0, 2, -50}
		preset_store("stroke", "Test wide", vals[:])
		preset_store("eraser", "Test big", {90, 0})
		sb := strings.builder_make(context.temp_allocator)
		files_prefs_write(&sb)
		lines := make([dynamic]string, context.temp_allocator)
		for line in strings.split_lines(strings.to_string(sb), context.temp_allocator) {
			if strings.has_prefix(line, "preset=") do append(&lines, line)
		}
		check(t, len(lines) == 2, "the prefs hold a line per user preset")
		for len(user_presets) > 0 do preset_remove(len(user_presets) - 1)
		for line in lines {
			eq := strings.index_byte(line, '=')
			check(t, preset_prefs_read(line[:eq], line[eq + 1:]), "preset_prefs_read takes the preset line")
		}
		v, ok := preset_value("stroke", "Test wide", stroke_builtins[:])
		same := ok && len(v.vals) == len(vals)
		if same do for x, i in vals do same &&= v.vals[i] == x
		check(t, same, fmt.tprintf("a stroke preset's values come back from the prefs (got %v)", v.vals))
		e, eok := preset_value("eraser", "Test big", eraser_builtins[:])
		check(t, eok && len(e.vals) == 2 && e.vals[0] == 90 && e.vals[1] == 0, "an eraser preset comes back from the prefs")
		_, wrong := preset_value("eraser", "Test wide", eraser_builtins[:])
		check(t, !wrong, "presets are kept apart by kind")
	}

	// picking a stroke preset sets the selected objects' stroke and the one new shapes get, in one undo step
	{
		d := sim_doc()
		n := new_shape(d, .Rect)
		n.x, n.y, n.w, n.h = 10, 10, 100, 50
		append(&d.root.children, n)
		doc_changed(d)
		sel_set(d, n)
		uid := n.uid
		before := stroke_style_of(n)
		ui.time += 10
		v, _ := preset_value("stroke", "Dashed 2", stroke_builtins[:])
		style_set_stroke_style(d, stroke_from_ints(stroke_style_current(d), v.vals))
		check(t, n.sw == 2 && n.ndash == 2 && n.dash[0] == 8 && n.dash[1] == 4 && n.cap == .Butt, "a stroke preset sets the selection's stroke")
		check(t, cur_sw == 2 && cur_ndash == 2 && cur_dash[0] == 8, "and the stroke of new shapes")
		now := stroke_to_ints(stroke_style_current(d))
		check(t, preset_same(v, now[:], ""), "the selection then matches the preset")
		check(t, line_pattern_of(n.dash, n.ndash) == 1, "the line pattern shows Dashed")
		p := new_shape(d, .Path)
		check(t, p.ndash == 2 && p.dash[0] == 8, "a new shape gets the dashes")
		node_free(p)
		history_undo(d)
		back := node_find(d.root, uid)
		check(t, back != nil && stroke_style_of(back) == before, "one undo puts the stroke back")

		// a solid line that once had dashes still matches a solid preset
		sel_set(d, back)
		ui.time += 10
		h, _ := preset_value("stroke", "Medium 2 round", stroke_builtins[:])
		style_set_stroke_style(d, stroke_from_ints(stroke_style_current(d), h.vals))
		ui.time += 10
		style_set_line_pattern(d, 1)
		ui.time += 10
		style_set_line_pattern(d, 0)
		now = stroke_to_ints(stroke_style_current(d))
		check(t, back.dash[0] != 0 && preset_same(h, now[:], ""), "unused dashes don't make a solid line differ from its preset")

		// nothing selected: only new shapes change
		clear(&d.sel)
		b, _ := preset_value("stroke", "Dotted 3", stroke_builtins[:])
		undo_n := len(d.undo)
		style_set_stroke_style(d, stroke_from_ints(stroke_style_current(d), b.vals))
		check(t, cur_sw == 3 && cur_cap == .Round && cur_ndash == 2 && line_pattern_of(cur_dash, cur_ndash) == 2, "with nothing selected a preset sets new shapes' stroke")
		check(t, len(d.undo) == undo_n && back.sw == 2, "and leaves the objects and the undo steps alone")
		// a preset saved with fewer values keeps the rest
		st := stroke_from_ints(stroke_style_current(d), {500})
		check(t, st.width == 5 && st.cap == .Round && st.ndash == 2, "a shorter preset keeps the other settings")
	}

	// eraser and sculpt presets
	{
		eraser_from_ints({100000, 0})
		check(t, eraser_size == ERASER_SIZE_MAX && !eraser_pressure, "an eraser preset is kept in range")
		v, _ := preset_value("eraser", "Fine", eraser_builtins[:])
		eraser_from_ints(v.vals)
		ev := eraser_to_ints()
		check(t, eraser_size == 6 && eraser_pressure && preset_same(v, ev[:], ""), "the Fine eraser preset")
		s, _ := preset_value("sculpt", "Broad", sculpt_builtins[:])
		sculpt_from_ints(s.vals)
		check(t, sculpt_size == 160 && sculpt_strength == 100 && sculpt_pressure, "the Broad sculpt preset")
		sculpt_from_ints({1, 1})
		check(t, sculpt_size == SCULPT_SIZE_MIN && sculpt_strength == 5 && sculpt_pressure, "a sculpt preset is kept in range")
	}
}
