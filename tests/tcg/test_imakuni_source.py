"""Imakuni? AI decision + effect (trainer_cards.asm AIDecide_Imakuni,
AIPlay_Imakuni; effect_functions.asm ImakuniEffect).

The real threshold check (plays whenever the Active isn't already Confused,
with no attempt to avoid the self-inflicted downside) is exercised for real
by lua_fixtures/imakuni_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below. These source-shape checks only confirm the
pieces are wired together and that the effect's two immunities (Clefairy
Doll/Mysterious Fossil always, Snorlax only while its own power is active)
are both present, targeting the turn duelist's own Active card (not the
opponent's, unlike the attack-side QueueStatusCondition helper).
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/imakuni_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ImakuniSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "IMAKUNI_CARD" then\n'
            "    return self:_decideImakuni()",
            self.ai_src,
        )
        self.assertIn('or constantName == "IMAKUNI_CARD"', self.ai_src)
        self.assertIn('[1] = { "IMAKUNI_CARD", "GAMBLER" }', self.ai_src)

    def test_decide_checks_confused_only(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideImakuni"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn("self.c.CNF_SLP_PRZ", block)
        self.assertIn("status ~= self.c.CONFUSED", block)

    def test_effect_is_registered_with_both_immunities(self):
        start = self.effects_src.index('self:register("ImakuniEffect"')
        end = self.effects_src.index('self:register(', start + 1)
        block = self.effects_src[start:end]
        self.assertIn("s.c.CLEFAIRY_DOLL", block)
        self.assertIn("s.c.MYSTERIOUS_FOSSIL", block)
        self.assertIn("s.c.SNORLAX", block)
        self.assertIn("checkIsIncapableOfUsingPkmnPower", block)
        self.assertIn("a.duelVars:get(s.c.DUELVARS_ARENA_CARD)", block)
        self.assertIn("bit.band(status, s.c.PSN_DBLPSN), s.c.CONFUSED", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ImakuniExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Imakuni AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
