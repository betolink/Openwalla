"""Read per-device analytics from the router's OpenWalla SQLite databases.

The control-plane API runs on the homelab and reaches betowrt over the LAN.
SSH is used only for these read-only analytics queries; enforcement will go
through the agent later. The databases live under /tmp/openwalla (tmpfs) on the
router.
"""

from __future__ import annotations

import ipaddress
import json
import os
import shutil
import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

BANDWIDTH_DB = "/overlay/openwalla/openwalla-device-bandwidth.sqlite"
NETIFY_DB = "/overlay/openwalla/openwalla-netify.sqlite"
DEVICES_DB = "/tmp/openwalla/openwalla-devices.sqlite"
SPEEDTEST_FILE = "/overlay/openwalla/openwalla-speedtest-monitor.txt"


class RouterDataError(RuntimeError):
    pass


@dataclass(frozen=True)
class RouterData:
    host: str
    ssh_user: str = "root"
    ssh_key: str | None = None
    timeout: float = 8.0

    def _run(self, remote: str, timeout: float | None = None) -> str:
        command = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            "UserKnownHostsFile=/tmp/openwalla_known_hosts",
        ]
        ssh_key = self._usable_key()
        if ssh_key:
            command += ["-i", ssh_key]
        command += [f"{self.ssh_user}@{self.host}", remote]
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout or self.timeout,
            )
        except subprocess.TimeoutExpired as error:
            raise RouterDataError("router query timed out") from error
        if result.returncode != 0:
            raise RouterDataError(
                result.stderr.strip() or "router query failed"
            )
        return result.stdout

    def _usable_key(self) -> str | None:
        """Docker secrets are 0444; OpenSSH requires a private 0600 key."""
        if not self.ssh_key:
            return None
        source = Path(self.ssh_key)
        try:
            mode = source.stat().st_mode & 0o777
        except OSError:
            return self.ssh_key
        if mode & 0o077 == 0:
            return self.ssh_key
        target = Path("/tmp") / f"openwalla-ssh-{os.getuid()}-{source.name}"
        try:
            if (
                not target.exists()
                or target.stat().st_mtime < source.stat().st_mtime
            ):
                shutil.copyfile(source, target)
                os.chmod(target, 0o600)
        except OSError:
            return self.ssh_key
        return str(target)

    def _query(self, database: str, sql: str) -> list[dict[str, Any]]:
        remote = (
            f"sqlite3 -json {shlex.quote(database)} {shlex.quote(sql)}"
        )
        raw = self._run(remote).strip()
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

    @staticmethod
    def _parse_uci(lines: list[str]) -> dict[str, str]:
        values: dict[str, str] = {}
        for line in lines:
            key, separator, raw = line.partition("=")
            if not separator:
                continue
            values[key.strip()] = raw.strip().strip("'\"")
        return values

    @staticmethod
    def _parse_speedtests(lines: list[str]) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        for line in lines:
            parts = line.split("|")
            if len(parts) < 6:
                continue
            timestamp, status, download, upload, server, message = parts[:6]

            def number(value: str) -> float | None:
                try:
                    return float(value)
                except ValueError:
                    return None

            items.append(
                {
                    "timestamp": timestamp,
                    "status": status,
                    "download": number(download),
                    "upload": number(upload),
                    "server": server,
                    "message": message,
                }
            )
        items.reverse()
        return items

    def speedtests(self, limit: int = 20) -> list[dict[str, Any]]:
        limit = max(1, min(int(limit), 100))
        raw = self._run(
            f"tail -n {limit} {shlex.quote(SPEEDTEST_FILE)} 2>/dev/null"
        )
        return self._parse_speedtests(raw.splitlines())

    def network_status(self) -> dict[str, Any]:
        remote = (
            "echo '###SQM'; uci -q show sqm 2>/dev/null; "
            "echo '###BANIP'; uci -q show banip 2>/dev/null; "
            "echo '###BANIP_STATUS'; /etc/init.d/banip status 2>/dev/null | head -20; "
            f"echo '###SPEED'; tail -n 20 {shlex.quote(SPEEDTEST_FILE)} 2>/dev/null; "
            "echo '###QDISC'; tc qdisc show dev eth1 2>/dev/null"
        )
        raw = self._run(remote, timeout=20)
        sections: dict[str, list[str]] = {}
        current = ""
        for line in raw.splitlines():
            if line.startswith("###"):
                current = line[3:].strip()
                sections[current] = []
            elif current:
                sections[current].append(line)

        sqm = self._parse_uci(sections.get("SQM", []))
        banip = self._parse_uci(sections.get("BANIP", []))
        status_lines = sections.get("BANIP_STATUS", [])

        def first_option(suffix: str, default: str = "") -> str:
            for key, value in sqm.items():
                if key.endswith(f".{suffix}"):
                    return value
            return default

        def first_banip_option(suffix: str, default: str = "") -> str:
            for key, value in banip.items():
                if key.endswith(f".{suffix}"):
                    return value
            return default

        def status_value(label: str) -> str:
            for line in status_lines:
                if label in line and ":" in line:
                    return line.split(":", 1)[1].strip()
            return ""

        status_line = status_value("status")
        element_text = status_value("element_count").split("(", 1)[0]
        elements = "".join(ch for ch in element_text if ch.isdigit())
        active_feed_text = status_value("active_feeds")
        active_feeds = [
            value.strip()
            for value in active_feed_text.split(",")
            if value.strip() and value.strip() != "-"
        ]
        countries = [
            value.lower()
            for value in first_banip_option("ban_country").replace(",", " ").split()
            if value.strip()
        ]

        return {
            "sqm": {
                "enabled": any(
                    key.endswith(".enabled") and value == "1"
                    for key, value in sqm.items()
                ),
                "interface": first_option("interface"),
                "download_kbit": int(first_option("download", "0") or 0),
                "upload_kbit": int(first_option("upload", "0") or 0),
                "qdisc": first_option("qdisc"),
                "script": first_option("script"),
                "qdiscs": sections.get("QDISC", []),
            },
            "banip": {
                "enabled": first_banip_option("ban_enabled") == "1",
                "active": "active" in status_line,
                "status": status_line,
                "element_count": int(elements or 0),
                "feeds": [
                    value
                    for value in first_banip_option("ban_feed").split()
                    if value
                ],
                "active_feeds": active_feeds,
                "last_run": status_value("last_run"),
            },
            "geoip": {
                "countries": countries,
                "enabled": "country" in first_banip_option("ban_feed").split(),
            },
            "speedtests": self._parse_speedtests(
                sections.get("SPEED", [])
            ),
        }

    def run_speedtest(self) -> dict[str, Any]:
        self._run(
            "/usr/bin/openwalla-speedtest-monitor --once",
            timeout=150,
        )
        results = self.speedtests(1)
        return results[0] if results else {}

    def clear_conntrack(self, address: str) -> dict[str, Any]:
        remote = (
            f"conntrack -D -f ipv4 -s {shlex.quote(address)} >/dev/null 2>&1 || true; "
            f"conntrack -D -f ipv4 -d {shlex.quote(address)} >/dev/null 2>&1 || true"
        )
        self._run(remote, timeout=15)
        return {"address": address}

    def apply_device_access(
        self, mac: str, blocked: bool, operation: str
    ) -> dict[str, Any]:
        action = "block" if blocked else "release"
        reason = "manual" if blocked else "current"
        remote = (
            ". /usr/lib/openwalla/device-access.sh; "
            f"openwalla_device_access {action} {reason} "
            f"{shlex.quote(mac)} {shlex.quote(operation)}"
        )
        output = self._run(remote, timeout=60)
        expected = f"OPENWALLA_DEVICE_ACCESS_OK|{action}|"
        if expected not in output:
            raise RouterDataError(output.strip() or "device access apply failed")
        return {"mac": mac, "blocked": blocked, "output": output.strip()}

    def adblock_status(self) -> dict[str, Any]:
        raw = self._run(
            "/etc/init.d/adblock status 2>/dev/null; "
            "echo '###UCI'; uci -q show adblock 2>/dev/null",
            timeout=20,
        )
        sections: dict[str, list[str]] = {}
        current = ""
        for line in raw.splitlines():
            if line.startswith("###"):
                current = line[3:].strip()
                sections[current] = []
            elif current:
                sections[current].append(line)

        values = self._parse_uci(sections.get("UCI", []))
        enabled = values.get("adblock.global.adb_enabled", "0") == "1"
        raw_feeds = values.get("adblock.global.adb_feed", "")
        feeds = [
            value.strip("'\"")
            for value in raw_feeds.replace("'", " ").replace('"', " ").split()
            if value.strip("'\"")
        ]
        status_text = "\n".join(sections.get("", [])) if "" in sections else ""
        # The status output precedes the ### marker.
        status_text = "\n".join(
            line for line in raw.splitlines() if not line.startswith("###")
        )
        blocked_domains = 0
        last_updated = ""
        for line in status_text.splitlines():
            if "blocked_domains" in line and ":" in line:
                digits = "".join(ch for ch in line.split(":", 1)[1] if ch.isdigit())
                blocked_domains = int(digits or 0)
            if "last_run" in line and "date / time:" in line:
                last_updated = line.split("date / time:", 1)[1].strip()
        return {
            "enabled": enabled,
            "blocklists": feeds,
            "total_queries": 0,
            "blocked_queries": blocked_domains,
            "blocked_domains": blocked_domains,
            "block_percent": 0,
            "update_interval_hours": 24,
            "last_updated": last_updated,
            "active_feeds": feeds,
        }

    def set_adblock(
        self, enabled: bool, blocklists: list[str]
    ) -> dict[str, Any]:
        current = self.adblock_status()
        feeds = [
            "".join(ch for ch in value.lower() if ch.isalnum() or ch in "_-")
            for value in blocklists
            if value.strip()
        ]
        feeds = [value for value in feeds if value]
        if not feeds:
            feeds = current.get("blocklists") or []
        commands = [
            f"uci set adblock.global.adb_enabled={'1' if enabled else '0'}",
            "uci -q delete adblock.global.adb_feed",
        ]
        commands.extend(
            f"uci add_list adblock.global.adb_feed={shlex.quote(feed)}"
            for feed in feeds
        )
        commands.extend(
            [
                "uci commit adblock",
                "/etc/init.d/adblock restart >/dev/null 2>&1 || true",
            ]
        )
        self._run("; ".join(commands), timeout=180)
        return self.adblock_status()

    def sync_parental(
        self,
        profile_id: str,
        name: str,
        enabled: bool,
        paused: bool,
        pause_until: int,
        content_filter: str,
        custom_dns: str,
        daily_limit_minutes: int,
        active_days: str,
        block_time: str,
        resume_time: str,
        member_macs: list[str],
    ) -> dict[str, Any]:
        arguments = [
            "/usr/bin/openwalla-parental",
            "profile-save",
            profile_id,
            name,
            "",
            "",
            "1" if enabled else "0",
            "1" if paused else "0",
            str(int(pause_until or 0)),
            content_filter or "none",
            custom_dns or "",
            str(max(0, int(daily_limit_minutes or 0))),
            active_days or "",
            block_time or "",
            resume_time or "",
            *member_macs,
        ]
        remote = " ".join(shlex.quote(value) for value in arguments)
        output = self._run(remote, timeout=60)
        return {"profile_id": profile_id, "output": output.strip()}

    def delete_parental(self, profile_id: str) -> dict[str, Any]:
        remote = (
            f"/usr/bin/openwalla-parental profile-delete {shlex.quote(profile_id)}"
        )
        output = self._run(remote, timeout=60)
        return {"profile_id": profile_id, "output": output.strip()}

    def set_geoip_countries(self, countries: list[str]) -> dict[str, Any]:
        codes = " ".join(sorted({code.lower() for code in countries}))
        remote = f"""
        feeds="$(uci -q get banip.global.ban_feed)"
        if [ -z {shlex.quote(codes)} ]; then
          new=""
          for feed in $feeds; do
            [ "$feed" = "country" ] || new="$new $feed"
          done
          uci set banip.global.ban_feed="${{new# }}"
          uci -q delete banip.global.ban_country
        else
          case " $feeds " in
            *" country "*) ;;
            *) feeds="$feeds country" ;;
          esac
          uci set banip.global.ban_feed="$feeds"
          uci set banip.global.ban_country={shlex.quote(codes)}
          uci set banip.global.ban_countrysplit=0
        fi
        uci commit banip
        /etc/init.d/banip restart >/dev/null 2>&1 || true
        """
        self._run(remote, timeout=120)
        return self.network_status()["geoip"]

    def blocked_elements(
        self,
        search: str = "",
        feed: str = "",
        limit: int = 100,
        offset: int = 0,
    ) -> dict[str, Any]:
        limit = max(1, min(int(limit), 500))
        offset = max(0, int(offset))
        raw = self._run("nft -j list table inet banIP", timeout=20)
        try:
            payload = json.loads(raw)
        except ValueError as error:
            raise RouterDataError("invalid nft response") from error

        items: list[dict[str, Any]] = []
        feed_counts: dict[str, int] = {}
        for entry in payload.get("nftables", []):
            set_data = entry.get("set")
            if not set_data:
                continue
            name = set_data.get("name") or ""
            if not (name.endswith(".v4") or name.endswith(".v6")):
                continue
            feed_name = name.rsplit(".", 1)[0]
            if feed_name in {"allowlist", "blocklist"}:
                continue
            elements = set_data.get("elem") or []
            feed_counts[feed_name] = feed_counts.get(feed_name, 0) + len(elements)
            for element in elements:
                value = (element.get("elem") or {}).get("val")
                addresses: list[str] = []
                if isinstance(value, dict) and "prefix" in value:
                    prefix = value["prefix"]
                    addresses = [
                        f"{prefix.get('addr', '')}/{prefix.get('len', '')}"
                    ]
                elif isinstance(value, dict) and "range" in value:
                    start, end = value["range"]
                    try:
                        addresses = [
                            str(network)
                            for network in ipaddress.summarize_address_range(
                                ipaddress.ip_address(start),
                                ipaddress.ip_address(end),
                            )
                        ]
                    except ValueError:
                        addresses = [f"{start}-{end}"]
                elif isinstance(value, str):
                    addresses = [value]
                else:
                    continue
                counter = (element.get("elem") or {}).get("counter") or {}
                for address in addresses:
                    items.append(
                        {
                            "ip": address,
                            "feed": feed_name,
                            "family": "ipv6" if name.endswith(".v6") else "ipv4",
                            "packets": int(counter.get("packets", 0) or 0),
                            "bytes": int(counter.get("bytes", 0) or 0),
                        }
                    )

        needle = search.strip().lower()
        selected_feed = feed.strip().lower()
        if needle:
            items = [
                item
                for item in items
                if needle in item["ip"].lower() or needle in item["feed"].lower()
            ]
        if selected_feed:
            items = [item for item in items if item["feed"] == selected_feed]
        items.sort(key=lambda item: (item["feed"], item["ip"]))
        total = len(items)
        return {
            "items": items[offset : offset + limit],
            "total": total,
            "limit": limit,
            "offset": offset,
            "feeds": [
                {"name": value, "count": count}
                for value, count in sorted(feed_counts.items())
            ],
            "source": "external reputation feeds, not local heuristics",
        }

    def allowlist_ip(self, value: str) -> dict[str, Any]:
        remote = f"""
        value={shlex.quote(value)}
        file=/etc/banip/banip.allowlist
        changed=0
        if ! grep -qF "$value" "$file" 2>/dev/null; then
          printf '%-45s%s\\n' "$value" "# openwalla allowlist $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$file"
          changed=1
          /etc/init.d/banip restart >/dev/null 2>&1 || true
        fi
        echo "$changed"
        """
        changed = self._run(remote, timeout=120).strip().endswith("1")
        return {"ip": value, "allowed": True, "changed": changed}

