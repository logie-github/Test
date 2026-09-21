"""Ditto's Morph (engine/duel/effect_functions.asm), part of the final
batch of standalone attack effects closing the card-effects sweep.

Shuffles the attacker's own Deck (excluding other Dittos, via
pickRandomBasicCardFromDeck's new excludeCardId parameter) for a random
Basic Pokemon, then transforms the Attacking Pokemon into it. Unlike
Devolution Beam's slot-content swap, this permanently overwrites the
arena's OWN deck slot's card-identity entry via the new
CardData:setCardIDForDeckIndex (a write-side counterpart to the existing
getCardIDFromDeckIndex) -- the picked deck card itself is untouched and
stays in the deck. If the Attacking Pokemon isn't already Basic (e.g.
copied via Metronome from an evolved Pokemon), first discards its
pre-evolution card and resets its own stage to Basic, reusing the
Devolution Spray/Beam family's cardOneStageBelow helper.

Exercised for real by lua_fixtures/morph_effect_smoke.lua under LuaJIT
(20 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/morph_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MorphEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")
        self.card_data_src = read("src/tcg/duel/CardData.lua")

    def _block(self):
        start = self.src.index('self:register("MorphEffect"')
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_pick_random_basic_card_gained_an_exclude_card_id_parameter(self):
        self.assertIn(
            "local function pickRandomBasicCardFromDeck(s, a, excludeCardId)", self.src)
        self.assertIn("and cardId ~= excludeCardId then", self.src)

    def test_card_data_gained_a_write_side_deck_index_id_setter(self):
        self.assertIn("function CardData:setCardIDForDeckIndex(deckIndex, cardId)", self.card_data_src)

    def test_morph_excludes_ditto_and_bails_on_no_candidate(self):
        block = self._block()
        self.assertIn("pickRandomBasicCardFromDeck(s, actor, s.c.DITTO)", block)
        self.assertIn("if pickedDeckIndex == nil then return false end", block)

    def test_morph_discards_pre_evolution_card_when_not_basic(self):
        block = self._block()
        self.assertIn("if ownStage ~= s.c.BASIC then", block)
        self.assertIn("cardOneStageBelow(s, actor, s.c.PLAY_AREA_ARENA)", block)
        self.assertIn("actor.duelOps:putCardInDiscardPile(lower)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STAGE, s.c.BASIC)", block)

    def test_morph_overwrites_own_slot_identity_and_heals_to_new_max_hp(self):
        block = self._block()
        self.assertIn("actor.cardData:setCardIDForDeckIndex(ownDeckIndex, newCardId)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, newRow.hp)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_CHANGED_TYPE, 0)", block)
        self.assertIn("actor.duelOps:clearAllStatusConditions()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class MorphEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all morph effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
