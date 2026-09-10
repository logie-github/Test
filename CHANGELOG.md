## 1.0.368 - Rocket Lounge Polish

- Rebuilt the CUE BONES game screen around the native 160x144 viewport. The title, dice, total, point, result, and controls now occupy deliberate rows inside the frame; no prompt is drawn below the screen or into the border.
- Rewrote all Rocket Hideout ambient dialogue around each grunt's actual job/room: kitchen, barracks, laundry, quartermaster, workshop, lookout, records, cards, and off-duty lounge activity.
- Replaced the “lucky cousins” CUE BONES line and removed the gag-heavy/meta tone from the rest of the hideout crew.
- Renamed Operation 2 from LUCKY BREAK to WALL ECHO and rewrote the Rocket Operations dialogue in the same concise DISPATCH voice.
- Hand-broke the new hideout and quest dialogue to fit the native 18-character text interior rather than relying on awkward automatic wrapping.
- Reworked resident Pokemon flavor text, including CUBONE, so they read as animals living in the remodeled base instead of punchlines.
- No generated image assets or image-generation code were added.

## 1.0.367 - Rocket Hideout Full Remodel Fix

- Fixed the real cause of the old spinner maze reappearing: the furnished map override was followed by a second hideout override that could re-read the pristine ROM map while clearing vanilla actors. Each B1F-B4F map is now authored and actor-cleared in one final override.
- Added a live-map geometry reconciliation pass on every Rocket Hideout floor entry. It repaves the complete former maze rectangles before stamping furniture, while excluding native stair/elevator warp blocks.
- Added a final map-reload geometry invalidation after the remodel batch so cached voxel/runtime meshes cannot retain old spinner walls or arrow tiles.
- Reworked the living layouts with intentional zones and traffic lanes: B1F recreation/dining/kitchen/dispatch, B2F barracks/laundry/dining/quartermaster, B3F TV/cards/workshop, and B4F sleeping/medical/archive/lounge/kitchen.
- Repositioned all 27 Rocket grunts and 12 resident Pokemon around the room functions instead of letting nearest-walkable fallback scatter them from furniture collisions.
- Fixed B1F's save-resume reconciliation check to look for its actual board/dispatch actors instead of the B4F HYPNO, and fixed HYPNO's dialogue speaker label.
- No image-generation code or generated image assets were added.

## 1.0.366 - Furnished Rocket Home

- Replaced the empty open-plan Rocket Hideout flood-fill with hand-authored furnished floor plans.
- Added native FACILITY-block beds, communal tables, lounge seating, TV/computer consoles, kitchen counters/appliances, cabinets, storage, workbenches, dining areas, barracks and a med/archive lounge.
- Removed the fake POKEDEX/BOULDER furniture actors; furnishings are now part of the actual map geometry.
- Preserved the original exterior shells and all native warp blocks while replacing the former maze interiors.
- Kept the 27 Rocket grunts, 12 resident Pokemon, unique dialogue, permanently-open Game Corner stair, and `Home Sweet Home!` poster.
- This revision adds no image-generation code and creates no new image assets; all furnishing visuals reuse existing game tiles.

## 1.0.365 - Rocket Hideout Syntax Fix

- Fixed the stray `end` after `ensureRocketHangout`, which prematurely closed the mod entry function and caused the loader error `'<eof>' expected near 'for'`.
- Preserved the 1.0.364 Rocket Hideout population expansion, unique dialogue, permanently-open Game Corner entrance, and `Home Sweet Home!` poster interaction.
- Re-ran a full Lua syntax parse over every packaged `.lua` file before packaging.

## 1.0.364 - Crowded Rocket Home

- Tripled the Rocket Hideout grunt population from 9 to 27 and the resident Pokemon population from 4 to 12, spread across B1F-B4F.
- Added eight Rocket-associated Gen I/II species not previously spawned in Pokopia: Ekans, Arbok, Golbat, Drowzee, Vileplume, Murkrow, Houndour, and Houndoom.
- Gave every Rocket grunt and every resident Pokemon its own named runtime actor and unique ambient dialogue, while preserving all five Rocket Operations quest handlers.
- Authored the Celadon Game Corner Rocket Hideout staircase in its permanently-open block state and also reassert the extracted open block/event on every Game Corner entry.
- Replaced the poster's secret-switch interaction with a harmless `Home Sweet Home!` message.

## 1.0.363 - Open-Plan Rocket Hideout

- Reopened Rocket Hideout B2F, B3F, and B4F; stairs and elevator routes are no longer intentionally blocked.
- Replaced the interior spinner-maze block layouts with broad open-plan floor space while preserving the outer shell and warp blocks.
- Spread the Rocket hangout cast across all four basement floors instead of concentrating everyone on B1F.
- Added themed living zones: B1F recreation/Cue Bones, B2F bunks, B3F TV/common room, and B4F quiet lounge/dream lab.
- Added beds, TVs, chairs, and tables as passable lounge props using stock overworld sprite assets.
- Kept all five Rocket Operations completable by distributing every required quest NPC across the reopened floors.

## 1.0.362 - Livelier Rocket Lounge

- Fixed Hypno's Card Club crashing on interaction because the TCG helpers were
  lexically local to `startCeladonEnding`. The self-contained TCG subsystem is
  now initialized at module scope and shared explicitly by Hypno and the Game
  Corner attendant, independent of story order or save/reload history.
- Audited all 319 usable TCG attacks across populated/head-biased,
  populated/tail-biased, and sparse-board scenarios with zero live-hook errors.
- Added generated argument metadata for all translated effect handlers and a
  context resolver that supplies the correct attacker, defender, duelist, card
  selection, Energy selection, Bench target, predicate, and card-data helper to
  each initial/selection/discard/before-damage/after-damage hook.
- Fixed Cat Punch and the other random/opposing-play-area effects receiving the
  attacking Pokemon where their translated handlers require the opposing duelist.
  Cat Punch now damages a random opposing Active/Bench Pokemon without raising a
  `.bench` length error.
- Moved translated-effect diagnostics out of player-facing duel messages, preventing
  internal hook names, source paths, and Lua errors from being paged through the TCG
  text box.
- Expanded the Pokemon Mansion 3F Hypno interaction into `HYPNO'S CARD CLUB`.
- Hypno now gives unlimited free Colosseum, Evolution, Mystery, and Laboratory
  booster packs in quantities of 1-99 per transaction without consuming Coins or
  the card counter's ten-pack introductory allowance.
- Hypno now gives repeatable free copies of all three 60-card starter decks, opens
  the deck builder, and starts TCG duels. The original Scene 1/2/2.5 developer
  jumps remain available in a separate submenu.
- Restored Pokemon TCG duel attack presentation from `pret/poketcg`: all per-card
  `ATK_ANIM_*` assignments, their ordered `DUEL_ANIM_*` command sequences, and the
  62 original duel-animation sprite sheets are now packaged.
- Player and AI attacks now enter a timed presentation phase and commit damage/effects
  at the impact command instead of resolving invisibly before the result text.
- Runtime animation, frame, redraw, and invalid-choice SFX calls now emit presentation
  events instead of silently discarding the translated source calls.
- Moved the entire Cue Bones group three walk-grid cells north, including the game board.
- Spread the non-gambling Rocket grunts across the reachable B1F lounge instead of clustering them around the table.
- Added three additional off-duty grunts around the lounge, with a mix of stationary and wandering behavior.
- Every added grunt has unique dialogue.
- Kept exactly one Zubat, one Raticate, and one Cubone, with their standard Pokemon palettes.
- All placements still pass through the reachable/walkable spawn resolver so nobody can appear behind locked doors.

## 1.0.361 - Rocket Hideout Accessible Spawns

- Every new B1F Rocket, Pokemon, and Cue Bones object now spawns only on walkable floor cells connected to the player's actual accessible area.
- Sealed rooms, behind-door pockets, warp cells, and occupied cells are automatically rejected by the spawn resolver.
- Moved the preferred positions for the wandering Rockets and Pokemon into the public central lounge.
- Preserved exactly one Zubat, one Raticate, and one Cubone with their normal Pokemon palettes and unique dialogue.

## 1.0.360 - Rocket Pokemon Palette Fix

- Restored the Rocket Hideout Zubat, Raticate, and Cubone to the same standard `registerFollower` rendering path used by all other Pokopia Pokemon.
- The three Pokemon now keep their normal species colors/default Pokemon palettes (`trueColor=true`) instead of inheriting the human NPC OBJ palette.
- Human Rocket NPCs, including the Perfect Crystal female grunt, continue to use the normal default NPC palette.
- Kept exactly one Zubat, one Raticate, and one Cubone on B1F, with the distinct dialogue and Cue Bones stability fixes from 1.0.359.

## 1.0.360 - Rocket Hideout Pokemon Palettes

- Restored Zubat, Raticate, and Cubone to the mod's normal Pokemon follower sprite definitions so they use the same default Pokemon palettes as other Pokemon.
- Removed the hideout-only DMG grayscale Pokemon sprite copies.
- Female Rocket remains on the normal NPC overworld palette path.
- Kept the one-of-each Pokemon guarantee and Cue Bones stability fixes from 1.0.359.

## 1.0.359 - Rocket Hideout MVP Stability

- Fixed Cue Bones crashing on Gen1Recomp builds that do not expose `SpriteRenderer:getPoseGeometry`; the dice now draw directly from the stock boulder sprite sheet.
- Reconciled the B1F hangout cast on every entry so there is exactly one Zubat, one Raticate, and one Cubone, with no duplicate runtime NPCs after reloads or hot reloads.
- Gave every B1F Rocket and Pokemon its own distinct dialogue; Cubone still says only `My mom's dead.`
- Kept the B1F-only hideout lockdown and normal default overworld palette behavior from 1.0.358.

## 1.0.358 - Rocket Hideout MVP Lockdown

- Reduced the active Rocket Hideout hangout to B1F only; all routes to B2F and the elevator are disabled and solid.
- Removed the original B1F trainer grunts so the floor contains only the new Pokopia hangout cast plus the existing non-NPC map objects.
- Moved Zubat, Raticate, and Cubone onto B1F so the full casual hangout cast remains available without lower floors.
- Female Rocket and hideout Pokemon now use DMG-index sprite sheets through the normal overworld OBJ palette pipeline, matching the default palette behavior of stock Rocket NPCs.
- Cue Bones and the Game Corner exit remain functional.

## 1.0.357 - Cue Bones

- Turned the Rocket Hideout game board into **CUE BONES**, a complete street-dice minigame with a native `PLAY / RULES / LEAVE` menu.
- Cue Bones follows the supplied street-craps rules: 7/11 wins on the come-out, 2/3/12 loses, otherwise establish a point and hit it again before a 7.
- The game screen places Cubone's battle sprite on the left and uses the game's real pushable `SPRITE_BOULDER` artwork as two dice, with pip dots drawn over each face.
- Winning pays **$300** to normal money (not Game Corner coins) and plays the standard item-acquired sound.
- Updated the three table grunts so their ambient dialogue talks about Cue Bones.

## 1.0.356 - Rocket Hideout Hangout

- Rebuilt the cleared Rocket Hideout as a casual off-duty Team Rocket hangout across B1F-B4F.
- Added male and Perfect Crystal female Rocket grunts, including wandering off-duty grunts and a three-grunt tabletop gambling group.
- The gambling table uses Gen I's real `SPRITE_POKEDEX` overworld object from Oak's Lab as the game-board piece.
- Added talking Zubat and Raticate residents plus Cubone, whose entire dialogue is `My mom's dead.`
- Kept the hideout non-combat and preserved its existing stairs, elevator, spin-tile geometry, and revealed entrance.

## 1.0.355 - Old Photo Family Walk Home

- The grandson now has to visibly walk the full Celadon route into the NPC house before the quest advances; the previous path-failure teleport fallback is gone.
- Moved the grandson's indoor position off the table and onto the lower floor beside the family.
- Rewrote Dad's OLD PHOTO reward dialogue to explain that the family's old photographs were lost when their house burned down, and to thank DITTO for bringing a piece of the family history back.

## 1.0.354 - OLD PHOTO Composition Polish

- Moved Grandpa closer to Erika in the OLD PHOTO composition.
- Lowered Grandpa's sprite baseline to compensate for the battle sprite's source padding so the visible characters are bottom-aligned.

## 1.0.353 - OLD PHOTO Family Epilogue

- Rebuilt the OLD PHOTO viewer around the user-supplied Celadon Gym image and now shows Erika and Grandpa as complete sprites instead of cropped upper halves.
- Rewrote the grandson reveal to recognize Grandma and the day Grandpa proposed, then ask to keep the photo for his parents.
- After accepting, the grandson physically walks from Celadon to the CELADON_CHIEF_HOUSE door and remains inside afterward.
- On the first visit to the house after the handoff, Dad awards 500 Game Corner COINS with the standard item-acquired sound.
- Preserved the OLD WOMAN transformation unlock as part of the photo handoff.

## 1.0.352

- Celadon Cafe delivery briefing now labels the finished ordered item instead of presenting the berry ingredient as the delivery target; the live HUD leads with the item name as well.
- Delivery customers remain visible until the native Gen I fade reaches full black on both success and timeout; the previous hand-drawn fade has been removed.
- Successful Cafe deliveries, winning Slot Machine payouts, Scalper RPS wins, Hitmon spar wins, and friendly transformed RPS wins now play the standard item-acquired sound.

## 1.0.351 - Permanent X20 Celadon Barrier Geometry

- Bakes the vertical Celadon card-line barrier at world cells X=20, Y=10-13 into the initial CELADON_CITY block map (block column 10, rows 5-6).
- The barrier is now present before `mods.loaded`, so Dramatic Shape and other 3D renderers see it during their first geometry snapshot/mesh build.
- Keeps the separate south-Gym barrier opening permanently removed in the authored map.

## 1.0.350 - Permanent Celadon Static Geometry

- Moved the south Celadon Gym approach opening into the base `CELADON_CITY` map block registry instead of applying it on map entry.
- Moved all Celadon Gym cut-tree removals into the base `CELADON_GYM` block registry using the native Gen I GYM Cut block swaps.
- These geometry changes now exist before the `mods.loaded` event, so 3D voxel renderers that snapshot static map geometry see the Pokopia layout from their first mesh build.
- Runtime block replacement remains only as a defensive fallback for stale/older engine map records; it is no longer the source of the permanent layout.

