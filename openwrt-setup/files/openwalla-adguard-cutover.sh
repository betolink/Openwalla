#!/bin/sh

# One-shot AdGuard DNS cutover with automatic rollback on failed resolution.
set -eu

BACKUP="/etc/openwalla-adguard-backup"
mkdir -p "$BACKUP"
if [ -f "$BACKUP/dhcp" ]; then
	echo "A previous cutover backup exists at $BACKUP; run openwalla-adguard-rollback first" >&2
	exit 1
fi

cp -p /etc/config/dhcp "$BACKUP/dhcp"
cp -p /etc/config/firewall "$BACKUP/firewall"
cp -p /etc/config/banip "$BACKUP/banip"
cp -p /etc/config/adblock "$BACKUP/adblock"
cp -p /etc/adguardhome/adguardhome.yaml "$BACKUP/adguardhome.yaml"

rollback() {
	/etc/init.d/adguardhome stop >/dev/null 2>&1 || true
	cp -p "$BACKUP/dhcp" /etc/config/dhcp
	cp -p "$BACKUP/firewall" /etc/config/firewall
	cp -p "$BACKUP/banip" /etc/config/banip
	cp -p "$BACKUP/adblock" /etc/config/adblock
	cp -p "$BACKUP/adguardhome.yaml" /etc/adguardhome/adguardhome.yaml
	uci commit dhcp
	uci commit firewall
	uci commit banip
	uci commit adblock
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	/etc/init.d/adblock restart >/dev/null 2>&1 || true
	echo "AdGuard cutover rolled back; dnsmasq/adblock restored" >&2
}
trap 'rollback; exit 1' HUP INT TERM

# Firewall rules refer to a zone *name*, not the network name. This install
# calls the LAN zone "trusted", while stock OpenWrt calls it "lan"; resolve it.
lan_zone="lan"
for zone_section in $(uci -q show firewall | sed -n 's/^firewall\.\([^.=]*\)=zone$/\1/p'); do
	zone_networks="$(uci -q get "firewall.$zone_section.network" 2>/dev/null || true)"
	case " $zone_networks " in
	*" lan "*)
		lan_zone="$(uci -q get "firewall.$zone_section.name" 2>/dev/null || echo lan)"
		break
		;;
	esac
done

# Force LAN clients to use the router for DNS.
if ! uci -q get firewall.openwalla_dns_redirect >/dev/null 2>&1; then
	section="$(uci add firewall redirect)"
	uci set "firewall.$section.name=openwalla_dns_redirect"
	uci set "firewall.$section.proto=tcp udp"
	uci set "firewall.$section.src_dport=53"
	uci set "firewall.$section.dest_ip=192.168.0.1"
	uci set "firewall.$section.dest_port=53"
	uci set "firewall.$section.target=DNAT"
fi
section="$(uci -q show firewall | sed -n 's/^firewall\.\([^.=]*\)\.name=.openwalla_dns_redirect.$/\1/p' | head -n 1)"
[ -n "$section" ] || section="$(uci add firewall redirect)"
uci set "firewall.$section.name=openwalla_dns_redirect"
uci set "firewall.$section.src=$lan_zone"
uci set "firewall.$section.dest=$lan_zone"
uci set "firewall.$section.proto=tcp udp"
uci set "firewall.$section.src_dport=53"
uci set "firewall.$section.dest_ip=192.168.0.1"
uci set "firewall.$section.dest_port=53"
uci set "firewall.$section.target=DNAT"

# Block DNS-over-TLS as a basic bypass path.
if ! uci -q get firewall.openwalla_block_dot >/dev/null 2>&1; then
	section="$(uci add firewall rule)"
	uci set "firewall.$section.name=openwalla_block_dot"
	uci set "firewall.$section.proto=tcp udp"
	uci set "firewall.$section.dest_port=853"
	uci set "firewall.$section.target=REJECT"
fi
section="$(uci -q show firewall | sed -n 's/^firewall\.\([^.=]*\)\.name=.openwalla_block_dot.$/\1/p' | head -n 1)"
[ -n "$section" ] || section="$(uci add firewall rule)"
uci set "firewall.$section.name=openwalla_block_dot"
uci set "firewall.$section.src=$lan_zone"
uci set "firewall.$section.proto=tcp udp"
uci set "firewall.$section.dest_port=853"
uci set "firewall.$section.target=REJECT"

# Include the public DoH resolver feed in banIP when available.
feeds="$(uci -q get banip.global.ban_feed 2>/dev/null || true)"
case " $feeds " in
*" doh "*) ;;
*) uci set "banip.global.ban_feed=$feeds doh" ;;
esac
uci commit banip
/etc/init.d/banip restart >/dev/null 2>&1 || true

uci set adblock.global.adb_enabled=0
uci set dhcp.@dnsmasq[0].port=0
uci commit adblock
uci commit dhcp
uci commit firewall
sed -i 's/^  port: 5353$/  port: 53/' /etc/adguardhome/adguardhome.yaml

/etc/init.d/dnsmasq restart
/etc/init.d/adguardhome restart
sleep 2

ok=0
for attempt in 1 2 3 4 5; do
	if nslookup example.com 127.0.0.1 >/dev/null 2>&1; then
		ok=1
		break
	fi
	sleep 1
done
if [ "$ok" != 1 ]; then
	rollback
	exit 1
fi
trap - HUP INT TERM
echo "AdGuard cutover complete; DNS now served by AdGuard on port 53"
