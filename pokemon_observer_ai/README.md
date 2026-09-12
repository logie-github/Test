# Pokemon Observer AI Arena 1.7

Gen1Recomp API-v2 total conversion for Red/Blue/Yellow. The simulation runs inside the regular Gen1Recomp overworld and reuses the original Gen I `DAYCARE` room, tileset and collision rules.

## Independent per-Pokemon models

Bulbasaur, Charmander and Squirtle each run their own decoder-only Transformer, loaded from their own weight file with their own 3000-word vocabulary and executed directly inside the game's Lua process. There is no Python process, socket, localhost server, shared checkpoint or network dependency, and the three models never see each other's state.

Each model is trained on its own Bulbapedia article text, the articles for the forms it evolves into, and a generated Day Care social corpus written in exactly the prompt shapes the runtime uses. See `training/README.md` for the pipeline, the architecture and the honest limits.

| | |
|---|---|
| parameters | ~1.75M per species |
| layers / d_model / heads / ff | 4 / 160 / 4 / 640 |
| context | 192 tokens |
| vocabulary | 3000 words per species |
| quantization | symmetric int8 per output row |

The Pokemon explicitly know they are living in a Pokemon Day Care. Spectator clicks, the thought panel and the MIND and MEMORY screens never enter their prompts, ledgers, beliefs or perception state.

## What a Pokemon actually does with a decision

```
permanent ledger -> retrieval -> beliefs / self-concept / theory of mind
  -> drives, emotions, relationships -> token-budgeted prompt
  -> model picks a plan, an action and a target
  -> model writes its thought and its speech
  -> physical consequence -> permanent ledger
```

**Permanent ledger.** Every event a Pokemon experiences or physically witnesses is appended and never removed. Because each model only has a 192-token context, a retrieval layer chooses a few lines per decision, scored on recency, salience, whether the other Pokemon in question is involved, and how often the same kind of thing has happened before.

**Beliefs.** Recurring patterns settle into beliefs - "charmander takes my food", "squirtle helps me" - with a strength that grows on repetition and decays when nothing confirms it. A belief is that Pokemon's own interpretation, so it can be mistaken, out of date or unfair.

**Self-concept.** Repeated behavior settles into things it believes about itself: "i usually share food", "i usually hit", "i am not safe here".

**Theory of mind.** Each Pokemon builds a picture of what another one wants purely from actions it physically observed. No Pokemon can read another's thought, plan, belief or need state.

**Drives and values.** Curiosity, security, social connection, autonomy, stimulation, mastery and comfort are general drives. Cooperation, dominance, fairness, revenge, novelty, safety and independence are values that move with experience. Both tilt action scoring; neither decides it.

**Plans and longer projects.** The model picks a plan for itself out of a candidate list - stay near someone, stay away from someone, guard the food, keep the toy, take food from someone, forgive someone, confront someone, speak to the human, stay away from the human, watch someone, stay near and help a newcomer - holds it while it biases later choices, and either keeps it or abandons it. Both outcomes go into the ledger.

**Development.** A stage that rises with accumulated experience gates which context sections a Pokemon is offered at all. They start simple because they have little history, not because anything forces childish output, and their language and planning widen as the run goes on.

**Counterfactuals.** From stage three, the prompt can carry a consequence to consider - "if i give the toy to squirtle it might stay near me". What it concludes is its own.

None of this scripts an outcome. There is no "becomes hostile at thirty minutes" and no "falls in love at affection eighty".

## Fainting, helplessness and death

At 0 HP a Pokemon is unconscious for ten real seconds. It cannot move, think, speak or defend itself. If nothing else happens it wakes at full health remembering who put it there and what led up to it.

A conscious Pokemon can perceive that another is helpless, and the engine offers it the whole range: guard it, comfort it, wait beside it, take from it, or leave. A lethal follow-up is added to that list only once the attacker's own accumulated relationship state has crossed severe hostility - and crossing that threshold causes nothing by itself. It only means the simulation stops protecting the victim from the possibility. The model still has to choose it. A Pokemon can stand over someone it hates, think about finishing it, and not.

If it does choose it, the victim is permanently dead. Everyone who witnessed it keeps that in their permanent memory, and so does the attacker.

## Real level-5 party Pokemon


The three original residents are also real Gen I party records. At the start of the observation run the mod creates:

- Bulbasaur — level 5
- Charmander — level 5
- Squirtle — level 5

Their HP, Attack, Defense, Speed, Special, EXP and starting moves are generated by Gen1Recomp's normal `Pokemon.new` path from the loaded game's species and move data. The social-simulation agents hold references to these same party tables rather than duplicate fake records.

The observation START menu now contains `POKéMON`. It opens the normal Gen I Party Menu, where the three residents can be selected and inspected through the normal STATS/Summary screen, including current HP, level, stats, moves and PP. Social use of a known attack move consumes its real PP, and injuries in the room are mirrored to the corresponding party HP display.

