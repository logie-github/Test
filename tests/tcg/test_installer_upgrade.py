import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPLY = ROOT / "tools/tcg/apply_foundation.py"
spec = importlib.util.spec_from_file_location("tcg_apply_foundation", APPLY)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

DATA_LAYER_REQUIRED = '''    requiredFiles = {
      "data/generated/tcg_meta.lua",
      "data/generated/tcg_constants.lua",
      "data/generated/tcg_text.lua",
      "data/generated/tcg_cards.lua",
      "data/generated/tcg_decks.lua",
      "assets/generated/tcg/cards/001.png",
    },'''


class InstallerUpgradeTests(unittest.TestCase):
    def test_previous_data_layer_profile_upgrades_required_files(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            p = root / "src/core/GameVersion.lua"
            p.parent.mkdir(parents=True)
            p.write_text(
                '''local GameVersion = {}\nGameVersion.VERSIONS = {\n  tcg = {\n    id = "tcg",\n'''
                + DATA_LAYER_REQUIRED
                + '''\n  },\n}\nGameVersion.ORDER = { "red", "blue", "yellow", "tcg" }\nreturn GameVersion\n''',
                encoding="utf-8",
            )
            mod.patch_game_version(root)
            out = p.read_text(encoding="utf-8")
            self.assertIn('"data/generated/tcg_memory.lua"', out)
            self.assertIn('"data/generated/tcg_core.lua"', out)
            self.assertIn('"data/generated/tcg_effects.lua"', out)
            self.assertEqual(out.count('"data/generated/tcg_core.lua"'), 1)
            self.assertEqual(out.count('"data/generated/tcg_effects.lua"'), 1)
            self.assertIn('cacheFormat = "tcg-rom-cache-v5:"', out)

    def test_previous_common_damage_profile_upgrades_v3_cache_and_effect_file(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            p = root / "src/core/GameVersion.lua"
            p.parent.mkdir(parents=True)
            p.write_text(
                '''local GameVersion = {}\nGameVersion.VERSIONS = {\n  tcg = {\n'''
                '''    id = "tcg",\n    cachePrefix = "tcg/",\n'''
                '''    cacheFormat = "tcg-rom-cache-v3:",\n'''
                '''    requiredFiles = {\n'''
                '''      "data/generated/tcg_meta.lua",\n'''
                '''      "data/generated/tcg_memory.lua",\n'''
                '''      "data/generated/tcg_constants.lua",\n'''
                '''      "data/generated/tcg_core.lua",\n'''
                '''      "data/generated/tcg_text.lua",\n'''
                '''      "data/generated/tcg_cards.lua",\n'''
                '''      "data/generated/tcg_decks.lua",\n'''
                '''      "assets/generated/tcg/cards/001.png",\n'''
                '''    },\n  },\n}\n'''
                '''GameVersion.ORDER = { "red", "blue", "yellow", "tcg" }\n'''
                '''return GameVersion\n''',
                encoding="utf-8",
            )
            mod.patch_game_version(root)
            out = p.read_text(encoding="utf-8")
            self.assertIn('cacheFormat = "tcg-rom-cache-v5:"', out)
            self.assertNotIn('cacheFormat = "tcg-rom-cache-v3:"', out)
            self.assertEqual(out.count('"data/generated/tcg_effects.lua"'), 1)


if __name__ == "__main__":
    unittest.main()
