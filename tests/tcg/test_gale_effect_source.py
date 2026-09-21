"""Pidgeot's Gale (engine/duel/effect_functions.asm), part of the broader
card-effects sweep.

Gale_LoadAnimation: sets the Gale animation, unconditional.
Gale_SwitchEffect: unless the attack was unaffected
(Status:checkNoDamageOrEffect), switches the Defending Pokemon to a random
Bench slot -- triggering Destiny Bond first if the Defending Pokemon's HP
is already 0, and clearing wDealtDamage if the switch actually happened --
then always switches the Attacking Pokemon to a random Bench slot too,
whether or not the Defending-side switch ran. Reuses
DuelOps:swapArenaWithBenchPokemon and Status:handleDestinyBondSubstatus
(both already registered elsewhere), but keeps its own body rather than
reusing the existing forcedSwitchEffect helper since the real ASM's check
order (prevented, then Destiny Bond, then the switch) differs from
forcedSwitchEffect's (Destiny Bond, then prevented).

Exercised for real by lua_fixtures/gale_effect_smoke.lua under LuaJIT
(26 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/gale_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GaleEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_load_animation_sets_gale_animation_unconditionally(self):
        start = self.src.index('self:register("Gale_LoadAnimation"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_GALE)', block)

    def test_switch_effect_checks_prevented_before_destiny_bond(self):
        start = self.src.index('self:register("Gale_SwitchEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        prevented_at = block.index("s.status:checkNoDamageOrEffect()")
        destiny_at = block.index("combat.status:handleDestinyBondSubstatus()")
        self.assertLess(prevented_at, destiny_at)
        self.assertIn("combat.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP) == 0", block)
        self.assertIn('s:_writeWord("wDealtDamage", 0)', block)
        self.assertEqual(block.count("switchToRandomBenchPokemon(s, combat)"), 2)

    def test_switch_to_random_bench_pokemon_reuses_swap_arena_primitive(self):
        start = self.src.index("local function switchToRandomBenchPokemon(s, actor)")
        end = self.src.index("\n  end", start)
        block = self.src[start:end]
        self.assertIn("s.setup.rng:random(count - 1) + 1", block)
        self.assertIn("actor.duelOps:swapArenaWithBenchPokemon(benchSlot)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class GaleEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all gale effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
