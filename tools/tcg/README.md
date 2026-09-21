# TCG decomp tooling

`build_manifest.py` consumes a local `pret/poketcg` checkout plus the matching
RGBDS `poketcg.sym`. It writes the ROM-import manifest used by the Lua
extractor and creates/updates the translation ledger keyed by canonical source
file SHA-1.

The manifest currently derives:

- ROM hash/size and RGBDS symbols;
- link layout;
- WRAM/HRAM/SRAM symbol maps, preserving aliases/UNION addresses;
- `EQUS LOW/HIGH(symbol)` duel-variable aliases resolved from RGBDS symbols;
- card/deck/text/duel constants;
- card and deck pointer table ordering;
- exact pointed deck `card_item` sequences and terminator form;
- text pointer labels and charmap data;
- card source-PNG dimensions;
- card rgbgfx storage flags from the root Makefile;
- ROM-backed core tables/templates addressed by decomp/RGBDS symbols;
- source-ordered effect-command lists (`EFFECTCMDTYPE_*` + function labels), later cross-checked byte-for-byte/pointer-for-pointer against the ROM by `RomExtractor.lua`.

Canonical `src/` inputs are fingerprinted for coverage, including source PNGs
and binary data. Reproducible build products (`.o`, `.1bpp`, `.2bpp`, `.pal`,
`.lz`, `.bgmap`, `.sym`, `.map`) are excluded.

Do not put ROM offsets, replacement card data, normalized deck data, or guessed
graphics layouts into Lua. If the decomp changes, regenerate the manifest; if
an input source changes, coverage returns to failing until its mapping is
reviewed.

`behavior_coverage.json` records the labels already translated in the native Lua layer. It is supplemental to the file-level 100% shipping ledger; it never upgrades a partially translated source file to shipping-complete by itself.


Current manifest schema: **5**. The runtime cache profile is `tcg-rom-cache-v5:` and includes `data/generated/tcg_effects.lua` plus AI constants from `deck_ai_constants.asm`; older v4 caches are deliberately re-extracted.
