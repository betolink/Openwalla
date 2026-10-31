"""Minimal LuCI RPC client used by the control plane.

Matches what the mobile app does:
  1. POST /cgi-bin/luci/ (luci_username/luci_password) -> sysauth cookie
  2. POST /cgi-bin/luci/admin/ubus with JSON-RPC "call"
     params: [sysauth, object, method, params]
"""

from __future__ import annotations

import json
import ssl
from http.cookiejar import CookieJar
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import (
    HTTPCookieProcessor,
    HTTPSHandler,
    Request,
    build_opener,
)


class RouterError(RuntimeError):
    pass


class RouterAuthError(RouterError):
    pass


class RouterRpcError(RouterError):
    pass


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return [value]


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def normalize_devices(leases: Any, hints: Any) -> list[dict[str, Any]]:
    """Normalize luci-rpc getDHCPLeases/getHostHints into API device records."""
    by_mac: dict[str, dict[str, Any]] = {}

    for lease in _as_list(leases):
        lease = _as_dict(lease)
        mac = str(lease.get("macaddr") or lease.get("mac") or "").lower()
        if not mac:
            continue
        entry = by_mac.setdefault(
            mac,
            {
                "mac": mac,
                "ipv4": "",
                "ipv6": [],
                "hostname": "",
                "vendor": "",
                "connection": "unknown",
                "online": True,
            },
        )
        entry["ipv4"] = str(lease.get("ipaddr") or lease.get("ip") or entry["ipv4"])
        entry["hostname"] = str(lease.get("hostname") or entry["hostname"])
        entry["online"] = True

    for mac, hint in _as_dict(hints).items():
        mac = str(mac).lower()
        if not mac:
            continue
        hint = _as_dict(hint)
        entry = by_mac.setdefault(
            mac,
            {
                "mac": mac,
                "ipv4": "",
                "ipv6": [],
                "hostname": "",
                "vendor": "",
                "connection": "unknown",
                "online": True,
            },
        )
        if not entry["hostname"]:
            entry["hostname"] = str(hint.get("name") or "")
        ipv4 = hint.get("ipv4") or hint.get("ipaddrs") or []
        ipv6 = hint.get("ipv6") or []
        for address in _as_list(ipv4):
            address = str(address)
            if ":" not in address and not entry["ipv4"]:
                entry["ipv4"] = address
        for address in _as_list(ipv6):
            address = str(address)
            if ":" in address and address not in entry["ipv6"]:
                entry["ipv6"].append(address)
        for address in _as_list(hint.get("ipaddrs")):
            address = str(address)
            if ":" in address and address not in entry["ipv6"]:
                entry["ipv6"].append(address)

    return list(by_mac.values())


def normalize_interfaces(devices: Any) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for name, device in _as_dict(devices).items():
        device = _as_dict(device)
        stats = _as_dict(device.get("stats"))
        result.append(
            {
                "id": str(device.get("name") or name),
                "name": str(device.get("name") or name),
                "type": str(device.get("type") or ""),
                "up": bool(device.get("up", False)),
                "mac": str(device.get("macaddr") or ""),
                "addresses": _as_list(device.get("ipaddrs")),
                "rx_bytes": int(stats.get("rx_bytes", 0) or 0),
                "tx_bytes": int(stats.get("tx_bytes", 0) or 0),
                "errors": int(stats.get("rx_errors", 0) or 0)
                + int(stats.get("tx_errors", 0) or 0),
            }
        )
    return result


class RouterClient:
    def __init__(
        self,
        address: str,
        username: str,
        password: str,
        *,
        port: int = 80,
        scheme: str = "http",
        verify_tls: bool = True,
        timeout: float = 10.0,
    ) -> None:
        self.base_url = f"{scheme}://{address}:{port}".rstrip("/")
        self.username = username
        self.password = password
        self.verify_tls = verify_tls
        self.timeout = timeout
        self.jar = CookieJar()
        context = None
        if scheme == "https" and not verify_tls:
            context = ssl._create_unverified_context()
        self.opener = build_opener(
            HTTPCookieProcessor(self.jar),
            HTTPSHandler(context=context) if context else HTTPSHandler(),
        )
        self.sysauth: str | None = None

    # ------------------------------------------------------------------ http

    def _request(
        self,
        path: str,
        *,
        data: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> bytes:
        request = Request(
            self.base_url + path, data=data, headers=headers or {}
        )
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                return response.read()
        except HTTPError as error:
            raise RouterError(f"HTTP {error.code} from {path}") from error
        except URLError as error:
            raise RouterError(f"Unable to reach {path}: {error.reason}") from error

    def login(self) -> str:
        body = urlencode(
            {"luci_username": self.username, "luci_password": self.password}
        ).encode()
        self._request(
            "/cgi-bin/luci/",
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        for cookie in self.jar:
            if "sysauth" in cookie.name:
                self.sysauth = cookie.value
                break
        if not self.sysauth:
            raise RouterAuthError("LuCI login failed: no sysauth cookie")
        return self.sysauth

    def call(
        self, obj: str, method: str, params: dict[str, Any] | None = None
    ) -> Any:
        if not self.sysauth:
            self.login()
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "call",
            "params": [self.sysauth, obj, method, params or {}],
        }
        raw = self._request(
            "/cgi-bin/luci/admin/ubus",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        try:
            decoded = json.loads(raw)
        except ValueError as error:
            raise RouterRpcError("Invalid JSON from ubus") from error
        if decoded.get("error"):
            message = _as_dict(decoded["error"]).get("message", "RPC error")
            raise RouterRpcError(str(message))
        result = decoded.get("result")
        if not isinstance(result, list) or not result:
            raise RouterRpcError("Unexpected ubus result")
        if result[0] != 0:
            raise RouterRpcError(f"ubus status {result[0]}")
        return result[1] if len(result) > 1 else None

    # --------------------------------------------------------------- queries

    def fetch_board(self) -> dict[str, Any]:
        try:
            board = self.call("luci-rpc", "getBoardJSON")
            board = _as_dict(board)
            if board:
                return board
        except RouterRpcError:
            pass
        return _as_dict(self.call("system", "board"))

    def fetch_devices(self) -> list[dict[str, Any]]:
        leases = self.call("luci-rpc", "getDHCPLeases")
        hints = self.call("luci-rpc", "getHostHints")
        return normalize_devices(leases, hints)

    def fetch_interfaces(self) -> list[dict[str, Any]]:
        return normalize_interfaces(self.call("luci-rpc", "getNetworkDevices"))
