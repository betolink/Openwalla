from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from fastapi.responses import JSONResponse

from ..auth import SESSION_COOKIE
from ..deps import require_auth

router = APIRouter(prefix="/auth", tags=["Auth"])


def _user(request: Request) -> dict[str, Any]:
    settings = request.app.state.settings
    return {
        "id": "admin",
        "username": getattr(settings, "ui_username", "admin"),
        "role": "admin",
    }


@router.post("/login")
def login(
    request: Request,
    payload: Annotated[dict[str, Any], Body()],
):
    authentication = request.app.state.authentication
    settings = request.app.state.settings
    if not authentication.enabled:
        return {"user": _user(request), "expires_at": None}
    result = authentication.login(
        authentication.client_ip(request),
        str(payload.get("username", "")),
        str(payload.get("password", "")),
    )
    if not result.accepted:
        raise HTTPException(401, "invalid credentials")
    session = authentication.create_session()
    response = JSONResponse({"user": _user(request), "expires_at": None})
    response.set_cookie(
        SESSION_COOKIE,
        session,
        max_age=int(getattr(settings, "session_hours", 24)) * 3600,
        httponly=True,
        secure=bool(getattr(settings, "auth_secure_cookie", False)),
        samesite="strict",
        path="/",
    )
    return response


@router.post("/logout", status_code=204)
def logout():
    response = JSONResponse(None, status_code=204)
    response.delete_cookie(SESSION_COOKIE, path="/")
    return response


@router.get("/me")
def me(request: Request, _: Annotated[None, Depends(require_auth)] = None):
    return _user(request)
