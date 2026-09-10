# Celadon Game Corner Pokemon TCG integration

Version 1.0.341 integrates the TCG prototype into an inventory-first booster and Binder flow using the supplied `pokemon_tcg_gbc_complete.zip` data and artwork.

## Booster items

The Game Corner attendant uses the standard Gen I storefront list, quantity selector, cursor, and YES/NO confirmation to sell four ordinary Bag items: `COLOSSEUM PACK`, `EVOLUTION PACK`, `MYSTERY PACK`, and `LABORATORY PACK`. They stack in INVENTORY and opening one consumes exactly one item. The first 10 packs acquired from the attendant are free across all four expansions; later packs cost 10 Coins each.
The attendant is positioned at the original Gen I northwest service-clerk cell behind the Game Corner counter; interaction reaches across the counter from the customer side.

Each opened pack contains exactly 10 cards using `booster_packs_data.lua` / `raw_source_reference/booster_pack_odds.asm`: Colosseum and Evolution use 1 Energy + 5 Common + 3 Uncommon + 1 Rare, while Mystery and Laboratory use 6 Common + 3 Uncommon + 1 Rare. Generic purchases use the supplied neutral/mostly-neutral variant for that expansion, including the original weighted type pull and per-pull chance reduction (integer original average, clamp to 1). Card labels resolve against the complete 228-card database.

## Opening presentation

Using a pack from INVENTORY closes the Bag, shows one of that expansion's supplied native booster images, tears the wrapper across the top tenth and pulls the torn strip away, then reveals all 10 pulled cards one at a time using the supplied 64x48 card artwork. The reveal includes card name, expansion, rarity, type and Pokemon stats where applicable.

## BINDER unlock and menus

The first successful booster opening permanently unlocks `BINDER`. On later START-menu opens, `BINDER` is inserted directly below the player-name/DITTO row, followed by `DECK`. `DECK` opens the live deck builder from the START menu.

BINDER lists all six sets from `expansions.lua`: Colosseum, Evolution, Mystery, Laboratory, Promotional and Energy. Selecting a set opens a 2x2 card grid in the source expansion order. Owned cards show their supplied artwork and copy count; unowned cards remain hidden. Selecting an owned card opens paged details with all available metadata, attack costs/damage/effect descriptions, or Trainer/Energy card description text without truncating long descriptions.

## Existing TCG systems

The counter's deck builder and AI duel from the earlier integration remain available and now use the complete imported TCG database/collection. TCG state is stored under `save.modData.pokopia_log568.tcg`. Older prototype pack counts migrate additively into the physical Bag when space permits.

## Imported source material

The mod retains the relevant supplied TCG source tables verbatim under `assets/tcg/data/` and the native source artwork under `assets/tcg/graphics/`. Runtime tables in `main.lua` were generated directly from those supplied Lua tables so the mod does not depend on unrestricted runtime file execution.

## Bag USE compatibility
Each booster declares `effect="TCG_OPEN_PACK"`. The mod registers the `item.use` interception during initial mod loading and also repairs the merged runtime `game.data.item_effects` entry before Bag input is dispatched on API-2 Gen 1 builds where custom item-effect content is not merged correctly. Boosters therefore bypass the vanilla OAK rejection, are usable from the Bag regardless of map, consume exactly one item, and launch the same opening sequence.

## Starter decks and booster scene mapping (1.0.331)

The attendant offers the three supplied starter recipes (Charmander & Friends, Squirtle & Friends, Bulbasaur & Friends). One is free; remaining starter recipes cost 100 Game Corner Coins. The active deck can load any owned starter recipe from DECK BUILDER.

The source booster PNGs are 96-tile sheets. Pokopia reconstructs the 8x12 DMG booster scene and overlays the 32-tile booster OAM graphic at the scene origin. The supplied `booster_scene_sprite.lua` table is retained verbatim; runtime image assembly follows the engine OAM writer's coordinate consumption order (stored Y first, X second), producing the intended 64x32 logo instead of treating the table as a 32x64 raster. Pack opening tears at 10% of the wrapper height.
## Menu polish (1.0.332)

