from __future__ import annotations

import os
import time
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from ..adguard import AdGuardClient
from ..adguard_sync import _target_devices, sync_filtering
from ..asn_filter import ASNFilterError, sync_app_filter
from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..filtering_catalog import (
    CATEGORIES,
    SERVICES,
    SERVICE_IDS,
    asns_for,
)
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/filtering", tags=["Filtering"], dependencies=[Depends(require_auth)]
)


def _source(request: Request) -> AdGuardClient | None:
    return getattr(request.app.state, "adguard", None)


def _router_source(request: Request, db: ControlDatabase) -> RouterData | None:
    source = getattr(request.app.state, "router_data", None)
    if source is not None:
        return source
    routers = db.list_routers()
    if not routers:
        return None
    return RouterData(
        routers[0]["address"],
        ssh_key=os.getenv("OPENWALLA_ROUTER_SSH_KEY"),
    )


def _rule_addresses(db: ControlDatabase, rule: dict[str, Any]) -> list[str]:
    """IPs belonging to a rule even after it has been deleted."""
    devices, _ = db.list_devices(limit=10000)
    groups = db.list_groups()
    return sorted(
        {
            str(device.get("ipv4"))
            for device in _target_devices(rule, devices, groups)
            if device.get("ipv4")
        }
    )


def _sync(
    request: Request,
    db: ControlDatabase,
    extra_addresses: list[str] | None = None,
) -> None:
    adguard = _source(request)
    addresses = set(extra_addresses or [])
    if adguard is not None:
        try:
            result = sync_filtering(db, adguard)
        except Exception as error:
            raise HTTPException(502, f"AdGuard sync failed: {error}") from error
        addresses.update(result.get("ips", []))
        # Every explicit rule change must invalidate cached DNS, including a
        # delete where no managed client remains.
        try:
            adguard.clear_cache()
        except Exception:
            pass
    # Even when the desired state is unchanged, an explicit rule change should
    # force the device to reconnect so cached DNS/sockets cannot bypass it.
    _reset_device_connections(request, db, sorted(addresses))
    source = _router_source(request, db)
    if source is None:
        return
    try:
        sync_app_filter(db, source)
    except (ASNFilterError, RouterDataError) as error:
        raise HTTPException(502, f"Strict ASN apply failed: {error}") from error


def _reset_device_connections(
    request: Request, db: ControlDatabase, addresses: list[str]
) -> None:
    if not addresses:
        return
    source = _router_source(request, db)
    if source is None:
        return
    for address in addresses:
        try:
            source.clear_conntrack(address)
        except Exception:
            continue


def _validate(payload: dict[str, Any]) -> dict[str, Any]:
    target_type = str(payload.get("target_type") or "device")
    if target_type not in {"device", "group", "all"}:
        raise HTTPException(422, "target_type must be device, group or all")
    kind = str(payload.get("kind") or "service")
    if kind not in {"service", "category", "domain"}:
        raise HTTPException(422, "kind must be service, category or domain")
    value = str(payload.get("value") or "").strip()
    if not value:
        raise HTTPException(422, "value is required")
    if kind == "service" and value not in SERVICE_IDS:
        raise HTTPException(422, f"unknown service: {value}")
    if kind == "category" and value not in CATEGORIES:
        raise HTTPException(422, f"unknown category: {value}")
    action = str(payload.get("action") or "block")
    if action not in {"block", "allow"}:
        raise HTTPException(422, "action must be block or allow")
    mode = str(payload.get("mode") or "dns")
    if mode not in {"dns", "asn"}:
        raise HTTPException(422, "mode must be dns or asn")
    if mode == "asn":
        if action != "block":
            raise HTTPException(422, "strict ASN mode only supports block rules")
        if kind not in {"service", "category"}:
            raise HTTPException(
                422, "strict ASN mode supports app/service or category rules"
            )
        if not asns_for(kind, value):
            raise HTTPException(
                422,
                "this app has no known ASN; use DNS mode or choose another app",
            )
    target_ids = payload.get("target_ids", [])
    if target_type != "all" and not isinstance(target_ids, list):
        raise HTTPException(422, "target_ids must be a list")
    schedule = payload.get("schedule") or {}
    if not isinstance(schedule, dict):
        raise HTTPException(422, "schedule must be an object")
    if schedule.get("start") and schedule.get("end"):
        for key in ("start", "end"):
            try:
                hour, minute = str(schedule[key]).split(":", 1)
                assert 0 <= int(hour) <= 23 and 0 <= int(minute[:2]) <= 59
            except (ValueError, AssertionError):
                raise HTTPException(422, f"invalid schedule {key}") from None
    expires_at = int(payload.get("expires_at") or 0)
    if payload.get("expires_minutes") is not None:
        try:
            minutes = int(payload["expires_minutes"])
        except (TypeError, ValueError):
            raise HTTPException(422, "expires_minutes must be an integer") from None
        if minutes > 0:
            expires_at = int(time.time()) + minutes * 60
    cleaned = {
        "name": str(payload.get("name") or value.title),
        "target_type": target_type,
        "target_ids": [str(value) for value in target_ids],
        "kind": kind,
        "value": value,
        "action": action,
        "mode": mode,
        "schedule": schedule,
        "expires_at": expires_at,
        "enabled": bool(payload.get("enabled", True)),
    }
    return cleaned


@router.get("/catalog")
def catalog():
    return {"services": SERVICES, "categories": CATEGORIES}


@router.get("/rules")
def list_rules(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_filtering_rules()}


@router.post("/rules", status_code=201)
def create_rule(
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    rule = db.create_filtering_rule(_validate(payload))
    _sync(request, db)
    return rule


@router.put("/rules/{rule_id}")
def update_rule(
    rule_id: str,
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db.get_filtering_rule(rule_id)
    if current is None:
        raise HTTPException(404, "rule not found")
    cleaned = _validate({**current, **payload})
    value = db.update_filtering_rule(rule_id, cleaned)
    if value is None:
        raise HTTPException(404, "rule not found")
    _sync(request, db)
    return value


@router.post("/rules/{rule_id}/apply")
def apply_rule(
    rule_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    rule = db.get_filtering_rule(rule_id)
    if rule is None:
        raise HTTPException(404, "rule not found")
    _sync(request, db)
    return {"applied": True, "rule_id": rule_id, "mode": rule.get("mode", "dns")}


@router.delete("/rules/{rule_id}", status_code=204)
def delete_rule(
    rule_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    rule = db.get_filtering_rule(rule_id)
    if rule is None:
        raise HTTPException(404, "rule not found")
    addresses = _rule_addresses(db, rule)
    db.delete_filtering_rule(rule_id)
    _sync(request, db, addresses)
    return None


@router.get("/status")
def status(request: Request):
    adguard = _source(request)
    if adguard is None:
        raise HTTPException(503, "AdGuard is not configured")
    try:
        return adguard.status()
    except Exception as error:
        raise HTTPException(502, str(error)) from error
