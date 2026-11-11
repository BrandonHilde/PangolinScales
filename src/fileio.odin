package pangolin

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

// ---------------------------------------------------------------------------
// Native file dialogs
// ---------------------------------------------------------------------------

Filter :: struct {
	name, pattern: string,
}

FILTERS_OPEN := [?]Filter {
	{"SVG and fonts", "*.svg;*.ttf;*.otf"},
	{"SVG (*.svg)", "*.svg"},
	{"Fonts (*.ttf, *.otf)", "*.ttf;*.otf"},
	{"All files", "*.*"},
}
FILTERS_SVG := [?]Filter{{"SVG (*.svg)", "*.svg"}}
FILTERS_TTF := [?]Filter{{"TrueType font (*.ttf)", "*.ttf"}}
FILTERS_PNG := [?]Filter{{"PNG image (*.png)", "*.png"}}
FILTERS_GIF := [?]Filter{{"GIF image (*.gif)", "*.gif"}}

path_basename :: proc(p: string) -> string {
	i := strings.last_index_any(p, "/\\")
	return i >= 0 ? p[i + 1:] : p
}

path_stem :: proc(p: string) -> string {
	b := path_basename(p)
	i := strings.last_index_byte(b, '.')
	return i > 0 ? b[:i] : b
}

path_ext :: proc(p: string) -> string {
	b := path_basename(p)
	i := strings.last_index_byte(b, '.')
	return i >= 0 ? b[i:] : ""
}

lower_ext :: proc(p: string) -> string {
	return strings.to_lower(path_ext(p), context.temp_allocator)
}

// `dir`: folder the dialog starts in (empty: the system's choice).
native_dialog :: proc(save: bool, title: string, filters: []Filter, def_ext, initial: string, dir := "") -> (path: string, ok: bool) {
	defer gfx_reset_input()
	when ODIN_OS == .Windows {
		return native_dialog_windows(save, title, filters, def_ext, initial, dir)
	} else {
		p, pok := native_dialog_zenity(save, title, filters, def_ext, initial, dir)
		if pok && save do p = path_default_ext(p, def_ext)
		return p, pok
	}
}

when ODIN_OS == .Windows {
	win_path :: proc(p: string) -> string {
		r, _ := strings.replace_all(p, "/", "\\", context.temp_allocator)
		return r
	}

	native_dialog_windows :: proc(save: bool, title: string, filters: []Filter, def_ext, initial, dir: string) -> (path: string, ok: bool) {
		buf := make([]u16, 32768, context.temp_allocator)
		if initial != "" {
			w := win.utf8_to_utf16(initial, context.temp_allocator)
			copy(buf[:len(buf) - 1], w)
		}
		fbuf := make([dynamic]u16, context.temp_allocator)
		for f in filters {
			append(&fbuf, ..win.utf8_to_utf16(f.name, context.temp_allocator))
			append(&fbuf, 0)
			append(&fbuf, ..win.utf8_to_utf16(f.pattern, context.temp_allocator))
			append(&fbuf, 0)
		}
		append(&fbuf, 0)
		append(&fbuf, 0)

		ofn := win.OPENFILENAMEW {
			lStructSize  = size_of(win.OPENFILENAMEW),
			hwndOwner    = win.HWND(gfx_hwnd()),
			lpstrFilter  = win.wstring(raw_data(fbuf)),
			lpstrFile    = raw_data(buf),
			nMaxFile     = u32(len(buf)),
			lpstrTitle   = win.utf8_to_wstring(title),
			Flags        = win.OFN_EXPLORER | win.OFN_NOCHANGEDIR | win.OFN_HIDEREADONLY | (save ? win.OFN_OVERWRITEPROMPT : (win.OFN_FILEMUSTEXIST | win.OFN_PATHMUSTEXIST)),
			lpstrDefExt  = def_ext != "" ? win.utf8_to_wstring(def_ext) : nil,
			lpstrInitialDir = dir != "" ? win.utf8_to_wstring(win_path(dir)) : nil,
		}
		r := save ? win.GetSaveFileNameW(&ofn) : win.GetOpenFileNameW(&ofn)
		if !r {
			return "", false
		}
		s, err := win.wstring_to_utf8(win.wstring(raw_data(buf)), -1, context.allocator)
		if err != nil {
			return "", false
		}
		return s, true
	}
}

// Linux/BSD file picker backed by the Zenity or KDialog helper if present.
when ODIN_OS != .Windows {
	// Zenity's `--file-filter` wants space-separated globs, e.g. "*.png *.jpg".
	zenity_pattern :: proc(p: string, alloc: runtime.Allocator) -> string {
		out, _ := strings.replace_all(p, ";", " ", alloc)
		return out
	}

	native_dialog_zenity :: proc(save: bool, title: string, filters: []Filter, def_ext, initial, dir: string) -> (path: string, ok: bool) {
		start := dir != "" ? fmt.tprintf("%s%s", dir, initial) : initial
		// Zenity
		{
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "zenity", "--file-selection")
			append(&cmd, fmt.tprintf("--title=%s", title))
			if save {
				append(&cmd, "--save", "--confirm-overwrite")
			}
			if start != "" {
				append(&cmd, fmt.tprintf("--filename=%s", start))
			}
			for f in filters {
				pat := zenity_pattern(f.pattern, context.temp_allocator)
				append(&cmd, fmt.tprintf("--file-filter=%s | %s", f.name, pat))
			}
			if out, code, err := run_dialog(cmd[:]); err == nil {
				if code != 0 {
					return "", false
				}
				return clone_trim(out), true
			}
		}
		// KDialog fallback
		{
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "kdialog", fmt.tprintf("--title=%s", title))
			if save {
				append(&cmd, "--getsavefilename")
			} else {
				append(&cmd, "--getopenfilename")
			}
			dir := start
			pattern_spec := "All files (*)"
			if len(filters) > 0 {
				pattern_spec = fmt.tprintf("%s (%s)", filters[0].name, zenity_pattern(filters[0].pattern, context.temp_allocator))
			}
			append(&cmd, dir, pattern_spec)
			if out, code, err := run_dialog(cmd[:]); err == nil {
				if code != 0 {
					return "", false
				}
				return clone_trim(out), true
			}
		}
		set_status("No file picker could be started: install zenity or kdialog")
		return "", false
	}

	run_dialog :: proc(cmd: []string) -> (stdout: string, exit_code: int, err: os.Error) {
		state, out, _ := os.process_exec({command = cmd}, context.temp_allocator) or_return
		return string(out), state.exit_code, nil
	}

	clone_trim :: proc(s: string) -> string {
		return strings.clone(strings.trim_space(s))
	}
}

