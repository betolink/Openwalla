import unittest

from app.adguard_sync import _desired_clients, _matches


class AdGuardSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.devices = [
            {
                "id": "d1",
                "mac": "aa:bb:cc:dd:ee:01",
                "ipv4": "192.168.0.50",
            }
        ]

    def test_merges_profiles_to_most_restrictive_client(self) -> None:
        profiles = [
            {
                "id": "p1",
                "enabled": True,
                "paused": False,
                "content_filter": "safe",
                "member_ids": ["d1"],
            },
            {
                "id": "p2",
                "enabled": True,
                "paused": False,
                "content_filter": "adult",
                "member_ids": ["d1"],
            },
        ]
        desired = _desired_clients(profiles, self.devices)
        client = desired["aa:bb:cc:dd:ee:01"]
        self.assertEqual(client["name"], "openwalla:aa:bb:cc:dd:ee:01")
        self.assertEqual(client["ids"], ["192.168.0.50", "aa:bb:cc:dd:ee:01"])
        self.assertTrue(client["safe_search"])
        self.assertTrue(client["parental"])

    def test_disabled_or_none_profiles_do_not_create_clients(self) -> None:
        profiles = [
            {
                "id": "p1",
                "enabled": False,
                "paused": False,
                "content_filter": "adult",
                "member_ids": ["d1"],
            },
            {
                "id": "p2",
                "enabled": True,
                "paused": False,
                "content_filter": "none",
                "member_ids": ["d1"],
            },
        ]
        self.assertEqual(_desired_clients(profiles, self.devices), {})

    def test_matches_ignores_nothing_it_should_not(self) -> None:
        desired = {
            "name": "openwalla:aa:bb:cc:dd:ee:01",
            "ids": ["192.168.0.50", "aa:bb:cc:dd:ee:01"],
            "safe_search": True,
            "parental": True,
        }
        current = {
            "name": desired["name"],
            "ids": list(reversed(desired["ids"])),
            "safe_search": {"enabled": True},
            "parental_enabled": True,
            "filtering_enabled": True,
            "use_global_settings": False,
        }
        self.assertTrue(_matches(current, desired))
        current["ids"] = ["192.168.0.51", "aa:bb:cc:dd:ee:01"]
        self.assertFalse(_matches(current, desired))


if __name__ == "__main__":
    unittest.main()
