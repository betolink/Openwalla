#!/bin/sh

# Measure the WAN with speedtest-go and enable SQM/CAKE at ~90% of the
# measured rates. This is intentionally a manual opt-in: it briefly saturates
# the link and should not run during calls or gaming.

set -u

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

SPEEDTEST_BIN="${OPENWALLA_SPEEDTEST_BIN:-/usr/bin/speedtest-go}"
TMP_OUT="/tmp/openwalla-sqm-autotune.$$"
trap 'rm -f "$TMP_OUT"' EXIT INT TERM

if ! command -v "$SPEEDTEST_BIN" >/dev/null 2>&1; then
	echo "speedtest-go is not installed" >&2
	exit 1
fi

"$SPEEDTEST_BIN" >"$TMP_OUT" 2>&1 || true
download="$(sed -n 's/.*Download: \([0-9][0-9.]*\).*/\1/p' "$TMP_OUT" | head -n 1)"
upload="$(sed -n 's/.*Upload: \([0-9][0-9.]*\).*/\1/p' "$TMP_OUT" | head -n 1)"

case "$download" in ''|*[!0-9.]*) echo "unable to parse download speed" >&2; exit 1 ;; esac
case "$upload" in ''|*[!0-9.]*) echo "unable to parse upload speed" >&2; exit 1 ;; esac

download_kbit="$(awk -v n="$download" 'BEGIN { printf "%d", n * 1000 * 0.9 }')"
upload_kbit="$(awk -v n="$upload" 'BEGIN { printf "%d", n * 1000 * 0.9 }')"
wan="$(uci -q get network.wan.device 2>/dev/null || echo eth1)"

uci set "sqm.$wan=queue"
uci set "sqm.$wan.interface=$wan"
uci set "sqm.$wan.enabled=1"
uci set "sqm.$wan.download=$download_kbit"
uci set "sqm.$wan.upload=$upload_kbit"
uci set "sqm.$wan.qdisc=cake"
uci set "sqm.$wan.script=piece_of_cake.qos"
uci set "sqm.$wan.linklayer=ethernet"
uci set "sqm.$wan.overhead=0"
uci set "sqm.$wan.ingress_ecn=ECN"
uci set "sqm.$wan.egress_ecn=ECN"
uci commit sqm
/etc/init.d/sqm restart

echo "SQM enabled on $wan: ${download_kbit} kbit down / ${upload_kbit} kbit up"
