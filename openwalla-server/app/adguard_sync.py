"""Reconcile parental profiles and filtering rules into AdGuard."""

from __future__ import annotations

from datetime import datetime, time as dt_time
from typing import Any
from zoneinfo import ZoneInfo

from .adguard import AdGuardClient
from .control_db import ControlDatabase
from .filtering_catalog import CATEGORIES

DAY_INDEX = {
    "mon": 0,
    "monday": 0,
    "tue": 1,
    "tuesday": 1,
    "wed": 2,
    "wednesday": 2,
    "thu": 3,
    "thursday": 3,
    "fri": 4,
    "friday": 4,
    "sat": 5,
    "saturday": 5,
    "sun": 6,
    "sunday": 6,
}


def _timezone(value: str | None, fallback: str) -> ZoneInfo:
    try:
        return ZoneInfo(value or fallback)
    except Exception:
        return ZoneInfo("UTC")


def _minutes(value: str) -> int | None:
    try:
        hour, minute = value.split(":", 1)
        parsed = int(hour) * 60 + int(minute[:2])
    except (ValueError, AttributeError):
        return None
    return parsed if 0 <= parsed < 1440 else None


def _rule_active(rule: dict[str, Any], default_timezone: str) -> bool:
    if not rule.get("enabled", True):
        return False
    expires = int(rule.get("expires_at") or 0)
    schedule = rule.get("schedule") or {}
    tz = _timezone(schedule.get("timezone"), default_timezone)
    now = datetime.now(tz)
    if expires and int(now.timestamp()) >= expires:
        return False
    days = schedule.get("days") or []
    start = _minutes(str(schedule.get("start") or ""))
    end = _minutes(str(schedule.get("end") or ""))
    if start is None or end is None:
        return True
    if days:
        indices = set()
        for value in days:
            text = str(value).strip().lower()
            if text.isdigit():
                indices.add(int(text) % 7)
            elif text in DAY_INDEX:
                indices.add(DAY_INDEX[text])
        if now.weekday() not in indices:
            return False
    current = now.hour * 60 + now.minute
    if start == end:
        return True
    if start < end:
        return start <= current < end
    return current >= start or current < end


