from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth

router = APIRouter(tags=["Events"], dependencies=[Depends(require_auth)])


@router.get("/events")
def list_events(
    db: Annotated[ControlDatabase, Depends(control_db)],
    severity: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    items, total = db.list_events(severity=severity, limit=limit, offset=offset)
    return {"items": items, "total": total}


@router.get("/notifications")
def list_notifications(
    db: Annotated[ControlDatabase, Depends(control_db)],
    unread: bool | None = None,
):
    items = db.list_notifications(unread=unread)
    return {"items": items, "unread": sum(1 for item in items if not item["read"])}


@router.post("/notifications/{notification_id}/read", status_code=204)
def mark_read(
    notification_id: str,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    db.mark_notification_read(notification_id)
    return None