## 1.0.349 - Celadon Gym Evacuation Polish

- Removed the remaining cuttable tree obstacles from the Celadon Gym by applying the native GYM cut-tree block replacements to both artwork and collision.
- Reworked the OLD WOMAN scare evacuation so every gym trainer starts running for the exit simultaneously instead of leaving one at a time.
- Erika's ghost now disappears at the midpoint of Gen1Recomp's native fade-to-black / fade-in transition, with the Rainbow Badge message appearing after the fade completes.

## 1.0.347 - Old Photo Relocation

- Moved the OLD PHOTO pickup on the outdoor Celadon map from `(38,33)` to the newly supplied `CELADON_CITY` coordinate `(48,16)`.
- The existing OLD PHOTO one-time save flag and OLD WOMAN clue progression are unchanged; the player can collect it while standing on or directly facing the new cell.

## 1.0.346 - Erika Ghost Epilogue

- After the OLD WOMAN Celadon Gym scare, Erika's ghost appears on the next outdoor Celadon entry using Erika's original overworld sprite.
- The ghost uses a cached runtime OBJ palette with inverted grayscale visible shades and no black pixels.
- Erika reflects on Celadon's decline, ends on hope for its future, disappears, and grants the Rainbow Badge exactly once.
- After the encounter, the Celadon Gym entrance is permanently locked and reads `CLOSED UNTIL FURTHER NOTICE`.

# 1.0.345

- Opened the Celadon south barrier span shown between the supplied `(22,31)` and `(26,31)` references by replacing block columns 11 through 13 on the immediately-south barrier row with Celadon's normal open-ground block.
- Replaced Erika's Celadon Gym overworld actor with a non-battling female attendant while preserving the authored leader position.
- Changed the OLD WOMAN transformation to use Erika's original Gen I overworld sprite (`SPRITE_SILPH_WORKER_F`) instead of the generic Beauty sprite.
- Converted every Celadon Gym trainer interaction to reactive, non-battle dialogue based on Ditto's current form.
- OLD WOMAN now triggers: `Lady Erika? But you died 20 years ago... GHOST! It's a ghost!`; the full gym cast then runs to the real exit and is removed, with the scare state persisted across reloads.

# 1.0.344

- Scoped the Pokemon TCG half-width menu/font/frame renderer strictly to TCG features.
- Restored the Celadon Cafe job menu, another-delivery prompt, and delivery briefing to Pokopia's normal Gen I menu/font presentation.
- Kept TCG-specific counter, Binder, Deck Builder, booster, pack-selection, and duel interfaces on the dedicated TCG UI.
- Cafe delivery HUD remains on the native Gen I renderer.

# 1.0.343

- Removed the stock old man who peers through the Celadon Gym window at the original `(11,28)` outdoor position.
- Moved the OLD PHOTO clue from the Department Store roof to `CELADON_CITY` coordinate `(38,33)`, matching the authored screenshot location.
- The OLD PHOTO can be picked up with A while standing on or directly facing the `(38,33)` cell; its existing one-time save flag and OLD WOMAN clue progression remain unchanged.

# 1.0.342

- Added the Celadon Cafe Delivery Job minigame as a cafe-only system, with a new Lass behind the diner counter and no job/referral changes to the Game Corner attendant.
- Added independent randomized berry dessert orders, one-minute single-delivery jobs, persistent customer/location/timer HUD, success return/payout flow, and timeout penalty/return flow.
- Added unique delivery IDs, single-transition success/failure guards, exactly-once money/stat accounting, persistent cafe job statistics, and safe cancellation of unfinished active deliveries on reload.
- Added curated Celadon outdoor destinations with warp/collision/NPC checks and explicit exclusion of the inaccessible northeast story-barrier region.
- Added temporary trainer-class delivery customers using only sprite classes present in the active Gen1Recomp data set, removed automatically on completion/failure.
- Added non-outline PokéSprite Cheri, Chesto, Pecha, Rawst, Aspear, Leppa, Oran, Persim, Lum, and Sitrus berry inventory artwork under `assets/cafe/berries/`, with transparency-preserving four-shade luminance conversion cached at runtime.
- Added `ASSET_SOURCES.md` with PokéSprite source and attribution details.

# 1.0.341

- Enforced a dialogue-only portrait policy: removed the global `pokemon.sprite` portrait substitution, removed Pokopia portrait use from TCG duels/setup and the SAVE status panel, and restored native Gen I battle front/back sprites for every species.
- TCG Active Pokemon now always use the supplied original 64x48 Pokemon TCG card illustrations; no character portrait assets are used in the duel renderer.
- Aligned duel setup to the GB1 `HandleDuelSetup` order: seven-card opening hands with Basic-Pokemon mulligan notices, player Arena choice, optional five-Pokemon Bench setup, opponent setup, six Prize cards, coin toss, then first-turn draw.
- Added opaque source-font setup notices and a TCG-styled coin-toss screen.
- Replaced the beginning-of-turn `DITTO drew...` RPG-style message with a dedicated TCG draw-card screen showing the drawn card plus Hand/Deck counts.
- Replaced numbered Prize lists with a dedicated face-down 3x2 Prize-card selection screen and non-cancelable source cursor behavior.
- Corrected between-turn status timing so Poison/Sleep process for both Active Pokemon while Paralysis clears after its owner's turn.
- Enforced the source deck rule of at most four cards sharing the same printed/display name; the six basic Energy cards remain unlimited while Double Colorless is limited to four. Deck Builder now requires exactly 60 cards before exiting.
- Converted booster sealed/rip/reveal/unlock screens, chained-pack YES/NO, card-counter pack menus, Prize Room pack selection, Binder details and Binder grids onto the common TCG half-width font/frame system with measured 160x144-safe spacing. `Open another pack?` still defaults to YES.
- Kept the Game Corner pack purchase storefront in native Gen I shop style deliberately; it is an overworld merchant interaction, while the actual TCG flow remains TCG-styled.
- Retained the source-timed four-channel Duel Theme 1 fix from v1.0.340 and the durable Hitmon transformation-unlock repair.

# 1.0.340

- Restored HITMONLEE and HITMONCHAN to their stock Gen1 battle front/back sprites. The global full-color portrait battler hook now explicitly excludes both Hitmon species so the dojo spar keeps its intended transformation presentation.
- Made Hitmon transformation learning independent of generic BattleState teardown. The selected Hitmon form is committed at the exact RPS win state, then reasserted in `onFinish`; a persistent `hitmonWinChoice` repair anchor also restores the selectable form on later loads.
- Replaced the approximate three-channel TCG duel-theme transcription with a source-score conversion of `pret/poketcg` `Music_DuelTheme1`. All four source channels, finite loops, call structure, speed changes, notes/rests, wave pattern, and noise rhythm are preserved.
- Corrected Duel Theme 1 timing to the source engine's `speed * length` VBlank clock by using ChipSynth tempo 256. Every channel now loops on the same 7,840-frame / 130.6667-second boundary instead of drifting against the others.
- Packaged the authoritative duel-theme ASM and deterministic converter under `assets/tcg/audio/source/` so the generated music can be reproduced from code.

# 1.0.339

- `Open another pack?` now defaults to YES. B/NO still exits normally.
- Rebuilt every custom non-shop TCG list on the Pokemon TCG GB half-width font and source-style 160x144 list/footer geometry.
- Pack selection, Binder, starter-deck, deck-builder, and attendant menus now use measured left/right columns with five safe rows and scrolling.
- Duel card-list title/status widths are calculated together, preventing header collisions.
- Duel list right columns are fitted before the card-name budget is calculated, fixing premature truncation and Active/Bench row collisions.
- Opening Active/Bench setup prompts were shortened to source-style controls (`A SELECT`, `A PLACE  B DONE`) so the footer never overruns its box.
- Footer wrapping now reserves an 8px margin from both borders.

# 1.0.338

## [1.0.338] - 2026-08-31

### TCG setup, color battle art, chained packs, and duel music
- Rebuilt the pre-duel Active/Bench selection screens around the Pokemon TCG GBC card-list layout instead of oversized Gen I RPG list boxes.
- Switched regular Pokemon battlers and TCG Active Pokemon to Pokopia's packaged full-color species artwork where available, with source TCG art as fallback.
- After a booster reveal, if another booster remains, ask `Open another pack?`; YES opens a remaining-pack selector and NO returns to the game.
- Packaged a native Gen1Recomp ChipAsm transcription of the Pokemon TCG GBC normal/main Duel Theme 1 in `assets/tcg/audio/dueltheme1.lua`.
- TCG duels start `Music_TCGDuelTheme1` at setup and restore the current map theme when the match closes.


- Replaced the duel setup's generic RPG CHOOSE ACTIVE / PLACE ON BENCH boxes with the same Pokemon TCG GB1 five-row card-list renderer used by HAND/CHECK/RETREAT. Opening choices now use the source half-width font, TCG cursor/symbols, card-type icons, HP right column, compact status header, and source-style prompt box.
- Converted the remaining duel target/prize/search/revive selection popups from generic RPG menus to the TCG GB list renderer so the presentation stays consistent after setup too.
- Opening Active selection is now non-cancelable instead of restarting the duel if B is pressed; opening Bench placement keeps DONE/B as the clean continuation path.
- Added a `pokemon.sprite` battle hook that swaps ordinary Pokemon battles to Pokopia's packaged full-color Normal portrait art, marks it true-color so Gen1Recomp does not quantize it through the SGB palette, and applies battle-specific scaling for the 40x40 art.
- Added deterministic `tools/build_battle_color.py` preprocessing plus 251 transparent battle cutouts derived from the already-packaged full-color portrait assets; no generated replacement artwork is used.
- TCG duel Active Pokemon now use those same full-color Pokopia portrait cutouts in the source duel geometry, with the original four-color TCG card art retained only as a fallback when a card name cannot map cleanly to a species.
- After finishing a booster, if another TCG pack remains in the Bag the game now asks `Open another pack?`. YES opens an expansion picker with remaining quantities and immediately opens the selected pack; NO/B closes out normally. The prompt repeats until the player stops or runs out of packs.

# 1.0.336

- Rebuilt the MVP duel presentation against the original Pokemon TCG GB1 screen layout instead of using generic Pokopia/RPG battle menus.
- The main duel screen now uses the original 160x144 geometry: opponent art at 96,8; player art at 0,40; stepped center separator; compact play-area/prize counters; E/HP HUDs; and the source HAND / CHECK / RETREAT / ATTACK / PKMN POWER / DONE positions.
- Packaged and now renders the original TCG half-width duel font and symbol atlas for menu text, Energy/type icons, Special Conditions, Pokemon/Prize counters, HP counters, cursor, and box-frame tiles.
- ATTACK stays on the duel scene and uses the original two-row bottom-box presentation with printed Energy requirements, damage, and the TCG cursor.
- HAND, CHECK, RETREAT, discard/play-area lists, and PKMN POWER now use a dedicated five-row TCG GB-style list screen instead of Gen1Recomp's RPG menu renderer.
- HAND displays the source-style `<player>'S HAND` header, 1/N counter, five visible cards, card-category icons, scrolling, PLAY/CHECK choice flow, and SELECT sorting.
- CHECK now follows the GB1 command structure: IN PLAY AREA / YOUR PLAY AREA / OPP. PLAY AREA / POKEMON CARD GLOSSARY, with nested play-area views.
- Duel messages now appear in the same wide bottom duel box over the active battle scene and page two lines at a time.
- Plain B on the main duel screen is inert as in GB1; B+direction view shortcuts remain available.
- Kept the v1.0.335 60-card rules engine, Prize/Bench/Trainer/Energy/evolution/status/retreat logic, and attendant AI unchanged beneath the new presentation.

# 1.0.335

- Replaced the old one-Pokemon damage-trading TCG prototype with a full duel state based on the supplied TCG package's executable runtime, damage calculation, AI, effect-command, and translated card-effect modules.
- Added the Pokemon TCG GBC six-command duel interface: HAND / ATTACK / CHECK / PKMN POWER / RETREAT / DONE in the original 3x2 layout.
- Duels now use real 60-card decks, opening 7-card hands with Basic-Pokemon mulligans, Active/Bench setup, six Prize cards, draw phases, deck-out losses, knockouts, Prize taking, replacement Active Pokemon, and win conditions.
- HAND now plays Basic Pokemon to the Bench, evolves matching Pokemon, attaches one Energy per turn, plays Trainer cards, and can inspect cards.
- ATTACK now checks printed Energy costs, uses Weakness/Resistance, PlusPower/Defender modifiers, translated attack-effect hooks, status conditions, coin flips, recoil/effect damage, and ends the turn.
- RETREAT now requires a Bench, respects Sleep/Paralysis and once-per-turn retreating, checks/discards the printed retreat Energy cost, and switches Active Pokemon.
- CHECK exposes both play areas, both discard piles, and the player's hand; PKMN POWER invokes translated Pokemon Power effect hooks from cards in play.
- The attendant now battles with one of the real source starter decks and runs an automated turn with deck draw, Trainer play, Bench setup, evolution, Energy attachment, retreat logic, and attack selection.
- Packaged the TCG source runtime modules used by the duel under `tcg_engine/` so the battle implementation remains directly traceable to the supplied TCG ZIP.

# 1.0.334

- Added Wooper's canonical personality reference under `characters/wooper/personality.md`, including his streetwise dreamer voice, money/TCG habits, loyalty, moral code, fears, and planned character arc.
- Added Wooper's first scripted encounter at the real Route 16 -> Celadon City outdoor connection. Crossing back into Celadon pauses Ditto and has Wooper approach from the city side.
- Added native-menu choices for APOLOGIZE/ARGUE and DEFEND ROCKET/AGREE, with both first responses feeding Wooper's joking fake argument.
- Added persistent `characters.WOOPER` save state for first-response history, Team Rocket opinion, meeting completion, and street cred; agreeing that Team Rocket is bad news grants +1 street cred.
- Added Wooper's Gen 2 overworld follower sprite and portrait speaker registration. After the conversation he reverses course, walks away, and player control is restored.

