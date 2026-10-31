from __future__ import annotations

import os
import re
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..notifier import send_best_effort
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/parental",
    tags=["Parental"],
    dependencies=[Depends(require_auth)],
)

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


def _member_macs(db: ControlDatabase, profile: dict[str, Any]) -> list[str]:
    macs: list[str] = []
    for value in profile.get("member_ids", []):
        text = str(value)
        lowered = text.lower()
        if MAC_PATTERN.match(lowered):
            macs.append(lowered)
            continue
        device = db.get_device(text)
        if device and MAC_PATTERN.match(str(device["mac"]).lower()):
            macs.append(str(device["mac"]).lower())
    return sorted(set(macs))


def _member_devices(db: ControlDatabase, profile: dict[str, Any]) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    for value in profile.get("member_ids", []):
        device = db.get_device(str(value))
        if device and MAC_PATTERN.match(str(device["mac"]).lower()):
            devices.append(device)
    return devices


def _schedule(profile: dict[str, Any]) -> tuple[str, str, str]:
    schedule = profile.get("schedule") or {}
    bedtime = profile.get("bedtime") or {}
    selected = schedule if any(schedule.values()) else bedtime
    raw_days = selected.get("days") or []
    indices = set()
    for value in raw_days:
        text = str(value).strip().lower()
        if text.isdigit():
            indices.add(int(text) % 7)
        elif text in DAY_INDEX:
            indices.add(DAY_INDEX[text])
    return (
        ",".join(str(value) for value in sorted(indices)),
        str(selected.get("start") or ""),
        str(selected.get("end") or ""),
    )


def _apply_parental(
    request: Request,
    db: ControlDatabase,
    profile: dict[str, Any],
) -> None:
    source = _source(request, db)
    days, start, end = _schedule(profile)
    try:
        pause_until = int(profile.get("pause_until") or 0)
    except (TypeError, ValueError):
        pause_until = 0
    try:
        source.sync_parental(
            str(profile["id"]),
            str(profile.get("name") or "Profile"),
            bool(profile.get("enabled", True)),
            bool(profile.get("paused", False)),
            pause_until,
            str(profile.get("content_filter") or "none"),
            str(profile.get("custom_dns") or ""),
            int(profile.get("daily_limit_minutes") or 0),
            days,
            start,
            end,
            _member_macs(db, profile),
        )
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Parental enforcement failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error

    adguard = getattr(request.app.state, "adguard", None)
    if adguard is not None:
        try:
            adguard.sync_profile(
                str(profile["id"]),
                _member_devices(db, profile),
                str(profile.get("content_filter") or "none"),
            )
        except Exception as error:
            send_best_effort(
                getattr(request.app.state, "notifier", None),
                "Content filtering sync failed",
                str(error),
                "warning",
                "enforcement",
            )
            raise HTTPException(502, str(error)) from error


@router.get("/profiles")
def list_profiles(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_parental()}


@router.post("/profiles", status_code=201)
def create_profile(
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    profile = db.create_parental(payload)
    try:
        _apply_parental(request, db, profile)
    except HTTPException:
        db.delete_parental(profile["id"])
        raise
    return profile


@router.put("/profiles/{profile_id}")
def update_profile(
    profile_id: str,
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db.get_parental(profile_id)
    if current is None:
        raise HTTPException(404, "profile not found")
    merged = {**current, **payload}
    _apply_parental(request, db, merged)
    value = db.update_parental(profile_id, payload)
    if value is None:
        raise HTTPException(404, "profile not found")
    return value


@router.delete("/profiles/{profile_id}", status_code=204)
def delete_profile(
    profile_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    current = db.get_parental(profile_id)
    if current is None:
        raise HTTPException(404, "profile not found")
    source = _source(request, db)
    try:
        source.delete_parental(profile_id)
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Parental deletion failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error
    if not db.delete_parental(profile_id):
        raise HTTPException(404, "profile not found")
    return None
