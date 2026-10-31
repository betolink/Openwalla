import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import api_router
from app.control_db import ControlDatabase
from app.deps import require_agent, require_auth


class FakeRouterClient:
    def login(self):
        return "token"

    def fetch_board(self):
        return {"model": "x86/64", "release": {"description": "OpenWrt 25.12.6"}}

    def fetch_devices(self):
        return [
            {
                "mac": "aa:bb:cc:dd:ee:01",
                "ipv4": "192.168.0.50",
                "ipv6": ["fe80::1"],
                "hostname": "phone",
                "vendor": "",
                "connection": "unknown",
                "online": True,
            }
        ]

    def fetch_interfaces(self):
        return [
            {
                "id": "br-lan",
                "name": "br-lan",
                "type": "bridge",
                "up": True,
                "mac": "00:11:22:33:44:55",
                "addresses": ["192.168.0.1"],
                "rx_bytes": 10,
                "tx_bytes": 20,
                "errors": 0,
            }
        ]


class FakeFlowDB:
    def traffic_series(self, hours: int, bucket: int):
        return [{"timestamp": 1, "flows": 3, "devices": 2}]


class FakeRouterData:
    def __init__(self):
        self.access_calls = []
        self.adblock = {
            "enabled": False,
            "blocklists": [],
            "total_queries": 0,
            "blocked_queries": 0,
            "block_percent": 0,
            "update_interval_hours": 24,
        }

    def apply_device_access(self, mac: str, blocked: bool, operation: str):
        self.access_calls.append((mac, blocked, operation))
        return {"mac": mac, "blocked": blocked}

    def adblock_status(self):
        return dict(self.adblock)

    def set_adblock(self, enabled: bool, blocklists: list[str]):
        self.adblock.update(
            {
                "enabled": enabled,
                "blocklists": list(blocklists),
            }
        )
        return dict(self.adblock)

    def device_details(self, mac: str, hours: int):
        return {
            "mac": mac,
            "hours": hours,
            "summary": {"vendor": "Acme", "status": "online"},
            "ranges": {
                "1h": {"download": 1000, "upload": 500},
                "12h": {"download": 2000, "upload": 1000},
                "1d": {"download": 3000, "upload": 1500},
                "7d": {"download": 4000, "upload": 2000},
            },
            "series": [
                {"timestamp": 1, "download": 1000, "upload": 500},
            ],
            "websites": [
                {
                    "domain": "example.com",
                    "app": "HTTP/S",
                    "protocol": "HTTP/S",
                    "visits": 3,
                    "last_seen": 1,
                }
            ],
        }


class FakeNetworkData:
    def network_status(self):
        return {
            "sqm": {
                "enabled": True,
                "download_kbit": 720000,
                "upload_kbit": 230000,
                "qdisc": "cake",
            },
            "banip": {
                "enabled": True,
                "active": True,
                "element_count": 100,
                "feeds": ["dshield", "feodo"],
            },
            "geoip": {"countries": [], "enabled": True},
            "speedtests": [],
        }

    def run_speedtest(self):
        return {
            "status": "OK",
            "download": 900.0,
            "upload": 300.0,
            "server": "test",
        }

    def set_geoip_countries(self, countries):
        return {"countries": countries, "enabled": True}

    def blocked_elements(self, search="", feed="", limit=100, offset=0):
        return {
            "items": [
                {"ip": "1.2.3.0/24", "feed": "dshield", "family": "ipv4"}
            ],
            "total": 1,
            "limit": limit,
            "offset": offset,
            "feeds": [{"name": "dshield", "count": 1}],
        }

    def allowlist_ip(self, ip):
        return {"ip": ip, "allowed": True, "changed": True}


class FakeNotifier:
    def test(self):
        return {
            "notification": {"id": "n1", "title": "test"},
            "channels": {"ntfy": "ok"},
        }


class ControlApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.app = FastAPI()
        self.db = ControlDatabase(Path(self.tempdir.name) / "control.sqlite")
        self.app.state.control_db = self.db
        self.app.state.settings = SimpleNamespace(api_token="", session_hours=24)
        self.app.state.router_client_factory = lambda router: FakeRouterClient()
        self.app.state.flow_db = FakeFlowDB()
        self.app.state.router_data = FakeRouterData()
        self.app.state.network_data = FakeNetworkData()
        self.app.state.notifier = FakeNotifier()
        self.app.include_router(api_router)
        self.app.dependency_overrides[require_auth] = lambda: None
        self.app.dependency_overrides[require_agent] = lambda: {
            "agent_id": "agent-1",
            "router_id": "router-1",
        }
        self.client = TestClient(self.app)

    def tearDown(self) -> None:
        self.db.close()
        self.tempdir.cleanup()

    def create_router(self) -> dict:
        response = self.client.post(
            "/api/v1/routers",
            json={
                "name": "betowrt",
                "address": "192.168.0.1",
                "username": "root",
                "password": "secret",
            },
        )
        self.assertEqual(response.status_code, 201)
        return response.json()

    # ------------------------------------------------------------- routers

    def test_router_crud_and_password_redaction(self) -> None:
        router = self.create_router()
        self.assertEqual(router["name"], "betowrt")
        self.assertNotIn("password", router)
        self.assertNotIn("username", router)
        self.assertTrue(router["has_credentials"])

        listed = self.client.get("/api/v1/routers").json()
        self.assertEqual(len(listed["items"]), 1)

        fetched = self.client.get(f"/api/v1/routers/{router['id']}")
        self.assertEqual(fetched.status_code, 200)
        self.assertEqual(fetched.json()["address"], "192.168.0.1")

        patched = self.client.patch(
            f"/api/v1/routers/{router['id']}", json={"status": "online"}
        )
        self.assertEqual(patched.json()["status"], "online")

        deleted = self.client.delete(f"/api/v1/routers/{router['id']}")
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(self.client.get(f"/api/v1/routers/{router['id']}").status_code, 404)

    def test_router_sync_populates_devices_and_interfaces(self) -> None:
        router = self.create_router()
        response = self.client.post(f"/api/v1/routers/{router['id']}/sync")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["devices"], 1)
        self.assertEqual(body["interfaces"], 1)
        self.assertEqual(body["router"]["status"], "online")
        self.assertEqual(body["router"]["model"], "x86/64")

        devices = self.client.get(
            "/api/v1/devices", params={"router_id": router["id"]}
        ).json()
        self.assertEqual(devices["total"], 1)
        self.assertEqual(devices["items"][0]["hostname"], "phone")

        interfaces = self.client.get(
            "/api/v1/interfaces", params={"router_id": router["id"]}
        ).json()
        self.assertEqual(len(interfaces["items"]), 1)
        self.assertEqual(interfaces["items"][0]["name"], "br-lan")

    def test_router_sync_normalizes_model_object(self) -> None:
        class DictModelClient(FakeRouterClient):
            def fetch_board(self):
                return {
                    "model": {
                        "id": "intel-corporation-crescentbay",
                        "name": "INTEL Corporation CRESCENTBAY",
                    },
                    "release": {"description": "OpenWrt 25.12.6"},
                }

        self.app.state.router_client_factory = lambda router: DictModelClient()
        router = self.create_router()
        body = self.client.post(f"/api/v1/routers/{router['id']}/sync").json()
        self.assertEqual(body["router"]["model"], "INTEL Corporation CRESCENTBAY")
        self.assertEqual(body["router"]["openwrt_version"], "OpenWrt 25.12.6")

    # ------------------------------------------------------------- devices

    def test_device_metadata_and_actions(self) -> None:
        router = self.create_router()
        self.client.post(f"/api/v1/routers/{router['id']}/sync")
        device = self.client.get(
            "/api/v1/devices", params={"router_id": router["id"]}
        ).json()["items"][0]
        device_id = device["id"]

        patched = self.client.patch(
            f"/api/v1/devices/{device_id}", json={"hostname": "Kai phone"}
        )
        self.assertEqual(patched.status_code, 200)
        self.assertEqual(patched.json()["hostname"], "Kai phone")

        blocked = self.client.post(f"/api/v1/devices/{device_id}/block")
        self.assertEqual(blocked.status_code, 200)
        self.assertTrue(blocked.json()["blocked"])

        unblocked = self.client.post(f"/api/v1/devices/{device_id}/unblock")
        self.assertFalse(unblocked.json()["blocked"])

        paused = self.client.post(
            f"/api/v1/devices/{device_id}/pause", json={"duration_minutes": 30}
        )
        self.assertTrue(paused.json()["paused"])
        self.assertGreater(paused.json()["pause_until"], 0)

        resumed = self.client.post(f"/api/v1/devices/{device_id}/resume")
        self.assertFalse(resumed.json()["paused"])

        calls = self.app.state.router_data.access_calls
        self.assertEqual(
            [called[1] for called in calls], [True, False, True, False]
        )

        traffic = self.client.get(f"/api/v1/devices/{device_id}/traffic")
        self.assertEqual(traffic.status_code, 200)
        self.assertEqual(traffic.json()["samples"], [])

    def test_device_details(self) -> None:
        router = self.create_router()
        self.client.post(f"/api/v1/routers/{router['id']}/sync")
        device = self.client.get(
            "/api/v1/devices", params={"router_id": router["id"]}
        ).json()["items"][0]
        response = self.client.get(
            f"/api/v1/devices/{device['id']}/details", params={"hours": 1}
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["hours"], 1)
        self.assertEqual(body["ranges"]["1h"]["download"], 1000)
        self.assertEqual(body["websites"][0]["domain"], "example.com")

    def test_device_display_name_survives_sync(self) -> None:
        router = self.create_router()
        self.client.post(f"/api/v1/routers/{router['id']}/sync")
        device = self.client.get(
            "/api/v1/devices", params={"router_id": router["id"]}
        ).json()["items"][0]

        renamed = self.client.patch(
            f"/api/v1/devices/{device['id']}",
            json={"display_name": "  Kitchen phone  "},
        )
        self.assertEqual(renamed.status_code, 200)
        self.assertEqual(renamed.json()["display_name"], "Kitchen phone")
        self.assertEqual(renamed.json()["hostname"], "phone")

        self.client.post(f"/api/v1/routers/{router['id']}/sync")
        fetched = self.client.get(f"/api/v1/devices/{device['id']}").json()
        self.assertEqual(fetched["display_name"], "Kitchen phone")
        self.assertEqual(fetched["hostname"], "phone")

        cleared = self.client.patch(
            f"/api/v1/devices/{device['id']}", json={"display_name": ""}
        )
        self.assertEqual(cleared.json()["display_name"], "")

    def test_network_status_speedtest_topology_and_notification(self) -> None:
        router = self.create_router()
        self.client.post(f"/api/v1/routers/{router['id']}/sync")

        status = self.client.get("/api/v1/network/status")
        self.assertEqual(status.status_code, 200)
        self.assertTrue(status.json()["sqm"]["enabled"])
        self.assertEqual(status.json()["banip"]["element_count"], 100)

        speedtest = self.client.post("/api/v1/network/speedtest")
        self.assertEqual(speedtest.status_code, 200)
        self.assertEqual(speedtest.json()["download"], 900.0)

        geoip = self.client.put(
            "/api/v1/network/geoip", json={"countries": ["VA"]}
        )
        self.assertEqual(geoip.status_code, 200)
        self.assertEqual(geoip.json()["countries"], ["va"])
        invalid = self.client.put(
            "/api/v1/network/geoip", json={"countries": ["USA"]}
        )
        self.assertEqual(invalid.status_code, 422)

        invalid_ip = self.client.get(
            "/api/v1/network/geoip/lookup", params={"ip": "not-an-ip"}
        )
        self.assertEqual(invalid_ip.status_code, 422)

        blocked = self.client.get("/api/v1/network/blocked")
        self.assertEqual(blocked.status_code, 200)
        self.assertEqual(blocked.json()["items"][0]["feed"], "dshield")

        allowed = self.client.post(
            "/api/v1/network/blocked/allow", json={"ip": "1.2.3.4"}
        )
        self.assertEqual(allowed.status_code, 200)
        self.assertTrue(allowed.json()["allowed"])
        invalid_allow = self.client.post(
            "/api/v1/network/blocked/allow", json={"ip": "nope"}
        )
        self.assertEqual(invalid_allow.status_code, 422)

        topology = self.client.get("/api/v1/network/topology")
        self.assertEqual(topology.status_code, 200)
        self.assertEqual(topology.json()["router"]["address"], "192.168.0.1")
        self.assertEqual(topology.json()["total_devices"], 1)

        notification = self.client.post("/api/v1/network/notifications/test")
        self.assertEqual(notification.status_code, 200)
        self.assertEqual(notification.json()["channels"]["ntfy"], "ok")

    # ------------------------------------------------------------- policies

    def test_policies_groups_parental_and_adblock(self) -> None:
        group = self.client.post(
            "/api/v1/groups", json={"name": "Children", "member_ids": []}
        )
        self.assertEqual(group.status_code, 201)
        group_id = group.json()["id"]

        policy = self.client.post(
            "/api/v1/policies",
            json={"name": "Bedtime", "scope": "group", "target_ids": [group_id]},
        )
        self.assertEqual(policy.status_code, 201)
        policy_id = policy.json()["id"]
        self.assertEqual(len(self.client.get("/api/v1/policies").json()["items"]), 1)

        updated = self.client.put(
            f"/api/v1/policies/{policy_id}", json={"enabled": False}
        )
        self.assertFalse(updated.json()["enabled"])

        profile = self.client.post(
            "/api/v1/parental/profiles",
            json={"name": "Kids", "member_ids": [], "daily_limit_minutes": 120},
        )
        self.assertEqual(profile.status_code, 201)
        self.assertEqual(profile.json()["daily_limit_minutes"], 120)

        status = self.client.get("/api/v1/adblock/status").json()
        self.assertFalse(status["enabled"])
        settings = self.client.put(
            "/api/v1/adblock/settings",
            json={"enabled": True, "blocklists": ["stevenblack"]},
        )
        self.assertTrue(settings.json()["enabled"])
        self.assertEqual(settings.json()["blocklists"], ["stevenblack"])

    def test_traffic_series(self) -> None:
        response = self.client.get(
            "/api/v1/traffic/series", params={"hours": 24, "bucket": 300}
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["items"], [{"timestamp": 1, "flows": 3, "devices": 2}]
        )

    # ------------------------------------------------------------- agent

    def test_agent_register_heartbeat_and_policies(self) -> None:
        router = self.create_router()
        registered = self.client.post(
            "/api/v1/agent/register",
            json={"router_id": router["id"], "name": "betowrt"},
        )
        self.assertEqual(registered.status_code, 201)
        body = registered.json()
        self.assertIn("token", body)
        self.assertIn("agent_id", body)

        heartbeat = self.client.post(
            "/api/v1/agent/heartbeat",
            json={"agent_id": body["agent_id"], "status": "online"},
        )
        self.assertEqual(heartbeat.status_code, 204)

        policies = self.client.get("/api/v1/agent/policies").json()
        self.assertEqual(policies["router_id"], "router-1")
        self.assertIn("policies", policies)
        self.assertIn("parental_profiles", policies)
        self.assertIn("adblock", policies)


if __name__ == "__main__":
    unittest.main()