# 1.0.333

- Fixed a compatibility crash in the polished TCG menu renderer when the installed Gen1Recomp `Menu` implementation does not expose `itemY`.
- Right-column text now derives its vertical position from the same bottom-anchored row calculation as the native `Menu:draw()` path when `itemY` is unavailable.
- Kept the native cursor, scrolling, Binder/deck menu polish, 10-Coin packs, starter decks, and booster-opening behavior unchanged.

# 1.0.332

- Replaced the hand-drawn TCG choice-list renderer with Gen1Recomp's native bordered `Menu`, restoring the normal blinking cursor, wrapping, and built-in scroll arrow.
- Added a dedicated right-aligned status column so prices, FREE/LOCKED states, collection counts, deck counts, and attack damage no longer have to be embedded in long labels.
- Added consistent header/status/footer spacing to the attendant hub, Binder set list, starter chooser, deck builder, card add/remove lists, starter loader, and duel attack menu.
- Reworked the Binder's 2x2 card grid with smaller centered card art, an in-cell native cursor, clear owned counts, page/collection counters, and a fixed control footer.
- Reworked Binder card details to use the full 160x144 frame safely, with a dedicated title/page header, centered card art, six-line detail area, and fixed bottom navigation prompt.
- Replaced VIEW DECK's truncated text dump with a scrollable card list; selecting a deck entry opens the same full card detail screen used by the Binder.
- The START-menu DECK entry now opens the live deck builder instead of the old COMING SOON placeholder once the TCG system has initialized.

# 1.0.331

- Corrected the booster-scene OAM tile mapping using the supplied `booster_scene_sprite.lua` reference together with the engine's actual Y,X OAM coordinate consumption.
- Rebuilt the 64x32 Pokémon Trading Card Game logo from all 32 source OAM tiles; the middle tile rows are no longer displayed in raw-sheet order.
- Reassembled all four 64x96 DMG booster scenes from their source tile sheets and overlaid the corrected OAM logo at the scene origin.
- Preserved the top-10% pack tear, starter-deck choice, 10-Coin paid packs, Binder, Bag-use bypass, and storefront behavior from 1.0.330.
- Added the supplied `booster_scene_sprite.lua` under `assets/tcg/data/` as a packaged source reference.

# 1.0.330

- Rebuilt booster visuals from the supplied TCG source tile layout so pack artwork maps as a 64x96 wrapper instead of displaying the raw 96-tile sheet.
- Booster opening now tears horizontally across the top 10% of the wrapper before revealing cards.
- The Celadon TCG attendant now gives Ditto one free choice of the three source starter decks: Charmander & Friends, Squirtle & Friends, or Bulbasaur & Friends.
- Starter decks use the exact 60-card lists from `data/ai_and_deck_mechanics.lua`; granting one adds those cards to the collection and loads it if the active deck is empty.
- The other starter decks can be purchased later for 100 Game Corner Coins each and loaded through DECK BUILDER.

## 1.0.329

- Booster packs now cost 10 Game Corner Coins each after the first 10 free packs.
- Corrected TCG reveal-screen spacing so card names, pack counters, metadata, and NEXT/FINISH prompts stay inside the frame.
- Moved the TCG hub cursor off the border and shortened the BUY PACKS row so the attendant menu no longer clips on the right.
- Added pixel-width fitting for long TCG labels and tightened Binder/detail layouts.
- Kept the booster tear animation inside the card-pack frame.
- Updated secondary Celadon booster vendors to the same 10-Coins-per-pack price.

## 1.0.328
- Added a hard Bag-level bypass for all four TCG booster ids. Their native USE row now calls the Pokopia pack opener directly before vanilla `ItemEffects.use`, making the Oak field-use rejection path unreachable.
- The booster Bag interaction still uses the stock Gen I USE/TOSS menu and native cursor. TOSS remains functional and updates the Bag stack normally.
- Kept the existing item-effect and runtime-hook routes as compatibility fallbacks, but booster opening no longer depends on either route.

## 1.0.327
- Fixed the booster storefront crash in `Font.draw`/`Font.split` by giving the stock `ListMenu` a concrete `BUY PACKS` title and forcing every booster/cancel row to carry non-nil string labels and price text.
- Kept the purchase flow on the standard Gen I `ListMenu`/`QuantityBox`/`ChoiceBox` storefront components.
- Added the native Gen1Recomp menu-arrow cursor to Pokopia's TCG hub/list menus; the booster storefront continues to use `ListMenu`'s built-in cursor.
- Preserved location-independent Bag opening, the first-ten-free rule, Game Corner Coin pricing, Binder data, and attendant placement.

## 1.0.326
- Fixed TCG booster Bag USE again by registering the `item.use` interception during initial mod load instead of during the Celadon runtime sequence. This avoids late-hook registration being skipped on API-2 builds.
- Added a runtime Gen 1 compatibility bridge that ensures all four booster definitions point at `TCG_OPEN_PACK` and that the merged `game.data.item_effects` table contains the handler before Bag input is processed.
- Booster packs are location-independent and can be opened from the Bag on any map; the effect is also permitted when the Bag is opened during battle.
- Replaced the custom booster-purchase menus with the engine's stock Gen I list/quantity/YES-NO storefront components, including the native cursor. The first ten packs are claimed through the same storefront for free; afterward packs cost 50 Game Corner Coins each.

## 1.0.325
- Fixed the TCG menu-box height calculation shown in the Game Corner screenshots. Menu entries use 16-pixel vertical spacing, so the renderer now allocates two 8-pixel box rows per visible option.
- Limited scrolling TCG menus to six visible choices, which fits the 160x144 viewport while keeping every row, cursor, and BACK option inside the border.
- The Game Corner attendant remains at `(5,6)` behind the northwest counter with two-cell across-counter interaction from `(5,8)`.

## 1.0.324
- Fixed the Celadon transition crash `item_effects: content is frozen after load`.
- Registered `TCG_OPEN_PACK` during initial mod loading, before Gen1Recomp freezes content registries.
- The registered effect now delegates to the same runtime pack-opening implementation once the Celadon TCG subsystem initializes; pull odds, inventory consumption, Binder unlocks, and attendant placement are unchanged.

## 1.0.323
- Moved the Celadon Game Corner TCG attendant to the original Gen I northwest service-clerk position behind the counter at map cell `(5,6)`.
- Added across-counter A-button interaction so the attendant remains reachable from the customer side while preserving the existing check-in, pack shop, Binder, deck-builder, and duel logic.

## 1.0.322
- Fixed TCG booster Bag USE on Gen1Recomp API-2 builds that dispatch through `item_effects` instead of the newer `item.use` hook.
- All four booster items now reference the registered `TCG_OPEN_PACK` effect. Successful use still consumes exactly one pack and launches the source-derived opening animation; failed pack generation consumes nothing.

## 1.0.321
- Converted all four TCG boosters into physical Bag items (`COLOSSEUM PACK`, `EVOLUTION PACK`, `MYSTERY PACK`, `LABORATORY PACK`) that stack in INVENTORY and consume one item when opened.
- The Celadon Game Corner attendant now gives the first 10 purchased packs free across all expansions, then charges 50 Coins per pack.
- Replaced the prototype hand-authored pulls with the supplied TCG package's complete 228-card database, six expansion lists, exact 10-card rarity slots, weighted type chances, original per-pull chance depletion, and native card/booster artwork.
- Added booster presentation: expansion pack art, animated center tear into two halves, then ten one-by-one card reveals.
- First pack opening permanently unlocks BINDER; START now inserts BINDER and a DECK placeholder immediately below the player-name/DITTO row.
- Added BINDER set list, source-ordered 2x2 card grids, owned copy counts, hidden unowned slots, and paged full card metadata/attack/description views.
- Preserved the counter deck builder and AI duel while migrating legacy prototype pack counts into physical Bag stacks non-destructively.

## 1.0.319
- Smoothed Scene 2 cutscene choreography: restored vanilla 32-frame NPC walk timing, added short settle beats after scripted movement, tweened the Celadon establishing-shot camera instead of snapping, and made paired Rocket movement simultaneous.
- The Celadon flood officer now visibly pushes Ditto two tiles left instead of teleporting the player after dialogue.
- Reduced excessively long static establishing-shot holds while preserving all dialogue and story sequencing.

## 1.0.226
- Fixed the Celadon flood-officer loop: after the final line Ditto is moved exactly two cells left before input is restored, with a short positional retrigger latch.
- Forced the vanilla Game Corner Rocket-hideout poster event on permanently, so the hidden stair block loads in its open state on every Game Corner visit.

## 1.0.225
- Fixed a Lua load failure caused by a stray `end` in the Celadon Scene 2 chatter interaction block.
- Parser-validated `main.lua` after the fix.

## v1.0.225

- Replaced the Mansion B1F PC overworld object with vanilla Pokémon Center block $22 at block coordinate (7,7); PC interaction is now position-based at cell (14,14).
- Removed the generated `SPRITE_POKEMON_CENTER_PC` path and its asset transform.

## 1.0.223

- Added a visible Celadon flood officer at the east road blockade; the interaction now keys off the spawned officer actor instead of an invisible coordinate.
- Preserved the speaker nameplate and dialogue cutout pipeline for Celadon human NPCs, including generic resident/trainer classes and the officer/attendant.
- Reworked Celadon outdoor dialogue to keep speaker labels out of prose and pass speaker identity as metadata; manually paginated longer lines to prevent run-on text.
- Added a dialogue re-entry guard so a single input cannot advance a textbox and trigger another Scene 2 interaction underneath it.
- Replaced all four Mansion-reused Celadon companion Pokemon with ordinary Gen 1-2 species appropriate to their NPCs: Growlithe, Bellsprout, Eevee, and Sentret.
- Registered those four species against the bundled Enhanced Overworld `_normal` follower sheets and existing Pokemon portrait library.

## 1.0.222

- HYPNO now acts as the scene selector on the initial encounter.
- The first interaction explicitly asks which scene to begin: Scene 1, Scene 2, or Scene 2.5.
- Scene 2.5 still enters the exact free-roam trash-cleanup handoff used by normal progression.

## 1.0.221

- HYPNO now offers a Scene 2.5 jump in addition to Scene 2 and Scene 1 restart.
- Scene 2.5 begins at the exact free-roam cleanup handoff used by normal progression: DITTO is playable in ROCKET_HIDEOUT_B1F with the three trash pickups active.
- The Scene 2.5 jump reuses the normal cleanup initialization instead of maintaining a separate approximation of that state.

## 1.0.220

- Fixed Celadon replacement NPCs failing to spawn when Ditto entered on a doorway/warp cell. The reachable-street flood fill now seeds correctly from transition cells and retries a failed empty population pass instead of caching it.

## 1.0.217
- Imported all 251 `_normal` follower sheets directly from `STADIUM2_OVERWORLD_MODELS-0.1.85.zip` into `assets/enhanced_overworld/poke_followers/`.
- Switched every Pokopia Pokemon follower registration and runtime override to the exact `follower_###_normal.png` files in that directory.
- Removed the mixed legacy/runtime-normal sprite routing introduced by the prior Enhanced Overworld integration.

## 1.0.216

- Fixed the v1.0.215 sprite regression by restoring every pre-existing Pokopia Pokemon to its established `assets/sprites/gen2_3d_followers` sheet.
- Enhanced Overworld assets remain bundled and credited, but are only assigned to the newly-added Scene 2 Pokemon that did not already have established Pokopia artwork: Hypno, Zubat, Raticate, Tentacool, and Tentacruel.
- Save compatibility behavior from v1.0.214 is unchanged.

## 1.0.214

### Save compatibility
- Added non-destructive save normalization for the permanent `save.modData.pokopia_log568` namespace.
- Saves from earlier builds now receive missing defaults and dependent progression flags additively without clearing existing story progress, forms, inventory, or unknown fields.
- Saves carrying a newer schema number are never downgraded, preserving forward-added data when moving between builds.
- Hardened legacy/malformed save tables so missing `modData`, form tables, or current-form fields no longer break loading.
- Updated the packaged manifest version to 1.0.214.

## 1.0.213

### Celadon overworld NPC visibility
- Fixed Scene 2 Celadon appearing empty before the cleanup task stage.
- The replacement Celadon population is now instantiated whenever the Scene 2 `CELADON_CITY` map is active; interaction/task logic remains gated to the appropriate cleanup phase.

## 1.0.167
- Fixed the first Celadon establishing shot rendering black by moving its camera target inward from the map edge; later Celadon framing and transition behavior are unchanged.

## 1.0.166
- Fixed the epilogue hideout Rocket path crash: cutscene actors still obey normal walkability, warp, and entity collision, but an unreachable scripted staging cell now resolves to the nearest reachable collision-safe cell instead of throwing an error.

## 1.0.165
- Removed the live vanilla Game Corner poster Rocket after map load so the guard stays hidden during the epilogue.
- Rocket grunts approaching the Super Nerd now spawn and route only through normal walkable, non-warp, unoccupied cells.
- Weather broadcast speaker is explicitly `TV Reporter` and uses the Cooltrainer F trainer cutout.

## 1.0.164
- Nudged the Super Nerd dialogue cutout slightly farther right while preserving its existing vertical offset and overworld position.

## 1.0.163
- Added trainer cutouts for Logan (Scientist), Prize Lady (Beauty), Prize Worker (Biker), and the weather broadcast's TV Reporter (Cooltrainer F).
- Shifted the Super Nerd dialogue cutout 25% upward and rightward while leaving its overworld collision position unchanged.
- Removed the vanilla Rocket grunt stationed at the Game Corner poster; epilogue Rocket actors are unaffected.
- Tightened scripted Rocket pathfinding so occupied destination cells are rejected instead of bypassing entity collision.
- Changed the weather broadcast speaker name to TV Reporter.
- Reframed Celadon's establishing shots through the native camera-follow/clamping path to prevent the first city view from rendering outside the map as black.

## 1.0.162
- Reworked the SAVE panel for Ditto: it now shows a smiling Ditto portrait, replaces POKéDEX with TRANSFORM, and displays the number of learned transformations.
- The "Much earlier..." chronology transition now wipes all learned transformations and resets Ditto to its base form before Celadon begins.
- Expanded dialogue portrait-expression inference so Pokémon portraits better match fear, pain, surprise, anger, determination, sadness, relief, and happiness in their actual lines.

