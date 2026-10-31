"""Control-plane API (v1) built on top of openwalla-server."""

from fastapi import APIRouter

from . import adblock, agent, auth, devices, events, interfaces, parental, policies, routers

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(routers.router)
api_router.include_router(devices.router)
api_router.include_router(interfaces.router)
api_router.include_router(policies.router)
api_router.include_router(parental.router)
api_router.include_router(adblock.router)
api_router.include_router(events.router)
api_router.include_router(agent.router)
