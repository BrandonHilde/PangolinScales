package pangolin

import "core:math"
import "core:strings"

// Icons are SVG files (assets/icons, a 24 x 24 grid drawn in currentColor so they can be tinted), rasterised
// by the document renderer at the window's physical resolution for each size they are drawn at.
ICON_SIZE :: 12 // logical px: option bars, object rows, menus
ICON_SIZE_LG :: 16 // tool buttons and the tool picker

Icon :: enum {
	Pencil,
	Eraser,
	Line,
	Rect,
	Ellipse,
	Curve,
	Bucket,
	Picker,
	Sel_Rect,
	Sel_Ellipse,
	Lasso,
	Wand,
	Move,
	Spray,
	Hand,
	Zoom,
	Eye,
	Lock,
	Plus,
	Minus,
	Close,
	Up,
	Down,
	Left,
	Right,
	First,
	Last,
	Stop,
	Trash,
	Copy,
	Layer,
	Frame,
	Onion,
	Grid,
	Pixel_Grid,
	Sym_X,
	Sym_Y,
	Tile,
	Swap,
	Check,
	Merge,
	Brush,
	Oil,
	Smudge,
	Blur,
	Dodge,
	Clone,
	Gradient,
	Transform,
	Crop,
	Mask,
	Lock_Alpha,
	Text,
	Canvas_Mode,
	Seamless,
	Node_Edit,
	Union,
	Subtract,
	Intersect,
	Exclude,
	Combine,
	Break_Apart,
	Reverse,
	Simplify,
	Offset_Out,
	Offset_In,
	To_Path,
	Stroke_Path,
	Pointer,
	Close_Paths,
	Control_Points,
	Close_Path,
	Film,
	Folder,
	Eye_Off,
	Refresh,
	Frame_Left,
	Frame_Right,
	Change_Fill,
	Change_Stroke,
}

ICON_SVG := [Icon]string {
	.Pencil = #load("../assets/icons/pencil.svg", string),
	.Eraser = #load("../assets/icons/eraser.svg", string),
	.Line = #load("../assets/icons/line.svg", string),
	.Rect = #load("../assets/icons/rect.svg", string),
	.Ellipse = #load("../assets/icons/ellipse.svg", string),
	.Curve = #load("../assets/icons/curve.svg", string),
	.Bucket = #load("../assets/icons/bucket.svg", string),
	.Picker = #load("../assets/icons/picker.svg", string),
	.Sel_Rect = #load("../assets/icons/sel_rect.svg", string),
	.Sel_Ellipse = #load("../assets/icons/sel_ellipse.svg", string),
	.Lasso = #load("../assets/icons/lasso.svg", string),
	.Wand = #load("../assets/icons/wand.svg", string),
	.Move = #load("../assets/icons/move.svg", string),
	.Spray = #load("../assets/icons/spray.svg", string),
	.Hand = #load("../assets/icons/hand.svg", string),
	.Zoom = #load("../assets/icons/zoom.svg", string),
	.Eye = #load("../assets/icons/eye.svg", string),
	.Lock = #load("../assets/icons/lock.svg", string),
	.Plus = #load("../assets/icons/plus.svg", string),
	.Minus = #load("../assets/icons/minus.svg", string),
	.Close = #load("../assets/icons/close.svg", string),
	.Up = #load("../assets/icons/up.svg", string),
	.Down = #load("../assets/icons/down.svg", string),
	.Left = #load("../assets/icons/left.svg", string),
	.Right = #load("../assets/icons/right.svg", string),
	.First = #load("../assets/icons/first.svg", string),
	.Last = #load("../assets/icons/last.svg", string),
	.Stop = #load("../assets/icons/stop.svg", string),
	.Trash = #load("../assets/icons/trash.svg", string),
	.Copy = #load("../assets/icons/copy.svg", string),
	.Layer = #load("../assets/icons/layer.svg", string),
	.Frame = #load("../assets/icons/frame.svg", string),
	.Onion = #load("../assets/icons/onion.svg", string),
	.Grid = #load("../assets/icons/grid.svg", string),
	.Pixel_Grid = #load("../assets/icons/pixel_grid.svg", string),
	.Sym_X = #load("../assets/icons/sym_x.svg", string),
	.Sym_Y = #load("../assets/icons/sym_y.svg", string),
	.Tile = #load("../assets/icons/tile.svg", string),
	.Swap = #load("../assets/icons/swap.svg", string),
	.Check = #load("../assets/icons/check.svg", string),
	.Merge = #load("../assets/icons/merge.svg", string),
	.Brush = #load("../assets/icons/brush.svg", string),
	.Oil = #load("../assets/icons/oil.svg", string),
	.Smudge = #load("../assets/icons/smudge.svg", string),
	.Blur = #load("../assets/icons/blur.svg", string),
	.Dodge = #load("../assets/icons/dodge.svg", string),
	.Clone = #load("../assets/icons/clone.svg", string),
	.Gradient = #load("../assets/icons/gradient.svg", string),
	.Transform = #load("../assets/icons/transform.svg", string),
	.Crop = #load("../assets/icons/crop.svg", string),
	.Mask = #load("../assets/icons/mask.svg", string),
	.Lock_Alpha = #load("../assets/icons/lock_alpha.svg", string),
	.Text = #load("../assets/icons/text.svg", string),
	.Canvas_Mode = #load("../assets/icons/canvas_mode.svg", string),
	.Seamless = #load("../assets/icons/seamless.svg", string),
	.Node_Edit = #load("../assets/icons/node_edit.svg", string),
	.Union = #load("../assets/icons/union.svg", string),
	.Subtract = #load("../assets/icons/subtract.svg", string),
	.Intersect = #load("../assets/icons/intersect.svg", string),
	.Exclude = #load("../assets/icons/exclude.svg", string),
	.Combine = #load("../assets/icons/combine.svg", string),
	.Break_Apart = #load("../assets/icons/break_apart.svg", string),
	.Reverse = #load("../assets/icons/reverse.svg", string),
	.Simplify = #load("../assets/icons/simplify.svg", string),
	.Offset_Out = #load("../assets/icons/offset_out.svg", string),
	.Offset_In = #load("../assets/icons/offset_in.svg", string),
	.To_Path = #load("../assets/icons/to_path.svg", string),
	.Stroke_Path = #load("../assets/icons/stroke_path.svg", string),
	.Pointer = #load("../assets/icons/pointer.svg", string),
	.Close_Paths = #load("../assets/icons/close_paths.svg", string),
	.Control_Points = #load("../assets/icons/control_points.svg", string),
	.Close_Path = #load("../assets/icons/close_path.svg", string),
	.Film = #load("../assets/icons/film.svg", string),
	.Folder = #load("../assets/icons/folder.svg", string),
	.Eye_Off = #load("../assets/icons/eye_off.svg", string),
	.Refresh = #load("../assets/icons/refresh.svg", string),
	.Frame_Left = #load("../assets/icons/frame_left.svg", string),
	.Frame_Right = #load("../assets/icons/frame_right.svg", string),
	.Change_Fill = #load("../assets/icons/change_fill.svg", string),
	.Change_Stroke = #load("../assets/icons/change_stroke.svg", string),
}

