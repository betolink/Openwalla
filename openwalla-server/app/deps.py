"""Shared FastAPI dependencies for the control-plane API."""

from __future__ import annotations

import hashlib
import hmac
from typing import Annotated, Any

from fastapi import Header, HTTPException, Request

from .auth import SESSION_COOKIE
from .control_db import ControlDatabase


def _bearer(authorization: str | None) -> str:
    if not authorization:
        return ""
    scheme, _, token = authorization.partition(" ")
    return token.strip() if scheme.lower() == "bearer" else ""


def require_auth(
    request: Request, authorization: Annotated[str | None, Header()] = None
) -> None:
    settings = request.app.state.settings
    authentication = request.app.state.authentication
    if settings.api_token and hmac.compare_digest(
        authorization or "", f"Bearer {settings.api_token}"
    ):
        return
    if authentication.enabled and authentication.valid_session(
        request.cookies.get(SESSION_COOKIE)
    ):
        return
    if not settings.api_token and not authentication.enabled:
        return
    raise HTTPException(status_code=401, detail="Authentication required")


def control_db(request: Request) -> ControlDatabase:
    return request.app.state.control_db


def require_agent(
    request: Request, authorization: Annotated[str | None, Header()] = None
) -> dict[str, Any]:
    token = _bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Agent token required")
    digest = hashlib.sha256(token.encode()).hexdigest()
    agent = request.app.state.control_db.find_agent_by_token(digest)
    if agent is None:
        raise HTTPException(status_code=401, detail="Invalid agent token")
    return agent
