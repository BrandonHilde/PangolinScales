#!/bin/sh
# Builds ./PangolinScales (requires the Odin compiler on PATH and SDL3 installed; stb comes from Odin's vendor: collection, the fonts are embedded)
# Linux needs one executable: run from a terminal it also prints the --selftest output, so there is no -console build.
# The window icon is embedded in the program; assets/icon/app.res is only the Windows executable's icon.
set -e
cd "$(dirname "$0")"
# OdinUI and the shared Pangolin code are git submodules in libs: fetch them on the first build after a plain clone
if [ ! -d libs/odinui/odinui ] || [ ! -d libs/shared/src ]; then
	git submodule update --init --recursive
fi
# Odin compiles one folder as one package, so the shared code is copied in
sh libs/shared/sync.sh
# SDL3 is linked from the system (its development package) instead of a DLL next to the executable
if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists sdl3; then
	echo "Warning: SDL3 was not found, so linking will likely fail. Install its development package" >&2
	echo "(Fedora: SDL3-devel, Debian/Ubuntu: libsdl3-dev, Arch: sdl3)." >&2
fi
# On Linux Odin ships stb as C source: build its libraries once, the first time they are missing
stb="$(odin root)"
stb="${stb%/}/vendor/stb"
for lib in stb_image stb_image_write stb_image_resize stb_truetype stb_rect_pack; do
	if [ ! -f "$stb/lib/$lib.a" ]; then
		echo "Building Odin's stb libraries in $stb/lib"
		(cd "$stb/src" && sh build_stb.sh) || {
			echo "Could not build them; the Odin folder may need write access (try: cd $stb/src && sudo sh build_stb.sh)." >&2
			exit 1
		}
		break
	fi
done
odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui
echo "Built PangolinScales"
