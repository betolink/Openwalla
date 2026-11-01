import unittest

from app.asn_filter import build_nft_ruleset


class ASNFilterTest(unittest.TestCase):
    def test_builds_per_device_ipv4_and_ipv6_rules(self) -> None:
        ruleset = build_nft_ruleset(
            [{"mac": "b0:d5:fb:c2:69:80", "asns": [32934]}],
            {
                32934: [
                    "31.13.24.0/21",
                    "31.13.24.0/22",
                    "2a03:2880::/32",
                ]
            },
        )
        self.assertIn("set openwalla_asn_32934_v4", ruleset)
        self.assertIn("set openwalla_asn_32934_v6", ruleset)
        self.assertIn("31.13.24.0/21", ruleset)
        self.assertNotIn("31.13.24.0/22", ruleset)
        self.assertIn(
            'ether saddr b0:d5:fb:c2:69:80 ip daddr '
            '@openwalla_asn_32934_v4 counter drop',
            ruleset,
        )
        self.assertIn(
            'ether saddr b0:d5:fb:c2:69:80 ip6 daddr '
            '@openwalla_asn_32934_v6 counter drop',
            ruleset,
        )

    def test_empty_ruleset_removes_the_include(self) -> None:
        self.assertEqual(build_nft_ruleset([], {32934: ["31.13.24.0/21"]}), "")

    def test_merges_rules_for_the_same_device(self) -> None:
        ruleset = build_nft_ruleset(
            [
                {"mac": "aa:bb:cc:dd:ee:01", "asns": [32934]},
                {"mac": "aa:bb:cc:dd:ee:01", "asns": [15169]},
            ],
            {
                32934: ["31.13.24.0/21"],
                15169: ["142.250.0.0/15"],
            },
        )
        self.assertIn("@openwalla_asn_32934_v4", ruleset)
        self.assertIn("@openwalla_asn_15169_v4", ruleset)


if __name__ == "__main__":
    unittest.main()
