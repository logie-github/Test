"""src/tcg/states/PracticePlayable.lua -- replaces the plain-text placeholder
duel screen ("SAM'S PRACTICE DUEL [development UI]") with real card art
(decoded and colorized via CardPalette from the imported ROM), HP bars, and
a bordered field/menu layout. Still a stylized approximation, not a
byte-exact recreation of the cartridge's own duel renderer.

Card art comes from RomExtractor:extractCardGraphic's `gfx.image` (the
mod's in-memory shape) or `gfx.path` (the canonical dev-mode, Data.lua
on-disk cache shape) -- both are plain grayscale until CardPalette.colorize
runs, so cardImage() handles both and always recolors.

Shared between PracticeSession and DuelSession (src/tcg/duel/
DuelSession.lua) -- DuelSession has no repeatTurn() (there is no "undo" in
a real duel; that's a practice-duel-only rewind tied to Practice.lua's
save/restore path), so update()'s "b" handler must check for it rather
than assume every session implements it. A real player hit exactly this:
pressing B on the free-duel screen crashed with "attempt to call method
'repeatTurn' (a nil value)" because the first version of this file called
it unconditionally -- draw() was tested thoroughly but update() (the only
place that call happens) was not.

Exercised for real by lua_fixtures/practice_playable_smoke.lua under
LuaJIT (14 checks): draws for the player's turn, a scrolled action list,
the opponent's turn, both win/loss result phases, a side with no active
Pokemon and an empty bench, and now update() itself -- pressing A invokes
performAction, pressing B is a no-op against a session without
repeatTurn (confirmed to reproduce the real crash when the guard is
removed) and still invokes it against one that has it -- all against a
love.graphics/love.image stub, so every call and layout branch runs as
real Lua, not just a source-shape assertion.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/practice_playable_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PracticePlayableSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/states/PracticePlayable.lua")

    def test_card_image_handles_both_mod_and_dev_mode_gfx_shapes(self):
        start = self.src.index("function PracticePlayable:cardImage")
        end = self.src.index("\nend", start)
        block = self.src[start:end]
        self.assertIn("gfx.image", block)
        self.assertIn("gfx.path", block)
        self.assertIn("CardPalette.colorize", block)

    def test_card_image_is_cached_by_id(self):
        start = self.src.index("function PracticePlayable:cardImage")
        end = self.src.index("\nend", start)
        block = self.src[start:end]
        self.assertIn("self.imageCache[cardId]", block)

    def test_color_is_reset_to_white_before_drawing_art(self):
        # love.graphics.draw tints by the current color; without resetting
        # to white right before it, card art would inherit whatever color
        # text/border drawing last set (e.g. render solid black).
        start = self.src.index("function PracticePlayable:drawCardFrame")
        end = self.src.index("\nend", start)
        block = self.src[start:end]
        draw_call = block.index("g.draw(image")
        preceding = block[:draw_call]
        self.assertIn("COLOR_WHITE", preceding[preceding.rindex("g.setColor"):])

    def test_action_list_scrolls_to_keep_cursor_visible(self):
        self.assertIn("firstRow = self.cursor - maxRows + 1", self.src)

    def test_practice_state_uses_gen1recomp_input(self):
        for token in ('wasPressed("up")', 'wasPressed("down")',
                      'wasPressed("a")', 'wasPressed("b")'):
            self.assertIn(token, self.src)
        self.assertIn('self.session:availableActions()', self.src)
        self.assertIn('self.session:performAction(action)', self.src)
        self.assertIn('self.session:repeatTurn()', self.src)

    def test_repeat_turn_is_guarded_for_sessions_without_it(self):
        self.assertIn('self.session.repeatTurn then', self.src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class PracticePlayableExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all practice playable cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
