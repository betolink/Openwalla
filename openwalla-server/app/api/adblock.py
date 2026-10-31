from __future__ import annotations

import os
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..notifier import send_best_effort
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/adblock", tags=["Adblock"], dependencies=[Depends(require_auth)]
)


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


@router.get("/status")
def status(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    try:
        return _source(request, db).adblock_status()
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


@router.get("/settings")
def settings(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    try:
        current = _source(request, db).adblock_status()
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error
    return {
        "enabled": current.get("enabled", False),
        "blocklists": current.get("blocklists", []),
        "update_interval_hours": current.get("update_interval_hours", 24),
    }


@router.put("/settings")
def update_settings(
    payload: Annotated[dict[str, Any], Body()],
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    enabled = bool(payload.get("enabled", False))
    blocklists = payload.get("blocklists", [])
    if not isinstance(blocklists, list) or any(
        not isinstance(value, str) for value in blocklists
    ):
        raise HTTPException(422, "blocklists must be a list of strings")
    try:
        applied = _source(request, db).set_adblock(enabled, blocklists)
    except RouterDataError as error:
        send_best_effort(
            getattr(request.app.state, "notifier", None),
            "Adblock enforcement failed",
            str(error),
            "warning",
            "enforcement",
        )
        raise HTTPException(502, str(error)) from error
    db.update_adblock(payload)
    return {
        "enabled": applied.get("enabled", False),
        "blocklists": applied.get("blocklists", []),
        "update_interval_hours": applied.get("update_interval_hours", 24),
    }
