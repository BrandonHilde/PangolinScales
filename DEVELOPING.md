# Developing Pangolin Scales

How to build, run, test and change it. For using it, see the [README](README.md) and the [guide](GUIDE.md).

## Building and installing from source

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows. [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui) and
the code the Pangolin tools share ([PangolinShared](https://github.com/BrandonHilde/PangolinShared)) are git submodules in
`libs/odinui` and `libs/shared`: clone with `git clone --recursive`, or let the build scripts fetch them on the first build
(`git submodule update --init`). Odin compiles one folder as one package, so the build scripts first copy the shared code into
`src` as `shared_*.odin` (ignored by git: edit it in `libs/shared`). To build by hand, run that step yourself:
`sh libs/shared/sync.sh` (or `libs\shared\sync.bat`), then `odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui`.
To update to the newest version, run `update.bat` (Windows) or `./update.sh`: it pulls the latest commits and moves the
submodules to the versions they expect (a plain `git pull` leaves the submodules where they were, and the build then
fails). `build.bat` / `./build.sh` on their own build whatever is there now.
On Linux, `./install.sh` builds the program and installs it for your account: in `~/.local/opt/pangolin/PangolinScales`, with
its own settings, workspaces and macros (apart from this folder's build), and in the application list with its icon.
Run it again to update, or `./install.sh --uninstall` to remove it. To install a build made elsewhere (for another
account on the computer, or without Odin), put `install.sh`, the `PangolinScales` program and `assets/icon` in one folder and
run `sh install.sh --no-build` there.
Drag `.svg`, `.ttf` or `.otf` files onto the window to open them.
`PangolinScales --selftest` runs the headless test suite (on Windows use `PangolinScales-console.exe`, since the GUI build has no console).

## Developer flags
`--selftest` (tests), `--demo` (sample drawing with a few frames), `--shot file.png` (screenshot after a few frames), `--shot-frame N` (which frame), `--size WxH`, `--scale N` (UI scale for this run, in percent),
`--render in.svg out.png [scale]` (headless SVG to PNG), `--icon-sheet out.png` (every icon at several sizes),
`--clicks "frame:x,y;..."` (left clicks at window pixels on those frames, `frame:x,y,r` for a right click, for checking the interface with `--shot`),
`--drag "frame:x0,y0,x1,y1;..."` (left drags at window pixels over 8 frames),
`--hover "frame:x,y"` (rests the pointer there from that frame on, for checking tooltips with `--shot` and a later `--shot-frame`),
`--menu N` (opens menu N).

## Source layout
`geom`, `path`, `fit`, `boolean`, `pathops` (geometry and path operations) - `raster`, `stroke`, `render` (anti-aliased scanline
renderer) - `doc`, `style`, `commands`, `frames` (document model, frames, timeline, export) - `tools`, `nodeedit`, `texttool`,
`shortcuts` (interaction) - `svg_read`, `svg_write`, `xml` (SVG files) - `text` (fonts for text objects) - `ttf`, `font_doc`,
`font_ui` (font editing) - `app`, `panels`, `toolgroups`, `switches`, `workspaces`, `files_hooks` (window layout, panels, tool groups,
workspaces, what the file browser does here) - `icons`, `brand`, `prefs`, `fileio` - `libs/shared` (copied in as `shared_*.odin`): the
OdinUI host, widgets, `gfx`, pen input, the file browser, tags and playback, image decoders and the GIF encoder, shared with the other
Pangolin tools.

## Releases
A tag such as `v0.9.0-beta` (matching `APP_VERSION` in `src/brand.odin`) runs `.github/workflows/release.yml`: it builds Windows, macOS and Linux bundles, runs `--selftest` inside each, and makes a draft GitHub release to try before publishing. Actions > Release > Run workflow builds the bundles without releasing. The workflow and the packaging script (`libs/shared/release/package.sh`) live in [PangolinShared](https://github.com/BrandonHilde/PangolinShared).

## License
BSD 3-Clause. See [LICENSE](LICENSE).
