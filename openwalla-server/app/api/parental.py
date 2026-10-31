from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth

router = APIRouter(
    prefix="/parental",
    tags=["Parental"],
    dependencies=[Depends(require_auth)],
)


@router.get("/profiles")
def list_profiles(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_parental()}


@router.post("/profiles", status_code=201)
def create_profile(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    return db.create_parental(payload)


@router.put("/profiles/{profile_id}")
def update_profile(
    profile_id: str,
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    value = db.update_parental(profile_id, payload)
    if value is None:
        raise HTTPException(404, "profile not found")
    return value


@router.delete("/profiles/{profile_id}", status_code=204)
def delete_profile(
    profile_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    if not db.delete_parental(profile_id):
        raise HTTPException(404, "profile not found")
