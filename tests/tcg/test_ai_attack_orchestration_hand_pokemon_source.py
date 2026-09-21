from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AIAttackOrchestrationHandPokemonSourceTests(unittest.TestCase):
    def test_attack_processing_restores_preview_scores_and_honors_pluspower_override(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:processButDontUseAttack", src)
        self.assertIn("function AI:_snapshotAttackProcessingScores", src)
        self.assertIn("function AI:_restoreAttackProcessingScores", src)
        self.assertIn("AI_FLAG_USED_PLUSPOWER", src)
        self.assertIn('self.memory:readSymbol8("wAIPlusPowerAttack")', src)
        self.assertIn('self.memory:writeSymbol8("wFirstAttackAIScore", first)', src)

    def test_attack_processing_updates_retreat_pressure_like_source(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_processAttacks")
        end = src.index("function AI:processButDontUseAttack", start)
        block = src[start:end]
        self.assertIn("processHandTrainerCards(14)", block)
        self.assertIn("estimate.damage ~= 0", block)
        self.assertIn("DAMAGE_TO_OPPONENT_BENCH_F", block)
        self.assertIn('self.memory:writeSymbol8("wAIRetreatScore", 0)', block)
        self.assertIn('self.memory:writeSymbol8("wAITriedAttack", self.c.TRUE)', block)

    def test_basic_pokemon_scoring_includes_legendary_bird_policy(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_legendaryBirdPlayScore")
        end = src.index("function AI:_isPrehistoricPowerActive", start)
        block = src[start:end]
        for name in ("ARTICUNO_LV37", "MOLTRES_LV37", "ZAPDOS_LV68",
                     "LEGENDARY_ZAPDOS_DECK_ID", "LEGENDARY_ARTICUNO_DECK_ID",
                     "LEGENDARY_RONALD_DECK_ID"):
            self.assertIn(f"self.c.{name}", block)
        self.assertIn("decideWhetherToRetreat", block)
        self.assertIn("countPokemonWithActivePkmnPowerInBothPlayAreas", block)
        self.assertIn("playCount >= self.c.MAX_BENCH_POKEMON", block)

    def test_evolution_scoring_preserves_source_bug_and_threshold(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_scoreEvolution")
        end = src.index("-- AIDecideEvolution::", start)
        block = src[start:end]
        self.assertIn("temporarily replaces only the deck index", block)
        self.assertIn("current.aiInfo == self.c.AI_INFO_ENCOURAGE_EVO", block)
        self.assertIn("math.floor(damage / 40)", block)
        self.assertIn("PIKACHU_DECK_ID", block)
        self.assertIn("satSub(score, 20)", block)
        self.assertIn("satAdd(score, 7)", block)
        self.assertIn("score = satAdd(score, 4)", block)

    def test_special_evolution_deck_branches_are_native(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_specialEvolutionScore")
        end = src.index("function AI:_scoreEvolution", start)
        block = src[start:end]
        for name in ("LEGENDARY_DRAGONITE_DECK_ID", "INVINCIBLE_RONALD_DECK_ID",
                     "LEGENDARY_RONALD_DECK_ID", "CHARMELEON", "MAGIKARP",
                     "DRAGONAIR", "GRIMER"):
            self.assertIn(f"self.c.{name}", block)
        self.assertIn("totalDamage <= 70", block)
        self.assertIn("_countAttachedEnergyCards", block)

    def test_evolution_respects_prehistoric_power_and_133_threshold(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_isPrehistoricPowerActive", src)
        self.assertIn("self.c.AERODACTYL", src)
        self.assertIn("self.c.MUK", src)
        start = src.index("function AI:decideEvolution")
        end = src.index("-- AIDecidePlayPokemonCard::", start)
        block = src[start:end]
        self.assertIn("if self:_isPrehistoricPowerActive() then return true end", block)
        self.assertIn("if score >= 133 then", block)
        self.assertIn("self.playerActions:evolve", block)


if __name__ == "__main__":
    unittest.main()