## 1.0.161
- Persian and Rattata now lock permanently into their exact FALSE SWIPE positions as soon as the attack lands.
- Talking to the post-lesson Rattata no longer makes it turn to face Ditto; the saved cutscene facing is preserved.

## 1.0.160
- Fixed the epilogue crash caused by reading map height from the runtime Map object instead of its map definition during Game Corner/Rocket cutscene staging.

## 1.0.159
- Giovanni's meeting dialogue now presents his trainer portrait and GIOVANNI name box for his spoken lines.
- Removed the duplicate narration that described Giovanni looking down at Ditto twice.
- While PIXIE or RATTATA is following Ditto, transformation movement bonuses are suppressed and Ditto uses default engine movement speed.

## 1.0.158
- Added Giovanni-room disguise enforcement: transforming within four blocks of Giovanni into any Pokemon other than Persian makes the Rocket guard approach and escort Ditto out.

## 1.0.158
- Transforming into a non-Persian Pokemon within four blocks of Giovanni now blows Ditto's disguise; the Rocket guard walks over and escorts Ditto out of the room.

## 1.0.157
- Rebuilt the epilogue: the Super Nerd returns to the Game Corner for a refund, Rockets take him away, and a later Rocket Hideout TV scene leads into impossible rain over Celadon.

## 1.0.156
- Electrode-form acceleration now starts at 10 frames per tile instead of 12; the 8 and 4 frame acceleration stages are unchanged.

## 1.0.155
- Electrode-form momentum now resets on a real collision, an A-button interaction, a scripted interaction stop, or a map/interaction transition, in addition to full D-pad release.
- Direction changes still preserve momentum while movement remains uninterrupted.

## 1.0.154
- Electrode-form momentum now survives direction changes while the D-pad remains held; acceleration resets only after every D-pad direction is released.

## 1.0.153
- Fixed Electrode acceleration to belong explicitly to Ditto's applied ELECTRODE transformation (`ctx.player.pokopiaForm`), never the Electrode NPC.
- Moved acceleration state onto the transformed player and reset it on D-pad release or form change.

## 1.0.152
- Made ELECTRODE acceleration an MVP-critical synchronous movement-speed feature: each new tile now uses a direct 12f -> 8f -> 4f progression from Player:stepLength(), with no input-step timing dependency.

## 1.0.151
- Replaced Electrode's layered bike-hook acceleration with a single deterministic Player.stepFrames acceleration path (12 → 8 → 4 frames/tile).

## 1.0.150
- Fixed ELECTRODE movement so it starts faster than Ditto and visibly accelerates while a direction is held, reaching 4 frames per tile at full charge.
- Reworked Larvitar hide-and-seek timing so he runs to the exit visibly first, then a single native fade covers only the actual hiding relocation.
- Changed ELECTRODE's teaching line from the Ditto/racing comparison to: "Roll around like me."

## 1.0.149
- Removed DITTO and VOLTORB name text from the race scorecard; portraits and live score remain.

## 1.0.148
- Restored minigame HUD to the full native dialogue presentation scale; the previous uiScale path was shrinking it a second time under survey zoom.
- Retained thin square portrait frames and square dialogue nameplates.

## 1.0.147
- Matched the minigame HUD to the renderer's actual UI scale/letterbox instead of the larger world viewport scale, so it is the same size as normal dialogue while remaining top-anchored.
- Reduced minigame portrait frames to a one-pixel square border.
- Changed dialogue speaker nameplates from rounded tabs to square-cornered frames.

## 1.0.146
- Rebuilt both minigame HUDs from the same 20x6 frame tiles and 8px glyph grid used by the normal in-game dialogue box, anchored at the top of the active game viewport.
- Changed all Pokémon portrait cards to hard square corners instead of rounded corners.

## 1.0.145
- Reworked the minigame dialogue HUD so the real full-size TextBox now shows both racer portraits, both names, and the live lap score in the native dialogue font.
- Larvitar hide-and-seek keeps the same full-size dialogue box with Larvitar portrait, name, and live timer.

## 1.0.144
- Fixed minigame dialogue HUD scaling by deriving the native 160px Game Boy scale from the actual drawable width and bottom-anchoring the real TextBox.

## 1.0.143
- Fixed minigame dialogue HUD viewport scaling/anchoring so the real TextBox fills the normal in-game dialogue width at the bottom of the game view.

## 1.0.142
- Replaced the hand-drawn minigame HUD with the engine's actual TextBox renderer, so its border, placement, anchoring, and text glyph size are identical to normal in-game dialogue.
- Kept the minigame display non-interactive so the race and hide-and-seek continue running behind it.

## 1.0.141
- Restored the single lower-right 1F Mansion barrier so the player can no longer walk beyond the map boundary there.
- All other intentionally opened Mansion barriers remain unchanged.

## 1.0.140
- Restored Larvitar's earlier, more natural hide-and-seek introduction; Larvitar no longer mentions Electrode.
- Softened Larvitar's pre-minigame idle dialogue so the interaction feels less abrupt.

## 1.0.139
- Removed race-start and race-end coordinate snapping for Voltorb and Ditto.
- Race staging now walks Ditto and Voltorb naturally into the two starting lanes before the rules dialogue.
- Voltorb hallway patrol now carries explicit 21-22 / y=7 bounds instead of inheriting an unbounded patrol record.

## 1.0.138
- Restored Voltorb to the hallway race-start position at (22,7); removed the incorrect forced relocation to (28,4) when accepting a race.
- Voltorb now patrols only the two-cell hallway segment at y=7 around the race start, and Ditto is staged at (22,6) without a visible Voltorb teleport.

## 1.0.137
- Rebuilt both minigame HUDs as literal in-game dialogue boxes: the same lower-screen 20x6 tile frame and the same two text baselines used by Gen1Recomp's TextBox.
- Removed the custom top-of-screen portrait/status-panel layout from the Voltorb race and Larvitar hide-and-seek HUDs.

## 1.0.136
- Moved Voltorb's idle patrol to the first demonstrated escort coordinate at (28,4), constrained to the adjacent hallway cells.
- Restored the literal scripted escort starting from that hallway point: (28,4) -> (25,4) -> (25,3) -> (20,3) -> (20,4) -> (19,4) -> (19,6) -> (22,6) -> (22,7).
- Ditto follows one command behind Voltorb during the escort; no waypoint routing or pathfinding is used.
- After a race, Voltorb returns to the new (28,4) patrol area.

## 1.0.135
- Removed the broken Voltorb follow/escort sequence entirely.
- Moved Voltorb's normal spawn to the race hallway start at (22,7) and made his idle patrol horizontal along the hallway.
- Accepting a race now resets Voltorb to (22,7) and Ditto to (22,6) directly, then starts the race; no pathfinding or escort collision is involved.

## 1.0.134
- Fixed Voltorb race crash by forward-declaring setActorCell before startVoltorbRace uses it.

## 1.0.133
- Replaced Voltorb waypoint/follower staging with a literal Gen-1-style lockstep movement script using the exact demonstrated route.
- Voltorb now runs one command ahead while Ditto executes the previous command simultaneously, preventing corner-cutting and pathfinder collision drift.

## 1.0.132
- Fixed Voltorb route testing on existing saves: stale post-race Voltorb positions are normalized back to his x=28 patrol lane before the screenshot route begins.
- Voltorb now resets to his normal (28,7) spawn after a race, preventing later attempts from starting from the hallway.
- Voltorb races are replayable after the first win; the MAGNET remains one-time and rematches use different dialogue.
- Kept the supplied screenshot checkpoint route, with deterministic cardinal leg expansion.

## 1.0.131
- Replaced Voltorb race staging with the exact user-supplied checkpoint route: (28,4) -> (25,4) -> (25,3) -> (20,3) -> (20,4) -> (19,4) -> (19,6) -> (22,6) -> (22,7).
- Voltorb and Ditto now traverse that route as collision-independent scripted lockstep, with Ditto always entering Voltorb's just-vacated tile.

## 1.0.130
- Rebuilt Voltorb's race escort around the same lockstep scripted-movement pattern used by the native Pewter/Oak-style follow sequences: Voltorb leads one tile, then Ditto steps into the exact tile he vacated; no BFS is used for either actor.
- Removed Pokopia's global dialogue reflow from the TextBox constructor so native Gen1Recomp pagination, page breaks, prompt waits, and continuation waits are preserved.
- Made the Voltorb MAGNET reward atomic by committing the race-win flag before granting the one-time item/reward dialogue.
- Larvitar now refuses hide-and-seek until Electrode has explicitly asked Ditto to cheer him up; after the first win Larvitar remains replayable with new rematch dialogue.
- Corrected Electrode's Mach Bike turn-state handling so mid-step direction changes are ignored until the current movement action completes, matching Emerald's `runningState == MOVING` rule; momentum-bearing turns then use TrySlowDown before re-accelerating.
- Fixed Spinarak's intended northwest-corner patrol bounds so it cannot drift below row 5.
- Audited minigame/fade state cleanup and retained the native Gen 1 Transition path for Larvitar start/find/timeout fades.

## 1.0.129
- Larvitar hide-and-seek now uses Gen1Recomp's native Gen 1 palette-staircase Transition when the round begins, when Larvitar is found, and when time expires.
- Finding Larvitar fades fully to black before Ditto and Larvitar are returned to their original positions, then fades back in before the result dialogue.
- Replaced the epilogue's hand-built alpha fades with the same native Transition used by standard map/building fades.

## 1.0.128
- Rebuilt Voltorb race staging as a strict one-tile follow-me trail: Voltorb never uses BFS/pathfinding, and Ditto follows each tile Voltorb vacates before the next lead step.
- Added deterministic final lane placement so the pair cannot weave around each other before the countdown.

## 1.0.127
- Replaced the compact minigame HUDs with full standard 20x6 Gen 1 dialogue-box chrome.
- Removed ELECTRODE from Gen 1 bicycle mode and made its transformed movement use only Emerald Mach Bike acceleration/coasting states.

## 1.0.126
- Moved both minigame HUDs to the engine post-composite `render.hud` seam so they render above the finished frame.
- Larvitar hiding now blacks out the finished game viewport until the hiding teleport completes.
- Electrode transformation now enters actual engine bicycle mode while retaining Emerald Mach Bike momentum states.

## 1.0.125
- Increased Larvitar hide-and-seek timer from 60 seconds to 1 minute 30 seconds.

## 1.0.124
- Fixed the Voltorb race and Larvitar hide-and-seek HUDs by drawing them through the active render.compose compositor hook.
- Kept hide-and-seek countdown updates exclusively on the fixed gameplay tick so rendering cannot alter timer speed.

## 1.0.123
- Fixed Voltorb race staging so Voltorb stays on the hallway lane instead of taking a wandering collision/pathfinding route while Ditto follows.
- Preserved normal collision during the race lead-in.

## 1.0.122
- Fixed Larvitar hide-and-seek so Larvitar physically runs through a room exit, warps to a collision-safe reachable hiding tile at least 10 squares away, and only then starts the 60-second timer.
- Moved the Voltorb race and Larvitar hide-and-seek overlays to the engine's final `render.hud` hook so their portraits, scores, and timer remain visible without blocking movement.
- Moved race AI and hide-and-seek countdowns to the fixed 60 Hz `input.step` hook.
- After the first Voltorb race loss, Electrode now gives Ditto a big-brother-style request to cheer up Larvitar.
- Beating Larvitar's hide-and-seek lets Electrode teach Ditto the ELECTRODE transformation, unlocked in the second transformation badge slot.
- ELECTRODE form now uses the pret/pokeemerald Mach Bike speed/momentum state math (Normal/Fast/Faster acceleration, slowdown/coasting, collision stop).

## 1.0.121
- Changed Voltorb race staging so Ditto follows directly behind Voltorb as a true follow-me sequence instead of taking a separate route.

## 1.0.121
- Changed Voltorb race staging into a true follow-me sequence: Voltorb leads one tile at a time and Ditto follows into his previous tile before he continues.
- Ditto still finishes at (22,6) beside Voltorb at (22,7) before the race rules are explained.

## 1.0.120
- Fixed Larvitar hide-and-seek startup crash by forward-declaring the route helper before the minigame code uses it.
- Patrol NPCs now wait when Ditto or another actor blocks their path instead of reversing/bouncing; they resume in the same direction when the tile clears.
- Spinarak now preserves its intended one-tile patrol direction while temporarily blocked by an actor.

## 1.0.119
- Fixed the Voltorb race crash caused by Lua helper declaration order.
- Restored Voltorb's original ambient racing observation before the race prompt.
- Moved Spinarak to the 3F northwest area around (2,2) with small random one-tile patrols that never pass x=5.
- Added repeatable Larvitar hide-and-seek with reachable collision-safe hiding spots at least 10 tiles away, a 60-second non-blocking HUD, timeout reset, and tsundere dialogue.

## 1.0.118
- Added Voltorb's repeatable 2F hallway race challenge.
- Accepting the race stages Voltorb at (22,7) and Ditto at (22,6) using collision-aware scripted movement.
- Race laps run between x=22 and x=10 on lanes y=7 (Voltorb) and y=6 (Ditto), first to three round trips.
- Added a non-blocking top-screen race score HUD with Ditto and Voltorb portraits.
- Voltorb briefly hesitates at randomized intervals during the race to give Ditto recovery opportunities.
- Winning awards the custom MAGNET item and permanently completes the challenge; losing allows unlimited rematches until victory.

## 1.0.117
- Fixed the title grass artwork so it fits the 160px title width with its original aspect ratio instead of being vertically stretched/compressed.
- Removed residual dark shadow/antialias pixels from the Conservation Project logo while preserving its bright green, pink, and white artwork.

## 1.0.116
- Replaced the Conservation Project title artwork with the latest supplied version.
- Preserved transparency by making the black canvas transparent while retaining the visible green, pink, and white artwork.
- Reduced the Conservation Project lockup by about 25% and moved it upward closer to the Pokopia logo.

## 1.0.115
- Replaced the Conservation Project title artwork with the newly supplied version.