Introduced mates are also constructed as real level-5 Pokemon records for internal simulation, but they are not added to the original three-member observer party.

## PokePC follower sprites

The in-room Bulbasaur, Charmander and Squirtle use the exact six-frame overworld follower sheets from `gamecorner-033/PokePCFollowers`, bundled directly with this mod with the user's stated permission:

- `assets/sprites/follower_001.png` — Bulbasaur
- `assets/sprites/follower_004.png` — Charmander
- `assets/sprites/follower_007.png` — Squirtle

The sheets retain their original down/up/side standing and walking-frame layout. They are also used as species-specific Party Menu icons. See `SPRITE_CREDITS.md` for exact source commit/blob provenance and upstream art credits.

## Battle presentation

Moves play a miniature animation over the 16x16 follower sprites: the attacker lunges toward its target, the defender is knocked back and flashes, and a short type-shaped effect plays between them - embers for fire, droplets for water, a vine line for grass, a zigzag for electric, bubbles for poison and psychic, slashes for everything else. A lethal follow-up plays the same shapes harder.

A health bar appears over a Pokemon's head for one second after it takes damage or is fully healed, and is otherwise absent.

## Spectator view

There is no visible or controllable player character. Gen1Recomp still owns an inert Player object internally because the overworld engine expects one, but this mod locks it, makes it passable and suppresses its draw call. The camera stays centered on the Day Care room.

Private thoughts are drawn over the room. A Pokemon's current thought appears in a dotted thought box above it for a few seconds after it thinks it, paging automatically rather than being cut off, and stays up for as long as that Pokemon is focused. Thought boxes are dotted so they never read as something another Pokemon heard; speech bubbles stay solid. `THOUGHTS ON` / `THOUGHTS OFF` in the START menu turns the ambient boxes off.

Click/touch a Pokemon to inspect it. Focus does not move the camera and is not perceptible to the Pokemon. The focused panel shows the full thought, the Pokemon's stage, its current plan and the compact process line. Labels are `B:`, `C:` and `S:` (`B2:`, `C2:`, `S2:` for introduced mates).

Speech bubbles use the same speaker tags. Social reactions can briefly show `++`, `+`, `-`, or `--` beside the Pokemon that experienced them, based on the learned disposition update.

## Day Care movement

Pokemon move on the engine's 16x16 world-cell grid. Every step uses Gen1Recomp map walkability, collision and entity occupancy, so they respect walls, furniture and one another. The Day Care exits remain sealed.

## START menu

The observation-room START menu contains:

- POKéMON
- GIVE FOOD
- TAKE FOOD
- GIVE TOY
- TAKE TOY
- GIVE MATE
- TAKE MATE
- SECRET ON / VISIBLE
- THOUGHTS ON / OFF
- MIND
- MEMORY
- ACTIVITY LOG

Food, toys and compatible mates can be applied to **ALL** Pokemon or to a specific Pokemon from a target submenu. `GIVE MATE` introduces a compatible opposite-sex member for the selected original Pokemon; `TAKE MATE` removes that selected Pokemon's introduced mate.

`MIND` has four tabs per Pokemon: SELF (stage, experience, drives, strongest value, self-concept), TOWARD (directional affection, trust, anger, fear, attachment and familiarity, and whether severe hostility has been crossed), BELIEFS (what it has settled on about the others, with strength, and what it reads the selected one as wanting) and PLAN (what it is holding, how long it has held it, and how many plans it has kept versus abandoned).

`MEMORY` is the permanent ledger itself, per Pokemon, timestamped and never trimmed. `ACTIVITY LOG` contains the observer/system history. There is no persistent AI-status overlay or instruction bar over the room.

## Progression

Damage is computed from the real move power, the real level-5 stats and the Gen I spread, and is applied to the real party record. Landing moves and knocking another Pokemon out award real experience; enough of it levels the real record up through the game's growth curve, and a level that satisfies the species' actual evolution condition pauses the simulation and runs the engine's evolution sequence. Afterwards the evolved form returns to the Day Care and its own model receives the event as something that happened to it: *I changed form. My body and abilities are different now.* What it makes of that is its own.

## Consequences

The models choose from general capabilities rather than hard-coded social outcomes. Relationship state, ledgers, beliefs and subsequent choices can lead to cooperation, hostility, attachment, avoidance, routines, reconciliation, fights, knockdowns, death, or compatible pairs eventually producing an Egg. The same infrastructure produces all of them.

## Install

Extract the ZIP so this path exists:

`mods/pokemon_observer_ai/manifest.json`

Enable **Pokemon Observer AI Arena**, reboot, and choose **NEW GAME**. Oak's new-game speech is skipped. No external process is required.
