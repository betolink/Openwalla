"""Local, offline GeoIP lookup using a MaxMind-format MMDB.

DB-IP Lite (CC BY 4.0) and MaxMind GeoLite2 both work. No per-lookup network
request is made.
"""

from __future__ import annotations

import ipaddress
import os
from pathlib import Path
from typing import Any

try:  # optional at import time so the API still starts without the database
    import maxminddb
except ImportError:  # pragma: no cover - depends on the runtime image
    maxminddb = None  # type: ignore[assignment]


class GeoIPError(RuntimeError):
    pass


def default_database_path() -> Path:
    return Path(os.getenv("OPENWALLA_GEOIP_DB", "/data/geoip.mmdb"))


class GeoIPLookup:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or default_database_path()

    def lookup(self, address: str) -> dict[str, Any]:
        try:
            ipaddress.ip_address(address)
        except ValueError as error:
            raise ValueError("invalid IP address") from error
        if maxminddb is None:
            raise GeoIPError("maxminddb is not installed")
        if not self.path.is_file():
            raise GeoIPError(f"GeoIP database not found at {self.path}")
        try:
            with maxminddb.open_database(str(self.path)) as reader:
                record = reader.get(address) or {}
        except (OSError, ValueError) as error:
            raise GeoIPError(f"unable to read GeoIP database: {error}") from error

        country = record.get("country") or record.get("registered_country") or {}
        names = country.get("names") or {}
        return {
            "ip": address,
            "country_code": (country.get("iso_code") or "").upper(),
            "country": names.get("en") or "",
            "continent": (record.get("continent") or {}).get("code") or "",
        }
