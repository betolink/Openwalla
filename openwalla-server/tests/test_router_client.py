import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from app.router_client import (
    RouterAuthError,
    RouterClient,
    normalize_devices,
    normalize_interfaces,
)


class NormalizeTest(unittest.TestCase):
    def test_normalize_devices_merges_leases_and_hints(self) -> None:
        leases = [
            {
                "macaddr": "AA:BB:CC:DD:EE:01",
                "ipaddr": "192.168.0.50",
                "hostname": "phone",
            }
        ]
        hints = {
            "aa:bb:cc:dd:ee:01": {
                "name": "phone",
                "ipaddrs": ["192.168.0.50", "fe80::1"],
            },
            "aa:bb:cc:dd:ee:02": {
                "name": "laptop",
                "ipaddrs": ["192.168.0.60"],
            },
        }
        devices = normalize_devices(leases, hints)
        self.assertEqual(len(devices), 2)
        by_mac = {device["mac"]: device for device in devices}
        phone = by_mac["aa:bb:cc:dd:ee:01"]
        self.assertEqual(phone["ipv4"], "192.168.0.50")
        self.assertEqual(phone["ipv6"], ["fe80::1"])
        self.assertTrue(phone["online"])
        laptop = by_mac["aa:bb:cc:dd:ee:02"]
        self.assertEqual(laptop["ipv4"], "192.168.0.60")
        self.assertEqual(laptop["hostname"], "laptop")

    def test_normalize_interfaces(self) -> None:
        devices = {
            "br-lan": {
                "name": "br-lan",
                "type": "bridge",
                "up": True,
                "macaddr": "00:11:22:33:44:55",
                "ipaddrs": ["192.168.0.1"],
                "stats": {"rx_bytes": 10, "tx_bytes": 20, "rx_errors": 1},
            }
        }
        interfaces = normalize_interfaces(devices)
        self.assertEqual(len(interfaces), 1)
        interface = interfaces[0]
        self.assertEqual(interface["name"], "br-lan")
        self.assertTrue(interface["up"])
        self.assertEqual(interface["rx_bytes"], 10)
        self.assertEqual(interface["errors"], 1)


class _Handler(BaseHTTPRequestHandler):
    ubus_payload = None

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if self.path == "/cgi-bin/luci/":
            self.send_response(200)
            self.send_header("Set-Cookie", "sysauth=test-token; Path=/")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if self.path == "/cgi-bin/luci/admin/ubus":
            type(self).ubus_payload = json.loads(body)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(
                json.dumps(
                    {"jsonrpc": "2.0", "id": 1, "result": [0, {"ok": True}]}
                ).encode()
            )
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args) -> None:
        return


class RouterClientTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_address[1]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def client(self) -> RouterClient:
        return RouterClient(
            "127.0.0.1", "root", "secret", port=self.port, scheme="http"
        )

    def test_login_and_call(self) -> None:
        client = self.client()
        self.assertEqual(client.login(), "test-token")
        result = client.call("luci-rpc", "getHostHints", {})
        self.assertEqual(result, {"ok": True})
        payload = _Handler.ubus_payload
        self.assertEqual(payload["params"][0], "test-token")
        self.assertEqual(payload["params"][1], "luci-rpc")
        self.assertEqual(payload["params"][2], "getHostHints")

    def test_login_without_cookie_raises(self) -> None:
        class NoCookieHandler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), NoCookieHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = RouterClient(
                "127.0.0.1",
                "root",
                "wrong",
                port=server.server_address[1],
                scheme="http",
            )
            with self.assertRaises(RouterAuthError):
                client.login()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
