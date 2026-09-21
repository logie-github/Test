import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AISelectionBenchSourceTests(unittest.TestCase):
    def test_lowest_hp_helper_preserves_later_slot_tie_behavior(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function aiFindTargetForBenchAttack")
        end = src.index("local function nonTurnPlayAreaCount", start)
        block = src[start:end]
        self.assertIn("actor.duelVars:swapTurn()", block)
        self.assertIn("PLAY_AREA_BENCH_1", block)
        self.assertIn("DUELVARS_ARENA_CARD_HP + slot", block)
        self.assertIn("if hp <= bestHP then", block)
        self.assertIn("bestSlot = slot", block)

    def test_spark_and_dark_mind_use_no_bench_sentinel_then_lowest_hp_helper(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Spark_AISelectEffect",
            "GengarDarkMind_AISelectEffect",
            "HypnoDarkMind_AISelectEffect",
        ):
            self.assertIn(f'self:register("{label}", selectLowestBenchForAI(true))', src)
        start = src.index("local function selectLowestBenchForAI")
        end = src.index('self:register("Spark_AISelectEffect"', start)
        block = src[start:end]
        self.assertIn('writeSymbol8("hTemp_ffa0", 0xff)', block)
        self.assertIn("if count < 2 then return false end", block)
        self.assertIn("aiFindTargetForBenchAttack", block)

    def test_stretch_kick_preserves_source_assumption_of_prior_bench_check(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn(
            'self:register("StretchKick_AISelectEffect", selectLowestBenchForAI(false))',
            src,
        )
        self.assertIn('self:register("StretchKick_CheckBench"', src)

    def test_gigashock_selects_all_when_three_or_fewer_bench_targets_exist(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function gigashockAISelect")
        end = src.index('self:register("Gigashock_AISelectEffect"', start)
        block = src[start:end]
        self.assertIn("count < s.c.MAX_PLAY_AREA_POKEMON - 1", block)
        self.assertIn("for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do", block)
        self.assertIn("values[#values + 1] = 0xff", block)
        self.assertIn("writeTempList(s, values)", block)

    def test_gigashock_preserves_executable_high_hp_sort_quirk_and_tie_order(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function gigashockAISelect")
        end = src.index('self:register("Gigashock_AISelectEffect"', start)
        block = src[start:end]
        self.assertIn("if hp >= bestHP then", block)
        self.assertIn("values[i], values[j] = values[j], values[i]", block)
        self.assertIn("writeTempList(s, { values[1], values[2], values[3], 0xff })", block)
        self.assertIn("compare/swap instructions order by *highest* remaining HP first", src)

    def test_gigashock_player_selection_is_bounded_unique_bench_list(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Gigashock_PlayerSelectEffect"')
        end = src.index('self:register("Gigashock_BenchDamageEffect"', start)
        block = src[start:end]
        self.assertIn('"opponentBenchSlots"', block)
        self.assertIn('"selectOpponentBenchCards"', block)
        self.assertIn("}, 1, 3)", block)
        self.assertIn("PLAY_AREA_BENCH_1", block)
        self.assertIn("values[#values + 1] = 0xff", block)

    def test_gigashock_bench_damage_consumes_temp_list_until_ff(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Gigashock_BenchDamageEffect"')
        end = src.index("-- ThunderboltEffect::", start)
        block = src[start:end]
        self.assertIn('s.memory:address("hTempList")', block)
        self.assertIn("if slot == 0xff then return false end", block)
        self.assertIn("combat:dealDamageToPlayAreaPokemon(slot, 10, true)", block)
        self.assertIn("unterminated_gigashock_temp_list", block)


if __name__ == "__main__":
    unittest.main()
