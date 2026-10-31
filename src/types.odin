package pangolin

IVec :: [2]int
Vec2 :: [2]f32

// Integer rectangle in logical UI pixels.
Rect :: struct {
	x, y, w, h: i32,
}

// Small fixed-capacity string (names, text inputs). Safe to copy by value.
Name :: struct {
	b: [128]u8,
	n: int,
}

name_set :: proc(nm: ^Name, s: string) {
	n := min(len(s), len(nm.b))
	copy(nm.b[:n], s)
	nm.n = n
}

name_str :: proc(nm: ^Name) -> string {
	return string(nm.b[:nm.n])
}

make_name :: proc(s: string) -> Name {
	r: Name
	name_set(&r, s)
	return r
}
