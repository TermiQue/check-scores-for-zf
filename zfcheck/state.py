from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any


class StateStore:
    def __init__(self, data_dir: Path):
        data_dir.mkdir(parents=True, exist_ok=True)
        self.path = data_dir / "state.db"
        self.connection = sqlite3.connect(self.path)
        self.connection.execute(
            "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def get(self, key: str) -> str | None:
        row = self.connection.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None

    def set(self, key: str, value: str) -> None:
        self.connection.execute(
            "INSERT INTO kv(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )
        self.connection.commit()

    def delete(self, key: str) -> None:
        self.connection.execute("DELETE FROM kv WHERE key = ?", (key,))
        self.connection.commit()

    def get_snapshot(self) -> dict[str, dict[str, Any]] | None:
        value = self.get("snapshot")
        return json.loads(value) if value is not None else None

    def set_snapshot(self, snapshot: dict[str, dict[str, Any]]) -> None:
        self.set("snapshot", json.dumps(snapshot, ensure_ascii=False, sort_keys=True))
