"""Selfdestruct attack family (Weezing/Golem/Magnemite/Magneton Lv28/
Magneton Lv35, engine/duel/effect_functions.asm). Part of the broader
card-effects sweep: cross-checking every self:register() call
EffectCommands.lua actually makes AT RUNTIME (introspecting self.handlers
after real construction, not just grepping source text -- several existing
families, e.g. "Call for Family", build their registered names by string
concatenation in a loop, invisible to a plain text search and the source
of an earlier false "missing" count in this same sweep) against every
function name engine/duel/effect_commands.asm's 317 lists actually
reference (parsed with the project's own tools/tcg/build_manifest.py, 569
distinct names total) turned up ~66 genuinely unimplemented effects. This
closes the first five: all Selfdestruct.

Shape (identical across all five, only the two damage amounts differ):
DealRecoilDamageToSelf(recoil) to the attacker, then DealDamageToAll
BenchedPokemon for the attacker's own Bench (no SwapTurn), then the SAME
amount for the defender's Bench (SwapTurn-bracketed in the source, which
Combat:dealDamageToAllBenchedPokemon's targetNonTurn=true parameter already
models) -- reusing the exact primitives Blizzard/StretchKick/Spark/
GengarDarkMind/HypnoDarkMind already use elsewhere in this file, so no new
Combat-layer code was needed, only the five per-card registrations.

All of this is exercised for real by
lua_fixtures/selfdestruct_effect_smoke.lua under LuaJIT (62 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/selfdestruct_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SelfdestructEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_all_five_registered_with_source_accurate_amounts(self):
        start = self.src.index("local function registerSelfdestruct")
        end = self.src.index('registerSelfdestruct("MagnetonLv35SelfdestructEffect"', start)
        end = self.src.index("\n", end)
        block = self.src[start:end]
        for name, recoil, bench in (
            ("WeezingSelfdestructEffect", 60, 10),
            ("GolemSelfdestructEffect", 100, 20),
            ("MagnemiteSelfdestructEffect", 40, 10),
            ("MagnetonLv28SelfdestructEffect", 80, 20),
            ("MagnetonLv35SelfdestructEffect", 100, 20),
        ):
            self.assertIn(f'registerSelfdestruct("{name}", {recoil}, {bench})', block)

    def test_shared_factory_reuses_existing_combat_primitives(self):
        block = self.src[self.src.index("local function registerSelfdestruct"):
                          self.src.index("local function registerSelfdestruct") + 700]
        self.assertIn("combat:dealRecoilDamageToSelf(recoilAmount)", block)
        self.assertIn(
            "combat:dealDamageToAllBenchedPokemon(benchAmount, false, { isDamageToSelf = true })", block)
        self.assertIn(
            "combat:dealDamageToAllBenchedPokemon(benchAmount, true, { isDamageToSelf = false })", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class SelfdestructEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Selfdestruct effect cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
