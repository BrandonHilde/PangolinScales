package pangolin


APP_NAME :: "Pangolin Scales"
APP_TAGLINE :: "Curves, scale by scale."

LOGO_SIZE :: 16

// Pixel-art pangolin facing left, holding a paintbrush with a wet tip.
// Characters map to colors in `logo_color`.
LOGO_ART := [LOGO_SIZE]string {
	"...........n....",
	"..........nn....",
	".........kk.....",
	"......oooook....",
	"....ooddbbkdoo..",
	"...oddbbddkbddo.",
	"..oddbbddbkddbbo",
	"..obbddbbdkbbddo",
	".oobddbbddkbddbo",
	"ossoobbddbkddbo.",
	"osswoddbbdldbo..",
	".osssllooolooo..",
	"..ooollo.ol.ol..",
	"....ol.o.ol.ol..",
	"....oo.o.oo.oo..",
	"..nn.nn.nn.nn...",
}

logo_color :: proc(ch: u8) -> (c: Color, ok: bool) {
	switch ch {
	case 'o':
		return Color{46, 32, 24, 255}, true
	case 'd':
		return Color{139, 94, 60, 255}, true
	case 'b':
		return Color{192, 140, 86, 255}, true
	case 'l':
		return Color{224, 185, 136, 255}, true
	case 's':
		return Color{240, 217, 181, 255}, true
	case 'w':
		return Color{255, 255, 255, 255}, true
	case 'k':
		return Color{120, 72, 40, 255}, true // brush handle
	case 'r':
		return Color{214, 64, 52, 255}, true
	case 'y':
		return Color{240, 196, 60, 255}, true
	case 'g':
		return Color{70, 150, 90, 255}, true
	case 'n':
		return Color{60, 160, 255, 255}, true
	}
	return {}, false
}

logo_tex: Texture

logo_pixels :: proc() -> []Color {
	pix := make([]Color, LOGO_SIZE * LOGO_SIZE, context.temp_allocator)
	for row, y in LOGO_ART {
		for x in 0 ..< len(row) {
			if c, ok := logo_color(row[x]); ok {
				pix[y * LOGO_SIZE + x] = c
			}
		}
	}
	return pix
}

// Window icon and the texture used by the About dialog.
brand_init :: proc() {
	pix := logo_pixels()
	logo_tex = tex_from_pixels(pix, LOGO_SIZE, LOGO_SIZE, .Point)
	const_scale :: 4
	big := make([]Color, LOGO_SIZE * const_scale * LOGO_SIZE * const_scale, context.temp_allocator)
	for y in 0 ..< LOGO_SIZE * const_scale {
		for x in 0 ..< LOGO_SIZE * const_scale {
			big[y * LOGO_SIZE * const_scale + x] = pix[(y / const_scale) * LOGO_SIZE + x / const_scale]
		}
	}
	gfx_set_icon(big, LOGO_SIZE * const_scale, LOGO_SIZE * const_scale)
}

// Draws the logo at an integer scale.
logo_draw :: proc(x, y, scale: i32) {
	draw_tex(logo_tex, {0, 0, LOGO_SIZE, LOGO_SIZE}, {f32(x), f32(y), f32(LOGO_SIZE * scale), f32(LOGO_SIZE * scale)})
}
