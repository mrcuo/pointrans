#!/usr/bin/env python3
"""Deterministically convert Pointrans' source JSON dictionary to SQLite.

The generated database is a build resource. Runtime code opens it read-only and
performs indexed lookups; it never deserializes the complete dictionary.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "Sources" / "Pointrans" / "local_dict.json"
DEFAULT_OUTPUT = ROOT / "Sources" / "Pointrans" / "Resources" / "Dictionary.sqlite3"


SCHEMA = """
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA page_size = 4096;

CREATE TABLE metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE en_zh (
    term TEXT PRIMARY KEY COLLATE NOCASE NOT NULL,
    meanings TEXT NOT NULL,
    phonetic TEXT
) WITHOUT ROWID;

CREATE TABLE zh_en (
    term TEXT PRIMARY KEY NOT NULL,
    meanings TEXT NOT NULL,
    pinyin TEXT
) WITHOUT ROWID;
"""


def normalized_rows(entries: dict[str, str]) -> list[tuple[str, str, None]]:
    return [
        (term.strip(), meanings.strip(), None)
        for term, meanings in sorted(entries.items(), key=lambda item: item[0])
        if term.strip() and meanings.strip()
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source_bytes = args.input.read_bytes()
    source = json.loads(source_bytes)
    en_rows = normalized_rows(source.get("en_to_zh", {}))
    zh_rows = normalized_rows(source.get("zh_to_en", {}))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".sqlite3.tmp")
    if temporary.exists():
        temporary.unlink()

    connection = sqlite3.connect(temporary)
    try:
        connection.executescript(SCHEMA)
        connection.executemany(
            "INSERT INTO en_zh(term, meanings, phonetic) VALUES (?, ?, ?)", en_rows
        )
        connection.executemany(
            "INSERT INTO zh_en(term, meanings, pinyin) VALUES (?, ?, ?)", zh_rows
        )
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            [
                ("format_version", "1"),
                ("source_sha256", hashlib.sha256(source_bytes).hexdigest()),
                ("en_zh_count", str(len(en_rows))),
                ("zh_en_count", str(len(zh_rows))),
            ],
        )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()

    os.replace(temporary, args.output)
    print(
        f"Built {args.output}: en_zh={len(en_rows)}, zh_en={len(zh_rows)}, "
        f"bytes={args.output.stat().st_size}"
    )


if __name__ == "__main__":
    main()
