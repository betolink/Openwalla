from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException

from ..control_db import ControlDatabase
from ..deps import control_db, require_auth

router = APIRouter(tags=["Policies"], dependencies=[Depends(require_auth)])


@router.get("/policies")
def list_policies(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_policies()}


@router.post("/policies", status_code=201)
def create_policy(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    return db.create_policy(payload)


@router.put("/policies/{policy_id}")
def update_policy(
    policy_id: str,
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    value = db.update_policy(policy_id, payload)
    if value is None:
        raise HTTPException(404, "policy not found")
    return value


@router.delete("/policies/{policy_id}", status_code=204)
def delete_policy(
    policy_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    if not db.delete_policy(policy_id):
        raise HTTPException(404, "policy not found")


@router.get("/groups")
def list_groups(db: Annotated[ControlDatabase, Depends(control_db)]):
    return {"items": db.list_groups()}


@router.post("/groups", status_code=201)
def create_group(
    payload: Annotated[dict[str, Any], Body()],
    db: Annotated[ControlDatabase, Depends(control_db)],
):
    if not payload.get("name"):
        raise HTTPException(400, "name is required")
    return db.create_group(payload)


@router.delete("/groups/{group_id}", status_code=204)
def delete_group(
    group_id: str, db: Annotated[ControlDatabase, Depends(control_db)]
):
    if not db.delete_group(group_id):
        raise HTTPException(404, "group not found")
