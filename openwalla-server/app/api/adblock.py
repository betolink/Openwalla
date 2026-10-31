from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth

router = APIRouter(
    prefix="/adblock", tags=["Adblock"], dependencies=[Depends(require_auth)]
)


@router.get("/status")
def status(db: Annotated[ControlDatabase, Depends(control_db)]):
    value = db.get_adblock()
    total = int(value.get("total_queries", 0) or 0)
    blocked = int(value.get("blocked_queries", 0) or 0)
    value["block_percent"] = round((blocked / total) * 100, 2) if total else 0
    return value


@router.get("/settings")
def settings(db: Annotated[ControlDatabase, Depends(control_db)]):
    value = db.get_adblock()
    return {
        "enabled": value.get("enabled", False),
        "blocklists": value.get("blocklists", []),
        "update_interval_hours": value.get("update_interval_hours", 24),
    }


@router.put("/settings")
def update_settings(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    db.update_adblock(payload)
    return settings(db)