TCG list-style screens now use Gen1Recomp's native bordered menu behavior for cursor movement and scrolling. The Binder keeps its requested 2x2 set grid, but uses consistent safe-area margins, collection/page counters, and fixed navigation prompts. Deck viewing is now a real scrollable card list with card-detail drill-down, and the START-menu DECK entry routes to the live deck builder.


## GB1 duel presentation parity (1.0.336)

The MVP duel renderer is now modeled directly on the original Pokemon Trading Card Game GB1 interface rather than on the host RPG menus. The 160x144 main screen uses the original active-card positions, HUD rows, six-command coordinates, HP/energy symbols, Prize/Pokemon counters, TCG cursor, wide duel text box, and five-row card-list presentation. `assets/tcg/graphics/ui/half_width.png` and `symbols_font.png` are the source TCG font/symbol atlases used by these screens.

## Source-driven duel system (1.0.335)

The previous one-active-Pokemon damage-trading prototype has been removed. `tcg_battle.lua` now drives a real 60-card duel using the executable modules from the supplied TCG package under `tcg_engine/`: `engine_runtime.lua`, `duel_engine.lua`, `damage_calculation.lua`, `ai_engine.lua`, `effect_commands.lua`, and `effect_functions_translated.lua`.

The duel starts with seven-card hands and Basic-Pokemon mulligans, Active/Bench placement, six face-down Prize cards and a coin toss for first turn. The battle screen uses the source game's six-option 3x2 command layout: HAND, ATTACK, CHECK, PKMN POWER, RETREAT and DONE. Player actions now include Basic placement, evolution, one Energy attachment per turn, Trainer play, attack Energy requirements, Weakness/Resistance, status conditions, retreat costs, knockouts, Prize selection, replacement Active Pokemon, deck-out and normal win conditions. The attendant uses one of the supplied starter-deck recipes and takes automated turns with the package's AI decision engine.


## 1.0.339 duel presentation / pack-flow pass
- Replaced the pre-duel Active/Bench pickers with the compact TCG GBC card-list presentation.
- Portrait assets are dialogue-only. Ordinary Pokemon battles use native Gen I battlers, while TCG Active Pokemon use the supplied original TCG card illustrations.
- Pack opening now asks `Open another pack?` when another booster remains; YES is selected by default, YES opens a remaining-pack picker, and NO/B exits.
- All custom TCG list menus (pack picker, attendant hub, Binder, starter decks, deck builder, and duel selectors) now share measured 160x144-safe geometry and compact TCG font spacing.
- Added the packaged native ChipAsm `Music_TCGDuelTheme1`, derived from the original Pokemon TCG GBC normal/main duel theme, and restore map music when the duel closes.


- Duel setup/selection screens now stay inside the GB1 TCG UI language from the first Active selection onward.
- Booster opening chains through an `Open another pack?` prompt while physical packs remain in Bag inventory.
- Ordinary Pokemon battles now resolve live battler art through the engine `pokemon.sprite` hook to transparent full-color Pokopia portraits while leaving TCG card art and scripted special previews on their own render paths.


## 1.0.341 authenticity pass

- Removed the portrait-art substitution path from all Pokemon/TCG battles. Portrait assets are now reserved for dialogue UI; the Ditto SAVE panel also no longer draws a portrait.
- TCG Active Pokemon always use the supplied 64x48 Pokemon TCG card art.
- Reordered and presented duel setup around the GB1 flow: seven-card opening hands and Basic mulligans, Arena selection, optional Bench placement, opponent setup, six Prize cards, coin toss, then the first turn.
- Added source-style setup notices, coin-toss presentation, beginning-of-turn draw-card screen, and a dedicated face-down Prize selection grid.
- Corrected between-turn status processing so Poison/Sleep process for both Active Pokemon and Paralysis clears after its owner completes a turn.
- Enforced the GB1 four-copy rule by printed card name with only basic Energy unlimited, and require an exact 60-card deck before leaving the deck builder/starting a duel.
- Converted booster reveal, Binder details, pack chaining, card-counter pack menus, and TCG pack prize menus to the same TCG half-width font and 160x144-safe frame system. The normal Game Corner purchase storefront remains deliberately Gen I because it is an overworld shop interaction.
