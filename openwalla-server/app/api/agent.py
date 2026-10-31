from __future__ import annotations

import hashlib
import secrets
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException

from ..control_db import ControlDatabase
from ..deps import control_db, require_agent

router = APIRouter(prefix="/agent", tags=["Agent"])


@router.post("/register", status_code=201)
def register(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    router_id = str(payload.get("router_id") or "")
    if not router_id or db.get_router(router_id) is None:
        raise HTTPException(404, "router not found")
    token = secrets.token_urlsafe(32)
    digest = hashlib.sha256(token.encode()).hexdigest()
    agent = db.create_agent(router_id, digest)
    return {
        "agent_id": agent["agent_id"],
        "token": token,
        "heartbeat_interval_seconds": 30,
    }


@router.post("/heartbeat", status_code=204)
def heartbeat(
    payload: Annotated[dict[str, Any], Body()],
    agent: Annotated[dict[str, Any], Depends(require_agent)],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    router_id = agent["router_id"]
    if db.get_router(router_id) is not None:
        db.update_router(
            router_id,
            {"status": payload.get("status", "online")},
        )
    return None


@router.get("/policies")
def policies(
    agent: Annotated[dict[str, Any], Depends(require_agent)],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    return {
        "router_id": agent["router_id"],
        "version": 1,
        "policies": db.list_policies(),
        "parental_profiles": db.list_parental(),
        "adblock": db.get_adblock(),
    }
