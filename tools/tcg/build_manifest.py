#!/usr/bin/env python3
"""Build Pokemon TCG ROM/import metadata strictly from pret/poketcg.

The generated manifest is the bridge between the decomp and the Lua runtime.
No ROM addresses are authored here: addresses come from RGBDS .sym output.
Declarative layouts/constants/names come from the decomp source files and are
recorded so the ROM extractor can validate what it reads against the same
source revision.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import pathlib
import re
import struct
import subprocess
from typing import Iterable

EXPECTED_ROM_SHA1 = "0f8670a583255cff3e5b7ca71b5d7454d928fc48"
SYM_RE = re.compile(r"^([0-9A-Fa-f]+):([0-9A-Fa-f]{4})\s+(.+?)\s*$")
ROM_SHA_RE = re.compile(r"^([0-9a-fA-F]{40})\s+\*?poketcg\.gbc\s*$")
SECTION_RE = re.compile(r'^\s*"(.+)"\s*$')
BANK_RE = re.compile(r"^\s*(ROM0|ROMX\s+\$([0-9A-Fa-f]+)|WRAM0|VRAM\s+\$[0-9A-Fa-f]+|SRAM\s+\$[0-9A-Fa-f]+)\s*$")
DEF_RE = re.compile(r"^\s*(?:DEF|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:EQU|equ)\s+(.+?)\s*$")
RSRESET_RE = re.compile(r"^\s*RSRESET\s*$", re.I)
RSFIELD_RE = re.compile(r"^\s*(?:DEF|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s+(RB|RW|RL)(?:\s+(.+?))?\s*$", re.I)
EQUS_SYMBOL_RE = re.compile(
    r'^\s*(?:DEF|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:EQUS|equs)\s+"(LOW|HIGH)\(([A-Za-z_][A-Za-z0-9_.]*)\)"\s*$'
)
CONST_DEF_RE = re.compile(r"^\s*const_def(?:\s+(.+?))?\s*$", re.I)
CONST_RE = re.compile(r"^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*,\s*(.+?))?\s*$", re.I)
DECK_CONST_RE = re.compile(r"^\s*deck_const\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", re.I)
CHARMAP_RE = re.compile(r'^\s*charmap\s+("(?:\\.|[^"])*")\s*,\s*(.+?)\s*$', re.I)
FWCHARMAP_RE = re.compile(r'^\s*fwcharmap\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*("(?:\\.|[^"])*")\s*,\s*(.+?)\s*$', re.I)
TEXTPOINTER_RE = re.compile(r"^\s*textpointer\s+([A-Za-z_][A-Za-z0-9_.]*)", re.I)
LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.]*)(?:::|:)\s*$")
DW_RE = re.compile(r"^\s*dw\s+([A-Za-z_][A-Za-z0-9_.]*|NULL)\s*(?:;.*)?$", re.I)
DBW_EFFECT_RE = re.compile(
    r"^\s*dbw\s+(EFFECTCMDTYPE_[A-Za-z0-9_]+)\s*,\s*([A-Za-z_][A-Za-z0-9_.]*)\s*$",
    re.I,
)
DB_ZERO_RE = re.compile(r"^\s*db\s+(?:\$00|0)\s*$", re.I)
GFX_LINE_RE = re.compile(r"^\s*gfx\s+([A-Za-z_][A-Za-z0-9_.]*)\s*(?:;.*)?$", re.I)
CARD_ITEM_RE = re.compile(r"^\s*card_item\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(.+?)\s*$", re.I)
LOCAL_LABEL_RE = re.compile(r"^\s*(\.[A-Za-z_][A-Za-z0-9_.]*)(?:(?:::|:))?\s*$")
STORE_LIST_POINTER_RE = re.compile(
    r"^\s*store_list_pointer\s+(wAICardList[A-Za-z0-9_]+)\s*,\s*(\.[A-Za-z_][A-Za-z0-9_.]*)\s*$",
    re.I,
)
AI_RETREAT_RE = re.compile(
    r"^\s*ai_retreat\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(.+?)\s*$", re.I
)
AI_ENERGY_RE = re.compile(
    r"^\s*ai_energy\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^,]+?)\s*,\s*(.+?)\s*$", re.I
)
DB_SINGLE_RE = re.compile(r"^\s*db\s+([^,]+?)\s*$", re.I)
INCBIN_CARD_RE = re.compile(r'^\s*INCBIN\s+"(gfx/cards/[^"]+)"\s*$', re.I)
CARD_GFX_RULE_RE = re.compile(r"^\s*src/gfx/cards/%\.2bpp:\s*RGBGFXFLAGS\s*\+=\s*(.*?)\s*$")


def sha1_file(path: pathlib.Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def strip_comment(line: str) -> str:
    # The files parsed here do not put semicolons inside quoted expressions.
    return line.split(";", 1)[0].rstrip()


def rgbds_string(token: str) -> str:
    # RGBDS accepts \{ to escape macro interpolation. Python does not need it.
    token = token.replace(r"\{", "{")
    value = ast.literal_eval(token)
    if not isinstance(value, str):
        raise ValueError(f"not a string literal: {token}")
    return value


def _replace_char_literals(expr: str) -> str:
    def repl(match: re.Match[str]) -> str:
        value = rgbds_string(match.group(0).replace("'", '"', 1)[::-1].replace("'", '"', 1)[::-1])
        if len(value) != 1:
            raise ValueError(f"expected one character in {match.group(0)}")
        return str(ord(value))
    # Handle the only form used by constants we consume, e.g. '\n'.
    return re.sub(r"'(?:\\.|[^'])'", repl, expr)


def eval_rgbds(expr: str, env: dict[str, int]) -> int:
    expr = strip_comment(expr).strip()
    expr = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", expr)
    expr = re.sub(r"%([01]+)", r"0b\1", expr)
    expr = _replace_char_literals(expr)
    # RGBDS arithmetic here is integral. Avoid float division in Python.
    expr = re.sub(r"(?<!/)/(?!/)", "//", expr)
    tree = ast.parse(expr, mode="eval")

    def walk(node: ast.AST) -> int:
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name):
            if node.id not in env:
                raise KeyError(node.id)
            return int(env[node.id])
        if isinstance(node, ast.UnaryOp):
            v = walk(node.operand)
            if isinstance(node.op, ast.USub): return -v
            if isinstance(node.op, ast.UAdd): return v
            if isinstance(node.op, ast.Invert): return ~v
        if isinstance(node, ast.BinOp):
            a, b = walk(node.left), walk(node.right)
            ops = {
                ast.Add: lambda: a + b, ast.Sub: lambda: a - b,
                ast.Mult: lambda: a * b, ast.FloorDiv: lambda: a // b,
                ast.LShift: lambda: a << b, ast.RShift: lambda: a >> b,
                ast.BitOr: lambda: a | b, ast.BitAnd: lambda: a & b,
                ast.BitXor: lambda: a ^ b,
            }
            for cls, fn in ops.items():
                if isinstance(node.op, cls): return fn()
        raise ValueError(f"unsupported RGBDS expression: {expr}")

    return int(walk(tree))


def read_rom_sha1(root: pathlib.Path) -> str:
    for line in (root / "rom.sha1").read_text(encoding="utf-8").splitlines():
        m = ROM_SHA_RE.match(line.strip())
        if m:
            value = m.group(1).lower()
            if value != EXPECTED_ROM_SHA1:
                raise SystemExit(
                    f"poketcg ROM hash changed: expected {EXPECTED_ROM_SHA1}, got {value}"
                )
            return value
    raise SystemExit("poketcg.gbc SHA-1 not found in rom.sha1")


def parse_symbols(path: pathlib.Path) -> dict[str, list[int]]:
    out: dict[str, list[int]] = {}
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith(";"):
            continue
        m = SYM_RE.match(line)
        if not m:
            continue
        bank = int(m.group(1), 16)
        address = int(m.group(2), 16)
        name = m.group(3)
        if name in out and out[name] != [bank, address]:
            raise SystemExit(f"duplicate symbol with different address at {path}:{lineno}: {name}")
        out[name] = [bank, address]
    if not out:
        raise SystemExit(f"no RGBDS symbols parsed from {path}")
    return out


def parse_layout(path: pathlib.Path) -> list[dict]:
    bank = None
    sections = []
    for line in path.read_text(encoding="utf-8").splitlines():
        bm = BANK_RE.match(line)
        if bm:
            token = bm.group(1)
            if token == "ROM0":
                bank = {"space": "rom", "bank": 0}
            elif token.startswith("ROMX"):
                bank = {"space": "rom", "bank": int(bm.group(2), 16)}
            elif token == "WRAM0":
                bank = {"space": "wram", "bank": 0}
            elif token.startswith("VRAM"):
                bank = {"space": "vram", "bank": int(token.split("$")[1], 16)}
            elif token.startswith("SRAM"):
                bank = {"space": "sram", "bank": int(token.split("$")[1], 16)}
            continue
        sm = SECTION_RE.match(line)
        if sm and bank:
            sections.append({**bank, "name": sm.group(1)})
    return sections


def parse_constants(paths: Iterable[pathlib.Path]) -> dict[str, int]:
    """Evaluate the simple DEF/const sequences used by TCG data layouts.

    Unknown expressions are skipped, then retried after later constants have
    been seen. The manifest only consumes constants that resolve numerically.
    """
    env: dict[str, int] = {}
    pending: list[tuple[str, str]] = []
    const_value = 0
    rs_value = 0
    for path in paths:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = strip_comment(raw)
            if not line.strip():
                continue
            if RSRESET_RE.match(line):
                rs_value = 0
                env["_RS"] = rs_value
                continue
            m = RSFIELD_RE.match(line)
            if m:
                name, unit, count_expr = m.groups()
                count = eval_rgbds(count_expr, env) if count_expr else 1
                size = {"RB": 1, "RW": 2, "RL": 4}[unit.upper()] * count
                env[name] = rs_value
                rs_value += size
                env["_RS"] = rs_value
                continue
            m = CONST_DEF_RE.match(line)
            if m:
                const_value = eval_rgbds(m.group(1), env) if m.group(1) else 0
                env["const_value"] = const_value
                continue
            m = CONST_RE.match(line)
            if m:
                if m.group(2):
                    const_value = eval_rgbds(m.group(2), env)
                env[m.group(1)] = const_value
                const_value += 1
                env["const_value"] = const_value
                continue
            m = DECK_CONST_RE.match(line)
            if m:
                name = m.group(1)
                if const_value >= 2:
                    env[name + "_ID"] = const_value - 2
                env[name] = const_value
                const_value += 1
                env["const_value"] = const_value
                continue
            m = DEF_RE.match(line)
            if m:
                name, expr = m.group(1), m.group(2)
                try:
                    env[name] = eval_rgbds(expr, env)
                except (KeyError, ValueError, SyntaxError):
                    pending.append((name, expr))
    changed = True
    while changed and pending:
        changed = False
        later = []
        for name, expr in pending:
            try:
                env[name] = eval_rgbds(expr, env)
                changed = True
            except (KeyError, ValueError, SyntaxError):
                later.append((name, expr))
        pending = later
    env.pop("const_value", None)
    env.pop("_RS", None)
    return env


def parse_symbol_alias_constants(
    paths: Iterable[pathlib.Path], symbols: dict[str, list[int]]
) -> dict[str, int]:
    """Resolve RGBDS EQUS aliases that name LOW()/HIGH() of a symbol.

    poketcg uses these for the duel-variable offsets and the turn-holder high
    bytes. They are part of the decomp contract, but are strings at assembly
    time rather than ordinary numeric EQU definitions.
    """
    out: dict[str, int] = {}
    for path in paths:
        for raw in path.read_text(encoding="utf-8").splitlines():
            m = EQUS_SYMBOL_RE.match(strip_comment(raw))
            if not m:
                continue
            name, op, label = m.groups()
            if label not in symbols:
                raise SystemExit(f"{path}: EQUS alias {name} references missing symbol {label}")
            address = symbols[label][1]
            out[name] = address & 0xFF if op.upper() == "LOW" else (address >> 8) & 0xFF
    return out


def memory_symbols(symbols: dict[str, list[int]]) -> dict[str, dict[str, list[int]]]:
    """Select RAM symbols from the linker symbol map without guessing sizes.

    Runtime memory is sparse and address-based, so aliases/unions remain exact:
    every source symbol keeps the bank/address RGBDS assigned it.
    """
    out: dict[str, dict[str, list[int]]] = {"wram": {}, "hram": {}, "sram": {}}
    for name, loc in symbols.items():
        bank, address = loc
        if 0xC000 <= address <= 0xDFFF:
            out["wram"][name] = [bank, address]
        elif 0xFF80 <= address <= 0xFFFE:
            out["hram"][name] = [bank, address]
        elif 0xA000 <= address <= 0xBFFF:
            out["sram"][name] = [bank, address]
    return out


def parse_card_ids(path: pathlib.Path) -> list[str]:
    names = []
    in_ids = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        m = CONST_DEF_RE.match(line)
        if m and not in_ids:
            start = eval_rgbds(m.group(1), {}) if m.group(1) else 0
            if start != 1:
                raise SystemExit("card_constants.asm no longer starts card IDs at 1")
            in_ids = True
            continue
        if not in_ids:
            continue
        m = CONST_RE.match(line)
        if m:
            names.append(m.group(1))
            continue
        if re.match(r"^\s*DEF\s+NUM_CARDS\s+EQU\b", line, re.I):
            break
    if not names:
        raise SystemExit("no card IDs parsed from card_constants.asm")
    return names


def parse_deck_ids(path: pathlib.Path) -> list[str]:
    names = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        m = DECK_CONST_RE.match(line)
        if m:
            names.append(m.group(1))
        elif names and re.match(r"^\s*DEF\s+NUM_VALID_DECKS\s+EQU\b", line, re.I):
            break
    if not names:
        raise SystemExit("no deck IDs parsed from deck_constants.asm")
    return names


def parse_pointer_table(path: pathlib.Path, table_label: str) -> list[str]:
    labels: list[str] = []
    active = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        lm = LABEL_RE.match(line)
        if lm:
            if active:
                break
            active = lm.group(1) == table_label
            continue
        if not active:
            continue
        m = DW_RE.match(line)
        if m:
            labels.append(m.group(1))
        elif labels and ("assert_table_length" in line or line.strip().startswith("db ")):
            break
    if not labels:
        raise SystemExit(f"no pointers parsed from {path}:{table_label}")
    return labels


def parse_effect_command_lists(path: pathlib.Path) -> list[dict]:
    """Parse the declarative effect-command records in source order.

    Each list in engine/duel/effect_commands.asm is a zero-terminated sequence
    of `dbw EFFECTCMDTYPE_*, FunctionLabel` records.  Preserve the symbolic
    command/function identities here; the ROM extractor later cross-checks the
    encoded byte/word values against RGBDS symbols before emitting runtime data.
    """
    out: list[dict] = []
    current_label: str | None = None
    commands: list[dict] = []
    active = False

    def finish() -> None:
        nonlocal current_label, commands, active
        if current_label is None:
            return
        out.append({"label": current_label, "commands": commands})
        current_label, commands, active = None, [], False

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        lm = LABEL_RE.match(line)
        if lm:
            if active:
                raise SystemExit(
                    f"{path}:{current_label}: effect list reached label {lm.group(1)} before terminator"
                )
            current_label = lm.group(1)
            commands = []
            active = False
            continue

        if current_label is None:
            continue
        cm = DBW_EFFECT_RE.match(line)
        if cm:
            active = True
            commands.append({"type": cm.group(1), "function": cm.group(2)})
            continue
        if DB_ZERO_RE.match(line):
            finish()

    if active:
        raise SystemExit(f"{path}:{current_label}: unterminated effect command list")
    if not out:
        raise SystemExit(f"no effect-command lists parsed from {path}")
    return out


def parse_deck_lists(
    path: pathlib.Path, pointer_labels: list[str], card_ids: list[str], deck_size: int
) -> dict[str, dict]:
    """Parse the exact list encoded at every DeckPointers source label.

    Most lists end through deck_list_end, which asserts DECK_SIZE. The decomp
    also contains intentionally malformed/unused lists that terminate with
    raw `db 0`; those totals are source truth too and must not be normalized.
    """
    wanted = {x for x in pointer_labels if x != "NULL"}
    id_by_name = {name: i + 1 for i, name in enumerate(card_ids)}
    out: dict[str, dict] = {}
    active: str | None = None
    in_list = False
    entries: list[dict] = []

    def finish(macro_ended: bool) -> None:
        nonlocal active, in_list, entries
        assert active is not None
        total = sum(row["quantity"] for row in entries)
        if macro_ended and total != deck_size:
            raise SystemExit(
                f"{active}: deck_list_end source total {total} != DECK_SIZE {deck_size}"
            )
        out[active] = {
            "entries": entries,
            "total": total,
            "macroEnded": macro_ended,
        }
        active, in_list, entries = None, False, []

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        lm = LABEL_RE.match(line)
        if lm:
            if active is not None and in_list:
                raise SystemExit(f"{active}: deck list reached a new label before terminator")
            active = lm.group(1) if lm.group(1) in wanted and lm.group(1) not in out else None
            in_list = False
            entries = []
            continue
        if active is None:
            continue
        if not in_list:
            if re.match(r"^\s*deck_list_start\s*$", line, re.I):
                in_list = True
            continue
        m = CARD_ITEM_RE.match(line)
        if m:
            name, qty_expr = m.groups()
            if name not in id_by_name:
                raise SystemExit(f"{active}: unknown card constant {name}")
            quantity = eval_rgbds(qty_expr, {})
            entries.append({
                "card": name,
                "cardId": id_by_name[name],
                "quantity": quantity,
            })
            continue
        if re.match(r"^\s*deck_list_end\s*$", line, re.I):
            finish(True)
            continue
        if re.match(r"^\s*db\s+(?:\$00|0)(?:\s|$)", line, re.I):
            finish(False)
            continue

    missing = sorted(wanted - out.keys())
    if missing:
        raise SystemExit(f"pointed deck lists not parsed: {', '.join(missing[:8])}")
    return out


DECK_AI_LIST_TARGETS = {
    "wAICardListAvoidPrize": ("avoidPrize", "card_ids"),
    "wAICardListArenaPriority": ("arenaPriority", "card_ids"),
    "wAICardListBenchPriority": ("benchPriority", "card_ids"),
    "wAICardListPlayFromHandPriority": ("playFromHandPriority", "card_ids"),
    "wAICardListRetreatBonus": ("retreatBonus", "retreat_bonus"),
    "wAICardListEnergyBonus": ("energyBonus", "energy_bonus"),
}


def parse_deck_ai_lists(
    paths: Iterable[pathlib.Path], card_ids: list[str], constants: dict[str, int]
) -> dict[str, dict]:
    """Parse specialized per-action-table AI lists and only the pointers source stores.

    The deck source often declares a .list_retreat but comments out the
    store_list_pointer for it.  That missing initialization is cartridge behavior:
    the manifest therefore records only explicit, uncommented pointer stores.
    """
    card_id_by_name = {name: i + 1 for i, name in enumerate(card_ids)}
    raw_lists: dict[str, dict] = {}
    assignments: dict[str, dict[str, str]] = {}

    for path in paths:
        scope: str | None = None
        active_label: str | None = None
        active_kind: str | None = None
        active_entries: list[dict] = []

        def finish_list() -> None:
            nonlocal active_label, active_kind, active_entries
            if active_label is not None and active_kind is not None:
                raw_lists[active_label] = {
                    "label": active_label,
                    "kind": active_kind,
                    "entries": active_entries,
                }
            active_label, active_kind, active_entries = None, None, []

        for raw in path.read_text(encoding="utf-8").splitlines():
            line = strip_comment(raw)
            if not line.strip():
                continue
            gm = LABEL_RE.match(line)
            if gm:
                finish_list()
                scope = gm.group(1)
                active_label = None
                continue
            lm = LOCAL_LABEL_RE.match(line)
            if lm:
                finish_list()
                if scope and scope.startswith("AIActionTable_"):
                    active_label = scope + lm.group(1)
                continue

            sm = STORE_LIST_POINTER_RE.match(line)
            if sm and scope and scope.startswith("AIActionTable_"):
                target, local_label = sm.groups()
                if target not in DECK_AI_LIST_TARGETS:
                    raise SystemExit(f"{path}: unsupported AI list pointer {target}")
                assignments.setdefault(scope, {})[target] = scope + local_label
                continue

            if active_label is None:
                continue

            if DB_ZERO_RE.match(line):
                if active_kind is None:
                    # Empty lists are typed later from the pointer target that uses them.
                    raw_lists[active_label] = {
                        "label": active_label, "kind": None, "entries": []
                    }
                    active_label = None
                else:
                    finish_list()
                continue

            rm = AI_RETREAT_RE.match(line)
            if rm:
                if active_kind not in (None, "retreat_bonus"):
                    raise SystemExit(f"{path}:{active_label}: mixed AI list encodings")
                active_kind = "retreat_bonus"
                name, delta_expr = rm.groups()
                if name not in card_id_by_name:
                    raise SystemExit(f"{path}:{active_label}: unknown card constant {name}")
                delta = eval_rgbds(delta_expr, constants)
                if not -128 <= delta <= 127:
                    raise SystemExit(f"{path}:{active_label}: retreat delta out of range: {delta}")
                active_entries.append({
                    "card": name,
                    "cardId": card_id_by_name[name],
                    "delta": delta,
                    "scoreByte": (0x80 + delta) & 0xFF,
                })
                continue

            em = AI_ENERGY_RE.match(line)
            if em:
                if active_kind not in (None, "energy_bonus"):
                    raise SystemExit(f"{path}:{active_label}: mixed AI list encodings")
                active_kind = "energy_bonus"
                name, maximum_expr, delta_expr = em.groups()
                if name not in card_id_by_name:
                    raise SystemExit(f"{path}:{active_label}: unknown card constant {name}")
                maximum = eval_rgbds(maximum_expr, constants)
                delta = eval_rgbds(delta_expr, constants)
                if not 0 <= maximum <= 255 or not -128 <= delta <= 127:
                    raise SystemExit(f"{path}:{active_label}: invalid ai_energy arguments")
                active_entries.append({
                    "card": name,
                    "cardId": card_id_by_name[name],
                    "maxEnergy": maximum,
                    "delta": delta,
                    "scoreByte": (0x80 + delta) & 0xFF,
                })
                continue

            dm = DB_SINGLE_RE.match(line)
            if dm:
                token = dm.group(1).strip()
                try:
                    value = eval_rgbds(token, constants)
                except (KeyError, ValueError, SyntaxError):
                    value = None
                if value == 0:
                    if active_kind is None:
                        raw_lists[active_label] = {
                            "label": active_label, "kind": None, "entries": []
                        }
                        active_label = None
                    else:
                        finish_list()
                    continue
                if token in card_id_by_name:
                    if active_kind not in (None, "card_ids"):
                        raise SystemExit(f"{path}:{active_label}: mixed AI list encodings")
                    active_kind = "card_ids"
                    active_entries.append({"card": token, "cardId": card_id_by_name[token]})
                    continue

        finish_list()

    out: dict[str, dict] = {}
    for action_table, pointer_map in assignments.items():
        lists: dict[str, dict] = {}
        for target, label in pointer_map.items():
            field, expected_kind = DECK_AI_LIST_TARGETS[target]
            if label not in raw_lists:
                raise SystemExit(f"{action_table}: pointed AI list not parsed: {label}")
            row = dict(raw_lists[label])
            actual_kind = row["kind"] or expected_kind
            if actual_kind != expected_kind:
                raise SystemExit(
                    f"{action_table}:{label}: expected {expected_kind}, got {actual_kind}"
                )
            row["kind"] = expected_kind
            lists[field] = row
        out[action_table] = lists
    return out


def parse_card_record_gfx(path: pathlib.Path, pointer_labels: list[str]) -> dict[str, str]:
    wanted = {x for x in pointer_labels if x != "NULL"}
    out: dict[str, str] = {}
    current = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        lm = LABEL_RE.match(line)
        if lm:
            current = lm.group(1) if lm.group(1) in wanted else None
            continue
        if current:
            gm = GFX_LINE_RE.match(line)
            if gm:
                out[current] = gm.group(1)
                current = None
    missing = sorted(wanted - out.keys())
    if missing:
        raise SystemExit(f"card records missing gfx declarations: {', '.join(missing[:8])}")
    return out


def png_dimensions(path: pathlib.Path) -> tuple[int, int]:
    with path.open("rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise SystemExit(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def parse_card_gfx_build_rule(path: pathlib.Path) -> dict[str, bool]:
    """Read the card rgbgfx layout flags from the decomp Makefile.

    Card art uses --columns in pret/poketcg. The runtime decoder is row-major,
    so this flag must travel through the generated manifest rather than live as
    a handwritten assumption in Lua.
    """
    for raw in path.read_text(encoding="utf-8").splitlines():
        m = CARD_GFX_RULE_RE.match(raw)
        if not m:
            continue
        flags = m.group(1).split()
        return {
            "columns": "--columns" in flags,
            "embeddedColors": "--colors" in flags and "embedded" in flags,
            "autoPalette": "--auto-palette" in flags,
        }
    raise SystemExit("card rgbgfx rule not found in Makefile")


def parse_card_graphics(root: pathlib.Path, path: pathlib.Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    current = None
    saw_2bpp: dict[str, str] = {}
    saw_pal: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        lm = LABEL_RE.match(line)
        if lm:
            current = lm.group(1) if lm.group(1).endswith("CardGfx") else None
            continue
        if not current:
            continue
        im = INCBIN_CARD_RE.match(line)
        if not im:
            continue
        rel = im.group(1)
        if rel.endswith(".2bpp"):
            saw_2bpp[current] = rel
        elif rel.endswith(".pal"):
            saw_pal.add(current)
            source = pathlib.Path("src") / pathlib.Path(rel).with_suffix(".png")
            png = root / source
            if not png.exists():
                raise SystemExit(f"card PNG source missing for {current}: {png}")
            width, height = png_dimensions(png)
            out[current] = {
                "sourcePng": source.as_posix(),
                "width": width,
                "height": height,
                "twoBppBytes": width * height * 2 // 8,
            }
            current = None
    missing_pal = sorted(set(saw_2bpp) - saw_pal)
    if missing_pal:
        raise SystemExit(f"card gfx without adjacent palette: {', '.join(missing_pal[:8])}")
    if not out:
        raise SystemExit("no card graphics parsed from gfx.asm")
    return out


def parse_text_pointer_names(path: pathlib.Path) -> list[str]:
    names = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        m = TEXTPOINTER_RE.match(strip_comment(raw))
        if m:
            names.append(m.group(1))
    if not names:
        raise SystemExit("no textpointer entries parsed")
    return names


def parse_charmaps(path: pathlib.Path, constants: dict[str, int]) -> dict:
    half: dict[str, str] = {}
    full: dict[str, dict[str, str]] = {}
    before_named = True
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        if re.match(r"^\s*NEWCHARMAP\b", line, re.I):
            before_named = False
            continue
        m = CHARMAP_RE.match(line)
        if m and before_named:
            try:
                char = rgbds_string(m.group(1))
                code = eval_rgbds(m.group(2), constants)
            except (ValueError, KeyError, SyntaxError):
                continue
            # Named control aliases are handled separately by text constants.
            if not char.startswith("<"):
                half[str(code)] = char
            continue
        m = FWCHARMAP_RE.match(line)
        if m:
            prefix_name, literal, code_expr = m.groups()
            if prefix_name not in constants:
                continue
            try:
                char = rgbds_string(literal)
                code = eval_rgbds(code_expr, constants)
            except (ValueError, KeyError, SyntaxError):
                continue
            prefix = str(constants[prefix_name])
            full.setdefault(prefix, {})[str(code)] = char
    return {"halfwidth": half, "fullwidth": full}


def git_commit(root: pathlib.Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def source_files(root: pathlib.Path) -> dict[str, str]:
    """Fingerprint canonical decomp inputs, not build products.

    The ledger is meant to prove complete source coverage. Restricting it to
    .asm files would omit source PNGs, map binaries, include files, and other
    data that the ROM is built from. RGBDS/rgbgfx intermediates are excluded
    because `make clean` removes them and they are reproducible from sources.
    """
    src = root / "src"
    generated_suffixes = {
        ".o", ".1bpp", ".2bpp", ".pal", ".lz", ".bgmap", ".sym", ".map",
    }
    files: dict[str, str] = {}
    for path in sorted(src.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() in generated_suffixes:
            continue
        rel = path.relative_to(root).as_posix()
        files[rel] = sha1_file(path)
    if not files:
        raise SystemExit(f"no canonical source files under {src}")
    return files


def load_or_create_ledger(path: pathlib.Path, sources: dict[str, str]) -> dict:
    if path.exists():
        ledger = json.loads(path.read_text(encoding="utf-8"))
    else:
        ledger = {"schema": 1, "files": {}}
    entries = ledger.setdefault("files", {})
    for source, digest in sources.items():
        row = entries.setdefault(source, {})
        row["sourceSha1"] = digest
        row.pop("stale", None)
        row.setdefault("kind", "unassigned")
        row.setdefault("state", "todo")
        row.setdefault("targets", [])
        row.setdefault("notes", "")
    for source, row in entries.items():
        if source not in sources:
            row["stale"] = True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return ledger


def translation_complete(ledger: dict, sources: dict[str, str]) -> bool:
    for source in sources:
        row = ledger.get("files", {}).get(source, {})
        if row.get("sourceSha1") != sources[source]:
            return False
        if row.get("kind") not in {"translated", "extracted", "hardware"}:
            return False
        if row.get("state") != "done":
            return False
        targets = row.get("targets")
        if not isinstance(targets, list) or not targets:
            return False
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--decomp", required=True, type=pathlib.Path)
    ap.add_argument("--sym", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--ledger", required=True, type=pathlib.Path)
    args = ap.parse_args()

    root = args.decomp.resolve()
    rom_sha1 = read_rom_sha1(root)
    symbols = parse_symbols(args.sym.resolve())
    sources = source_files(root)
    ledger = load_or_create_ledger(args.ledger.resolve(), sources)

    const_paths = [
        root / "src/constants/hardware.inc",
        root / "src/constants/text_constants.asm",
        root / "src/constants/card_data_constants.asm",
        root / "src/constants/card_constants.asm",
        root / "src/constants/deck_constants.asm",
        root / "src/constants/deck_ai_constants.asm",
        root / "src/constants/duel_constants.asm",
        root / "src/constants/misc_constants.asm",
    ]
    constants = parse_constants(const_paths)
    constants.update(parse_symbol_alias_constants(
        [root / "src/constants/duel_constants.asm"], symbols
    ))
    card_ids = parse_card_ids(root / "src/constants/card_constants.asm")
    deck_ids = parse_deck_ids(root / "src/constants/deck_constants.asm")
    card_pointer_labels = parse_pointer_table(root / "src/data/cards.asm", "CardPointers")
    deck_pointer_labels = parse_pointer_table(root / "src/data/decks.asm", "DeckPointers")
    deck_ai_action_tables = parse_pointer_table(
        root / "src/data/deck_ai_pointers.asm", "DeckAIPointerTable"
    )
    deck_ai_lists = parse_deck_ai_lists(
        sorted((root / "src/engine/duel/ai/decks").glob("*.asm")), card_ids, constants
    )
    effect_command_lists = parse_effect_command_lists(
        root / "src/engine/duel/effect_commands.asm"
    )

    if card_pointer_labels[0] != "NULL" or card_pointer_labels[-1] != "NULL":
        raise SystemExit("CardPointers sentinel layout changed")
    if len(card_pointer_labels) != len(card_ids) + 2:
        raise SystemExit("CardPointers count does not match card_constants.asm")
    if deck_pointer_labels[-1] != "NULL" or len(deck_pointer_labels) != len(deck_ids) + 1:
        raise SystemExit("DeckPointers count does not match deck_constants.asm")
    if constants.get("NUM_CARDS") != len(card_ids):
        raise SystemExit("NUM_CARDS does not match parsed card IDs")
    if constants.get("NUM_VALID_DECKS") != len(deck_ids):
        raise SystemExit("NUM_VALID_DECKS does not match parsed deck IDs")
    if constants.get("NUM_DECK_IDS") != len(deck_ai_action_tables):
        raise SystemExit("DeckAIPointerTable count does not match NUM_DECK_IDS")

    deck_source_lists = parse_deck_lists(
        root / "src/data/decks.asm", deck_pointer_labels, card_ids, constants["DECK_SIZE"]
    )

    record_gfx = parse_card_record_gfx(root / "src/data/cards.asm", card_pointer_labels)
    card_gfx_build = parse_card_gfx_build_rule(root / "Makefile")
    card_graphics = parse_card_graphics(root, root / "src/gfx.asm")
    for row in card_graphics.values():
        row.update(card_gfx_build)
    for card, gfx in record_gfx.items():
        if gfx not in card_graphics:
            raise SystemExit(f"{card} references unknown card gfx {gfx}")

    text_names = parse_text_pointer_names(root / "src/text/text_offsets.asm")
    charmap = parse_charmaps(root / "src/constants/charmaps.asm", constants)

    required_symbols = [
        "CardPointers", "CardGraphics", "DeckPointers", "DeckAIPointerTable",
        "TextOffsets", "GameLoop", "DuelDataToSave", "EffectCommands",
        "ConvertSpecialTrainerCardToPokemon.trainer_to_pkmn_data",
        "PrizeBitmasks", "TakeAPrizes",
    ]
    for name in required_symbols:
        if name not in symbols:
            raise SystemExit(f"required symbol missing from .sym: {name}")
    for label in card_pointer_labels + deck_pointer_labels + text_names + list(record_gfx.values()):
        if label != "NULL" and label not in symbols:
            raise SystemExit(f"source label missing from .sym: {label}")
    for action_table, lists in deck_ai_lists.items():
        if action_table not in symbols:
            raise SystemExit(f"deck AI action table missing from .sym: {action_table}")
        for row in lists.values():
            if row["label"] not in symbols:
                raise SystemExit(f"deck AI list missing from .sym: {row['label']}")
    for row in effect_command_lists:
        if row["label"] not in symbols:
            raise SystemExit(f"effect-command list missing from .sym: {row['label']}")
        for command in row["commands"]:
            if command["type"] not in constants:
                raise SystemExit(f"unknown effect command type: {command['type']}")
            if command["function"] not in symbols:
                raise SystemExit(f"effect function missing from .sym: {command['function']}")

    manifest = {
        "schema": 5,
        "romSha1": rom_sha1,
        "romSize": 64 * 0x4000,
        "decompCommit": git_commit(root),
        "sourceFileCount": len(sources),
        "sourceFiles": sources,
        "buildInputs": {
            "Makefile": sha1_file(root / "Makefile"),
            "rom.sha1": sha1_file(root / "rom.sha1"),
        },
        "layout": parse_layout(root / "src/layout.link"),
        "symbols": symbols,
        "memory": {
            "symbols": memory_symbols(symbols),
            "sourceFiles": {
                name: sha1_file(root / name)
                for name in [
                    "src/wram.asm", "src/hram.asm", "src/sram.asm",
                    "src/macros/wram.asm",
                ]
            },
        },
        "constants": constants,
        "cards": {
            "ids": card_ids,
            "pointerLabels": card_pointer_labels,
            "recordGraphics": record_gfx,
            "graphicsBuild": card_gfx_build,
            "graphics": card_graphics,
        },
        "decks": {
            "ids": deck_ids,
            "pointerLabels": deck_pointer_labels,
            "sourceLists": deck_source_lists,
            "aiActionTables": deck_ai_action_tables,
            "aiListsByActionTable": deck_ai_lists,
        },
        "effects": {
            "lists": effect_command_lists,
        },
        "text": {
            "pointerNames": text_names,
            "charmap": charmap,
        },
        "translationComplete": translation_complete(ledger, sources),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.out} ({len(symbols)} symbols, {len(sources)} source files)")
    print(f"cards={len(card_ids)} decks={len(deck_ids)} text={len(text_names)} gfx={len(card_graphics)}")
    print("translationComplete =", manifest["translationComplete"])


if __name__ == "__main__":
    main()
