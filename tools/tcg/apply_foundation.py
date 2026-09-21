#!/usr/bin/env python3
"""Apply the TCG cartridge-profile plumbing to the inspected Gen1Recomp dev tree.

All edits use exact anchors and abort if upstream has moved. This is safer than
silently applying fuzzy edits to a changing engine.
"""
from __future__ import annotations
import argparse
import pathlib
import shutil
import sys

TCG_BLOCK = '''  tcg = {
    id = "tcg",
    label = "TCG",
    displayName = "Pokemon Trading Card Game",
    launcherName = "TCG",
    sha1 = "0f8670a583255cff3e5b7ca71b5d7454d928fc48",
    manifest = "tools/tcg_rom_manifest.json",
    cachePrefix = "tcg/",
    cacheFormat = "tcg-rom-cache-v5:",
    saveSuffix = "_tcg",
    romSize = 64 * 0x4000,
    extractor = "src.tcg.import.RomExtractor",
    gameModule = "src.tcg.Game",
    requiredFiles = {
      "data/generated/tcg_meta.lua",
      "data/generated/tcg_memory.lua",
      "data/generated/tcg_constants.lua",
      "data/generated/tcg_core.lua",
      "data/generated/tcg_effects.lua",
      "data/generated/tcg_text.lua",
      "data/generated/tcg_cards.lua",
      "data/generated/tcg_decks.lua",
      "assets/generated/tcg/cards/001.png",
    },
    defaultRomName = "poketcg.gbc",
  },
'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_game_version(root: pathlib.Path) -> None:
    p = root / "src/core/GameVersion.lua"
    s = p.read_text(encoding="utf-8")
    if 'id = "tcg"' not in s:
        anchor = '}\n\n-- Launcher column order.\n'
        s = replace_once(s, anchor, TCG_BLOCK + '}\n\n-- Launcher column order.\n', str(p))
    else:
        # Upgrade known earlier TCG profile revisions in place. These are exact
        # blocks from the previously shipped checkpoints; an unknown local edit
        # is left alone and then rejected below if the current core file is absent.
        new_required = '''    requiredFiles = {
      "data/generated/tcg_meta.lua",
      "data/generated/tcg_memory.lua",
      "data/generated/tcg_constants.lua",
      "data/generated/tcg_core.lua",
      "data/generated/tcg_effects.lua",
      "data/generated/tcg_text.lua",
      "data/generated/tcg_cards.lua",
      "data/generated/tcg_decks.lua",
      "assets/generated/tcg/cards/001.png",
    },'''
        prior_required_blocks = [
            '    requiredFiles = { "data/generated/tcg_meta.lua" },',
            '''    requiredFiles = {
      "data/generated/tcg_meta.lua",
      "data/generated/tcg_constants.lua",
      "data/generated/tcg_text.lua",
      "data/generated/tcg_cards.lua",
      "data/generated/tcg_decks.lua",
      "assets/generated/tcg/cards/001.png",
    },''',
            '''    requiredFiles = {
      "data/generated/tcg_meta.lua",
      "data/generated/tcg_memory.lua",
      "data/generated/tcg_constants.lua",
      "data/generated/tcg_text.lua",
      "data/generated/tcg_cards.lua",
      "data/generated/tcg_decks.lua",
      "assets/generated/tcg/cards/001.png",
    },''',
        ]
        if '"data/generated/tcg_core.lua"' not in s:
            matches = [block for block in prior_required_blocks if block in s]
            if len(matches) != 1:
                raise SystemExit(f"{p}: cannot identify prior TCG requiredFiles block")
            s = replace_once(s, matches[0], new_required, str(p))
        elif '"data/generated/tcg_effects.lua"' not in s:
            s = replace_once(
                s,
                '      "data/generated/tcg_core.lua",\n',
                '      "data/generated/tcg_core.lua",\n      "data/generated/tcg_effects.lua",\n',
                str(p),
            )
    if 'cacheFormat = "tcg-rom-cache-v5:"' not in s:
        if 'cacheFormat = "tcg-rom-cache-v3:"' in s:
            s = replace_once(
                s,
                'cacheFormat = "tcg-rom-cache-v3:"',
                'cacheFormat = "tcg-rom-cache-v5:"',
                str(p),
            )
        else:
            tcg_anchor = '    cachePrefix = "tcg/",\n'
            if tcg_anchor in s:
                s = replace_once(s, tcg_anchor,
                    tcg_anchor + '    cacheFormat = "tcg-rom-cache-v5:",\n', str(p))
            else:
                # Earliest checkpoint fixtures predate cachePrefix/cacheFormat.
                id_anchor = '    id = "tcg",\n'
                s = replace_once(s, id_anchor,
                    id_anchor + '    cacheFormat = "tcg-rom-cache-v5:",\n', str(p))

    s = replace_once(
        s,
        'GameVersion.ORDER = { "red", "blue", "yellow" }',
        'GameVersion.ORDER = { "red", "blue", "yellow", "tcg" }',
        str(p),
    ) if '"tcg" }' not in s.split('GameVersion.ORDER =',1)[1].split('\n',1)[0] else s
    p.write_text(s, encoding="utf-8")


def patch_main(root: pathlib.Path) -> None:
    p = root / "main.lua"
    s = p.read_text(encoding="utf-8")
    old = '  Game = require("src.core.Game")\n  Game:load()'
    new = '  local info = GameVersion.info()\n  Game = require(info.gameModule or "src.core.Game")\n  Game:load()'
    if new not in s:
        s = replace_once(s, old, new, str(p))
    p.write_text(s, encoding="utf-8")


def patch_importer(root: pathlib.Path) -> None:
    p = root / "src/import/RomImporter.lua"
    s = p.read_text(encoding="utf-8")

    old_marker = '''local function markerFor(version)
  return CACHE_FORMAT .. GameVersion.info(version).sha1
