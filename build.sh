#!/bin/sh
# Builds ./PangolinScales (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the fonts are embedded)
set -e
cd "$(dirname "$0")"
# OdinUI is a git submodule in libs/odinui: fetch it on the first build after a plain clone
if [ ! -d libs/odinui/odinui ]; then
	git submodule update --init --recursive
fi
odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui
echo "Built PangolinScales"
