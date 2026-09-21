"""Computer Search AI decision (trainer_cards.asm AIDecide_ComputerSearch
and its four deck-specific branches). The card's effect (ComputerSearch_
HandDeckCheck/PlayerDiscardHandSelection/PlayerDeckSelection/
DiscardAddToHandEffect) was already translated in an earlier round; this
adds the real AI decision side, replacing an earlier placeholder that only
implemented the deck-agnostic hand-count>=3 gate and failed closed for all
four decks that can actually play the card.

AIDecide_ComputerSearch has no general/default path at all -- only Rock
Crusher, Wonders of Science, Fire Charge, and Anger ever play this card,
each through its own dedicated multi-branch deck-search routine:

- RockCrusher: at exactly 3 hand cards, targets Professor Oak (discarding
  any 2 hand cards outside a fixed blocklist); with more, walks the
  Geodude/Graveler, Graveler-in-Play-Area/Golem, Diglett-in-Play-Area/
  Dugtrio evolution chain.
- WondersOfScience: <5 hand cards targets Professor Oak; otherwise Grimer
  (or, failing that, Muk) so long as the AI doesn't already have one.
- FireCharge: Chansey > Tauros > JigglypuffLv12 priority, skipping any
  already in hand.
- Anger: for Rattata/Raticate, Growlithe/ArcanineLv34, Doduo/Dodrio --
  prefers fetching the evolution when the pre-evolution is already out
  (hand or Play Area), else fetches the pre-evolution itself when the
  evolution is already in hand. Reuses the exact same
  LookForCardIDInDeck_GivenCardIDInHand[AndPlayArea] primitives as
  AIDecide_Pokeball (AI:_pokeBallGivenCardInHand[AndPlayArea]).

Three of the four decks (all but RockCrusher's Oak case) share a "discard
exactly 2 Trainer cards from hand" tail that shuffles the hand list via the
real RNG before picking (AI:_removeFromListDifferentCardOfGivenType,
AI:_findTwoTrainerDiscardsExcept); RockCrusher's evolution-chain case uses
a variant that advances Trainer -> Pokemon -> Energy on failure
(AI:_findTwoDiscardsAdvancingType) instead.

All of this is exercised for real by
lua_fixtures/computer_search_smoke.lua under LuaJIT (26 checks) -- see
test_lua_execution_smoke below, which is what actually caught a bug in an
early draft of that fixture, not in AI.lua: a test case placed a card at
deck index 60, one past the real 0-59 range (DECK_SIZE=60), so
_findCardIDInDeck's own scan (0 to DECK_SIZE-1) could never see it --
surfaced only once the fixture actually ran and the "should find it" case
failed, not from reading the fixture's source.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/computer_search_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ComputerSearchSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nlocal function", "\nlocal ", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        return self.ai_src[start:min(candidates)]

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "COMPUTER_SEARCH" then\n'
            "    return self:_decideComputerSearch(currentTrainerDeckIndex)",
            self.ai_src,
        )
        self.assertIn('or constantName == "COMPUTER_SEARCH"', self.ai_src)
        self.assertIn('"MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER"', self.ai_src)

    def test_play_sets_modified_hand_flag(self):
        block = self.ai_src[self.ai_src.index("function AI:_playTrainerForAI"):
                             self.ai_src.index("local AI_TRAINER_PHASES")]
        flag_group_start = block.index('if constantName == "MAINTENANCE"')
        flag_group_end = block.index("then", flag_group_start)
        self.assertIn('constantName == "COMPUTER_SEARCH"', block[flag_group_start:flag_group_end])

    def test_decide_dispatches_to_all_four_specialized_decks(self):
        block = self._block("function AI:_decideComputerSearch(avoidDeckIndex)")
        self.assertIn("handCount < 3", block)
        self.assertIn("self:_decideComputerSearchRockCrusher(avoidDeckIndex)", block)
        self.assertIn("self:_decideComputerSearchWondersOfScience(avoidDeckIndex)", block)
        self.assertIn("self:_decideComputerSearchFireCharge(avoidDeckIndex)", block)
        self.assertIn("self:_decideComputerSearchAnger(avoidDeckIndex)", block)

    def test_rock_crusher_oak_case_uses_the_fixed_blocklist_no_shuffle(self):
        block = self._block("function AI:_decideComputerSearchRockCrusher")
        self.assertIn("handCount == 3", block)
        self.assertIn("self:_findCardIDInDeck(self.c.PROFESSOR_OAK)", block)
        self.assertIn("self:_rockCrusherOakDiscards(avoidDeckIndex)", block)
        blocklist = self._block("local ROCK_CRUSHER_OAK_DISCARD_BLOCKLIST")
        for name in ("PROFESSOR_OAK", "FIGHTING_ENERGY", "DOUBLE_COLORLESS_ENERGY",
                     "DIGLETT", "GEODUDE", "ONIX", "RHYHORN"):
            self.assertIn(f'"{name}"', blocklist)

    def test_rock_crusher_evolution_chain_checks_graveler_golem_dugtrio_in_order(self):
        block = self._block("function AI:_decideComputerSearchRockCrusher")
        graveler_pos = block.index("self.c.GRAVELER")
        golem_pos = block.index("self.c.GOLEM")
        dugtrio_pos = block.index("self.c.DUGTRIO")
        self.assertLess(graveler_pos, golem_pos)
        self.assertLess(golem_pos, dugtrio_pos)
        self.assertIn("self:_cardListWithout(list, self:_findCardIDInHand(self.c.GEODUDE))", block)
        self.assertIn("self:_findTwoDiscardsAdvancingType(list, avoidDeckIndex)", block)

    def test_wonders_of_science_falls_from_oak_to_grimer_to_muk(self):
        block = self._block("function AI:_decideComputerSearchWondersOfScience")
        oak_pos = block.index("self.c.PROFESSOR_OAK")
        grimer_pos = block.index("self.c.GRIMER")
        muk_pos = block.index("self.c.MUK")
        self.assertLess(oak_pos, grimer_pos)
        self.assertLess(grimer_pos, muk_pos)
        self.assertIn("handCount < 5", block)
        self.assertIn("self:_findTwoTrainerDiscardsExcept(avoidDeckIndex)", block)

    def test_fire_charge_priority_order(self):
        block = self._block("function AI:_decideComputerSearchFireCharge")
        self.assertIn("self.c.CHANSEY, self.c.TAUROS, self.c.JIGGLYPUFF_LV12", block)
        self.assertIn("self:_findTwoTrainerDiscardsExcept(avoidDeckIndex)", block)

    def test_anger_reuses_the_poke_ball_deck_search_primitives(self):
        block = self._block("function AI:_decideComputerSearchAnger")
        self.assertIn("self.c.RATICATE, self.c.RATTATA", block)
        self.assertIn("self.c.ARCANINE_LV34, self.c.GROWLITHE", block)
        self.assertIn("self.c.DODRIO, self.c.DODUO", block)
        self.assertIn("self:_pokeBallGivenCardInHandAndPlayArea(evolution, preEvolution)", block)
        self.assertIn("self:_pokeBallGivenCardInHand(preEvolution, evolution)", block)

    def test_remove_from_list_shuffles_before_matching_by_type(self):
        block = self._block("function AI:_removeFromListDifferentCardOfGivenType")
        self.assertIn("self.rng:shuffleCards(base, #list)", block)
        self.assertIn("deckIndex ~= avoidDeckIndex", block)
        self.assertIn("cardType == 1", block)  # Pokemon
        self.assertIn("cardType == 0", block)  # Trainer
        self.assertIn("cardType == 2", block)  # Energy

    def test_effect_side_already_registered_from_a_prior_round(self):
        effects_src = read("src/tcg/duel/EffectCommands.lua")
        for label in ("ComputerSearch_HandDeckCheck", "ComputerSearch_PlayerDiscardHandSelection",
                     "ComputerSearch_PlayerDeckSelection", "ComputerSearch_DiscardAddToHandEffect"):
            self.assertIn(f'self:register("{label}"', effects_src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ComputerSearchExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Computer Search AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
