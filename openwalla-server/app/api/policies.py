from __future__ import annotations

import os
import re
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..notifier import send_best_effort
from ..router_data import RouterData, RouterDataError

router = APIRouter(tags=["Policies"], dependencies=[Depends(require_auth)])

MAC_PATTERN = re.compile(r"^([0-9a-f]{2}:){5}[0-9a-f]{2}$")
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


def _source(request: Request, db: ControlDatabase):
    source = getattr(request.app.state, "router_data", None)
    if source is not None:
        return source
    routers = db.list_routers()
    if not routers:
        raise HTTPException(404, "router not found")
    return RouterData(
        routers[0]["address"], ssh_key=os.getenv("OPENWALLA_ROUTER_SSH_KEY")
    )


def _resolve_macs(db: ControlDatabase, ids: list[Any]) -> list[str]:
    macs: list[str] = []
    for value in ids:
        text = str(value)
        if MAC_PATTERN.match(text.lower()):
            macs.append(text.lower())
            continue
        device = db.get_device(text)
        if device and MAC_PATTERN.match(str(device["mac"]).lower()):
            macs.append(str(device["mac"]).lower())
    return sorted(set(macs))


def _policy_macs(db: ControlDatabase, policy: dict[str, Any]) -> list[str]:
    scope = policy.get("scope", "device")
    targets = policy.get("target_ids", [])
    if scope == "all":
        devices, _ = db.list_devices(limit=10000)
        return sorted({str(device["mac"]).lower() for device in devices})
    if scope == "group":
        ids: list[str] = []
        for group_id in targets:
            group = db._one("SELECT * FROM groups WHERE id = ?", (group_id,))
            if group:
                ids.extend(group.get("member_ids", []))
        return _resolve_macs(db, ids)
    return _resolve_macs(db, targets)


def _schedule(policy: dict[str, Any]) -> tuple[str, str, str]:
    schedule = policy.get("schedule") or {}
    raw_days = schedule.get("days") or []
    indices = set()
    for value in raw_days:
        text = str(value).strip().lower()
        if text.isdigit():
            indices.add(int(text) % 7)
        elif text in DAY_INDEX:
            indices.add(DAY_INDEX[text])
    return (
        ",".join(str(value) for value in sorted(indices)),
        str(schedule.get("start") or ""),
        str(schedule.get("end") or ""),
    )


def _apply_policy(
    request: Request,
    db: ControlDatabase,
    policy: dict[str, Any],
) -> None:
    source = _source(request, db)
    synthetic_id = f"policy_{policy['id']}"
    if not policy.get("enabled", True):
        try:
            source.delete_parental(synthetic_id)
        except RouterDataError as error:
            send_best_effort(
                getattr(request.app.state, "notifier", None),
                "Policy disable failed",
                str(error),
                "warning",
                "enforcement",
            )
            raise HTTPException(502, str(error)) from error
        return

    days, start, end = _schedule(policy)
    has_schedule = bool(days and start and end)
    # Without a schedule the policy is an always-on block. With a schedule
    # the parental engine blocks only inside the active window.
    always_block = not has_schedule
    try:
        source.sync_parental(
            synthetic_id,
            f"Policy: {policy.get('name') or policy['id']}",
            True,
            always_block,
            0,
            "none",
            "",
            0,
            days,
            start,
            end,
            _policy_macs(db, policy),
        )
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Policy enforcement failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error


def _reapply_group_policies(
    request: Request,
    db: ControlDatabase,
    group_id: str,
) -> None:
    for policy in db.list_policies():
        if (
            policy.get("enabled")
            and policy.get("scope") == "group"
            and group_id in policy.get("target_ids", [])
        ):
            _apply_policy(request, db, policy)


@router.get("/policies")
def list_policies(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_policies()}


@router.post("/policies", status_code=201)
def create_policy(
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    if not payload.get("rules"):
        payload["rules"] = [
            {"type": "internet", "value": "all", "action": "block"}
        ]
    policy = db.create_policy(payload)
    try:
        _apply_policy(request, db, policy)
    except HTTPException:
        db.delete_policy(policy["id"])
        raise
    return policy


@router.put("/policies/{policy_id}")
def update_policy(
    policy_id: str,
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db.get_policy(policy_id)
    if current is None:
        raise HTTPException(404, "policy not found")
    merged = {**current, **payload}
    _apply_policy(request, db, merged)
    value = db.update_policy(policy_id, payload)
    if value is None:
        raise HTTPException(404, "policy not found")
    return value


@router.delete("/policies/{policy_id}", status_code=204)
def delete_policy(
    policy_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db.get_policy(policy_id)
    if current is None:
        raise HTTPException(404, "policy not found")
    source = _source(request, db)
    try:
        source.delete_parental(f"policy_{policy_id}")
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Policy deletion failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error
    if not db.delete_policy(policy_id):
        raise HTTPException(404, "policy not found")
    return None


@router.get("/groups")
def list_groups(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_groups()}


@router.post("/groups", status_code=201)
def create_group(
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    return db.create_group(payload)


@router.put("/groups/{group_id}")
def update_group(
    group_id: str,
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db._one("SELECT * FROM groups WHERE id = ?", (group_id,))
    if current is None:
        raise HTTPException(404, "group not found")
    value = db.update_group(group_id, payload)
    if value is None:
        raise HTTPException(404, "group not found")
    try:
        _reapply_group_policies(request, db, group_id)
    except HTTPException:
        db.update_group(group_id, current)
        raise
    return value


@router.delete("/groups/{group_id}", status_code=204)
def delete_group(
    group_id: str,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not db.delete_group(group_id):
        raise HTTPException(404, "group not found")
    return None
