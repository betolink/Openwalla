"""Strict per-device ASN filtering for OpenWrt.

DNS filtering is best effort: an app can reuse a cached answer, connect to a
hard-coded address, or use a CDN name that is not in a blocklist. Strict mode
adds a packet-level nftables rule for the target device and every announced
prefix of the app's ASN(s). The ruleset is loaded through fw4's
``/etc/nftables.d/*.nft`` include and therefore survives firewall reloads.

ASN data is fetched from IPinfo's free ASN prefix endpoint and cached on the
control-plane data volume. The router never needs outbound access for this.
"""

from __future__ import annotations

import ipaddress
import json
import logging
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from .adguard_sync import _rule_active, _target_devices
from .control_db import ControlDatabase
from .filtering_catalog import asns_for

DEFAULT_TIMEZONE = "America/Chicago"
ASN_CACHE_TTL = 24 * 60 * 60
ASN_CACHE_DIR = Path(
    os.getenv("OPENWALLA_ASN_CACHE_DIR", "/data/asn-cache")
)
ASN_PREFIX_URL = "https://asn.ipinfo.app/api/text/list/AS{asn}"
NFT_INCLUDE_PATH = "/etc/nftables.d/90-openwalla-app-filter.nft"


class ASNFilterError(RuntimeError):
    pass


def _cache_file(asn: int) -> Path:
    return ASN_CACHE_DIR / f"AS{asn}.json"


def _read_cache(asn: int) -> dict[str, Any] | None:
    path = _cache_file(asn)
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not isinstance(data.get("prefixes"), list):
        return None
    return data


def _write_cache(asn: int, prefixes: list[str]) -> None:
    try:
        ASN_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path = _cache_file(asn)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "asn": asn,
                    "updated_at": int(time.time()),
                    "prefixes": prefixes,
                },
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        temporary.replace(path)
    except OSError:
        logging.exception("Unable to cache ASN prefixes for AS%s", asn)


def _normalize_prefixes(values: list[str]) -> list[str]:
    networks: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    for value in values:
        text = value.strip()
        if not text or text.startswith("#"):
            continue
        try:
            networks.append(ipaddress.ip_network(text, strict=False))
        except ValueError:
            continue
    result: list[str] = []
    for version in (4, 6):
        family = [network for network in networks if network.version == version]
        if family:
            result.extend(
                str(network) for network in ipaddress.collapse_addresses(family)
            )
    return result


def fetch_asn_prefixes(asn: int, *, max_age: int = ASN_CACHE_TTL) -> list[str]:
    """Return announced IPv4/IPv6 prefixes for an ASN, using a local cache."""
    cached = _read_cache(asn)
    if cached is not None:
        updated = int(cached.get("updated_at") or 0)
        prefixes = [str(value) for value in cached.get("prefixes") or []]
        if prefixes and int(time.time()) - updated <= max_age:
            return prefixes

    url = ASN_PREFIX_URL.format(asn=asn)
    try:
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "OpenWalla/1.0 ASN prefix refresh"},
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            body = response.read().decode("utf-8", errors="replace")
        prefixes = _normalize_prefixes(body.splitlines())
        if not prefixes:
            raise ASNFilterError(f"AS{asn} returned no prefixes")
        _write_cache(asn, prefixes)
        return prefixes
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        if cached is not None:
            logging.warning(
                "ASN prefix refresh failed for AS%s; using cached data: %s",
                asn,
                error,
            )
            return [str(value) for value in cached.get("prefixes") or []]
        raise ASNFilterError(f"unable to fetch AS{asn} prefixes: {error}") from error


