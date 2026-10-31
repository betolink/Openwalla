"""Common AdGuard service identifiers exposed by the Filtering UI."""

from __future__ import annotations

SERVICES = [
    {"id": "instagram", "name": "Instagram"},
    {"id": "facebook", "name": "Facebook"},
    {"id": "youtube", "name": "YouTube"},
    {"id": "tiktok", "name": "TikTok"},
    {"id": "snapchat", "name": "Snapchat"},
    {"id": "twitter", "name": "X / Twitter"},
    {"id": "discord", "name": "Discord"},
    {"id": "netflix", "name": "Netflix"},
    {"id": "twitch", "name": "Twitch"},
    {"id": "roblox", "name": "Roblox"},
    {"id": "minecraft", "name": "Minecraft"},
    {"id": "steam", "name": "Steam"},
    {"id": "epic_games", "name": "Epic Games"},
    {"id": "playstation", "name": "PlayStation"},
    {"id": "xboxlive", "name": "Xbox Live"},
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
    }
}

SERVICE_IDS = {item["id"] for item in SERVICES}
