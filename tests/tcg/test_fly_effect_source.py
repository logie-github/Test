"""Pidgeot's Fly (engine/duel/effect_functions.asm) -- found by running the
real RomExtractor against a from-source-built, byte-identical poketcg.gbc
(SHA-1 verified against rom.sha1) and checking EffectCommands.lua's actual
runtime handlers against every real function label the ROM's 317
effect-command lists reference: this was the one genuine gap (568/569),
never previously caught by any prior sweep or ledger audit.

Unlike the existing protectCoin helper's tails branch (a bare
SetWasUnsuccessful), Fly's tails branch also explicitly resets the
animation to ATK_ANIM_NONE and zeroes damage via SetDefiniteDamage
(touching the AI hint fields too), so it is its own registration rather
than reusing protectCoin.

Exercised for real by lua_fixtures/fly_effect_smoke.lua under LuaJIT
(8 checks) -- see test_lua_execution_smoke below. Also re-validated end to
end against the real ROM extraction: after this fix, EffectCommands.lua's
runtime handlers cover 569/569 (100%) of every real function label
referenced by the actual cartridge's 317 effect-command lists.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/fly_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class FlyEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_fly_tails_resets_animation_and_zeroes_damage(self):
        start = self.src.index('self:register("Fly_Success50PercentEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_NONE)', block)
        self.assertIn("s:_setDefiniteDamage(0)", block)
        self.assertIn("return s:_setWasUnsuccessful()", block)

    def test_fly_heads_applies_fly_substatus(self):
        start = self.src.index('self:register("Fly_Success50PercentEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_AGILITY_PROTECT)', block)
        self.assertIn("s.status:applySubstatus1ToAttackingCard(s.c.SUBSTATUS1_FLY)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class FlyEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all fly effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
