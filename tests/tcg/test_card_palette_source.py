"""src/tcg/states/CardPalette.lua -- colorizes the grayscale ImageData that
ImageWriter.decode2bpp produces using the palette bytes RomExtractor already
extracts alongside each card's tiles (extractCardGraphic's `palette` field)
but never applies. Card art was rendering in flat grayscale; this closes
that gap so the duel screen can show real card colors.

Format verified against gbdev/rgbds's own Rgba::fromCGBColor (src/gfx/
rgba.cpp): a GBC color is a little-endian packed word (byte0 | byte1<<8),
5 bits per channel (r | g<<5 | b<<10), each channel expanded 5-to-8 bit via
(v5<<3)|(v5>>2) -- the exact bytes rgbgfx's own `--colors embedded
--auto-palette` (this project's card gfx Makefile rule) emits.

Exercised for real by lua_fixtures/card_palette_smoke.lua under LuaJIT (27
checks: known BGR555 reference colors decoded exactly, plus a colorize pass
against a fake ImageData seeded with decode2bpp's four exact shade levels,
including that a transparent pixel is left untouched).
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/card_palette_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CardPaletteSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/states/CardPalette.lua")

    def test_decode_reads_little_endian_bgr555(self):
        self.assertIn("lo + hi * 256", self.src)
        self.assertIn("word % 32", self.src)
        self.assertIn("math.floor(word / 32) % 32", self.src)
        self.assertIn("math.floor(word / 1024) % 32", self.src)

    def test_expand5to8_matches_rgbgfx_default_curve(self):
        self.assertIn("(v5 * 8) + math.floor(v5 / 4)", self.src)

    def test_colorize_skips_transparent_pixels(self):
        start = self.src.index("function CardPalette.colorize")
        end = self.src.index("\nend", start)
        block = self.src[start:end]
        self.assertIn("if a > 0 then", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class CardPaletteExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all card palette cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
