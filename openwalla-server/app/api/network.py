from __future__ import annotations

import ipaddress
import os
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth
from ..geoip import GeoIPError, GeoIPLookup
from ..notifier import Notifier
from ..router_data import RouterData, RouterDataError

router = APIRouter(
    prefix="/network", tags=["Network"], dependencies=[Depends(require_auth)]
)


def _first_router(db: ControlDatabase) -> dict[str, Any]:
    routers = db.list_routers()
    if not routers:
        raise HTTPException(404, "router not found")
    return routers[0]


def _source(request: Request, db: ControlDatabase) -> Any:
    source = getattr(request.app.state, "network_data", None)
    if source is not None:
        return source
    router_row = _first_router(db)
    return RouterData(
        router_row["address"],
        ssh_key=os.getenv("OPENWALLA_ROUTER_SSH_KEY"),
    )


@router.get("/status")
def network_status(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    try:
        return _source(request, db).network_status()
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


@router.get("/usage")
def network_usage(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    try:
        return _source(request, db).network_usage()
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


@router.post("/speedtest")
def run_speedtest(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    try:
        return _source(request, db).run_speedtest()
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


class GeoIPSettings(BaseModel):
    countries: list[str] = Field(default_factory=list, max_length=50)


@router.put("/geoip")
def set_geoip(
    settings: GeoIPSettings,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    countries = [code.lower() for code in settings.countries]
    if any(len(code) != 2 or not code.isalpha() for code in countries):
        raise HTTPException(422, "country codes must be two letters")
    try:
        return _source(request, db).set_geoip_countries(countries)
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


@router.get("/geoip/lookup")
def geoip_lookup(ip: str):
    try:
        return GeoIPLookup().lookup(ip)
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    except GeoIPError as error:
        raise HTTPException(503, str(error)) from error


@router.get("/blocked")
def blocked_elements(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
    search: str = "",
    feed: str = "",
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    try:
        return _source(request, db).blocked_elements(
            search=search, feed=feed, limit=limit, offset=offset
        )
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error


class AllowlistRequest(BaseModel):
    ip: str


@router.post("/blocked/allow")
def allow_blocked_ip(
    payload: AllowlistRequest,
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    value = payload.ip.strip()
    try:
        normalized = str(ipaddress.ip_address(value))
    except ValueError:
        try:
            normalized = str(ipaddress.ip_network(value, strict=False))
        except ValueError as error:
            raise HTTPException(422, "invalid IP address or CIDR") from error

    try:
        result = _source(request, db).allowlist_ip(normalized)
    except RouterDataError as error:
        raise HTTPException(502, str(error)) from error

    try:
        router_row = _first_router(db)
        db.create_event(
            {
                "type": "ip_allowlisted",
                "severity": "warning",
                "message": f"allowlisted {normalized}",
                "router_id": router_row["id"],
                "data": result,
            }
        )
    except Exception:
        pass
    return result


@router.get("/topology")
def topology(db: Annotated[ControlDatabase, Depends(control_db)]):
    router_row = _first_router(db)
    devices, total = db.list_devices(limit=1000)

    def is_infrastructure(device: dict[str, Any]) -> bool:
        text = " ".join(
            str(device.get(key) or "")
            for key in ("hostname", "vendor", "device_type")
        ).lower()
        return any(
            token in text
            for token in (
                "access point",
                "archer",
                "ax1500",
                "wac",
                "switch",
                "tl-sg",
            )
        )

    infrastructure = [device for device in devices if is_infrastructure(device)]
    wired = [device for device in devices if device["connection"] == "wired"]
    wireless = [device for device in devices if device["connection"] == "wireless"]
    unclassified = [
        device
        for device in devices
        if device["connection"] not in {"wired", "wireless"}
    ]

    return {
        "router": {
            "name": router_row["name"],
            "address": router_row["address"],
            "status": router_row["status"],
            "model": router_row.get("model") or "",
        },
        "wan": {"label": "WAN / ISP", "detail": "DHCP / CGNAT"},
        "lan": {"label": "LAN", "detail": "192.168.0.0/24"},
        "access_points": infrastructure,
        "wired": {"count": len(wired), "devices": wired[:25]},
        "wireless": {"count": len(wireless), "devices": wireless[:25]},
        "unclassified": {"count": len(unclassified), "devices": unclassified[:25]},
        "total_devices": total,
    }


@router.post("/notifications/test")
def test_notification(
    request: Request,
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    notifier = getattr(request.app.state, "notifier", None)
    if notifier is None:
        notifier = Notifier(db)
    return notifier.test()
