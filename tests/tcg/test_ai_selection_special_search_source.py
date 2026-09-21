from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AISelectionSpecialSearchSourceTests(unittest.TestCase):
    def _read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_devolution_special_parameter_uses_source_ko_on_devolution_search(self):
        src = self._read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_getCardOneStageBelow(slot)", src)
        self.assertIn("function AI:_lookForCardThatIsKnockedOutOnDevolution()", src)
        self.assertIn("lowerRow.hp <= damage", src)
        self.assertIn('writeSymbol8("hTemp_ffa0", 0x01)', src)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", slot)', src)
        self.assertIn("return finish(true)", src)

    def test_teleport_special_parameter_uses_bench_scorer_not_random_selector(self):
        src = self._read("src/tcg/duel/AI.lua")
        start = src.index("if self.c.EXEGGUTOR")
        end = src.index("return finish(false)", start)
        block = src[start:end]
        self.assertIn("self:decideBenchPokemonToSwitchTo()", block)
        self.assertNotIn("self.rng:random", block)

    def test_generic_teleport_identity_preserves_random_zero_through_count_minus_one(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Teleport_AISelectEffect"')
        end = src.index('self:register("Teleport_SwitchEffect"', start)
        block = src[start:end]
        self.assertIn("actor.setup.rng:random(count)", block)
        self.assertNotIn("+ 1", block)

    def test_barrier_full_effect_list_is_registered(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Barrier_CheckEnergy", "Barrier_PlayerSelectEffect", "Barrier_AISelectEffect",
            "Barrier_DiscardEffect", "Barrier_BarrierEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("createFilteredArenaEnergyList", src)

    def test_amnesia_source_choice_prefers_usable_second_attack(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function amnesiaAISelect")
        end = src.index("local function amnesiaDisable", start)
        block = src[start:end]
        self.assertIn("handleEnergyBurn()", block)
        self.assertIn("second.energy[color]", block)
        self.assertIn("if enoughSecond then", block)
        self.assertIn("first.category == s.c.POKEMON_POWER", block)
        for prefix in ("PoliwhirlAmnesia", "SlowpokeAmnesia"):
            self.assertIn(f'prefix .. "_AISelectEffect"', src)

    def test_amnesia_disable_sets_substatus_disabled_attack_and_last_turn_effect(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function amnesiaDisable")
        end = src.index("for _, prefix in ipairs({ \"PoliwhirlAmnesia\"", start)
        block = src[start:end]
        self.assertIn("SUBSTATUS2_AMNESIA", block)
        self.assertIn("DUELVARS_ARENA_CARD_DISABLED_ATTACK_INDEX", block)
        self.assertIn("DUELVARS_ARENA_CARD_LAST_TURN_EFFECT", block)
        self.assertIn("LAST_TURN_EFFECT_AMNESIA", block)

    def test_family_selectors_scan_source_deck_order_and_noop_when_absent(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("local function familyAISelect(predicate)", src)
        self.assertIn("local deck = actor.duelOps:createDeckCardList()", src)
        self.assertIn('s.memory:writeSymbol8("hTemp_ffa0", deckIndex)', src)
        self.assertIn('s.memory:writeSymbol8("hTemp_ffa0", 0xff)', src)
        for prefix in (
            "Sprout", "BellsproutCallForFamily", "KrabbyCallForFamily",
            "NidoranFCallForFamily", "MarowakCallForFamily",
        ):
            self.assertIn(f'{{ "{prefix}"', src)

    def test_marowak_selector_requires_basic_fighting_pokemon(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function basicFighting")
        end = src.index("local families =", start)
        block = src[start:end]
        self.assertIn("row.type == s.c.FIGHTING", block)
        self.assertIn("row.stage == s.c.BASIC", block)

    def test_devolution_ai_identity_prefers_opponent_then_own_first_nonbasic(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("DevolutionBeam_AISelectEffect"')
        end = src.index('self:register("DevolutionBeam_LoadAnimation"', start)
        block = src[start:end]
        self.assertIn("firstNonBasic(s, actor, true)", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", 1)', block)
        self.assertIn("firstNonBasic(s, actor, false)", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", 0)', block)

    def test_devolution_effect_returns_top_stage_to_hand_and_preserves_damage(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("DevolutionBeam_DevolveEffect"')
        end = src.index("-- Energy Removal Trainer", start)
        block = src[start:end]
        self.assertIn("local damage = math.max(0, (current.hp or 0) - remaining)", block)
        self.assertIn("math.max(0, lowerRow.hp - damage)", block)
        self.assertIn("DUELVARS_ARENA_CARD_STAGE + slot", block)
        self.assertIn("actor.duelOps:addCardToHand(currentDeckIndex)", block)
        self.assertIn("handlePlayAreaPokemonPowerDamage", block)


if __name__ == "__main__":
    unittest.main()
