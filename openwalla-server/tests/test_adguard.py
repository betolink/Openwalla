import unittest

from app.adguard import AdGuardClient


class AdGuardClientTest(unittest.TestCase):
    def test_cache_clear_sends_json_body(self) -> None:
        class RecordingClient(AdGuardClient):
            def __init__(self) -> None:
                super().__init__("http://adguard.invalid")
                self.calls = []

            def _request(self, method, path, payload=None):
                self.calls.append((method, path, payload))
                return None

        client = RecordingClient()
        client.clear_cache()
        self.assertEqual(
            client.calls,
            [("POST", "/control/cache_clear", {})],
        )


if __name__ == "__main__":
    unittest.main()
