from __future__ import annotations

import os
import time
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..notifier import send_best_effort
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/devices", tags=["Devices"], dependencies=[Depends(require_auth)]
)


def _get(db: ControlDatabase, device_id: str) -> dict[str, Any]:
    value = db.get_device(device_id)
    if value is None:
        raise HTTPException(404, "device not found")
    return value


def _source(request: Request, db: ControlDatabase, device: dict[str, Any]) -> Any:
    source = getattr(request.app.state, "router_data", None)
    if source is not None:
        return source
    router = db.get_router(device["router_id"])
    if router is None:
        raise HTTPException(404, "router not found")
    return RouterData(
        router["address"], ssh_key=os.getenv("OPENWALLA_ROUTER_SSH_KEY")
    )


def _action(
    request: Request,
    db: ControlDatabase,
    device_id: str,
    *,
    blocked: bool | None = None,
    event_type: str,
) -> dict[str, Any]:
    device = _get(db, device_id)
    source = _source(request, db, device)
    try:
        if blocked is True:
            source.apply_device_access(
                device["mac"], True, uuid.uuid4().hex
            )
        elif blocked is False and not device.get("paused"):
            source.apply_device_access(
                device["mac"], False, uuid.uuid4().hex
            )
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Device enforcement failed",
            f"{event_type.replace('_', ' ')}: {error}",
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error

    value = db.set_device_state(device_id, blocked=blocked)
    if value is None:
        raise HTTPException(404, "device not found")
    db.create_event(
        {
            "type": event_type,
            "severity": "info",
            "message": f"{event_type.replace('_', ' ')}: {value.get('hostname') or value['mac']}",
            "router_id": value["router_id"],
            "device_id": device_id,
        }
    )
    return value


@router.get("")
def list_devices(
    db: Annotated[ControlDatabase, Depends(control_db)],
    router_id: str | None = None,
    online: bool | None = None,
    group_id: str | None = None,
    q: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    items, total = db.list_devices(
        router_id=router_id,
        online=online,
        group_id=group_id,
        query=q,
        limit=limit,
        offset=offset,
    )
    return {"items": items, "total": total}


@router.get("/{device_id}")
def get_device(
    device_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    return _get(db, device_id)


@router.patch("/{device_id}")
def update_device(
    device_id: str,
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if "display_name" in payload:
        value = payload["display_name"]
        if not isinstance(value, str):
            raise HTTPException(422, "display_name must be a string")
        payload["display_name"] = value.strip()[:80]
    before = _get(db, device_id)
    updated = db.update_device(device_id, payload)
    if updated is None:
        raise HTTPException(404, "device not found")
    if "display_name" in payload and before.get("display_name") != updated.get(
        "display_name"
    ):
        db.create_event(
            {
                "type": "device_renamed",
                "severity": "info",
                "message": f"renamed device: {before.get('hostname') or before['mac']} -> {updated.get('display_name') or updated.get('hostname') or updated['mac']}",
                "router_id": updated["router_id"],
                "device_id": device_id,
            }
        )
    return updated


@router.get("/{device_id}/traffic")
def device_traffic(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    device = _get(db, device_id)
    source = _source(request, db, device)
    try:
        details = source.device_details(device["mac"], 24)
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error
    daily = details.get("ranges", {}).get("1d", {})
    return {
        "router_id": device["router_id"],
        "device_id": device_id,
        "period": "day",
        "rx_bytes": daily.get("download", 0),
        "tx_bytes": daily.get("upload", 0),
        "samples": details.get("series", []),
    }


@router.get("/{device_id}/details")
def device_details(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
    hours: int = Query(24, ge=1, le=168),
):
    device = _get(db, device_id)
    router = db.get_router(device["router_id"])
    if router is None:
        raise HTTPException(404, "router not found")
    source = getattr(request.app.state, "router_data", None)
    if source is None:
        source = RouterData(
            router["address"], ssh_key=os.getenv("OPENWALLA_ROUTER_SSH_KEY")
        )
    try:
        return source.device_details(device["mac"], hours)
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


@router.post("/{device_id}/pause")
def pause_device(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
    payload: Annotated[dict[str, Any] | None, Body()] = None,
):
    device = _get(db, device_id)
    minutes = 30
    if payload and payload.get("duration_minutes") is not None:
        try:
            minutes = int(payload["duration_minutes"])
        except (TypeError, ValueError) as error:
            raise HTTPException(422, "duration_minutes must be an integer") from error
    minutes = max(1, min(minutes, 10080))
    source = _source(request, db, device)
    try:
        if not (device.get("blocked") or device.get("paused")):
            source.apply_device_access(
                device["mac"], True, uuid.uuid4().hex
            )
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Device pause failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error
    value = db.set_device_state(
        device_id,
        paused=True,
        pause_until=int(time.time()) + minutes * 60,
    )
    if value is None:
        raise HTTPException(404, "device not found")
    db.create_event(
        {
            "type": "device_paused",
            "severity": "info",
            "message": f"device paused for {minutes}m: {value.get('hostname') or value['mac']}",
            "router_id": value["router_id"],
            "device_id": device_id,
        }
    )
    return value


@router.post("/{device_id}/resume")
def resume_device(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    device = _get(db, device_id)
    source = _source(request, db, device)
    try:
        if not device.get("blocked"):
            source.apply_device_access(
                device["mac"], False, uuid.uuid4().hex
            )
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Device resume failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error
    value = db.set_device_state(
        device_id, paused=False, pause_until=0
    )
    if value is None:
        raise HTTPException(404, "device not found")
    db.create_event(
        {
            "type": "device_resumed",
            "severity": "info",
            "message": f"device resumed: {value.get('hostname') or value['mac']}",
            "router_id": value["router_id"],
            "device_id": device_id,
        }
    )
    return value


@router.post("/{device_id}/block")
def block_device(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
    payload: Annotated[dict[str, Any] | None, Body()] = None,
):
    return _action(
        request,
        db,
        device_id,
        blocked=True,
        event_type="device_blocked",
    )


@router.post("/{device_id}/unblock")
def unblock_device(
    device_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    return _action(
        request,
        db,
        device_id,
        blocked=False,
        event_type="device_unblocked",
    )
