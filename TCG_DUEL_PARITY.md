# Pokemon TCG GB1 duel parity reference

Pokopia treats the original Pokemon Trading Card Game GB1 duel flow as the source specification for the embedded card game. Host-RPG UI is only retained where Ditto is explicitly talking to an overworld NPC or using a normal Gen I shop.

## Portrait policy

Character portrait assets are dialogue-only. They are not used for ordinary Pokemon battles, TCG duels, duel setup, Binder pages, deck building, pack opening, draw screens, Prize selection, or transformation previews. Normal Pokemon battles keep their native Gen I front/back battle sprites. TCG duels use the original 64x48 Pokemon TCG card illustrations supplied with the TCG package.

## Main duel scene

- Native canvas: 160x144.
- Opponent Active Pokemon illustration: 64x48 at (96, 8).
- Player Active Pokemon illustration: 64x48 at (0, 40).
- Opponent E / HP labels: tile (1,1) / (1,2).
- Player E / HP labels: tile (9,8) / (9,9).
- Opponent Pokemon / Prize counters begin at tile x=1, y=0.
- Player Pokemon / Prize counters begin at tile x=15, y=11.
- Bottom duel box occupies rows 12-17.
- Command grid follows GB1: HAND / CHECK / RETREAT on the first row, ATTACK / PKMN POWER / DONE on the second.

## Source UI assets

- `assets/tcg/graphics/ui/half_width.png`: original 4-pixel-advance English duel font.
- `assets/tcg/graphics/ui/symbols_font.png`: original 8x8 TCG symbol atlas.
- Energy, status, Pokemon, Prize, HP, cursor and box-frame symbols are drawn from the source atlas.

## Duel setup

The setup sequence now follows `HandleDuelSetup` ordering as closely as the embedded runtime permits:

1. Shuffle each 60-card deck and draw seven cards.
2. Detect opening hands with no Basic Pokemon, return them to the Deck, shuffle and redraw until legal; the source mulligan notices are shown instead of silently retrying.
3. Prompt Ditto to choose a Basic Pokemon for the Arena using the TCG card-list screen.
4. Offer up to five additional Basic Pokemon for the Bench.
5. Show the opponent selecting and placing its opening Pokemon.
6. Deal six face-down Prize cards to each side.
7. Run a TCG-styled coin toss to decide who plays first.
8. Enter the main duel screen and perform the normal beginning-of-turn draw step.

The first turn keeps the source evolution restriction. Energy attachment and retreat flags reset per turn.

## Turn and battle flow

- Beginning-of-turn draw is a dedicated TCG draw-card screen rather than an RPG dialogue line.
- Translated effect hooks use generated per-handler argument metadata rather than a
  single generic attacker argument. The packaged regression sweep executes all 319
  usable attacks against full, unfavorable-coin, and sparse-board states.
- Every printed attack uses its original per-card `ATK_ANIM_*` ID and the corresponding
  ordered `DUEL_ANIM_*` command sequence from the decompilation. The original 2-bit
  grayscale duel sprite sheets are used for the visible animation stages.
- Both player and AI attacks wait for their presentation phase; damage and scripted
  effects are committed on the impact stage rather than before the animation begins.
- HAND, CHECK, RETREAT, play-area/discard lists and PKMN POWER use the GB1 five-visible-row card-list composition.
- ATTACK stays in the lower duel box with Energy requirements and damage in the source layout.
- Between-turn Poison and Sleep resolve for both Active Pokemon; Paralysis clears after the affected Pokemon's controller finishes that controller's turn.
- Knock Outs discard the Pokemon stack and attached Energy, then force Prize-taking and Active promotion before play continues.
- Player Prize-taking uses a dedicated six-position face-down Prize screen instead of a generic numbered list.
- Deck-out, all-Prizes-taken and no-Pokemon-left win conditions are enforced.

## Deck construction

- Duel decks must contain exactly 60 cards.
- The four-copy limit is enforced by printed/display name, matching GB1 rather than by internal card label.
- The six basic Energy cards are unlimited; Double Colorless Energy still obeys the four-copy rule.
- The deck builder refuses to close an invalid non-60-card deck.

## TCG-adjacent screens

Binder set grids, card details, deck lists, pack selection, chained-pack prompts and booster reveals use the TCG half-width font, source borders/cursors, and 160x144-safe measured text. The normal Game Corner purchase counter intentionally remains a Gen I shop because it is an overworld merchant interaction; after a booster is opened, the TCG presentation stays consistent until the pack flow exits.

## Known remaining differences

The embedded duel is source-driven but is not a byte-for-byte emulator of the original ROM. Some highly card-specific target-selection/effect routines still use the supplied translated Lua hooks, Double Colorless attachment is represented by the runtime's typed Energy counts rather than a complete physical attachment object, and the source game's rare simultaneous-KO sudden-death restart flow is not yet fully reproduced. These are engine limitations rather than deliberate UI substitutions.
# Turn and attack ordering

The interactive adapter follows the pret/poketcg core ordering rather than an
immediate damage call. Attack costs occur before Confusion; the attack is
declared before required selections and damage preparation; the complete
`ATK_ANIM_*` command sequence finishes before HP is subtracted; after-damage
effects, knockouts, Prize selection, promotion, and between-turn events then
run in order. Direct and staged execution paths are audited across every
packaged attack.