## 1.0.114
- Replaced the Conservation Project title subtitle with the supplied pink-and-white artwork.
- Removed all black and dark pixels from that artwork so it overlays the title cleanly.

## 1.0.113
- Fixed the title subtitle rendering so the white outline no longer creates black mask rectangles.
- Changed POKEMON CONSERVATION PROJECT from two lines to three centered lines: POKEMON / CONSERVATION / PROJECT.
- Kept the original black Game Boy font with only the 2 px white outline.

## 1.0.112
- Restored the main-title `POKEMON CONSERVATION PROJECT` subtitle to its original black Game Boy font, weight, and placement.
- Kept only the requested 2px white outline; removed the random colors and faux-bold treatment from v1.0.111.

## 1.0.111
- Restyled the main-title `POKEMON CONSERVATION PROJECT` subtitle in bold, randomly assigned Pokopia-style colors.
- Added a 2px white outline around each subtitle glyph and protected the colored subtitle from palette remapping.

## 1.0.110
- Moved Larvitar seven tiles left in the 1F lobby, from (12,24) to (5,24).
- Preserved the existing player-acknowledged dialogue flow; dialogue callbacks continue only after the active text box is dismissed.

## 1.0.109

- Moved Ampharos on 2F to `(12,25)`, exactly 13 tiles below Vulpix at `(12,12)`.
- Moved Spinarak from B1F to 3F at `(6,10)`, immediately left of the stair tile at `(7,10)`.
- Updated Spinarak's ambient dialogue for its new stairwell location.

## 1.0.108

- Replaced Pokopia's PokePCFollowers runtime dependency with bundled non-shiny follower sheets from `randyadr/Gen2-3D-Sprites/assets/enhanced_overworld/poke_followers`.
- All currently used Pokémon overworld actors, including Pichu and Togepi, now use the bundled `follower_###_normal.png` art directly.
- Added the source repository's license/attribution notice to `THIRD_PARTY_LICENSES/` and documented the asset source in `CREDITS.md`.
- Imported the user-provided base portrait sets for Pokédex #152-#251 and extended the dialogue portrait registry through Celebi.
- Removed the obsolete PokePCFollowers dependency and the temporary Pichu/Togepi walker sheets.

## 1.0.107
- Replaced the B1F Squirtle with Totodile in the same emergency-firefighting role.
- Added Spinarak to a quiet B1F basement corner.
- Added Ampharos to the 2F east balcony as a glowing-tail beacon for boats offshore.
- Added Larvitar to the 1F lobby, where it keeps rubble out of the evacuation path.
- Added dialogue portrait art for Totodile, Spinarak, Ampharos, and Larvitar.

## 1.0.106
- Added an ambient Poliwhirl to Pokémon Mansion 1F.
- Added Slowpoke beside the cheese area on 2F.
- Added Dodrio to the top floor (3F).
- Added unique interaction dialogue and native cries for all three.

## 1.0.105
- Added Pichu and Togepi beside Weezing on Pokémon Mansion B1F as small Johto baby guests.
- Pichu and Togepi use self-contained Crystal-era sprite art and baby-like chirps using compatible Gen-I cry cues.
- Rewrote Muk's interaction so it focuses on plugging a leaking pipe instead of escorting smaller Pokémon.

## 1.0.104

- Restored the Rocket grunt dialogue to its original wording and line structure.

## 1.0.103

- Dialogue reflow now treats manual `\n` / `\v` line breaks as soft spacing within each authored page beat, then repacks text using the active font width.
- Text that fits naturally in two lines now uses both lines without leaving large gaps; longer text continues onto additional two-line pages only when needed.

## 1.0.102

- Dialogue pagination now hard-limits every visible page to two rendered lines.
- Gen I scrolling continuations and soft-wrapped third lines are converted into explicit page advances so text cannot visually skip.

## 1.0.101

### Dialogue portrait palette/layout polish
- Human trainer battler cutouts are now 2x and right-aligned to the live dialogue box edge rather than the screen edge.
- Pokemon dialogue portraits stay full-color only in ADVANCED; all other Gen I color modes reduce the portrait to four luminance shades and remap it through the active species/game palette, including inverted/classic modes.
- Portrait regions opt out of the later UI palette pass after their explicit remap, preventing double tinting.
- Speaker name tabs now size from the engine font's real pixel width, expand within the dialogue box width, and clip/truncate safely instead of overflowing.

## [1.0.100] - 2026-08-28

### Dialogue portrait asset-path fix
- Fixed Pokémon portrait loading to use the installed mod root (`mod.path`) plus the packaged portrait path, instead of treating `assets/portraits/...` as a game-root asset.
- Trainer-class dialogue sprites now render at 2x scale instead of 3x while remaining bottom-anchored and frameless.


## 1.0.99
- Dialogue trainer portraits now use the engine's native OakSpeech trainer resolver, so Giovanni, Super Nerd, Scientist, and Rocket portraits come from their actual extracted trainer battle assets rather than guessed asset paths.

## 1.0.98

- Reworked speaker presentation to remove the blue portrait-card treatment.
- Pokémon portraits now sit in one simple black rounded square with no nested/blue frame.
- Human trainer-class art now renders as an unframed 3x cutout anchored to the bottom-right of the screen behind the dialogue box.
- Speaker name tabs are monochrome rounded tabs.

## 1.0.97
- Fixed portrait loading to use the engine mod-aware image-data path instead of Assets.resolve for packaged portrait PNGs.
- Simplified the speaker nameplate to a single clean border; removed the nested frame that produced the odd blue-block appearance.
- Portrait frames are still only drawn after a portrait texture successfully loads.

## 1.0.96
- Moved speaker nameplate and portrait rendering onto each TextBox draw pass so visible dialogue always owns its UI metadata.
- Removed the unreliable global-compositor portrait rediscovery path.
- Preserved contextual Pokémon emotion assignments and Rattata overrides.

# 1.0.94

- Added base-form portrait sets for all 151 Generation I Pokémon.
- Only direct Pokédex-folder portrait assets are packaged; nested form folders (including 0000/0001) and caret-suffixed alternates are excluded.
- Added contextual automatic emotion selection for Pokémon dialogue, with per-line explicit emotion metadata taking precedence.
- Added automatic Normal fallback for species that do not provide a requested emotion.
- Preserved Rattata's authored per-line emotion overrides.

## 1.0.93
- Rebuilt dialogue presentation around speaker metadata: inline NAME: prefixes are stripped at runtime, a separate upper-left nameplate identifies the speaker, and portraits render upper-right.
- Replaced fragile top-stack-only portrait lookup with an explicit active-dialogue record while still preferring live TextBox metadata when available.
- Rattata expression portraits remain supported; human speakers can use native trainer-class battle portraits when available (Giovanni, Super Nerd, Scientist, Rocket).
- Giovanni source dialogue strings were not edited.

# 1.0.92

- Fixed dialogue portrait assets to load through the engine mod asset resolver instead of raw relative paths.
- Moved portrait rendering out of the Mansion-only effects branch so portrait-enabled textboxes render on every map.
- Rattata expression assignments and dialogue text are unchanged from 1.0.91.

# 1.0.91

- Added the complete supplied Rattata portrait set: Angry, Crying, Determined, Dizzy, Happy, Inspired, Joyous, Normal, Pain, Sad, Shouting, Sigh, Stunned, Surprised, Teary-Eyed, and Worried.
- Rattata dialogue now automatically selects portrait expressions from line context, with Normal as the fallback for future lines.
- Split multi-beat Rattata exchanges into separate textbox events where the emotional expression changes, allowing portraits to update naturally between beats.
- Rattata narration/interactions, cheese negotiation, distraction trigger, chase taunt, and FALSE SWIPE reaction are portrait-enabled.

## 1.0.90

- Added a data-driven dialogue portrait framework. Text boxes can now carry speaker/expression metadata, and each speaker can register multiple portrait variants.
- Added a native-style 40x40 portrait panel positioned above the standard dialogue box. The panel renders only when matching portrait art is registered, so this build contains no placeholder portrait images.
- Exposed `mod.pokopiaPortraits.register(speaker, expression, def)` for the later portrait-asset pass.

# Changelog

## 1.0.89

### Full dialogue polish
- Reworked dialogue throughout the mod except Giovanni's spoken lines, which remain unchanged from v1.0.88.
- Reflowed longer conversations into shorter Gen I-style textbox beats to reduce crowding and skipped text.
- Tightened character voices for Logan, Pixie, Rattata, Rockets, Scientists, Magneton, ambient Pokemon, and the Celadon prize sequence.
- Polished the intro Log 568 wording and Conservation Project briefing while preserving story content and event order.
- Updated duplicate scripted-interceptor lines so event-triggered dialogue matches the NPC dialogue pass.

## 1.0.88

### Cutscene focus, pre-PC pacing, and Scientist exit
- The epilogue camera now switches its explicit focus to Ditto before the Super Nerd begins walking away, and remains locked on Ditto throughout his exit.
- Polished Logan/PIXIE dialogue before the PC sequence into shorter, cleaner event-sized pages with more deliberate reaction beats.
- Giovanni's existing meeting/reply speech text is unchanged.
- The meeting Scientist no longer vanishes after a short fixed route; the script finds a reachable room warp, walks the Scientist fully to and through that exit, and removes the actor only after the last movement tile completes.
- Giovanni's reply is gated on the Scientist's completed room exit.

## 1.0.87

### Ditto reveal and epilogue framing
- The prize Porygon now appears in Ditto-purple immediately when it is released instead of changing palette later.
- The Nerd's hesitation is split into its own textbox; when the "Is my PORYGON sick?" question begins, the disguise drops to the actual Ditto overworld sprite and the Transform sound plays.
- After the Nerd exits, the camera hands off to Ditto and remains centered on it for the final beat.
- Reflowed the prize cutscene dialogue into shorter textbox pages to prevent crowded lines or skipped text.

## 1.0.86

### Prize event staging polish
- Removed the authored Prize Lady and Prize Worker overworld sprites; the prize counter staff remain background interactions like the original Gen I maps.
- Reworked the prize conversation into shorter scripted beats with timed pauses and Super Nerd facing changes that sell the off-screen attendants conferring.
- Added a brief impatient pacing animation while the prize is fetched, plus reaction turns around the handoff and punchline.
- The Super Nerd now visibly walks back toward the prize-room exit before the scene transition instead of cutting away at the counter.
- Map-change callbacks no longer begin dialogue or movement underneath the fade-in; each event waits until the destination room is fully visible.

## 1.0.85

### Center PC, Transform audio, epilogue staging
- Replaced the bogus whole-tileset PC sprite registration with a one-frame sprite derived from the actual vanilla Pokémon Center PC graphic in the player's imported cache.
- Transform now uses `Sound.playMove` so the Gen I Transform pitch/tempo modifiers are actually honored instead of being silently ignored by `Sound.play`.
- The Porygon-disguised Ditto reveal keeps the Porygon silhouette in the explicit Ditto-purple true-color bake and triggers the Transform move sound at the reveal.
- Prize Lady and Prize Worker are runtime actors at the prize counter so custom overworld pipelines include them in the cutscene.
- Authored scene changes now use the same four-step, 8-frames-per-step black palette fade cadence as building transitions, with a matching fade back in.


## [1.0.95] - 2026-08-27

### Active Pokémon dialogue portraits
- Wired portrait/nameplate detection to every Pokémon currently used as a dialogue speaker in the mod.
- Added support for Gen-I-style narrated Pokémon event text such as `VULPIX is trembling`, `PERSIAN used FALSE SWIPE!`, and `DITTO had an idea!`, not only `NAME:`-prefixed speech.
- PIXIE keeps the PIXIE nameplate while resolving portrait art and contextual expressions from VULPIX.
- Existing explicit Rattata expression assignments remain authoritative; other Pokémon continue to use contextual emotion inference with Normal fallback.
- Human trainer/battler portrait behavior is unchanged.

## [1.0.84] - 2026-08-27

### PC, Transform SFX, Porygon reveal, prize room, transitions
- Removed the fabricated PC artwork. The B1F terminal now draws from the base game's extracted Pokémon Center tileset.
- Fixed Transform SFX logic: the previous form is now captured before applying the new form, so the sound actually triggers.
- Uses Gen I's exact TRANSFORM move sound mapping: `SFX_FAINT_FALL` with pitch `$ff` and tempo `$ff`.
- Fixed the epilogue crash (`NPC.lua:595 ... draw nil`) caused by replacing `NPC.sprite` with the string `DITTO`; NPC sprites remain real SpriteRenderer objects.
- The apparent PORYGON is now visibly rendered in Ditto purple when its disguise breaks.
- The Nerd now says: "Uhh... Is my PORYGON sick?" immediately before that transformation.
- Added visible Prize Lady and Prize Worker actors at the Game Corner prize counter during their conversation.
- Added fade-to-black / fade-from-black transitions around authored map changes between the Celadon/Game Corner/Department Store cutscenes.
- Removed the obsolete custom PC PNG from Pokopia.


## [1.0.83] - 2026-08-27

### Exact PokePCFollowers asset compatibility
- Removed Pokopia's runtime rewriting/derived copies of PokePCFollowers sprite sheets.
- Pokopia now consumes the dependency's exported `assetPath(species)` directly, exactly as PokePCFollowers does.
- Custom Pokémon records now match the follower pack's six-frame 16x96 walker geometry and use the source PNG's real alpha.
- Enabled true-color rendering for these source follower sheets so SpriteRenderer does not erase light-colored pixels inside the Pokémon as OBJ color 0.
- The uploaded follower pack's PNGs were verified to already contain real transparent backgrounds, so no additional alpha processing is needed.
- Changed the custom PC terminal to use a direct `mod.path` asset path, matching the asset-loading pattern used by PokePCFollowers itself.
- Removed the broken generated/derived asset path from the live follower path.


## [1.0.82] - 2026-08-27

### Missing PC and follower sprite fix
- Fixed the Pokémon Center PC terminal asset path. The PC now uses the engine's normal `assets/generated/...` mod-override resolution path, so its custom sprite can actually be loaded from the Pokopia mod.
- Fixed the processed follower sprite path. Runtime alpha-corrected follower sheets are now written to this mod's `save/mod-derived` tree and referenced through `assets/generated/...`, which is the path shape `Assets.resolve` supports.
- This restores Ditto and the Mansion follower Pokémon while keeping the exterior-only transparency processing and normal in-game palette handling from v1.0.80.
- No follower source artwork is bundled into Pokopia; the processed sheets are still derived at runtime from the installed follower dependency.


