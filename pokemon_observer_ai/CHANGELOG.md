# Changelog

## 1.6.0

- Converted Bulbasaur, Charmander and Squirtle into real Gen I level-5 party records created through the engine's normal Pokemon constructor.
- Their normal level-5 HP, stats, EXP, starting moves and PP are now visible in the stock Party/Summary screens.
- Added `POKéMON` to the observer START menu and routed it to the normal Gen I Party Menu.
- Social combat now selects from each Pokemon's actually known moves and consumes real move PP.
- Social injury/knockdown/death HP is mirrored into the same party records shown by the normal UI.
- Replaced generic party-icon room actors with exact six-frame Bulbasaur, Charmander and Squirtle follower sheets from `gamecorner-033/PokePCFollowers`, packaged under the user's stated permission.
- Added walking-frame/facing animation for the bundled follower sheets and species-specific Party Menu icon overrides.
- Added exact sprite source provenance and upstream art credits in `SPRITE_CREDITS.md`.

## 1.5.0

- Removed the persistent `AI:LOCAL Q8` status overlay.
- Removed the overworld activity-log box and bottom instruction overlay.
- Converted the player into an invisible, input-locked, passable engine anchor; no player avatar appears or walks in the room.
- Locked the camera to the center of the Day Care room instead of following the hidden Player object or focused Pokemon.
- Added explicit Day Care location awareness to every microLM prompt and starting memory.
- Added ALL/specific-Pokemon target menus for giving or taking food, toys and compatible mates.
- Added `GIVE MATE` and `TAKE MATE` as symmetrical interventions.
- Moved observer/system history to a dedicated `ACTIVITY LOG` START-menu screen with retained history.
- Renamed `RELATIONS` to `DISPOSITIONS` in the START menu.
- Reworked focused private thoughts to use `B:`, `C:`, `S:` labels and automatic multi-page wrapping so longer thoughts are not silently clipped.
- Removed the clipped ambient one-line thought snippets from the room view; full private thoughts are available through focus.

## 1.4.0 - 2026-09-12

### Changed
- Moved the simulation from a bespoke arena screen into the regular Gen1Recomp overworld.
- Reused the original Gen I DAYCARE block layout and tileset instead of a drawn arena floor.
- Pokemon movement is now cell-based and checked through engine collision before every step.
- Replaced the vanilla START-menu rows with intervention controls and a relations viewer.
- Speech bubbles dynamically size and clamp so wrapped lines are not cut off.

### Added
- `B` / `C` / `S` speaker labels (`B2` / `C2` / `S2` for a newcomer).
- Temporary `++`, `+`, `-`, `--` reaction markers derived from learned disposition changes.
- In-menu directional disposition viewer for affection, trust, anger, fear, attachment and familiarity.
- Camera focus in the regular overworld while remaining invisible to the agents.
- Player/Pokemon and Pokemon/Pokemon occupancy collision.

## 1.3.0 - 2026-09-12

### Changed
- Replaced the localhost/PyTorch sidecar with an embedded Lua Transformer runtime.
- Quantized all three arena microLMs to row-wise q8 weights consumed directly with `mod:read`.
- Added causal KV caching and cooperative coroutine inference so model work is spread across frames.
- Continued-trained the three model copies with recent-memory context, broader social speech, inspection behavior and arena observations.
- The AI HUD now reports `AI:LOCAL Q8`; there is no online/offline state.

### Added
- Embedded learned disposition network.
- Inspect-food, inspect-water, inspect-toy and inspect-wall capabilities.
- Unexplained-memory handling for secret player interventions.
- Witnessed-death event context for observers of lethal escalation.

### Removed
- Network permission.
- Python, PyTorch, localhost sockets, start scripts and server requirements.
- Scripted offline fallback behavior.

## 1.2.0 - 2026-09-12
- Added continued-trained social agent models and learned directional disposition.

## 1.1.0 - 2026-09-12
- Switched to Gen I party icons and hard-clamped the arena to one screen.

## 1.0.0 - 2026-09-11
- Initial observer arena prototype.
