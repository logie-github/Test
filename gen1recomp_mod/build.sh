#!/usr/bin/env bash
# Materializes gen1recomp_mod/pokemon_tcg into a ready-to-drop-in
# bryanthaboi/gen1recomp mods/pokemon_tcg directory.
#
# Copies src/tcg/ from this repo (the canonical source of truth for the
# duel engine) into the mod, rewrites its internal require("src.tcg.*")
# calls to require("mods.pokemon_tcg.src.tcg.*") so they resolve inside a
# mod's own directory, drops the two files that don't apply in mod context
# (Game.lua, Data.lua -- the mod's own main.lua replaces both), and patches
# RomExtractor.lua so it never references the shared data/generated or
# assets/generated cache paths (required by this engine's mod legal-posture
# lint, MK301 -- a mod may never point at or shadow the player's ROM-derived
# cache). None of this touches the canonical src/tcg/ tree; it only builds
# a derived copy under gen1recomp_mod/pokemon_tcg/src/tcg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_DIR="$ROOT/gen1recomp_mod/pokemon_tcg"
SRC_OUT="$MOD_DIR/src/tcg"

rm -rf "$SRC_OUT"
mkdir -p "$MOD_DIR/src"
cp -r "$ROOT/src/tcg" "$SRC_OUT"

rm -f "$SRC_OUT/Game.lua" "$SRC_OUT/Data.lua" "$SRC_OUT/states/TranslationIncomplete.lua"

# Unused anywhere in src/tcg and references the shared ROM-derived cache
# path directly (forbidden by mod legal-posture lint, MK301).
rm -f "$SRC_OUT/duel/Constants.lua"

grep -rlZ 'require("src\.tcg\.' "$SRC_OUT" 2>/dev/null \
  | xargs -0 -r sed -i 's/require("src\.tcg\./require("mods.pokemon_tcg.src.tcg./g'

# Never reference the shared ROM-derived cache (mod legal-posture, MK301):
# write()/save() become no-ops (this mod keeps everything in memory for one
# session and never persists it), and the card-gfx path field -- which
# would otherwise be a phantom "assets/generated/..." string -- is dropped
# in favor of returning the decoded in-memory image directly.
python3 - "$SRC_OUT/import/RomExtractor.lua" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()

src = src.replace(
    'local Rom = require("src.import.Rom")\n'
    'local LuaWriter = require("src.import.LuaWriter")\n'
    'local ImageWriter = require("src.import.ImageWriter")\n',
    'local Rom = require("src.import.Rom")\n'
    'local ImageWriter = require("src.import.ImageWriter")\n',
)

src = src.replace(
    'function RomExtractor:write(name, value)\n'
    '  LuaWriter.write("data/generated/" .. name .. ".lua", value)\n'
    'end\n'
    '\n'
    'function RomExtractor:save(image, relative)\n'
    '  ImageWriter.save(image, "assets/generated/" .. relative)\n'
    'end\n',
    '-- No-ops in the pokemon_tcg mod: extraction results are consumed\n'
    '-- directly from each extract*() method\'s return value and never\n'
    '-- persisted to the shared ROM-derived cache -- the ROM is read, used\n'
    '-- to build this turn\'s duel state, and never written back out.\n'
    'function RomExtractor:write(name, value) end\n'
    '\n'
    'function RomExtractor:save(image, relative) end\n',
)

src = src.replace(
    '  local image = ImageWriter.decode2bpp(raw, gfxSpec.width, gfxSpec.height)\n'
    '  local path = ("tcg/cards/%03d.png"):format(id)\n'
    '  self:save(image, path)\n'
    '  return {\n'
    '    sourceLabel = gfxLabel,\n'
    '    path = "assets/generated/" .. path,\n',
    '  local image = ImageWriter.decode2bpp(raw, gfxSpec.width, gfxSpec.height)\n'
    '  -- Not persisted to the shared ROM-derived cache: the pokemon_tcg mod\n'
    '  -- keeps the decoded image in memory for this session only.\n'
    '  return {\n'
    '    sourceLabel = gfxLabel,\n'
    '    image = image,\n',
)

open(path, "w", encoding="utf-8").write(src)
PYEOF

echo "materialized $SRC_OUT"
echo "next: copy $MOD_DIR into your local gen1recomp checkout's mods/ directory"
