from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth

router = APIRouter(
    prefix="/interfaces", tags=["Interfaces"], dependencies=[Depends(require_auth)]
)


@router.get("")
def list_interfaces(
    db: Annotated[ControlDatabase, Depends(control_db)],
    router_id: str | None = None,
):
    return {"items": db.list_interfaces(router_id)}
