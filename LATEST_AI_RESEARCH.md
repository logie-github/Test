# Latest AI source research — 2026-09-19

This file records source findings gathered after the last promoted 212-test checkpoint. It is research, not merged implementation.

## 1. Deck action routing

`src/data/deck_ai_pointers.asm` maps deck IDs to action tables. Most ordinary decks use `AIActionTable_GeneralDecks`; Muscles for Brains and Imakuni use `AIActionTable_GeneralNoRetreat`. Specialized tables include:

- Sam Practice;
- Legendary Moltres, Zapdos, Articuno, Dragonite;
- First Strike;
- Rock Crusher;
- Go Go Rain Dance;
- Zapping Selfdestruct;
- Flower Power;
- Strange Psyshock;
- Wonders of Science;
- Fire Charge;
- I'm Ronald;
- Powerful Ronald;
- Invincible Ronald;
- Legendary Ronald.

The action-table slots are do-turn, start-duel, forced switch, KO switch and take-prize (plus an unused do-turn slot in these tables).

## 2. Exact general turn order

`src/engine/duel/ai/decks/general.asm` performs, in order:

1. `InitAITurnVars`.
2. Trainer phase 01.
3. anti-Mewtwo-mill check.
4. Pokémon Powers: Rain Dance energy, Damage Swap, general powers, Cowardice.
5. Trainer phases 02, 03, 04.
6. play Pokémon from hand.
7. Trainer phases 05, 06, 07, 08.
8. retreat processing.
9. Trainer phases 10, 11, 12.
10. normal Energy attachment if not already attached.
11. play Pokémon from hand again.
12. Damage Swap / general Powers / Rain Dance / Energy Trans for attack.
13. Trainer phases 13 and 15.
14. If Professor Oak was used, reprocess a source-defined subset of the above phases, including retreat and Energy attachment, then phase 13 but not phase 15.
15. Energy Trans to Bench.
16. attack; otherwise finish without attack.

`general_no_retreat.asm` follows the same broad cadence but omits retreat processing and uses its own ending sequence.

## 3. Boss start setup

`SetUpBossStartingHandAndDeck`:

- returns the current opening hand to the deck and repeatedly shuffles until the opening seven contain at least 2 Basic Pokémon and 2 Energy;
- then checks six would-be prize cards against the avoid-prize list;
- then checks the following six cards so the opening seven plus those six contain at least 4 Basic Pokémon and 4 Energy;
- redraws the opening seven.

Important source bug: `.CheckIfIDIsInList` contains `cp a` where the intended terminator check would have been `or a`, so the avoid-prize check always returns false/no-carry. Preserve the cartridge bug rather than "fixing" prize avoidance silently.

`TrySetUpBossStartingPlayArea` chooses the first available Basic from the deck's Arena-priority list, then Bench-priority cards until there are at most three Pokémon in play; if the Arena setup cannot be made, source callers fall back to ordinary initial Basic placement.

## 4. List-pointer quirks

Many specialized deck files define `.list_retreat` data but never store it in `wAICardListRetreatBonus`. This omission is present in source and must be preserved where applicable. Legendary Moltres is an example that does store its retreat list; several others explicitly have a "missing store_list_pointer" comment.

## 5. Specialized turn behaviors reviewed

### Legendary Moltres

Before ordinary Pokémon-from-hand logic, play Moltres Lv37 if:

- Play Area is not full;
- more than 9 cards remain in deck;
- Muk's active Pokémon Power is not suppressing powers;
- Moltres Lv37 is in hand.

Energy special-case: if Active is Magmar Lv31 with no attached Energy, try attaching directly to it before normal Energy scoring.

### Legendary Zapdos

Energy special-case: if Active is Voltorb and Electrode Lv35 is in hand, or Active is Electabuzz Lv35, and Active has no Energy, attempt direct Energy attachment before normal Energy scoring.

### Legendary Articuno

Uses custom `ScoreLegendaryArticunoCards` Bench-energy priority involving Lapras, Articuno Lv35, Dewgong and Seel, plus a reduced Trainer-phase turn sequence.

### Legendary Dragonite

Energy special-case: if Active is Kangaskhan with no Energy, attempt direct attachment first. Uses a reduced source phase order and Professor Oak replay path.

### Legendary Ronald

Has the Moltres Lv37 pre-play behavior and repeats it after Professor Oak when the new hand is reprocessed. Uses its own phase order.

The other specialized boss/club decks reviewed mostly install Arena/Bench/hand-priority, Energy-score and prize lists, then delegate turns to `AIMainTurnLogic`.

## 6. Hidden Mewtwo Lv53 mill detector

`InitAITurnVars` examines the Player's previous attack:

- it must be the second attack;
- the attacking card must be Mewtwo Lv53;
- after three consecutive Barrier uses, source verifies the Player's Active is Mewtwo Lv53 and scans the Player deck for any Pokémon other than Mewtwo Lv53;
- if none exist, set the `AI_MEWTWO_MILL` flag in the counter.

