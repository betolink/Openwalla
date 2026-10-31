from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..router_client import RouterClient, RouterError

router = APIRouter(
    prefix="/routers", tags=["Routers"], dependencies=[Depends(require_auth)]
)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def public_router(value: dict[str, Any]) -> dict[str, Any]:
    result = {
        key: item
        for key, item in value.items()
        if key not in ("username", "password")
    }
    result["has_credentials"] = bool(
        value.get("username") or value.get("password")
    )
    return result


def _factory(request, router_value: dict[str, Any]):
    factory = getattr(request.app.state, "router_client_factory", None)
    if factory is not None:
        return factory(router_value)
    return RouterClient(
        router_value["address"],
        router_value.get("username", ""),
        router_value.get("password", ""),
        port=int(router_value.get("port", 80)),
        scheme=router_value.get("scheme", "http"),
        verify_tls=bool(router_value.get("verify_tls", True)),
    )


@router.get("")
def list_routers(db: Annotated[ControlDatabase, Depends(control_db)]):
    items = [public_router(value) for value in db.list_routers()]
    return {"items": items, "total": len(items)}


@router.post("", status_code=201)
def create_router(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name") or not payload.get("address"):
        raise HTTPException(400, "name and address are required")
    return public_router(db.create_router(payload))


@router.get("/{router_id}")
def get_router(
    router_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    value = db.get_router(router_id)
    if value is None:
        raise HTTPException(404, "router not found")
    return public_router(value)


@router.patch("/{router_id}")
def update_router(
    router_id: str,
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    value = db.update_router(router_id, payload)
    if value is None:
        raise HTTPException(404, "router not found")
    return public_router(value)


@router.delete("/{router_id}", status_code=204)
def delete_router(
    router_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    if not db.delete_router(router_id):
        raise HTTPException(404, "router not found")


@router.post("/{router_id}/sync")
def sync_router(
    router_id: str,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    value = db.get_router(router_id)
    if value is None:
        raise HTTPException(404, "router not found")
    client = _factory(request, value)
    try:
        client.login()
        board = client.fetch_board()
        devices = client.fetch_devices()
        interfaces = client.fetch_interfaces()
    except RouterError as error:
        db.update_router(router_id, {"status": "offline", "last_seen": _now()})
        raise HTTPException(502, str(error)) from error
    db.upsert_devices(router_id, devices)
    db.upsert_interfaces(router_id, interfaces)
    updated = db.update_router(
        router_id,
        {
            "status": "online",
            "last_seen": _now(),
            "model": str(board.get("model") or ""),
            "openwrt_version": str(
                (board.get("release") or {}).get("description")
                or board.get("system")
                or ""
            ),
        },
    )
    return {
        "router": public_router(updated or value),
        "devices": len(devices),
        "interfaces": len(interfaces),
    }