end'''
    new_marker = '''local function markerFor(version)
  local info = GameVersion.info(version)
  return (info.cacheFormat or CACHE_FORMAT) .. info.sha1
end'''
    if new_marker not in s:
        s = replace_once(s, old_marker, new_marker, str(p))

    if "local DEFAULT_REQUIRED_FILES = {" not in s:
        s = replace_once(s, "local REQUIRED_FILES = {", "local DEFAULT_REQUIRED_FILES = {", str(p))
        anchor = '}\n\n-- "Split-screen ROM selector" first-run palette'
        helper = '''}\n\nlocal function requiredFiles(version)\n  local info = GameVersion.info(version)\n  return info.requiredFiles or DEFAULT_REQUIRED_FILES\nend\n\n-- "Split-screen ROM selector" first-run palette'''
        s = replace_once(s, anchor, helper, str(p))
        s = replace_once(s,
            "for _, path in ipairs(REQUIRED_FILES) do",
            "for _, path in ipairs(requiredFiles(version)) do",
            str(p))
        s = replace_once(s,
            "love.filesystem.getRealDirectory(REQUIRED_FILES[1])",
            "love.filesystem.getRealDirectory(DEFAULT_REQUIRED_FILES[1])",
            str(p))
        s = replace_once(s,
            "saveDirHas(prefix .. REQUIRED_FILES[1])",
            "saveDirHas(prefix .. requiredFiles(version)[1])",
            str(p))

    old_name = '''    self.romName[version] = "pokemon_" .. info.id\n      .. (info.id == "yellow" and ".gbc" or ".gb")'''
    new_name = '''    self.romName[version] = info.defaultRomName or ("pokemon_" .. info.id\n      .. (info.id == "yellow" and ".gbc" or ".gb"))'''
    if new_name not in s:
        s = replace_once(s, old_name, new_name, str(p))

    old_size = '''  if #data ~= 1024 * 1024 then\n    self:setError(("Expected a 1 MiB Game Boy ROM; this file is %.2f MiB.")\n      :format(#data / 1024 / 1024))\n    return\n  end\n  local actualHash = sha1(data)'''
    new_size = '''  local actualHash = sha1(data)'''
    if old_size in s:
        s = replace_once(s, old_size, new_size, str(p))

    old_unsupported = '''    self:setError(("Unsupported ROM (SHA-1 %s). Use an unmodified US Pokemon "\n      .. "Red, Blue, or Yellow ROM."):format(actualHash))'''
    new_unsupported = '''    self:setError(("Unsupported ROM (SHA-1 %s). Use an exact supported ROM.")\n      :format(actualHash))'''
    if old_unsupported in s:
        s = replace_once(s, old_unsupported, new_unsupported, str(p))

    anchor = '  local info = GameVersion.info(version)\n\n  -- Bring the launcher'
    replacement = '''  local info = GameVersion.info(version)\n  local expectedSize = info.romSize or (1024 * 1024)\n  if #data ~= expectedSize then\n    self:setError(("Expected a %d-byte %s ROM; got %d bytes.")\n      :format(expectedSize, info.displayName, #data))\n    return\n  end\n\n  -- Bring the launcher'''
    if "local expectedSize = info.romSize" not in s:
        s = replace_once(s, anchor, replacement, str(p))

    if 'require(info.extractor or "src.import.RomExtractor")' not in s:
        s = replace_once(s,
            'local RomExtractor = require("src.import.RomExtractor")',
            'local RomExtractor = require(info.extractor or "src.import.RomExtractor")',
            str(p))

    p.write_text(s, encoding="utf-8")


def copy_tree(package_root: pathlib.Path, engine_root: pathlib.Path) -> None:
    for rel in ["src/tcg", "tools/tcg"]:
        src = package_root / rel
        dst = engine_root / rel
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("engine_root", type=pathlib.Path)
    args = ap.parse_args()
    root = args.engine_root.resolve()
    if not (root / "src/core/GameVersion.lua").exists():
        raise SystemExit("not a Gen1Recomp source tree")
    package_root = pathlib.Path(__file__).resolve().parents[2]
    patch_game_version(root)
    patch_main(root)
    patch_importer(root)
    copy_tree(package_root, root)
    print("TCG foundation applied. Generate tools/tcg_rom_manifest.json next.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