While flagged, turns without Barrier increment the counter. `HandleAIAntiMewtwoDeckStrategy` allows only a short grace period; after enough non-Barrier turns it clears the flag. While active and before reset, if the AI has at least four "set up" Bench Pokémon it processes Trainer phase 05 and can jump directly toward attacking instead of running the full normal turn sequence.

## 7. Remaining Trainer AI decisions reviewed

### Imposter Professor Oak

Decision source depends on opponent deck/hand counts:

- when opponent has fewer than 14 cards left in deck, use only if opponent hand has fewer than 6;
- otherwise use if opponent hand has at least 9.

Effect: shuffle opponent's entire hand into deck, then draw up to 7.

### Lass

Use if opponent/player hand has at least 7 cards and AI's own hand contains no Trainer card other than Lass. Effect discards the used Lass, then returns all Trainer cards from both hands to their respective decks and shuffles affected decks.

### Imakuni?

AI decision: use only when own Active is not already Confused. Effect tries to Confuse own Active. It has no effect on Clefairy Doll/Mysterious Fossil, and no effect on Snorlax while Thick Skinned is active.

### Gambler

For non-Imakuni decks, decision is tied to detected Mewtwo-mill strategy and very low deck count; Imakuni uses a 2-in-10 random decision. The non-Imakuni play routine temporarily overwrites the three RNG bytes with `$50,$50,$50` so the coin toss yields the intended source behavior, then restores RNG. Effect returns remaining hand to deck and draws 8 on heads or 1 on tails.

### Clefairy Doll / Mysterious Fossil

Shared decision: skip at max Play Area size; immediately allow if Active is Wigglytuff; otherwise only use below four Pokémon in play. Player-side effect places the Trainer-as-Pokémon card into Play Area.

### Scoop Up

General branch:

- requires at least two Pokémon in play;
- avoids use if Active has a usable KO attack or can become that KO with an Energy from hand;
- if normal retreat is possible, do not Scoop Up;
- if retreat is impossible, only continue when damage ratio is high enough (source compares total HP counters / damage counters, effectively around the documented 70% threshold), then pick a Bench switch target.

Legendary Articuno/Ronald have special branches for scooping zero-Energy Legendary birds from Bench and for threatened Active Articuno/Chansey.

Effect: return the selected slot's Basic Pokémon to hand, discard higher stages and attachments, clear Active status if needed, and promote the selected Bench Pokémon when scooping Active.

### Super Potion

Two decision phases. Source checks retreat intent, high-recoil attacks, attached Energy, whether healing changes the defending Pokémon's KO outcome, damage threshold, `BOOST_IF_TAKEN_DAMAGE`, and whether discarding an Energy makes attacks unusable. Bench use includes the cartridge's random gate. Effect discards one attached Energy and heals up to 40 damage.

### Pokémon Breeder

Skips under Prehistoric Power. Source first prioritizes a small Stage2 set (Venusaur variants, Blastoise, Vileplume, Alakazam, Gengar), scores compatible Basics by remaining HP counters and attached Energy, then handles the general evolution pass with a Dragonite Lv41 special policy. Effect performs Basic -> Stage2 evolution directly and marks the stage accordingly.

Compatibility is source-shaped: the Stage2 card's printed Stage1 pre-evolution name must match the Basic's name through the decomp's `CheckIfCanEvolveInto_BasicToStage2` logic, and the Basic must be allowed to evolve this turn.

### Computer Search

Source AI has dedicated policies for Rock Crusher, Wonders of Science, Fire Charge and Anger. It chooses a deck target, then chooses two hand cards to discard with source type priority/avoidance behavior. Do not replace these with a generic "best card" heuristic.

### Pokémon Trader

Source has dedicated policies for Legendary Moltres, Legendary Articuno, Legendary Dragonite, Legendary Ronald, Blistering Pokémon, Sound of the Waves, Power Generator, Flower Garden, Strange Power and Flamethrower.

Important source bug: `AIDecide_PokemonTrader_PowerGenerator` is missing a `jr .no_carry` after its final search chain. The fall-through can leave an invalid value in A and lead to unintended trade behavior. Treat this as an explicit cartridge-bug boundary; do not silently implement the upstream bug-fix patch.

## 8. Retreat one-Energy edge

Source `CheckIfAnyAttackKnocksOutDefendingCard` can establish potential KO damage before a later usability check. Retreat/Scoop Up/Defender policies then call `LookForEnergyNeededForAttackInHand` if the chosen attack is currently unusable.

The hand helper only succeeds when:

- exactly one Energy is missing (typed or Colorless, with matching Energy in hand), or
- exactly two Colorless are missing and Double Colorless Energy is in hand.

This must be implemented without changing unrelated callers that expect "KO" to mean currently usable KO.
