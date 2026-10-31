"""Read per-device analytics from the router's OpenWalla SQLite databases.

The control-plane API runs on the homelab and reaches betowrt over the LAN.
SSH is used only for these read-only analytics queries; enforcement will go
through the agent later. The databases live under /tmp/openwalla (tmpfs) on the
router.
"""

from __future__ import annotations

import json
import shlex
import subprocess
import time
from dataclasses import dataclass
from typing import Any

BANDWIDTH_DB = "/overlay/openwalla/openwalla-device-bandwidth.sqlite"
NETIFY_DB = "/overlay/openwalla/openwalla-netify.sqlite"
DEVICES_DB = "/tmp/openwalla/openwalla-devices.sqlite"


class RouterDataError(RuntimeError):
    pass


@dataclass(frozen=True)
class RouterData:
    host: str
    ssh_user: str = "root"
    ssh_key: str | None = None
    timeout: float = 8.0

    def _query(self, database: str, sql: str) -> list[dict[str, Any]]:
        remote = (
            f"sqlite3 -json {shlex.quote(database)} {shlex.quote(sql)}"
        )
        command = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
        ]
        if self.ssh_key:
            command += ["-i", self.ssh_key]
        command += [f"{self.ssh_user}@{self.host}", remote]
        try:
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=self.timeout
            )
        except subprocess.TimeoutExpired as error:
            raise RouterDataError("router query timed out") from error
        if result.returncode != 0:
            raise RouterDataError(
                result.stderr.strip() or "router query failed"
            )
        raw = result.stdout.strip()
        if not raw:
            return []
        try:
            return json.loads(raw)
        except ValueError as error:
            raise RouterDataError("invalid router response") from error

    def device_details(self, mac: str, hours: int = 24) -> dict[str, Any]:
        hours = max(1, min(int(hours), 168))
        now = int(time.time())
        mac_sql = mac.lower().replace("'", "")

        totals = self._query(
            BANDWIDTH_DB,
            f"""
            SELECT
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 3600}
                                THEN rx_bytes END), 0) AS download_1h,
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 3600}
                                THEN tx_bytes END), 0) AS upload_1h,
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 43200}
                                THEN rx_bytes END), 0) AS download_12h,
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 43200}
                                THEN tx_bytes END), 0) AS upload_12h,
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 86400}
                                THEN rx_bytes END), 0) AS download_24h,
              COALESCE(SUM(CASE WHEN bucket_start >= {now - 86400}
                                THEN tx_bytes END), 0) AS upload_24h,
              COALESCE(SUM(rx_bytes), 0) AS download_7d,
              COALESCE(SUM(tx_bytes), 0) AS upload_7d
            FROM device_bandwidth_15m
            WHERE mac = '{mac_sql}' AND bucket_start >= {now - 604800}
            """,
        )
        row = totals[0] if totals else {}
        ranges = {
            "1h": {
                "download": int(row.get("download_1h", 0)),
                "upload": int(row.get("upload_1h", 0)),
            },
            "12h": {
                "download": int(row.get("download_12h", 0)),
                "upload": int(row.get("upload_12h", 0)),
            },
            "1d": {
                "download": int(row.get("download_24h", 0)),
                "upload": int(row.get("upload_24h", 0)),
            },
            "7d": {
                "download": int(row.get("download_7d", 0)),
                "upload": int(row.get("upload_7d", 0)),
            },
        }

        series = self._query(
            BANDWIDTH_DB,
            f"""
            SELECT bucket_start AS timestamp,
                   SUM(rx_bytes) AS download,
                   SUM(tx_bytes) AS upload
            FROM device_bandwidth_15m
            WHERE mac = '{mac_sql}' AND bucket_start >= {now - hours * 3600}
            GROUP BY bucket_start
            ORDER BY bucket_start
            """,
        )

        websites = self._query(
            NETIFY_DB,
            f"""
            SELECT
              COALESCE(NULLIF(fqdn, ''),
                       NULLIF(host_server_name, ''),
                       NULLIF(client_sni, ''),
                       dest_ip) AS domain,
              detected_app_name AS app,
              detected_protocol_name AS protocol,
              COUNT(*) AS visits,
              MAX(timeinsert) AS last_seen
            FROM flow_raw
            WHERE local_mac = '{mac_sql}'
              AND timeinsert >= {now - hours * 3600}
            GROUP BY domain, app, protocol
            ORDER BY visits DESC
            LIMIT 25
            """,
        )

        info = self._query(
            DEVICES_DB,
            f"""
            SELECT vendor, status, total_up, total_down, last_seen, quarantined
            FROM devices WHERE mac = '{mac_sql}'
            """,
        )

        return {
            "mac": mac_sql,
            "hours": hours,
            "summary": info[0] if info else {},
            "ranges": ranges,
            "series": [
                {
                    "timestamp": int(item.get("timestamp", 0)),
                    "download": int(item.get("download", 0) or 0),
                    "upload": int(item.get("upload", 0) or 0),
                }
                for item in series
            ],
            "websites": [
                {
                    "domain": item.get("domain") or "",
                    "app": item.get("app") or "",
                    "protocol": item.get("protocol") or "",
                    "visits": int(item.get("visits", 0) or 0),
                    "last_seen": int(item.get("last_seen", 0) or 0),
                }
                for item in websites
            ],
        }
