from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AISelectionForcedSwitchSourceTests(unittest.TestCase):
    def _read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_runtime_wires_ai_back_into_effect_dispatcher(self):
        src = self._read("src/tcg/duel/Runtime.lua")
        self.assertIn("effectCommands:setAI(ai)", src)
        effects = self._read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("function EffectCommands:setAI(ai)", effects)

    def test_ai_forced_switch_preserves_sam_general_and_special_table_routes(self):
        src = self._read("src/tcg/duel/AI.lua")
        start = src.index("function AI:forcedSwitch()")
        end = src.index("-- AIDoAction_KOSwitch::", start)
        block = src[start:end]
        self.assertIn('label == "AIActionTable_SamPractice" and self:isSamPracticeScriptedTurn()', block)
        self.assertIn("slot = self:pickRandomBenchPokemon()", block)
        self.assertIn("slot, reason = self:decideBenchPokemonToSwitchTo()", block)
        self.assertIn("self.adapters.forcedSwitchSpecial", block)
        self.assertIn('"untranslated_ai_forced_switch_table:" .. label', block)
        self.assertIn('self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)', block)

    def test_duelist_select_forced_switch_routes_link_human_and_ai_defenders(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function duelistSelectForcedSwitch")
        end = src.index("local function forcedSwitchSelection", start)
        block = src[start:end]
        self.assertIn("DUELIST_TYPE_LINK_OPP", block)
        self.assertIn('"receiveForcedSwitch"', block)
        self.assertIn("DUELIST_TYPE_PLAYER", block)
        self.assertIn('s:_selectBench(context, actor, true, "opponentBench")', block)
        self.assertIn("actor.duelVars:swapTurn()", block)
        self.assertIn("ai:forcedSwitch()", block)
        self.assertIn("combat:loadAttack(cardIndex, attackIndex)", block)
        self.assertIn("combat:updateArenaCardIDsAndClearTwoTurnDuelVars()", block)

    def test_all_five_ai_switch_function_identities_are_registered(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "ButterfreeWhirlwind_CheckBench",
            "PidgeottoWhirlwind_SelectEffect",
            "PidgeyWhirlwind_SelectEffect",
            "Ram_SelectSwitchEffect",
            "TerrorStrike_50PercentSelectSwitchPokemon",
        ):
            self.assertIn(f'self:register("{label}"', src)

    def test_lure_ai_selectors_reuse_lowest_hp_later_slot_policy(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        self.assertIn(
            'self:register("NinetalesLure_AISelectEffect", selectLowestBenchForAI(false))', src
        )
        self.assertIn(
            'self:register("VictreebelLure_GetBenchPokemonWithLowestHP", selectLowestBenchForAI(false))', src
        )
        helper_start = src.index("local function aiFindTargetForBenchAttack")
        helper_end = src.index("local function nonTurnPlayAreaCount", helper_start)
        helper = src[helper_start:helper_end]
        self.assertIn("if hp <= bestHP then", helper)

    def test_lure_switch_preserves_selected_target_nshield_and_transparency(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function lureSwitch")
        end = src.index('self:register("NinetalesLure_CheckBench"', start)
        block = src[start:end]
        self.assertIn("cardId == s.c.MEW_LV8", block)
        self.assertIn("DUELVARS_ARENA_CARD_STAGE", block)
        self.assertIn("NO_DAMAGE_OR_EFFECT_NSHIELD", block)
        self.assertIn("cardId == s.c.HAUNTER_LV17", block)
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn("NO_DAMAGE_OR_EFFECT_TRANSPARENCY", block)
        self.assertIn("actor.duelOps:swapArenaWithBenchPokemon(slot)", block)
        self.assertNotIn("wDefendingWasForcedToSwitch", block)

    def test_ram_preserves_recoil_then_forced_switch(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Ram_SelectSwitchEffect"')
        end = src.index('self:register("TerrorStrike_50PercentSelectSwitchPokemon"', start)
        block = src[start:end]
        self.assertIn('self:register("Ram_SelectSwitchEffect", forcedSwitchSelection)', block)
        self.assertIn("dealRecoilDamageToSelf(20)", block)
        self.assertIn("return forcedSwitchEffect(s, context)", block)

    def test_terror_strike_keeps_coin_in_ffa0_and_target_in_ffa1(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("TerrorStrike_50PercentSelectSwitchPokemon"')
        end = src.index("-- Ninetales/Victreebel Lure", start)
        block = src[start:end]
        self.assertIn('writeSymbol8("hTemp_ffa0", s.c.TAILS)', block)
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", result)', block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", slot)', block)
        self.assertIn('readSymbol8("hTempPlayAreaLocation_ffa1")', block)


if __name__ == "__main__":
    unittest.main()
