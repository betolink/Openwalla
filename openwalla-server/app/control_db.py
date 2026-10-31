"""SQLite-backed control-plane state for routers, devices, policies and profiles.

This is deliberately separate from FlowDatabase (Netify flow storage). It stores
the objects the web dashboard and mobile app manage; the router remains the
source of truth for live state and enforcement.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

JSON_FIELDS = {
    "capabilities",
    "ipv6",
    "tags",
    "member_ids",
    "target_ids",
    "rules",
    "schedule",
    "bedtime",
    "blocklists",
    "data",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _new_id() -> str:
    return uuid.uuid4().hex


def _encode(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _decode_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    result = dict(row)
    for key in JSON_FIELDS:
        if key in result and isinstance(result[key], str):
            try:
                result[key] = json.loads(result[key])
            except (ValueError, TypeError):
                pass
    for key in ("online", "blocked", "paused", "enabled", "read", "verify_tls"):
        if key in result and result[key] is not None:
            result[key] = bool(result[key])
    return result


class ControlDatabase:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._connection = sqlite3.connect(
            self.path, check_same_thread=False, timeout=30
        )
        self._connection.row_factory = sqlite3.Row
        self._initialize()

    def _initialize(self) -> None:
        with self._lock, self._connection:
            self._connection.executescript(
                """
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                PRAGMA busy_timeout=30000;

                CREATE TABLE IF NOT EXISTS routers (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    address TEXT NOT NULL,
                    port INTEGER NOT NULL DEFAULT 80,
                    scheme TEXT NOT NULL DEFAULT 'http',
                    username TEXT NOT NULL DEFAULT '',
                    password TEXT NOT NULL DEFAULT '',
                    verify_tls INTEGER NOT NULL DEFAULT 1,
                    model TEXT NOT NULL DEFAULT '',
                    openwrt_version TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT 'unknown',
                    last_seen TEXT NOT NULL DEFAULT '',
                    capabilities TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY,
                    router_id TEXT NOT NULL,
                    mac TEXT NOT NULL,
                    ipv4 TEXT NOT NULL DEFAULT '',
                    ipv6 TEXT NOT NULL DEFAULT '[]',
                    hostname TEXT NOT NULL DEFAULT '',
                    display_name TEXT NOT NULL DEFAULT '',
                    vendor TEXT NOT NULL DEFAULT '',
                    device_type TEXT NOT NULL DEFAULT '',
                    connection TEXT NOT NULL DEFAULT 'unknown',
                    online INTEGER NOT NULL DEFAULT 0,
                    blocked INTEGER NOT NULL DEFAULT 0,
                    paused INTEGER NOT NULL DEFAULT 0,
                    pause_until INTEGER NOT NULL DEFAULT 0,
                    group_id TEXT NOT NULL DEFAULT '',
                    first_seen TEXT NOT NULL,
                    last_seen TEXT NOT NULL,
                    tags TEXT NOT NULL DEFAULT '[]',
                    UNIQUE (router_id, mac)
                );
                CREATE INDEX IF NOT EXISTS idx_devices_router
                    ON devices(router_id, online);

                CREATE TABLE IF NOT EXISTS interfaces (
                    router_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL DEFAULT '',
                    up INTEGER NOT NULL DEFAULT 0,
                    mac TEXT NOT NULL DEFAULT '',
                    addresses TEXT NOT NULL DEFAULT '[]',
                    rx_bytes INTEGER NOT NULL DEFAULT 0,
                    tx_bytes INTEGER NOT NULL DEFAULT 0,
                    errors INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (router_id, id)
                );

                CREATE TABLE IF NOT EXISTS groups (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    member_ids TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS policies (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    scope TEXT NOT NULL DEFAULT 'device',
                    target_ids TEXT NOT NULL DEFAULT '[]',
                    rules TEXT NOT NULL DEFAULT '[]',
                    schedule TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS filtering_rules (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL DEFAULT '',
                    target_type TEXT NOT NULL DEFAULT 'device',
                    target_ids TEXT NOT NULL DEFAULT '[]',
                    kind TEXT NOT NULL DEFAULT 'service',
                    value TEXT NOT NULL,
                    action TEXT NOT NULL DEFAULT 'block',
                    schedule TEXT NOT NULL DEFAULT '{}',
                    expires_at INTEGER NOT NULL DEFAULT 0,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS parental_profiles (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    member_ids TEXT NOT NULL DEFAULT '[]',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    paused INTEGER NOT NULL DEFAULT 0,
                    pause_until TEXT NOT NULL DEFAULT '',
                    daily_limit_minutes INTEGER NOT NULL DEFAULT 0,
                    content_filter TEXT NOT NULL DEFAULT 'none',
                    custom_dns TEXT NOT NULL DEFAULT '',
                    schedule TEXT NOT NULL DEFAULT '{}',
                    bedtime TEXT NOT NULL DEFAULT '{}',
                    used_minutes_today INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS adblock (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    enabled INTEGER NOT NULL DEFAULT 0,
                    blocklists TEXT NOT NULL DEFAULT '[]',
                    update_interval_hours INTEGER NOT NULL DEFAULT 24,
                    total_queries INTEGER NOT NULL DEFAULT 0,
                    blocked_queries INTEGER NOT NULL DEFAULT 0,
                    last_updated TEXT NOT NULL DEFAULT ''
                );

                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    severity TEXT NOT NULL DEFAULT 'info',
                    message TEXT NOT NULL,
                    router_id TEXT NOT NULL DEFAULT '',
                    device_id TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    data TEXT NOT NULL DEFAULT '{}'
                );

                CREATE TABLE IF NOT EXISTS notifications (
                    id TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL DEFAULT '',
                    read INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    data TEXT NOT NULL DEFAULT '{}'
                );

                CREATE TABLE IF NOT EXISTS agent_tokens (
                    agent_id TEXT PRIMARY KEY,
                    router_id TEXT NOT NULL,
                    token_hash TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            device_columns = {
                row[1]
                for row in self._connection.execute("PRAGMA table_info(devices)")
            }
            if "display_name" not in device_columns:
                self._connection.execute(
                    "ALTER TABLE devices ADD COLUMN display_name TEXT NOT NULL DEFAULT ''"
                )
            if "pause_until" not in device_columns:
                self._connection.execute(
                    "ALTER TABLE devices ADD COLUMN pause_until INTEGER NOT NULL DEFAULT 0"
                )
            self._connection.execute(
                "INSERT OR IGNORE INTO adblock (id) VALUES (1)"
            )

    def close(self) -> None:
        with self._lock:
            self._connection.close()

    # ---------------------------------------------------------------- helpers

    def _all(self, query: str, args: Iterable[Any] = ()) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._connection.execute(query, tuple(args)).fetchall()
        return [row for row in (_decode_row(r) for r in rows) if row is not None]

    def _one(
        self, query: str, args: Iterable[Any] = ()
    ) -> dict[str, Any] | None:
        with self._lock:
            row = self._connection.execute(query, tuple(args)).fetchone()
        return _decode_row(row)

    # ---------------------------------------------------------------- routers

    def list_routers(self) -> list[dict[str, Any]]:
        return self._all("SELECT * FROM routers ORDER BY name")

    def get_router(self, router_id: str) -> dict[str, Any] | None:
        return self._one("SELECT * FROM routers WHERE id = ?", (router_id,))

    def create_router(self, data: dict[str, Any]) -> dict[str, Any]:
        router_id = data.get("id") or _new_id()
        now = _now()
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO routers
                    (id, name, address, port, scheme, username, password,
                     verify_tls, model, openwrt_version, status, last_seen,
                     capabilities, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    router_id,
                    data.get("name", ""),
                    data.get("address", ""),
                    int(data.get("port", 80)),
                    data.get("scheme", "http"),
                    data.get("username", ""),
                    data.get("password", ""),
                    1 if data.get("verify_tls", True) else 0,
                    data.get("model", ""),
                    data.get("openwrt_version", ""),
                    data.get("status", "unknown"),
                    data.get("last_seen", ""),
                    _encode(data.get("capabilities", [])),
                    now,
                    now,
                ),
            )
        return self.get_router(router_id)  # type: ignore[return-value]

    def update_router(self, router_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        current = self.get_router(router_id)
        if current is None:
            return None
        fields = {
            "name",
            "address",
            "port",
            "scheme",
            "username",
            "password",
            "verify_tls",
            "model",
            "openwrt_version",
            "status",
            "last_seen",
        }
        updates: list[str] = []
        values: list[Any] = []
        for key in fields:
            if key in data:
                value = data[key]
                if key == "verify_tls":
                    value = 1 if value else 0
                if key == "port":
                    value = int(value)
                updates.append(f"{key} = ?")
                values.append(value)
        if "capabilities" in data:
            updates.append("capabilities = ?")
            values.append(_encode(data["capabilities"]))
        if not updates:
            return current
        updates.append("updated_at = ?")
        values.append(_now())
        values.append(router_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE routers SET {', '.join(updates)} WHERE id = ?", values
            )
        return self.get_router(router_id)

    def delete_router(self, router_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "DELETE FROM routers WHERE id = ?", (router_id,)
            )
            self._connection.execute(
                "DELETE FROM devices WHERE router_id = ?", (router_id,)
            )
        return cursor.rowcount > 0

    # ---------------------------------------------------------------- devices

    def list_devices(
        self,
        router_id: str | None = None,
        online: bool | None = None,
        group_id: str | None = None,
        query: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        where: list[str] = []
        args: list[Any] = []
        if router_id:
            where.append("router_id = ?")
            args.append(router_id)
        if online is not None:
            where.append("online = ?")
            args.append(1 if online else 0)
        if group_id:
            where.append("group_id = ?")
            args.append(group_id)
        if query:
            like = f"%{query}%"
            where.append(
                "(hostname LIKE ? OR display_name LIKE ? OR ipv4 LIKE ? OR mac LIKE ? OR vendor LIKE ?)"
            )
            args.extend([like, like, like, like, like])
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        total_row = self._one(
            f"SELECT COUNT(*) AS count FROM devices {clause}", args
        )
        total = int(total_row["count"]) if total_row else 0
        items = self._all(
            f"SELECT * FROM devices {clause} ORDER BY hostname, ipv4 LIMIT ? OFFSET ?",
            [*args, limit, offset],
        )
        return items, total

    def get_device(self, device_id: str) -> dict[str, Any] | None:
        return self._one("SELECT * FROM devices WHERE id = ?", (device_id,))

    def update_device(self, device_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        allowed = {
            "hostname",
            "display_name",
            "device_type",
            "group_id",
            "vendor",
            "tags",
        }
        updates: list[str] = []
        values: list[Any] = []
        for key in allowed:
            if key in data:
                updates.append(f"{key} = ?")
                values.append(_encode(data[key]) if key == "tags" else data[key])
        if not updates:
            return self.get_device(device_id)
        values.append(device_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE devices SET {', '.join(updates)} WHERE id = ?", values
            )
        return self.get_device(device_id)

    def set_device_state(
        self,
        device_id: str,
        *,
        blocked: bool | None = None,
        paused: bool | None = None,
        online: bool | None = None,
        pause_until: int | None = None,
    ) -> dict[str, Any] | None:
        updates: list[str] = []
        values: list[Any] = []
        for key, value in (
            ("blocked", blocked),
            ("paused", paused),
            ("online", online),
        ):
            if value is not None:
                updates.append(f"{key} = ?")
                values.append(1 if value else 0)
        if pause_until is not None:
            updates.append("pause_until = ?")
            values.append(int(pause_until))
        if not updates:
            return self.get_device(device_id)
        values.append(device_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE devices SET {', '.join(updates)} WHERE id = ?", values
            )
        return self.get_device(device_id)

    def upsert_devices(
        self, router_id: str, devices: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        now = _now()
        with self._lock, self._connection:
            for device in devices:
                mac = (device.get("mac") or "").lower()
                if not mac:
                    continue
                existing = self._connection.execute(
                    "SELECT id, first_seen, blocked, paused, group_id, device_type "
                    "FROM devices WHERE router_id = ? AND mac = ?",
                    (router_id, mac),
                ).fetchone()
                if existing:
                    self._connection.execute(
                        """
                        UPDATE devices SET ipv4 = ?, ipv6 = ?, hostname = ?,
                            vendor = ?, connection = ?, online = ?, last_seen = ?
                        WHERE id = ?
                        """,
                        (
                            device.get("ipv4", ""),
                            _encode(device.get("ipv6", [])),
                            device.get("hostname", ""),
                            device.get("vendor", ""),
                            device.get("connection", "unknown"),
                            1 if device.get("online", True) else 0,
                            now,
                            existing["id"],
                        ),
                    )
                else:
                    self._connection.execute(
                        """
                        INSERT INTO devices
                            (id, router_id, mac, ipv4, ipv6, hostname, vendor,
                             device_type, connection, online, blocked, paused,
                             group_id, first_seen, last_seen, tags)
                        VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?, 0, 0, '', ?, ?, '[]')
                        """,
                        (
                            _new_id(),
                            router_id,
                            mac,
                            device.get("ipv4", ""),
                            _encode(device.get("ipv6", [])),
                            device.get("hostname", ""),
                            device.get("vendor", ""),
                            device.get("connection", "unknown"),
                            1 if device.get("online", True) else 0,
                            now,
                            now,
                        ),
                    )
        return self.list_devices(router_id=router_id, limit=10000)[0]

    # ---------------------------------------------------------------- interfaces

    def upsert_interfaces(
        self, router_id: str, interfaces: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        now = _now()
        with self._lock, self._connection:
            for interface in interfaces:
                interface_id = str(
                    interface.get("id") or interface.get("name") or ""
                )
                if not interface_id:
                    continue
                self._connection.execute(
                    """
                    INSERT INTO interfaces
                        (router_id, id, name, type, up, mac, addresses,
                         rx_bytes, tx_bytes, errors, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(router_id, id) DO UPDATE SET
                        name = excluded.name,
                        type = excluded.type,
                        up = excluded.up,
                        mac = excluded.mac,
                        addresses = excluded.addresses,
                        rx_bytes = excluded.rx_bytes,
                        tx_bytes = excluded.tx_bytes,
                        errors = excluded.errors,
                        updated_at = excluded.updated_at
                    """,
                    (
                        router_id,
                        interface_id,
                        interface.get("name", interface_id),
                        interface.get("type", ""),
                        1 if interface.get("up") else 0,
                        interface.get("mac", ""),
                        _encode(interface.get("addresses", [])),
                        int(interface.get("rx_bytes", 0) or 0),
                        int(interface.get("tx_bytes", 0) or 0),
                        int(interface.get("errors", 0) or 0),
                        now,
                    ),
                )
        return self.list_interfaces(router_id)

    def list_interfaces(self, router_id: str | None = None) -> list[dict[str, Any]]:
        if router_id:
            return self._all(
                "SELECT * FROM interfaces WHERE router_id = ? ORDER BY name",
                (router_id,),
            )
        return self._all("SELECT * FROM interfaces ORDER BY router_id, name")

    # ---------------------------------------------------------------- groups

    def list_groups(self) -> list[dict[str, Any]]:
        return self._all("SELECT * FROM groups ORDER BY name")

    def create_group(self, data: dict[str, Any]) -> dict[str, Any]:
        group_id = _new_id()
        now = _now()
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO groups (id, name, description, member_ids, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    group_id,
                    data.get("name", ""),
                    data.get("description", ""),
                    _encode(data.get("member_ids", [])),
                    now,
                    now,
                ),
            )
        return self._one("SELECT * FROM groups WHERE id = ?", (group_id,))  # type: ignore[return-value]

    def update_group(self, group_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        current = self._one("SELECT * FROM groups WHERE id = ?", (group_id,))
        if current is None:
            return None
        updates: list[str] = []
        values: list[Any] = []
        for key in ("name", "description"):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(data[key])
        if "member_ids" in data:
            updates.append("member_ids = ?")
            values.append(_encode(data["member_ids"]))
        if not updates:
            return current
        updates.append("updated_at = ?")
        values.append(_now())
        values.append(group_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE groups SET {', '.join(updates)} WHERE id = ?",
                values,
            )
        return self._one("SELECT * FROM groups WHERE id = ?", (group_id,))

    def delete_group(self, group_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute("DELETE FROM groups WHERE id = ?", (group_id,))
        return cursor.rowcount > 0

    # ---------------------------------------------------------------- policies

    def list_policies(self) -> list[dict[str, Any]]:
        return self._all("SELECT * FROM policies ORDER BY name")

    def get_policy(self, policy_id: str) -> dict[str, Any] | None:
        return self._one("SELECT * FROM policies WHERE id = ?", (policy_id,))

    def create_policy(self, data: dict[str, Any]) -> dict[str, Any]:
        policy_id = _new_id()
        now = _now()
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO policies
                    (id, name, description, enabled, scope, target_ids, rules,
                     schedule, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    policy_id,
                    data.get("name", ""),
                    data.get("description", ""),
                    1 if data.get("enabled", True) else 0,
                    data.get("scope", "device"),
                    _encode(data.get("target_ids", [])),
                    _encode(data.get("rules", [])),
                    _encode(data.get("schedule", {})),
                    now,
                    now,
                ),
            )
        return self.get_policy(policy_id)  # type: ignore[return-value]

    def update_policy(self, policy_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        current = self.get_policy(policy_id)
        if current is None:
            return None
        fields = ("name", "description", "scope")
        updates: list[str] = []
        values: list[Any] = []
        for key in fields:
            if key in data:
                updates.append(f"{key} = ?")
                values.append(data[key])
        for key in ("enabled",):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(1 if data[key] else 0)
        for key in ("target_ids", "rules", "schedule"):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(_encode(data[key]))
        if not updates:
            return current
        updates.append("updated_at = ?")
        values.append(_now())
        values.append(policy_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE policies SET {', '.join(updates)} WHERE id = ?", values
            )
        return self.get_policy(policy_id)

    def delete_policy(self, policy_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute("DELETE FROM policies WHERE id = ?", (policy_id,))
        return cursor.rowcount > 0

    # ------------------------------------------------------- filtering rules

    def list_filtering_rules(self) -> list[dict[str, Any]]:
        return self._all(
            "SELECT * FROM filtering_rules ORDER BY name, created_at"
        )

    def get_filtering_rule(self, rule_id: str) -> dict[str, Any] | None:
        return self._one(
            "SELECT * FROM filtering_rules WHERE id = ?", (rule_id,)
        )

    def create_filtering_rule(self, data: dict[str, Any]) -> dict[str, Any]:
        rule_id = _new_id()
        now = _now()
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO filtering_rules
                    (id, name, target_type, target_ids, kind, value, action,
                     schedule, expires_at, enabled, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    rule_id,
                    data.get("name", ""),
                    data.get("target_type", "device"),
                    _encode(data.get("target_ids", [])),
                    data.get("kind", "service"),
                    data.get("value", ""),
                    data.get("action", "block"),
                    _encode(data.get("schedule", {})),
                    int(data.get("expires_at", 0) or 0),
                    1 if data.get("enabled", True) else 0,
                    now,
                    now,
                ),
            )
        return self.get_filtering_rule(rule_id)  # type: ignore[return-value]

    def update_filtering_rule(
        self, rule_id: str, data: dict[str, Any]
    ) -> dict[str, Any] | None:
        current = self.get_filtering_rule(rule_id)
        if current is None:
            return None
        updates: list[str] = []
        values: list[Any] = []
        for key in ("name", "target_type", "kind", "value", "action"):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(data[key])
        if "target_ids" in data:
            updates.append("target_ids = ?")
            values.append(_encode(data["target_ids"]))
        if "schedule" in data:
            updates.append("schedule = ?")
            values.append(_encode(data["schedule"]))
        if "expires_at" in data:
            updates.append("expires_at = ?")
            values.append(int(data["expires_at"] or 0))
        if "enabled" in data:
            updates.append("enabled = ?")
            values.append(1 if data["enabled"] else 0)
        if not updates:
            return current
        updates.append("updated_at = ?")
        values.append(_now())
        values.append(rule_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE filtering_rules SET {', '.join(updates)} WHERE id = ?",
                values,
            )
        return self.get_filtering_rule(rule_id)

    def delete_filtering_rule(self, rule_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "DELETE FROM filtering_rules WHERE id = ?", (rule_id,)
            )
        return cursor.rowcount > 0

    # ---------------------------------------------------------------- parental

    def list_parental(self) -> list[dict[str, Any]]:
        return self._all("SELECT * FROM parental_profiles ORDER BY name")

    def get_parental(self, profile_id: str) -> dict[str, Any] | None:
        return self._one("SELECT * FROM parental_profiles WHERE id = ?", (profile_id,))

    def create_parental(self, data: dict[str, Any]) -> dict[str, Any]:
        profile_id = _new_id()
        now = _now()
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO parental_profiles
                    (id, name, member_ids, enabled, paused, pause_until,
                     daily_limit_minutes, content_filter, custom_dns, schedule,
                     bedtime, used_minutes_today, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, '', ?, ?, ?, ?, ?, 0, ?, ?)
                """,
                (
                    profile_id,
                    data.get("name", ""),
                    _encode(data.get("member_ids", [])),
                    1 if data.get("enabled", True) else 0,
                    int(data.get("daily_limit_minutes", 0)),
                    data.get("content_filter", "none"),
                    data.get("custom_dns", ""),
                    _encode(data.get("schedule", {})),
                    _encode(data.get("bedtime", {})),
                    now,
                    now,
                ),
            )
        return self.get_parental(profile_id)  # type: ignore[return-value]

    def update_parental(self, profile_id: str, data: dict[str, Any]) -> dict[str, Any] | None:
        current = self.get_parental(profile_id)
        if current is None:
            return None
        fields = ("name", "content_filter", "custom_dns", "pause_until")
        updates: list[str] = []
        values: list[Any] = []
        for key in fields:
            if key in data:
                updates.append(f"{key} = ?")
                values.append(data[key])
        for key in ("enabled", "paused"):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(1 if data[key] else 0)
        if "daily_limit_minutes" in data:
            updates.append("daily_limit_minutes = ?")
            values.append(int(data["daily_limit_minutes"]))
        for key in ("member_ids", "schedule", "bedtime"):
            if key in data:
                updates.append(f"{key} = ?")
                values.append(_encode(data[key]))
        if not updates:
            return current
        updates.append("updated_at = ?")
        values.append(_now())
        values.append(profile_id)
        with self._lock, self._connection:
            self._connection.execute(
                f"UPDATE parental_profiles SET {', '.join(updates)} WHERE id = ?",
                values,
            )
        return self.get_parental(profile_id)

    def delete_parental(self, profile_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "DELETE FROM parental_profiles WHERE id = ?", (profile_id,)
            )
        return cursor.rowcount > 0

    # ---------------------------------------------------------------- adblock

    def get_adblock(self) -> dict[str, Any]:
        row = self._one("SELECT * FROM adblock WHERE id = 1")
        return row or {
            "enabled": False,
            "blocklists": [],
            "update_interval_hours": 24,
            "total_queries": 0,
            "blocked_queries": 0,
            "last_updated": "",
        }

    def update_adblock(self, data: dict[str, Any]) -> dict[str, Any]:
        updates: list[str] = []
        values: list[Any] = []
        if "enabled" in data:
            updates.append("enabled = ?")
            values.append(1 if data["enabled"] else 0)
        if "blocklists" in data:
            updates.append("blocklists = ?")
            values.append(_encode(data["blocklists"]))
        if "update_interval_hours" in data:
            updates.append("update_interval_hours = ?")
            values.append(int(data["update_interval_hours"]))
        if updates:
            with self._lock, self._connection:
                self._connection.execute(
                    f"UPDATE adblock SET {', '.join(updates)} WHERE id = 1", values
                )
        return self.get_adblock()

    # ---------------------------------------------------------------- events

    def list_events(
        self, severity: str | None = None, limit: int = 100, offset: int = 0
    ) -> tuple[list[dict[str, Any]], int]:
        where = "WHERE severity = ?" if severity else ""
        args = [severity] if severity else []
        total_row = self._one(f"SELECT COUNT(*) AS count FROM events {where}", args)
        total = int(total_row["count"]) if total_row else 0
        items = self._all(
            f"SELECT * FROM events {where} ORDER BY created_at DESC LIMIT ? OFFSET ?",
            [*args, limit, offset],
        )
        return items, total

    def create_event(self, data: dict[str, Any]) -> dict[str, Any]:
        event_id = _new_id()
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO events (id, type, severity, message, router_id, device_id, created_at, data) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    event_id,
                    data.get("type", ""),
                    data.get("severity", "info"),
                    data.get("message", ""),
                    data.get("router_id", ""),
                    data.get("device_id", ""),
                    _now(),
                    _encode(data.get("data", {})),
                ),
            )
        return self._one("SELECT * FROM events WHERE id = ?", (event_id,))  # type: ignore[return-value]

    def list_notifications(self, unread: bool | None = None) -> list[dict[str, Any]]:
        where = "WHERE read = 0" if unread else ""
        return self._all(
            f"SELECT * FROM notifications {where} ORDER BY created_at DESC"
        )

    def mark_notification_read(self, notification_id: str) -> bool:
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "UPDATE notifications SET read = 1 WHERE id = ?", (notification_id,)
            )
        return cursor.rowcount > 0

    def create_notification(self, data: dict[str, Any]) -> dict[str, Any]:
        notification_id = _new_id()
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO notifications (id, type, title, body, read, created_at, data) "
                "VALUES (?, ?, ?, ?, 0, ?, ?)",
                (
                    notification_id,
                    data.get("type", ""),
                    data.get("title", ""),
                    data.get("body", ""),
                    _now(),
                    _encode(data.get("data", {})),
                ),
            )
        return self._one(
            "SELECT * FROM notifications WHERE id = ?", (notification_id,)
        )  # type: ignore[return-value]

    # ---------------------------------------------------------------- agents

    def create_agent(self, router_id: str, token_hash: str) -> dict[str, Any]:
        agent_id = _new_id()
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO agent_tokens (agent_id, router_id, token_hash, created_at) "
                "VALUES (?, ?, ?, ?)",
                (agent_id, router_id, token_hash, _now()),
            )
        return {"agent_id": agent_id, "router_id": router_id}

    def find_agent_by_token(self, token_hash: str) -> dict[str, Any] | None:
        return self._one(
            "SELECT * FROM agent_tokens WHERE token_hash = ?", (token_hash,)
        )
