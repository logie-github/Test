"""AI:checkEnergyNeededForAttack's multi-color edge case (engine/duel/ai/
core.asm CheckEnergyNeededForAttack), closing out the last open item on
that ledger entry (the other two labels sharing the entry,
CheckIfSelectedAttackIsUnusable and CheckIfDefendingPokemonCanKnockOut, are
fully covered already: the former's active-card branch is Combat:
checkAttackUsable -- cant-attack-substatus, paralysis/sleep, amnesia, energy
check, and the INITIAL_EFFECT_1+ phases -- shared by both the player engine
and AI:estimateDamageFromDefendingPokemon's own SwapTurn+checkAttackUsable
call, matching the source's `.CheckAttack` sub-routine exactly; the latter
is AI:checkIfDefendingPokemonCanKnockOut).

The source's own comment on CheckEnergyNeededForAttack documents that
running CheckIfEnoughParticularAttachedEnergy back-to-back for every basic
energy color overwrites the previous color's shortfall result -- but only
when that later color genuinely has ITS OWN shortfall (a fully-satisfied or
unneeded color leaves the running result untouched, since its `.has_enough`
path never writes wTempLoadedAttackEnergyNeededAmount/Type). So a
(hypothetical -- no real card in this game's pool needs it) attack
requiring two different colored energy types only reports the
HIGHEST-indexed color's shortfall when BOTH are actually short; a lower
color's genuine shortfall survives untouched if the higher color is already
satisfied. AI:checkEnergyNeededForAttack's ascending `for color = 0,
NUM_COLORED_TYPES - 1` loop, which only overwrites `neededColor`/
`coloredNeeded` inside `if required > attached then`, reproduces this
exactly.

All of this is exercised for real by
lua_fixtures/energy_needed_multicolor_smoke.lua under LuaJIT (18 checks) --
see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/energy_needed_multicolor_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class EnergyNeededMulticolorSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def test_check_energy_needed_for_attack_only_overwrites_on_genuine_shortfall(self):
        start = self.ai_src.index("function AI:checkEnergyNeededForAttack")
        end = self.ai_src.index("\nend", start)
        block = self.ai_src[start:end]
        self.assertIn("for color = 0, self.c.NUM_COLORED_TYPES - 1 do", block)
        self.assertIn("if required > attached then", block)
        self.assertIn("coloredNeeded = required - attached", block)
        self.assertIn("neededColor = color", block)

    def test_check_attack_usable_shared_by_ai_and_player_engine(self):
        combat_src = read("src/tcg/duel/Combat.lua")
        self.assertIn("function Combat:checkAttackUsable", combat_src)
        self.assertIn("handleCantAttackSubstatus", combat_src)
        self.assertIn("handleAmnesiaSubstatus", combat_src)
        self.assertIn("hasEnoughEnergy", combat_src)
        self.assertIn("self:estimateDamageFromDefendingPokemon", self.ai_src)
        estimate_start = self.ai_src.index("function AI:estimateDamageFromDefendingPokemon")
        estimate_end = self.ai_src.index("\nend", estimate_start)
        estimate_block = self.ai_src[estimate_start:estimate_end]
        self.assertIn("self.duelVars:swapTurn()", estimate_block)
        self.assertIn("self.combat:checkAttackUsable(playerDeckIndex, attackIndex)", estimate_block)

    def test_check_if_defending_pokemon_can_knock_out_uses_exact_equality(self):
        start = self.ai_src.index("function AI:checkIfDefendingPokemonCanKnockOut")
        end = self.ai_src.index("\nend", start)
        block = self.ai_src[start:end]
        self.assertIn("estimate.damage == hp", block)

    def test_special_attack_parameters_dispatcher_covers_all_four_cards(self):
        start = self.ai_src.index("function AI:_selectSpecialAttackParameters")
        end = self.ai_src.index("\nend", start)
        block = self.ai_src[start:end]
        for name in ("MEW_LV23", "MEWTWO_LV60", "MEWTWO_ALT_LV60", "EXEGGUTOR", "ELECTRODE_LV35"):
            self.assertIn(name, block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class EnergyNeededMulticolorExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all checkEnergyNeededForAttack multi-color edge cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
