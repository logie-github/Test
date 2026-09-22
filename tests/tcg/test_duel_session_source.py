"""src/tcg/duel/DuelSession.lua -- a generic, non-scripted duel session:
dynamic per-turn action menu (computed from live game state, not a fixed
script like PracticeSession's), interactive starting-hand/bench selection,
and interactive prize/knockout-replacement choices via a coroutine (those
adapters fire synchronously, nested arbitrarily deep inside one boot()/turn
call -- including mid-opponent-turn, if their attack knocks out your active
Pokemon).

v1 scope (see the file's own header comment for the full rationale): a
fixed matchup (Squirtle and Friends vs Charmander and Friends, two real
ROM decks), and Bill/Professor Oak/Full Heal/Potion/Switch/Scoop Up wired
into the menu -- Computer Search/Item Finder/Poke Ball/PlusPower are real
cards in those decks not wired to a picker yet.

Exercised for real end to end (boot -> interactive setup -> 8 real turns
-> a real win/loss conclusion, 52 checks) against a real, from-source-built
poketcg.gbc this session -- not committed here (no ROM bytes, ever) but
the run is what found and fixed three real bugs along the way:
  - DuelSession's own attackIndex off-by-one (row.attacks is a 1-indexed
    Lua array; Combat/PlayerActions take the source's 0-based index).
  - AI.lua's `wrMask` local function was defined *after* two call sites
    that used it (Lua locals aren't hoisted), so both silently resolved to
    a nonexistent global and crashed the first time the AI's general
    forward/reverse damage estimator actually ran end to end.
  - Combat.lua's dealRecoilDamageToSelf referenced a misspelled constant,
    ATK_ANIM_RECOIL_HIT (real name: ATK_ANIM_HIT_RECOIL), and a
    build_manifest.py gap (a hardcoded, incomplete constants-file list)
    meant 20 real ATK_ANIM_* constants referenced across the engine were
    silently absent from every manifest built before this fix -- unnoticed
    because no prior real-ROM validation had ever executed those specific
    animation-writing code paths.

lua_fixtures/duel_session_menu_smoke.lua exercises _turnActions() (the
dynamic menu builder) directly against a hand-built fake runtime -- 16
checks covering the attackIndex conversion, the unused-attack-slot skip,
the once-per-turn energy gate, the CAN_EVOLVE_THIS_TURN gate, and the
once-per-turn retreat gate.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/duel_session_menu_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DuelSessionSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/DuelSession.lua")

    def test_uses_a_coroutine_for_nested_player_decisions(self):
        self.assertIn("self.co = coroutine.create", self.src)
        self.assertIn("coroutine.yield()", self.src)
        self.assertIn("coroutine.resume(self.co, value)", self.src)

    def test_setup_prize_knockout_adapters_force_player_phase(self):
        for token in (
            'selectInitialActive = function(turn) return self:_yieldAsPlayer',
            'selectInitialBench = function(turn) return self:_yieldAsPlayer',
            'selectPrizeCard = function(mask, remaining)',
            'selectKnockoutReplacement = function() return self:_yieldAsPlayer',
        ):
            self.assertIn(token, self.src)

    def test_attack_index_is_converted_from_lua_1_indexed_loop(self):
        self.assertIn("local attackIndex = luaIndex - 1", self.src)

    def test_skips_unused_attack_slots(self):
        self.assertIn("if attack.nameTextId ~= 0 then", self.src)

    def test_evolve_offer_checks_can_evolve_this_turn_flag(self):
        self.assertIn("c.DUELVARS_ARENA_CARD_FLAGS + target.slot", self.src)
        self.assertIn("bit.band(flags, c.CAN_EVOLVE_THIS_TURN) ~= 0", self.src)

    def test_retreat_reuses_ai_execution_path_with_disclosed_caveat(self):
        self.assertIn("r.ai:tryToRetreat(action.slot)", self.src)

    def test_end_turn_is_always_offered_and_completes_the_turn(self):
        self.assertIn('kind = "end_turn"', self.src)
        self.assertIn('action.kind == "end_turn"', self.src)

    def test_fixed_matchup_uses_real_deck_constants(self):
        self.assertIn("c.SQUIRTLE_AND_FRIENDS_DECK", self.src)
        self.assertIn("c.CHARMANDER_AND_FRIENDS_DECK_ID", self.src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class DuelSessionExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all duel session menu cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


class AIWrMaskFixTests(unittest.TestCase):
    """AI.lua's wrMask helper: verified missing/broken until this session
    (see DuelSessionSourceTests' module docstring) -- a Lua `local
    function` isn't visible before its own declaration, so the two call
    sites at the old line ~825/872 resolved it as a nonexistent global.
    """

    def test_wrmask_is_defined_before_first_use(self):
        src = read("src/tcg/duel/AI.lua")
        definition_at = src.index("local function wrMask")
        first_use_at = src.index("wrMask(color)")
        self.assertLess(definition_at, first_use_at)
        self.assertEqual(src.count("local function wrMask"), 1)


class CombatRecoilAnimationFixTests(unittest.TestCase):
    def test_uses_the_real_atk_anim_hit_recoil_constant(self):
        src = read("src/tcg/duel/Combat.lua")
        self.assertIn("self.c.ATK_ANIM_HIT_RECOIL", src)
        self.assertNotIn("ATK_ANIM_RECOIL_HIT", src)


class BuildManifestConstantsCoverageTests(unittest.TestCase):
    def test_scans_every_constants_file_not_a_curated_subset(self):
        src = read("tools/tcg/build_manifest.py")
        self.assertIn('(root / "src/constants").glob("*.asm")', src)


if __name__ == "__main__":
    unittest.main()