@(private = "file")
Icon_Atlas :: struct {
	tex: Texture,
	px:  i32, // physical size of one icon
}

@(private = "file")
icon_atlases: map[i32]Icon_Atlas // by logical size

// One icon as white pixels with coverage in alpha, `px` pixels square.
icon_render :: proc(src: string, px: int, allocator := context.allocator) -> []Color {
	pix := make([]Color, px * px, allocator)
	white, _ := strings.replace_all(src, "currentColor", "#ffffff", context.temp_allocator)
	d, ok := svg_parse(white)
	if !ok do return pix
	defer doc_free(d)
	r: Raster
	raster_init(&r, px, px)
	defer raster_free(&r)
	k := f32(px) / max(d.w, 1)
	render_doc_to(d, pix, px, px, Mat{k, 0, 0, k, 0, 0}, &r, false)
	return pix
}

// One row of icons, each `px` pixels square.
icons_build_atlas :: proc(px: int) -> Texture {
	w := len(Icon) * px
	pix := make([]Color, w * px, context.temp_allocator)
	for ic in Icon {
		cell := icon_render(ICON_SVG[ic], px, context.temp_allocator)
		for y in 0 ..< px {
			copy(pix[y * w + int(ic) * px:][:px], cell[y * px:][:px])
		}
	}
	return tex_from_pixels(pix, w, px, .Point)
}

// The atlas for icons drawn `size` logical px wide, rebuilt when the UI scale changes.
icon_atlas :: proc(size: i32) -> (Texture, i32) {
	px := max(i32(math.round(f32(size) * gfx.scale)), 1)
	a := icon_atlases[size]
	if a.px != px || !tex_valid(a.tex) {
		tex_destroy(&a.tex)
		a = Icon_Atlas{icons_build_atlas(int(px)), px}
		icon_atlases[size] = a
	}
	return a.tex, a.px
}