def _target_devices(
    rule: dict[str, Any],
    devices: list[dict[str, Any]],
    groups: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    by_id = {str(device["id"]): device for device in devices}
    values = [str(value) for value in rule.get("target_ids", [])]
    target_type = rule.get("target_type", "device")
    if target_type == "all":
        return devices
    if target_type == "group":
        group_map = {str(group["id"]): group for group in groups}
        ids: list[str] = []
        for group_id in values:
            group = group_map.get(group_id)
            if group:
                ids.extend(str(value) for value in group.get("member_ids", []))
        values = ids
    return [by_id[value] for value in values if value in by_id]


def _normalize_domain(value: str) -> str:
    domain = value.strip().lower()
    for prefix in ("http://", "https://"):
        if domain.startswith(prefix):
            domain = domain[len(prefix) :]
    domain = domain.split("/", 1)[0].split(":", 1)[0]
    if domain.startswith("*."):
        domain = domain[2:]
    return domain.strip(".")


def _build_desired_state(
    profiles: list[dict[str, Any]],
    devices: list[dict[str, Any]],
    rules: list[dict[str, Any]] | None = None,
    groups: list[dict[str, Any]] | None = None,
    timezone: str = "America/Chicago",
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    desired: dict[str, dict[str, Any]] = {}
    managed_rules: set[str] = set()
    groups = groups or []

    def client_for(device: dict[str, Any]) -> dict[str, Any]:
        mac = str(device.get("mac") or "").lower()
        client = desired.setdefault(
            mac,
            {
                "name": f"openwalla:{mac}",
                "ids": sorted(
                    value
                    for value in {mac, str(device.get("ipv4") or "")}
                    if value
                ),
                "safe_search": False,
                "parental": False,
                "blocked_services": set(),
            },
        )
        return client

    for profile in profiles:
        if not profile.get("enabled", True) or profile.get("paused", False):
            continue
        content_filter = str(profile.get("content_filter") or "none")
        if content_filter not in {"safe", "adult"}:
            continue
        for member_id in profile.get("member_ids", []):
            device = next(
                (item for item in devices if str(item["id"]) == str(member_id)),
                None,
            )
            if not device:
                continue
            client = client_for(device)
            client["safe_search"] = True
            client["parental"] = client["parental"] or content_filter == "adult"

    for rule in rules or []:
        if not _rule_active(rule, timezone):
            continue
        kind = str(rule.get("kind") or "service")
        action = str(rule.get("action") or "block")
        value = str(rule.get("value") or "").strip()
        if not value:
            continue
        for device in _target_devices(rule, devices, groups):
            client = client_for(device)
            if kind == "service":
                if action == "allow":
                    client["blocked_services"].discard(value)
                else:
                    client["blocked_services"].add(value)
            elif kind == "category":
                services = CATEGORIES.get(value, {}).get("services", [])
                if action == "allow":
                    client["blocked_services"].difference_update(services)
                else:
                    client["blocked_services"].update(services)
            elif kind == "domain":
                domain = _normalize_domain(value)
                if not domain:
                    continue
                prefix = "@@" if action == "allow" else ""
                mac = client["name"].split(":", 1)[1]
                managed_rules.add(
                    f"{prefix}||{domain}^$client='openwalla:{mac}'"
                )

    for client in desired.values():
        client["blocked_services"] = sorted(client["blocked_services"])
    return desired, sorted(managed_rules)


def _desired_clients(
    profiles: list[dict[str, Any]],
    devices: list[dict[str, Any]],
    rules: list[dict[str, Any]] | None = None,
    groups: list[dict[str, Any]] | None = None,
    timezone: str = "America/Chicago",
) -> dict[str, dict[str, Any]]:
    clients, _ = _build_desired_state(
        profiles, devices, rules, groups, timezone
    )
    return clients


def _matches(current: dict[str, Any], desired: dict[str, Any]) -> bool:
    current_ids = sorted(str(value) for value in (current.get("ids") or []))
    if current_ids != sorted(desired["ids"]):
        return False
    safe_search = current.get("safe_search") or {}
    if bool(safe_search.get("enabled")) != bool(desired["safe_search"]):
        return False
    if bool(current.get("parental_enabled")) != bool(desired["parental"]):
        return False
    if sorted(current.get("blocked_services") or []) != sorted(
        desired.get("blocked_services") or []
    ):
        return False
    if not bool(current.get("filtering_enabled")):
        return False
    if bool(current.get("use_global_settings")):
        return False
    return True


def sync_filtering(
    database: ControlDatabase,
    adguard: AdGuardClient,
    timezone: str = "America/Chicago",
) -> dict[str, int]:
    devices, _ = database.list_devices(limit=10000)
    desired, managed_rules = _build_desired_state(
        database.list_parental(),
        devices,
        database.list_filtering_rules(),
        database.list_groups(),
        timezone,
    )
    current = {
        client["name"]: client
        for client in adguard.clients()
        if str(client.get("name", "")).startswith("openwalla:")
    }

    removed = 0
    updated = 0
    added = 0

    desired_names = {value["name"] for value in desired.values()}
    for name in sorted(set(current) - desired_names):
        adguard.delete_client(name)
        current.pop(name, None)
        removed += 1

    for wanted in desired.values():
        name = wanted["name"]
        existing = current.get(name)
        if existing is not None and _matches(existing, wanted):
            continue
        adguard.upsert_client(
            name,
            list(wanted["ids"]),
            safe_search=bool(wanted["safe_search"]),
            parental=bool(wanted["parental"]),
            blocked_services=list(wanted["blocked_services"]),
        )
        if existing is None:
            added += 1
        else:
            updated += 1

    adguard.sync_user_rules(managed_rules)
    return {
        "added": added,
        "updated": updated,
        "removed": removed,
    }


def sync_parental_profiles(
    database: ControlDatabase,
    adguard: AdGuardClient,
    timezone: str = "America/Chicago",
) -> dict[str, int]:
    return sync_filtering(database, adguard, timezone)
