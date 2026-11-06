package pangolin

APP_NAME :: "Pangolin Scales"
APP_TAGLINE :: "Curves, scale by scale."

LOGO_SIZE :: 16

// The app icon, as drawn for each size: fewer and bigger scales as it gets smaller, and pixel art at 32 and below,
// where smooth shapes would blur. The source is in PangolinShared/art/pangolin_icons. assets/icon/app.ico holds the
// same drawings, for the Windows executable.
@(private = "file")
Icon_Size :: struct {
	px:  i32,
	png: []u8,
}

@(private = "file")
ICON_SIZES := [?]Icon_Size {
	{16, #load("../assets/icon/icon_16.png")},
	{24, #load("../assets/icon/icon_24.png")},
	{32, #load("../assets/icon/icon_32.png")},
	{48, #load("../assets/icon/icon_48.png")},
	{64, #load("../assets/icon/icon_64.png")},
	{128, #load("../assets/icon/icon_128.png")},
	{256, #load("../assets/icon/icon_256.png")},
}

@(private = "file")
logo_cache: map[i32]Texture // by physical size

// Window icon.
brand_init :: proc() {
	pix, w, h, ok := decode_common_image(ICON_SIZES[len(ICON_SIZES) - 1].png)
	if !ok do return
	defer delete(pix)
	gfx_set_icon(pix, w, h)
}

// The drawing for this size, or the next one up to be reduced to it.
@(private = "file")
icon_for :: proc(px: i32) -> Icon_Size {
	for s in ICON_SIZES {
		if s.px >= px do return s
	}
	return ICON_SIZES[len(ICON_SIZES) - 1]
}

// Draws the logo LOGO_SIZE * scale logical px wide, sharp at the window's physical resolution.
logo_draw :: proc(x, y, scale: i32) {
	size := LOGO_SIZE * scale
	px := phys_size(size)
	t, cached := logo_cache[px]
	if !cached {
		s := icon_for(px)
		pix, w, h, ok := decode_common_image(s.png)
		if !ok do return
		defer delete(pix)
		// an exact size stays pixel for pixel; a larger drawing is reduced smoothly
		t = tex_from_pixels(pix, w, h, s.px == px ? .Point : .Linear)
		logo_cache[px] = t
	}
	if t.w == px {
		draw_tex_exact(t, {0, 0, f32(t.w), f32(t.h)}, f32(x), f32(y))
	} else {
		draw_tex(t, {0, 0, f32(t.w), f32(t.h)}, {snap(f32(x)), snap(f32(y)), f32(size), f32(size)})
	}
}

// True if every size is a readable image of that size, with a see-through corner and a solid middle.
icons_ok :: proc() -> bool {
	for s in ICON_SIZES {
		pix, w, h, ok := decode_common_image(s.png)
		if !ok do return false
		defer delete(pix)
		if w != int(s.px) || h != int(s.px) do return false
		if pix[0].a != 0 || pix[(h / 2) * w + w / 2].a != 255 do return false
	}
	return true
}
