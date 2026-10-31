from __future__ import annotations

import asyncio
import json
import time

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import StreamingResponse

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


@router.get("/live")
async def traffic_live(
    request: Request,
    hours: int = Query(1, ge=1, le=168),
    bucket: int = Query(60, ge=60, le=3600),
):
    flow_db = getattr(request.app.state, "flow_db", None)

    async def events():
        while True:
            if await request.is_disconnected():
                return
            items = (
                flow_db.traffic_series(hours, bucket)
                if flow_db is not None
                else []
            )
            payload = {
                "items": items,
                "latest": items[-1] if items else None,
                "timestamp": int(time.time()),
            }
            yield f"data: {json.dumps(payload)}\n\n"
            await asyncio.sleep(5)

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
