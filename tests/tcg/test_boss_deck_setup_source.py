"""Specialized (boss) deck StartDuel/Turn action tables (engine/duel/ai/
{boss_deck_set_up,core}.asm SetUpBossStartingHandAndDeck /
TrySetUpBossStartingPlayArea; the per-deck AIActionTable_<Boss> wrappers in
engine/duel/ai/decks/*.asm; DeckAIPointerTable in data/deck_ai_pointers.asm).

Of the 55 decks in DeckAIPointerTable, only ~17 use a table other than
AIActionTable_GeneralDecks/GeneralNoRetreat/SamPractice (all three already
natively translated). All sixteen of those (Legendary Moltres/Zapdos/
Articuno/Dragonite, First Strike, Rock Crusher, Go Go Rain Dance, Zapping
Selfdestruct, Flower Power, Strange Psyshock, Wonders of Science, Fire
Charge, Im Ronald, Powerful Ronald, Invincible Ronald, Legendary Ronald)
were checked directly against their own engine/duel/ai/decks/*.asm source
and share byte-identical .start_duel/.forced_switch/.ko_switch/.take_prize
sequences -- the only per-deck variation is their own generated priority-
list data (already read through _deckAIList, same as every other deck-
aware routine in this file) and, for 5 of the 16, .do_turn (a bespoke
AIDoTurn_<Deck> -- each now natively translated too, in its own dedicated
fixture: legendary_{zapdos,moltres,dragonite,articuno,ronald}_turn_smoke.lua).

The real logic (the reshuffle-until-satisfied threshold loop, the capture-
then-draw ordering, and the Arena/Bench priority-list placement) is
exercised for real by lua_fixtures/boss_deck_setup_smoke.lua under LuaJIT --
see test_lua_execution_smoke below, which caught a genuine bug in an early
draft: TrySetUpBossStartingPlayArea used `hand[i] = nil` to mark a matched
hand card consumed, which silently breaks Lua's `ipairs` for every entry
after that index (ipairs stops at the first hole), making later-priority
Bench matches invisible. Fixed with `table.remove`.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/boss_deck_setup_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BossDeckSetupSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index(end_marker, start)
        return self.ai_src[start:end]

    def test_boss_action_table_sets_exist(self):
        self.assertIn("local AI_BOSS_ACTION_TABLES = {", self.ai_src)
        self.assertIn("local AI_BOSS_GENERAL_TURN_TABLES = {", self.ai_src)
        for label in (
            "AIActionTable_LegendaryMoltres", "AIActionTable_LegendaryZapdos",
            "AIActionTable_LegendaryArticuno", "AIActionTable_LegendaryDragonite",
            "AIActionTable_FirstStrike", "AIActionTable_RockCrusher",
            "AIActionTable_GoGoRainDance", "AIActionTable_ZappingSelfdestruct",
            "AIActionTable_FlowerPower", "AIActionTable_StrangePsyshock",
            "AIActionTable_WondersOfScience", "AIActionTable_FireCharge",
            "AIActionTable_ImRonald", "AIActionTable_PowerfulRonald",
            "AIActionTable_InvincibleRonald", "AIActionTable_LegendaryRonald",
        ):
            self.assertIn(label, self.ai_src)
        # Only these five have their own bespoke AIDoTurn_<Deck>.
        general_turn_block = self._block("local AI_BOSS_GENERAL_TURN_TABLES = {", "\n}\n")
        for bespoke in ("AIActionTable_LegendaryMoltres", "AIActionTable_LegendaryZapdos",
                       "AIActionTable_LegendaryArticuno", "AIActionTable_LegendaryDragonite",
                       "AIActionTable_LegendaryRonald"):
            self.assertNotIn(bespoke, general_turn_block)

    def test_setup_hand_and_deck_counts_across_both_ranges(self):
        block = self._block("function AI:setUpBossStartingHandAndDeck", "\nfunction AI:")
        self.assertIn("_countEnergyAndBasicInDeckRange(0, size)", block)
        self.assertIn("_countEnergyAndBasicInDeckRange(size, 6)", block)
        self.assertIn("basic1 + basic2 >= 4", block)
        self.assertIn("energy1 + energy2 >= 4", block)
        self.assertIn("self.duelOps:shuffleDeck()", block)
        self.assertIn("searchCardInDeckAndAddToHand", block)

    def test_avoid_prize_dead_branch_is_documented_not_reimplemented(self):
        comment = self._block("-- SetUpBossStartingHandAndDeck::", "\nfunction AI:")
        self.assertIn("cp a", comment)  # the real source bug, quoted in the comment
        body = self._block("function AI:setUpBossStartingHandAndDeck", "\nfunction AI:")
        self.assertNotIn("AvoidPrize", body)  # never actually consulted

    def test_play_area_setup_removes_matched_cards_safely(self):
        block = self._block("function AI:trySetUpBossStartingPlayArea", "\nfunction AI:")
        self.assertIn("table.remove(hand, i)", block)
        self.assertNotIn("hand[i] = nil", block)
        self.assertIn('self:_deckAIList("arenaPriority")', block)
        self.assertIn('self:_deckAIList("benchPriority")', block)
        self.assertIn("count < 3", block)

    def test_boss_start_duel_skips_initial_basics_on_play_area_failure(self):
        block = self._block("function AI:bossStartDuel", "\nfunction AI:startDuel")
        self.assertIn("if not self:trySetUpBossStartingPlayArea() then return end", block)
        self.assertIn("self:playInitialBasicCards()", block)

    def test_start_duel_routes_boss_labels_to_the_shared_sequence(self):
        block = self._block("function AI:startDuel", "\n-- PickRandomBenchPokemon")
        self.assertIn("AI_BOSS_ACTION_TABLES[label]", block)
        self.assertIn("self:bossStartDuel()", block)

    def test_forced_switch_and_ko_switch_include_boss_labels(self):
        forced = self._block("function AI:forcedSwitch", "\n-- AIDoAction_KOSwitch")
        self.assertIn("AI_BOSS_ACTION_TABLES[label]", forced)
        ko = self._block("function AI:koSwitch", "\n-- AIPickPrizeCards")
        self.assertIn("AI_BOSS_ACTION_TABLES[label]", ko)

    def test_do_turn_routes_the_eleven_generic_boss_labels_natively(self):
        block = self._block("function AI:doTurn", "\nreturn AI")
        self.assertIn("AI_BOSS_GENERAL_TURN_TABLES[label]", block)
        self.assertIn("self:mainTurnLogic(false)", block)
        self.assertIn('self:_required("turnSpecial")', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class BossDeckSetupExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all boss-deck setup cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
