"""Reconcile parental profiles into AdGuard clients idempotently.

Desired state is computed from all enabled parental profiles. AdGuard clients
are keyed by device MAC, so a device in multiple profiles gets the most
restrictive filter. Repeated runs only update clients whose settings or IPs
actually changed, and stale OpenWalla clients are removed.
"""

from __future__ import annotations

from typing import Any

from .adguard import AdGuardClient
from .control_db import ControlDatabase


def _desired_clients(
    profiles: list[dict[str, Any]],
    devices: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    by_id = {str(device["id"]): device for device in devices}
    desired: dict[str, dict[str, Any]] = {}

    for profile in profiles:
        if not profile.get("enabled", True) or profile.get("paused", False):
            continue
        content_filter = str(profile.get("content_filter") or "none")
        if content_filter not in {"safe", "adult"}:
            continue
        for member_id in profile.get("member_ids", []):
            device = by_id.get(str(member_id))
            if not device:
                continue
            mac = str(device.get("mac") or "").lower()
            if not mac:
                continue
            current = desired.get(mac)
            parental = current.get("parental", False) if current else False
            current = {
                "name": f"openwalla:{mac}",
                "ids": sorted(
                    value
                    for value in {mac, str(device.get("ipv4") or "")}
                    if value
                ),
                "safe_search": True,
                "parental": parental or content_filter == "adult",
            }
            desired[mac] = current
    return desired


def _matches(current: dict[str, Any], desired: dict[str, Any]) -> bool:
    current_ids = sorted(str(value) for value in (current.get("ids") or []))
    if current_ids != sorted(desired["ids"]):
        return False
    safe_search = current.get("safe_search") or {}
    if bool(safe_search.get("enabled")) != bool(desired["safe_search"]):
        return False
    if bool(current.get("parental_enabled")) != bool(desired["parental"]):
        return False
    if not bool(current.get("filtering_enabled")):
        return False
    if bool(current.get("use_global_settings")):
        return False
    return True


def sync_parental_profiles(
    database: ControlDatabase,
    adguard: AdGuardClient,
) -> dict[str, int]:
    devices, _ = database.list_devices(limit=10000)
    desired = _desired_clients(database.list_parental(), devices)
    current = {
        client["name"]: client
        for client in adguard.clients()
        if str(client.get("name", "")).startswith("openwalla:")
    }

    removed = 0
    updated = 0
    added = 0

    # Remove stale clients first so their IPs can be reused.
    for name in sorted(set(current) - set(value["name"] for value in desired.values())):
        adguard.delete_client(name)
        current.pop(name, None)
        removed += 1

    for mac, wanted in desired.items():
        name = wanted["name"]
        existing = current.get(name)
        if existing is not None and _matches(existing, wanted):
            continue
        adguard.upsert_client(
            name,
            list(wanted["ids"]),
            safe_search=bool(wanted["safe_search"]),
            parental=bool(wanted["parental"]),
        )
        if existing is None:
            added += 1
        else:
            updated += 1

    return {"added": added, "updated": updated, "removed": removed}
