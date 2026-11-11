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
# A pull doesn't move the submodules: say so when libs/shared isn't the version this app's code expects
case "$(git submodule status libs/shared 2>/dev/null)" in
+*) echo "Note: libs/shared is not the version this app's code expects, so the build may fail. Run ./update.sh to bring both up to date, or 'git submodule update' to match this code." >&2 ;;
esac
# Odin compiles one folder as one package, so the shared code is copied in
sh libs/shared/sync.sh
# SDL3 is linked from the system (its development package) instead of a DLL next to the executable
if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists sdl3; then
	echo "Warning: SDL3 was not found, so linking will likely fail. Install its development package" >&2
	echo "(Fedora: SDL3-devel, Debian/Ubuntu: libsdl3-dev, Arch: sdl3)." >&2
fi
# On Linux Odin ships stb as C source: build its libraries once, the first time they are missing
# (macOS gets them ready-built, in vendor/stb/lib/darwin)
stb="$(odin root)"
stb="${stb%/}/vendor/stb"
for lib in stb_image stb_image_write stb_image_resize stb_truetype stb_rect_pack; do
	[ "$(uname)" = Darwin ] && break
	if [ ! -f "$stb/lib/$lib.a" ]; then
		echo "Building Odin's stb libraries in $stb/lib"
		(cd "$stb/src" && sh build_stb.sh) || {
			echo "Could not build them; the Odin folder may need write access (try: cd $stb/src && sudo sh build_stb.sh)." >&2
			exit 1
		}
		break
	fi
done
# The commit goes into About and --version. (Odin links with the runpath $ORIGIN already, so a release folder's
# bundled libSDL3.so.0, next to the program, is found on systems that have no SDL3 of their own.)
set -- -out:PangolinScales -o:speed -collection:odinui=libs/odinui
commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
if [ -n "$commit" ]; then set -- "$@" "-define:APP_COMMIT=$commit"; fi
# SDL3 links from the system: on macOS from SDL3_PREFIX (the release workflow's own build) or Homebrew,
# whose lib folder the linker doesn't search by itself. A macOS build also looks for libraries in the app's
# Contents/Frameworks, where the release puts SDL3 (libs/shared/release/package.sh).
link=""
if [ -n "$SDL3_PREFIX" ]; then
	link="-L$SDL3_PREFIX/lib"
elif [ "$(uname)" = Darwin ] && command -v brew >/dev/null 2>&1; then
	link="-L$(brew --prefix)/lib"
fi
if [ "$(uname)" = Darwin ]; then
	link="$link -Wl,-rpath,@executable_path/../Frameworks"
fi
if [ -n "$link" ]; then set -- "$@" "-extra-linker-flags:$link"; fi
odin build src "$@"
echo "Built PangolinScales"
