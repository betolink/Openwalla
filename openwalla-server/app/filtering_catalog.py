"""Common AdGuard service identifiers exposed by the Filtering UI.

``asns`` powers strict, packet-level app blocking. Only map an ASN when it
actually belongs to the app/company: shared CDNs and parent-company ASNs have
collateral (for example Meta AS32934 also carries Facebook and WhatsApp).
"""

from __future__ import annotations

SERVICES = [
    {"id": "instagram", "name": "Instagram", "asns": [32934]},
    {"id": "facebook", "name": "Facebook", "asns": [32934]},
    {"id": "youtube", "name": "YouTube", "asns": [15169]},
    {"id": "tiktok", "name": "TikTok", "asns": [138699]},
    {"id": "snapchat", "name": "Snapchat"},
    {"id": "twitter", "name": "X / Twitter", "asns": [13414]},
    {"id": "discord", "name": "Discord"},
    {"id": "netflix", "name": "Netflix", "asns": [2906]},
    {"id": "twitch", "name": "Twitch", "asns": [46489]},
    {"id": "roblox", "name": "Roblox"},
    {"id": "minecraft", "name": "Minecraft", "asns": [8075]},
    {"id": "steam", "name": "Steam", "asns": [32590]},
    {"id": "epic_games", "name": "Epic Games"},
    {"id": "playstation", "name": "PlayStation", "asns": [33353]},
    {"id": "xboxlive", "name": "Xbox Live", "asns": [8075]},
    {"id": "nintendo", "name": "Nintendo"},
    {"id": "riot_games", "name": "Riot Games"},
]

CATEGORIES = {
    "games": {
        "name": "Games",
        "services": [
            "steam",
            "epic_games",
            "playstation",
            "xboxlive",
            "nintendo",
            "roblox",
            "minecraft",
            "riot_games",
        ],
        "asns": [32590, 33353, 8075],
    }
}

SERVICES_BY_ID = {item["id"]: item for item in SERVICES}
SERVICE_IDS = set(SERVICES_BY_ID)


def asns_for(kind: str, value: str) -> list[int]:
    """Return the ASNs that can enforce a service/category rule."""
    if kind == "service":
        return list(SERVICES_BY_ID.get(value, {}).get("asns") or [])
    if kind == "category":
        return list(CATEGORIES.get(value, {}).get("asns") or [])
    return []
