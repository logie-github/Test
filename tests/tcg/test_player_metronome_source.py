from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PlayerMetronomeSourceTests(unittest.TestCase):
    def test_player_metronome_handlers_preserve_card_specific_energy_costs(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn('self:register("ClefableMetronome_UseAttackEffect"', src)
        self.assertIn('handlePlayerMetronomeEffect(s, context, 1)', src)
        self.assertIn('self:register("ClefairyMetronome_UseAttackEffect"', src)
        self.assertIn('handlePlayerMetronomeEffect(s, context, 3)', src)
        self.assertIn('writeSymbol8("wMetronomeEnergyCost", energyCost)', src)

    def test_metronome_uses_separate_defending_attack_selection(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function handlePlayerMetronomeEffect")
        end = src.index("local function metronomeAINoop", start)
        block = src[start:end]
        self.assertIn("selection.metronomeAttack", block)
        self.assertIn('selection_required:metronomeAttack', block)
        self.assertIn("copied.category == s.c.POKEMON_POWER", block)
        self.assertIn("copied.nameTextId or 0", block)

    def test_metronome_stores_selected_pair_and_rejects_metronome_by_name(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function handlePlayerMetronomeEffect")
        end = src.index("local function metronomeAINoop", start)
        block = src[start:end]
        self.assertIn('s:_readWord("wLoadedAttackName")', block)
        self.assertIn("copied.nameTextId == originalName", block)
        self.assertIn('s.memory:address("wMetronomeSelectedAttack")', block)
        self.assertIn("defendingDeckIndex", block)
        self.assertIn("attackIndex", block)

    def test_copied_initial_phases_execute_and_later_phases_are_preflighted(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function handlePlayerMetronomeEffect")
        end = src.index("local function metronomeAINoop", start)
        block = src[start:end]
        for phase in ("EFFECTCMDTYPE_INITIAL_EFFECT_1", "EFFECTCMDTYPE_INITIAL_EFFECT_2",
                      "EFFECTCMDTYPE_DISCARD_ENERGY", "EFFECTCMDTYPE_REQUIRE_SELECTION",
                      "EFFECTCMDTYPE_BEFORE_DAMAGE", "EFFECTCMDTYPE_AFTER_DAMAGE"):
            self.assertIn(phase, block)
        self.assertIn("s:validatePhases(phases)", block)
        self.assertGreaterEqual(block.count("s:tryExecute("), 2)

    def test_nested_copied_attack_selection_and_transport_boundary_are_preserved(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function handlePlayerMetronomeEffect")
        end = src.index("local function metronomeAINoop", start)
        block = src[start:end]
        self.assertIn("selection.metronomeEffect", block)
        self.assertIn("context.selection = nestedSelection", block)
        self.assertIn("s.adapters.sendMetronomeAttack", block)
        self.assertIn('writeSymbol8("wPlayerAttackingCardIndex", defendingDeckIndex)', block)
        self.assertIn('writeSymbol8("wPlayerAttackingAttackIndex", attackIndex)', block)

    def test_combat_refreshes_loaded_attack_category_after_initial_effect_2(self):
        src = read("src/tcg/duel/Combat.lua")
        self.assertIn('local activeAttackCategory = self.memory:readSymbol8("wLoadedAttackCategory")', src)
        self.assertIn('{ category = activeAttackCategory }', src)
        self.assertIn("applyTransparencyIfApplicable(damage, activeAttackCategory)", src)


if __name__ == "__main__":
    unittest.main()
