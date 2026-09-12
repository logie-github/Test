# Changelog

## 1.7.0

### Models

- Replaced the three ~304k-parameter microLMs with ~1.75M-parameter models, one
  per species, each with its own 3000-word vocabulary and its own weight file.
  Context went from 128 to 192 tokens, layers from 3 to 4, d_model from 96 to
  160. The three models remain fully independent and local: no server, no
  socket, no shared checkpoint, no cross-model state.
- Trained each model on its own Bulbapedia article text and the articles for
  the forms it evolves into, plus a generated Day Care social corpus written in
  exactly the four prompt shapes the runtime uses.
- Added the whole training pipeline under `training/`: article fetch, corpus
  build, trainer, q8 exporter, and a verifier that runs the mod's own reader
  against the float checkpoint and compares logits.
- Prompt text is now filtered against each species' vocabulary, so a word a
  model never learned is dropped instead of being fed to it as `<unk>`.
- Dequantized weights once at load into flat float arrays (LuaJIT FFI where it
  is available, plain Lua arrays otherwise) instead of decoding int8 bytes
  inside every inner loop.

### Cognition

- Added a permanent per-Pokemon event ledger. Nothing is ever deleted.
- Added a retrieval layer that selects a few relevant ledger lines per decision
  on recency, salience, involvement and recurrence, so long-run autobiographical
  memory survives a small context window.
- Added beliefs formed from recurring patterns, with strength that grows on
  repetition and decays without confirmation. Beliefs are interpretations and
  can be wrong.
- Added a self-concept accumulated from a Pokemon's own behavior and outcomes.
- Added theory of mind built only from physically observed actions. No Pokemon
  can read another's thought, plan, belief or need state.
- Added general drives - curiosity, security, social connection, autonomy,
  stimulation, mastery, comfort - and values that shift with experience.
- Added plans and longer projects the model chooses for itself, holds while they
  bias later action scoring, and either keeps or abandons.
- Added counterfactual seeds to the thought prompt from stage three.
- Added a development stage, driven by accumulated experience, that gates which
  context sections a Pokemon is offered at all.
- Assembled prompts against a real token budget, section by section, keeping the
  head instead of cutting the front away when something has to give.

### Fighting

- Fainting is now ten real seconds of unconsciousness. A Pokemon at 0 HP cannot
  move, think, speak or defend itself, then wakes at full health remembering who
  knocked it out and what led up to it.
- Conscious Pokemon can perceive a helpless one and are offered the full range:
  guard, comfort, wait nearby, take from it, or leave.
- A lethal follow-up becomes available only after the attacker's own
  relationship state crosses severe hostility, and the model still has to choose
  it. Crossing the threshold causes nothing by itself.
- Witnesses to a kill keep it permanently, and so does the attacker.

### Body and progression

- Damage now comes from real move power, real level-5 stats and the Gen I
  spread, applied to the real party record.
- Landing moves and knockouts award real experience; enough of it levels the
  real record up through the species growth curve.
- A level that satisfies the real evolution condition pauses the simulation and
  runs the engine's evolution sequence, then returns the evolved form to the
  Day Care and gives its model the event as something that happened to it.

### Presentation

- Private thoughts are drawn over the room again, in dotted thought boxes that
  page rather than clip, with a `THOUGHTS ON/OFF` toggle.
- The focused panel now uses the same transform the room sprites use, so it
  lands inside the visible game area, and shows stage and current plan.
- Added sprite-scale battle animation: attacker lunge, defender knockback and
  flash, and a type-shaped effect between them.
- Added a health bar over the head that appears for one second after damage or
  a full heal.
- Replaced `DISPOSITIONS` with `MIND` (SELF / TOWARD / BELIEFS / PLAN) and added
  `MEMORY`, the permanent ledger itself.


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
