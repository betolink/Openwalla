"""Small AdGuard Home API client used for per-client parental filtering.

AdGuard Home is the DNS filtering engine on betowrt. The control plane only
uses its local API (basic auth); the AdGuard web UI is not exposed publicly.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request
from typing import Any

from .config import Settings


class AdGuardError(RuntimeError):
    pass


SAFE_SEARCH = {
    "enabled": True,
    "bing": True,
    "duckduckgo": True,
    "ecosia": True,
    "google": True,
    "pixabay": True,
    "yandex": True,
    "youtube": True,
}


class AdGuardClient:
    def __init__(
        self,
        base_url: str,
        username: str = "admin",
        password: str = "",
        timeout: float = 8.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password
        self.timeout = timeout

    @classmethod
    def from_settings(cls, settings: Settings) -> "AdGuardClient":
        password = settings.adguard_password
        if not password:
            path = os.getenv("OPENWALLA_ADGUARD_PASSWORD_FILE", "").strip()
            if path:
                try:
                    password = open(path, encoding="utf-8").read().rstrip("\r\n")
                except OSError:
                    password = ""
        return cls(
            settings.adguard_url,
            settings.adguard_username,
            password,
        )

    def _request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> Any:
        token = base64.b64encode(
            f"{self.username}:{self.password}".encode()
        ).decode()
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Basic {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            detail = error.read(300).decode("utf-8", errors="replace")
            raise AdGuardError(f"AdGuard {path}: {error.code} {detail}") from error
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            raise AdGuardError(f"AdGuard {path}: {error}") from error

    def status(self) -> dict[str, Any]:
        return self._request("GET", "/control/status") or {}

    def clients(self) -> list[dict[str, Any]]:
        payload = self._request("GET", "/control/clients") or {}
        return list(payload.get("clients") or [])

    def delete_client(self, name: str) -> None:
        try:
            self._request("POST", "/control/clients/delete", {"name": name})
        except AdGuardError as error:
            if "not found" not in str(error).lower():
                raise

    def upsert_client(
        self,
        name: str,
        ids: list[str],
        *,
        safe_search: bool,
        parental: bool,
        blocked_services: list[str] | None = None,
    ) -> None:
        existing = {client["name"] for client in self.clients()}
        payload = {
            "name": name,
            "ids": ids,
            "use_global_settings": False,
            "filtering_enabled": True,
            "safesearch_enabled": safe_search,
            "safe_search": SAFE_SEARCH if safe_search else {"enabled": False},
            "parental_enabled": parental,
            "use_global_blocked_services": False,
            "blocked_services": list(blocked_services or []),
        }
        if name in existing:
            self._request(
                "POST",
                "/control/clients/update",
                {"name": name, "data": payload},
            )
        else:
            self._request("POST", "/control/clients/add", payload)

    def sync_user_rules(self, rules: list[str]) -> bool:
        payload = self._request("GET", "/control/filtering/status") or {}
        current = list(payload.get("user_rules") or [])
        preserved = [
            rule for rule in current if "openwalla:" not in rule
        ]
        desired = preserved + list(rules)
        if desired == current:
            return False
        self._request(
            "POST",
            "/control/filtering/set_rules",
            {"rules": desired},
        )
        return True

    def clear_cache(self) -> None:
        # AdGuard requires a JSON body; an empty POST is rejected with 415.
        self._request("POST", "/control/cache_clear", {})

    def sync_profile(
        self,
        profile_id: str,
        devices: list[dict[str, Any]],
        content_filter: str,
    ) -> None:
        prefix = f"openwalla:{profile_id}:"
        for client in self.clients():
            if client.get("name", "").startswith(prefix):
                self.delete_client(client["name"])

        if content_filter not in {"safe", "adult"}:
            return
        for device in devices:
            name = f"{prefix}{device['mac']}"
            ids = [device["mac"]]
            if device.get("ipv4"):
                ids.append(device["ipv4"])
            self.upsert_client(
                name,
                ids,
                safe_search=True,
                parental=content_filter == "adult",
            )

    def remove_profile(self, profile_id: str) -> None:
        prefix = f"openwalla:{profile_id}:"
        for client in self.clients():
            if client.get("name", "").startswith(prefix):
                self.delete_client(client["name"])
