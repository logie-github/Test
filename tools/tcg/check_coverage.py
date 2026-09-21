#!/usr/bin/env python3
"""Fail unless every canonical pret/poketcg source has an explicit done mapping."""

import json
import pathlib
import sys

ALLOWED = {"translated", "extracted", "hardware"}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_coverage.py MANIFEST LEDGER", file=sys.stderr)
        return 2
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    ledger = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    sources = manifest["sourceFiles"]
    rows = ledger.get("files", {})
    problems = []
    for source, digest in sorted(sources.items()):
        row = rows.get(source)
        if not row:
            problems.append(f"{source}: missing ledger row")
            continue
        if row.get("sourceSha1") != digest:
            problems.append(f"{source}: source changed since ledger mapping")
        if row.get("kind") not in ALLOWED:
            problems.append(f"{source}: kind={row.get('kind')!r}")
        if row.get("state") != "done":
            problems.append(f"{source}: state={row.get('state')!r}")
        if not row.get("targets"):
            problems.append(f"{source}: no Lua/extractor/hardware target")
    if problems:
        print(f"TCG translation coverage incomplete: {len(problems)} issue(s)", file=sys.stderr)
        for item in problems:
            print(" - " + item, file=sys.stderr)
        return 1
    print(f"TCG translation coverage: 100% ({len(sources)} source files accounted for)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
