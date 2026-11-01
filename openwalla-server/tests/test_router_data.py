import json
import unittest

from app.router_data import RouterData


class RouterDataParsingTest(unittest.TestCase):
    def test_parse_speedtest_lines_newest_first(self) -> None:
        items = RouterData._parse_speedtests(
            [
                "2026-10-31T07:52:00Z|ERROR|N/A|N/A||speedtest binary not found",
                "2026-10-31T07:53:39Z|OK|687.31|289.50|Ames|speedtest completed",
            ]
        )
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["download"], 687.31)
        self.assertEqual(items[0]["upload"], 289.5)
        self.assertIsNone(items[1]["download"])
        self.assertEqual(items[0]["server"], "Ames")

    def test_parse_uci_values(self) -> None:
        values = RouterData._parse_uci(
            [
                "sqm.eth1.enabled='1'",
                "sqm.eth1.download='720000'",
                "sqm.eth1.interface='eth1'",
                "",
            ]
        )
        self.assertEqual(values["sqm.eth1.enabled"], "1")
        self.assertEqual(values["sqm.eth1.download"], "720000")
        self.assertEqual(values["sqm.eth1.interface"], "eth1")

    def test_vnstat_usage_prefers_wan_and_normalizes_direction(self) -> None:
        payload = {
            "interfaces": [
                {
                    "name": "eth1",
                    "updated": {"timestamp": 123},
                    "month": [{"timestamp": 2, "rx": 300, "tx": 200}],
                    "day": [{"timestamp": 2, "rx": 30, "tx": 20}],
                    "total": {"rx": 3000, "tx": 2000},
                }
            ]
        }
        usage = RouterData._vnstat_usage(json.dumps(payload), "eth1")
        self.assertEqual(usage["source"], "vnstat-wan")
        self.assertEqual(usage["month"]["download"], 300)
        self.assertEqual(usage["month"]["upload"], 200)
        self.assertEqual(usage["month"]["total"], 500)
        self.assertEqual(usage["all_time"]["total"], 5000)

    def test_vnstat_usage_reverses_directions_for_br_lan_fallback(self) -> None:
        payload = {
            "interfaces": [
                {
                    "name": "br-lan",
                    "month": [{"timestamp": 2, "rx": 300, "tx": 200}],
                    "day": [],
                    "total": {"rx": 0, "tx": 0},
                }
            ]
        }
        usage = RouterData._vnstat_usage(json.dumps(payload), "eth1")
        self.assertEqual(usage["source"], "vnstat-lan-fallback")
        self.assertEqual(usage["month"]["download"], 200)
        self.assertEqual(usage["month"]["upload"], 300)
        self.assertIn("WAN interface", usage["warning"])


if __name__ == "__main__":
    unittest.main()
