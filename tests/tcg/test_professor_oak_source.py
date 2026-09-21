"""Professor Oak AI decision (trainer_cards.asm AIDecide_ProfessorOak). The
card's effect (drawing 7 new cards) was already translated in an earlier
round; this replaces a placeholder that only implemented the deck-agnostic
gates and failed closed for the three deck-specific branches
(LegendaryArticuno/Excavation/WondersOfScience) with the real per-branch
decision logic, plus the general path's own evolution/hand-basic/Blastoise
scoring terms it never had at all.

AIDecide_ProfessorOak's real shape: a deck-agnostic ">=DECK_SIZE-6 not in
deck" gate, then a three-way deck-ID dispatch (LegendaryArticuno /
Excavation / WondersOfScience), falling through to a general path shared,
via AI:_decideProfessorOakGeneral(initialScore), by the plain default deck,
WondersOfScience's own Grimer/Muk-miss fallthrough (initialScore=30, same as
default), and Excavation's Mysterious-Fossil-scored entry (30 if already
out, 80 if missing).

The general scoring path has a genuine source bug, preserved literally: its
hand-Basic-Pokemon encouragement loop does `cp TYPE_ENERGY; jr c, .loop_hand`
(source comment: "bug, should be jr nc"), which skips every card whose type
is BELOW TYPE_ENERGY -- i.e. every actual Pokemon card -- and instead
inspects Trainer/Energy cards' raw stage byte (which RomExtractor.lua
populates for every card kind, not just Pokemon) for stage==BASIC.

LegendaryArticuno's own branch has a second source quirk: with fewer than 3
Play Area Pokemon, its CheckForEvolutionInList call always consults
PLAY_AREA_ARENA's own CAN_EVOLVE_THIS_TURN flag, regardless of which real
Play Area slot's card identity is being checked (the source temporarily
overwrites PLAY_AREA_ARENA's arena-card byte to reuse CheckIfCanEvolveInto,
never touching its flags byte) -- reproduced here as a pure read
(AI:_checkForEvolutionInList) with the identical net result, no memory
mutation.

All of this is exercised for real by lua_fixtures/professor_oak_smoke.lua
under LuaJIT (39 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/professor_oak_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ProfessorOakSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nlocal function", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        return self.ai_src[start:min(candidates)]

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "PROFESSOR_OAK" then\n'
            "    return self:_decideProfessorOak()",
            self.ai_src,
        )
        self.assertIn('PROFESSOR_OAK = true', self.ai_src)

    def test_dispatcher_gate_then_three_way_deck_dispatch(self):
        block = self._block("function AI:_decideProfessorOak()")
        self.assertIn("notInDeck >= self.c.DECK_SIZE - 6", block)
        self.assertIn("self:_decideProfessorOakLegendaryArticuno()", block)
        self.assertIn("self:_decideProfessorOakExcavation(notInDeck)", block)
        self.assertIn("self:_decideProfessorOakWondersOfScience()", block)
        self.assertIn("self:_decideProfessorOakGeneral(30)", block)

    def test_general_shares_deck_size_14_gate_and_initial_score_param(self):
        block = self._block("function AI:_decideProfessorOakGeneral(initialScore)")
        self.assertIn("notInDeck >= self.c.DECK_SIZE - 14", block)
        self.assertIn("local score = initialScore", block)
        self.assertIn("score >= 60", block)

    def test_general_preserves_the_hand_basic_type_check_bug(self):
        block = self._block("function AI:_decideProfessorOakGeneral(initialScore)")
        self.assertIn("Source bug", block)
        self.assertIn("row.type >= self.c.TYPE_ENERGY and row.stage == self.c.BASIC", block)

    def test_general_blastoise_bonus_gated_by_muk(self):
        block = self._block("function AI:_decideProfessorOakGeneral(initialScore)")
        muk_pos = block.index("countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)")
        blastoise_pos = block.index("countTurnDuelistPokemonWithActivePkmnPower(self.c.BLASTOISE)")
        self.assertLess(muk_pos, blastoise_pos)
        self.assertIn("not mukActive", block)
        self.assertIn("not self:_findCardIDInHand(self.c.WATER_ENERGY)", block)

    def test_excavation_scores_by_mysterious_fossil_presence(self):
        block = self._block("function AI:_decideProfessorOakExcavation(notInDeck)")
        self.assertIn("notInDeck >= self.c.DECK_SIZE - 14", block)
        self.assertIn("self:_cardIDInHandAndPlayArea(self.c.MYSTERIOUS_FOSSIL) and 30 or 80", block)
        self.assertIn("self:_decideProfessorOakGeneral(initialScore)", block)

    def test_wonders_of_science_blocks_on_grimer_or_muk_else_falls_through(self):
        block = self._block("function AI:_decideProfessorOakWondersOfScience()")
        self.assertIn("self:_cardIDInHand(self.c.GRIMER)", block)
        self.assertIn("self:_cardIDInHand(self.c.MUK)", block)
        self.assertIn("self:_decideProfessorOakGeneral(30)", block)

    def test_articuno_skips_playable_check_when_no_evolution_found_below_three(self):
        block = self._block("function AI:_decideProfessorOakLegendaryArticuno()")
        self.assertIn("count < 3", block)
        self.assertIn("self:_checkForEvolutionInList(realCardId, hand)", block)
        self.assertIn("if not foundEvolution then return true end", block)

    def test_articuno_energy_gate_then_playable_scan_excludes_up_to_two_oaks(self):
        block = self._block("function AI:_decideProfessorOakLegendaryArticuno()")
        energy_pos = block.index("#self:_energyCardsInHand() >= 4")
        removal_pos = block.index("removed < 2")
        self.assertLess(energy_pos, removal_pos)
        self.assertIn("self.c.PROFESSOR_OAK", block)
        self.assertIn("self:_checkIfCardCanBePlayed(deckIndex)", block)

    def test_check_for_evolution_in_list_uses_play_area_arena_flags_not_slot_specific(self):
        block = self._block("function AI:_checkForEvolutionInList(cardId, list)")
        self.assertIn("DUELVARS_ARENA_CARD_FLAGS + self.c.PLAY_AREA_ARENA", block)
        self.assertIn("preEvolutionTextId == current.nameTextId", block)
        self.assertNotIn("[hli]", block)  # no literal memory-mutation swap, unlike the ASM

    def test_check_if_card_can_be_played_dispatches_by_type_like_the_source(self):
        block = self._block("function AI:_checkIfCardCanBePlayed(deckIndex)")
        pokemon_pos = block.index("row.type < self.c.TYPE_ENERGY")
        trainer_pos = block.index("row.type == self.c.TYPE_TRAINER")
        self.assertLess(pokemon_pos, trainer_pos)
        self.assertIn("self:_isPrehistoricPowerActive()", block)
        self.assertIn("self.duelOps:checkIfCanEvolveInto(deckIndex, slot)", block)
        self.assertIn("self.combat.status:checkCantUseTrainerDueToEffect()", block)
        self.assertIn("EFFECTCMDTYPE_INITIAL_EFFECT_1", block)
        self.assertIn('readSymbol8("wAlreadyPlayedEnergy") == 0', block)

    def test_look_for_evolution_for_play_area_short_circuits_on_hand_match(self):
        block = self._block("function AI:_lookForEvolutionForPlayArea(slot)")
        self.assertIn("for deckIndex = 0, self.c.DECK_SIZE - 1 do", block)
        self.assertIn("return true, true", block)
        self.assertIn("return false, foundAnywhere", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ProfessorOakExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Professor Oak AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
