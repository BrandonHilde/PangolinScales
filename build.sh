#!/bin/sh
# Builds ./PangolinScales (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the fonts are embedded)
set -e
cd "$(dirname "$0")"
# OdinUI and the shared Pangolin code are git submodules in libs: fetch them on the first build after a plain clone
if [ ! -d libs/odinui/odinui ] || [ ! -d libs/shared/src ]; then
	git submodule update --init --recursive
fi
# Odin compiles one folder as one package, so the shared code is copied in
sh libs/shared/sync.sh
odin build src -out:PangolinScales -o:speed -collection:odinui=libs/odinui
echo "Built PangolinScales"
