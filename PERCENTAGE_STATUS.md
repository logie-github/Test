# Percentage status

- **Whole-game estimate: ~21%**, counted against real routine totals in
  `pret/poketcg` (see methodology below) — not the ~56% this file previously
  claimed, which was scoped only to areas already under active work rather
  than the whole cartridge.
- **AI subsystem: 100%.**
- **Card effects (`EffectCommands.lua`, all attack/Power/Trainer effect
  commands): 100%.**
- **Duel engine (setup/turn flow/combat/status/prizes/knockouts): complete
  modulo presentation** — everything still open in
  `tools/tcg/behavior_pending.json` for these files is UI, animation timing,
  or link/serial transport, not untranslated logic.
- **Six scope areas from `PROJECT_SCOPE.md` are untouched (0%):** in-duel
  menus/card-list/animation presentation, the actual link/serial protocol,
  overworld/NPC/story, collection/deck-building/album/trades/Card Pop,
  save/progression beyond duel state, and graphics/audio replacements.
- **ROM extraction (`src/tcg/import/RomExtractor.lua`): unaudited as of this
  entry** — built (723 lines) but not yet checked line-by-line against the
  manifest for correctness/completeness.

## Methodology for the 21% figure

Counted every top-level labeled routine (`Label::` / `Label:` at column 0,
excluding local `.sub` labels) across all 445 `.asm` files in the real
`pret/poketcg` source: 9,333 total. Excluded `src/text` (2,913 — text string
data), `src/data` (1,388 — card/deck/tileset tables), `src/audio` (645 —
music engine), and `src/gfx`/`src/vc` (asset/VC-only) from the denominator,
since those are pulled by the ROM extractor automatically rather than
hand-translated routine-by-routine. That leaves **~3,830 routines** that
plausibly need hand translation into Lua:

| Area | Labels |
|---|---|
| `src/engine/duel` (attacks/Powers/Trainers/AI/core dispatch) | 1,655 |
| `src/home` (shared dispatch/utility, only part duel-specific) | 559 |
| `src/engine/menus` (all in-duel + other menu presentation) | 384 |
| `src/scripts` (overworld NPC/event scripts) | 433 |
| `src/engine/overworld` | 314 |
| `src/engine/link` | 75 |
| misc `src/engine/*.asm` (deck machines, booster packs, save, sgb, etc.) | 174 |
| `src/engine/gfx` | 74 |
| `src/engine/sequences` | 57 |

`tools/tcg/behavior_coverage.json` currently lists **822 translated
labels**. 822 / 3,830 ≈ **21%**.

Caveats: this denominator still mixes real game logic with embedded
presentation routines inside the same files (most of `src/engine/duel`'s
untranslated half is exactly that, matching the pending ledger), and some of
`src/home`'s 559 labels may already be covered generically by Gen1Recomp's
shared host runtime rather than needing per-title work. Treat 21% as a
reasonable estimate, not an audited byte-count — same caveat this file
carried before, just against a real denominator this time.
