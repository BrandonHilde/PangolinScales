#!/bin/sh
# Installs Pangolin Scales for this user, apart from this development folder: builds it here, copies the program to
# ~/.local/opt/pangolin/PangolinScales, and adds it to the application list with its icon.
# The installed copy keeps its own settings, workspaces and macros, next to the program, so it never shares them with
# this folder's build. Run this again to update it (it can be running). ./install.sh --uninstall takes away the program,
# its menu entry and its icons, and leaves its settings, workspaces and macros in that folder.
set -e
cd "$(dirname "$0")"
APP=PangolinScales
NAME="Pangolin Scales"
COMMENT="Edit SVG drawings and fonts"
CATEGORIES="Graphics;2DGraphics;VectorGraphics;"
dest="${PANGOLIN_PREFIX:-$HOME/.local/opt/pangolin}/$APP"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data/applications"
icons="$data/icons/hicolor"
SIZES="16 24 32 48 64 128 256"

# the desktop picks up a new or removed entry and icon sooner with these (they're optional)
refresh() {
	update-desktop-database -q "$apps" 2>/dev/null || true
	gtk-update-icon-cache -q -t -f "$icons" 2>/dev/null || true
}

if [ "$1" = "--uninstall" ]; then
	rm -f "$dest/$APP" "$apps/$APP.desktop"
	for s in $SIZES; do rm -f "$icons/${s}x${s}/apps/$APP.png"; done
	refresh
	echo "Uninstalled $NAME. Its settings, workspaces and macros are still in $dest"
	exit 0
fi

sh ./build.sh
mkdir -p "$dest"
# copied beside it, then renamed over it: that works even while the installed copy is running
cp "$APP" "$dest/.$APP.new"
mv -f "$dest/.$APP.new" "$dest/$APP"
for s in $SIZES; do
	mkdir -p "$icons/${s}x${s}/apps"
	cp "assets/icon/icon_$s.png" "$icons/${s}x${s}/apps/$APP.png"
done
# the window's app id is the program's name (SDL's default), so the entry is named after it: the dock then shows
# the open window with this icon
mkdir -p "$apps"
cat > "$apps/$APP.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=$NAME
Comment=$COMMENT
Exec="$dest/$APP"
Icon=$APP
Terminal=false
Categories=$CATEGORIES
StartupWMClass=$APP
ENTRY
refresh
echo "Installed $NAME in $dest. It's in the application list."