## [1.0.81] - 2026-08-27

### Startup crash fix
- Fixed the mod-manager crash caused by calling the nonexistent sprite-registry method `:set()`.
- The Pokémon Center PC terminal now uses the supported `mod.content.sprites:register()` API.
- No story, transformation, palette, or dialogue behavior was otherwise changed.


## [1.0.80] - 2026-08-27

### Transform SFX, Logan text, follower alpha/palette
- Successful form changes now play the generated battle-move sound effect for TRANSFORM.
- Reworded Logan's opening line from "The PC is still online." to "The Conservation Project has now launched..."
- Fixed follower-sheet transparency so only the edge-connected outside/background is transparent.
- Light pixels enclosed inside a Pokemon's outline remain opaque rather than becoming holes.
- External PokePCFollowers art is still resolved from the dependency at runtime; it is not bundled into Pokopia.
- Runtime-derived follower sheets remain on SpriteRenderer's normal OBJ palette path (`trueColor=false`), so the current game palette is retained and changing COLORS in the in-game menu is respected.
- Ditto-purple transformed forms now use the same exterior-only alpha rule, preventing transparent holes inside the transformed Pokemon.


## [1.0.79] - 2026-08-27

### PC terminal sprite
- Replaced the temporary Poké Ball visual used for the B1F PC with a dedicated stationary Pokémon Center-style PC terminal sprite.
- The PC retains the same inactive/active dialogue and story gating.


## [1.0.78] - 2026-08-27

### Pixie quest sequencing and PC state
- PIXIE dialogue/quest progression is now locked behind both required story events: the PERSIAN distraction sequence must be complete and Giovanni must have finished his full speech.
- LOGAN no longer appears in Mansion B1F before those two prerequisites are complete.
- This also means LOGAN cannot appear while Giovanni's scientist is still in the meeting; the scientist leaves before Giovanni's speech, and Giovanni's completion flag is set only after the speech finishes.
- Added a PC box immediately beside LOGAN's eventual B1F position.
- Before the prerequisites are complete, interacting with the PC says: "The PC is inactive."
- Once LOGAN is eligible to appear, interacting with the same PC says: "The PC is active."
- Added a defensive prerequisite check inside LOGAN's dialogue so older saves cannot accidentally start the PIXIE quest early.


## [1.0.77] - 2026-08-27

### Transformation cursor polish
- Replaced the rectangular selection outlines with small Gen1-style arrow cursors beside the hovered Ditto/form slot.
- Hovering a transformation no longer changes the large battle portrait.
- The upper-right battle sprite now always shows the currently active transformation in Ditto purple.
- Pressing A applies the hovered form; only then does the battle portrait change to that form.
- The hovered form name still appears in the FORM line so you can see what A will select.


## [1.0.76] - 2026-08-27

### Badge-style Transformations screen
- Replaced the temporary text-list transformation picker with a selectable Trainer Card / Badge-layout transformation screen.
- Reuses the engine's real Trainer Card frame geometry and original 4x2 badge-grid placement.
- BADGES is replaced by TRANSFORMATIONS.
- MONEY is replaced by FORM and displays the transformation currently under the cursor.
- The upper-right trainer portrait is now a selectable front battle sprite preview. Hovering DITTO and pressing A returns to DITTO.
- Hovering a transformation icon changes the upper-right battle preview to that Pokemon in Ditto's purple palette.
- Transformation slots use the Pokemon's overworld stand sprite in the original badge positions.
- Known but unearned transformation sprites render dark gray and cannot be selected.
- Pressing A on an earned transformation applies it and closes the screen; B cancels.
- PERSIAN is currently the only defined transformation slot.
- The early PERSIAN transformation is temporary: when the scientist puts DITTO into the PC, PERSIAN is removed from the learned-form set and DITTO is restored.
- The slot system remains ready for PERSIAN or other forms to be learned again later.


## [1.0.75] - 2026-08-27

### Title grass fit
- Removed the repeated 24x24 grass tiling.
- The green texture is now drawn once and fitted across the complete 160-pixel screen width.
- It is also fitted to the existing lower area from y=80 through y=144.
- Sky, clouds, logo, Ditto animation, text, and music are unchanged.


## [1.0.74] - 2026-08-27

### Pokopia logo cleanup
- Removed exterior black and near-black fringe pixels around the true-color Pokopia logo.
- Cleanup is restricted to dark pixels connected to transparent/outside space, preserving enclosed logo details.
- Re-trimmed the alpha bounds after cleanup.
- Title layout, Ditto animation, grass, clouds, and MIDI theme are unchanged.


## [1.0.73] - 2026-08-27

### MIDI event syntax fix
- Fixed the new mod-manager error `channel 1 event 157: no command in event`.
- v1.0.72 correctly split the 17-step MIDI note, but the generated Lua used `{{note=...}}` around split notes.
- That created an extra anonymous table layer, which ChipAsm interpreted as an event containing no command.
- Flattened all split MIDI notes back to valid `{note=...,len=...}` ChipAsm events.
- Validated every converted note and rest is now a direct command event with a legal length from 1 through 16.


## [1.0.72] - 2026-08-27

### MIDI title-theme crash fix
- Fixed the mod-manager error `channel 1 event 157: len out of range 1-16: 17`.
- ChipAsm only accepts individual note/rest lengths from 1 through 16.
- Long events produced by the MIDI conversion are now split into legal 16-step-or-shorter events.
- The supplied Pokopia MIDI remains the title theme; its pitch sequence and total timing are preserved.


## [1.0.71] - 2026-08-27

### New title theme
- Removed the Bicycle/Credits mashup entirely.
- Replaced it with the user-supplied `Pokopia theme MIDI.mid`.
- Converted all 478 MIDI notes into three synchronized Game Boy music channels.
- Preserved the MIDI's original 120 BPM tempo and rhythmic timing.
- The source MIDI has a maximum polyphony of three, so no pitched notes had to be dropped for the three available pitched Game Boy channels.
- All three converted channels share the same loop boundary so they remain synchronized.
- Packaged the original MIDI in the mod assets for reference.


## [1.0.70] - 2026-08-27

### Title Ditto size
- Doubled the animated title DITTO battler scale from 0.58x to 1.16x.
- Movement paths, timing, bounce, squash/stretch, purple palette, and random path behavior are unchanged.


## [1.0.69] - 2026-08-27

### Ditto / title logo fixes
- DITTO no longer depends on TitleState's native `currentSprite()` cycle to exist.
- The mod now loads DITTO's front battler sprite directly through `src.pokemon.Sprites.path(..., "front", {kind="title"})`, matching the engine's own title sprite lookup.
- The custom moving DITTO actor uses that direct battler image, so native title-cycle suppression cannot make DITTO disappear.
- Replaced the grayscale `pokopia_logo_dmg.png` title asset with the original full-color Pokopia logo supplied earlier.
- Converted the logo's black canvas to transparency and packaged it as `pokopia_logo_truecolor.png`.
- The logo is still marked true-color after drawing so emulator palette remapping does not desaturate it.


## [1.0.68] - 2026-08-27

### Title startup crash fix
- Fixed line 636 crash caused by calling `mod:path(...)`; this runtime exposes `mod.path` as a string rather than a method.
- Grass now loads from the same explicit mod asset path convention used by the logo, sky, and clouds.
- Moved grass loading outside the cloud-success branch so the two title assets initialize independently.
- Retains the outline-free cloud image from v1.0.67.


## [1.0.67] - 2026-08-27

### Title clouds
- Removed the black/dark outline pixels from the animated cloud image.
- Preserved the white and pale-blue cloud shading.
- Re-trimmed the cloud sheet after clearing the outline so looping placement stays compact.


## [1.0.66] - 2026-08-27

### Title grass and Ditto animation root fixes
- Fixed the grass layer from v1.0.65: the draw code existed, but the grass image variable was never declared or loaded, so the entire block was always skipped.
- The supplied green grass tile is now explicitly loaded as `pokopiaGrassTile` and drawn only below y=80.
- Fixed the frozen DITTO animation: this engine's TitleState update callback does not provide numeric frame delta as the second argument, so the previous `tonumber(dt) or 0` logic advanced by zero every frame.
- Removed the custom TitleState update wrapper entirely.
- DITTO now advances from `love.timer.getTime()` in the draw routine, using the same proven real-time approach as the moving cloud layer.
- Path state remains stored on TitleState, so paths persist and randomize correctly while real elapsed time drives movement and squash/stretch.


## [1.0.65] - 2026-08-27

### Grass lower title section
- Added the supplied green pixel texture as a tiled grass floor.
- Grass begins exactly at the existing title split at y=80 and is clipped to the lower 64 pixels.
- The sky and cloud region above y=80 remains untouched.
- The large source image is reduced into a small nearest-neighbor pixel tile and repeated across the bottom.
- Grass is true-color masked when supported so the green does not inherit the sky/Game Boy palette.
- DITTO remains rendered above the grass.


## [1.0.64] - 2026-08-27

### Ditto path-state fix
- Moved title DITTO path progression out of the draw routine and into `TitleState.update`.
- DITTO's current path, elapsed path time, wait time, and animation clock now live on the TitleState instance instead of transient draw-local variables.
- Native title sprite/cycle activity can no longer restart DITTO at the beginning of the left-to-right entrance.
- A path must now reach its own completion condition before the next random path is selected.
- Successive paths still cannot repeat.
- Squash/stretch and special path deformation now use the persistent path timer, so they can progress beyond their opening frames.


## [1.0.63] - 2026-08-27

### Ditto title animation correction
- Fixed randomized movement so DITTO cannot select the same path twice in succession.
- Reworked all six routines to be visually distinct instead of mostly horizontal variants.
- Added a reverse-direction hop path, large wave path, stop-and-wobble path, retreat-and-sprint path, and a puddle/spring gag.
- Increased normal squash/stretch from barely perceptible deformation to roughly 12–14%.
- Special paths now exaggerate deformation: DITTO can flatten to 148% width / 58% height and spring to 82% width / 130% height.
- Increased walking bob so the battler sprite visibly breathes and bounces while moving.
- DITTO remains confined to the bottom title band.


## [1.0.62] - 2026-08-27

### Animated title Ditto
- Removed the rotating/flashing title Pokemon roster. DITTO is now the only title Pokemon.
- Uses DITTO's battler sprite rather than an overworld follower sprite.
- Native TitleState Pokemon drawing is suppressed and replaced by one persistent custom DITTO actor.
- DITTO randomly selects from six bottom-screen movement routines: left/right crossings, pauses and direction changes, a low zig-zag, backtracking, and playful hopping paths.
- DITTO is confined to the lower title band and never enters the Pokopia logo or Conservation Project text area.
- Added subtle continuous vertical bob plus inverse squash/stretch morphing to make the battler sprite feel soft and alive while it moves.
- Applies the same four-shade Ditto-purple ramp used by the mod's transformed sprites.
- DITTO's purple sprite is true-color masked when supported so emulator palette changes do not erase the purple.
- Each completed movement path is followed by a short randomized delay and a newly selected path.


## [1.0.61] - 2026-08-27

### Bicycle + Credits title arrangement
- Removed all Route 1 accompaniment channels.
- Bicycle Ch2 remains the sole melody at tempo 144.
- Added accompaniment sourced from pret/pokered `audio/music/credits.asm`: Credits Ch1 pulse material plus Credits Ch3's actual arpeggio figures.
- Retained the standard Credits pulse/wave channel timbres.
- Transposed the pitched Credits material from its A-major center to C-major so it harmonizes with the Bicycle melody.
- Both accompaniment channels start on the same tick as Bicycle and run from the same ChipAsm tempo clock.


## [1.0.60] - 2026-08-27

### Pokopia logo color
- The Pokopia title logo now requests true-color rendering when the runtime exposes `PaletteFX.markTrueColor`.
- The true-color mask is limited to the logo's exact on-screen rectangle.
- If true-color masking is unavailable, the logo still renders normally through the existing palette path.
- Title background, clouds, Pokemon, and game-font text behavior are unchanged.


## [1.0.59] - 2026-08-27

### Bicycle + Route 1 title arrangement
- Bicycle Ch2 is the sole melody.
- Replaced Credits accompaniment with Route 1 Ch1, Ch3, and Ch4.
- Preserved Route 1's normal channel timbres and rhythms.
- Set the combined song to tempo 144.
- Transposed Route 1's pitched accompaniment down two semitones to fit the Bicycle melody's harmonic center.
- All channels start on the same song clock.


## [1.0.58] - 2026-08-27

### Title mashup synchronization
- Restored the stock Bicycle lead pulse-channel timbre instead of the custom duty/note-type modifications.
- Restored the stock Credits Ch3 wave-channel timbre (`note_type 12, 1, 0`) instead of forcing it through a square-channel voice.
- Removed the Credits theme's standalone opening phrase and long rest from the mashup accompaniment. Those occurred before its accompaniment section and made the two parts sound like they entered at different times.
- Bicycle melody and the actual Credits accompaniment body now begin their repeating material on the same tick.
- Both channels share the title song's single tempo clock, preventing independent playback drift.


## [1.0.57] - 2026-08-27

### Actual Credits accompaniment
- Removed the abbreviated hand-written Credits approximation.
- The accompaniment now uses the actual `Music_Credits_Ch3` note/rest/call sequence from pret/pokered, including all eight original subroutines.
- Kept the Bicycle lead melody as the only Bicycle-derived melodic channel.
- Credits accompaniment is rendered on square channel 2 using the requested `duty_cycle 2`, `note_type 12,13,2`, and `vibrato 6,1,2` timbre so it is clearly audible.
- The Credits accompaniment loops from its real beginning while the title remains open.


## [1.0.56] - 2026-08-27

### Title accompaniment voice
- Kept the Bicycle lead melody unchanged.
- Changed the pulse accompaniment voice to the requested `duty_cycle 2`.
- Set accompaniment `note_type` to `12, 13, 2`.
- Set accompaniment vibrato to `6, 1, 2`.
- Starts the accompaniment in octave 2.
- The mashup remains restricted to the Pokopia logo/title screen.


