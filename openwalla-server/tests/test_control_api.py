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


class ControlApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.app = FastAPI()
        self.db = ControlDatabase(Path(self.tempdir.name) / "control.sqlite")
        self.app.state.control_db = self.db
        self.app.state.settings = SimpleNamespace(api_token="", session_hours=24)
        self.app.state.router_client_factory = lambda router: FakeRouterClient()
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

        resumed = self.client.post(f"/api/v1/devices/{device_id}/resume")
        self.assertFalse(resumed.json()["paused"])

        traffic = self.client.get(f"/api/v1/devices/{device_id}/traffic")
        self.assertEqual(traffic.status_code, 200)
        self.assertEqual(traffic.json()["samples"], [])

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
