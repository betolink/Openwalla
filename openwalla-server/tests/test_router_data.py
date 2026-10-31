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


if __name__ == "__main__":
    unittest.main()