## [1.0.55] - 2026-08-27

### Title music timing
- Fixed the custom Bicycle/Credits mashup replacing the preceding intro music.
- Removed mashup playback from the `TitleState` constructor because that state is created during the transition into the title.
- The mashup now starts on the first actual Pokopia logo/title-screen draw.
- The intro retains its normal music; only the logo/title menu uses `Music_PokopiaTitleMashup`.


## [1.0.54] - 2026-08-27

### Title music correction
- Removed the extra Bicycle harmony/melodic channel and Bicycle percussion from the custom title cue.
- The title now has one Bicycle melodic voice only.
- All supporting voices are Credits-derived accompaniment patterns.
- Keeps the custom song synchronized as a single native ChipAsm track.


## [1.0.53] - 2026-08-27

### Custom title music
- Added `Music_PokopiaTitleMashup` as a native four-channel ChipAsm song.
- The square channels carry a Bicycle-theme arrangement.
- The wave channel uses a Credits-inspired broken-chord accompaniment.
- Added a light noise-channel rhythm so the title cue is a single synchronized chip arrangement rather than two songs playing over one another.
- The title screen now plays this custom registered song directly.


## [1.0.52] - 2026-08-27

### Title music
- Replaced the title-screen theme with the game's Bicycle theme.
- Uses Gen1Recomp's `Music.special(game.data, "bike")` role lookup; for Gen I this resolves to `Music_BikeRiding`.
- The Bicycle theme loops on the title screen.


## [1.0.51] - 2026-08-27

### NPC draw crash
- Removed the unsafe TitleState asset mutations introduced by the title cleanup.
- The mod no longer sets engine-owned logo/version/copyright image fields to nil.
- Native title elements remain suppressed only inside the temporary title-screen draw wrappers.
- This prevents title-screen state changes from leaking into overworld rendering and causing `NPC.lua:595` to call `draw` on a nil sprite/image object.
- Keeps the Scientist removed, Pokemon centered, and smooth time-based cloud drift from v1.0.50.


## [1.0.50] - 2026-08-27

### Title composition
- Removed the Scientist portrait from the title screen.
- Centered the animated Pokemon horizontally in the lower half.
- Changed cloud scrolling from fixed per-frame stepping to delta-time movement for smoother motion.
- Clouds continue to drift left slowly and loop seamlessly.


## [1.0.49] - 2026-08-27

### Animated title clouds
- Added the supplied cloud artwork over the blue sky and behind the Pokopia logo.
- Converted the cloud sheet's edge-connected black canvas to transparency.
- Clouds drift slowly to the left.
- A second wrapped copy is drawn so the cloud field loops continuously across the screen.
- Cloud colors remain true-color like the sky.


## [1.0.48] - 2026-08-27

### Title background
- Replaced the green patterned title background with the supplied blue sky image.
- Resized the image to the full 160x144 Game Boy title canvas.
- Marked the background true-color so its blue gradient displays as supplied instead of being remapped through the emulator palette.
- The upper-title repaint uses the same sky image, preventing native title remnants from showing through.


## [1.0.47] - 2026-08-27

### Real Game Boy title font
- Replaced LÖVE `print()` title text with Gen1Recomp's real `src.render.Font.draw()` renderer.
- `POKEMON CONSERVATION` now uses the actual extracted 8px Game Boy glyphs and spans the 160px canvas exactly.
- `PROJECT` is centered beneath it.
- `2026 Logie` also uses the real game font.
- Disabled TitleState's native logo, version ribbon, copyright image, copyright quads, and Game Freak Inc. image at the state level so `UNDERdecodedHD` cannot remain behind the replacement.


## [1.0.46] - 2026-08-27

### Title text / footer
- Forced `POKEMON CONSERVATION / PROJECT` to render in black.
- Forced `2026 Logie` to render in black.
- Strengthened suppression of the native `UNDERdecodedHD` footer so `Logie` fully replaces it rather than appearing alongside it.


## [1.0.45] - 2026-08-27

### Title cleanup
- Fixed stock title fragments bleeding through behind the Pokopia title.
- The upper 80 pixels are repainted from the palette-aware Pokopia background after native TitleState finishes drawing.
- Native title text in the upper region is suppressed completely.
- Reduced/repositioned the Pokopia logo and placed the game-font `POKEMON CONSERVATION / PROJECT` subtitle cleanly beneath it.
- Kept `2026 Logie` as the footer.


## [1.0.44] - 2026-08-27

### Title subtitle
- Removed the custom Conservation Project image.
- Restored `POKEMON CONSERVATION PROJECT` as text rendered with the game's own font beneath the Pokopia logo.
- Kept the custom `2026 Logie` footer.


## [1.0.43] - 2026-08-27

### Title footer
- Suppressed the native `2026 UNDERdecodedHD` title footer.
- Added `2026 Logie` in its place using the game's title font.


## [1.0.42] - 2026-08-27

### Native title artwork suppression
- Removed the stock Pokemon title logo instead of drawing the Pokopia artwork over it.
- Removed the stock BLUE/version artwork and added text suppression as a fallback.
- Native upper-title image draws are filtered before `TitleState` renders them.
- The animated title Pokemon is preserved and still renders at the intended reduced size.
- Pokopia's custom logo and Conservation Project artwork are drawn afterward on a clean title background.


## [1.0.41] - 2026-08-27

### Title subtitle artwork
- Replaced the two-line rendered `POKEMON CONSERVATION / PROJECT` text with the supplied pixel-lettering image.
- Cropped the supplied image exactly to the occupied lettering pixels.
- Converted its white and near-white JPEG background to full alpha transparency.
- Normalized the lettering to the dark DMG shade and kept it palette-aware.
- Uses nearest-neighbor filtering on the title artwork.


## [1.0.40] - 2026-08-27

### Title screen palette / transparency
- Made the logo's edge-connected black empty canvas transparent while preserving enclosed black logo details.
- Converted the green title pattern to DMG grayscale palette indices.
- Removed the title background's `markTrueColor` call so the active emulator/title palette now recolors the background together with the rest of the title screen.
- The logo remains palette-aware rather than true-color.


## [1.0.39] - 2026-08-25

### Persian dialogue
- Changed Giovanni's gendered reference to PERSIAN to gender-neutral language.
- PERSIAN is now referred to as `it` rather than `he`.


## [1.0.38] - 2026-08-25

### Pokopia sprite alpha fix
- Fixed Pokopia's own custom Pokemon sprites rendering with white 16x16 boxes.
- Cause: every `POKOPIA_*` follower sprite was registered with `trueColor=true`, bypassing Gen1Recomp's normal OBJ/background-key rendering.
- All ordinary Pokopia Pokemon sprites now use `trueColor=false`, so the engine keys the sheet background correctly.
- The setting is enforced again after the follower image paths are installed during `game.ready`.
- The transformed purple PERSIAN remains a separate true-color renderer because that image is manually alpha-keyed and recolored.


## [1.0.37] - 2026-08-25

### Transformed sprite alpha
- Fixed the white rectangular background around transformed overworld sprites.
- The white source-sheet background key now becomes alpha in the custom true-color transformed image.
- Existing transparent pixels remain transparent.
- The three visible Persian sprite shades remain fully opaque and use the Ditto-purple ramp.


## [1.0.36] - 2026-08-25

### Giovanni meeting
- Talking to Giovanni or the meeting scientist now starts one shared one-shot conversation.
- The scientist delivers the Pokemon Conservation Project briefing in short text pages.
- After finishing the briefing, the scientist physically walks out of the meeting room and is removed.
- Giovanni then gives the requested response about abandoning Earth, recognizing that DITTO is impersonating PERSIAN, the ear-twitch tell, PERSIAN playing with RATTATA, and his promise to save every Pokemon.
- `giovanniMeetingDone` persists in save data; after the scene the scientist stays gone across floor reloads and saves.
- Re-talking to Giovanni after the scene gives a short version of his final promise.


## [1.0.35] - 2026-08-25

### Rattata / Persian persistence
- Fixed the apparent reset after the distraction.
- Cause: 1F's static population table recreated the original RATTATA and Giovanni's PERSIAN every time the floor loaded, even though the live chase had removed them.
- Once `distractionDone` is saved, every 1F load now removes those original population actors immediately. They have permanently left 1F.
- The later basement `RATTATA_ARGUMENT` / `PERSIAN_ARGUMENT` pair is now the only persistent post-chase pair.
- If one member of the basement pair is ever missing, both are rebuilt together from the same saved `argumentPositions` record instead of regenerating a new location.
- Post-FALSE-SWIPE argument coordinates remain locked and the pair is excluded from generic wandering/patrol behavior.


## [1.0.34] - 2026-08-25

### PERSIAN transform opacity
- Removed the white-to-transparent conversion from the transformed PERSIAN sprite.
- The source sprite's alpha is now preserved exactly.
- All four grayscale shades are recolored into a Ditto-purple ramp, including the lightest shade.
- The transform no longer creates transparency as part of recoloring.


## [1.0.33] - 2026-08-25

### PERSIAN transform compatibility
- Fixed the crash caused by `SpriteRenderer:setObjPalette` not existing in the runtime build.
- Removed the runtime dependency on that method.
- PERSIAN's follower sheet is now recolored directly into a Ditto-purple image.
- White background pixels are made transparent; the remaining three shades are remapped to a purple Ditto ramp.
- The transformed renderer is marked true-color so the purple Persian sprite displays as baked.


## [1.0.32] - 2026-08-25

### PERSIAN transform now applies immediately
- Fixed the transform selection doing nothing.
- `activeOverworld` and `applyDittoForm` are now forward-declared before the transform menu, so the menu callback can legally call the later local implementations.
- Selecting PERSIAN immediately finds the actual overworld state beneath the START menu and replaces the player's SpriteRenderer with the PERSIAN renderer.
- No manual stack pop is used; Gen1Recomp's Menu still owns menu closure.
- `requestedForm` remains as a fallback for warps/player rebuilds.
- Updated the transformed PERSIAN OBJ palette to a stronger Ditto-purple four-shade ramp.


## [1.0.31] - 2026-08-25

### Transform white-screen fix
- Fixed the white screen after choosing DITTO/PERSIAN.
- Cause: the transform callback manually popped the menu even though `Menu:update()` already pops non-`keepOpen` items before invoking `onSelect`.
- That double-pop removed the overworld state.
- Removed the manual stack pop and explicitly left both transform rows as normal auto-closing menu entries.
- The selected form still persists through `currentForm`/`requestedForm` and is applied by the live overworld update path.


## [1.0.30] - 2026-08-25

### Transform menu crash
- Fixed `activeOverworld` nil at transform selection.
- The START-menu callback no longer calls later local functions out of lexical scope.
- Selecting a form now saves `currentForm` and `requestedForm`, closes the menu, and the existing live-overworld update path applies the sprite on the next frame.
- Form persistence across saves and warps remains intact.


## [1.0.29] - 2026-08-25

### Transform selection
- PERSIAN/DITTO selection now writes `currentForm` immediately, closes the transform menu, resolves the live overworld, and applies the selected sprite directly.
- `requestedForm` remains as a fallback for map/player rebuilds.
- The selected form therefore persists even if an immediate sprite rebuild is unavailable.

### Basement Rattata / Persian population
- Removed the spawn-time writeback that could overwrite the saved argument coordinates with newly populated entity positions.
- After FALSE SWIPE / the Persian lesson, every B1F load hard-restores Rattata and Persian to their exact saved cells and facings after generic NPC sanitization.
- Both argument NPCs are frozen at those persistent post-scene positions so patrol/population logic cannot move them.


## [1.0.28] - 2026-08-25

### Logan / Persian dialogue
- Logan now scolds PERSIAN for bothering the lab Pokemon.
- He acknowledges PERSIAN as the boss's Pokemon and tells PERSIAN to apologize to RATTY.
- This dialogue does not advance the Ditto/Pixie quest.


## [1.0.27] - 2026-08-25

### Persian identity
- Logan now checks Ditto's active saved form before any PC-ending quest dialogue.
- If transformed as PERSIAN, Logan does not recognize the player as Ditto and instead treats them as Giovanni's Persian.
- Talking to Logan as PERSIAN does not advance or alter the Ditto/Pixie quest state.

### Persian movement speed
- Added a `movement.speed` hook for the PERSIAN form.
- PERSIAN moves at 1.5x Ditto's normal overworld speed by reducing per-tile movement frames by a factor of 1.5.
- Returning to DITTO automatically restores normal movement speed.


## [1.0.26] - 2026-08-25

### Persistent Rattata / Persian state
- All story progression continues to live under `save.modData.pokopia_log568`, which is part of the normal playthrough save.
- Added state normalization/migration so completed distraction and Persian-learning flags restore their dependent state after loading an older save.
- Basement Rattata/Persian positions, facings, and locked-position marker are now explicitly stored in the save.
- The exact live pair coordinates are rewritten after spawning and after the FALSE SWIPE / transformation-learning scene.
- Revisiting B1F restores the pair from those saved cells instead of recomputing placement.
- Once the lesson is complete, talking to either one keeps the same saved positions and only says to leave them alone.

### PERSIAN transformation
- Fixed the transform applying to `game.overworld`, which Gen1Recomp uses as the OverworldController class rather than necessarily the live map state.
- Transformation now resolves the actual live overworld from the state stack and applies directly to that Player object.
- PERSIAN selection is reapplied after map/player rebuilds and persists through `q.currentForm`.
- Persian uses its own sprite geometry with an explicit Ditto-purple OBJ palette.
- The palette is baked through SpriteRenderer's supported `setObjPalette` path with a new cache key.


## [1.0.25] - 2026-08-25

### Input compatibility after Rattata/Persian chase
- Kept the fix entirely inside Pokopia; no external touch-control mod files or APIs are referenced.
- Added one generic `restorePlayerInput` cleanup using only Gen1Recomp core services.
- Chase completion now clears player lock/frozen/movement-target state and stale overworld emotes.
- It calls Gen1Recomp `TouchControls:reset()` to release overlay-held buttons whose release event may have been lost while the cutscene owned input.
- It then calls core `Input:reset()` and `Input:reconcile()` so physical keyboard/gamepad holds are reconstructed from actual hardware state.
- The same cleanup is used for authoritative chase completion, stale-distraction recovery, and completed-save recovery.


