from __future__ import annotations

import os
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/devices", tags=["Devices"], dependencies=[Depends(require_auth)]
)


def _get(db: ControlDatabase, device_id: str) -> dict[str, Any]:
    value = db.get_device(device_id)
    if value is None:
        raise HTTPException(404, "device not found")
    return value


def _action(
    db: ControlDatabase,
    device_id: str,
    *,
    blocked: bool | None = None,
    paused: bool | None = None,
    event_type: str,
) -> dict[str, Any]:
    value = db.set_device_state(device_id, blocked=blocked, paused=paused)
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
    value = db.update_device(device_id, payload)
    if value is None:
        raise HTTPException(404, "device not found")
    return value


@router.get("/{device_id}/traffic")
def device_traffic(
    device_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    value = _get(db, device_id)
    return {
        "router_id": value["router_id"],
        "device_id": device_id,
        "period": "day",
        "rx_bytes": 0,
        "tx_bytes": 0,
        "samples": [],
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
    db: Annotated[ControlDatabase, Depends(control_db)],
    payload: Annotated[dict[str, Any] | None, Body()] = None,
):
    return _action(db, device_id, paused=True, event_type="device_paused")


@router.post("/{device_id}/resume")
def resume_device(
    device_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    return _action(db, device_id, paused=False, event_type="device_resumed")


@router.post("/{device_id}/block")
def block_device(
    device_id: str,
    db: Annotated[ControlDatabase, Depends(control_db)],
    payload: Annotated[dict[str, Any] | None, Body()] = None,
):
    return _action(db, device_id, blocked=True, event_type="device_blocked")


@router.post("/{device_id}/unblock")
def unblock_device(
    device_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    return _action(db, device_id, blocked=False, event_type="device_unblocked")