def desired_strict_rules(
    database: ControlDatabase,
    timezone: str = DEFAULT_TIMEZONE,
) -> list[dict[str, Any]]:
    """Resolve active strict rules into ``{mac, asns}`` entries."""
    devices, _ = database.list_devices(limit=10000)
    groups = database.list_groups()
    entries: dict[str, set[int]] = {}
    for rule in database.list_filtering_rules():
        if str(rule.get("mode") or "dns") != "asn":
            continue
        if str(rule.get("action") or "block") != "block":
            continue
        if not _rule_active(rule, timezone):
            continue
        kind = str(rule.get("kind") or "service")
        if kind not in {"service", "category"}:
            continue
        asns = asns_for(kind, str(rule.get("value") or ""))
        if not asns:
            continue
        for device in _target_devices(rule, devices, groups):
            mac = str(device.get("mac") or "").strip().lower()
            if mac:
                entries.setdefault(mac, set()).update(asns)
    return [
        {"mac": mac, "asns": sorted(asns)}
        for mac, asns in sorted(entries.items())
    ]


def _set_name(asn: int, family: int) -> str:
    return f"openwalla_asn_{asn}_v{family}"


def build_nft_ruleset(
    entries: list[dict[str, Any]],
    prefixes_by_asn: dict[int, list[str]],
) -> str:
    """Build an fw4 include fragment for the active strict rules."""
    if not entries:
        return ""

    by_asn: dict[int, dict[int, list[str]]] = {}
    for asn, prefixes in prefixes_by_asn.items():
        families: dict[int, list[str]] = {4: [], 6: []}
        for value in prefixes:
            try:
                network = ipaddress.ip_network(value, strict=False)
            except ValueError:
                continue
            families[network.version].append(str(network))
        for family in (4, 6):
            if families[family]:
                collapsed = ipaddress.collapse_addresses(
                    ipaddress.ip_network(value)
                    for value in families[family]
                )
                families[family] = [str(network) for network in collapsed]
        by_asn[int(asn)] = families

    lines = [
        "# Managed by OpenWalla. Do not edit by hand.",
        "# Strict per-device ASN blocking; regenerated by the control plane.",
        "",
    ]
    for asn in sorted(by_asn):
        for family in (4, 6):
            values = by_asn[asn][family]
            if not values:
                continue
            name = _set_name(asn, family)
            address_type = "ipv4_addr" if family == 4 else "ipv6_addr"
            lines.extend(
                [
                    f"set {name} {{",
                    f"\ttype {address_type}",
                    "\tflags interval",
                    "\tauto-merge",
                    "\telements = {",
                ]
            )
            lines.extend(f"\t\t{value}," for value in values)
            lines.extend(["\t}", "}", ""])

    lines.extend(
        [
            "chain openwalla_app_filter {",
            "\ttype filter hook forward priority -5; policy accept;",
        ]
    )
    for entry in entries:
        mac = str(entry.get("mac") or "").strip().lower()
        if not mac:
            continue
        for asn in sorted({int(value) for value in entry.get("asns") or []}):
            families = by_asn.get(asn, {})
            for family in (4, 6):
                if not families.get(family):
                    continue
                protocol = "ip" if family == 4 else "ip6"
                lines.append(
                    f'\tether saddr {mac} {protocol} daddr '
                    f'@{_set_name(asn, family)} counter drop '
                    f'comment "openwalla AS{asn}"'
                )
    lines.extend(["}", ""])
    return "\n".join(lines)


def sync_app_filter(
    database: ControlDatabase,
    router: Any,
    timezone: str = DEFAULT_TIMEZONE,
) -> dict[str, Any]:
    """Reconcile the strict ASN ruleset onto the router."""
    entries = desired_strict_rules(database, timezone)
    asns = sorted({int(asn) for entry in entries for asn in entry["asns"]})
    if not entries:
        result = router.apply_app_filter("")
        return {"devices": 0, "asns": [], "status": result}

    prefixes = {asn: fetch_asn_prefixes(asn) for asn in asns}
    ruleset = build_nft_ruleset(entries, prefixes)
    if not ruleset:
        raise ASNFilterError("strict rules produced an empty ASN ruleset")
    result = router.apply_app_filter(ruleset)
    return {
        "devices": len(entries),
        "asns": asns,
        "status": result,
    }


__all__ = [
    "ASNFilterError",
    "build_nft_ruleset",
    "desired_strict_rules",
    "fetch_asn_prefixes",
    "sync_app_filter",
]
