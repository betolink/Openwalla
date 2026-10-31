from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request

from ..deps import require_auth

router = APIRouter(
    prefix="/traffic", tags=["Traffic"], dependencies=[Depends(require_auth)]
)


@router.get("/series")
def traffic_series(
    request: Request,
    hours: int = Query(24, ge=1, le=168),
    bucket: int = Query(300, ge=60, le=86400),
):
    flow_db = getattr(request.app.state, "flow_db", None)
    if flow_db is None:
        return {"items": []}
    return {"items": flow_db.traffic_series(hours, bucket)}
