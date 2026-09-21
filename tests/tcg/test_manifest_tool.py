import importlib.util
import pathlib
import struct
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "tcg" / "build_manifest.py"
spec = importlib.util.spec_from_file_location("tcg_manifest", TOOL)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ManifestToolTests(unittest.TestCase):
    def test_parse_symbols(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "poketcg.sym"
            p.write_text("00:0150 Start\n0c:4000 CardPointers\n", encoding="utf-8")
            self.assertEqual(mod.parse_symbols(p)["Start"], [0, 0x150])
            self.assertEqual(mod.parse_symbols(p)["CardPointers"], [0x0C, 0x4000])

    def test_parse_layout(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "layout.link"
            p.write_text('ROM0\n\t"start"\nROMX $0c\n\t"Cards"\n', encoding="utf-8")
            self.assertEqual(mod.parse_layout(p), [
                {"space": "rom", "bank": 0, "name": "start"},
                {"space": "rom", "bank": 0x0C, "name": "Cards"},
            ])

    def test_constants_follow_rgbds_const_sequences(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "constants.asm"
            p.write_text(
                "DEF COLOR_SIZE EQU 2\n"
                "DEF PAL_COLORS EQU 4\n"
                "DEF PAL_SIZE EQU COLOR_SIZE * PAL_COLORS\n"
                "const_def 1\n"
                "const GRASS_ENERGY\n"
                "const FIRE_ENERGY\n"
                "DEF NUM_CARDS EQU const_value - 1\n"
                "DEF TX_LINE EQU '\\n'\n",
                encoding="utf-8",
            )
            values = mod.parse_constants([p])
            self.assertEqual(values["PAL_SIZE"], 8)
            self.assertEqual(values["GRASS_ENERGY"], 1)
            self.assertEqual(values["FIRE_ENERGY"], 2)
            self.assertEqual(values["NUM_CARDS"], 2)
            self.assertEqual(values["TX_LINE"], 10)

    def test_pointer_and_text_tables_are_source_ordered(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            cards = root / "cards.asm"
            cards.write_text(
                "CardPointers::\n\ttable_width 2\n\tdw NULL\n\tdw BulbasaurCard\n\tdw NULL\n"
                "\tassert_table_length NUM_CARDS + 2\n\n"
                "BulbasaurCard:\n\tdb TYPE_PKMN_GRASS\n\tgfx BulbasaurCardGfx\n",
                encoding="utf-8",
            )
            text = root / "text_offsets.asm"
            text.write_text(
                "const_def 1\nTextOffsets::\n\tdwb $0000, $00\n"
                "\ttextpointer HandText\n\ttextpointer BulbasaurName\n",
                encoding="utf-8",
            )
            labels = mod.parse_pointer_table(cards, "CardPointers")
            self.assertEqual(labels, ["NULL", "BulbasaurCard", "NULL"])
            self.assertEqual(mod.parse_card_record_gfx(cards, labels),
                             {"BulbasaurCard": "BulbasaurCardGfx"})
            self.assertEqual(mod.parse_text_pointer_names(text),
                             ["HandText", "BulbasaurName"])

    def test_deck_ai_pointer_table_preserves_source_order(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "deck_ai_pointers.asm"
            p.write_text(
                "DeckAIPointerTable::\n"
                "  table_width 2\n"
                "  dw AIActionTable_SamPractice\n"
                "  dw AIActionTable_GeneralDecks\n"
                "  dw AIActionTable_GeneralNoRetreat\n"
                "  assert_table_length NUM_DECK_IDS\n",
                encoding="utf-8",
            )
            self.assertEqual(mod.parse_pointer_table(p, "DeckAIPointerTable"), [
                "AIActionTable_SamPractice",
                "AIActionTable_GeneralDecks",
                "AIActionTable_GeneralNoRetreat",
            ])

    def test_effect_command_lists_preserve_phase_and_function_identity(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "effect_commands.asm"
            p.write_text(
                "EffectCommands::\n\n"
                "EkansWrapEffectCommands:\n"
                "  dbw EFFECTCMDTYPE_BEFORE_DAMAGE, Paralysis50PercentEffect\n"
                "  db $00\n\n"
                "ArbokTerrorStrikeEffectCommands:\n"
                "  dbw EFFECTCMDTYPE_AFTER_DAMAGE, TerrorStrike_SwitchDefendingPokemon\n"
                "  dbw EFFECTCMDTYPE_REQUIRE_SELECTION, TerrorStrike_50PercentSelectSwitchPokemon\n"
                "  db 0\n\n"
                "DoubleColorlessEnergyEffectCommands:\n"
                "  db $00\n",
                encoding="utf-8",
            )
            self.assertEqual(mod.parse_effect_command_lists(p), [
                {
                    "label": "EkansWrapEffectCommands",
                    "commands": [{
                        "type": "EFFECTCMDTYPE_BEFORE_DAMAGE",
                        "function": "Paralysis50PercentEffect",
                    }],
                },
                {
                    "label": "ArbokTerrorStrikeEffectCommands",
                    "commands": [
                        {
                            "type": "EFFECTCMDTYPE_AFTER_DAMAGE",
                            "function": "TerrorStrike_SwitchDefendingPokemon",
                        },
                        {
                            "type": "EFFECTCMDTYPE_REQUIRE_SELECTION",
                            "function": "TerrorStrike_50PercentSelectSwitchPokemon",
                        },
                    ],
                },
                {
                    "label": "DoubleColorlessEnergyEffectCommands",
                    "commands": [],
                },
            ])

    def test_charmap_is_derived_from_source(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "charmaps.asm"
            p.write_text(
                'charmap " ", $20\ncharmap "A", $41\n'
                'NEWCHARMAP fullwidth\n'
                'fwcharmap TX_KATAKANA, "ア", $11\n'
                'fwcharmap TX_FULLWIDTH0, "0", $60\n',
                encoding="utf-8",
            )
            maps = mod.parse_charmaps(p, {"TX_KATAKANA": 0x0F, "TX_FULLWIDTH0": 0})
            self.assertEqual(maps["halfwidth"]["65"], "A")
            self.assertEqual(maps["fullwidth"]["15"]["17"], "ア")
            self.assertEqual(maps["fullwidth"]["0"]["96"], "0")


    def test_deck_ai_lists_preserve_pointer_presence_and_macro_payloads(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "fire_charge.asm"
            p.write_text(
                "AIActionTable_FireCharge:\n"
                ".list_bench\n"
                "  db BASIC_A\n"
                "  db BASIC_B\n"
                "  db $00\n"
                ".list_retreat\n"
                "  ai_retreat BASIC_A, -5\n"
                "  db $00\n"
                ".list_energy\n"
                "  ai_energy BASIC_A, 3, +2\n"
                "  ai_energy BASIC_B, 0, -8\n"
                "  db $00\n"
                ".store_list_pointers\n"
                "  store_list_pointer wAICardListPlayFromHandPriority, .list_bench\n"
                "  ; missing store_list_pointer wAICardListRetreatBonus, .list_retreat\n"
                "  store_list_pointer wAICardListEnergyBonus, .list_energy\n",
                encoding="utf-8",
            )
            parsed = mod.parse_deck_ai_lists([p], ["BASIC_A", "BASIC_B"], {})
            row = parsed["AIActionTable_FireCharge"]
            self.assertNotIn("retreatBonus", row)
            self.assertEqual([x["cardId"] for x in row["playFromHandPriority"]["entries"]], [1, 2])
            self.assertEqual(row["energyBonus"]["entries"], [
                {"card": "BASIC_A", "cardId": 1, "maxEnergy": 3, "delta": 2, "scoreByte": 0x82},
                {"card": "BASIC_B", "cardId": 2, "maxEnergy": 0, "delta": -8, "scoreByte": 0x78},
            ])

    def test_deck_ai_lists_capture_explicit_retreat_pointer(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "legendary_moltres.asm"
            p.write_text(
                "AIActionTable_LegendaryMoltres:\n"
                ".list_retreat\n"
                "  ai_retreat A, -5\n"
                "  ai_retreat B, +3\n"
                "  db 0\n"
                ".store_list_pointers\n"
                "  store_list_pointer wAICardListRetreatBonus, .list_retreat\n",
                encoding="utf-8",
            )
            parsed = mod.parse_deck_ai_lists([p], ["A", "B"], {})
            entries = parsed["AIActionTable_LegendaryMoltres"]["retreatBonus"]["entries"]
            self.assertEqual([(x["delta"], x["scoreByte"]) for x in entries], [(-5, 0x7b), (3, 0x83)])

    def test_card_graphics_use_png_dimensions_from_decomp(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            (root / "src/gfx/cards").mkdir(parents=True)
            png = root / "src/gfx/cards/bulbasaur.png"
            # parse_card_graphics only needs the PNG signature + IHDR dimensions.
            png.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                            + struct.pack(">II", 48, 64))
            gfx = root / "src/gfx.asm"
            gfx.write_text(
                'BulbasaurCardGfx::\n'
                '\tINCBIN "gfx/cards/bulbasaur.2bpp"\n'
                '\tINCBIN "gfx/cards/bulbasaur.pal"\n',
                encoding="utf-8",
            )
            parsed = mod.parse_card_graphics(root, gfx)
            self.assertEqual(parsed["BulbasaurCardGfx"]["width"], 48)
            self.assertEqual(parsed["BulbasaurCardGfx"]["height"], 64)
            self.assertEqual(parsed["BulbasaurCardGfx"]["twoBppBytes"], 768)

    def test_card_gfx_build_rule_is_source_derived(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "Makefile"
            p.write_text(
                "src/gfx/cards/%.2bpp: RGBGFXFLAGS += --columns --colors embedded --auto-palette\n",
                encoding="utf-8",
            )
            self.assertEqual(mod.parse_card_gfx_build_rule(p), {
                "columns": True,
                "embeddedColors": True,
                "autoPalette": True,
            })

    def test_source_ledger_includes_non_asm_inputs_but_not_build_products(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            (root / "src/gfx/cards").mkdir(parents=True)
            (root / "src/data").mkdir(parents=True)
            (root / "src/main.asm").write_text("db 0\n", encoding="utf-8")
            (root / "src/constants.inc").write_text("DEF X equ 1\n", encoding="utf-8")
            (root / "src/data/map.bin").write_bytes(b"source")
            (root / "src/gfx/cards/card.png").write_bytes(b"png source")
            (root / "src/gfx/cards/card.2bpp").write_bytes(b"generated")
            (root / "src/gfx/cards/card.pal").write_bytes(b"generated")
            files = mod.source_files(root)
            self.assertIn("src/main.asm", files)
            self.assertIn("src/constants.inc", files)
            self.assertIn("src/data/map.bin", files)
            self.assertIn("src/gfx/cards/card.png", files)
            self.assertNotIn("src/gfx/cards/card.2bpp", files)
            self.assertNotIn("src/gfx/cards/card.pal", files)

    def test_deck_lists_preserve_raw_terminator_totals(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "decks.asm"
            p.write_text(
                "DeckPointers::\n  dw GoodDeck\n  dw OddDeck\n  dw NULL\n\n"
                "GoodDeck:\n  deck_list_start\n  card_item A, 2\n"
                "  card_item B, 2\n  deck_list_end\n\n"
                "OddDeck:\n  deck_list_start\n  card_item A, 3\n"
                "  card_item B, 2\n  db 0 ; deliberate source terminator\n",
                encoding="utf-8",
            )
            parsed = mod.parse_deck_lists(
                p, ["GoodDeck", "OddDeck", "NULL"], ["A", "B"], 4
            )
            self.assertEqual(parsed["GoodDeck"]["total"], 4)
            self.assertTrue(parsed["GoodDeck"]["macroEnded"])
            self.assertEqual(parsed["OddDeck"]["total"], 5)
            self.assertFalse(parsed["OddDeck"]["macroEnded"])
            self.assertEqual(parsed["OddDeck"]["entries"][1]["cardId"], 2)

    def test_symbol_alias_constants_follow_rgbds_addresses(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            p = root / "duel_constants.asm"
            p.write_text(
                'DEF PLAYER_TURN EQUS "HIGH(wPlayerDuelVariables)"\n'
                'DEF DUELVARS_HAND EQUS "LOW(wPlayerHand)"\n',
                encoding="utf-8",
            )
            values = mod.parse_symbol_alias_constants([p], {
                "wPlayerDuelVariables": [0, 0xC200],
                "wPlayerHand": [0, 0xC242],
            })
            self.assertEqual(values["PLAYER_TURN"], 0xC2)
            self.assertEqual(values["DUELVARS_HAND"], 0x42)

    def test_memory_symbols_preserve_aliases_and_banks(self):
        symbols = {
            "wPlayerDuelVariables": [0, 0xC200],
            "wAlias": [0, 0xC200],
            "hWhoseTurn": [0, 0xFF97],
            "sCurrentDuel": [3, 0xBC00],
            "CardPointers": [0x0C, 0x4000],
        }
        memory = mod.memory_symbols(symbols)
        self.assertEqual(memory["wram"]["wPlayerDuelVariables"], [0, 0xC200])
        self.assertEqual(memory["wram"]["wAlias"], [0, 0xC200])
        self.assertEqual(memory["hram"]["hWhoseTurn"], [0, 0xFF97])
        self.assertEqual(memory["sram"]["sCurrentDuel"], [3, 0xBC00])
        self.assertNotIn("CardPointers", memory["wram"])

    def test_rgbds_rsreset_rb_layout_constants(self):
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "misc.asm"
            path.write_text(
                "RSRESET\n"
                "DEF RNGVARS_RNG_1 RB\n"
                "DEF RNGVARS_RNG_2 RB\n"
                "DEF RNGVARS_RNG_COUNTER RB\n"
                "DEF RNGVARS_SIZE EQU _RS\n",
                encoding="utf-8",
            )
            out = mod.parse_constants([path])
            self.assertEqual(out["RNGVARS_RNG_1"], 0)
            self.assertEqual(out["RNGVARS_RNG_2"], 1)
            self.assertEqual(out["RNGVARS_RNG_COUNTER"], 2)
            self.assertEqual(out["RNGVARS_SIZE"], 3)



if __name__ == "__main__":
    unittest.main()
