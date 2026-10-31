#!/bin/sh
# Builds ./PangolinScales (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the fonts are embedded)
set -e
cd "$(dirname "$0")"
odin build src -out:PangolinScales -o:speed
echo "Built PangolinScales"