## [1.0.24] - 2026-08-24

### Fixed MAGNETON shutdown effect
- Found a Lua lexical-scope bug: `magnetonTalk` was defined before `magnetonSurgeFrames`, `magnetonSurgeDone`, and `magnetonSurgeOw`.
- The dialogue callback was therefore writing globals while the render hook was reading separate locals, so the flash/shake countdown never started.
- Moved the surge-state locals above `magnetonTalk`; the dialogue and render hook now share the same state.
- Removed the one-second player input lock entirely. The visual effect can no longer strand Ditto's controls.
- The effect start and completion both defensively clear stale `inputLocked` / `frozen` state from older broken runs.
- Thunder Wave sound, one-second flashing, and one-second screen shake remain enabled.


## [1.0.23] - 2026-08-24

### MAGNETON interaction fix
- Fixed MAGNETON becoming non-interactive.
- Cause: `COMMON.TEXT_MAGNETON` referenced `magnetonTalk` before that local function was declared, so Lua stored nil.
- The dynamic MAGNETON handler is now attached inside `talkFor`, after the function exists.
- MAGNEMITE's original interaction is left intact.

### Alarm shutdown effect
- Choosing YES now plays the Gen I Thunder Wave move sound.
- The screen flashes and shakes for 60 frames (one second).
- The alarm is stopped as the electrical surge begins.
- Ditto is held only for the one-second effect and control is explicitly restored before MAGNETON's final dialogue.


## [1.0.22] - 2026-08-24

### Rebuilt post-chase completion
- Reviewed the entire Rattata/Persian distraction lock flow.
- The real problem was cutscene completion waiting for Persian's trailing queue after Rattata had already visibly finished escaping.
- Rattata reaching the end of its validated escape route is now the authoritative end of the cutscene.
- At that exact point the chase runtime state is destroyed and the normal distraction `finish()` callback runs immediately.
- Removed the old 90-frame unlock timeout and the `rattataFinished` / Persian-tail completion gate.
- Final cleanup clears `ow.emote`, `inputLocked`, `frozen`, leftover player movement targets, Rattata follower state and both chase runtime tables.
- Completed saves also clear stale runtime chase/emote/input locks whenever a Mansion floor loads.


## [1.0.21] - 2026-08-24

### MAGNETON alarm control
- Talking to MAGNETON now presents the agreed `Disrupt the alarm?` YES/NO interaction.
- YES plays the magnetic-pulse dialogue, stops both the custom Pokopia alarm source and the engine Low Health Alarm loop, and saves `alarmDisabled=true`.
- The disabled state persists across Mansion floor changes and reloads.
- Talking to MAGNETON afterward gives its proud follow-up dialogue.
- NO leaves the alarm running and gives the magnets-slow-down response.


## [1.0.20] - 2026-08-24

### Fixed post-chase movement lock
- Found the post-chase guard interceptor was able to immediately retrigger its trainer-style emote after `distractionDone` became true.
- The post-chase guard is now temporarily disarmed until Ditto successfully steps away from the original (9,2) interceptor tile.
- Once Ditto has moved away, returning to the guard arms the normal post-chase dialogue again.
- Chase cleanup now explicitly clears any stale `ow.emote`, `inputLocked`, and `frozen` state.
- Existing completed saves initialize the new post-chase guard latch safely.


## [1.0.19] - 2026-08-24

### Title subtitle
- The native version label is now suppressed during TitleState rendering.
- `POKEMON CONSERVATION PROJECT` is drawn in the version label's place after native title rendering, rather than being drawn over the version.


## [1.0.18] - 2026-08-24

### Rattata distraction retrigger fix
- Fixed Ditto regaining control for a couple of steps and then being locked again.
- Added a persistent `distractionCommitted` one-shot latch the instant Rattata says `Stand back, kid.`
- The four-tile proximity trigger cannot fire again once that latch is set.
- Existing completed saves automatically mark the distraction as committed.
- Stale `distractionStarted` recovery still unlocks Ditto without clearing the one-shot latch.


## [1.0.17] - 2026-08-24

### Player control recovery
- Player control now returns immediately when Rattata's scripted escape route ends.
- Added a 90-frame failsafe that clears both `inputLocked` and `frozen` even if Persian's follower trail stalls.
- Added map-entry recovery for saves left with `distractionStarted` set after the chase object no longer exists.
- Persian finishing its trailing movement can no longer determine whether Ditto is allowed to move.


## [1.0.16] - 2026-08-24

### Title screen artwork
- Replaced the previous title logo with the newly supplied Pokopia logo.
- Converted the logo to four DMG luminance shades and deliberately left it out of the true-color exemption, so the emulator's currently selected palette colorizes the logo.
- Replaced the native white title-screen background with the supplied green Pokopia pattern, scaled to fill the full 160x144 logical screen.
- The green background remains true-color so its supplied pattern/colors stay intact.
- Native title drawing can no longer clear the custom background back to white.
- `POKEMON CONSERVATION PROJECT` remains in place of the version label.


## [1.0.15] - 2026-08-24

### Distraction control timing
- Ditto regains movement as soon as Rattata finishes its escape route.
- Persian may finish its final one-tile trailing movement without keeping player input locked.
- The distraction cleanup also force-clears both `inputLocked` and `frozen` on Ditto, preventing a failed/shortened chase path from leaving controls disabled.


## [1.0.14] - 2026-08-24

### Title crash
- Fixed `module 'src.render.Text' not found`.
- Removed the nonexistent renderer module.
- `POKEMON CONSERVATION PROJECT` is now drawn with LOVE using the title screen's active pixel font.


## [1.0.13] - 2026-08-24

### Title screen
- Replaced the native title logo area with the supplied Pokopia logo artwork.
- Replaced the version text with `POKEMON CONSERVATION PROJECT`.
- Kept the existing Scientist and rotating title Pokemon behavior below the new title treatment.


## [1.0.12] - 2026-08-24

### Persian / Rattata
- Rebuilt Persian's chase using the same target-cell trail timing used by the smooth PIXIE follower.
- Rattata runs continuously on its collision-validated route while Persian follows one cell behind instead of alternating full turns.
- Basement Rattata/Persian coordinates are saved and restored, so the pair remains where the argument scene placed them on later visits.
- The persistent pair is spawned after the room-position sanitizer so that sanitizer cannot relocate them.

### Ditto Persian form
- Uses SpriteRenderer's explicit OBJ-palette support to render the Persian geometry with a dedicated Ditto-purple four-color ramp.
- Added `DITTO had an idea!` immediately before the learned-transformation message.


## [1.0.11] - 2026-08-24

### Transform menu
- Fixed `unlockedForms` nil caused by Lua lexical declaration order.
- The early START-menu callback now reads the saved learned-form table directly and queues the requested form for the live overworld code to apply.

### Rattata / Persian chase
- Reworked the chase so Rattata and Persian begin each chase step together instead of completing alternating turns.
- Rattata's escape route is generated only through walkable, non-warp map cells.
- Persian follows Rattata's vacated-cell trail one block behind.
- Rattata's own movement keeps native collision enabled; Persian's simultaneous step is map-validated before scheduling and targets only the cell Rattata is vacating.

### Basement payoff
- Talking to either Rattata or Persian starts the same one-time scene.
- Rattata insults Persian after the chase.
- Persian uses FALSE SWIPE and the verified `Damage` hit sound plays.
- Rattata says `AHHGGH...`
- Ditto then learns the PERSIAN transformation.
- Afterward, talking to either Pokémon says `You should probably leave them alone.`


## [1.0.10] - 2026-08-24

### Transform menu crash
- Fixed `src.ui.PokopiaDittoForms` not found.
- Removed the custom Screens route entirely.
- The DITTO START-menu entry now pushes a real `src.ui.Menu` state directly.
- Learned forms still appear as a selectable list under TRANSFORM.

### Rattata / Persian distraction
- Rattata now obeys normal map and entity collision during the entire distraction.
- Removed collision-disabled escape movement.
- After charging in, Rattata runs around Persian for several seconds while Persian turns to track it.
- Rattata then gets one legal tile of head start.
- Persian follows the same route one tile behind, with every step executed through native `scriptMove(..., {collide=true})`.


## [1.0.9] - 2026-08-24

### Conservation Project meeting dialogue
- Talking to either Giovanni or the scientist beside him now gives the same Conservation Project briefing.
- The briefing is split into very small text-box pages to prevent overflow and give each statement time to be read.


## [1.0.8] - 2026-08-24

### Persian distraction and transformation
- Persian now starts chasing immediately after Rattata gets a one-tile head start.
- Rattata and Persian run the same validated route, with Persian occupying Rattata's previous cell so the chase remains one block apart.
- After the distraction, the Rocket guard comments on Rattata riling Persian up and still refuses non-Persian Pokémon.
- B1F Persian now teaches Ditto the Persian form: `DITTO learned to transform into a PERSIAN!`
- The DITTO row in the START menu now opens a TRANSFORM list instead of the Trainer Card/badge screen.
- The list contains DITTO and every learned form; currently PERSIAN is unlocked by the basement Persian interaction.
- Selecting PERSIAN swaps Ditto's overworld walk/surf/bike sprites to Persian geometry while routing the sprite through Ditto's palette treatment.
- The selected form persists in the mod save data across Mansion floors.
- While transformed into Persian, the meeting-room interceptor lets Ditto pass and says: `Hey PERSIAN! Welcome back! The Boss has been waiting.`


## [1.0.7] - 2026-08-24

### Rattata distraction beat
- When Ditto returns within four tiles of the Rocket guard with Rattata following, Rattata now stops and says:
  `Stand back, kid.`
- The distraction charge begins only after that text box closes.
- Player input is locked during the line so the moment remains one continuous scripted sequence.


## [1.0.6] - 2026-08-24

### Fixed Rattata/Persian distraction crash
- Fixed `attempt to perform arithmetic on field 'height' (a nil value)` at the end of Rattata's distraction run.
- Gen1Recomp's runtime `Map` does not expose `map.width` / `map.height`; those dimensions live on `map.def`.
- Converted the distraction escape-cell scan to cell dimensions using `map.def.width * 2` and `map.def.height * 2`.
- Fixed the same invalid dimension access in the later B1F Rattata/Persian placement search so it cannot cause the same crash there.


## [1.0.5] - 2026-08-24

### CHEESE table placement fix
- Corrected the 2F CHEESE coordinate from (3,24) to (3,23).
- Koffing is at (3,22); CHEESE is now on the immediately adjacent cell below it rather than one cell too far down.
- Kept CHEESE as a native item object so the engine renders it as a Poké Ball and handles pickup normally.


## [1.0.4] - 2026-08-24

### CHEESE placement correction
- Removed CHEESE from Pokémon Mansion 1F.
- Moved CHEESE to Pokémon Mansion 2F, on the table directly below Koffing at (3,24).
- CHEESE remains a normal visible Poké Ball pickup using the native item-object behavior.


## [1.0.3] - 2026-08-24

### CHEESE placement
- Added CHEESE as a visible Poké Ball pickup on the table beside the Pokémon Mansion 1F diary area.
- Placement uses the verified Mansion 1F diary/hidden-item table area around (8,16); CHEESE is at adjacent cell (9,16).
- Uses the engine's native item-object pickup path, so collecting it adds CHEESE to inventory and permanently hides the ball through `save.itemsTaken`.


## [1.0.2] - 2026-08-24

### Rattata distraction
- Added CHEESE as a real key item.
- First Rocket interception unlocks Rattata's secret-meeting conversation.
- Repeat guard dialogue: `Sorry, only the boss and his PERSIAN are allowed back here.`
- Rattata checks the real bag inventory for CHEESE and offers a YES/NO trade.
- NO: `You're wasting my time, punk.`
- YES removes one CHEESE and makes Rattata follow Ditto.
- At four tiles from the guard, Rattata automatically runs in, pesters Persian, and flees; Persian chases it.
- The distraction removes both from 1F and disables the guard's interception tile.
- Rattata and Persian later reappear in B1F on a pair of live-map-validated walkable cells, facing each other and arguing.
# Team Rocket HQ operations

- Wired the quest list into the existing Cue Bones notice board, which is the
  guaranteed interaction point in both old and new lounge saves. Added live-map
  reconciliation so saves resumed inside B1F immediately receive Dispatch and
  Hypno without leaving and re-entering the floor.
- Added five save-persistent, sequential Ditto quests to the B1F Rocket lounge:
  Counterfeit Credentials, Cue Bones' Lucky Break, Cubone's Missing Keepsake,
  Operation: Empty Vault, and The Hypno Protocol.
- Added a Rocket Operations terminal with NEW/ACTIVE/REPORT/DONE/LOCKED states,
  objective reminders, branching Empty Vault reward, and repeat-safe payouts.
- Integrated quest objectives with the existing lounge cast, Cue Bones win state,
  and a new Hypno TCG duel finale. The final reward includes a legal 60-card
  Psychic deck and adds every card in it to the player's collection.
- Corrected the lounge Cubone spawn to use its registered species identifier.
- TCG duel completion callbacks now report the winner, allowing quest logic to
  distinguish a win from a loss without inspecting presentation state.

# TCG duel step parity

- Reordered attacks to match pret/poketcg's `UseAttackOrPokemonPower` and
  `PlayAttackAnimation_DealAttackDamage`: initial checks and Energy costs,
  Confusion check, attack declaration, required selection/before-damage hooks,
  complete attack animation, HP commit, after-damage hooks, knockouts, prizes.
- Damage is shown inside the attack presentation and HP remains unchanged until
  the animation finishes. A separate result page appears only for Weakness,
  Resistance, or an effect message.
- Turn announcements precede draws/actions. Opponent actions are reported
  before its attack, and its normally hidden draw is no longer announced.
- Added visible BETWEEN TURNS handling for Poison, Double Poison, Sleep checks,
  Paralysis recovery, and resulting knockouts in source order.
- Added Confusion retreat checks, correct AI evolution stacks/status clearing,
  and simultaneous-knockout draw resolution.
