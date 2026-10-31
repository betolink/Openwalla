"""Notification delivery for dashboard and operator alerts.

Channels are optional and configured through environment variables:

- OPENWALLA_NTFY_URL: full ntfy topic URL (for example https://ntfy.sh/openwalla)
- OPENWALLA_WEBHOOK_URL: generic JSON webhook

Every message is also stored in the control database, so the Events page can
show it even when no external channel is configured.
"""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any

from .control_db import ControlDatabase

LOGGER = logging.getLogger(__name__)


class Notifier:
    def __init__(
        self,
        database: ControlDatabase,
        ntfy_url: str | None = None,
        webhook_url: str | None = None,
        timeout: float = 5.0,
    ) -> None:
        self.database = database
        self.ntfy_url = (ntfy_url or os.getenv("OPENWALLA_NTFY_URL", "")).strip()
        self.webhook_url = (
            webhook_url or os.getenv("OPENWALLA_WEBHOOK_URL", "")
        ).strip()
        self.timeout = timeout

    def send(
        self,
        title: str,
        body: str = "",
        severity: str = "info",
        notification_type: str = "system",
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        notification = self.database.create_notification(
            {
                "type": notification_type,
                "title": title,
                "body": body,
                "data": {
                    "severity": severity,
                    **(data or {}),
                },
            }
        )
        channels: dict[str, str] = {}
        if self.ntfy_url:
            channels["ntfy"] = self._send_ntfy(title, body, severity)
        if self.webhook_url:
            channels["webhook"] = self._send_webhook(
                title, body, severity, notification_type, data or {}
            )
        return {"notification": notification, "channels": channels}

    def test(self) -> dict[str, Any]:
        return self.send(
            "OpenWalla test notification",
            "If you can read this, notification delivery is configured.",
            "info",
            "test",
        )

    def _send_ntfy(self, title: str, body: str, severity: str) -> str:
        priority = {"critical": "5", "warning": "4", "info": "3"}.get(
            severity, "3"
        )
        request = urllib.request.Request(
            self.ntfy_url,
            data=body.encode("utf-8"),
            method="POST",
            headers={
                "Title": title,
                "Priority": priority,
                "Tags": "shield",
            },
        )
        return self._execute(request)

    def _send_webhook(
        self,
        title: str,
        body: str,
        severity: str,
        notification_type: str,
        data: dict[str, Any],
    ) -> str:
        payload = json.dumps(
            {
                "title": title,
                "body": body,
                "severity": severity,
                "type": notification_type,
                "data": data,
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            self.webhook_url,
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        return self._execute(request)

    def _execute(self, request: urllib.request.Request) -> str:
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                response.read(256)
                return f"ok ({response.status})"
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            LOGGER.warning("Notification delivery failed: %s", error)
            return f"failed: {error}"


def send_best_effort(
    notifier: Notifier | None,
    title: str,
    body: str,
    severity: str = "warning",
    notification_type: str = "system",
) -> None:
    if notifier is None:
        return
    try:
        notifier.send(title, body, severity, notification_type)
    except Exception:
        LOGGER.exception("Unable to send notification")
