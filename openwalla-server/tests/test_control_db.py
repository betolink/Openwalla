import tempfile
import unittest
from pathlib import Path

from app.control_db import ControlDatabase


class ControlDatabaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.db = ControlDatabase(Path(self.tempdir.name) / "control.sqlite")

    def tearDown(self) -> None:
        self.db.close()
        self.tempdir.cleanup()

    # ------------------------------------------------------------- routers

    def test_router_crud(self) -> None:
        router = self.db.create_router(
            {
                "name": "betowrt",
                "address": "192.168.0.1",
                "username": "root",
                "password": "secret",
            }
        )
        self.assertEqual(router["name"], "betowrt")
        self.assertEqual(router["address"], "192.168.0.1")
        self.assertEqual(router["status"], "unknown")
        self.assertEqual(len(self.db.list_routers()), 1)

        updated = self.db.update_router(
            router["id"], {"status": "online", "model": "x86/64"}
        )
        self.assertEqual(updated["status"], "online")
        self.assertEqual(updated["model"], "x86/64")

        self.assertTrue(self.db.delete_router(router["id"]))
        self.assertIsNone(self.db.get_router(router["id"]))
        self.assertEqual(self.db.list_routers(), [])

    # ------------------------------------------------------------- devices

    def test_device_upsert_preserves_state(self) -> None:
        router = self.db.create_router({"name": "betowrt", "address": "192.168.0.1"})

        self.db.upsert_devices(
            router["id"],
            [
                {
                    "mac": "AA:BB:CC:DD:EE:01",
                    "ipv4": "192.168.0.50",
                    "ipv6": ["fe80::1"],
                    "hostname": "phone",
                    "online": True,
                }
            ],
        )
        devices, total = self.db.list_devices(router_id=router["id"])
        self.assertEqual(total, 1)
        device = devices[0]
        self.assertEqual(device["mac"], "aa:bb:cc:dd:ee:01")
        self.assertEqual(device["ipv4"], "192.168.0.50")
        self.assertEqual(device["ipv6"], ["fe80::1"])
        first_seen = device["first_seen"]

        self.db.set_device_state(device["id"], blocked=True)
        self.db.upsert_devices(
            router["id"],
            [
                {
                    "mac": "AA:BB:CC:DD:EE:01",
                    "ipv4": "192.168.0.51",
                    "hostname": "phone-renamed",
                    "online": False,
                }
            ],
        )
        refreshed = self.db.get_device(device["id"])
        self.assertTrue(refreshed["blocked"])
        self.assertFalse(refreshed["online"])
        self.assertEqual(refreshed["ipv4"], "192.168.0.51")
        self.assertEqual(refreshed["first_seen"], first_seen)

    def test_device_filters_and_search(self) -> None:
        router = self.db.create_router({"name": "betowrt", "address": "192.168.0.1"})
        self.db.upsert_devices(
            router["id"],
            [
                {"mac": "aa:00:00:00:00:01", "hostname": "laptop", "online": True},
                {"mac": "aa:00:00:00:00:02", "hostname": "phone", "online": False},
            ],
        )
        online, total = self.db.list_devices(router_id=router["id"], online=True)
        self.assertEqual(total, 1)
        self.assertEqual(online[0]["hostname"], "laptop")

        found, total = self.db.list_devices(router_id=router["id"], query="phon")
        self.assertEqual(total, 1)
        self.assertEqual(found[0]["hostname"], "phone")

    # ------------------------------------------------------------- policies

    def test_groups_policies_and_parental(self) -> None:
        group = self.db.create_group(
            {"name": "Children", "member_ids": ["device-1"]}
        )
        self.assertEqual(group["member_ids"], ["device-1"])

        policy = self.db.create_policy(
            {
                "name": "Bedtime",
                "scope": "group",
                "target_ids": [group["id"]],
                "rules": [{"type": "block", "value": "internet"}],
                "schedule": {"days": ["mon"], "start": "21:00", "end": "07:00"},
                "enabled": True,
            }
        )
        self.assertTrue(policy["enabled"])
        self.assertEqual(policy["target_ids"], [group["id"]])
        self.assertEqual(policy["schedule"]["start"], "21:00")

        updated = self.db.update_policy(policy["id"], {"enabled": False})
        self.assertFalse(updated["enabled"])

        profile = self.db.create_parental(
            {
                "name": "Kids",
                "member_ids": ["device-1"],
                "daily_limit_minutes": 180,
                "content_filter": "safe",
            }
        )
        self.assertEqual(profile["daily_limit_minutes"], 180)
        updated_profile = self.db.update_parental(
            profile["id"], {"paused": True, "pause_until": "2026-11-01T07:00:00Z"}
        )
        self.assertTrue(updated_profile["paused"])
        self.assertEqual(updated_profile["pause_until"], "2026-11-01T07:00:00Z")

        self.assertTrue(self.db.delete_parental(profile["id"]))
        self.assertTrue(self.db.delete_policy(policy["id"]))
        self.assertTrue(self.db.delete_group(group["id"]))

    # ------------------------------------------------------------- adblock

    def test_adblock_defaults_and_update(self) -> None:
        status = self.db.get_adblock()
        self.assertFalse(status["enabled"])
        self.assertEqual(status["blocklists"], [])

        updated = self.db.update_adblock(
            {"enabled": True, "blocklists": ["stevenblack"], "update_interval_hours": 12}
        )
        self.assertTrue(updated["enabled"])
        self.assertEqual(updated["blocklists"], ["stevenblack"])
        self.assertEqual(updated["update_interval_hours"], 12)

    # ------------------------------------------------------------- events

    def test_events_and_notifications(self) -> None:
        event = self.db.create_event(
            {"type": "device_blocked", "severity": "warning", "message": "blocked"}
        )
        events, total = self.db.list_events()
        self.assertEqual(total, 1)
        self.assertEqual(events[0]["id"], event["id"])
        self.assertEqual(events[0]["severity"], "warning")

        notification = self.db.create_notification(
            {"type": "info", "title": "Hello", "body": "World"}
        )
        self.assertEqual(len(self.db.list_notifications(unread=True)), 1)
        self.assertTrue(self.db.mark_notification_read(notification["id"]))
        self.assertEqual(self.db.list_notifications(unread=True), [])

    # ------------------------------------------------------------- agents

    def test_agent_token_lookup(self) -> None:
        router = self.db.create_router({"name": "betowrt", "address": "192.168.0.1"})
        agent = self.db.create_agent(router["id"], "hashed-token")
        self.assertEqual(agent["router_id"], router["id"])
        found = self.db.find_agent_by_token("hashed-token")
        self.assertIsNotNone(found)
        self.assertEqual(found["agent_id"], agent["agent_id"])
        self.assertIsNone(self.db.find_agent_by_token("wrong"))


if __name__ == "__main__":
    unittest.main()
